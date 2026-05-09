//+------------------------------------------------------------------+
//|                                      MultiBotPro_BoundsChecking.mqh |
//|                               Copyright 2025, Expert Advisor Pro |
//|                          Array Bounds & Safety Validation Helpers |
//+------------------------------------------------------------------+
#ifndef __MULTIBOTPRO_BOUNDSCHECKING_MQH__
#define __MULTIBOTPRO_BOUNDSCHECKING_MQH__

// Helper functions for safe array access and bounds validation
namespace MBP_Bounds
{
   // Validate array index is within bounds
   template<typename T>
   bool IsValidIndex(const T &array[], int index)
   {
      int size = ArraySize(array);
      return (index >= 0 && index < size);
   }

   // Safe array access with bounds check
   // Returns success status
   template<typename T>
   bool SafeGet(const T &array[], int index, T &outValue)
   {
      if(!IsValidIndex(array, index))
      {
         Print("MBP BoundsCheck: Array index out of bounds [" +
               IntegerToString(index) + "/" + IntegerToString(ArraySize(array)) + "]");
         return false;
      }
      outValue = array[index];
      return true;
   }

   // Safe array set with bounds check
   template<typename T>
   bool SafeSet(T &array[], int index, const T &value)
   {
      if(!IsValidIndex(array, index))
      {
         Print("MBP BoundsCheck: Array index out of bounds [" +
               IntegerToString(index) + "/" + IntegerToString(ArraySize(array)) + "]");
         return false;
      }
      array[index] = value;
      return true;
   }

   // Find element in array with bounds check
   template<typename T>
   int FindInArray(const T &array[], const T &searchValue)
   {
      int size = ArraySize(array);
      for(int i = 0; i < size; i++)
      {
         if(array[i] == searchValue)
            return i;
      }
      return -1;
   }

   // Validate symbol string is within reasonable length
   bool IsValidSymbol(const string &symbol)
   {
      int len = StringLen(symbol);
      if(len < 1 || len > 20)
      {
         Print("MBP BoundsCheck: Invalid symbol length [" + IntegerToString(len) + "]");
         return false;
      }
      return true;
   }

   // Validate position ticket number
   bool IsValidTicket(ulong ticket)
   {
      return (ticket > 0 && ticket < 9223372036854775807UL); // Max uint64
   }

   // Validate lot size within broker limits
   bool IsValidLot(string symbol, double lot)
   {
      if(lot <= 0)
      {
         Print("MBP BoundsCheck: Lot size <= 0 [" + DoubleToString(lot, 4) + "]");
         return false;
      }

      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(minLot == 0 || maxLot == 0)
      {
         Print("MBP BoundsCheck: Cannot determine lot limits for " + symbol);
         return true; // Assume valid if can't query
      }

      if(lot < minLot || lot > maxLot)
      {
         Print("MBP BoundsCheck: Lot outside range [" + DoubleToString(lot, 4) +
               " not in " + DoubleToString(minLot, 4) + ".." +
               DoubleToString(maxLot, 4) + "]");
         return false;
      }

      if(stepLot > 0)
      {
         // Check if lot is aligned to step
         double remainder = MathMod(lot - minLot, stepLot);
         if(remainder > 0.0001)
         {
            Print("MBP BoundsCheck: Lot not aligned to step [" + DoubleToString(lot, 4) +
                  " step=" + DoubleToString(stepLot, 4) + "]");
            return false;
         }
      }

      return true;
   }

   // Validate price within reasonable deviation from current market
   bool IsValidPrice(string symbol, double price)
   {
      if(price <= 0)
      {
         Print("MBP BoundsCheck: Price <= 0 [" + DoubleToString(price, 5) + "]");
         return false;
      }

      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

      if(bid <= 0 || ask <= 0)
      {
         Print("MBP BoundsCheck: Cannot get market price for " + symbol);
         return true; // Assume valid if can't query
      }

      // Allow ±10% deviation from current market
      double mid = (bid + ask) / 2.0;
      double maxDeviation = mid * 0.10;
      double deviation = MathAbs(price - mid);

      if(deviation > maxDeviation)
      {
         Print("MBP BoundsCheck: Price deviates too much from market [" +
               DoubleToString(price, 5) + " vs " + DoubleToString(mid, 5) + "]");
         return false;
      }

      return true;
   }

   // Validate equity value is reasonable
   bool IsValidEquity(double equity)
   {
      return (equity > 0 && equity < 9999999999.0);
   }

   // Validate percentage (0-100)
   bool IsValidPercentage(double percent)
   {
      return (percent >= 0 && percent <= 100);
   }

   // Batch validation result
   struct SValidationResult
   {
      bool isValid;
      string errorMessage;
   };

   // Validate position parameters before opening
   SValidationResult ValidatePositionParams(string symbol, int orderType,
                                           double volume, double price,
                                           double stopLoss, double takeProfit)
   {
      SValidationResult result;
      result.isValid = true;
      result.errorMessage = "";

      if(!IsValidSymbol(symbol))
      {
         result.isValid = false;
         result.errorMessage = "Invalid symbol";
         return result;
      }

      if(!IsValidLot(symbol, volume))
      {
         result.isValid = false;
         result.errorMessage = "Invalid lot size";
         return result;
      }

      if(!IsValidPrice(symbol, price))
      {
         result.isValid = false;
         result.errorMessage = "Invalid entry price";
         return result;
      }

      if(stopLoss > 0 && !IsValidPrice(symbol, stopLoss))
      {
         result.isValid = false;
         result.errorMessage = "Invalid stop loss price";
         return result;
      }

      if(takeProfit > 0 && !IsValidPrice(symbol, takeProfit))
      {
         result.isValid = false;
         result.errorMessage = "Invalid take profit price";
         return result;
      }

      return result;
   }
}

#endif
