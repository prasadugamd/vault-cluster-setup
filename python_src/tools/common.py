from __future__ import annotations

import os
import re
import subprocess  # nosec B404 - used only with argv lists and shell=False
from pathlib import Path
from typing import Any, Sequence


ToolResponse = dict[str, Any]

# Blocks shell metacharacters while allowing typical k8s, helm, hostname, and file names.
_SAFE_IDENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$")
_UNSEAL_KEY = re.compile(r"^[A-Za-z0-9+/=_-]{1,4096}$")


def text_response(text: str, is_error: bool = False) -> ToolResponse:
    response: ToolResponse = {
        "content": [{"type": "text", "text": text}],
    }
    if is_error:
        response["isError"] = True
    return response


def require_ident(value: str | None, field: str) -> str:
    if not isinstance(value, str) or not _SAFE_IDENT.fullmatch(value):
        raise ValueError(f"Invalid {field}")
    return value


def require_filename(value: str | None, field: str = "file") -> str:
    if not isinstance(value, str) or not _SAFE_IDENT.fullmatch(value) or ".." in value:
        raise ValueError(f"Invalid {field}")
    return value


def require_unseal_key(value: str | None) -> str:
    if not isinstance(value, str) or not _UNSEAL_KEY.fullmatch(value):
        raise ValueError("Invalid unseal key")
    return value


def run_command(
    argv: Sequence[str],
    cwd: str | None = None,
    max_bytes: int = 10 * 1024 * 1024,
) -> tuple[str, str]:
    if not argv:
        raise ValueError("Command must include at least one argument")

    command = [str(part) for part in argv]
    if any(part == "" for part in command):
        raise ValueError("Command arguments must not be empty")

    work_dir = str(Path(cwd).resolve()) if cwd else None

    # Invoke .sh scripts with bash as argv[0] so no shell is required.
    if command[0].endswith(".sh") and os.name == "posix" and Path("/bin/bash").exists():
        command = ["/bin/bash", *command]

    completed = subprocess.run(  # nosec B603 - argv list, shell=False
        command,
        shell=False,
        cwd=work_dir,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    stdout = completed.stdout or ""
    stderr = completed.stderr or ""

    if len(stdout.encode("utf-8")) > max_bytes:
        stdout = stdout[: max_bytes // 2] + "\n... (output truncated) ..."
    if len(stderr.encode("utf-8")) > max_bytes:
        stderr = stderr[: max_bytes // 2] + "\n... (output truncated) ..."

    if completed.returncode != 0:
        raise RuntimeError((stderr or stdout).strip() or f"Command failed: {command[0]}")

    return stdout, stderr
