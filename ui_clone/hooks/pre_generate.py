"""
Pre-generation check hook for ui-reverse-engineering.
Blocks Write/Edit on component files when extraction pipeline is incomplete.

Usage: python -m ui_clone.hooks.pre_generate
Reads PreToolUse JSON from stdin.
Exit 0 = allow; exit 0 with JSON on stdout = block.

Environment variables:
    UI_RE_COMPONENT_PATHS  — colon-separated list of path substrings to enforce
                             (overrides the built-in defaults)
    Example: UI_RE_COMPONENT_PATHS=/src/components/:/app/components/:/src/pages/
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import cast

from ui_clone.hooks._common import find_project_root as _find_project_root
from ui_clone.hooks._common import find_ref_dir as _find_ref_dir
from ui_clone.hooks._common import run_gate as _run_gate_common

# ── Is this a component/page file? ──

# Built-in default patterns (substring match, except page.* which uses segment logic)
_DEFAULT_COMPONENT_SUBSTRINGS = ["/src/components/", "/src/projects/"]
_DEFAULT_APP_PREFIX = "/src/app/"


def _is_component_file(file_path: str) -> bool:
    """Return True for component/page files that the pre-generate gate should enforce.

    Default enforced paths:
    - /src/components/**       — all component files
    - /src/projects/**/        — project-scoped component trees
    - /src/app/**/page.*       — Next.js App Router page files only
                                 (layout.tsx, route.ts etc. are excluded)

    Override via UI_RE_COMPONENT_PATHS env var (colon-separated substrings):
        UI_RE_COMPONENT_PATHS=/src/components/:/app/components/
    """
    custom = os.environ.get("UI_RE_COMPONENT_PATHS", "").strip()
    if custom:
        return any(p in file_path for p in custom.split(":") if p)

    if any(sub in file_path for sub in _DEFAULT_COMPONENT_SUBSTRINGS):
        return True
    if _DEFAULT_APP_PREFIX in file_path:
        return any(seg.startswith("page.") for seg in file_path.split("/"))
    return False


def _run_gate(ref_dir: Path) -> dict[str, object]:
    return _run_gate_common(ref_dir, "pre-generate")


# ── Emit block JSON ──


def _emit_block(reason: str) -> None:
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(payload, ensure_ascii=False))


# ── Main ──


def main() -> None:
    # Read tool input from stdin
    raw_input = sys.stdin.read() if not sys.stdin.isatty() else ""
    file_path = ""
    if raw_input.strip():
        try:
            data = json.loads(raw_input)
            # Support both flat {"file_path": ...} and nested {"tool_input": {"file_path": ...}}
            file_path = data.get("tool_input", {}).get("file_path", "") or data.get("file_path", "")
        except json.JSONDecodeError:
            pass

    # Only enforce on component/page files
    if not _is_component_file(file_path):
        sys.exit(0)

    # Derive project root from the file being edited when possible.
    # This prevents cross-project ref dir pollution (e.g., editing
    # navercorp-clone/src/... but hook finds kurlynmart/tmp/ref/).
    project_root = None
    if file_path:
        fp = Path(file_path).resolve()
        # Walk up from file path looking for tmp/ref/
        cur = fp.parent
        while cur != cur.parent:
            if (cur / "tmp" / "ref").is_dir():
                project_root = cur
                break
            cur = cur.parent
    if project_root is None:
        project_root = _find_project_root()

    search_root = project_root / "tmp" / "ref"
    ref_dir = _find_ref_dir(search_root)

    # No ref dir → not a ui-re project
    if ref_dir is None:
        sys.exit(0)

    # Check if WIP marker exists (only proceed if active)
    marker = ref_dir / ".ui-re-active"
    if not marker.is_file():
        # No active marker — skip
        sys.exit(0)

    # Run pre-generate gate
    gate_result = _run_gate(ref_dir)

    if not gate_result.get("passed", True):
        failures: list[dict[str, str]] = cast(list[dict[str, str]], gate_result.get("failures", []))
        fail_count = cast(int, gate_result.get("fail_count", len(failures)))
        if failures:
            missing_list = ", ".join(f["label"] for f in failures[:8])
            reason = (
                f"UI Reverse Engineering: extraction incomplete "
                f"({fail_count} artifacts missing). Missing: {missing_list}. "
                f"Complete Phase 2 before writing components."
            )
        else:
            reason = (
                "UI Reverse Engineering: pre-generate gate FAILED. "
                "Run: python -m ui_clone.gate tmp/ref/<component> pre-generate"
            )
        _emit_block(reason)
        sys.exit(0)

    # Gate passed — refresh the existing WIP marker timestamp (proves liveness).
    # marker.is_file() was confirmed at line 119; touch may still race with
    # section_gate stale cleanup, so catch OSError.
    try:
        marker.touch()
        print(
            "⚑  UI-RE Stop gate ACTIVATED: section-compare must pass before finishing.",
            file=sys.stderr,
        )
    except OSError:
        pass

    sys.exit(0)


if __name__ == "__main__":
    main()
