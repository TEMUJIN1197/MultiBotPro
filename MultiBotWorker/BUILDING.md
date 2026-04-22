# MultiBotWorker Build Notes

`accel.dll` must be built as a self-contained DLL for MetaTrader 5.

Do not ship a worker build that depends on `libc++.dll`, `libunwind.dll`, or any other external LLVM-MinGW runtime DLL beside MT5. MT5 will fail to load it with error `126`.

Supported packaging path:

```powershell
& .\MultiBotWorker\build_static_worker.ps1
```

This produces a self-contained `accel.dll` in the project root. After building, copy that DLL into:

- the workspace copy: `MQL5\Experts\MultiBotPro2\accel.dll`
- the MT5 runtime copy: `MQL5\Libraries\accel.dll`

Verification:

```powershell
& 'C:\Program Files\LLVM-MinGW\bin\llvm-readobj.exe' --coff-imports .\accel.dll
```

The output must not list `libc++.dll` or `libunwind.dll`.
