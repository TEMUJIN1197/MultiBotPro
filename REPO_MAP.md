# MultiBotPro Repo Map

This repository is an MT5 Expert Advisor product bundle. Keep root-level MQL5 files
and root-level resource images in place until build automation proves relocation is
safe; MetaEditor include/resource resolution currently depends on those paths.

## Active Runtime Sources

- `MultiBotPro.mq5` is the active EA entry point.
- `hedgeBridge.mqh` is the bridge file currently included by `MultiBotPro.mq5`.
- `MultiBotPro_HedgeBridge.mqh` exists and is the preferred future canonical
  bridge name, but it is not byte-identical to `hedgeBridge.mqh`; do not switch
  includes until the differences are reconciled and compile-tested.
- `PythonApp/ShadowMaster.py` is the ShadowMaster optimizer/sentiment runtime.
- `MultiBotWorker/` contains the native C++ worker/DLL source.

## Dormant Or Partially Wired Modules

These files exist but are not directly included by `MultiBotPro.mq5` in the
current root entry point:

- `MultiBotPro_Globals.mqh`
- `MultiBotPro_Cache.mqh`
- `MultiBotPro_SignalEngine.mqh`
- `MultiBotPro_TradeManager.mqh`

Treat them as candidates for future cleanup only after include order and compile
behavior are proven. Do not delete active globals from `MultiBotPro.mq5` based on
these files alone.

## Schemas

- Runtime v3 schema behavior is implemented in `hedgeBridge.mqh` and mirrored by
  `PythonApp/init_database.py` / `extras/schema_clean.sql`.
- Root `sqlite_schema.sql` uses older table names such as `signal_queue`; treat it
  as legacy documentation until an active caller proves otherwise.
- `schemas/runtime_v3.sql` is the documentation copy for the current v3 shape.

## Generated Or Packaged Artifacts

The following are build/runtime output and should not be edited as source:

- `Output/`
- `PackageStage/`
- `build/`
- `*.ex5`
- installer `*.exe`
- SQLite `*.db`, `*.db-wal`, `*.db-shm`
- compile/runtime `*.log`
- `PythonApp/WinPython/`

## Packaging

- `build_installer.ps1`, `bundle_assets.ps1`, and `combine_assets.ps1` are existing
  packaging helpers.
- `scripts/build.ps1` is the conservative orchestration wrapper.
- `scripts/check.ps1` is the read-only health check.

## Current Hardening Rules

- Do not introduce a new `hedge_bridge` module.
- Preserve master/slave bridge semantics.
- Preserve the core signal, grid, zone, recovery, and trade-management flow.
- ShadowMaster may tune parameters in the background when enabled, but all output
  must be validated before use.
