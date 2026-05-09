"""
Gate validation for ui-clone pipeline.
Replaces validate-gate.sh (594 lines of bash).

Usage:
    python -m ui_clone.gate <ref-dir> <gate> [--json]
    gate: reference | extraction | bundle | spec | pre-generate |
          post-implement | section-compare | all
Exit: 0=PASS, 1=BLOCKED, 2=usage error
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from itertools import islice
from pathlib import Path
from typing import Any, Literal

from ui_clone import dag as _dag
from ui_clone import state as _state
from ui_clone.hooks._common import GREEN as _GREEN
from ui_clone.hooks._common import NC as _NC
from ui_clone.hooks._common import RED as _RED
from ui_clone.hooks._common import YELLOW as _YELLOW
from ui_clone.hooks._common import load_json_safe as _load_json_safe

# Single source of truth: state.GATE_ORDER. Everything else (VALID_GATES,
# dispatch dict, drift validators) is derived. Adding a gate = (1) add to
# state.GATE_ORDER, (2) add a `gate_<name>` method to Gate (with `-` → `_`).
# The import-time validator below catches any miss.
VALID_GATES = list(_state.GATE_ORDER) + ["all"]


def _gate_method_name(gate: str) -> str:
    """Map gate name (kebab-case) to Gate method name (snake_case)."""
    return f"gate_{gate.replace('-', '_')}"


@dataclass
class CheckResult:
    label: str
    status: Literal["pass", "fail", "warn"]
    message: str
    fix: str = ""


class Gate:
    def __init__(self, ref_dir: Path) -> None:
        self.ref_dir = Path(ref_dir)

    # ── Primitive checks ──

    def check_file(
        self,
        path: Path,
        label: str,
        *,
        allow_empty_array: bool = False,
        fix: str = "",
    ) -> CheckResult:
        """File must exist and have > 10 bytes (or be a valid empty JSON array if allow_empty_array)."""
        if not path.exists():
            return CheckResult(label, "fail", f"{label} — MISSING", fix=fix)
        try:
            size = path.stat().st_size
        except OSError as e:
            return CheckResult(label, "fail", f"{label} — exists but unreadable ({e})", fix=fix)
        if size < 10:
            if allow_empty_array and size >= 2:
                try:
                    if json.loads(path.read_text()) == []:
                        return CheckResult(label, "pass", f"{label} (empty array — no elements found)")
                except (json.JSONDecodeError, ValueError, UnicodeDecodeError):
                    pass
            return CheckResult(label, "fail", f"{label} — exists but empty ({size} bytes)", fix=fix)
        return CheckResult(label, "pass", f"{label}")

    def check_dir(
        self,
        path: Path,
        label: str,
        min_files: int = 1,
        fix: str = "",
        pattern: str = "*",
    ) -> CheckResult:
        """Directory must exist with at least min_files files matching pattern."""
        if not path.is_dir():
            return CheckResult(label, "fail", f"{label} — MISSING directory", fix=fix)
        matched = list(islice((p for p in path.rglob(pattern) if p.is_file()), min_files))
        if len(matched) < min_files:
            return CheckResult(
                label,
                "fail",
                f"{label} \u2014 directory exists but only {len(matched)} files (need \u2265{min_files})",
            )
        return CheckResult(label, "pass", f"{label} (\u2265{min_files} files)")

    def check_json_key(self, path: Path, key: str, label: str) -> CheckResult:
        """JSON file must contain a top-level key."""
        if not path.exists():
            # File-level failure already reported by check_file; skip to avoid duplicate fail
            return CheckResult(label, "warn", f"{label} (skipped — file missing)")
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            return CheckResult(label, "fail", f"{label} — malformed JSON: {str(e)[:80]}")
        if key not in data:
            return CheckResult(label, "fail", f"{label} — JSON missing required key '{key}'")
        return CheckResult(label, "pass", f"{label} (has '{key}' key)")

    def _load_json(self, filename: str) -> dict[str, Any] | None:
        """Load a JSON artifact from ref_dir. Returns None if missing, malformed, or not an object."""
        return _load_json_safe(self.ref_dir / filename)

    # ── Gate functions ──

    def gate_reference(self) -> list[CheckResult]:
        results = []
        results.append(
            self.check_dir(
                self.ref_dir / "static" / "ref",
                "static/ref screenshots",
                min_files=5,
                fix="Run Phase 1: invoke /ui-capture <url> to capture reference screenshots",
            )
        )
        results.append(
            self.check_dir(
                self.ref_dir / "transitions" / "ref",
                "transitions/ref (transition videos)",
                min_files=1,
                fix="Run Phase 1: invoke /ui-capture <url> to capture transition videos",
            )
        )
        results.append(
            self.check_file(
                self.ref_dir / "regions.json",
                "regions.json (transition regions)",
                fix="Run Phase 1: invoke /ui-capture <url> to generate regions.json",
            )
        )
        return results

    def gate_extraction(self) -> list[CheckResult]:
        results = []
        for filename, label in [
            ("structure.json", "structure.json (DOM hierarchy)"),
            ("head.json", "head.json (metadata)"),
            ("styles.json", "styles.json (computed styles)"),
            ("fonts.json", "fonts.json (font faces)"),
            ("visible-images.json", "visible-images.json"),
            ("inline-svgs.json", "inline-svgs.json"),
            ("body-state.json", "body-state.json"),
            ("design-bundles.json", "design-bundles.json"),
        ]:
            results.append(self.check_file(self.ref_dir / filename, label))

        results.append(
            self.check_file(
                self.ref_dir / "css" / "variables.txt", "css/variables.txt (CSS custom properties)"
            )
        )

        # Viewport-scaled font em-conversion gate
        typo = self._load_json("typography.json")
        if typo:
            scaling = typo.get("scalingSystem", "")
            if scaling and any(k in scaling.lower() for k in ("viewport-scaled", "em-based")):
                results.append(
                    self.check_file(
                        self.ref_dir / "em-conversion.json",
                        f"em-conversion.json (REQUIRED: scalingSystem={scaling})",
                    )
                )

        return results

    def gate_bundle(self) -> list[CheckResult]:
        results = []
        results.append(
            self.check_dir(self.ref_dir / "bundles", "bundles/ (downloaded JS chunks)", min_files=1)
        )

        # Advisory: warn if fewer than 3 JS chunks
        bundles_dir = self.ref_dir / "bundles"
        if bundles_dir.is_dir():
            js_count = sum(1 for f in bundles_dir.rglob("*.js") if f.is_file())
            if 1 <= js_count < 3:
                results.append(
                    CheckResult(
                        "JS chunk count",
                        "warn",
                        f"Only {js_count} JS chunk(s) — typical SPAs have \u22653. "
                        "Verify all chunks via performance.getEntriesByType('resource').",
                    )
                )

        for filename, label in [
            ("interactions-detected.json", "interactions-detected.json"),
            ("scroll-engine.json", "scroll-engine.json"),
        ]:
            results.append(self.check_file(self.ref_dir / filename, label))

        return results

    # Paid-font CDN hostnames — must stay in sync with PAID_FONT_HOSTS in
    # skills/visual-debug/scripts/paid-features-detect.sh. Used both for
    # cross-validation in gate_spec and for the defensive "agent skipped
    # paid-features gate" check below.
    _PAID_FONT_CDN_HOSTS = (
        "use.typekit.net",
        "p.typekit.net",
        "use.edgefonts.net",
        "fast.fonts.net",
        "fast.fonts.com",
        "cloud.typography.com",
        "client.linotype.com",
        "mit.fontplus.jp",
        "webfont.fontplus.jp",
        "typesquare.com",
    )

    def _check_paid_font_substitution(self) -> list[CheckResult]:
        """FAIL early if any paid font is marked decision='substitute' but the
        substitution is not declared in asset-substitution.json.

        Why: 'substitute' is a promise — the agent picked a free family at 5c-c
        and font-parity will verify the swap at runtime. Without an
        asset-substitution.json fonts[] entry, font-parity FAILs much later
        (after Step 7 generation and section-compare have already run). Surfacing
        the missing declaration at spec time saves the wasted generation pass.

        Only paid-features with decision='substitute' are checked. 'use' and
        'skip' do not require asset-substitution.json. Empty findings pass.

        Also defensively flags the "agent skipped the paid-features gate" case:
        when paid-features.json is missing but extraction artifacts (fonts.json,
        head.json) contain known paid CDN hostnames, fail spec gate with a
        pointer to run paid-features-detect.sh.
        """
        results: list[CheckResult] = []
        paid = self._load_json("paid-features.json")
        if not paid:
            # Defensive: if extraction artifacts already prove paid CDNs are
            # in play, the paid-features gate should have run before spec.
            corpus = ""
            for fname in ("fonts.json", "head.json", "external-sdks.json"):
                fp = self.ref_dir / fname
                if fp.is_file():
                    try:
                        corpus += fp.read_text(encoding="utf-8")
                    except OSError:
                        pass
            hits = [h for h in self._PAID_FONT_CDN_HOSTS if h in corpus]
            if hits:
                shown = ", ".join(hits[:3]) + ("..." if len(hits) > 3 else "")
                results.append(
                    CheckResult(
                        "paid-features.json missing",
                        "fail",
                        f"Paid font CDN host(s) detected in extraction artifacts ({shown}) "
                        "but paid-features.json is missing — the `paid-features` gate has not run.",
                        fix=(
                            "Run: bash skills/visual-debug/scripts/paid-features-detect.sh "
                            "$(pwd)/tmp/ref/<component> — then re-run the `paid-features` gate "
                            "before `spec` so substitution decisions are recorded."
                        ),
                    )
                )
            return results

        substitutes = [
            item
            for item in paid.get("paidFonts", [])
            if isinstance(item, dict) and item.get("decision") == "substitute"
        ]
        if not substitutes:
            return results

        sub_path = self.ref_dir / "asset-substitution.json"
        cdns = ", ".join(str(item.get("cdn", "?")) for item in substitutes[:5]) + (
            "..." if len(substitutes) > 5 else ""
        )
        if not sub_path.is_file():
            results.append(
                CheckResult(
                    "paid-font substitution undeclared",
                    "fail",
                    f"{len(substitutes)} paid font(s) marked decision='substitute' "
                    f"({cdns}) but asset-substitution.json is missing.",
                    fix=(
                        "Write tmp/ref/<c>/asset-substitution.json with a fonts[] entry "
                        "for each substituted CDN. See ui-reverse-engineering/asset-substitution.md."
                    ),
                )
            )
            return results

        sub_data = self._load_json("asset-substitution.json")
        fonts = sub_data.get("fonts", []) if sub_data else []
        if not (isinstance(fonts, list) and len(fonts) > 0):
            results.append(
                CheckResult(
                    "paid-font substitution undeclared",
                    "fail",
                    f"asset-substitution.json exists but has no fonts[] entries — "
                    f"{len(substitutes)} paid font(s) marked decision='substitute' "
                    f"({cdns}) need declaration.",
                    fix=(
                        "Add a fonts[] entry to asset-substitution.json for each "
                        "substituted CDN. See ui-reverse-engineering/asset-substitution.md."
                    ),
                )
            )
            return results

        results.append(
            CheckResult(
                "paid-font substitution",
                "pass",
                f"{len(substitutes)} substitute decision(s) declared in asset-substitution.json",
            )
        )
        return results

    def gate_paid_features(self) -> list[CheckResult]:
        """Verify the agent has *consciously decided* what to do about paid fonts.

        Reads tmp/ref/<c>/paid-features.json (produced by paid-features-detect.sh).
        The script greps downloaded bundles + CSS for paid font CDN domains and
        writes findings with `decision: null`.

        For every entry:
          - decision == null  → FAIL (the agent has not made a choice yet)
          - decision == "use"        → PASS (license is in place; agent confirmed)
          - decision == "substitute" → PASS (using a free alternative; downstream
                                        font-parity gate enforces declaration)
          - decision == "skip"       → PASS (intentionally not replicating)

        Why early: catches expensive scope problems BEFORE Step 7 generation.
        Declaring paid-font substitution upfront avoids a section-compare loop
        that can never close (every text-bearing section reports 100% mismatch
        forever when the impl silently falls back to default sans-serif).

        Note: GSAP plugins are no longer checked — GSAP became 100% free
        following the Webflow acquisition. See paid-features-detect.sh header.
        """
        results = []
        path = self.ref_dir / "paid-features.json"
        fix_msg = (
            "Run: bash skills/visual-debug/scripts/paid-features-detect.sh "
            "$(pwd)/tmp/ref/<component>"
        )
        if not path.is_file():
            results.append(
                CheckResult(
                    "paid-features.json",
                    "fail",
                    "paid-features.json — MISSING (paid-features-detect.sh has not been run)",
                    fix=fix_msg,
                )
            )
            return results

        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            results.append(
                CheckResult(
                    "paid-features.json",
                    "fail",
                    f"paid-features.json — unreadable ({e})",
                    fix=fix_msg,
                )
            )
            return results

        if not isinstance(data, dict):
            results.append(
                CheckResult(
                    "paid-features.json",
                    "fail",
                    "paid-features.json — must be a JSON object",
                    fix=fix_msg,
                )
            )
            return results

        valid_decisions = {"use", "substitute", "skip"}
        pending: list[str] = []
        invalid: list[str] = []
        total = 0
        items = data.get("paidFonts", [])
        if isinstance(items, list):
            for item in items:
                if not isinstance(item, dict):
                    continue
                total += 1
                name = item.get("family") or item.get("cdn") or "?"
                decision = item.get("decision")
                label = f"paidFont:{name}"
                if decision is None:
                    pending.append(label)
                elif decision not in valid_decisions:
                    invalid.append(f"{label} (decision={decision!r})")

        if total == 0:
            results.append(
                CheckResult(
                    "paid-features",
                    "pass",
                    "No paid fonts detected",
                )
            )
            return results

        if invalid:
            results.append(
                CheckResult(
                    "paid-features decisions",
                    "fail",
                    f"{len(invalid)} item(s) have invalid `decision`: {', '.join(invalid[:5])}"
                    + ("..." if len(invalid) > 5 else ""),
                    fix="Set `decision` to one of: 'use', 'substitute', 'skip'",
                )
            )
            return results

        if pending:
            results.append(
                CheckResult(
                    "paid-features decisions",
                    "fail",
                    f"{len(pending)}/{total} paid item(s) have decision=null: "
                    f"{', '.join(pending[:5])}"
                    + ("..." if len(pending) > 5 else ""),
                    fix=(
                        "Edit paid-features.json — set each `decision` to one of: "
                        "'use' (you have the license), "
                        "'substitute' (using free alternative — must back with asset-substitution.json), "
                        "'skip' (intentionally not replicating). "
                        "Decide BEFORE generation to avoid wasted Step 7 work."
                    ),
                )
            )
            return results

        results.append(
            CheckResult(
                "paid-features",
                "pass",
                f"All {total} paid item(s) have a decision recorded",
            )
        )
        return results

    def gate_spec(self) -> list[CheckResult]:
        results = []
        results.append(
            self.check_file(
                self.ref_dir / "bundle-map.json",
                "bundle-map.json (Step 5d input — {} for static sites)",
            )
        )
        results.append(
            self.check_file(
                self.ref_dir / "external-sdks.json",
                "external-sdks.json (GSAP/Lenis/Framer detection — {} for no SDKs)",
            )
        )
        results.append(
            self.check_file(
                self.ref_dir / "transition-spec.json",
                "transition-spec.json (single source of truth)",
            )
        )

        # Validate transition-spec structure
        spec = self._load_json("transition-spec.json")
        if spec is not None:
            transitions = spec.get("transitions", [])
            if transitions:
                t0 = transitions[0]
                missing_keys = [k for k in ("id", "trigger", "bundle_branch") if k not in t0]
                if missing_keys:
                    results.append(
                        CheckResult(
                            "transitions[0] keys",
                            "fail",
                            f"transitions[0] missing required keys: {missing_keys}",
                        )
                    )
                else:
                    results.append(
                        CheckResult(
                            "transitions[0] keys",
                            "pass",
                            f"transitions[0] has id, trigger, bundle_branch ({len(transitions)} total)",
                        )
                    )

        # Cross-validate against paid-features decisions: any font marked
        # decision='substitute' at 5c-c MUST be declared in asset-substitution.json
        # by spec time, otherwise font-parity will FAIL after generation.
        results.extend(self._check_paid_font_substitution())

        # Capture verification frames
        verify_frames = (
            sum(1 for f in (self.ref_dir / "verify").rglob("*.png") if f.is_file())
            if (self.ref_dir / "verify").is_dir()
            else 0
        )
        if verify_frames >= 5:
            results.append(
                CheckResult(
                    "capture verification",
                    "pass",
                    f"capture verification frames ({verify_frames} frames in verify/)",
                )
            )
        else:
            results.append(
                CheckResult(
                    "capture verification",
                    "warn",
                    f"capture verification missing ({verify_frames} frames — need \u22655). "
                    "See interaction-detection.md 'MANDATORY: Capture Verification'.",
                )
            )

        return results

    # ── gate_pre_generate helpers ──

    def _check_webflow(self) -> list[CheckResult]:
        """Check Webflow IX2 artifacts when site is Webflow."""
        results = []
        webflow = self._load_json("webflow-detection.json")
        if webflow and webflow.get("isWebflow"):
            results.append(
                self.check_file(
                    self.ref_dir / "webflow-hide-rule.json",
                    "webflow-hide-rule.json (IX2 selector inventory — Step W-2)",
                )
            )
            results.append(
                self.check_file(
                    self.ref_dir / "webflow-ix2.json",
                    "webflow-ix2.json (IX2 timeline data — Step W-3)",
                )
            )
        return results

    def _check_hover_timing(
        self, interactions_data: dict[str, Any]
    ) -> tuple[list[CheckResult], bool]:
        """Check hover interaction timing and preloader. Returns (results, has_hover)."""
        results = []
        has_hover = any(
            i.get("trigger") == "hover" for i in interactions_data.get("interactions", [])
        )
        unknown_timing = [
            i
            for i in interactions_data.get("interactions", [])
            if i.get("timingSource") == "unknown"
        ]
        if unknown_timing:
            results.append(
                CheckResult(
                    "hover timing",
                    "fail",
                    f"{len(unknown_timing)} hover interactions have timingSource='unknown' "
                    "— bundle analysis must resolve",
                )
            )
        else:
            results.append(
                CheckResult("hover timing", "pass", "All hover interactions have known timing")
            )

        if interactions_data.get("hasPreloader"):
            results.append(
                self.check_file(
                    self.ref_dir / "dom-state-diff.json",
                    "dom-state-diff.json (REQUIRED: site has preloader — dual-snapshot needed)",
                )
            )
        return results, has_hover

    def _check_transition_coverage(self, spec: dict[str, Any] | None) -> list[CheckResult]:
        """Check transition-coverage.json completeness."""
        results = []
        results.append(
            self.check_file(
                self.ref_dir / "transition-coverage.json",
                "transition-coverage.json (Step 6d multi-position scroll measurement)",
            )
        )
        cov = self._load_json("transition-coverage.json")
        if cov is not None:
            animated_count = len(cov.get("animatedElements", []))
            is_static = spec is not None and len(spec.get("transitions", [])) == 0
            if animated_count > 0:
                results.append(
                    CheckResult(
                        "transition-coverage animated",
                        "pass",
                        f"transition-coverage: {animated_count} animated elements",
                    )
                )
            elif is_static:
                results.append(
                    CheckResult(
                        "transition-coverage animated",
                        "pass",
                        "transition-coverage: 0 animated elements (static site)",
                    )
                )
            else:
                results.append(
                    CheckResult(
                        "transition-coverage animated",
                        "fail",
                        "transition-coverage.json animatedElements is empty — audit incomplete",
                    )
                )
        return results

    def _check_section_counts(
        self, section_map: dict[str, Any], component_map: dict[str, Any]
    ) -> list[CheckResult]:
        """Cross-check section counts between section-map and component-map."""
        results = []
        sc = section_map.get("totalCount", len(section_map.get("sections", [])))
        cc = component_map.get("sectionCount", len(component_map.get("sections", [])))
        if sc is not None and cc is not None and sc != cc:
            results.append(
                CheckResult(
                    "section count",
                    "warn",
                    f"Section count: section-map={sc}, component-map={cc} (advisory — "
                    "OK if sections were intentionally merged/omitted)",
                )
            )
        elif sc is not None and cc is not None:
            results.append(
                CheckResult("section count", "pass", f"Section count matches ({sc} sections)")
            )

        if section_map.get("hasFooter"):
            comp_sections = component_map.get("sections", [])
            has_footer_in_map = any(
                "footer" in s.get("sourceTag", "").lower()
                or "footer" in s.get("componentName", "").lower()
                or "footer" in s.get("sourceClass", "").lower()
                for s in comp_sections
            )
            if not has_footer_in_map:
                results.append(
                    CheckResult(
                        "footer in component-map",
                        "fail",
                        "section-map.json has a <footer> but component-map.json does not include it. "
                        "Add a Footer component before generating code.",
                    )
                )
        return results

    def _check_audit_artifacts(self) -> list[CheckResult]:
        """Check that all 6c audit JSON artifacts are present."""
        results = []
        if (self.ref_dir / "section-map.json").exists():
            for filename, label in [
                ("element-roles.json", "element-roles.json"),
                ("element-groups.json", "element-groups.json"),
                ("layout-decisions.json", "layout-decisions.json"),
                ("component-map.json", "component-map.json"),
            ]:
                results.append(self.check_file(self.ref_dir / filename, label))
        return results

    # ── gate_pre_generate ──

    def gate_pre_generate(self) -> list[CheckResult]:
        results = []
        results.append(
            self.check_file(
                self.ref_dir / "extracted.json", "extracted.json (assembled extraction)"
            )
        )
        results.append(
            self.check_json_key(
                self.ref_dir / "extracted.json", "sections", "extracted.json content validation"
            )
        )
        results.append(
            self.check_file(self.ref_dir / "transition-spec.json", "transition-spec.json")
        )

        # Load once — reused across helpers below
        spec = self._load_json("transition-spec.json")

        # DAG staleness — transitive dependency check
        stale_issues = _dag.check_staleness(self.ref_dir)
        for issue in stale_issues:
            results.append(
                CheckResult(
                    f"staleness: {issue.stale}",
                    "fail" if issue.severity == "block" else "warn",
                    f"{issue.stale} — STALE (re-extracted after {issue.because_of})",
                    fix=issue.fix,
                )
            )

        for filename, label, allow_empty in [
            ("animation-init-styles.json", "animation-init-styles.json (Step 2.6)", False),
            ("section-map.json", "section-map.json (semantic section enumeration)", False),
            ("svg-text-elements.json", "svg-text-elements.json (SVG-as-text detection)", True),
        ]:
            results.append(
                self.check_file(self.ref_dir / filename, label, allow_empty_array=allow_empty)
            )

        results.append(
            self.check_file(
                self.ref_dir / "responsive" / "sizing-expressions.json",
                "sizing-expressions.json (multi-viewport element sizing)",
            )
        )

        # Viewport-scaled em check
        typo = self._load_json("typography.json")
        if typo:
            scaling = typo.get("scalingSystem", "")
            if scaling and any(k in scaling.lower() for k in ("viewport-scaled", "em-based")):
                results.append(
                    self.check_file(
                        self.ref_dir / "em-conversion.json",
                        f"em-conversion.json (REQUIRED for {scaling} sites)",
                    )
                )

        # Hover timing + preloader
        interactions_data = self._load_json("interactions-detected.json")
        has_hover = False
        if interactions_data:
            hover_results, has_hover = self._check_hover_timing(interactions_data)
            results.extend(hover_results)

        if has_hover:
            results.append(
                self.check_file(
                    self.ref_dir / "hover-css-rules.json",
                    "hover-css-rules.json (ALL :hover rules from live stylesheets)",
                )
            )
        else:
            results.append(
                CheckResult(
                    "hover-css-rules.json",
                    "pass",
                    "hover-css-rules.json (skipped — no hover interactions detected)",
                )
            )

        # Webflow IX2
        results.extend(self._check_webflow())

        # Transition coverage
        results.extend(self._check_transition_coverage(spec))

        # Section count cross-check
        section_map = self._load_json("section-map.json")
        component_map = self._load_json("component-map.json")
        if section_map and component_map:
            results.extend(self._check_section_counts(section_map, component_map))

        # Audit artifacts
        results.extend(self._check_audit_artifacts())

        return results

    def gate_post_implement(self) -> list[CheckResult]:
        results = []
        results.append(self.check_file(self.ref_dir / "extracted.json", "extracted.json"))
        results.append(
            self.check_file(self.ref_dir / "transition-spec.json", "transition-spec.json")
        )
        results.append(
            self.check_dir(self.ref_dir / "static" / "ref", "static/ref screenshots", min_files=5)
        )
        return results

    def gate_boundary(self) -> list[CheckResult]:
        """Check that breakpoint-collision-check.sh has been run and reports no collisions.

        Reads tmp/ref/<c>/responsive/boundary-collisions.json — must exist and be `[]`.
        Catches the Tailwind ↔ project @media boundary collision class
        (see diagnosis.md → Root Cause J). The bug only manifests at exactly the
        breakpoint width and Step 4-C2 measurements happen to land on those widths,
        so it never appears as a sweep change — only an isolated overflow spike.
        """
        results = []
        path = self.ref_dir / "responsive" / "boundary-collisions.json"
        fix_msg = (
            "Run: bash skills/visual-debug/scripts/breakpoint-collision-check.sh "
            "<session> <impl-url>"
        )
        if not path.is_file():
            results.append(
                CheckResult(
                    "responsive/boundary-collisions.json",
                    "fail",
                    "responsive/boundary-collisions.json — MISSING (breakpoint-collision-check.sh has not been run)",
                    fix=fix_msg,
                )
            )
            return results

        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            results.append(
                CheckResult(
                    "responsive/boundary-collisions.json",
                    "fail",
                    f"responsive/boundary-collisions.json — unreadable ({e})",
                    fix=fix_msg,
                )
            )
            return results

        if not isinstance(data, list):
            results.append(
                CheckResult(
                    "responsive/boundary-collisions.json",
                    "fail",
                    "responsive/boundary-collisions.json — must be a JSON array",
                    fix=fix_msg,
                )
            )
            return results

        if not data:
            results.append(
                CheckResult(
                    "responsive/boundary-collisions.json",
                    "pass",
                    "No breakpoint collisions detected",
                )
            )
            return results

        bp_summary = ", ".join(str(d.get("bp", "?")) for d in data if isinstance(d, dict))
        results.append(
            CheckResult(
                "boundary collisions",
                "fail",
                f"{len(data)} breakpoint collision(s) detected at: {bp_summary}. "
                "See diagnosis.md → Root Cause J for fix patterns.",
                fix=(
                    "Pick ONE side: (A) shift project @media to (max-width: <bp - 0.02>px), "
                    "or (B) bump Tailwind variant up one tier (md: → lg:). "
                    "Re-run breakpoint-collision-check.sh until the array is []."
                ),
            )
        )
        return results

    def gate_font_parity(self) -> list[CheckResult]:
        """Check that the impl loads the same font as the ref, OR that the substitution is declared.

        Reads tmp/ref/<c>/font-parity.json (produced by font-parity-check.sh).
        - parity: "match" → PASS.
        - parity: "mismatch" + asset-substitution.json with at least one font entry → PASS (declared).
        - parity: "mismatch" + no asset-substitution.json → FAIL.

        Catches the class of bug where commercial-font substitution makes section-compare
        report 100% FAIL forever because every section renders the substituted asset.
        See asset-substitution.md.
        """
        results = []
        path = self.ref_dir / "font-parity.json"
        fix_msg = (
            "Run: bash skills/visual-debug/scripts/font-parity-check.sh "
            "<session> <ref-url> <impl-url> $(pwd)/tmp/ref/<component>"
        )
        if not path.is_file():
            results.append(
                CheckResult(
                    "font-parity.json",
                    "fail",
                    "font-parity.json — MISSING (font-parity-check.sh has not been run)",
                    fix=fix_msg,
                )
            )
            return results

        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            results.append(
                CheckResult(
                    "font-parity.json",
                    "fail",
                    f"font-parity.json — unreadable ({e})",
                    fix=fix_msg,
                )
            )
            return results

        if not isinstance(data, dict):
            results.append(
                CheckResult(
                    "font-parity.json",
                    "fail",
                    "font-parity.json — must be a JSON object",
                    fix=fix_msg,
                )
            )
            return results

        parity = data.get("parity")
        ref_obj = data.get("ref") or {}
        impl_obj = data.get("impl") or {}
        if parity == "match":
            # Silent-fallback guard: ref and impl declare the same family, but the
            # impl's FontFace failed to load (paid font 404'd, expired Typekit ID,
            # CORS-blocked). computedStyle.fontFamily lies in this case — we use
            # document.fonts.check() result captured by font-parity-check.sh.
            ref_loaded = ref_obj.get("loaded", True)
            impl_loaded = impl_obj.get("loaded", True)
            family = (impl_obj.get("family") or ref_obj.get("family") or "?")
            if not ref_loaded and not impl_loaded:
                # Both sides report the FontFace is not loaded. The parity result
                # is meaningless — neither side is actually rendering the declared
                # family, so any "match" is matching two fallbacks. Could be a
                # transient network issue (re-run) or a real config bug (paid
                # font CDN unreachable from both deploys).
                results.append(
                    CheckResult(
                        "font load failure (both sides)",
                        "fail",
                        f"Both ref and impl declare '{family}' but neither has the "
                        "FontFace actually loaded — both are rendering with a fallback. "
                        "The parity 'match' is between two fallbacks, not the declared font.",
                        fix=(
                            "Re-run font-parity-check.sh with WAIT_MS bumped (slow networks "
                            "may not resolve the FontFace within 2.5s). If the failure persists, "
                            "the declared font CDN is unreachable — fix the source, or substitute "
                            "and declare via asset-substitution.json."
                        ),
                    )
                )
                return results
            if ref_loaded and not impl_loaded:
                results.append(
                    CheckResult(
                        "font load failure",
                        "fail",
                        f"Impl declares '{family}' (matches ref) but the FontFace is NOT actually loaded "
                        "— browser is silently rendering with a fallback. Likely causes: 404, CORS, "
                        "expired Typekit/Adobe Fonts ID, or missing license file in deploy.",
                        fix=(
                            "Open DevTools → Network → filter 'font' on the impl URL. "
                            "Look for failed font requests. Either: (A) fix the loading issue "
                            "(restore @font-face, add CDN auth, refresh Typekit kit ID), "
                            "or (B) intentionally substitute and declare it in asset-substitution.json."
                        ),
                    )
                )
                return results
            results.append(CheckResult("font-parity", "pass", "Ref and impl load the same primary font"))
            return results

        if parity != "mismatch":
            results.append(
                CheckResult(
                    "font-parity.json",
                    "fail",
                    f"font-parity.json — `parity` must be 'match' or 'mismatch' (got {parity!r})",
                    fix=fix_msg,
                )
            )
            return results

        # Mismatch — must be acknowledged via asset-substitution.json
        sub_path = self.ref_dir / "asset-substitution.json"
        ref_family = (data.get("ref") or {}).get("family", "?")
        impl_family = (data.get("impl") or {}).get("family", "?")
        if not sub_path.is_file():
            results.append(
                CheckResult(
                    "font substitution undeclared",
                    "fail",
                    f"Ref loads '{ref_family}' but impl loads '{impl_family}'. "
                    "If this is intentional (e.g. commercial-font replacement), declare it in "
                    "asset-substitution.json. Otherwise fix the impl to load the original font.",
                    fix=(
                        "Either: (A) fix impl to load the same font as ref, "
                        "or (B) write tmp/ref/<c>/asset-substitution.json per asset-substitution.md "
                        "with a fonts[] entry covering the substitution."
                    ),
                )
            )
            return results

        try:
            sub_data = json.loads(sub_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            results.append(
                CheckResult(
                    "asset-substitution.json",
                    "fail",
                    f"asset-substitution.json — unreadable ({e})",
                )
            )
            return results

        fonts = sub_data.get("fonts", []) if isinstance(sub_data, dict) else []
        if not (isinstance(fonts, list) and len(fonts) > 0):
            results.append(
                CheckResult(
                    "font substitution undeclared",
                    "fail",
                    f"asset-substitution.json exists but has no fonts[] entry. "
                    f"Ref loads '{ref_family}', impl loads '{impl_family}'.",
                    fix=(
                        "Add a fonts[] entry to asset-substitution.json describing the substitution, "
                        "or fix the impl to load the original font."
                    ),
                )
            )
            return results

        results.append(
            CheckResult(
                "font-parity",
                "pass",
                f"Font mismatch declared in asset-substitution.json ({ref_family} → {impl_family})",
            )
        )
        return results

    def gate_section_compare(self) -> list[CheckResult]:
        """Check that section-compare.sh has been run and all sections passed."""
        results = []
        result_file = self.ref_dir / "sections" / "result.txt"
        if not result_file.is_file():
            results.append(
                CheckResult(
                    "sections/result.txt",
                    "fail",
                    "sections/result.txt — MISSING (visual-debug/scripts/section-compare.sh has not been run)",
                    fix=(
                        f"Run: bash skills/visual-debug/scripts/section-compare.sh "
                        f"<orig-url> <impl-url> <session> {self.ref_dir}"
                    ),
                )
            )
            return results

        content = result_file.read_text(encoding="utf-8", errors="replace")
        lines = content.splitlines()
        fail_count = sum(1 for ln in lines if "❌" in ln)
        missing_count = sum(1 for ln in lines if "⚠️ MISSING impl" in ln)

        if fail_count == 0 and missing_count == 0:
            results.append(CheckResult("sections/result.txt", "pass", "All sections PASS"))
        else:
            if fail_count > 0:
                results.append(
                    CheckResult(
                        "section failures",
                        "fail",
                        f"{fail_count} section(s) FAILED — fix diffs in {self.ref_dir}/sections/diff/ "
                        "and re-run section-compare",
                    )
                )
            if missing_count > 0:
                results.append(
                    CheckResult(
                        "missing sections",
                        "fail",
                        f"{missing_count} section(s) MISSING impl — implement them and re-run section-compare",
                    )
                )

        return results

    # ── Dispatch ──

    def _make_dispatch(self) -> dict[str, Any]:
        """Build {gate_name: bound_method} from state.GATE_ORDER.

        Method names follow the convention `gate_<name>` with `-` → `_`. The
        import-time validator below ensures every gate in GATE_ORDER has a
        matching method, so getattr() here cannot raise at runtime.
        """
        return {gate: getattr(self, _gate_method_name(gate)) for gate in _state.GATE_ORDER}

    def _dispatch(self, gate: str) -> list[CheckResult]:
        dispatch = self._make_dispatch()
        if gate == "all":
            results = []
            for fn in dispatch.values():
                results.extend(fn())
            return results
        if gate not in dispatch:
            return []
        return list(dispatch[gate]())

    def _render_text(self, results: list[CheckResult]) -> None:
        for r in results:
            if r.status == "pass":
                print(f"  {_GREEN}\u2713{_NC} {r.message}")
            elif r.status == "fail":
                print(f"  {_RED}\u2717{_NC} {r.message}")
                if r.fix:
                    print(f"    \u2192 {r.fix}")
            else:  # warn
                print(f"  {_YELLOW}\u26a0{_NC}  {r.message}")

    def _render_json(self, results: list[CheckResult]) -> None:
        failures = [
            {"label": r.label, "reason": r.message, "fix": r.fix}
            for r in results
            if r.status == "fail"
        ]
        output = {
            "passed": len(failures) == 0,
            "fail_count": len(failures),
            "warn_count": sum(1 for r in results if r.status == "warn"),
            "pass_count": sum(1 for r in results if r.status == "pass"),
            "failures": failures,
        }
        print(json.dumps(output, ensure_ascii=False))

    def run(self, gate: str, json_output: bool = False) -> int:
        """Run gate checks. Returns 0=PASS, 1=BLOCKED, 2=usage error."""
        if gate not in VALID_GATES:
            if json_output:
                print(json.dumps({"error": f"Unknown gate: {gate}", "valid": VALID_GATES}))
            else:
                print(f"Unknown gate: {gate}")
                print(f"Valid gates: {' | '.join(VALID_GATES)}")
            return 2

        if not json_output:
            print(f"Gate: {gate}")

        results = self._dispatch(gate)

        if json_output:
            self._render_json(results)
        else:
            self._render_text(results)
            fail_count = sum(1 for r in results if r.status == "fail")
            total = len(results)
            print()
            if fail_count > 0:
                print(
                    f"{_RED}BLOCKED{_NC}: {fail_count}/{total} checks failed. Fix before proceeding."
                )
            else:
                print(f"{_GREEN}PASS{_NC}: {total}/{total} checks passed. May proceed.")

        passed = not any(r.status == "fail" for r in results)

        # Record gate result in pipeline-state.json (only on PASS, skip "all")
        if passed and gate != "all":
            try:
                ps = _state.PipelineState.load(self.ref_dir)
                ps.mark_passed(gate, self.ref_dir)
            except OSError:
                pass  # Non-fatal — state tracking is best-effort

        return 0 if passed else 1


# Validate at import: every gate in state.GATE_ORDER has a matching `gate_<name>`
# method on Gate. Catches drift the moment a gate is added to GATE_ORDER without
# a corresponding implementation (or vice versa), with no runtime overhead.
_missing_methods = [
    gate for gate in _state.GATE_ORDER
    if not callable(getattr(Gate, _gate_method_name(gate), None))
]
if _missing_methods:
    raise RuntimeError(
        f"Gate methods missing for state.GATE_ORDER entries: {_missing_methods}. "
        f"Expected method name: gate_<name> with '-' replaced by '_'."
    )


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="Validate ui-clone-skills pipeline gate",
        usage="python -m ui_clone.gate <ref-dir> <gate> [--json]",
    )
    parser.add_argument("ref_dir", type=Path)
    parser.add_argument("gate", choices=VALID_GATES)
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output structured JSON instead of colored text",
    )
    args = parser.parse_args()

    gate = Gate(args.ref_dir)
    sys.exit(gate.run(args.gate, json_output=args.json_output))


if __name__ == "__main__":
    main()
