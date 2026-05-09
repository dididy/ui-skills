"""Tests for ui_clone.state — pipeline-state.json read/write."""

import json

from ui_clone.state import GATE_ORDER, PipelineState

# ── GATE_ORDER ──


def test_gate_order_contains_all_gates():
    expected = [
        "reference",
        "extraction",
        "bundle",
        "paid-features",
        "spec",
        "pre-generate",
        "post-implement",
        "boundary",
        "font-parity",
        "section-compare",
    ]
    assert GATE_ORDER == expected


# ── PipelineState.load ──


def test_load_missing_file_returns_defaults(tmp_path):
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    state = PipelineState.load(ref_dir)
    assert state.current_gate == "reference"
    assert state.completed_steps == []


def test_load_existing_file(tmp_path):
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    data = {
        "component": "Comp",
        "started_at": "2026-01-01T00:00:00Z",
        "completed_steps": ["reference", "extraction"],
        "current_gate": "bundle",
        "last_updated": "2026-01-01T01:00:00Z",
    }
    (ref_dir / "pipeline-state.json").write_text(json.dumps(data))
    state = PipelineState.load(ref_dir)
    assert state.current_gate == "bundle"
    assert state.completed_steps == ["reference", "extraction"]


def test_load_corrupted_json_returns_defaults(tmp_path):
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    (ref_dir / "pipeline-state.json").write_text("not json{{{")
    state = PipelineState.load(ref_dir)
    assert state.current_gate == "reference"


# ── PipelineState.mark_passed ──


def test_mark_passed_advances_current_gate(tmp_path):
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    state = PipelineState.load(ref_dir)
    state.mark_passed("reference", ref_dir)
    reloaded = PipelineState.load(ref_dir)
    assert "reference" in reloaded.completed_steps
    assert reloaded.current_gate == "extraction"


def test_mark_passed_idempotent(tmp_path):
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    state = PipelineState.load(ref_dir)
    state.mark_passed("reference", ref_dir)
    state2 = PipelineState.load(ref_dir)
    state2.mark_passed("reference", ref_dir)
    state3 = PipelineState.load(ref_dir)
    assert state3.completed_steps.count("reference") == 1


def test_mark_passed_last_gate_sets_done(tmp_path):
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    data = {
        "component": "Comp",
        "started_at": "2026-01-01T00:00:00Z",
        "completed_steps": list(GATE_ORDER[:-1]),
        "current_gate": "section-compare",
        "last_updated": "2026-01-01T01:00:00Z",
    }
    (ref_dir / "pipeline-state.json").write_text(json.dumps(data))
    state = PipelineState.load(ref_dir)
    state.mark_passed("section-compare", ref_dir)
    reloaded = PipelineState.load(ref_dir)
    assert reloaded.current_gate == "done"
    assert "section-compare" in reloaded.completed_steps


def test_mark_passed_writes_file(tmp_path):
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    state = PipelineState.load(ref_dir)
    state.mark_passed("reference", ref_dir)
    assert (ref_dir / "pipeline-state.json").exists()
    data = json.loads((ref_dir / "pipeline-state.json").read_text())
    assert data["current_gate"] == "extraction"


def test_mark_passed_does_not_regress_gate(tmp_path):
    """Calling mark_passed on an earlier gate must not move current_gate backwards.

    Regression test for: out-of-order mark_passed() regressing current_gate.
    """
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    # Advance to "bundle"
    state = PipelineState.load(ref_dir)
    state.mark_passed("reference", ref_dir)
    state = PipelineState.load(ref_dir)
    state.mark_passed("extraction", ref_dir)
    state = PipelineState.load(ref_dir)
    assert state.current_gate == "bundle"

    # Re-run an earlier gate (e.g. reference re-checked)
    state.mark_passed("reference", ref_dir)
    reloaded = PipelineState.load(ref_dir)
    # Must stay at "bundle", not regress to "extraction"
    assert reloaded.current_gate == "bundle"


def test_mark_passed_does_not_regress_from_done(tmp_path):
    """current_gate='done' must not be overwritten by mark_passed on any gate."""
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    data = {
        "component": "Comp",
        "started_at": "2026-01-01T00:00:00Z",
        "completed_steps": list(GATE_ORDER),
        "current_gate": "done",
        "last_updated": "2026-01-01T02:00:00Z",
    }
    (ref_dir / "pipeline-state.json").write_text(json.dumps(data))
    state = PipelineState.load(ref_dir)
    # Re-mark an earlier gate — must not regress from "done"
    state.mark_passed("reference", ref_dir)
    reloaded = PipelineState.load(ref_dir)
    assert reloaded.current_gate == "done"


# ── PipelineState.demote_to ──


def test_demote_to_from_done_moves_back_to_section_compare(tmp_path):
    """When state is 'done', demote_to('section-compare') retreats current_gate
    and removes section-compare from completed_steps."""
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    data = {
        "component": "Comp",
        "started_at": "2026-01-01T00:00:00Z",
        "completed_steps": list(GATE_ORDER),
        "current_gate": "done",
        "last_updated": "2026-01-01T02:00:00Z",
    }
    (ref_dir / "pipeline-state.json").write_text(json.dumps(data))
    state = PipelineState.load(ref_dir)
    state.demote_to("section-compare", ref_dir)
    reloaded = PipelineState.load(ref_dir)
    assert reloaded.current_gate == "section-compare"
    assert "section-compare" not in reloaded.completed_steps
    # Earlier gates remain completed
    assert "post-implement" in reloaded.completed_steps
    assert "pre-generate" in reloaded.completed_steps


def test_demote_to_does_not_advance(tmp_path):
    """demote_to must never move current_gate forward — only backward or stay."""
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    state = PipelineState.load(ref_dir)
    # Currently at "reference" — demote_to("section-compare") must not advance
    state.demote_to("section-compare", ref_dir)
    reloaded = PipelineState.load(ref_dir)
    assert reloaded.current_gate == "reference"


def test_demote_to_unknown_gate_is_noop(tmp_path):
    """demote_to with a gate not in GATE_ORDER → no state change."""
    ref_dir = tmp_path / "comp"
    ref_dir.mkdir()
    data = {
        "component": "Comp",
        "started_at": "2026-01-01T00:00:00Z",
        "completed_steps": list(GATE_ORDER),
        "current_gate": "done",
        "last_updated": "2026-01-01T02:00:00Z",
    }
    (ref_dir / "pipeline-state.json").write_text(json.dumps(data))
    state = PipelineState.load(ref_dir)
    state.demote_to("nonexistent-gate", ref_dir)
    reloaded = PipelineState.load(ref_dir)
    assert reloaded.current_gate == "done"
