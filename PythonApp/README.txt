# Python Environment Setup

The installer deployed this folder structure correctly (`PythonApp\WinPython`).
However, embedding a massive 1.5GB full WinPython environment natively into our EA's installer script would severely slow down installation and inflate the .exe file unnecessarily for users who don't even use the AI.

**To enable the AI integration:**
1. Download a "WinPython" portable distribution (e.g. WinPython 3.10) from SourceForge or Github.
2. Extract the contents fully so that `python.exe` is located at `PythonApp\WinPython\python.exe`.
3. Launch MultiBotPro on the MT5 Chart. The bot will automatically detect this `python.exe` and execute `ShadowMaster.py` gracefully in the background.
