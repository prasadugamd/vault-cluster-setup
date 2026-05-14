from __future__ import annotations

import subprocess
import os
from pathlib import Path
from typing import Any


ToolResponse = dict[str, Any]


def text_response(text: str, is_error: bool = False) -> ToolResponse:
    response: ToolResponse = {
        "content": [{"type": "text", "text": text}],
    }
    if is_error:
        response["isError"] = True
    return response


def run_shell(command: str, cwd: str | None = None, max_bytes: int = 10 * 1024 * 1024) -> tuple[str, str]:
    work_dir = str(Path(cwd).resolve()) if cwd else None

    # Prefer Bash on Linux/Unix so .sh scripts and bash-specific syntax work consistently.
    shell_executable = "/bin/bash" if os.name == "posix" and Path("/bin/bash").exists() else None

    completed = subprocess.run(
        command,
        shell=True,
        executable=shell_executable,
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
        raise RuntimeError((stderr or stdout).strip() or f"Command failed: {command}")

    return stdout, stderr
