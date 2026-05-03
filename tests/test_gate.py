import json
from pathlib import Path

from ui_clone.gate import VALID_GATES, Gate


def test_gate_keys_match_dispatch(tmp_path: Path):
    """_gate_keys() must stay in sync with _make_dispatch() — drift would
    make the import-time validator (used without instantiation) silently lie
    about which gates exist."""
    gate = Gate(tmp_path)
    assert frozenset(gate._make_dispatch().keys()) == Gate._gate_keys()


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
