extends SceneTree
## Headless: provisional theme label determinism + quality on fixture text.
##
## Run (from synesyn_client):
##   godot --headless --path . --script res://addons/synaxes/tests/test_theme_labels.gd

const ThemeLabelerScript = preload("res://addons/synaxes/scripts/analysis/synaxes_theme_labeler.gd")
const DiscoverFocusScript = preload("res://addons/synaxes/scripts/runtime/synaxes_discover_focus.gd")
const AnalysisControllerScript = preload(
	"res://addons/synaxes/scripts/runtime/synaxes_analysis_controller.gd"
)
const ClosureControllerScript = preload(
	"res://addons/synaxes/scripts/runtime/synaxes_closure_controller.gd"
)
const TestDataGeneratorScript = preload(
	"res://addons/synaxes/scripts/integration/test_data_generator.gd"
)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: int = 0
	failures += _test_label_determinism()
	failures += _test_label_quality_fixture()
	failures += _test_snippet_fallback()
	failures += _test_focus_policy()
	failures += await _test_discover_prefills_provisional()
	if failures == 0:
		print("SynAxes theme labels: all passed")
		quit(0)
	else:
		push_error("SynAxes theme labels failures: %d" % failures)
		quit(1)


func _fixture_patterns() -> Array:
	return [
		{
			"id": 0,
			"type": "cluster",
			"confidence": 0.8,
			"position": Vector3.ZERO,
			"items": [
				{"id": "a1", "content": "Machine learning models improve prediction accuracy over time."},
				{"id": "a2", "content": "Deep learning neural networks train on large prediction datasets."},
				{"id": "a3", "content": "Supervised learning improves model prediction for classification."},
			],
		},
		{
			"id": 1,
			"type": "cluster",
			"confidence": 0.7,
			"position": Vector3.RIGHT,
			"items": [
				{"id": "b1", "content": "Community gardens grow vegetables for neighborhood kitchens."},
				{"id": "b2", "content": "Urban gardens share fresh vegetables with local neighborhoods."},
				{"id": "b3", "content": "Volunteer gardens plant vegetables across city neighborhoods."},
			],
		},
	]


func _test_label_determinism() -> int:
	var labeler_a: RefCounted = ThemeLabelerScript.new()
	var labeler_b: RefCounted = ThemeLabelerScript.new()
	var patterns_a: Array = _fixture_patterns()
	var patterns_b: Array = _fixture_patterns()
	labeler_a.annotate_patterns(patterns_a)
	labeler_b.annotate_patterns(patterns_b)
	for i in range(patterns_a.size()):
		var la: String = str((patterns_a[i] as Dictionary).get("provisional_label", ""))
		var lb: String = str((patterns_b[i] as Dictionary).get("provisional_label", ""))
		if la.is_empty() or la != lb:
			push_error("FAIL determinism: cluster %d labels diverge (%s vs %s)" % [i, la, lb])
			return 1
		if not bool((patterns_a[i] as Dictionary).get("label_is_provisional", false)):
			push_error("FAIL determinism: label_is_provisional missing")
			return 1
	print("OK label determinism")
	return 0


func _test_label_quality_fixture() -> int:
	var labeler: RefCounted = ThemeLabelerScript.new()
	var patterns: Array = _fixture_patterns()
	labeler.annotate_patterns(patterns)
	var label0: String = str((patterns[0] as Dictionary).get("provisional_label", "")).to_lower()
	var label1: String = str((patterns[1] as Dictionary).get("provisional_label", "")).to_lower()
	var source0: String = str((patterns[0] as Dictionary).get("label_source", ""))
	if source0 != "machine_proposed_terms" and source0 != "machine_proposed_snippet":
		push_error("FAIL quality: unexpected label_source %s" % source0)
		return 1
	# Distinctive content words should appear; stopwords / Cluster #N should not.
	if label0.find("cluster") != -1:
		push_error("FAIL quality: learning cluster still named Cluster #N (%s)" % label0)
		return 1
	var learning_hit: bool = (
		label0.find("learning") != -1
		or label0.find("prediction") != -1
		or label0.find("model") != -1
	)
	if not learning_hit:
		push_error("FAIL quality: learning fixture label weak: %s" % label0)
		return 1
	var garden_hit: bool = (
		label1.find("garden") != -1
		or label1.find("vegetable") != -1
		or label1.find("neighborhood") != -1
	)
	if not garden_hit:
		push_error("FAIL quality: garden fixture label weak: %s" % label1)
		return 1
	var words0: PackedStringArray = label0.split(" ", false)
	if words0.size() < 2 or words0.size() > 4:
		# Snippet fallback may be longer; only enforce word count for term source.
		if source0 == "machine_proposed_terms":
			push_error("FAIL quality: expected 2-4 words, got %d (%s)" % [words0.size(), label0])
			return 1
	print("OK label quality: '%s' / '%s'" % [label0, label1])
	return 0


func _test_snippet_fallback() -> int:
	var labeler: RefCounted = ThemeLabelerScript.new()
	var items: Array = [
		{"id": "s1", "content": "The and for that with this from are was were have"},
		{"id": "s2", "content": "The and for that with this from are was were have again"},
	]
	var result: Dictionary = labeler.label_cluster(items, {}, 0, null)
	var label: String = str(result.get("label", ""))
	var source: String = str(result.get("source", ""))
	if label.is_empty():
		push_error("FAIL snippet fallback: empty label")
		return 1
	if source != "machine_proposed_snippet" and source != "machine_proposed_terms":
		push_error("FAIL snippet fallback: unexpected source %s" % source)
		return 1
	print("OK snippet/fallback: source=%s label=%s" % [source, label])
	return 0


func _test_focus_policy() -> int:
	if DiscoverFocusScript.bottom_tab_after_discover(false, 3) != 0:
		push_error("FAIL focus: Discover should focus Overview (0)")
		return 1
	if DiscoverFocusScript.bottom_tab_after_discover(true, 3) != 2:
		push_error("FAIL focus: Propose-themes should focus Closures (2)")
		return 1
	if DiscoverFocusScript.bottom_tab_after_discover(true, 1) != 0:
		push_error("FAIL focus: Closures focus requires tab_count > 2")
		return 1
	var steps: Array[String] = ["Import", "Explore", "Choose", "Name", "Commit"]
	var spine: String = DiscoverFocusScript.spine_text(steps, 0)
	if spine.find("Commit") == -1 or spine.find("\n") == -1:
		push_error("FAIL spine: expected two-line spine including Commit, got %s" % spine)
		return 1
	print("OK focus policy")
	return 0


func _test_discover_prefills_provisional() -> int:
	var closure_ctrl: RefCounted = ClosureControllerScript.new()
	var analysis: RefCounted = AnalysisControllerScript.new()
	analysis.closure_ctrl = closure_ctrl
	analysis.use_hub_embeddings = false
	analysis.ensure_engine()

	var gen: RefCounted = TestDataGeneratorScript.new()
	gen.set_data_type("text")
	gen.set_item_count(12)
	var source_data: Array = gen.generate_test_data()
	for i in range(source_data.size()):
		if typeof(source_data[i]) != TYPE_DICTIONARY:
			continue
		var item_dict: Dictionary = (source_data[i] as Dictionary).duplicate()
		item_dict["vector"] = []
		source_data[i] = item_dict

	var result: Dictionary = await analysis.import_embed_discover(
		source_data,
		"",
		{"method": 0, "dim_method": 0, "num_clusters": 4, "use_hub_embeddings": false},
	)
	var patterns: Array = result.get("patterns", [])
	if patterns.is_empty():
		push_error("FAIL discover labels: no patterns")
		return 1
	var labeled_count: int = 0
	for p_any in patterns:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		if str(p.get("type", "")).to_lower() != "cluster":
			continue
		var plabel: String = str(p.get("provisional_label", "")).strip_edges()
		if plabel.is_empty():
			push_error("FAIL discover labels: cluster missing provisional_label")
			return 1
		labeled_count += 1
	var candidates: Array = closure_ctrl.get_dream_candidates()
	if candidates.is_empty():
		push_error("FAIL discover labels: no dream candidates")
		return 1
	var c0: Dictionary = candidates[0]
	if not bool(c0.get("label_is_provisional", false)):
		push_error("FAIL discover labels: candidate not marked provisional")
		return 1
	if str(c0.get("name", "")).strip_edges().is_empty():
		push_error("FAIL discover labels: candidate name empty")
		return 1
	print(
		"OK discover prefills: %d labeled clusters, candidate='%s' source=%s"
		% [labeled_count, str(c0.get("name", "")), str(c0.get("label_source", ""))]
	)
	return 0
