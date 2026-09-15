#ifndef __MULTIBOTPRO_CUSTOMSYMBOLPUBLISHER_MQH__
#define __MULTIBOTPRO_CUSTOMSYMBOLPUBLISHER_MQH__
//+------------------------------------------------------------------+
//|                               MultiBotPro_CustomSymbolPublisher.mqh |
//|        Base class for custom chart engines to unify tick publishing|
//+------------------------------------------------------------------+

class CCustomSymbolPublisher
{
protected:
   #define MBP_CUSTOM_PUBLISHER_MAX_CACHED_RATES 2048

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
      if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("[CustomPublisher] WARNING: Custom tick mirroring disabled for ", m_customSymbol,
            " after repeated ", stage, " failures (Err: ", errorCode,
            "). Rates-only mode will continue until the next retry window.");
   }

   void PublishLiveStateTick(datetime syntheticTime, long tickTimeMsc, double sourceBid, double sourceAsk, double syntheticLast, bool allowMirrorDegrade)
   {
      if(!m_tickMirroringEnabled)
         return;

      if(m_tickMirrorFailureCount >= 5 && GetTickCount() < m_tickMirrorRetryAfterMs)
         return;

      if(tickTimeMsc <= 0)
         tickTimeMsc = (syntheticTime > 0) ? ((long)syntheticTime * 1000) : ((long)TimeCurrent() * 1000);
      if(tickTimeMsc <= 0)
         tickTimeMsc = (long)TimeCurrent() * 1000;
      if(m_lastLiveTickMsc > 0 && tickTimeMsc < m_lastLiveTickMsc)
         tickTimeMsc = m_lastLiveTickMsc + 1;

      MqlTick liveTick[1];
      ZeroMemory(liveTick[0]);
      liveTick[0].time = syntheticTime;
      if(liveTick[0].time <= 0)
         liveTick[0].time = (datetime)(tickTimeMsc / 1000);
      liveTick[0].time_msc = tickTimeMsc;
      liveTick[0].bid = sourceBid;
      liveTick[0].ask = sourceAsk;
      liveTick[0].last = syntheticLast;
      liveTick[0].volume = 1;
      liveTick[0].volume_real = 1.0;
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
               m_tickMirrorRetryAfterMs = GetTickCount() + 30000;
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
      if(count <= 0)
         return true;

      ResetLastError();
      
      // If we have cached rates from a previous failure, we MUST flush them first
      if(m_flushPending)
      {
         int cacheSize = ArraySize(m_rateCache);
         if(cacheSize > 0)
         {
            if(!CustomRatesUpdate(m_customSymbol, m_rateCache, cacheSize))
            {
               int keepExisting = MathMin(cacheSize, MBP_CUSTOM_PUBLISHER_MAX_CACHED_RATES);
               int keepNew = MathMin(count, MBP_CUSTOM_PUBLISHER_MAX_CACHED_RATES - keepExisting);
               if(keepExisting < cacheSize)
               {
                  for(int i = 0; i < keepExisting; i++)
                     m_rateCache[i] = m_rateCache[cacheSize - keepExisting + i];
               }
               ArrayResize(m_rateCache, keepExisting + keepNew, 512);
               for(int i = 0; i < keepNew; i++)
                  m_rateCache[keepExisting + i] = rates[count - keepNew + i];
               return false;
            }
            // Success! Clear cache and continue.
            ArrayFree(m_rateCache);
            m_flushPending = false;
            if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("[CustomPublisher] Successfully recovered ", cacheSize, " pending rates for ", m_customSymbol);
         }
      }

      bool success = CustomRatesUpdate(m_customSymbol, rates, count);
      if(!success)
      {
         int err = _LastError;
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL)) Print("[CustomPublisher] WARNING: Rate flush failed for ", m_customSymbol, 
               " | Bars: ", count, " (Err: ", err, "). Caching for retry.");
         m_flushPending = true;
         
         // Cache the failed rates
         int cacheSize = ArraySize(m_rateCache);
         int keepExisting = MathMin(cacheSize, MBP_CUSTOM_PUBLISHER_MAX_CACHED_RATES);
         int keepNew = MathMin(count, MBP_CUSTOM_PUBLISHER_MAX_CACHED_RATES - keepExisting);
         if(keepExisting < cacheSize)
         {
            for(int i = 0; i < keepExisting; i++)
               m_rateCache[i] = m_rateCache[cacheSize - keepExisting + i];
         }
         ArrayResize(m_rateCache, keepExisting + keepNew, 512);
         for(int i = 0; i < keepNew; i++)
            m_rateCache[keepExisting + i] = rates[count - keepNew + i];
         
         return false;
      }
      
      return true;
   }
};

#endif

