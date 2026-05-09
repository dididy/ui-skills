import json
from pathlib import Path

from ui_clone import state as _state
from ui_clone.gate import VALID_GATES, Gate


def test_dispatch_matches_gate_order(tmp_path: Path):
    """_make_dispatch() must return exactly the gates declared in state.GATE_ORDER.

    state.GATE_ORDER is the single source of truth. dispatch is auto-derived
    via getattr; this test guards against accidental method-name typos / missing
    methods that the import-time validator already catches but is cheap to
    re-assert at the unit-test layer."""
    gate = Gate(tmp_path)
    assert list(gate._make_dispatch().keys()) == list(_state.GATE_ORDER)


def test_valid_gates_derives_from_gate_order():
    """VALID_GATES must equal GATE_ORDER + ['all'] — no manual list to drift."""
    assert VALID_GATES == list(_state.GATE_ORDER) + ["all"]


# ── check_file ──


def test_check_file_pass(ref_dir_with_artifacts: Path):
    gate = Gate(ref_dir_with_artifacts)
    result = gate.check_file(ref_dir_with_artifacts / "structure.json", "structure.json")
    assert result.status == "pass"


def test_check_file_missing(tmp_path: Path):
    ref = tmp_path / "ref"
    ref.mkdir()
    gate = Gate(ref)
    result = gate.check_file(ref / "missing.json", "missing.json")
    assert result.status == "fail"
    assert "MISSING" in result.message


def test_check_file_empty(tmp_path: Path):
    ref = tmp_path / "ref"
    ref.mkdir()
    empty = ref / "empty.json"
    empty.write_bytes(b"")
    gate = Gate(ref)
    result = gate.check_file(empty, "empty.json")
    assert result.status == "fail"
    assert "empty" in result.message.lower()


def test_check_dir_pass(ref_dir_with_artifacts: Path):
    gate = Gate(ref_dir_with_artifacts)
    result = gate.check_dir(ref_dir_with_artifacts / "static" / "ref", "screenshots", min_files=5)
    assert result.status == "pass"


def test_check_dir_missing(tmp_path: Path):
    ref = tmp_path / "ref"
    ref.mkdir()
    gate = Gate(ref)
    result = gate.check_dir(ref / "nonexistent", "dir", min_files=1)
    assert result.status == "fail"


def test_check_dir_too_few_files(tmp_path: Path):
    ref = tmp_path / "ref"
    ref.mkdir()
    d = ref / "screenshots"
    d.mkdir()
    (d / "only_one.png").write_bytes(b"PNG")
    gate = Gate(ref)
    result = gate.check_dir(d, "screenshots", min_files=5)
    assert result.status == "fail"
    assert "1" in result.message


def test_check_json_key_pass(tmp_path: Path):
    ref = tmp_path / "ref"
    ref.mkdir()
    f = ref / "extracted.json"
    f.write_text(json.dumps({"sections": [], "url": "https://example.com"}))
    gate = Gate(ref)
    result = gate.check_json_key(f, "sections", "extracted.json has sections")
    assert result.status == "pass"


def test_check_json_key_missing_key(tmp_path: Path):
    ref = tmp_path / "ref"
    ref.mkdir()
    f = ref / "extracted.json"
    f.write_text(json.dumps({"url": "https://example.com"}))
    gate = Gate(ref)
    result = gate.check_json_key(f, "sections", "extracted.json has sections")
    assert result.status == "fail"
    assert "sections" in result.message


def test_check_json_key_malformed(tmp_path: Path):
    ref = tmp_path / "ref"
    ref.mkdir()
    f = ref / "bad.json"
    f.write_text("{not valid json")
    gate = Gate(ref)
    result = gate.check_json_key(f, "sections", "bad.json")
    assert result.status == "fail"
    assert "malformed" in result.message.lower()


# ── gate_reference ──


def test_gate_reference_pass(ref_dir_with_artifacts: Path):
    gate = Gate(ref_dir_with_artifacts)
    results = gate.gate_reference()
    failures = [r for r in results if r.status == "fail"]
    assert failures == [], f"Unexpected failures: {failures}"


def test_gate_reference_fail_no_screenshots(tmp_path: Path):
    ref = tmp_path / "ref"
    ref.mkdir()
    gate = Gate(ref)
    results = gate.gate_reference()
    failures = [r for r in results if r.status == "fail"]
    assert len(failures) > 0


def test_gate_reference_fail_no_transitions_ref(tmp_path: Path):
    """gate_reference must fail when transitions/ref/ is missing (SKILL.md Phase 1 gate)."""
    ref = tmp_path / "ref"
    ref.mkdir()
    # Has screenshots but no transitions/ref/
    screenshots = ref / "static" / "ref"
    screenshots.mkdir(parents=True)
    for i in range(5):
        (screenshots / f"scroll_{i:02d}.png").write_bytes(b"\x89PNG" + b"\x00" * 100)
    (ref / "regions.json").write_text('{"regions": []}')

    gate = Gate(ref)
    results = gate.gate_reference()
    failures = [r for r in results if r.status == "fail"]
    assert any("transitions" in r.label or "transitions" in r.message for r in failures), (
        "Missing transitions/ref/ must produce a fail result"
    )


def test_gate_reference_pass_with_transitions_ref(tmp_path: Path):
    """gate_reference must pass when all three Phase 1 artifacts exist."""
    ref = tmp_path / "ref"
    ref.mkdir()
    screenshots = ref / "static" / "ref"
    screenshots.mkdir(parents=True)
    for i in range(5):
        (screenshots / f"scroll_{i:02d}.png").write_bytes(b"\x89PNG" + b"\x00" * 100)
    transitions = ref / "transitions" / "ref"
    transitions.mkdir(parents=True)
    (transitions / "scroll.webm").write_bytes(b"\x1aE\xdf\xa3" + b"\x00" * 100)
    (ref / "regions.json").write_text('{"regions": []}')

    gate = Gate(ref)
    results = gate.gate_reference()
    failures = [r for r in results if r.status == "fail"]
    assert failures == [], f"Unexpected failures: {failures}"


# ── run() exit codes ──


def test_run_returns_0_on_pass(ref_dir_with_artifacts: Path):
    gate = Gate(ref_dir_with_artifacts)
    code = gate.run("reference")
    assert code == 0


def test_run_returns_1_on_fail(tmp_path: Path):
    ref = tmp_path / "ref"
    ref.mkdir()
    gate = Gate(ref)
    code = gate.run("reference")
    assert code == 1


def test_run_returns_2_on_unknown_gate(ref_dir_with_artifacts: Path):
    gate = Gate(ref_dir_with_artifacts)
    code = gate.run("nonexistent-gate")
    assert code == 2


# ── JSON output ──


def test_json_output_structure(ref_dir_with_artifacts: Path, capsys):
    gate = Gate(ref_dir_with_artifacts)
    gate.run("reference", json_output=True)
    captured = capsys.readouterr()
    data = json.loads(captured.out)
    assert "passed" in data
    assert "fail_count" in data
    assert "failures" in data
    assert isinstance(data["failures"], list)


# ── pipeline-state.json recording ──


def test_run_gate_pass_writes_pipeline_state(ref_dir_with_artifacts: Path):
    """Gate PASS: pipeline-state.json is created and the gate is recorded."""
    from ui_clone.state import PipelineState

    gate = Gate(ref_dir_with_artifacts)
    exit_code = gate.run("reference", json_output=True)
    assert exit_code == 0
    state = PipelineState.load(ref_dir_with_artifacts)
    assert "reference" in state.completed_steps
    assert state.current_gate == "extraction"


def test_run_gate_fail_does_not_write_pipeline_state(tmp_path: Path):
    """Gate FAIL: pipeline-state.json is not written."""
    ref = tmp_path / "ref"
    ref.mkdir()
    gate = Gate(ref)
    exit_code = gate.run("reference", json_output=True)
    assert exit_code == 1
    assert not (ref / "pipeline-state.json").exists()


# ── gate_pre_generate — footer check ──


def test_gate_pre_generate_blocks_when_footer_missing_from_component_map(tmp_path: Path):
    """section-map has hasFooter=True but component-map has no footer entry → fail."""
    ref = tmp_path / "ref"
    ref.mkdir()

    # Minimal artifacts required by gate_pre_generate
    (ref / "extracted.json").write_text(json.dumps({"sections": [], "url": "https://example.com"}))
    (ref / "transition-spec.json").write_text(json.dumps({"transitions": []}))
    (ref / "animation-init-styles.json").write_text(json.dumps({}))
    (ref / "svg-text-elements.json").write_text(json.dumps([]))
    responsive = ref / "responsive"
    responsive.mkdir()
    (responsive / "sizing-expressions.json").write_text(json.dumps({}))
    (ref / "interactions-detected.json").write_text(
        json.dumps({"interactions": [], "hasPreloader": False})
    )
    (ref / "hover-css-rules.json").write_text(json.dumps([]))
    (ref / "transition-coverage.json").write_text(
        json.dumps({"animatedElements": [], "staticElements": []})
    )
    (ref / "element-roles.json").write_text(json.dumps({}))
    (ref / "element-groups.json").write_text(json.dumps({}))
    (ref / "layout-decisions.json").write_text(json.dumps({}))

    # section-map has a <footer>
    (ref / "section-map.json").write_text(
        json.dumps(
            {
                "sections": [{"tag": "main"}],
                "totalCount": 1,
                "hasFooter": True,
            }
        )
    )
    # component-map has NO footer entry
    (ref / "component-map.json").write_text(
        json.dumps(
            {
                "sections": [{"componentName": "HeroSection", "sourceTag": "main"}],
                "sectionCount": 1,
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_pre_generate()
    footer_failures = [r for r in results if r.status == "fail" and "footer" in r.message.lower()]
    assert footer_failures, "Missing footer in component-map must produce a fail result"


# ── gate_pre_generate — hover timing unknown ──


def test_gate_pre_generate_fails_when_hover_timing_unknown(tmp_path: Path):
    """interactions with timingSource='unknown' must cause gate failure."""
    ref = tmp_path / "ref"
    ref.mkdir()

    (ref / "extracted.json").write_text(json.dumps({"sections": [], "url": "https://example.com"}))
    (ref / "transition-spec.json").write_text(json.dumps({"transitions": []}))
    (ref / "animation-init-styles.json").write_text(json.dumps({}))
    (ref / "svg-text-elements.json").write_text(json.dumps([]))
    responsive = ref / "responsive"
    responsive.mkdir()
    (responsive / "sizing-expressions.json").write_text(json.dumps({}))
    (ref / "hover-css-rules.json").write_text(json.dumps([]))
    (ref / "transition-coverage.json").write_text(
        json.dumps({"animatedElements": [], "staticElements": []})
    )
    (ref / "element-roles.json").write_text(json.dumps({}))
    (ref / "element-groups.json").write_text(json.dumps({}))
    (ref / "layout-decisions.json").write_text(json.dumps({}))
    (ref / "section-map.json").write_text(
        json.dumps({"sections": [], "totalCount": 0, "hasFooter": False})
    )
    (ref / "component-map.json").write_text(json.dumps({"sections": [], "sectionCount": 0}))
    # interactions with timingSource='unknown'
    (ref / "interactions-detected.json").write_text(
        json.dumps(
            {
                "interactions": [
                    {"trigger": "hover", "timingSource": "unknown", "selector": ".btn"},
                ],
                "hasPreloader": False,
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_pre_generate()
    timing_failures = [r for r in results if r.status == "fail" and "unknown" in r.message.lower()]
    assert timing_failures, "timingSource='unknown' must produce a fail result"


# ── gate_extraction must NOT require Step 6d artifacts ──


def test_gate_extraction_does_not_require_transition_coverage(tmp_path: Path):
    """gate_extraction must pass without transition-coverage.json.

    transition-coverage.json is produced at Step 6d, after bundle (5c) and spec (5d).
    Requiring it at the extraction gate (which runs after Step 2-3) would deadlock
    the pipeline — extraction can never advance until 6d, but 6d depends on bundle,
    which depends on extraction having passed. Coverage of transition-coverage.json
    belongs to gate_pre_generate (see test_gate_pre_generate_*).
    """
    ref = tmp_path / "ref"
    ref.mkdir()
    for fname in [
        "structure.json",
        "head.json",
        "styles.json",
        "fonts.json",
        "visible-images.json",
        "inline-svgs.json",
        "body-state.json",
        "design-bundles.json",
    ]:
        (ref / fname).write_text(json.dumps({}))
    css_dir = ref / "css"
    css_dir.mkdir()
    (css_dir / "variables.txt").write_text(":root {}")
    # transition-coverage.json intentionally omitted

    gate = Gate(ref)
    results = gate.gate_extraction()
    failures = [r for r in results if r.status == "fail"]
    labels = [r.label for r in failures]
    assert not any("transition-coverage" in lbl for lbl in labels), (
        "gate_extraction must not require transition-coverage.json (Step 6d artifact)"
    )


# ── gate_bundle ──


def test_gate_bundle_fails_when_no_js_files(tmp_path: Path):
    """gate_bundle must fail when bundles/ directory has no JS files."""
    ref = tmp_path / "ref"
    ref.mkdir()
    bundles = ref / "bundles"
    bundles.mkdir()
    # No JS files

    gate = Gate(ref)
    results = gate.gate_bundle()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "Empty bundles/ must produce a fail result"


def test_gate_bundle_fails_when_required_json_missing(tmp_path: Path):
    """gate_bundle must fail when interactions-detected.json is missing."""
    ref = tmp_path / "ref"
    ref.mkdir()
    bundles = ref / "bundles"
    bundles.mkdir()
    (bundles / "chunk-0.js").write_text("// bundle")
    # interactions-detected.json, scroll-engine.json, external-sdks.json intentionally absent

    gate = Gate(ref)
    results = gate.gate_bundle()
    failures = [r for r in results if r.status == "fail"]
    assert any(
        "interactions-detected" in r.label or "interactions-detected" in r.message for r in failures
    ), "Missing interactions-detected.json must produce a fail"


def test_gate_bundle_passes_with_required_files(tmp_path: Path):
    """gate_bundle must pass when bundles/ has JS files and all required JSON files exist."""
    ref = tmp_path / "ref"
    ref.mkdir()
    bundles = ref / "bundles"
    bundles.mkdir()
    for i in range(3):
        (bundles / f"chunk-{i}.js").write_text("// bundle")
    (ref / "interactions-detected.json").write_text(
        json.dumps({"interactions": [], "hasPreloader": False})
    )
    (ref / "scroll-engine.json").write_text(json.dumps({"engine": "native"}))
    (ref / "external-sdks.json").write_text(json.dumps({"sdks": [], "gsap": False}))

    gate = Gate(ref)
    results = gate.gate_bundle()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"gate_bundle must pass with required files: {failures}"


# ── gate_spec ──


def test_gate_spec_fails_when_transition_spec_missing(tmp_path: Path):
    """gate_spec must fail when transition-spec.json is absent."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "bundle-map.json").write_text(json.dumps({"chunks": ["a.js"]}))
    # transition-spec.json intentionally absent

    gate = Gate(ref)
    results = gate.gate_spec()
    failures = [r for r in results if r.status == "fail"]
    assert any("transition-spec" in r.label or "transition-spec" in r.message for r in failures), (
        "Missing transition-spec.json must produce a fail"
    )


def test_gate_spec_fails_when_bundle_map_missing(tmp_path: Path):
    """gate_spec must fail when bundle-map.json is absent."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "transition-spec.json").write_text(json.dumps({"transitions": []}))
    # bundle-map.json intentionally absent

    gate = Gate(ref)
    results = gate.gate_spec()
    failures = [r for r in results if r.status == "fail"]
    assert any("bundle-map" in r.label or "bundle-map" in r.message for r in failures), (
        "Missing bundle-map.json must produce a fail"
    )


def test_gate_spec_passes_with_required_files(tmp_path: Path):
    """gate_spec must pass when bundle-map.json, transition-spec.json, and external-sdks.json exist."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "bundle-map.json").write_text(json.dumps({"chunks": ["a.js"]}))
    (ref / "transition-spec.json").write_text(json.dumps({"transitions": []}))
    (ref / "external-sdks.json").write_text(json.dumps({"sdks": []}))
    verify = ref / "verify"
    verify.mkdir()
    for i in range(5):
        (verify / f"frame_{i:02d}.png").write_bytes(b"\x89PNG" + b"\x00" * 100)

    gate = Gate(ref)
    results = gate.gate_spec()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"gate_spec must pass with required files present: {failures}"


# ── gate_post_implement ──


def test_gate_post_implement_fails_when_extracted_missing(tmp_path: Path):
    """gate_post_implement must fail when extracted.json is absent."""
    ref = tmp_path / "ref"
    ref.mkdir()

    gate = Gate(ref)
    results = gate.gate_post_implement()
    failures = [r for r in results if r.status == "fail"]
    assert any("extracted" in r.label or "extracted" in r.message for r in failures), (
        "Missing extracted.json must produce a fail in gate_post_implement"
    )


def test_gate_post_implement_passes_with_required_files(tmp_path: Path):
    """gate_post_implement must pass when extracted.json, transition-spec.json, and screenshots exist."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "extracted.json").write_text(json.dumps({"sections": [], "url": "https://example.com"}))
    (ref / "transition-spec.json").write_text(json.dumps({"transitions": []}))
    screenshots = ref / "static" / "ref"
    screenshots.mkdir(parents=True)
    for i in range(5):
        (screenshots / f"scroll_{i:02d}.png").write_bytes(b"\x89PNG" + b"\x00" * 100)

    gate = Gate(ref)
    results = gate.gate_post_implement()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"gate_post_implement must pass with required files present: {failures}"


# ── gate_boundary ──


def test_gate_boundary_fails_when_artifact_missing(tmp_path: Path):
    """gate_boundary must fail when responsive/boundary-collisions.json is absent."""
    ref = tmp_path / "ref"
    ref.mkdir()

    gate = Gate(ref)
    results = gate.gate_boundary()
    failures = [r for r in results if r.status == "fail"]
    assert any("boundary-collisions.json" in r.message for r in failures), (
        "Missing boundary-collisions.json must produce a fail in gate_boundary"
    )


def test_gate_boundary_passes_when_array_empty(tmp_path: Path):
    """gate_boundary must pass when the artifact exists and is `[]` (no collisions)."""
    ref = tmp_path / "ref"
    (ref / "responsive").mkdir(parents=True)
    (ref / "responsive" / "boundary-collisions.json").write_text("[]")

    gate = Gate(ref)
    results = gate.gate_boundary()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"empty array must pass gate_boundary: {failures}"
    assert any("No breakpoint collisions" in r.message for r in results)


def test_gate_boundary_fails_when_collisions_present(tmp_path: Path):
    """gate_boundary must fail when the array has at least one finding."""
    ref = tmp_path / "ref"
    (ref / "responsive").mkdir(parents=True)
    (ref / "responsive" / "boundary-collisions.json").write_text(
        json.dumps([{"bp": 768, "reasons": ["isolated overflow spike"]}])
    )

    gate = Gate(ref)
    results = gate.gate_boundary()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "non-empty boundary-collisions.json must fail gate_boundary"
    assert any("768" in r.message for r in failures)


def test_gate_boundary_fails_when_artifact_invalid_json(tmp_path: Path):
    """gate_boundary must fail when the artifact is not valid JSON."""
    ref = tmp_path / "ref"
    (ref / "responsive").mkdir(parents=True)
    (ref / "responsive" / "boundary-collisions.json").write_text("{not json")

    gate = Gate(ref)
    results = gate.gate_boundary()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "invalid JSON must fail gate_boundary"


def test_gate_boundary_fails_when_artifact_not_array(tmp_path: Path):
    """gate_boundary must fail when the artifact is JSON but not an array."""
    ref = tmp_path / "ref"
    (ref / "responsive").mkdir(parents=True)
    (ref / "responsive" / "boundary-collisions.json").write_text('{"bp": 768}')

    gate = Gate(ref)
    results = gate.gate_boundary()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "non-array JSON must fail gate_boundary"


# ── gate_font_parity ──


def test_gate_font_parity_fails_when_artifact_missing(tmp_path: Path):
    """gate_font_parity must fail when font-parity.json is absent."""
    ref = tmp_path / "ref"
    ref.mkdir()

    gate = Gate(ref)
    results = gate.gate_font_parity()
    failures = [r for r in results if r.status == "fail"]
    assert any("font-parity.json" in r.message for r in failures), (
        "Missing font-parity.json must fail gate_font_parity"
    )


def test_gate_font_parity_passes_when_match(tmp_path: Path):
    """gate_font_parity must pass when parity is 'match'."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "font-parity.json").write_text(
        json.dumps(
            {"ref": {"family": "Inter"}, "impl": {"family": "Inter"}, "parity": "match"}
        )
    )

    gate = Gate(ref)
    results = gate.gate_font_parity()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"match must pass: {failures}"


def test_gate_font_parity_fails_when_mismatch_undeclared(tmp_path: Path):
    """gate_font_parity must fail when parity is 'mismatch' and asset-substitution.json is absent."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "font-parity.json").write_text(
        json.dumps(
            {"ref": {"family": "Exat"}, "impl": {"family": "Roboto Flex"}, "parity": "mismatch"}
        )
    )

    gate = Gate(ref)
    results = gate.gate_font_parity()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "undeclared mismatch must fail"
    assert any("Exat" in r.message and "Roboto Flex" in r.message for r in failures)


def test_gate_font_parity_passes_when_mismatch_declared(tmp_path: Path):
    """gate_font_parity must pass when mismatch is declared in asset-substitution.json."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "font-parity.json").write_text(
        json.dumps(
            {"ref": {"family": "Exat"}, "impl": {"family": "Roboto Flex"}, "parity": "mismatch"}
        )
    )
    (ref / "asset-substitution.json").write_text(
        json.dumps(
            {
                "fonts": [
                    {"original": "Exat", "replacement": "Roboto Flex", "reason": "license"}
                ],
                "structuralOnlySections": ["*"],
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_font_parity()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"declared mismatch must pass: {failures}"


def test_gate_font_parity_fails_when_substitution_has_empty_fonts(tmp_path: Path):
    """gate_font_parity must fail when asset-substitution.json exists but fonts[] is empty."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "font-parity.json").write_text(
        json.dumps(
            {"ref": {"family": "Exat"}, "impl": {"family": "Roboto Flex"}, "parity": "mismatch"}
        )
    )
    (ref / "asset-substitution.json").write_text(json.dumps({"fonts": [], "images": []}))

    gate = Gate(ref)
    results = gate.gate_font_parity()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "empty fonts[] must still fail"


def test_gate_font_parity_fails_when_impl_declared_but_not_loaded(tmp_path: Path):
    """gate_font_parity must catch the silent-fallback case: same family declared but impl FontFace failed to load."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "font-parity.json").write_text(
        json.dumps(
            {
                "ref": {"family": "Exat", "loaded": True},
                "impl": {"family": "Exat", "loaded": False},
                "parity": "match",
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_font_parity()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "match parity but impl unloaded must fail"
    assert any("NOT actually loaded" in r.message or "not actually loaded" in r.message.lower() for r in failures)


def test_gate_font_parity_passes_when_both_loaded(tmp_path: Path):
    """gate_font_parity must pass when both ref and impl have loaded:true."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "font-parity.json").write_text(
        json.dumps(
            {
                "ref": {"family": "Inter", "loaded": True},
                "impl": {"family": "Inter", "loaded": True},
                "parity": "match",
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_font_parity()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"both loaded must pass: {failures}"


def test_gate_font_parity_passes_when_loaded_field_missing(tmp_path: Path):
    """Backward compat: older font-parity.json without `loaded` field still passes on match."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "font-parity.json").write_text(
        json.dumps(
            {"ref": {"family": "Inter"}, "impl": {"family": "Inter"}, "parity": "match"}
        )
    )

    gate = Gate(ref)
    results = gate.gate_font_parity()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, "missing loaded field defaults to True (backward compat)"


def test_gate_font_parity_fails_when_invalid_parity_value(tmp_path: Path):
    """gate_font_parity must fail when `parity` is not 'match' or 'mismatch'."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "font-parity.json").write_text(json.dumps({"parity": "unknown"}))

    gate = Gate(ref)
    results = gate.gate_font_parity()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "unknown parity value must fail"


# ── gate_paid_features ──


def test_gate_paid_features_fails_when_artifact_missing(tmp_path: Path):
    """gate_paid_features must fail when paid-features.json is absent."""
    ref = tmp_path / "ref"
    ref.mkdir()

    gate = Gate(ref)
    results = gate.gate_paid_features()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "Missing paid-features.json must fail gate_paid_features"
    assert any("paid-features.json" in r.message for r in failures)


def test_gate_paid_features_passes_when_no_findings(tmp_path: Path):
    """gate_paid_features must pass when paidFonts is empty."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "paid-features.json").write_text(json.dumps({"paidFonts": []}))

    gate = Gate(ref)
    results = gate.gate_paid_features()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"empty findings must pass: {failures}"


def test_gate_paid_features_fails_when_decision_is_null(tmp_path: Path):
    """gate_paid_features must fail when any paid font has decision=null."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "paid-features.json").write_text(
        json.dumps(
            {
                "paidFonts": [
                    {
                        "family": None,
                        "cdn": "use.typekit.net",
                        "evidence": "css/main.css:1",
                        "decision": None,
                    }
                ],
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_paid_features()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "decision=null must fail"
    assert any("use.typekit.net" in r.message for r in failures)


def test_gate_paid_features_passes_when_decisions_set(tmp_path: Path):
    """gate_paid_features must pass once every paid font has a valid decision."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "paid-features.json").write_text(
        json.dumps(
            {
                "paidFonts": [
                    {
                        "family": None,
                        "cdn": "use.typekit.net",
                        "evidence": "css/main.css:1",
                        "decision": "substitute",
                    },
                    {
                        "family": None,
                        "cdn": "fast.fonts.net",
                        "evidence": "head.json:1",
                        "decision": "use",
                    },
                ],
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_paid_features()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"valid decisions must pass: {failures}"


def test_gate_paid_features_fails_when_decision_invalid(tmp_path: Path):
    """gate_paid_features must fail when decision is not in {use, substitute, skip}."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "paid-features.json").write_text(
        json.dumps(
            {
                "paidFonts": [
                    {
                        "family": None,
                        "cdn": "p.typekit.net",
                        "evidence": "css/main.css:7",
                        "decision": "yes",
                    }
                ],
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_paid_features()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "invalid decision value must fail"
    assert any("p.typekit.net" in r.message for r in failures)


def test_gate_paid_features_fails_when_partial_decisions(tmp_path: Path):
    """gate_paid_features must fail if even one paid font has decision=null among many."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "paid-features.json").write_text(
        json.dumps(
            {
                "paidFonts": [
                    {
                        "family": None,
                        "cdn": "use.typekit.net",
                        "evidence": "css/a.css:1",
                        "decision": "use",
                    },
                    {
                        "family": None,
                        "cdn": "fast.fonts.net",
                        "evidence": "css/b.css:2",
                        "decision": None,
                    },
                ],
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_paid_features()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "any null decision must fail the gate"


# ── gate_spec ↔ paid-features cross-validation (font substitution) ──


def _write_min_spec_artifacts(ref: Path, transitions: list[dict] | None = None) -> None:
    """Write the minimum artifacts gate_spec needs so we can exercise the
    cross-validation branch without satisfying every other check."""
    (ref / "bundle-map.json").write_text(json.dumps({}))
    (ref / "external-sdks.json").write_text(json.dumps({}))
    (ref / "transition-spec.json").write_text(
        json.dumps({"transitions": transitions or []})
    )


def test_gate_spec_passes_when_no_substitute_decisions(tmp_path: Path):
    """No paid-features.json (or no substitute decisions) → cross-check is silent."""
    ref = tmp_path / "ref"
    ref.mkdir()
    _write_min_spec_artifacts(ref)
    (ref / "paid-features.json").write_text(
        json.dumps(
            {
                "paidFonts": [
                    {
                        "family": None,
                        "cdn": "use.typekit.net",
                        "evidence": "css/main.css:1",
                        "decision": "use",
                    }
                ]
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_spec()
    sub_failures = [
        r
        for r in results
        if r.status == "fail" and "paid-font substitution" in r.label
    ]
    assert not sub_failures, (
        f"decision=use must not trigger substitution failure: {sub_failures}"
    )


def test_gate_spec_fails_when_substitute_but_no_asset_substitution_json(tmp_path: Path):
    """decision='substitute' without asset-substitution.json must fail at spec time
    (otherwise font-parity discovers it much later, after generation)."""
    ref = tmp_path / "ref"
    ref.mkdir()
    _write_min_spec_artifacts(ref)
    (ref / "paid-features.json").write_text(
        json.dumps(
            {
                "paidFonts": [
                    {
                        "family": None,
                        "cdn": "use.typekit.net",
                        "evidence": "css/main.css:1",
                        "decision": "substitute",
                    }
                ]
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_spec()
    failures = [
        r
        for r in results
        if r.status == "fail" and "paid-font substitution" in r.label
    ]
    assert failures, "substitute without asset-substitution.json must fail"
    assert any("use.typekit.net" in r.message for r in failures)


def test_gate_spec_fails_when_asset_substitution_has_no_fonts(tmp_path: Path):
    """asset-substitution.json present but missing fonts[] → still fail."""
    ref = tmp_path / "ref"
    ref.mkdir()
    _write_min_spec_artifacts(ref)
    (ref / "paid-features.json").write_text(
        json.dumps(
            {
                "paidFonts": [
                    {
                        "family": None,
                        "cdn": "fast.fonts.net",
                        "evidence": "css/main.css:7",
                        "decision": "substitute",
                    }
                ]
            }
        )
    )
    # Has images but no fonts — schema allows other categories
    (ref / "asset-substitution.json").write_text(
        json.dumps({"images": [{"from": "a", "to": "b"}]})
    )

    gate = Gate(ref)
    results = gate.gate_spec()
    failures = [
        r
        for r in results
        if r.status == "fail" and "paid-font substitution" in r.label
    ]
    assert failures, "asset-substitution.json without fonts[] must fail"


def test_gate_spec_passes_when_substitute_and_fonts_declared(tmp_path: Path):
    """substitute + asset-substitution.json with fonts[] → pass."""
    ref = tmp_path / "ref"
    ref.mkdir()
    _write_min_spec_artifacts(ref)
    (ref / "paid-features.json").write_text(
        json.dumps(
            {
                "paidFonts": [
                    {
                        "family": None,
                        "cdn": "use.typekit.net",
                        "evidence": "css/main.css:1",
                        "decision": "substitute",
                    }
                ]
            }
        )
    )
    (ref / "asset-substitution.json").write_text(
        json.dumps(
            {
                "fonts": [
                    {"from": "Adobe Garamond Pro", "to": "EB Garamond", "reason": "paid"}
                ]
            }
        )
    )

    gate = Gate(ref)
    results = gate.gate_spec()
    failures = [
        r
        for r in results
        if r.status == "fail" and "paid-font substitution" in r.label
    ]
    assert not failures, f"declared substitute must pass: {failures}"
    sub_pass = [r for r in results if r.label == "paid-font substitution"]
    assert sub_pass and sub_pass[0].status == "pass"


def test_gate_spec_skips_substitution_check_when_no_paid_features_json(tmp_path: Path):
    """No paid-features.json → no substitution check runs (paid-features gate
    would block first; here we just verify spec stays silent)."""
    ref = tmp_path / "ref"
    ref.mkdir()
    _write_min_spec_artifacts(ref)
    # No paid-features.json written

    gate = Gate(ref)
    results = gate.gate_spec()
    sub_results = [r for r in results if "paid-font substitution" in r.label]
    assert sub_results == [], "no paid-features.json → no substitution check"


# ── gate_section_compare ──


def test_gate_section_compare_fails_when_result_txt_missing(tmp_path: Path):
    """gate_section_compare must fail when sections/result.txt does not exist."""
    ref = tmp_path / "ref"
    ref.mkdir()
    gate = Gate(ref)
    results = gate.gate_section_compare()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "Missing result.txt must produce a fail result"
    assert any("result.txt" in r.message or "result.txt" in r.fix for r in failures)


def test_gate_section_compare_passes_when_all_sections_pass(tmp_path: Path):
    """gate_section_compare must pass when result.txt has only ✅ lines."""
    ref = tmp_path / "ref"
    ref.mkdir()
    sections = ref / "sections"
    sections.mkdir()
    (sections / "result.txt").write_text("| Hero | ✅ PASS | 97% |\n| Footer | ✅ PASS | 99% |\n")
    gate = Gate(ref)
    results = gate.gate_section_compare()
    failures = [r for r in results if r.status == "fail"]
    assert not failures, f"All-pass result.txt must not produce failures: {failures}"


def test_gate_section_compare_fails_when_section_failed(tmp_path: Path):
    """gate_section_compare must fail when result.txt contains ❌."""
    ref = tmp_path / "ref"
    ref.mkdir()
    sections = ref / "sections"
    sections.mkdir()
    (sections / "result.txt").write_text("| Hero | ❌ FAIL | 55% |\n| Footer | ✅ PASS | 99% |\n")
    gate = Gate(ref)
    results = gate.gate_section_compare()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "❌ in result.txt must produce a fail result"
    assert any("FAILED" in r.message or "section" in r.message.lower() for r in failures)


def test_gate_section_compare_fails_when_section_missing(tmp_path: Path):
    """gate_section_compare must fail when result.txt contains ⚠️ MISSING impl."""
    ref = tmp_path / "ref"
    ref.mkdir()
    sections = ref / "sections"
    sections.mkdir()
    (sections / "result.txt").write_text("| Hero | ✅ PASS | 97% |\n| Nav | ⚠️ MISSING impl |\n")
    gate = Gate(ref)
    results = gate.gate_section_compare()
    failures = [r for r in results if r.status == "fail"]
    assert failures, "MISSING impl in result.txt must produce a fail result"


def test_gate_section_compare_accessible_via_run(tmp_path: Path):
    """section-compare gate must be callable through Gate.run()."""
    ref = tmp_path / "ref"
    ref.mkdir()
    gate = Gate(ref)
    # No result.txt → BLOCKED (exit code 1)
    exit_code = gate.run("section-compare", json_output=True)
    assert exit_code == 1


def test_section_count_mismatch_warns(tmp_path: Path):
    """section-map totalCount=3 vs component-map sectionCount=0 must produce a warn."""
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "section-map.json").write_text(
        json.dumps({"sections": [{"tag": "s1"}, {"tag": "s2"}, {"tag": "s3"}], "totalCount": 3})
    )
    (ref / "component-map.json").write_text(json.dumps({"sections": [], "sectionCount": 0}))
    gate = Gate(ref)
    results = gate._check_section_counts(
        json.loads((ref / "section-map.json").read_text()),
        json.loads((ref / "component-map.json").read_text()),
    )
    warns = [r for r in results if r.status == "warn" and "section count" in r.label.lower()]
    assert warns, "section-map=3 vs component-map=0 must produce a warn"


def test_section_count_both_zero_passes(tmp_path: Path):
    """section-map totalCount=0 vs component-map sectionCount=0 must pass (not silently skip)."""
    ref = tmp_path / "ref"
    ref.mkdir()
    gate = Gate(ref)
    results = gate._check_section_counts(
        {"sections": [], "totalCount": 0},
        {"sections": [], "sectionCount": 0},
    )
    passes = [r for r in results if r.status == "pass" and "section count" in r.label.lower()]
    assert passes, "Both counts=0 must produce a pass result"


def test_valid_gates_matches_dispatch():
    """VALID_GATES must exactly match the gates handled by _dispatch."""
    from pathlib import Path

    gate = Gate(Path("/tmp"))
    for gate_name in VALID_GATES:
        if gate_name == "all":
            continue
        results = gate._dispatch(gate_name)
        assert isinstance(results, list), f"_dispatch('{gate_name}') must return a list"
