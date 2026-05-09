//+------------------------------------------------------------------+
//|                                        MultiBotPro_Coordinator.mqh |
//|                               Copyright 2025, Expert Advisor Pro |
//|                        Coordinator/Master Orchestration & IPC Hub |
//+------------------------------------------------------------------+
#ifndef __MULTIBOTPRO_COORDINATOR_MQH__
#define __MULTIBOTPRO_COORDINATOR_MQH__

#include "MultiBotPro_SystemState.mqh"
#include "MultiBotPro_MessageQueue.mqh"
#include "MultiBotPro_RiskEngine.mqh"

class CCoordinator
{
private:
   CSystemState *m_systemState;
   CMbpMessageQueue *m_coordinatorQueue;
   CMbpMessageQueue *m_workerQueue;
   CRiskEngine *m_riskEngine;

   static ulong m_lastBankSaveMs;
   static ulong m_lastSyntheticPumpMs;
   static ulong m_lastDeferredHousekeepingMs;

public:
   CCoordinator(CSystemState *sysState, CMbpMessageQueue *coordQueue, CMbpMessageQueue *workerQueue, CRiskEngine *riskEngine) :
      m_systemState(sysState),
      m_coordinatorQueue(coordQueue),
      m_workerQueue(workerQueue),
      m_riskEngine(riskEngine)
   {
      m_lastBankSaveMs = 0;
      m_lastSyntheticPumpMs = 0;
      m_lastDeferredHousekeepingMs = 0;
   }

   ~CCoordinator() {}

   // Initialize coordinator at startup
   void Initialize()
   {
      if(!m_systemState) return;
      m_systemState.SetDayStartEquity(AccountInfoDouble(ACCOUNT_EQUITY));
      m_systemState.SetHighWaterMark(AccountInfoDouble(ACCOUNT_EQUITY));
      m_systemState.SetMasterStartEquity(AccountInfoDouble(ACCOUNT_EQUITY));
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      m_systemState.SetCurrentDayOfYear(dt.day_of_year);
      Print("CCoordinator: Initialized");
   }

   // Main coordinator cycle (called from OnTimer)
   void ProcessCycle()
   {
      if(!m_systemState || !m_riskEngine) return;

      ulong timerNowMs = GetTickCount();
      bool coordinatorMode = IsParallelCoordinatorMode();
      bool workerMode = IsParallelWorkerMode();

      // Sync system state with current account
      SyncAccountState();

      // Publish heartbeats
      PublishHeartbeats(coordinatorMode);

      // Consume UI commands
      ConsumeUiCommands();

      // Manage coordinator-specific logic
      if(coordinatorMode)
      {
         ManageCoordinatorMode();
      }

      // Dashboard UI management
      ManageDashboardUi(workerMode);

      // Trade control and processing
      ProcessTradeControl();
      ProcessBridgeRequests();

      // Periodic maintenance
      PerformMaintenance(timerNowMs);

      // Synthetic pump (if applicable)
      ProcessSyntheticPump(timerNowMs, coordinatorMode);

      // Worker charts need a timer-side overlay pulse because live/custom bars do
      // not always arrive through the normal tick path while panel UI is active.
      RefreshWorkerChartOverlay(workerMode, coordinatorMode);

      // License verification
      VerifyLicensePeriodic(workerMode);

      // Tester support
      HandleTesterMode(workerMode, coordinatorMode);
   }

   // Handle chart event from OnChartEvent
   void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
   {
      G_MasterUiPriorityUntilMs = GetTickCount() + 250;

      if(id == CHARTEVENT_OBJECT_DRAG)
      {
         OnPanelDrag(sparam);
         return;
      }

      if(id == CHARTEVENT_MOUSE_MOVE)
      {
         HandleDashboardMouseMove((int)lparam, (int)dparam, (int)StringToInteger(sparam));
         return;
      }

      if(id == CHARTEVENT_OBJECT_CLICK)
      {
         if(MQLInfoInteger(MQL_TESTER) && StringFind(sparam, "Btn_") == 0)
            return;

         HandleDashboardClick(sparam);
         return;
      }
   }

   // Process incoming worker messages
   int ProcessWorkerMessages()
   {
      if(!m_workerQueue) return 0;

      int processedCount = 0;
      SMbpMessage msg;

      while(m_workerQueue.Dequeue(msg))
      {
         switch(msg.msgType)
         {
            case MBP_MSG_RISK_BREACH:
               HandleWorkerRiskBreach(msg);
               break;
            case MBP_MSG_POSITION_OPEN:
            case MBP_MSG_POSITION_CLOSE:
            case MBP_MSG_POSITION_MODIFY:
               HandleWorkerPositionUpdate(msg);
               break;
            default:
               break;
         }
         processedCount++;
      }

      return processedCount;
   }

private:

   // === PRIVATE HELPERS ===

   void SyncAccountState()
   {
      if(!m_riskEngine) return;

      m_riskEngine.UpdateHighWaterMark();
      m_riskEngine.CheckAndResetDailyMetrics();
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_systemState.SetCacheIsTradingTime(IsTradingTime());
   }

   void PublishHeartbeats(bool coordinatorMode)
   {
      MasterPublishWorkerHeartbeat();

      if(coordinatorMode)
      {
         string coordAliveGV = "MBP_COORD_ALIVE_" + G_RuntimeCoordinatorKey;
         string coordOwnerGV = "MBP_COORD_OWNER_" + G_RuntimeCoordinatorKey;
         GlobalVariableSet(coordAliveGV, (double)GetTickCount64());
         GlobalVariableSet(coordOwnerGV, (double)ChartID());
      }
   }

   void ConsumeUiCommands()
   {
      MasterConsumeUiCommands();
   }

   void ManageCoordinatorMode()
   {
      MasterEnsureRuntimeWorkers();
   }

   void ManageDashboardUi(bool workerMode)
   {
      bool shouldManageDashboardUi = (!workerMode &&
                                      (ShowManualSection || ShowTradeList || Panel_IsModifying || MQLInfoInteger(MQL_TESTER)));
      bool uiPriorityActive = MasterIsUiPriorityWindowActive() || shouldManageDashboardUi;

      if(ShowDashboard && !IsDragging && !G_DashboardDragArmed)
      {
         if(workerMode)
         {
            UpdateDashboard(0);
         }
         else if(shouldManageDashboardUi)
         {
            ManageManualSystem();
         }
         else
         {
            UpdateDashboard(0);
            if(!DashboardCollapsed)
            {
               if(Panel_IsModifying) ManageModificationMode();
               else ManageTradeListMode();
            }
            else if(!Panel_IsModifying)
            {
               ObjectsDeleteAll(0, BTN_PREFIX_LIST);
            }
         }
      }
   }

   void ProcessTradeControl()
   {
      MasterProcessTradeControlLane();
   }

   void ProcessBridgeRequests()
   {
      ProcessBridgePendingRequest();
      FlushBridgeSignalQueue();
   }

   void PerformMaintenance(ulong timerNowMs)
   {
      bool uiPriorityActive = MasterIsUiPriorityWindowActive();
      uint bankSaveIntervalMs = uiPriorityActive ? 5000 : 1000;

      if(timerNowMs - m_lastBankSaveMs >= bankSaveIntervalMs)
      {
         SaveAllBankStates();
         m_lastBankSaveMs = timerNowMs;
      }

      if(!uiPriorityActive || (timerNowMs - m_lastDeferredHousekeepingMs) >= 5000)
      {
         if(ShadowMaster_ShouldOwnRuntime())
            ShadowMaster_Supervise(false);
         m_lastDeferredHousekeepingMs = timerNowMs;
      }
   }

   void ProcessSyntheticPump(ulong timerNowMs, bool coordinatorMode)
   {
      if(coordinatorMode) return;

      bool uiPriorityActive = MasterIsUiPriorityWindowActive();
      int configuredPumpMs = MBP_IsRenkoDataMode(InpDataMode)
                             ? InpRenkoLivePoolMs
                             : InpSyntheticPumpIntervalMs;
      uint syntheticPumpIntervalMs = (configuredPumpMs <= 0) ? 0 : (uint)configuredPumpMs;
      uint effectivePumpIntervalMs = syntheticPumpIntervalMs;

      if(uiPriorityActive)
      {
         if(effectivePumpIntervalMs == 0)
            effectivePumpIntervalMs = 250;
         else
            effectivePumpIntervalMs = MathMax((uint)250, effectivePumpIntervalMs * 4);
      }

      if(effectivePumpIntervalMs == 0 ||
         m_lastSyntheticPumpMs == 0 ||
         (timerNowMs - m_lastSyntheticPumpMs) >= effectivePumpIntervalMs)
      {
         MasterPumpRuntimeServices();
         MasterPumpTimerServices();
         m_lastSyntheticPumpMs = timerNowMs;
      }
   }

   void RefreshWorkerChartOverlay(bool workerMode, bool coordinatorMode)
   {
      if(!workerMode || coordinatorMode) return;
      if(G_IS_DEINIT || IsStopped()) return;
      if(!InpShowIndicatorOverlay) return;

      RefreshIndicatorOverlay(true);
      ChartRedraw(0);
   }

   void VerifyLicensePeriodic(bool workerMode)
   {
      if(workerMode) return;

      static int auth_timer_ticks = 0;
      auth_timer_ticks++;
      if(auth_timer_ticks >= 28800)
      {
         Print(EmojiBrain(), " Running background license verification...");
         if(!VerifyLicense())
         {
            Print(EmojiWarning(), " Subscription expired mid-session. Executing a hard shutdown.");
            for(int i = 0; i < ArraySize(SymbolData); i++)
            {
               if(SymbolData[i].active)
               {
                  CloseAllGridPositions(i, "License Expired");
                  ResetGridTracking(i);
               }
            }
            CloseAllGlobalPositions("License Expired");
            ExpertRemove();
         }
         auth_timer_ticks = 0;
      }
   }

   void HandleTesterMode(bool workerMode, bool coordinatorMode)
   {
      MasterHandleTesterCharts();

      if(MQLInfoInteger(MQL_TESTER) && !workerMode)
         MasterPollDashboardButtons();

      if(ForceTimerExecution && !MasterIsUiPriorityWindowActive() && !coordinatorMode)
         Master_OnTick();
   }

   void HandleDashboardClick(const string &sparam)
   {
      if(G_DashboardDragArmed && !IsDragging)
      {
         G_DashboardDragArmed = false;
         DragInteractionX = 0;
         DragInteractionY = 0;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
      }

      if(sparam == "Dash_BG" || sparam == "Dash_Title" || sparam == "Dash_RobotPic")
      {
         G_DashboardDragArmed = true;
         G_DashboardDragStartX = DashboardX;
         G_DashboardDragStartY = DashboardY;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         return;
      }

      if(StringFind(sparam, "Btn_") == 0)
      {
         ProcessButtonClick(sparam);
         return;
      }

      if(StringFind(sparam, "NewsLine_") >= 0 || StringFind(sparam, "NewsIcon_") >= 0)
      {
         string idStr = StringSubstr(sparam, 9);
         ShowNewsDetails("NewsLine_" + idStr);
      }
      else if(StringFind(sparam, "Row_Sym_") == 0)
      {
         ProcessSymbolRowClick(sparam);
      }
   }

   void ProcessButtonClick(const string &buttonName)
   {
      int queuedSymbolIndex = -1;
      int queuedCommand = MBP_UI_CMD_NONE;

      if(buttonName == "Btn_MasterReset") queuedCommand = MBP_UI_CMD_MASTER_RESET;
      else if(buttonName == "Btn_Pause") queuedCommand = MBP_UI_CMD_TOGGLE_PAUSE;
      else if(buttonName == "Btn_Collapse") queuedCommand = MBP_UI_CMD_TOGGLE_COLLAPSE;
      else if(buttonName == "Btn_Dash_Scale_P") queuedCommand = MBP_UI_CMD_DASH_SCALE_UP;
      else if(buttonName == "Btn_Dash_Scale_M") queuedCommand = MBP_UI_CMD_DASH_SCALE_DOWN;
      else if(buttonName == "Btn_ToggleMan") queuedCommand = MBP_UI_CMD_TOGGLE_MANUAL_SECTION;
      else if(buttonName == "Btn_ToggleList") queuedCommand = MBP_UI_CMD_TOGGLE_TRADE_LIST;
      else if(buttonName == "Btn_CloseAll") queuedCommand = MBP_UI_CMD_CLOSE_ALL;
      else if(buttonName == "Btn_CloseChart")
      {
         queuedCommand = MBP_UI_CMD_CLOSE_SYMBOL;
         queuedSymbolIndex = ResolveDashboardFocusSymbolIndex();
         if(queuedSymbolIndex < 0)
         {
            queuedSymbolIndex = GetSymbolIndex(_Symbol);
            if(queuedSymbolIndex == -1)
               queuedSymbolIndex = GetSymbolIndex(RealSymbol);
         }
      }

      if(queuedCommand != MBP_UI_CMD_NONE)
      {
         bool isImmediateUiCommand = (queuedCommand == MBP_UI_CMD_TOGGLE_PAUSE ||
                                      queuedCommand == MBP_UI_CMD_TOGGLE_COLLAPSE ||
                                      queuedCommand == MBP_UI_CMD_DASH_SCALE_UP ||
                                      queuedCommand == MBP_UI_CMD_DASH_SCALE_DOWN ||
                                      queuedCommand == MBP_UI_CMD_TOGGLE_MANUAL_SECTION ||
                                      queuedCommand == MBP_UI_CMD_TOGGLE_TRADE_LIST);

         if(!MQLInfoInteger(MQL_TESTER) && isImmediateUiCommand)
         {
            RememberDashboardButtonHandled(buttonName);
            MasterRaiseUiPriorityWindow(1200);

            SMasterUiCommand immediateCmd;
            ZeroMemory(immediateCmd);
            immediateCmd.type = queuedCommand;
            immediateCmd.symbolIndex = queuedSymbolIndex;
            immediateCmd.buttonName = buttonName;
            MasterExecuteUiCommand(immediateCmd);
         }
         else
         {
            MasterEnqueueUiCommand(queuedCommand, queuedSymbolIndex, buttonName);
            ChartRedraw(0);
         }
      }

      RememberDashboardButtonHandled(buttonName);
   }

   void ProcessSymbolRowClick(const string &symbolRowObj)
   {
      static string lastClickedSymObj = "";
      static uint lastClickTimeSym = 0;
      uint currentTime = GetTickCount();

      if(symbolRowObj == lastClickedSymObj && (currentTime - lastClickTimeSym) < 500)
      {
         int row = (int)StringToInteger(StringSubstr(symbolRowObj, 8));
         int idx = GetDashboardSymbolIndexByRow(row);
         if(idx >= 0 && idx < ArraySize(SymbolData))
         {
            string targetSymbol = ResolveManagedAnalysisSymbol(idx);
            string targetBaseSymbol = (SymbolData[idx].BaseSymbol != "") ? SymbolData[idx].BaseSymbol : GetBaseSymbol(targetSymbol);
            SetDashboardFocusSymbol(targetBaseSymbol);
            SaveFastChartSwitchDashboardState();

            if(targetSymbol == "")
               targetSymbol = targetBaseSymbol;

            if(targetSymbol != "" && SymbolSelect(targetSymbol, true))
            {
               MarkFastChartSwitchPending();
               ResetLastError();
               ENUM_TIMEFRAMES currentPeriod = (ENUM_TIMEFRAMES)ChartPeriod(0);
               if(!ChartSetSymbolPeriod(0, targetSymbol, currentPeriod))
                  Print(EmojiWarning(), " Dashboard symbol switch failed for ", targetSymbol, ". Error=", _LastError);
            }
            else
            {
               Print(EmojiWarning(), " Dashboard symbol switch skipped. Symbol unavailable: ", targetSymbol);
            }
         }
      }

      lastClickedSymObj = symbolRowObj;
      lastClickTimeSym = currentTime;
   }

   bool IsDashboardDragHandlePoint(const int mouseX, const int mouseY)
   {
      if(!ShowDashboard || ObjectFind(0, "Dash_BG") < 0)
         return false;

      int width = GetDashboardWidth();
      int headerHeight = S_Dash(30);
      int controlStartX = IsWorkerDashboardMode() ? S_Dash(215) : S_Dash(215);

      return (mouseX >= DashboardX &&
              mouseX <= DashboardX + width &&
              mouseY >= DashboardY &&
              mouseY <= DashboardY + headerHeight &&
              mouseX < DashboardX + controlStartX);
   }

   void HandleDashboardMouseMove(const int mouseX, const int mouseY, const int buttons)
   {
      bool leftButtonDown = ((buttons & 1) == 1);

      if(!leftButtonDown)
      {
         if(IsDragging || G_DashboardDragArmed)
         {
            IsDragging = false;
            G_DashboardDragArmed = false;
            DragInteractionX = 0;
            DragInteractionY = 0;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
            SaveFastChartSwitchDashboardState();
            ChartRedraw(0);
         }
         return;
      }

      if(!ShowDashboard || (DashboardCollapsed && ObjectFind(0, "Dash_BG") < 0))
         return;

      if(!IsDragging)
      {
         if(!G_DashboardDragArmed && !IsDashboardDragHandlePoint(mouseX, mouseY))
            return;

         IsDragging = true;
         G_DashboardDragArmed = false;
         DragInteractionX = mouseX - DashboardX;
         DragInteractionY = mouseY - DashboardY;
         G_DashboardDragStartX = DashboardX;
         G_DashboardDragStartY = DashboardY;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
      }

      int newX = MathMax(0, mouseX - DragInteractionX);
      int newY = MathMax(0, mouseY - DragInteractionY);
      if(newX == DashboardX && newY == DashboardY)
         return;

      DashboardX = newX;
      DashboardY = newY;
      MoveDashboard(DashboardX, DashboardY);
      SyncDashboardHeartbeatLayout();
      G_MasterUiPriorityUntilMs = GetTickCount() + 500;
   }

   void HandleWorkerRiskBreach(const SMbpMessage &msg)
   {
      Print("CCoordinator: Worker risk breach from " + msg.senderSymbol);
      if(m_riskEngine)
         m_riskEngine.SetEquityBlock("Worker risk breach: " + msg.dataStr);
   }

   void HandleWorkerPositionUpdate(const SMbpMessage &msg)
   {
      if(m_coordinatorQueue)
         m_coordinatorQueue.AcknowledgeById(msg.ackId);
   }
};

// Static member initialization
ulong CCoordinator::m_lastBankSaveMs = 0;
ulong CCoordinator::m_lastSyntheticPumpMs = 0;
ulong CCoordinator::m_lastDeferredHousekeepingMs = 0;

#endif
