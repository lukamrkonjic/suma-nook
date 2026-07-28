"""Provision an isolated runtime for Mesh Polish."""
from __future__ import annotations

import json
import os
import platform
import subprocess
import sys
from pathlib import Path


def extension_python(venv_dir: Path) -> Path:
    if platform.system() == "Windows":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def run(command: list[str]) -> None:
    subprocess.check_call(command)


def main() -> None:
    if len(sys.argv) >= 2:
        setup_args = json.loads(sys.argv[1])
    else:
        setup_args = {
            "python_exe": os.environ.get("MODLY_PYTHON_EXE", sys.executable),
            "ext_dir": os.environ.get(
                "MODLY_EXTENSION_DIR",
                str(Path(__file__).resolve().parent),
            ),
        }

    source_python = Path(setup_args["python_exe"])
    extension_dir = Path(
        setup_args.get("ext_dir", Path(__file__).resolve().parent)
    )
    venv_dir = extension_dir / "venv"
    requirements = extension_dir / "requirements.txt"

    print(f"[setup] Mesh Polish: {extension_dir}", flush=True)
    run([
        str(source_python), "-m", "venv", "--upgrade-deps", str(venv_dir),
    ])
    python = extension_python(venv_dir)
    run([
        str(python), "-m", "pip", "install", "--upgrade",
        "pip", "wheel", "--quiet",
    ])
    run([
        str(python), "-m", "pip", "install",
        "-r", str(requirements), "--quiet",
    ])
    run([
        str(python), "-c",
        "import numpy, trimesh, pymeshlab; "
        "print('[setup] numpy/trimesh/pymeshlab imports OK')",
    ])
    print("[setup] Setup complete.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[setup] Error: {exc}", flush=True)
        raise SystemExit(1)
