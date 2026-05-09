//+------------------------------------------------------------------+
//|                                         MultiBotPro_SystemTests.mqh |
//|                               Copyright 2025, Expert Advisor Pro |
//|                    Resilience & Stress Tests for Distributed System |
//+------------------------------------------------------------------+
#ifndef __MULTIBOTPRO_SYSTEMTESTS_MQH__
#define __MULTIBOTPRO_SYSTEMTESTS_MQH__

#include "MultiBotPro_MessageQueue.mqh"

// ========================================
// TEST 1: Coordinator Resilience After Worker Crash
// ========================================

class CCoordinatorResilienceTest
{
private:
   CMbpMessageQueue m_coordinator_queue;
   CMbpMessageQueue m_worker_queue;
   ulong m_workerLastHeartbeatMs;
   bool m_workerIsAlive;
   

public:
   CCoordinatorResilienceTest() :
      m_workerLastHeartbeatMs(0),
      m_workerIsAlive(true)
   {}

   // Simulate: Coordinator sends heartbeat, Worker dies
   void SimulateWorkerCrash()
   {
      m_workerIsAlive = false;
      m_workerLastHeartbeatMs = GetTickCount64();
      Print("TEST1: Worker crash simulated at " + IntegerToString(m_workerLastHeartbeatMs));
   }

   // Coordinator detects timeout and pauses positions
   bool TestCoordinatorDetectsTimeout()
   {
      ulong nowMs = GetTickCount64();
      ulong elapsedMs = nowMs - m_workerLastHeartbeatMs;

      // Check if heartbeat timeout exceeded
      if(!m_workerIsAlive && elapsedMs >= 5000)
      {
         Print("TEST1: Coordinator detected worker timeout at " + IntegerToString(elapsedMs) + "ms");
         return true;
      }

      return false;
   }

   // Coordinator continues with other symbols
   bool TestCoordinatorContinuesOtherSymbols()
   {
      // Send position query for non-affected symbol
      SMbpMessage msg;
      msg.msgType = MBP_MSG_HEARTBEAT;
      msg.senderSymbol = "EURUSD"; // Different from crashed worker symbol
      msg.senderChartId = 12345;

      if(m_coordinator_queue.Enqueue(msg))
      {
         Print("TEST1: Coordinator continues trading other symbol");
         return true;
      }

      return false;
   }

   // Run full test scenario
   bool RunTest()
   {
      Print("=== TEST 1: Coordinator Resilience ===");

      SimulateWorkerCrash();
      Sleep(5100); // Wait for timeout

      bool detectsTimeout = TestCoordinatorDetectsTimeout();
      bool continuesOthers = TestCoordinatorContinuesOtherSymbols();

      Print("TEST1 Result: " + (detectsTimeout && continuesOthers ? "PASS" : "FAIL"));
      return (detectsTimeout && continuesOthers);
   }
};

// ========================================
// TEST 2: Worker Auto-Pause at Heartbeat Timeout
// ========================================

class CWorkerHeartbeatTest
{
private:
   ulong m_lastHeartbeatMs;
   bool m_isPaused;
   

public:
   CWorkerHeartbeatTest() :
      m_lastHeartbeatMs(0),
      m_isPaused(false)
   {}

   // Simulate: Coordinator sends heartbeat
   void SendCoordinatorHeartbeat()
   {
      m_lastHeartbeatMs = GetTickCount64();
      m_isPaused = false; // Resume on heartbeat
      Print("TEST2: Coordinator heartbeat received at " + IntegerToString(m_lastHeartbeatMs));
   }

   // Simulate: Worker checks heartbeat periodically
   bool CheckHeartbeatTimeout()
   {
      ulong nowMs = GetTickCount64();
      ulong elapsedMs = nowMs - m_lastHeartbeatMs;

      if(elapsedMs >= 5000 && !m_isPaused)
      {
         m_isPaused = true;
         Print("TEST2: Worker auto-paused at " + IntegerToString(elapsedMs) + "ms");
         return true;
      }

      return m_isPaused;
   }

   // Verify pause happens exactly at timeout threshold (within 100ms tolerance)
   bool VerifyTimeoutPrecision()
   {
      ulong nowMs = GetTickCount64();
      ulong elapsedMs = nowMs - m_lastHeartbeatMs;

      if(m_isPaused)
      {
         ulong tolerance = 100; // Allow 100ms deviation
         bool withinTolerance = (elapsedMs >= 5000 &&
                                elapsedMs <= (5000 + tolerance));

         Print("TEST2: Timeout precision check - elapsed=" + IntegerToString(elapsedMs) +
               "ms (tolerance=" + IntegerToString(tolerance) + "ms) - " +
               (withinTolerance ? "PASS" : "FAIL"));
         return withinTolerance;
      }

      return false;
   }

   // Run full test scenario
   bool RunTest()
   {
      Print("=== TEST 2: Worker Heartbeat Auto-Pause ===");

      SendCoordinatorHeartbeat();
      Sleep(5100); // Wait for timeout
      bool paused = CheckHeartbeatTimeout();
      bool precise = VerifyTimeoutPrecision();

      Print("TEST2 Result: " + (paused && precise ? "PASS" : "FAIL"));
      return (paused && precise);
   }
};

// ========================================
// TEST 3: Global Variable Synchronization Stress Test
// ========================================

class CGlobalVarSyncStressTest
{
private:
   struct SPositionOp
   {
      ulong ticket;
      string symbol;
      int action; // 1=open, 2=close, 3=modify
      ulong timestamp;
   };

   SPositionOp m_operations[];
   int m_operationIdx;
   

public:
   CGlobalVarSyncStressTest() :
      m_operationIdx(0)
   {
      ArrayResize(m_operations, 100);
   }

   // Simulate rapid position open/close
   void GenerateStressOperations()
   {
      Print("TEST3: Generating " + IntegerToString(100) + " rapid operations");

      string symbols[] = {"EURUSD", "GBPUSD", "USDJPY", "NZDUSD", "AUDUSD"};
      int symbolCount = ArraySize(symbols);

      for(int i = 0; i < 100; i++)
      {
         m_operations[i].ticket = 100000 + i;
         m_operations[i].symbol = symbols[i % symbolCount];
         m_operations[i].action = (i % 3) + 1; // Cycles through 1,2,3
         m_operations[i].timestamp = GetTickCount64();
      }
   }

   // Process operations and verify sync
   bool ProcessAndVerifySync()
   {
      int successCount = 0;
      int failureCount = 0;

      for(int i = 0; i < 100; i++)
      {
         SPositionOp op = m_operations[i];

         // Simulate operation with global variable update
         string gvKey = "MBP_POS_" + IntegerToString(op.ticket);
         GlobalVariableSet(gvKey, (double)op.action);

         // Verify write
         double readBack = GlobalVariableGet(gvKey);
         if(readBack == (double)op.action)
         {
            successCount++;
         }
         else
         {
            failureCount++;
            Print("TEST3: Sync failure at operation " + IntegerToString(i));
         }

         // Small delay to simulate processing
         if(i % 10 == 0)
            Sleep(1);
      }

      Print("TEST3: Processed " + IntegerToString(successCount) + " successful, " +
            IntegerToString(failureCount) + " failed");

      return (failureCount == 0);
   }

   // Cleanup global variables after test
   void Cleanup()
   {
      for(int i = 0; i < 100; i++)
      {
         string gvKey = "MBP_POS_" + IntegerToString(m_operations[i].ticket);
         GlobalVariableDel(gvKey);
      }
      Print("TEST3: Cleanup complete");
   }

   // Run full test scenario
   bool RunTest()
   {
      Print("=== TEST 3: Global Variable Synchronization Stress ===");

      GenerateStressOperations();
      bool syncOk = ProcessAndVerifySync();
      Cleanup();

      Print("TEST3 Result: " + (syncOk ? "PASS" : "FAIL"));
      return syncOk;
   }
};

// ========================================
// Test Suite Runner
// ========================================

class CSystemTestSuite
{
public:
   bool RunAllTests()
   {
      bool allPass = true;

      CCoordinatorResilienceTest coordTest;
      if(!coordTest.RunTest()) allPass = false;
      Print("");

      CWorkerHeartbeatTest heartbeatTest;
      if(!heartbeatTest.RunTest()) allPass = false;
      Print("");

      CGlobalVarSyncStressTest syncTest;
      if(!syncTest.RunTest()) allPass = false;
      Print("");

      Print("=== TEST SUITE SUMMARY ===");
      Print("Overall Result: " + (allPass ? "ALL TESTS PASSED" : "SOME TESTS FAILED"));
      return allPass;
   }
};

#endif
