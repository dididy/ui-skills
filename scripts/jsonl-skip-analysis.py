#!/usr/bin/env python3
"""Offline analysis of Claude Code JSONL transcripts for ui-clone-skills usage.

Counts skip events (declaration-of-done without preceding verification, sub-doc
skips, post-compact behavior change) and prints a per-session + aggregate
report. Used to surface failure modes the current enforcement hooks don't yet
catch — input for prioritising new gates / hooks.

Usage:
    uv run python scripts/jsonl-skip-analysis.py [JSONL ...]

If no JSONL paths are given, defaults to the heavy-use onpixel sessions.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

DECLARATION_RE = re.compile(
    r"\b(git\s+(?:commit|push)|gh\s+pr\s+(?:create|merge|close))\b"
)
VERIFY_RE = re.compile(
    r"(ui_clone\.gate|section-compare|auto-verify|visual-debug|"
    r"auto-diagnose|transition-compare|video-transition-compare|frame-pair-compare)"
)
SUBDOC_RE = re.compile(r"skills/(ui-reverse-engineering|ui-capture|visual-debug)/[^/]+\.md")
GATE_INVOKE_RE = re.compile(r"python\s+-m\s+ui_clone\.(?:gate|pipeline)")
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
COMPONENT_PATH_RE = re.compile(r"\.(tsx|jsx|ts|js|css|scss|svelte|vue)$")


@dataclass
class Event:
    idx: int
    kind: str                 # 'tool', 'result', 'compact', 'hook'
    name: str = ""
    cmd: str = ""             # Bash command
    file_path: str = ""       # Edit/Read target
    is_error: bool = False
    raw: dict | None = None


@dataclass
class SessionReport:
    path: Path
    turns: int = 0
    compacts: int = 0
    tool_counts: Counter = field(default_factory=Counter)
    declarations: list[Event] = field(default_factory=list)
    verifications: list[Event] = field(default_factory=list)
    subdoc_reads: list[Event] = field(default_factory=list)
    component_edits: list[Event] = field(default_factory=list)
    gate_invocations: list[Event] = field(default_factory=list)
    skip_events: list[dict] = field(default_factory=list)


def iter_events(path: Path):
    idx = 0
    with path.open() as fp:
        for line in fp:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            t = obj.get("type")
            if t == "system":
                sub = obj.get("subtype")
                if sub == "compact_boundary":
                    yield Event(idx=idx, kind="compact")
                elif sub == "stop_hook_summary":
                    yield Event(idx=idx, kind="hook", raw=obj)
                idx += 1
                continue
            if t == "assistant":
                msg = obj.get("message", {})
                for c in msg.get("content", []) or []:
                    if c.get("type") == "tool_use":
                        name = c.get("name", "")
                        inp = c.get("input", {}) or {}
                        cmd = inp.get("command", "") if name == "Bash" else ""
                        fp_path = inp.get("file_path", "") or inp.get("path", "")
                        yield Event(idx=idx, kind="tool", name=name, cmd=cmd, file_path=fp_path, raw=c)
                idx += 1
                continue
            if t == "user":
                msg = obj.get("message", {})
                content = msg.get("content", []) or []
                if isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "tool_result":
                            yield Event(idx=idx, kind="result", is_error=bool(c.get("is_error")))
                idx += 1
                continue
            idx += 1


def analyse(path: Path) -> SessionReport:
    rep = SessionReport(path=path)
    last_verify_idx = -10**9
    last_subdoc_idx = -10**9
    declarations_pre_compact = 0
    declarations_post_compact = 0
    skips_pre = 0
    skips_post = 0
    last_compact_idx = -1

    for ev in iter_events(path):
        rep.turns = max(rep.turns, ev.idx)
        if ev.kind == "compact":
            rep.compacts += 1
            last_compact_idx = ev.idx
            continue
        if ev.kind != "tool":
            continue

        rep.tool_counts[ev.name] += 1

        if ev.name == "Bash" and ev.cmd:
            if VERIFY_RE.search(ev.cmd):
                rep.verifications.append(ev)
                last_verify_idx = ev.idx
            if GATE_INVOKE_RE.search(ev.cmd):
                rep.gate_invocations.append(ev)
            if DECLARATION_RE.search(ev.cmd):
                rep.declarations.append(ev)
                gap = ev.idx - last_verify_idx
                # "skip" heuristic: declared done with no verification in prior 200 events
                if gap > 200:
                    rep.skip_events.append({
                        "kind": "declaration_without_verify",
                        "idx": ev.idx,
                        "gap": gap,
                        "cmd": ev.cmd[:120],
                        "post_compact": last_compact_idx > 0 and ev.idx - last_compact_idx < 200,
                    })
                    if last_compact_idx > 0 and ev.idx - last_compact_idx < 200:
                        skips_post += 1
                    else:
                        skips_pre += 1
                if last_compact_idx > 0:
                    declarations_post_compact += 1
                else:
                    declarations_pre_compact += 1

        if ev.name == "Read" and ev.file_path:
            if SUBDOC_RE.search(ev.file_path):
                rep.subdoc_reads.append(ev)
                last_subdoc_idx = ev.idx

        if ev.name in EDIT_TOOLS and ev.file_path:
            if COMPONENT_PATH_RE.search(ev.file_path) and "/skills/" not in ev.file_path:
                rep.component_edits.append(ev)
                # sub-doc-skip heuristic: edit a component without reading any sub-doc in prior 100 events.
                # Skip the "no sub-doc ever read" case (last_subdoc_idx still sentinel) — that's a separate
                # signal handled by tracking total sub-doc reads. Only count gaps between actual reads.
                if last_subdoc_idx > 0 and ev.idx - last_subdoc_idx > 100:
                    prev = rep.skip_events[-1] if rep.skip_events else None
                    if not (prev and prev.get("kind") == "edit_without_subdoc" and ev.idx - prev["idx"] < 50):
                        rep.skip_events.append({
                            "kind": "edit_without_subdoc",
                            "idx": ev.idx,
                            "gap": ev.idx - last_subdoc_idx,
                            "file": ev.file_path,
                            "post_compact": last_compact_idx > 0 and ev.idx - last_compact_idx < 100,
                        })

    rep.skip_events.append({"kind": "summary", "skips_pre": skips_pre, "skips_post": skips_post,
                             "decls_pre": declarations_pre_compact, "decls_post": declarations_post_compact})
    return rep


def fmt_session(rep: SessionReport) -> str:
    lines = []
    lines.append(f"\n=== {rep.path.name} ({rep.turns} turns, {rep.compacts} compacts) ===")
    top_tools = ", ".join(f"{n}={c}" for n, c in rep.tool_counts.most_common(8))
    lines.append(f"  tools: {top_tools}")
    lines.append(f"  declarations (commit/push/PR): {len(rep.declarations)}")
    lines.append(f"  verifications (gate/visual-debug): {len(rep.verifications)}")
    lines.append(f"  sub-doc reads: {len(rep.subdoc_reads)}")
    lines.append(f"  component edits: {len(rep.component_edits)}")
    lines.append(f"  gate invocations: {len(rep.gate_invocations)}")

    by_kind = Counter(s.get("kind") for s in rep.skip_events if s.get("kind") != "summary")
    if by_kind:
        lines.append(f"  skip events: {dict(by_kind)}")

    summary = next((s for s in rep.skip_events if s.get("kind") == "summary"), {})
    if summary:
        lines.append(
            f"  pre-compact decls: {summary.get('decls_pre',0)} / skips {summary.get('skips_pre',0)}; "
            f"post-compact decls: {summary.get('decls_post',0)} / skips {summary.get('skips_post',0)}"
        )

    samples = [s for s in rep.skip_events if s.get("kind") != "summary"][:5]
    for s in samples:
        if s["kind"] == "declaration_without_verify":
            lines.append(f"    ! decl@{s['idx']} (gap={s['gap']}, post_compact={s['post_compact']}): {s['cmd']}")
        elif s["kind"] == "edit_without_subdoc":
            lines.append(f"    ! edit@{s['idx']} (gap={s['gap']}, post_compact={s['post_compact']}): {s['file']}")
    return "\n".join(lines)


def is_plugin_active(rep: SessionReport) -> bool:
    """Filter to sessions where ui-clone-skills was actually invoked.

    Heuristic: at least one gate invocation OR sub-doc read OR verification call.
    Sessions that just edit files in the project without using the plugin are
    out-of-scope for skip-rate analysis (the plugin correctly stays silent).
    """
    return bool(rep.gate_invocations or rep.subdoc_reads or rep.verifications)


def fmt_aggregate(reports: list[SessionReport]) -> str:
    total_decls = sum(len(r.declarations) for r in reports)
    total_verifs = sum(len(r.verifications) for r in reports)
    total_edits = sum(len(r.component_edits) for r in reports)
    total_subdoc = sum(len(r.subdoc_reads) for r in reports)
    total_compacts = sum(r.compacts for r in reports)
    decl_skip = sum(1 for r in reports for s in r.skip_events if s.get("kind") == "declaration_without_verify")
    edit_skip = sum(1 for r in reports for s in r.skip_events if s.get("kind") == "edit_without_subdoc")

    pre_skip = sum(s.get("skips_pre", 0) for r in reports for s in r.skip_events if s.get("kind") == "summary")
    post_skip = sum(s.get("skips_post", 0) for r in reports for s in r.skip_events if s.get("kind") == "summary")

    lines = ["", "=== AGGREGATE ==="]
    lines.append(f"  sessions: {len(reports)}")
    lines.append(f"  total compacts: {total_compacts}")
    lines.append(f"  declarations / verifications / edits / sub-doc reads: {total_decls} / {total_verifs} / {total_edits} / {total_subdoc}")
    lines.append(f"  declaration_without_verify events: {decl_skip}")
    lines.append(f"  edit_without_subdoc events: {edit_skip}")
    lines.append(f"  decl_skip pre-compact / post-compact: {pre_skip} / {post_skip}")
    if total_decls:
        lines.append(f"  declaration skip rate: {decl_skip}/{total_decls} = {100*decl_skip/total_decls:.1f}%")
    if total_edits:
        lines.append(f"  edit-without-subdoc rate: {edit_skip}/{total_edits} = {100*edit_skip/total_edits:.1f}%")
    return "\n".join(lines)


def default_paths() -> list[Path]:
    base = Path.home() / ".claude/projects/-Users-yongjae-Documents-onpixel"
    if not base.is_dir():
        return []
    by_uses = []
    declaration_re = re.compile(r"ui-reverse-engineering|ui_clone\.gate|tmp/ref/")
    for p in base.glob("*.jsonl"):
        try:
            text = p.read_text(errors="replace")
        except OSError:
            continue
        n = len(declaration_re.findall(text))
        if n >= 50:
            by_uses.append((n, p))
    by_uses.sort(reverse=True)
    return [p for _, p in by_uses]


def main(argv: list[str]) -> int:
    if argv:
        paths = [Path(a) for a in argv]
    else:
        paths = default_paths()
    if not paths:
        print("No JSONL transcripts found.", file=sys.stderr)
        return 1
    reports = [analyse(p) for p in paths]
    plugin_active = [r for r in reports if is_plugin_active(r)]
    skipped = [r for r in reports if not is_plugin_active(r)]
    for r in plugin_active:
        print(fmt_session(r))
    if skipped:
        print(f"\n[Excluded {len(skipped)} non-plugin sessions: " +
              ", ".join(r.path.name[:8] for r in skipped) + "]")
    print(fmt_aggregate(plugin_active))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
