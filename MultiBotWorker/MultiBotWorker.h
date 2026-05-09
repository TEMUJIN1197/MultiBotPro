#pragma once

#ifdef MULTIBOTWORKER_EXPORTS
#define MULTIBOTWORKER_API __declspec(dllexport)
#else
#define MULTIBOTWORKER_API __declspec(dllimport)
#endif

extern "C" {
    // Legacy exports kept for compatibility with older MQL call sites.
    MULTIBOTWORKER_API int __stdcall TestConnection(int value);
    MULTIBOTWORKER_API bool __stdcall ProcessRenkoTicks(const double* pTicks, int tickCount, double boxSize, double* pOutBoxesKeys, int* pOutCount, int maxBoxes);
    MULTIBOTWORKER_API double __stdcall CalculateGridMath(double startLevel, double multiplier, int maxLevels);

    // Worker-runtime helpers.
    MULTIBOTWORKER_API int __stdcall MBP_BoxBuildPayloadW(const wchar_t* filePath, const double* values, int valueCount);
    MULTIBOTWORKER_API int __stdcall MBP_EnsureWorkersW(const wchar_t* runtimeRoot, const wchar_t* requestedBackend);
    MULTIBOTWORKER_API int __stdcall MBP_FileExistsW(const wchar_t* path);
    MULTIBOTWORKER_API int __stdcall MBP_IsWorkerProcessRunningW(const wchar_t* workerRole, const wchar_t* sessionKey, const wchar_t* reserved);
    MULTIBOTWORKER_API int __stdcall MBP_QueryRenkoBackendW(const wchar_t* runtimeRoot, const wchar_t* requestedBackend);
    MULTIBOTWORKER_API int __stdcall MBP_QueryWorkerStatusW(const wchar_t* runtimeRoot, const wchar_t* workerRole, const wchar_t* sessionKey, int timeoutMs);
    MULTIBOTWORKER_API int __stdcall MBP_StopWorkersW(const wchar_t* runtimeRoot, const wchar_t* workerRole);

    // Session-backed Renko worker surface.
    MULTIBOTWORKER_API int __stdcall MBP_RenkoOpenSessionW(const wchar_t* sessionKey, const wchar_t* customSymbol, int renkoFamily, double pointSize, int digits);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoResetSessionW(const wchar_t* sessionKey, const wchar_t* customSymbol);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoCloseSessionW(const wchar_t* sessionKey, const wchar_t* customSymbol);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoSeedSessionW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                           double anchorPrice, int trendUp, double blockSize,
                                                           double openOffsetPct, double reversalShadowPct, double reversalPct,
                                                           int applyOffsetToFirstBar, int offsetDigits, int resetOpenOnNewDay);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoFeedRatesW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                         const double* prices, const long long* timesMsc, int rateCount);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoFeedM1RatesW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                           const double* opens, const double* highs, const double* lows,
                                                           const double* closes, const long long* timesMsc, int rateCount);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoFeedTicksW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                         const double* prices, const long long* timesMsc, int tickCount);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoReadSnapshotW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                            double* outDoubles, long long* outLongs);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoGetHistoryInfoW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                              long long* outLongs);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoReadHistoryBarsW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                               double* outDoubles, long long* outLongs, int maxBars);
    MULTIBOTWORKER_API int __stdcall MBP_RenkoReadClosedBarsW(const wchar_t* sessionKey, const wchar_t* customSymbol,
                                                              double* outDoubles, long long* outLongs, int maxBars);
}
