#ifndef __MULTIBOTPRO_ICLOCK_MQH__
#define __MULTIBOTPRO_ICLOCK_MQH__
//+------------------------------------------------------------------+
//|                                        MultiBotPro_IClock.mqh    |
//|  Step 7: Clock abstraction for coordinator unit tests             |
//+------------------------------------------------------------------+
class IClock
{
public:
   virtual ulong NowMs() const { return 0; }
   virtual datetime NowGmt() const { return 0; }
};

class CRealClock : public IClock
{
public:
   virtual ulong NowMs() const override { return GetTickCount64(); }
   virtual datetime NowGmt() const override { return TimeGMT(); }
};

class CMockClock : public IClock
{
public:
   ulong    m_nowMs;
   datetime m_nowGmt;
   CMockClock(): m_nowMs(0), m_nowGmt(0) {}
   CMockClock(ulong ms, datetime gmt): m_nowMs(ms), m_nowGmt(gmt) {}
   void Set(ulong ms, datetime gmt) { m_nowMs = ms; m_nowGmt = gmt; }
   void Advance(ulong deltaMs) { m_nowMs += deltaMs; if(deltaMs >= 1000) m_nowGmt += (datetime)(deltaMs/1000); }
   virtual ulong NowMs() const override { return m_nowMs; }
   virtual datetime NowGmt() const override { return m_nowGmt; }
};
#endif