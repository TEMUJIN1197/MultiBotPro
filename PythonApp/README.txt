# Python Environment Setup

The installer deployed this folder structure correctly (`PythonApp\WinPython`).
However, embedding a massive full WinPython environment natively into the EA installer would severely slow down installation and inflate the package for users who do not use the AI runtime.

The current ShadowMaster backend supports OpenAI's Responses API with `gpt-5.5` for sentiment and risk gating, while keeping the existing RSS and external-sentiment fallbacks.

**To enable the AI integration:**
1. Download a portable Python distribution so that `python.exe` exists at `PythonApp\WinPython\python.exe`.
2. Set `OPENAI_API_KEY` before launching MT5 if you want GPT-5.5 sentiment analysis enabled.
3. Optionally set `OPENAI_MODEL` (default `gpt-5.5`), `OPENAI_REASONING_EFFORT` (default `low`), `OPENAI_PROJECT`, `OPENAI_ORG_ID`, or `OPENAI_BASE_URL`.
4. Use `runtime_v3.openai.sample.json` as a reference if you want explicit OpenAI runtime settings in the generated config.
5. Launch MultiBotPro on the MT5 chart. The bot will detect `python.exe`, start `ShadowMaster.py`, and fall back to the local RSS/external sentiment providers if OpenAI is unavailable.
