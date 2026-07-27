"""Small newline-delimited JSON bridge for Modly process extensions."""
from __future__ import annotations

import json
import sys
from typing import NoReturn


try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass


def emit(data: dict) -> None:
    try:
        print(json.dumps(data, ensure_ascii=False), flush=True)
    except BrokenPipeError:
        # Modly closes stdout when a workflow is cancelled.
        raise SystemExit(0)


def log(message: str) -> None:
    emit({"type": "log", "message": str(message)})


def progress(percent: int, label: str = "") -> None:
    emit({
        "type": "progress",
        "percent": max(0, min(100, int(percent))),
        "label": str(label),
    })


def done(file_path: str, stats: dict | None = None) -> NoReturn:
    result: dict = {"filePath": str(file_path)}
    if stats is not None:
        result["stats"] = stats
    emit({"type": "done", "result": result})
    raise SystemExit(0)


def error(message: str) -> NoReturn:
    emit({"type": "error", "message": str(message)})
    raise SystemExit(1)


def parse_bool(value: object, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    return str(value).strip().lower() not in {
        "", "false", "0", "no", "off", "null", "none",
    }
