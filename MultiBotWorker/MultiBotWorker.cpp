#include "MultiBotWorker.h"

#include <algorithm>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace
{
struct FeedEvent
{
    double price = 0.0;
    long long timeMsc = 0;
};

struct RenkoBar
{
    long long timeSec = 0;
    double open = 0.0;
    double high = 0.0;
    double low = 0.0;
    double close = 0.0;
    long long volume = 0;
    long long eventTimeMsc = 0;
};

struct Session
{
    std::wstring sessionKey;
    std::wstring customSymbol;
    int family = 0;
    double pointSize = 0.01;
    int digits = 2;
    double blockSize = 0.0;
    double openOffsetPct = 0.0;
    double reversalShadowPct = 1.0;
    double reversalPct = 2.0;
    bool applyOffsetToFirstBar = false;
    int offsetDigits = 0;
    bool resetOpenOnNewDay = false;

    double anchorPrice = 0.0;
    double lastBarOpen = 0.0;
    double boxHigh = 0.0;
    double boxLow = 0.0;
    bool trendUp = true;
    long long lastCommittedTime = 0;
    long long logicalStartTime = 0;
    double liveOpen = 0.0;
    double liveClose = 0.0;
    double liveTargetClose = 0.0;
    bool liveActive = false;
    bool liveBullish = true;
    bool liveReversal = false;
    double lastClosePrice = 0.0;
    double lastLivePrice = 0.0;
    long long previewEndTime = 0;
    long long lastTickMsc = 0;
    int lastBrickDay = -1;

    bool opened = false;
    bool seeded = false;
    bool stop = false;
    std::deque<FeedEvent> queue;
    std::vector<RenkoBar> history;
    std::deque<RenkoBar> unreadClosed;
    std::mutex mutex;
    std::condition_variable cv;
    std::thread worker;
};

struct Profile
{
    double continuationOpenPct = 0.0;
    double reversalOpenPct = 1.0;
    double reversalDistancePct = 2.0;
};

std::mutex g_sessionsMutex;
std::unordered_map<std::wstring, std::shared_ptr<Session>> g_sessions;

std::wstring SafeString(const wchar_t* value)
{
    return value ? std::wstring(value) : std::wstring();
}

std::wstring MakeKey(const wchar_t* sessionKey, const wchar_t* customSymbol)
{
    return SafeString(sessionKey) + L"|" + SafeString(customSymbol);
}

double RoundPrice(const Session& session, const double price)
{
    const double tick = (session.pointSize > 0.0) ? session.pointSize : 0.00001;
    const double scaled = std::round(price / tick) * tick;
    const double factor = std::pow(10.0, std::max(0, session.digits));
    return std::round(scaled * factor) / factor;
}

double RoundDistance(const Session& session, const double distance)
{
    const double tick = (session.pointSize > 0.0) ? session.pointSize : 0.00001;
    const double scaled = std::round(distance / tick) * tick;
    const double factor = std::pow(10.0, std::max(0, session.digits));
    return std::max(std::round(scaled * factor) / factor, tick);
}

Profile ResolveProfile(const Session& session)
{
    Profile profile;
    profile.continuationOpenPct = 0.0;
    profile.reversalOpenPct = 1.0;
    profile.reversalDistancePct = 2.0;
    return profile;
}

double ContinuationOpen(const Session& session, const bool bullish, const double anchor, const double blockSize)
{
    return RoundPrice(session, anchor);
}

double ReversalDistance(const Session& session, const double blockSize)
{
    return RoundDistance(session, 2.0 * blockSize);
}

double ReversalOpen(const Session& session, const bool bullish, const double anchor, const double blockSize)
{
    const double priorOpen = (session.lastBarOpen > 0.0)
        ? session.lastBarOpen
        : (bullish ? (anchor + blockSize) : (anchor - blockSize));
    return RoundPrice(session, priorOpen);
}

double ReversalClose(const Session& session, const bool bullish, const double anchor, const double blockSize)
{
    const double revOpen = ReversalOpen(session, bullish, anchor, blockSize);
    return RoundPrice(session, revOpen + (bullish ? blockSize : -blockSize));
}

long long TickSeconds(const long long timeMsc)
{
    return (timeMsc > 0) ? (timeMsc / 1000LL) : 0LL;
}

void ClearLive(Session& session)
{
    session.logicalStartTime = 0;
    session.liveOpen = 0.0;
    session.liveClose = 0.0;
    session.liveTargetClose = 0.0;
    session.liveActive = false;
    session.liveBullish = session.trendUp;
    session.liveReversal = false;
    session.previewEndTime = 0;
}

void SeedFromFirstPrice(Session& session, const double price, const long long tickSec)
{
    session.anchorPrice = RoundPrice(session, price);
    session.lastClosePrice = session.anchorPrice;
    session.lastBarOpen = session.anchorPrice;
    session.boxHigh = session.anchorPrice;
    session.boxLow = session.anchorPrice;
    session.logicalStartTime = tickSec;
    session.liveOpen = session.anchorPrice;
    session.lastLivePrice = session.anchorPrice;
    session.liveActive = true;
    session.liveBullish = true;
    session.liveReversal = false;
    session.liveTargetClose = 0.0;
    session.liveClose = session.anchorPrice;
    session.previewEndTime = tickSec;
    session.seeded = true;
}

void PushClosedBar(Session& session, long long startTime, const double open, const double close, const long long eventTimeMsc)
{
    if(session.lastCommittedTime > 0)
        startTime = session.lastCommittedTime + 1;

    RenkoBar bar;
    bar.timeSec = startTime;
    bar.open = RoundPrice(session, open);
    bar.close = RoundPrice(session, close);
    bar.high = std::max(bar.open, bar.close);
    bar.low = std::min(bar.open, bar.close);
    bar.volume = 1;
    bar.eventTimeMsc = eventTimeMsc;

    if(!session.history.empty())
    {
        const auto& prev = session.history.back();
        if(std::abs(bar.high - prev.high) < session.pointSize * 0.5 &&
           std::abs(bar.low - prev.low) < session.pointSize * 0.5)
        {
            return; // Discard side-by-side artifact bar
        }
    }

    session.history.push_back(bar);
    session.unreadClosed.push_back(bar);
    session.lastCommittedTime = bar.timeSec;
    session.lastBarOpen = bar.open;
    session.lastClosePrice = bar.close;
    session.lastLivePrice = bar.close;
}

void RefreshLiveCandidate(Session& session, const double price, const long long tickSec)
{
    if(session.logicalStartTime <= 0)
        session.logicalStartTime = tickSec;

    const double point = (session.pointSize > 0.0) ? session.pointSize : 0.00001;
    const double blockSize = std::max(RoundDistance(session, session.blockSize), point);
    const bool bullishCandidate = (price > (session.anchorPrice + point / 2.0))
                                  ? true
                                  : ((price < (session.anchorPrice - point / 2.0)) ? false : session.trendUp);
    const bool useReversalCandidate = (bullishCandidate != session.trendUp);

    const double candidateOpen = RoundPrice(session, session.anchorPrice);
    const double candidateDistance = useReversalCandidate ? ReversalDistance(session, blockSize) : blockSize;
    const double candidateTarget = RoundPrice(session, session.anchorPrice + (bullishCandidate ? candidateDistance : -candidateDistance));

    const double closeMin = std::min(candidateOpen, candidateTarget);
    const double closeMax = std::max(candidateOpen, candidateTarget);
    double candidateClose = price;
    if(candidateClose < closeMin)
        candidateClose = closeMin;
    if(candidateClose > closeMax)
        candidateClose = closeMax;

    const bool candidateChanged = !session.liveActive ||
                                  (session.liveReversal != useReversalCandidate) ||
                                  (session.liveBullish != bullishCandidate) ||
                                  (std::fabs(session.liveOpen - candidateOpen) > point / 2.0) ||
                                  (std::fabs(session.liveTargetClose - candidateTarget) > point / 2.0);

    if(candidateChanged)
    {
        session.logicalStartTime = tickSec;
        session.boxHigh = std::max(session.anchorPrice, price);
        session.boxLow = std::min(session.anchorPrice, price);
    }
    else
    {
        session.boxHigh = (session.boxHigh == 0.0) ? price : std::max(session.boxHigh, price);
        session.boxLow = (session.boxLow == 0.0) ? price : std::min(session.boxLow, price);
    }

    session.previewEndTime = tickSec;
    session.liveActive = true;
    session.liveBullish = bullishCandidate;
    session.liveReversal = useReversalCandidate;
    session.liveOpen = RoundPrice(session, candidateOpen);
    session.liveTargetClose = RoundPrice(session, candidateTarget);
    session.liveClose = RoundPrice(session, candidateClose);
    session.lastLivePrice = session.liveClose;
}

void ProcessTick(Session& session, const double rawPrice, const long long timeMsc)
{
    if(rawPrice <= 0.0)
        return;

    const long long tickSec = TickSeconds(timeMsc);
    const double price = RoundPrice(session, rawPrice);
    const double point = (session.pointSize > 0.0) ? session.pointSize : 0.00001;
    const double blockSize = std::max(RoundDistance(session, session.blockSize), point);
    session.lastTickMsc = std::max(session.lastTickMsc, timeMsc);

    if(session.anchorPrice == 0.0)
    {
        SeedFromFirstPrice(session, price, tickSec);
        return;
    }

    session.boxHigh = (session.boxHigh == 0.0) ? price : std::max(session.boxHigh, price);
    session.boxLow = (session.boxLow == 0.0) ? price : std::min(session.boxLow, price);
    if(session.logicalStartTime <= 0)
        session.logicalStartTime = tickSec;
    session.previewEndTime = tickSec;

    bool created = false;
    int loops = 0;
    const double reversalDistance = ReversalDistance(session, blockSize);

    while(++loops < 1000)
    {
        bool action = false;
        const double priorOpen = (session.lastBarOpen > 0.0)
            ? session.lastBarOpen
            : (session.trendUp ? (session.anchorPrice - blockSize) : (session.anchorPrice + blockSize));

        if(session.trendUp)
        {
            const double upTarget = RoundPrice(session, session.anchorPrice + blockSize);
            const double reversalDownTarget = RoundPrice(session, priorOpen - blockSize);

            if(price >= upTarget - point / 2.0)
            {
                PushClosedBar(session, session.logicalStartTime > 0 ? session.logicalStartTime : tickSec,
                              session.anchorPrice, upTarget, timeMsc);
                session.lastBarOpen = session.anchorPrice;
                session.anchorPrice = upTarget;
                action = true;
            }
            else if(price <= reversalDownTarget + point / 2.0)
            {
                PushClosedBar(session, session.logicalStartTime > 0 ? session.logicalStartTime : tickSec,
                              priorOpen, reversalDownTarget, timeMsc);
                session.lastBarOpen = priorOpen;
                session.anchorPrice = reversalDownTarget;
                session.trendUp = false;
                action = true;
            }
        }
        else
        {
            const double downTarget = RoundPrice(session, session.anchorPrice - blockSize);
            const double reversalUpTarget = RoundPrice(session, priorOpen + blockSize);

            if(price <= downTarget + point / 2.0)
            {
                PushClosedBar(session, session.logicalStartTime > 0 ? session.logicalStartTime : tickSec,
                              session.anchorPrice, downTarget, timeMsc);
                session.lastBarOpen = session.anchorPrice;
                session.anchorPrice = downTarget;
                action = true;
            }
            else if(price >= reversalUpTarget - point / 2.0)
            {
                PushClosedBar(session, session.logicalStartTime > 0 ? session.logicalStartTime : tickSec,
                              priorOpen, reversalUpTarget, timeMsc);
                session.lastBarOpen = priorOpen;
                session.anchorPrice = reversalUpTarget;
                session.trendUp = true;
                action = true;
            }
        }

        if(!action)
            break;

        created = true;
        session.boxHigh = session.anchorPrice;
        session.boxLow = session.anchorPrice;
        session.logicalStartTime = tickSec;
        session.previewEndTime = tickSec;
        session.liveOpen = session.anchorPrice;
        session.liveClose = session.anchorPrice;
        session.liveActive = true;
        session.liveBullish = session.trendUp;
        session.liveReversal = false;
        session.liveTargetClose = 0.0;
        session.lastLivePrice = session.anchorPrice;
    }

    RefreshLiveCandidate(session, price, tickSec);
}

void WorkerLoop(const std::shared_ptr<Session>& session)
{
    std::unique_lock<std::mutex> lock(session->mutex);
    while(!session->stop)
    {
        session->cv.wait(lock, [&]() { return session->stop || !session->queue.empty(); });
        if(session->stop)
            break;

        std::deque<FeedEvent> local;
        local.swap(session->queue);
        for(const FeedEvent& feed : local)
        {
            ProcessTick(*session, feed.price, feed.timeMsc);
        }
    }
}

std::shared_ptr<Session> FindSession(const wchar_t* sessionKey, const wchar_t* customSymbol)
{
    std::lock_guard<std::mutex> guard(g_sessionsMutex);
    auto it = g_sessions.find(MakeKey(sessionKey, customSymbol));
    return (it != g_sessions.end()) ? it->second : nullptr;
}

std::shared_ptr<Session> EnsureSession(const wchar_t* sessionKey, const wchar_t* customSymbol)
{
    const std::wstring key = MakeKey(sessionKey, customSymbol);
    std::lock_guard<std::mutex> guard(g_sessionsMutex);
    auto it = g_sessions.find(key);
    if(it != g_sessions.end())
        return it->second;

    auto session = std::make_shared<Session>();
    session->sessionKey = SafeString(sessionKey);
    session->customSymbol = SafeString(customSymbol);
    session->opened = true;
    session->worker = std::thread(WorkerLoop, session);
    g_sessions.emplace(key, session);
    return session;
}

void StopSession(const std::shared_ptr<Session>& session)
{
    if(!session)
        return;
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        session->stop = true;
    }
    session->cv.notify_all();
    if(session->worker.joinable())
        session->worker.join();
}
}

extern "C" {

MULTIBOTWORKER_API int __stdcall TestConnection(int value) { return value * 2; }

MULTIBOTWORKER_API bool __stdcall ProcessRenkoTicks(const double* pTicks, int tickCount, double boxSize, double* pOutBoxesKeys, int* pOutCount, int maxBoxes)
{
    if(!pTicks || !pOutBoxesKeys || !pOutCount || tickCount <= 0 || maxBoxes <= 0 || boxSize <= 0.0)
        return false;
    int outCount = 0;
    double anchor = pTicks[0];
    for(int i = 1; i < tickCount && outCount < maxBoxes; ++i)
    {
        if(std::fabs(pTicks[i] - anchor) >= boxSize)
        {
            anchor = pTicks[i];
            pOutBoxesKeys[outCount++] = anchor;
        }
    }
    *pOutCount = outCount;
    return true;
}

MULTIBOTWORKER_API double __stdcall CalculateGridMath(double startLevel, double multiplier, int maxLevels)
{
    double result = 0.0;
    for(int i = 0; i < maxLevels; ++i)
        result += startLevel * std::pow(multiplier, i);
    return result;
}

MULTIBOTWORKER_API int __stdcall MBP_BoxBuildPayloadW(const wchar_t* filePath, const double* values, int valueCount)
{
    if(!filePath || !values || valueCount < 0)
        return 0;
    FILE* file = _wfopen(filePath, L"wb");
    if(!file)
        return 0;
    const size_t written = fwrite(values, sizeof(double), static_cast<size_t>(valueCount), file);
    fclose(file);
    return (written == static_cast<size_t>(valueCount)) ? 1 : 0;
}

MULTIBOTWORKER_API int __stdcall MBP_EnsureWorkersW(const wchar_t*, const wchar_t*) { return 1; }
MULTIBOTWORKER_API int __stdcall MBP_FileExistsW(const wchar_t* path)
{
    if(!path || !path[0])
        return 0;
    FILE* file = _wfopen(path, L"rb");
    if(!file)
        return 0;
    fclose(file);
    return 1;
}
MULTIBOTWORKER_API int __stdcall MBP_IsWorkerProcessRunningW(const wchar_t*, const wchar_t*, const wchar_t*) { return 1; }
MULTIBOTWORKER_API int __stdcall MBP_QueryRenkoBackendW(const wchar_t*, const wchar_t*) { return 2; }
MULTIBOTWORKER_API int __stdcall MBP_QueryWorkerStatusW(const wchar_t*, const wchar_t*, const wchar_t*, int) { return 1; }

MULTIBOTWORKER_API int __stdcall MBP_StopWorkersW(const wchar_t*, const wchar_t*)
{
    std::vector<std::shared_ptr<Session>> sessions;
    {
        std::lock_guard<std::mutex> guard(g_sessionsMutex);
        for(auto& item : g_sessions)
            sessions.push_back(item.second);
        g_sessions.clear();
    }
    for(const auto& session : sessions)
        StopSession(session);
    return 1;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoOpenSessionW(const wchar_t* sessionKey, const wchar_t* customSymbol, int renkoFamily, double pointSize, int digits)
{
    auto session = EnsureSession(sessionKey, customSymbol);
    if(!session)
        return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    session->family = renkoFamily;
    session->pointSize = pointSize;
    session->digits = digits;
    session->opened = true;
    return 1;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoResetSessionW(const wchar_t* sessionKey, const wchar_t* customSymbol)
{
    auto session = FindSession(sessionKey, customSymbol);
    if(!session)
        return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    session->anchorPrice = 0.0;
    session->boxHigh = 0.0;
    session->boxLow = 0.0;
    session->trendUp = true;
    session->lastCommittedTime = 0;
    session->logicalStartTime = 0;
    session->liveOpen = 0.0;
    session->liveClose = 0.0;
    session->liveTargetClose = 0.0;
    session->liveActive = false;
    session->liveBullish = true;
    session->liveReversal = false;
    session->lastClosePrice = 0.0;
    session->lastLivePrice = 0.0;
    session->previewEndTime = 0;
    session->lastTickMsc = 0;
    session->queue.clear();
    session->history.clear();
    session->unreadClosed.clear();
    session->seeded = false;
    return 1;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoCloseSessionW(const wchar_t* sessionKey, const wchar_t* customSymbol)
{
    const std::wstring key = MakeKey(sessionKey, customSymbol);
    std::shared_ptr<Session> session;
    {
        std::lock_guard<std::mutex> guard(g_sessionsMutex);
        auto it = g_sessions.find(key);
        if(it == g_sessions.end())
            return 0;
        session = it->second;
        g_sessions.erase(it);
    }
    StopSession(session);
    return 1;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoSeedSessionW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                       double anchorPrice, int trendUp, double blockSize,
                                                       double openOffsetPct, double reversalShadowPct, double reversalPct,
                                                       int applyOffsetToFirstBar, int offsetDigits, int resetOpenOnNewDay)
{
    auto session = EnsureSession(sessionKey, customSymbol);
    if(!session)
        return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    session->blockSize = blockSize;
    session->openOffsetPct = openOffsetPct;
    session->reversalShadowPct = reversalShadowPct;
    session->reversalPct = reversalPct;
    session->applyOffsetToFirstBar = (applyOffsetToFirstBar != 0);
    session->offsetDigits = offsetDigits;
    session->resetOpenOnNewDay = (resetOpenOnNewDay != 0);
    session->anchorPrice = RoundPrice(*session, anchorPrice);
    session->boxHigh = session->anchorPrice;
    session->boxLow = session->anchorPrice;
    session->trendUp = (trendUp != 0);
    session->lastClosePrice = session->anchorPrice;
    session->lastLivePrice = session->anchorPrice;
    session->liveOpen = session->anchorPrice;
    session->liveClose = session->anchorPrice;
    session->liveTargetClose = 0.0;
    session->liveActive = true;
    session->liveBullish = session->trendUp;
    session->liveReversal = false;
    session->logicalStartTime = 0;
    session->previewEndTime = 0;
    session->seeded = true;
    return 1;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoFeedRatesW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                     const double* prices, const long long* timesMsc, int rateCount)
{
    return MBP_RenkoFeedTicksW(sessionKey, customSymbol, prices, timesMsc, rateCount);
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoFeedM1RatesW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                       const double* opens, const double* highs, const double* lows,
                                                       const double* closes, const long long* timesMsc, int rateCount)
{
    std::shared_ptr<Session> session = FindSession(sessionKey, customSymbol);
    if(!session || !opens || !highs || !lows || !closes || !timesMsc || rateCount <= 0)
        return 0;

    int queued = 0;
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        for(int i = 0; i < rateCount; ++i)
        {
            const double open = opens[i];
            const double high = highs[i];
            const double low = lows[i];
            const double close = closes[i];
            const long long baseTime = timesMsc[i];
            if(open <= 0.0 || high <= 0.0 || low <= 0.0 || close <= 0.0 || baseTime <= 0)
                continue;

            session->queue.push_back({open, baseTime});
            if(close >= open)
            {
                session->queue.push_back({low, baseTime + 20000LL});
                session->queue.push_back({high, baseTime + 40000LL});
            }
            else
            {
                session->queue.push_back({high, baseTime + 20000LL});
                session->queue.push_back({low, baseTime + 40000LL});
            }
            session->queue.push_back({close, baseTime + 59000LL});
            queued += 4;
        }
    }
    if(queued > 0)
        session->cv.notify_one();
    return queued;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoFeedTicksW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                     const double* prices, const long long* timesMsc, int tickCount)
{
    auto session = FindSession(sessionKey, customSymbol);
    if(!session || !prices || !timesMsc || tickCount <= 0)
        return 0;
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        for(int i = 0; i < tickCount; ++i)
            session->queue.push_back(FeedEvent{prices[i], timesMsc[i]});
    }
    session->cv.notify_one();
    return tickCount;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoReadSnapshotW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                        double* outDoubles, long long* outLongs)
{
    auto session = FindSession(sessionKey, customSymbol);
    if(!session || !outDoubles || !outLongs)
        return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    outDoubles[0] = session->anchorPrice;
    outDoubles[1] = session->boxHigh;
    outDoubles[2] = session->boxLow;
    outDoubles[3] = session->liveOpen;
    outDoubles[4] = session->liveClose;
    outDoubles[5] = session->liveTargetClose;
    outDoubles[6] = session->lastClosePrice;
    outDoubles[7] = session->lastLivePrice;
    outDoubles[8] = session->blockSize;

    outLongs[0] = session->opened ? 1 : 0;
    outLongs[1] = session->seeded ? 1 : 0;
    outLongs[2] = session->trendUp ? 1 : 0;
    outLongs[3] = session->liveActive ? 1 : 0;
    outLongs[4] = session->liveBullish ? 1 : 0;
    outLongs[5] = session->liveReversal ? 1 : 0;
    outLongs[6] = session->logicalStartTime;
    outLongs[7] = session->previewEndTime;
    outLongs[8] = session->lastTickMsc;
    outLongs[9] = static_cast<long long>(session->unreadClosed.size());
    return 1;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoGetHistoryInfoW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                          long long* outLongs)
{
    auto session = FindSession(sessionKey, customSymbol);
    if(!session || !outLongs)
        return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    outLongs[0] = static_cast<long long>(session->history.size());
    outLongs[1] = static_cast<long long>(session->unreadClosed.size());
    outLongs[2] = session->lastCommittedTime;
    outLongs[3] = session->lastTickMsc;
    return 1;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoReadHistoryBarsW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                           double* outDoubles, long long* outLongs, int maxBars)
{
    auto session = FindSession(sessionKey, customSymbol);
    if(!session || !outDoubles || !outLongs || maxBars <= 0)
        return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    const int count = std::min(maxBars, static_cast<int>(session->history.size()));
    const int start = static_cast<int>(session->history.size()) - count;
    for(int i = 0; i < count; ++i)
    {
        const RenkoBar& bar = session->history[start + i];
        outDoubles[i * 4 + 0] = bar.open;
        outDoubles[i * 4 + 1] = bar.high;
        outDoubles[i * 4 + 2] = bar.low;
        outDoubles[i * 4 + 3] = bar.close;
        outLongs[i * 3 + 0] = bar.timeSec;
        outLongs[i * 3 + 1] = bar.volume;
        outLongs[i * 3 + 2] = bar.eventTimeMsc;
    }
    return count;
}

MULTIBOTWORKER_API int __stdcall MBP_RenkoReadClosedBarsW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                          double* outDoubles, long long* outLongs, int maxBars)
{
    auto session = FindSession(sessionKey, customSymbol);
    if(!session || !outDoubles || !outLongs || maxBars <= 0)
        return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    const int count = std::min(maxBars, static_cast<int>(session->unreadClosed.size()));
    for(int i = 0; i < count; ++i)
    {
        const RenkoBar& bar = session->unreadClosed[i];
        outDoubles[i * 4 + 0] = bar.open;
        outDoubles[i * 4 + 1] = bar.high;
        outDoubles[i * 4 + 2] = bar.low;
        outDoubles[i * 4 + 3] = bar.close;
        outLongs[i * 3 + 0] = bar.timeSec;
        outLongs[i * 3 + 1] = bar.volume;
        outLongs[i * 3 + 2] = bar.eventTimeMsc;
    }
    session->unreadClosed.erase(session->unreadClosed.begin(), session->unreadClosed.begin() + count);
    return count;
}

}
