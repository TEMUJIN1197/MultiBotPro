MultiBotPro - ShadowMaster AI Engine
====================================

ShadowMaster.exe is a self-contained PyInstaller binary.
No external Python installation is required.

The executable bundles its own Python 3.12 interpreter and required
dependencies (MetaTrader5, pandas, numpy, etc.) so it runs on Windows 10/11
without additional setup.

Launched automatically by MultiBotPro.ex5 on EA start.
Working directory: this folder (PythonApp\).
Configuration: runtime_v3.json path passed by the EA.

Runtime contract: the EA writes runtime_v3.json as the single command/config
source of truth. ShadowMaster.exe reads that JSON and writes
ShadowMasterRuntime.json plus ShadowConfig_<symbol>.json outputs in the
configured MT5 Files directory.

Do not move or rename ShadowMaster.exe - the EA resolves its path relative to
the EA's own folder (MQL5\Experts\MultiBotPro2\).
