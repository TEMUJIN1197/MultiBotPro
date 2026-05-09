#ifndef __MULTIBOTPRO_GRIDZONE_STATE_MQH__
#define __MULTIBOTPRO_GRIDZONE_STATE_MQH__
//+------------------------------------------------------------------+
//|                                  MultiBotPro_GridZone_State.mqh  |
//|                         Basket state management and synchronization |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://discord.com/channels/929723953415589918/929723953415589920"

struct SBridgeChannelLock
{
   long     requestId;
   datetime expiresAt;
};

int BasketRuntimeIdForIndex(int symbolIndex)
{
   if(InpEnableMultiBaskets && symbolIndex >= 0 && symbolIndex < ArraySize(SymbolData) && SymbolData[symbolIndex].BasketId > 0)
      return SymbolData[symbolIndex].BasketId;
   return 0;
}

int BasketIdFromCommentOrDefault(string comment, int defaultBasketId)
{
   int parsed = ExtractBasketId(comment);
   if(parsed >= 0)
      return parsed;
   return defaultBasketId;
}

void MirrorBasketStateToSymbol(int symbolIndex, SBasketState* basketState)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData) || basketState == NULL)
      return;

   SymbolData[symbolIndex].GridPhase1Active = basketState.GridPhase1Active;
   SymbolData[symbolIndex].GridPhase2Active = basketState.GridPhase2Active;
   SymbolData[symbolIndex].GridTargetReached = basketState.GridTargetReached;
   SymbolData[symbolIndex].GridTargetProfit = basketState.GridTargetProfit;
   SymbolData[symbolIndex].GridTPHit = basketState.GridTPHit;
   SymbolData[symbolIndex].GridTPHitPrice = basketState.GridTPHitPrice;
   SymbolData[symbolIndex].CurrentRecoveryPortion = basketState.CurrentRecoveryPortion;
   SymbolData[symbolIndex].ZoneActive = basketState.ZoneActive;
   SymbolData[symbolIndex].ZoneTopPrice = basketState.ZoneTopPrice;
   SymbolData[symbolIndex].ZoneBottomPrice = basketState.ZoneBottomPrice;
   SymbolData[symbolIndex].ZoneNextLot = basketState.ZoneNextLot;
   SymbolData[symbolIndex].ZoneSeqCount = basketState.ZoneSeqCount;
   SymbolData[symbolIndex].ZoneResolved = basketState.ZoneResolved;
}

void MirrorSymbolToBasketState(int symbolIndex, SBasketState* basketState)
{
   if(symbolIndex < 0 || symbolIndex >= ArraySize(SymbolData) || basketState == NULL)
      return;

   basketState.GridPhase1Active = SymbolData[symbolIndex].GridPhase1Active;
   basketState.GridPhase2Active = SymbolData[symbolIndex].GridPhase2Active;
   basketState.GridTargetReached = SymbolData[symbolIndex].GridTargetReached;
   basketState.GridTargetProfit = SymbolData[symbolIndex].GridTargetProfit;
   basketState.GridTPHit = SymbolData[symbolIndex].GridTPHit;
   basketState.GridTPHitPrice = SymbolData[symbolIndex].GridTPHitPrice;
   basketState.CurrentRecoveryPortion = SymbolData[symbolIndex].CurrentRecoveryPortion;
   basketState.ZoneActive = SymbolData[symbolIndex].ZoneActive;
   basketState.ZoneTopPrice = SymbolData[symbolIndex].ZoneTopPrice;
   basketState.ZoneBottomPrice = SymbolData[symbolIndex].ZoneBottomPrice;
   basketState.ZoneNextLot = SymbolData[symbolIndex].ZoneNextLot;
   basketState.ZoneSeqCount = SymbolData[symbolIndex].ZoneSeqCount;
   basketState.ZoneResolved = SymbolData[symbolIndex].ZoneResolved;
}

#endif // __MULTIBOTPRO_GRIDZONE_STATE_MQH__
