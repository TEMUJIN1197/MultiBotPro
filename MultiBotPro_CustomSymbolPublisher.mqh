#ifndef __MULTIBOTPRO_CUSTOMSYMBOLPUBLISHER_MQH__
#define __MULTIBOTPRO_CUSTOMSYMBOLPUBLISHER_MQH__
//+------------------------------------------------------------------+
//|                               MultiBotPro_CustomSymbolPublisher.mqh |
//|        Base class for custom chart engines to unify tick publishing|
//+------------------------------------------------------------------+

class CCustomSymbolPublisher
{
protected:
   string   m_customSymbol;
   long     m_lastLiveTickMsc;
   bool     m_tickMirroringEnabled;
   bool     m_tickMirrorWarningLogged;
   int      m_tickMirrorFailureCount;
   ulong    m_tickMirrorRetryAfterMs;
   bool     m_flushPending;
   ulong    m_lastFlushTryMs;
   MqlRates m_rateCache[];

public:
   CCustomSymbolPublisher() : m_lastLiveTickMsc(0),
                              m_tickMirroringEnabled(true),
                              m_tickMirrorWarningLogged(false),
                              m_tickMirrorFailureCount(0),
                              m_tickMirrorRetryAfterMs(0),
                              m_flushPending(false),
                              m_lastFlushTryMs(0)
   {
      ArrayFree(m_rateCache);
   }

   virtual ~CCustomSymbolPublisher() {}

protected:
   void ResetPublisherState()
   {
      m_lastLiveTickMsc = 0;
      m_tickMirroringEnabled = true;
      m_tickMirrorWarningLogged = false;
      m_tickMirrorFailureCount = 0;
      m_tickMirrorRetryAfterMs = 0;
      m_flushPending = false;
      m_lastFlushTryMs = 0;
      ArrayFree(m_rateCache);
   }

   void DisableTickMirroring(string stage, int errorCode)
   {
      m_tickMirroringEnabled = false;
      if(m_tickMirrorWarningLogged)
         return;

      m_tickMirrorWarningLogged = true;
      Print("[CustomPublisher] WARNING: Custom tick mirroring disabled for ", m_customSymbol,
            " after repeated ", stage, " failures (Err: ", errorCode,
            "). Rates-only mode will continue until the next retry window.");
   }

   void PublishLiveStateTick(datetime syntheticTime, long tickTimeMsc, double sourceBid, double sourceAsk, double syntheticLast, bool allowMirrorDegrade)
   {
      if(!m_tickMirroringEnabled || !allowMirrorDegrade)
         return;

      if(m_tickMirrorFailureCount >= 5 && GetTickCount64() < m_tickMirrorRetryAfterMs)
         return;

      if(tickTimeMsc <= 0)
         return;
      if(m_lastLiveTickMsc > 0 && tickTimeMsc < m_lastLiveTickMsc)
         return;

      MqlTick liveTick[1];
      liveTick[0].time = syntheticTime;
      liveTick[0].time_msc = tickTimeMsc;
      liveTick[0].bid = sourceBid;
      liveTick[0].ask = sourceAsk;
      liveTick[0].last = syntheticLast;
      liveTick[0].volume = 1;
      liveTick[0].flags = TICK_FLAG_BID | TICK_FLAG_ASK | TICK_FLAG_LAST | TICK_FLAG_VOLUME;

      ResetLastError();
      if(!CustomTicksAdd(m_customSymbol, liveTick, 1))
      {
         int err = _LastError;
         if(err == 5304 || err == 4001 || err == 4401)
         {
            m_tickMirrorFailureCount++;
            if(m_tickMirrorFailureCount >= 5)
            {
               m_tickMirrorRetryAfterMs = GetTickCount64() + 30000;
               DisableTickMirroring("CustomTicksAdd(live)", err);
            }
         }
      }
      else
      {
         m_tickMirrorFailureCount = 0;
         m_tickMirrorWarningLogged = false;
         m_tickMirroringEnabled = true;
         m_lastLiveTickMsc = tickTimeMsc;
      }
   }

   bool SafeCustomRatesUpdate(const MqlRates &rates[], int count)
   {
      ResetLastError();
      
      // If we have cached rates from a previous failure, we MUST flush them first
      if(m_flushPending)
      {
         int cacheSize = ArraySize(m_rateCache);
         if(cacheSize > 0)
         {
            if(!CustomRatesUpdate(m_customSymbol, m_rateCache, cacheSize))
            {
               // Still failing, append the NEW rates to the cache and abort
               int newSize = cacheSize + count;
               ArrayResize(m_rateCache, newSize, 512);
               for(int i = 0; i < count; i++) m_rateCache[cacheSize + i] = rates[i];
               return false;
            }
            // Success! Clear cache and continue.
            ArrayFree(m_rateCache);
            m_flushPending = false;
            Print("[CustomPublisher] Successfully recovered ", cacheSize, " pending rates for ", m_customSymbol);
         }
      }

      bool success = CustomRatesUpdate(m_customSymbol, rates, count);
      if(!success)
      {
         int err = _LastError;
         Print("[CustomPublisher] WARNING: Rate flush failed for ", m_customSymbol, 
               " | Bars: ", count, " (Err: ", err, "). Caching for retry.");
         m_flushPending = true;
         
         // Cache the failed rates
         int cacheSize = ArraySize(m_rateCache);
         ArrayResize(m_rateCache, cacheSize + count, 512);
         for(int i = 0; i < count; i++) m_rateCache[cacheSize + i] = rates[i];
         
         return false;
      }
      
      return true;
   }
};

#endif
