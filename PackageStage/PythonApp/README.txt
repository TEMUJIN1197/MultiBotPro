MultiBotPro – ShadowMaster AI Engine
======================================

ShadowMaster.exe is a self-contained PyInstaller binary.
No external Python installation is required.

The executable bundles its own Python 3.12 interpreter and all
required dependencies (MetaTrader5, pandas, pandas_ta, schedule, etc.)
so it runs on any Windows 10/11 machine without additional setup.

Launched automatically by MultiBotPro.ex5 on EA start.
Working directory: this folder (PythonApp\).
Configuration:    ..\runtime_v3.json  (or as passed on the command line).

Do not move or rename ShadowMaster.exe — the EA resolves its path
relative to the EA's own folder (MQL5\Experts\MultiBotPro2\).
