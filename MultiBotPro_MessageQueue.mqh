//+------------------------------------------------------------------+
//|                                       MultiBotPro_MessageQueue.mqh |
//|                               Copyright 2025, Expert Advisor Pro |
//|                     Coordinator↔Worker Structured Communication |
//+------------------------------------------------------------------+
#ifndef __MULTIBOTPRO_MESSAGEQUEUE_MQH__
#define __MULTIBOTPRO_MESSAGEQUEUE_MQH__

// Structured message types for Coordinator↔Worker protocol
enum ENUM_MBP_MESSAGE_TYPE
{
   MBP_MSG_HEARTBEAT = 0,      // Alive signal from Coordinator/Worker
   MBP_MSG_POSITION_OPEN = 1,  // Worker opens position
   MBP_MSG_POSITION_CLOSE = 2, // Worker closes position
   MBP_MSG_POSITION_MODIFY = 3,// Worker modifies position
   MBP_MSG_RISK_BREACH = 4,    // Risk limit breach notification
   MBP_MSG_EMERGENCY_STOP = 5, // Emergency stop from Coordinator
   MBP_MSG_WORKER_PAUSE = 6,   // Pause trading (Coordinator → Worker)
   MBP_MSG_WORKER_RESUME = 7,  // Resume trading (Coordinator → Worker)
   MBP_MSG_CHART_ATTACHED = 8, // Worker chart initialized
   MBP_MSG_CHART_DETACHED = 9  // Worker chart closing
};

// Message structure for queue operations
struct SMbpMessage
{
   ENUM_MBP_MESSAGE_TYPE msgType;
   ulong timestamp;        // GetTickCount64() when created
   ulong senderChartId;    // ChartID() of sender
   string senderSymbol;    // Symbol name for context
   int   priority;         // 0=low, 10=high
   ulong dataA;            // Generic data field A (ticket, count, etc.)
   double dataB;           // Generic data field B (price, pnl, etc.)
   string dataStr;         // String payload
   int   ackId;            // Acknowledge with this ID if set to >0
   bool  acknowledged;     // Set true when ACK received
   ulong ackedAtMs;        // When ACK was received
};

// Thread-safe message queue for Coordinator↔Worker IPC
// Step 11: NOTE — this queue is IN-PROCESS ONLY (same chart). It does NOT cross chart boundaries.
// Cross-chart Coordinator↔Worker IPC uses GlobalVariable MBP_COORD_ALIVE/MBP_WB_<sym> + atomic files (MBP_WorkerHeartbeat_, MBP_WorkerAssignment_) + SQLite.
// Do not use this queue for worker messages expecting cross-chart delivery.
class CMbpMessageQueue
{
private:
   SMbpMessage m_queue[];
   int m_writeIdx;
   int m_readIdx;
   int m_capacity;
   int m_nextAckId;

public:
   CMbpMessageQueue(int capacity = 64) :
      m_writeIdx(0),
      m_readIdx(0),
      m_capacity(capacity),
      m_nextAckId(1)
   {
      ArrayResize(m_queue, m_capacity);
   }

   ~CMbpMessageQueue() {}

   // Enqueue a message. Returns true if successful.
   bool Enqueue(const SMbpMessage &msg)
   {
      int nextWrite = (m_writeIdx + 1) % m_capacity;

      // Queue full check (protect read index)
      if(nextWrite == m_readIdx)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("MBP MessageQueue overflow: capacity " + IntegerToString(m_capacity));
         return false;
      }

      SMbpMessage toQueue = msg;
      toQueue.timestamp = GetTickCount64();
      if(toQueue.ackId > 0 || (toQueue.msgType >= MBP_MSG_RISK_BREACH))
      {
         toQueue.ackId = m_nextAckId++;
      }

      m_queue[m_writeIdx] = toQueue;
      m_writeIdx = nextWrite;
      return true;
   }

   // Dequeue oldest message. Returns true if message available.
   bool Dequeue(SMbpMessage &outMsg)
   {
      if(m_readIdx == m_writeIdx)
      {
         return false; // Queue empty
      }

      outMsg = m_queue[m_readIdx];
      m_readIdx = (m_readIdx + 1) % m_capacity;
      return true;
   }

   // Peek at oldest message without removing. Returns true if available.
   bool Peek(SMbpMessage &outMsg) const
   {
      if(m_readIdx == m_writeIdx)
      {
         return false;
      }

      outMsg = m_queue[m_readIdx];
      return true;
   }

   // Count messages in queue
   int GetMessageCount() const
   {
      if(m_writeIdx >= m_readIdx)
         return m_writeIdx - m_readIdx;
      else
         return m_capacity - (m_readIdx - m_writeIdx);
   }

   // Check if queue is empty
   bool IsEmpty() const
   {
      return m_readIdx == m_writeIdx;
   }

   // Clear all pending messages
   void Clear()
   {
      m_readIdx = 0;
      m_writeIdx = 0;
   }

   // Find oldest message of specific type (for acknowledgment matching)
   bool FindByType(ENUM_MBP_MESSAGE_TYPE type, SMbpMessage &outMsg)
   {
      int current = m_readIdx;
      while(current != m_writeIdx)
      {
         if(m_queue[current].msgType == type)
         {
            outMsg = m_queue[current];
            return true;
         }
         current = (current + 1) % m_capacity;
      }
      return false;
   }

   // Acknowledge a message by ID
   bool AcknowledgeById(int ackId, ulong ackedAtMs = 0)
   {
      if(ackId <= 0) return false;
      if(ackedAtMs == 0) ackedAtMs = GetTickCount64();

      int current = m_readIdx;
      while(current != m_writeIdx)
      {
         if(m_queue[current].ackId == ackId)
         {
            m_queue[current].acknowledged = true;
            m_queue[current].ackedAtMs = ackedAtMs;
            return true;
         }
         current = (current + 1) % m_capacity;
      }
      return false;
   }

   // Find unacknowledged messages (for retry logic)
   int FindUnacknowledgedCount() const
   {
      int count = 0;
      int current = m_readIdx;
      while(current != m_writeIdx)
      {
         if(m_queue[current].ackId > 0 && !m_queue[current].acknowledged)
            count++;
         current = (current + 1) % m_capacity;
      }
      return count;
   }

   // Purge acknowledged messages (cleanup)
   void PurgeAcknowledged()
   {
      while(!IsEmpty() && m_queue[m_readIdx].acknowledged)
      {
         m_readIdx = (m_readIdx + 1) % m_capacity;
      }
   }

   // Diagnostic: dump queue contents
   void DumpQueueStatus()
   {
      int count = GetMessageCount();
      if(MBP_LogTierEnabled(MBP_LOG_TIER_DEBUG)) Print("MBP MessageQueue [" + IntegerToString(count) + "/" + IntegerToString(m_capacity) + "]:");

      int current = m_readIdx;
      int displayCount = 0;
      while(current != m_writeIdx && displayCount < 10)
      {
         SMbpMessage msg = m_queue[current];
         string ackStatus = (msg.ackId > 0)
                           ? (msg.acknowledged ? "ACK'd" : "Pending")
                           : "NoAck";
         if(MBP_LogTierEnabled(MBP_LOG_TIER_IMPORTANT)) Print("  [" + IntegerToString(displayCount) + "] Type=" + IntegerToString(msg.msgType) +
               " Sym=" + msg.senderSymbol + " Ack=" + ackStatus);
         current = (current + 1) % m_capacity;
         displayCount++;
      }
   }
};

#endif

