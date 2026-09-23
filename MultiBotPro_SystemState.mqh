//+------------------------------------------------------------------+
//|                                          MultiBotPro_SystemState.mqh |
//|                               Copyright 2025, Expert Advisor Pro |
//|                                    System State Encapsulation Class |
//+------------------------------------------------------------------+
#ifndef __MULTIBOTPRO_SYSTEMSTATE_MQH__
#define __MULTIBOTPRO_SYSTEMSTATE_MQH__

// Encapsulates all system cache, handshake, and risk globals in a single class
// Provides thread-safe access patterns and clear mutation contracts
class CSystemState
{
private:
   // --- CACHE STATE (Updated via OnTimer) ---
   bool   m_cache_SystemBlocked;
   bool   m_cache_IsTradingTime;
   bool   m_cache_IsNewsTime;
   bool   m_cache_IsHardBlock;
   bool   m_cache_IsDailyCloseBlock;
   string m_cache_BlockReason;

   ulong  m_lastShadowSyncCheckMs;
   ulong  m_lastShadowSupervisorCheckMs;
   ulong  m_lastShadowRuntimeWriteMs;
   ulong  m_lastShadowLaunchAttemptMs;
   string m_lastShadowRuntimeSignature;

   // --- HANDSHAKE PROTOCOL STATE ---
   bool   m_handshakePending;
   ulong  m_handshakeStartTimeMs;
   ulong  m_pendingProposalTicket;

   // --- HEDGE MASTER RISK STATE ---
   double m_masterStartEquity;
   double m_highWaterMark;
   double m_trailingStopLevel;
   double m_dayStartEquity;
   int    m_currentDayOfYear;
   bool   m_dailyStopHit;
   bool   m_totalStopHit;
   long   m_currentResetID;
   double m_effectiveMasterRisk;

   // --- UI STATE ---
   bool   m_showManualSection;
   bool   m_showTradeList;
   bool   m_panelIsModifying;
   ulong  m_panelSelectedTicket;
   double m_panelManualLot;

   // --- INITIALIZATION/DEINIT ---
   bool   m_isDeinit;
   bool   m_initInProgress;
   bool   m_sltp_hidden;

public:
   // Constructor
   CSystemState() :
      m_cache_SystemBlocked(false),
      m_cache_IsTradingTime(false), // Step 3: fail-closed default
      m_cache_IsNewsTime(false),
      m_cache_IsHardBlock(false),
      m_cache_IsDailyCloseBlock(false),
      m_cache_BlockReason(""),
      m_lastShadowSyncCheckMs(0),
      m_lastShadowSupervisorCheckMs(0),
      m_lastShadowRuntimeWriteMs(0),
      m_lastShadowLaunchAttemptMs(0),
      m_lastShadowRuntimeSignature(""),
      m_handshakePending(false),
      m_handshakeStartTimeMs(0),
      m_pendingProposalTicket(0),
      m_masterStartEquity(0),
      m_highWaterMark(0),
      m_trailingStopLevel(0),
      m_dayStartEquity(0),
      m_currentDayOfYear(-1),
      m_dailyStopHit(false),
      m_totalStopHit(false),
      m_currentResetID(0),
      m_effectiveMasterRisk(0),
      m_showManualSection(false),
      m_showTradeList(false),
      m_panelIsModifying(false),
      m_panelSelectedTicket(0),
      m_panelManualLot(0.01),
      m_isDeinit(false),
      m_initInProgress(false),
      m_sltp_hidden(false)
   {}

   // --- CACHE GETTERS/SETTERS ---
   bool GetCacheSystemBlocked() const { return m_cache_SystemBlocked; }
   void SetCacheSystemBlocked(bool value) { m_cache_SystemBlocked = value; }

   bool GetCacheIsTradingTime() const { return m_cache_IsTradingTime; }
   void SetCacheIsTradingTime(bool value) { m_cache_IsTradingTime = value; }

   bool GetCacheIsNewsTime() const { return m_cache_IsNewsTime; }
   void SetCacheIsNewsTime(bool value) { m_cache_IsNewsTime = value; }

   bool GetCacheIsHardBlock() const { return m_cache_IsHardBlock; }
   void SetCacheIsHardBlock(bool value) { m_cache_IsHardBlock = value; }

   bool GetCacheIsDailyCloseBlock() const { return m_cache_IsDailyCloseBlock; }
   void SetCacheIsDailyCloseBlock(bool value) { m_cache_IsDailyCloseBlock = value; }

   string GetCacheBlockReason() const { return m_cache_BlockReason; }
   void SetCacheBlockReason(string reason) { m_cache_BlockReason = reason; }

   // --- SHADOW SYNC TIMESTAMPS ---
   ulong GetLastShadowSyncCheckMs() const { return m_lastShadowSyncCheckMs; }
   void SetLastShadowSyncCheckMs(ulong timeMs) { m_lastShadowSyncCheckMs = timeMs; }

   ulong GetLastShadowSupervisorCheckMs() const { return m_lastShadowSupervisorCheckMs; }
   void SetLastShadowSupervisorCheckMs(ulong timeMs) { m_lastShadowSupervisorCheckMs = timeMs; }

   ulong GetLastShadowRuntimeWriteMs() const { return m_lastShadowRuntimeWriteMs; }
   void SetLastShadowRuntimeWriteMs(ulong timeMs) { m_lastShadowRuntimeWriteMs = timeMs; }

   ulong GetLastShadowLaunchAttemptMs() const { return m_lastShadowLaunchAttemptMs; }
   void SetLastShadowLaunchAttemptMs(ulong timeMs) { m_lastShadowLaunchAttemptMs = timeMs; }

   string GetLastShadowRuntimeSignature() const { return m_lastShadowRuntimeSignature; }
   void SetLastShadowRuntimeSignature(string sig) { m_lastShadowRuntimeSignature = sig; }

   // --- HANDSHAKE STATE ---
   bool GetHandshakePending() const { return m_handshakePending; }
   void SetHandshakePending(bool value) { m_handshakePending = value; }

   ulong GetHandshakeStartTimeMs() const { return m_handshakeStartTimeMs; }
   void SetHandshakeStartTimeMs(ulong timeMs) { m_handshakeStartTimeMs = timeMs; }

   ulong GetPendingProposalTicket() const { return m_pendingProposalTicket; }
   void SetPendingProposalTicket(ulong ticket) { m_pendingProposalTicket = ticket; }

   // --- HEDGE MASTER RISK STATE ---
   double GetMasterStartEquity() const { return m_masterStartEquity; }
   void SetMasterStartEquity(double value) { m_masterStartEquity = value; }

   double GetHighWaterMark() const { return m_highWaterMark; }
   void SetHighWaterMark(double value) { m_highWaterMark = value; }

   double GetTrailingStopLevel() const { return m_trailingStopLevel; }
   void SetTrailingStopLevel(double value) { m_trailingStopLevel = value; }

   double GetDayStartEquity() const { return m_dayStartEquity; }
   void SetDayStartEquity(double value) { m_dayStartEquity = value; }

   int GetCurrentDayOfYear() const { return m_currentDayOfYear; }
   void SetCurrentDayOfYear(int day) { m_currentDayOfYear = day; }

   bool GetDailyStopHit() const { return m_dailyStopHit; }
   void SetDailyStopHit(bool value) { m_dailyStopHit = value; }

   bool GetTotalStopHit() const { return m_totalStopHit; }
   void SetTotalStopHit(bool value) { m_totalStopHit = value; }

   long GetCurrentResetID() const { return m_currentResetID; }
   void SetCurrentResetID(long id) { m_currentResetID = id; }

   double GetEffectiveMasterRisk() const { return m_effectiveMasterRisk; }
   void SetEffectiveMasterRisk(double value) { m_effectiveMasterRisk = value; }

   // --- UI STATE ---
   bool GetShowManualSection() const { return m_showManualSection; }
   void SetShowManualSection(bool value) { m_showManualSection = value; }

   bool GetShowTradeList() const { return m_showTradeList; }
   void SetShowTradeList(bool value) { m_showTradeList = value; }

   bool GetPanelIsModifying() const { return m_panelIsModifying; }
   void SetPanelIsModifying(bool value) { m_panelIsModifying = value; }

   ulong GetPanelSelectedTicket() const { return m_panelSelectedTicket; }
   void SetPanelSelectedTicket(ulong ticket) { m_panelSelectedTicket = ticket; }

   double GetPanelManualLot() const { return m_panelManualLot; }
   void SetPanelManualLot(double lot) { if(lot <= 0.0) lot = 0.01; if(lot > 50.0) lot = 50.0; m_panelManualLot = lot; }

   // --- LIFECYCLE FLAGS ---
   bool GetIsDeinit() const { return m_isDeinit; }
   void SetIsDeinit(bool value) { m_isDeinit = value; }

   bool GetInitInProgress() const { return m_initInProgress; }
   void SetInitInProgress(bool value) { m_initInProgress = value; }

   bool GetSltpHidden() const { return m_sltp_hidden; }
   void SetSltpHidden(bool value) { m_sltp_hidden = value; }

   // --- DIAGNOSTICS ---
   bool IsSystemOnBlockade() const
   {
      return m_cache_SystemBlocked || m_cache_IsHardBlock ||
             m_cache_IsDailyCloseBlock;
   }

   bool HasPendingProposal() const { return m_handshakePending && m_pendingProposalTicket != 0; }
   void ResetDaily(const int dayOfYear, const double equity) { m_currentDayOfYear = dayOfYear; m_dayStartEquity = equity; m_dailyStopHit = false; }
   bool CanTrade() const { if(m_isDeinit) return false; if(!m_cache_IsTradingTime) return false; if(m_cache_IsNewsTime) return false; if(IsSystemOnBlockade()) return false; if(HasPendingProposal()) return false; return true; }

   // Thread-safety note: This class should be accessed from OnInit/OnTimer/OnTick/OnChartEvent
   // All getters/setters are simple member access with no external side effects
};

#endif

