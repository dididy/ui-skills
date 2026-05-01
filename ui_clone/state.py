"""
Pipeline state tracking for ui-clone-skills.

Reads/writes tmp/ref/<component>/pipeline-state.json.
Single source of truth for which gate the pipeline is currently at.
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

GATE_ORDER: list[str] = [
    "reference",
    "extraction",
    "bundle",
    "spec",
    "pre-generate",
    "post-implement",
    "section-compare",
]


@dataclass
class PipelineState:
    component: str = ""
    started_at: str = ""
    completed_steps: list[str] = field(default_factory=list)
    current_gate: str = "reference"
    last_updated: str = ""

    @classmethod
    def load(cls, ref_dir: Path) -> PipelineState:
        """Load state from pipeline-state.json. Returns defaults if missing or corrupt."""
        path = ref_dir / "pipeline-state.json"
        if not path.exists():
            return cls(component=ref_dir.name)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return cls(
                component=data.get("component", ref_dir.name),
                started_at=data.get("started_at", ""),
                completed_steps=data.get("completed_steps", []),
                current_gate=data.get("current_gate", "reference"),
                last_updated=data.get("last_updated", ""),
            )
        except json.JSONDecodeError:
            return cls(component=ref_dir.name)
        except OSError as exc:
            print(f"ui-re-state: Cannot read {path}: {exc}", file=sys.stderr)
            return cls(component=ref_dir.name)

    def mark_passed(self, gate: str, ref_dir: Path) -> None:
        """Record gate as passed and advance current_gate. Writes file atomically.

        Skips the write when the gate was already recorded and current_gate
        would not advance — avoids unnecessary filesystem churn on re-runs.
        """
        already_recorded = gate in self.completed_steps
        if not already_recorded:
            self.completed_steps.append(gate)

        # Compute next gate — only advance, never retreat.
        # If current_gate is already ahead of `gate` (e.g. re-running an earlier
        # step), preserve the current position instead of regressing.
        next_gate = self.current_gate
        if self.current_gate == "done":
            pass  # Terminal state — never regress
        elif gate in GATE_ORDER:
            idx = GATE_ORDER.index(gate)
            next_idx = idx + 1
            candidate = GATE_ORDER[next_idx] if next_idx < len(GATE_ORDER) else "done"
            # Only advance if candidate is strictly later than current_gate
            current_idx = (
                GATE_ORDER.index(self.current_gate) if self.current_gate in GATE_ORDER else -1
            )
            candidate_idx = (
                GATE_ORDER.index(candidate) if candidate in GATE_ORDER else len(GATE_ORDER)
            )
            if candidate_idx > current_idx:
                next_gate = candidate

        # Skip write if nothing would change
        if already_recorded and next_gate == self.current_gate:
            return

        self.current_gate = next_gate

        now = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        if not self.started_at:
            self.started_at = now
        self.last_updated = now

        path = ref_dir / "pipeline-state.json"
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(
            json.dumps(
                {
                    "component": self.component,
                    "started_at": self.started_at,
                    "completed_steps": self.completed_steps,
                    "current_gate": self.current_gate,
                    "last_updated": self.last_updated,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        tmp.replace(path)
