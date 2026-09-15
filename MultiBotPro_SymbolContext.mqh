#ifndef __MULTIBOTPRO_SYMBOLCONTEXT_MQH__
#define __MULTIBOTPRO_SYMBOLCONTEXT_MQH__

//+------------------------------------------------------------------+
//|                                   MultiBotPro_SymbolContext.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//+------------------------------------------------------------------+

// --- SYMBOL MAPPING HELPERS ---

string NormalizeSymbolLookupValue(string value)
{
   string normalized = value;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   StringToUpper(normalized);
   return normalized;
}

bool IsCustomTerminalSymbol(string symbol)
{
   if(symbol == "")
      return false;

   long isCustom = 0;
   if(!SymbolInfoInteger(symbol, SYMBOL_CUSTOM, isCustom))
      return false;

   return (isCustom != 0);
}

int GetRequestedTradingSymbolMatchRank(string requestedUpper, string candidateUpper)
{
   if(requestedUpper == "" || candidateUpper == "")
      return -1;

   if(candidateUpper == requestedUpper)
      return 0;

   if(StringFind(candidateUpper, requestedUpper) == 0)
      return 1;

   int requestedLen = StringLen(requestedUpper);
   int candidateLen = StringLen(candidateUpper);
   int suffixPos = candidateLen - requestedLen;
   if(suffixPos >= 0 && StringSubstr(candidateUpper, suffixPos, requestedLen) == requestedUpper)
      return 2;

   if(StringFind(candidateUpper, requestedUpper) >= 0)
      return 3;

   return -1;
}

bool ResolveRequestedTradingSymbol(string requestedSymbol, string &resolvedSymbol, bool &usedVariant)
{
   resolvedSymbol = "";
   usedVariant = false;

   string requestedTrimmed = requestedSymbol;
   StringTrimLeft(requestedTrimmed);
   StringTrimRight(requestedTrimmed);
   if(requestedTrimmed == "")
      return false;

   long exactIsCustom = 0;
   bool hasExactInfo = SymbolInfoInteger(requestedTrimmed, SYMBOL_CUSTOM, exactIsCustom);
   if(SymbolSelect(requestedTrimmed, true) && (!hasExactInfo || exactIsCustom == 0))
     {
      resolvedSymbol = requestedTrimmed;
      return true;
     }

   string requestedUpper = NormalizeSymbolLookupValue(requestedTrimmed);
   string bestCandidate = "";
   string bestCandidateUpper = "";
   int bestRank = 2147483647;
   int bestExtraLength = 2147483647;

   int totalSymbols = SymbolsTotal(false);
   for(int i = 0; i < totalSymbols; i++)
     {
      string candidate = SymbolName(i, false);
      if(candidate == "" || IsCustomTerminalSymbol(candidate))
         continue;

      string candidateUpper = NormalizeSymbolLookupValue(candidate);
      int matchRank = GetRequestedTradingSymbolMatchRank(requestedUpper, candidateUpper);
      if(matchRank < 0)
         continue;

      int extraLength = StringLen(candidateUpper) - StringLen(requestedUpper);
      if(extraLength < 0)
         extraLength = 0;

      bool isBetter = false;
      if(matchRank < bestRank)
         isBetter = true;
      else if(matchRank == bestRank && extraLength < bestExtraLength)
         isBetter = true;
      else if(matchRank == bestRank && extraLength == bestExtraLength &&
              (bestCandidateUpper == "" || StringCompare(candidateUpper, bestCandidateUpper) < 0))
         isBetter = true;

      if(!isBetter)
         continue;

      bestCandidate = candidate;
      bestCandidateUpper = candidateUpper;
      bestRank = matchRank;
      bestExtraLength = extraLength;
     }

   if(bestCandidate == "")
      return false;

   if(!SymbolSelect(bestCandidate, true))
      return false;

   resolvedSymbol = bestCandidate;
   usedVariant = (StringCompare(bestCandidate, requestedTrimmed, false) != 0);
   return true;
}

/**
 * Parses the execution symbol from an analysis symbol.
 * Example: "BTCUSD_Renko" -> "BTCUSD", "XAUUSD.m" -> "XAUUSD"
 */
string GetBaseSymbol(string analysisSymbol)
{
   string candidates[];
   string guess = "";
   
   // 1. Try splitting by Dot (Example: "XAUUSD.Renko")
   if(StringSplit(analysisSymbol, '.', candidates) > 1)
   {
      guess = candidates[0];
      if(SymbolSelect(guess, true)) return guess;
   }
   
   // 2. Try splitting by Underscore (Example: "BTCUSD_Renko")
   if(StringSplit(analysisSymbol, '_', candidates) > 1)
   {
      guess = candidates[0];
      if(SymbolSelect(guess, true)) return guess;
   }
   
   // 3. Try splitting by Space
   if(StringSplit(analysisSymbol, ' ', candidates) > 1)
   {
      guess = candidates[0];
      if(SymbolSelect(guess, true)) return guess;
   }

   // 4. Default to original if no match found
   return analysisSymbol; 
}

/**
 * Checks if a symbol is a synthetic/analysis symbol.
 */
bool IsAnalysisSymbol(string symbol)
{
   return (symbol != GetBaseSymbol(symbol));
}

/**
 * Context tracker for active trading symbols.
 */
struct SBP_SymbolStats
{
   string   symbol;
   double   lastAsk;
   double   lastBid;
   ulong    lastTickMs;
   bool     isLive;
};

#endif // __MULTIBOTPRO_SYMBOLCONTEXT_MQH__

