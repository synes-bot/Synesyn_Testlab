extends RefCounted
## Pattern Space interaction coordinator (expand, inspect, region → draft).
## Keeps synaxes_runtime_controller thin.

signal status_message(msg: String)
signal inspect_changed(details: Dictionary)
signal hover_tooltip_changed(text: String)
signal expand_changed(state: Dictionary)
signal region_draft_created(candidate: Dictionary)

const SpacePointsScript = preload("res://addons/synaxes/scripts/visualization/synaxes_space_points.gd")
const RegionMathScript = preload("res://addons/synaxes/scripts/visualization/synaxes_region_math.gd")
const ViewerExpandScript = preload("res://addons/synaxes/scripts/visualization/synaxes_viewer_expand.gd")
const ThemeLabelerScript = preload("res://addons/synaxes/scripts/analysis/synaxes_theme_labeler.gd")

var points: Array = []
var selected_point_indices: Array[int] = []
var inspected_index: int = -1
var region_mode: bool = false
var _expand: RefCounted = ViewerExpandScript.new()
var _region_drag_start: Vector2 = Vector2.ZERO
var _region_dragging: bool = false
var closure_ctrl  # optional ClosureController


func set_patterns(patterns: Array) -> void:
	points = SpacePointsScript.build_from_patterns(patterns)
	selected_point_indices.clear()
	inspected_index = -1
	inspect_changed.emit({})
	hover_tooltip_changed.emit("")


func point_count() -> int:
	return points.size()


func is_expanded() -> bool:
	return bool(_expand.is_expanded)


func expand_button_text() -> String:
	return str(_expand.button_text())


func toggle_expand(
	left_visible: bool,
	bottom_visible: bool,
	left_toggle_pressed: bool,
	bottom_toggle_pressed: bool,
) -> Dictionary:
	var state: Dictionary = _expand.toggle(
		left_visible, bottom_visible, left_toggle_pressed, bottom_toggle_pressed
	)
	expand_changed.emit(state)
	return state


func set_region_mode(is_on: bool) -> void:
	region_mode = is_on
	_region_dragging = false
	status_message.emit(
		"Box select on — drag in Pattern Space to select points."
		if is_on
		else "Box select off."
	)


func is_region_dragging() -> bool:
	return _region_dragging


func begin_region_drag(screen_pos: Vector2) -> void:
	_region_drag_start = screen_pos
	_region_dragging = true


func update_region_drag(screen_pos: Vector2) -> Rect2:
	if not _region_dragging:
		return Rect2()
	return RegionMathScript.box_from_drag(_region_drag_start, screen_pos)


func end_region_drag(screen_pos: Vector2, screen_positions: Array) -> Array[int]:
	_region_dragging = false
	if not RegionMathScript.is_meaningful_drag(_region_drag_start, screen_pos):
		return []
	var box: Rect2 = RegionMathScript.box_from_drag(_region_drag_start, screen_pos)
	var indices: Array[int] = RegionMathScript.indices_in_box(screen_positions, box)
	selected_point_indices = indices
	return indices


func hover_at_index(idx: int) -> void:
	if idx < 0 or idx >= points.size():
		hover_tooltip_changed.emit("")
		return
	hover_tooltip_changed.emit(SpacePointsScript.hover_tooltip(points[idx]))


func inspect_at_index(idx: int) -> Dictionary:
	if idx < 0 or idx >= points.size():
		inspected_index = -1
		inspect_changed.emit({})
		return {}
	inspected_index = idx
	selected_point_indices = [idx] as Array[int]
	var details: Dictionary = SpacePointsScript.inspect_details(points[idx])
	inspect_changed.emit(details)
	return details


func draft_closure_from_selection() -> Dictionary:
	## Build a Dream Inbox candidate from selected points. Never auto-commits.
	if selected_point_indices.is_empty():
		status_message.emit("Select points in Pattern Space first (box select or click).")
		return {"ok": false, "error": "no_selection"}
	var items: Array = SpacePointsScript.items_for_indices(points, selected_point_indices)
	if items.is_empty():
		return {"ok": false, "error": "empty_items"}
	var labeler: RefCounted = ThemeLabelerScript.new()
	var labeled: Dictionary = labeler.label_cluster(items, {}, 0, null)
	var provisional: String = str(labeled.get("label", "Region selection")).strip_edges()
	if provisional.is_empty():
		provisional = "Region selection"
	var item_ids: Array[String] = []
	for it_any in items:
		if typeof(it_any) == TYPE_DICTIONARY:
			item_ids.append(str((it_any as Dictionary).get("id", "")))
	var candidate := {
		"candidate_id": "region_%d" % Time.get_ticks_msec(),
		"name": provisional,
		"intent": "Manual region selection in Pattern Space (%d items)." % items.size(),
		"orientation_quadrant": "",
		"pattern_ids": [],
		"item_ids": item_ids,
		"items": items,
		"confidence": 0.5,
		"label_is_provisional": true,
		"label_source": str(labeled.get("source", "machine_proposed_terms")),
		"label_terms": labeled.get("terms", []),
		"provisional_label": provisional,
		"selection_origin": "manual_region",
	}
	if closure_ctrl != null and closure_ctrl.has_method("add_provisional_candidate"):
		closure_ctrl.add_provisional_candidate(candidate)
	region_draft_created.emit(candidate)
	status_message.emit(
		"Draft closure from %d points — provisional name “%s”. Edit, then Commit."
		% [items.size(), provisional]
	)
	return {"ok": true, "candidate": candidate}
