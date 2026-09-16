#ifndef __MULTIBOTPRO_SIGNALENGINE_MQH__
#define __MULTIBOTPRO_SIGNALENGINE_MQH__
//+------------------------------------------------------------------+
//|                                     MultiBotPro_SignalEngine.mqh |
//|                          Decoupled entry and indicator component |
//+------------------------------------------------------------------+
#property strict

// Stub for now. We will migrate 'CheckEntrySignals' and 'CheckORReversalSignals' here.
class CSignalEngine
{
public:
   CSignalEngine() {}
   
   void ProcessSignals(int symbolIndex, bool isNewBar)
   {
      if(InpProcessSignalsPerBar && !isNewBar)
      {
         SetEntryGateDiagnostic(symbolIndex, ENTRY_GATE_SIGNAL_STACK, "Waiting for a new bar", false);
      }
      else
      {
         if(UseORReversal) CheckORReversalSignals(symbolIndex);
         else CheckEntrySignals(symbolIndex);
      }
   }
};

CSignalEngine G_SignalEngine;

#endif // __MULTIBOTPRO_SIGNALENGINE_MQH__
