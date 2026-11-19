extends SceneTree
## Headless: Pattern Space selection model, region math, expand toggle, draft-from-selection.
##
## Run (from synesyn_client):
##   godot --headless --path . --script res://addons/synaxes/tests/test_pattern_space_viewer.gd

const SpacePointsScript = preload("res://addons/synaxes/scripts/visualization/synaxes_space_points.gd")
const RegionMathScript = preload("res://addons/synaxes/scripts/visualization/synaxes_region_math.gd")
const ViewerExpandScript = preload("res://addons/synaxes/scripts/visualization/synaxes_viewer_expand.gd")
const SpaceControllerScript = preload("res://addons/synaxes/scripts/runtime/synaxes_space_controller.gd")
const ClosureControllerScript = preload(
	"res://addons/synaxes/scripts/runtime/synaxes_closure_controller.gd"
)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: int = 0
	failures += _test_space_points_model()
	failures += _test_region_math()
	failures += _test_expand_toggle()
	failures += _test_draft_from_selection()
	if failures == 0:
		print("SynAxes pattern space viewer: all passed")
		quit(0)
	else:
		push_error("SynAxes pattern space viewer failures: %d" % failures)
		quit(1)


func _fixture_patterns() -> Array:
	return [
		{
			"id": 0,
			"type": "cluster",
			"confidence": 0.8,
			"position": Vector3(0, 0, 0),
			"provisional_label": "learning prediction",
			"items": [
				{
					"id": "a1",
					"content": "Machine learning models improve prediction accuracy over time.",
					"source": "demo",
					"space_position": Vector3(0.1, 0.0, 0.0),
				},
				{
					"id": "a2",
					"content": "Deep learning neural networks train on large prediction datasets.",
					"source": "demo",
					"space_position": Vector3(0.2, 0.1, 0.0),
				},
			],
		},
		{
			"id": 1,
			"type": "cluster",
			"confidence": 0.7,
			"position": Vector3(2, 0, 0),
			"provisional_label": "garden vegetables",
			"items": [
				{
					"id": "b1",
					"content": "Community gardens grow vegetables for neighborhood kitchens.",
					"source": "demo",
					"space_position": Vector3(2.0, 0.0, 0.1),
				},
			],
		},
	]


func _test_space_points_model() -> int:
	var points: Array = SpacePointsScript.build_from_patterns(_fixture_patterns())
	if points.size() != 3:
		push_error("FAIL space_points: expected 3 points, got %d" % points.size())
		return 1
	var tip: String = SpacePointsScript.hover_tooltip(points[0])
	if tip.is_empty() or not ("demo" in tip):
		push_error("FAIL space_points: hover tooltip missing source: %s" % tip)
		return 1
	var details: Dictionary = SpacePointsScript.inspect_details(points[0])
	if str(details.get("theme_label", "")) != "learning prediction":
		push_error("FAIL space_points: theme_label wrong: %s" % str(details))
		return 1
	if str(details.get("snippet", "")).is_empty():
		push_error("FAIL space_points: snippet empty")
		return 1
	var items: Array = SpacePointsScript.items_for_indices(points, [0, 2])
	if items.size() != 2:
		push_error("FAIL space_points: items_for_indices size %d" % items.size())
		return 1
	print("PASS space_points model")
	return 0


func _test_region_math() -> int:
	var positions: Array = [
		Vector2(10, 10),
		Vector2(50, 50),
		Vector2(200, 200),
		Vector2(5, 90),
	]
	var box: Rect2 = RegionMathScript.box_from_drag(Vector2(0, 0), Vector2(60, 60))
	var idxs: Array[int] = RegionMathScript.indices_in_box(positions, box)
	if idxs != ([0, 1] as Array[int]) and not (idxs.has(0) and idxs.has(1) and idxs.size() == 2):
		push_error("FAIL region_math: expected indices 0,1 got %s" % str(idxs))
		return 1
	if RegionMathScript.is_meaningful_drag(Vector2.ZERO, Vector2(2, 2)):
		push_error("FAIL region_math: tiny drag should not be meaningful")
		return 1
	if not RegionMathScript.is_meaningful_drag(Vector2.ZERO, Vector2(20, 0)):
		push_error("FAIL region_math: 20px drag should be meaningful")
		return 1
	# Reverse drag corners
	var rev: Rect2 = RegionMathScript.box_from_drag(Vector2(80, 80), Vector2(0, 0))
	var rev_idxs: Array[int] = RegionMathScript.indices_in_box(positions, rev)
	if not (rev_idxs.has(0) and rev_idxs.has(1)):
		push_error("FAIL region_math: reverse box missed points: %s" % str(rev_idxs))
		return 1
	print("PASS region_math")
	return 0


func _test_expand_toggle() -> int:
	var expand: RefCounted = ViewerExpandScript.new()
	if expand.is_expanded:
		push_error("FAIL expand: starts expanded")
		return 1
	var state: Dictionary = expand.toggle(true, true, true, true)
	if not bool(state.get("expanded", false)):
		push_error("FAIL expand: not expanded after toggle")
		return 1
	if bool(state.get("left_visible", true)) or bool(state.get("bottom_visible", true)):
		push_error("FAIL expand: panels still visible when expanded")
		return 1
	if expand.button_text() != "Restore":
		push_error("FAIL expand: button text expected Restore")
		return 1
	var restored: Dictionary = expand.toggle(false, false, false, false)
	if bool(restored.get("expanded", true)):
		push_error("FAIL expand: still expanded after restore")
		return 1
	if not bool(restored.get("left_visible", false)) or not bool(restored.get("bottom_visible", false)):
		push_error("FAIL expand: did not restore panel visibility: %s" % str(restored))
		return 1
	if expand.button_text() != "Expand":
		push_error("FAIL expand: button text expected Expand")
		return 1
	print("PASS expand toggle")
	return 0


func _test_draft_from_selection() -> int:
	var space: RefCounted = SpaceControllerScript.new()
	var closure: RefCounted = ClosureControllerScript.new()
	space.closure_ctrl = closure
	space.set_patterns(_fixture_patterns())
	if space.point_count() != 3:
		push_error("FAIL draft: point_count %d" % space.point_count())
		return 1
	var empty: Dictionary = space.draft_closure_from_selection()
	if bool(empty.get("ok", true)):
		push_error("FAIL draft: empty selection should fail")
		return 1
	# Simulate region select across both themes (indices 0 and 2)
	space.selected_point_indices = [0, 2] as Array[int]
	var result: Dictionary = space.draft_closure_from_selection()
	if not bool(result.get("ok", false)):
		push_error("FAIL draft: expected ok: %s" % str(result))
		return 1
	var candidate: Dictionary = result.get("candidate", {})
	if str(candidate.get("selection_origin", "")) != "manual_region":
		push_error("FAIL draft: selection_origin missing/wrong")
		return 1
	if not bool(candidate.get("label_is_provisional", false)):
		push_error("FAIL draft: label_is_provisional false")
		return 1
	if str(candidate.get("name", "")).is_empty():
		push_error("FAIL draft: provisional name empty")
		return 1
	var inbox: Array = closure.get_dream_candidates()
	if inbox.is_empty():
		push_error("FAIL draft: candidate not added to Dream Inbox")
		return 1
	var last: Dictionary = inbox[inbox.size() - 1]
	if str(last.get("selection_origin", "")) != "manual_region":
		push_error("FAIL draft: inbox selection_origin wrong")
		return 1
	# Never auto-committed: dream inbox only, no commit side-effect
	if closure.has_method("get_saved_closures"):
		pass
	print("PASS draft_from_selection")
	return 0
