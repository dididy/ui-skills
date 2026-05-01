"""
Shared utilities for ui_clone hook modules.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

# ── ANSI colors (shared across pipeline/gate/hooks) ──

GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
RED = "\033[0;31m"
BOLD = "\033[1m"
NC = "\033[0m"


def _plugin_root() -> Path:
    """Return the ui-clone-skills plugin root (the directory containing pyproject.toml).

    Priority:
    1. $CLAUDE_PLUGIN_ROOT env var (set by Claude Code hooks)
    2. Walk up from this file's location looking for pyproject.toml
    """
    env_root = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    if env_root and (Path(env_root) / "pyproject.toml").is_file():
        return Path(env_root)
    cur = Path(__file__).resolve()
    while cur != cur.parent:
        if (cur / "pyproject.toml").is_file():
            return cur
        cur = cur.parent
    raise FileNotFoundError(
        "Cannot find ui-clone-skills plugin root. "
        "Set CLAUDE_PLUGIN_ROOT or run from within the plugin directory."
    )


_cached_project_root: Path | None = None


def find_project_root() -> Path:
    """Discover project root.

    Priority:
    1. $CLAUDE_PROJECT_DIR env var
    2. git rev-parse --show-toplevel (cached per process to avoid repeated subprocess calls)
    3. Walk up from cwd looking for tmp/ref/
    4. cwd fallback
    """
    global _cached_project_root

    env_root = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if env_root and Path(env_root).is_dir():
        return Path(env_root)

    if _cached_project_root is not None:
        return _cached_project_root

    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            git_root = Path(result.stdout.strip())
            # Verify this git root actually contains tmp/ref/ — guards nested-repo
            # setups where the monorepo parent is the git root, not the project dir.
            if (git_root / "tmp" / "ref").is_dir():
                _cached_project_root = git_root
                return git_root
    except FileNotFoundError:
        pass

    cwd = Path.cwd()
    cur = cwd
    while cur != cur.parent:
        if (cur / "tmp" / "ref").is_dir():
            _cached_project_root = cur
            return cur
        cur = cur.parent

    _cached_project_root = cwd
    return cwd


def find_ref_dir(search_root: Path) -> Path | None:
    """Find ref dir: prefer WIP marker, fall back to newest extracted.json mtime."""
    if not search_root.is_dir():
        return None

    # 1. WIP marker
    for d in sorted(search_root.iterdir()):
        if not d.is_dir():
            continue
        if (d / ".ui-re-active").is_file():
            return d

    # 2. mtime fallback — only refs with extracted.json
    newest_time = 0.0
    newest_dir: Path | None = None
    for d in sorted(search_root.iterdir()):
        if not d.is_dir():
            continue
        extracted = d / "extracted.json"
        if not extracted.is_file():
            continue
        mtime = extracted.stat().st_mtime
        if mtime > newest_time:
            newest_time = mtime
            newest_dir = d

    return newest_dir


def load_json_safe(path: Path) -> dict[str, Any] | None:
    """Load a JSON file and return it as a dict. Returns None if missing, malformed, or not an object."""
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    if not isinstance(data, dict):
        return None
    return data


def run_gate(ref_dir: Path, gate_name: str) -> dict[str, object]:
    """Run `uv run python -m ui_clone.gate <ref_dir> <gate_name> --json` as a subprocess.

    Uses `uv run` to guarantee execution inside the ui-clone-skills virtual environment
    (with scikit-image, Pillow installed). Falls back to sys.executable if uv is
    not available, which will fail-open with a warning if dependencies are missing.

    Returns parsed JSON dict from gate output.
    Falls back to {"passed": True} if gate script not found (fail-open).
    """
    uv = shutil.which("uv")
    if uv:
        cmd = [
            uv,
            "run",
            "--project",
            str(_plugin_root()),
            "python",
            "-m",
            "ui_clone.gate",
            str(ref_dir),
            gate_name,
            "--json",
        ]
    else:
        print("ui-re-gate: WARNING: uv not found, falling back to sys.executable", file=sys.stderr)
        cmd = [sys.executable, "-m", "ui_clone.gate", str(ref_dir), gate_name, "--json"]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )
        raw = result.stdout.strip()
        if raw:
            data: dict[str, object] = json.loads(raw)
            return data
        if result.returncode != 0:
            return {
                "passed": False,
                "fail_count": 1,
                "failures": [
                    {
                        "label": gate_name,
                        "reason": result.stderr.strip() or "gate failed",
                        "fix": "",
                    }
                ],
            }
    except (FileNotFoundError, json.JSONDecodeError, subprocess.TimeoutExpired) as exc:
        print(f"ui-re-gate: WARNING: gate not runnable: {exc}", file=sys.stderr)
    return {"passed": True, "fail_count": 0, "failures": []}
