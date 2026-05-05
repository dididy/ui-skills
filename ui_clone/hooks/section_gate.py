"""
Stop hook — blocks Claude response based on current pipeline gate.

Reads pipeline-state.json to determine which gate to enforce.
If pipeline-state.json is absent, defaults to reference gate (fresh start).

Activation: only fires when a .ui-re-active marker exists in tmp/ref/*/.

Usage: python -m ui_clone.hooks.section_gate
Outputs {"decision": "block", "reason": "..."} to stdout to block, or exits 0 to allow.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import cast

from ui_clone.hooks._common import find_project_root as _find_project_root
from ui_clone.hooks._common import run_gate as _run_gate
from ui_clone.state import GATE_ORDER, PipelineState

_DEFAULT_STALE_DAYS = 3


def _get_stale_seconds() -> float:
    """Return stale threshold in seconds. Overridable via UI_RE_STALE_DAYS env var."""
    try:
        days = float(os.environ.get("UI_RE_STALE_DAYS", _DEFAULT_STALE_DAYS))
    except (ValueError, TypeError):
        days = _DEFAULT_STALE_DAYS
    return days * 24 * 3600


def _find_active_markers(search_root: Path) -> list[Path]:
    """Return list of ref dirs that have a .ui-re-active marker."""
    if not search_root.is_dir():
        return []
    return [
        d for d in sorted(search_root.iterdir()) if d.is_dir() and (d / ".ui-re-active").is_file()
    ]


def _emit_block(reason: str) -> None:
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


def _block_reason_for_gate(gate_name: str, ref_dir: Path, gate_result: dict[str, object]) -> str:
    failures: list[dict[str, str]] = cast(list[dict[str, str]], gate_result.get("failures", []))
    fail_count = cast(int, gate_result.get("fail_count", len(failures)))
    missing_list = "\n  - ".join(f["label"] for f in failures[:10])
    return (
        f"⛔ UI-RE Gate: {gate_name} BLOCKED\n\n"
        f"Incomplete items ({fail_count}):\n  - {missing_list}\n\n"
        f"Run:\n"
        f"  python -m ui_clone.gate {ref_dir} {gate_name}\n"
        f"  → After passing, run python -m ui_clone.pipeline ... status to see the next step"
    )


def main() -> None:
    project_root = _find_project_root()
    search_root = project_root / "tmp" / "ref"

    active_dirs = _find_active_markers(search_root)
    if not active_dirs:
        sys.exit(0)

    # Stale marker guard
    ref_dir = active_dirs[0]
    marker = ref_dir / ".ui-re-active"
    try:
        age = time.time() - marker.stat().st_mtime
    except OSError:
        sys.exit(0)
    if age >= _get_stale_seconds():
        age_days = int(age // 86400)
        print(
            f"ui-clone-skills: Stale WIP marker ({age_days}d) at {marker} — removing.", file=sys.stderr
        )
        try:
            marker.unlink()
        except OSError:
            pass
        active_dirs = _find_active_markers(search_root)
        if not active_dirs:
            sys.exit(0)
        ref_dir = active_dirs[0]

    if len(active_dirs) > 1:
        print(
            f"ui-clone-skills: WARNING: {len(active_dirs)} concurrent WIP markers. Enforcing: {ref_dir}",
            file=sys.stderr,
        )

    # Load current gate from pipeline-state.json.
    # If absent, treat as fresh start at "reference" gate (not legacy section-compare fallback).
    state = PipelineState.load(ref_dir)
    current_gate = state.current_gate

    # Terminal state — all gates done, allow
    if current_gate == "done":
        sys.exit(0)

    # section-compare is handled via Gate (same logic as python -m ui_clone.gate ... section-compare)
    if current_gate == "section-compare":
        gate_result = _run_gate(ref_dir, "section-compare")
        if not gate_result.get("passed", True):
            failures: list[dict[str, str]] = cast(
                list[dict[str, str]], gate_result.get("failures", [])
            )
            fail_count = cast(int, gate_result.get("fail_count", len(failures)))
            parts = [f"⛔ UI-RE Gate: section-compare FAILED ({fail_count} issue(s))."]
            for f in failures[:5]:
                parts.append(f"  • {f['label']}: {f['reason']}")
                if f.get("fix"):
                    parts.append(f"    → {f['fix']}")
            parts.append("\nAll sections must PASS before finishing.")
            _emit_block("\n".join(parts))
            sys.exit(0)
        # Gate passed — _run_gate subprocess already recorded state via Gate.run().
        # Reload state to verify it was persisted before removing the WIP marker.
        updated_state = PipelineState.load(ref_dir)
        if "section-compare" in updated_state.completed_steps:
            try:
                marker.unlink()
            except OSError:
                pass
        sys.exit(0)

    # For all other gates, run the Python gate
    if current_gate not in GATE_ORDER:
        # Unknown gate — allow (fail-open)
        sys.exit(0)

    gate_result = _run_gate(ref_dir, current_gate)
    if not gate_result.get("passed", True):
        _emit_block(_block_reason_for_gate(current_gate, ref_dir, gate_result))

    sys.exit(0)


if __name__ == "__main__":
    main()
