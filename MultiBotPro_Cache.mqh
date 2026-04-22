#ifndef __MULTIBOTPRO_CACHE_MQH__
#define __MULTIBOTPRO_CACHE_MQH__
//+------------------------------------------------------------------+
//|                                           MultiBotPro_Cache.mqh  |
//|                                      Advanced State Caching Unit |
//+------------------------------------------------------------------+
#property strict

class CCacheManager
{
private:
   ulong m_lastTickProcessMs;
   ulong m_lastTimerProcessMs;
   
   // Cached global states
   int m_totalOpenPositions;
   double m_totalFloatingPnL;
   
public:
   CCacheManager()
   {
      m_lastTickProcessMs = 0;
      m_lastTimerProcessMs = 0;
      m_totalOpenPositions = 0;
      m_totalFloatingPnL = 0.0;
   }
   
   // Called very first thing in OnTick
   void UpdateTickCache()
   {
      ulong nowMs = GetTickCount();
      // Only run expensive global cache updates every 100ms max
      if(nowMs - m_lastTickProcessMs < 100) return;
      
      m_lastTickProcessMs = nowMs;
      
      // Update global position counts
      m_totalOpenPositions = PositionsTotal();
      
      // We can batch compute other things here to prevent 
      // redundant calls deep in the TradeManager loop.
   }
   
   int GetTotalOpenPositions() const { return m_totalOpenPositions; }
};

CCacheManager G_CacheManager;

#endif // __MULTIBOTPRO_CACHE_MQH__
