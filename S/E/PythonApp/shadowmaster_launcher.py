import os
import subprocess
import sys


def _program_dir() -> str:
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


def _resolve_python(program_dir: str) -> str:
    candidates = (
        os.path.join(program_dir, "WinPython", "pythonw.exe"),
        os.path.join(program_dir, "WinPython", "python.exe"),
        os.path.join(program_dir, "pythonw.exe"),
        os.path.join(program_dir, "python.exe"),
    )

    for candidate in candidates:
        if os.path.exists(candidate):
            return candidate

    return sys.executable


def main() -> int:
    program_dir = _program_dir()
    python_exe = _resolve_python(program_dir)
    script_path = os.path.join(program_dir, "ShadowMaster.py")

    if not os.path.exists(script_path):
        return 2

    command = [python_exe, script_path]
    if len(sys.argv) > 1:
        command.extend(sys.argv[1:])

    creationflags = 0
    if hasattr(subprocess, "DETACHED_PROCESS"):
        creationflags |= subprocess.DETACHED_PROCESS
    if hasattr(subprocess, "CREATE_NO_WINDOW"):
        creationflags |= subprocess.CREATE_NO_WINDOW

    subprocess.Popen(
        command,
        cwd=program_dir,
        close_fds=False,
        creationflags=creationflags,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
