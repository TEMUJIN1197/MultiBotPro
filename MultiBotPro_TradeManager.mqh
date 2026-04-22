#ifndef __MULTIBOTPRO_TRADEMANAGER_MQH__
#define __MULTIBOTPRO_TRADEMANAGER_MQH__
//+------------------------------------------------------------------+
//|                                      MultiBotPro_TradeManager.mqh|
//|                         Decoupled trailing, grid, and zone logic |
//+------------------------------------------------------------------+
#property strict

// Stub for now. Will migrate 'ManageAllPositionsOnTick', 'CheckGridOnTick', etc. here.
class CTradeManager
{
public:
   CTradeManager() {}
   
   void ManagePositions(int symbolIndex)
   {
      ManageAllPositionsOnTick(symbolIndex);
      if(SymbolData[symbolIndex].HasPendingTrail) ApplyPendingTrail(symbolIndex);
      CheckStackTradesOnTick(symbolIndex);

      bool gridAllowed = true;
      if(UseORReversal && !SymbolData[symbolIndex].GridInTrailing) gridAllowed = false;
      
      if(RiskMode == RISK_MODE_GRID && gridAllowed && (SymbolData[symbolIndex].GridLevels > 0 || SymbolData[symbolIndex].GridPhase1Active))
      {
         CheckGridOnTick(symbolIndex);
         if(!SymbolData[symbolIndex].GridTargetReached && SymbolData[symbolIndex].GridPhase1Active)
            CheckGridTargetOnTick(symbolIndex);
      }

      if(RiskMode == RISK_MODE_ZONE_RECOVERY) CheckZoneRecovery(symbolIndex);
      ManageRisk(symbolIndex);
   }
};

CTradeManager G_TradeManager;

#endif // __MULTIBOTPRO_TRADEMANAGER_MQH__
