extends RefCounted
## Wires Pattern Space expand / inspect / region UI onto the main SynAxes scene.
## Keeps synaxes_runtime_controller thin (line-limit ratchet).

const SpaceControllerScript = preload(
	"res://addons/synaxes/scripts/runtime/synaxes_space_controller.gd"
)

var space: RefCounted = SpaceControllerScript.new()
var host: Node = null
var pattern_viewer: Node = null
var left_panel: Control = null
var bottom_panel: Control = null
var left_toggle: Button = null
var bottom_toggle: Button = null
var expand_btn: Button = null
var expand_toolbar: Button = null
var box_btn: Button = null
var draft_btn: Button = null
var hover_label: Label = null
var inspect_panel: Control = null
var inspect_theme: Label = null
var inspect_source: Label = null
var inspect_snippet: Label = null
var region_overlay: ColorRect = null
var status_cb: Callable = Callable()
var _syncing_expand_buttons: bool = false


func bind(host_node: Node, refs: Dictionary, closure_ctrl) -> void:
	host = host_node
	space.closure_ctrl = closure_ctrl
	pattern_viewer = refs.get("pattern_viewer") as Node
	left_panel = refs.get("left_panel") as Control
	bottom_panel = refs.get("bottom_panel") as Control
	left_toggle = refs.get("left_toggle") as Button
	bottom_toggle = refs.get("bottom_toggle") as Button
	expand_btn = refs.get("expand_btn") as Button
	expand_toolbar = refs.get("expand_toolbar") as Button
	box_btn = refs.get("box_btn") as Button
	draft_btn = refs.get("draft_btn") as Button
	hover_label = refs.get("hover_label") as Label
	inspect_panel = refs.get("inspect_panel") as Control
	inspect_theme = refs.get("inspect_theme") as Label
	inspect_source = refs.get("inspect_source") as Label
	inspect_snippet = refs.get("inspect_snippet") as Label
	region_overlay = refs.get("region_overlay") as ColorRect
	status_cb = refs.get("status_cb", Callable()) as Callable

	if space.has_signal("status_message"):
		space.status_message.connect(_on_status)
	if space.has_signal("inspect_changed"):
		space.inspect_changed.connect(_on_inspect)
	if space.has_signal("hover_tooltip_changed"):
		space.hover_tooltip_changed.connect(_on_hover)
	if space.has_signal("expand_changed"):
		space.expand_changed.connect(_apply_expand_state)
	if space.has_signal("region_draft_created"):
		space.region_draft_created.connect(_on_region_draft)

	if expand_btn:
		expand_btn.pressed.connect(_on_expand_pressed)
	if expand_toolbar:
		expand_toolbar.pressed.connect(_on_expand_pressed)
	if box_btn:
		box_btn.toggled.connect(_on_box_toggled)
	if draft_btn:
		draft_btn.pressed.connect(_on_draft_pressed)

	if pattern_viewer and pattern_viewer.has_signal("point_hovered"):
		pattern_viewer.point_hovered.connect(_on_point_hovered)
	if pattern_viewer and pattern_viewer.has_signal("point_clicked"):
		pattern_viewer.point_clicked.connect(_on_point_clicked)
	if pattern_viewer and pattern_viewer.has_signal("region_drag_updated"):
		pattern_viewer.region_drag_updated.connect(_on_region_drag_updated)
	if pattern_viewer and pattern_viewer.has_signal("region_drag_ended"):
		pattern_viewer.region_drag_ended.connect(_on_region_drag_ended)

	if host and not host.is_connected("gui_input", _on_host_gui_input):
		# Shortcuts are handled in _unhandled_key via host process.
		pass
	if host and host.has_method("set_process_unhandled_key_input"):
		pass


func on_patterns_ready(patterns: Array) -> void:
	space.set_patterns(patterns)
	if pattern_viewer and pattern_viewer.has_method("set_point_cloud"):
		pattern_viewer.set_point_cloud(space.points)


func clear() -> void:
	space.set_patterns([])
	if pattern_viewer and pattern_viewer.has_method("clear_point_cloud"):
		pattern_viewer.clear_point_cloud()
	_on_inspect({})
	_on_hover("")
	_hide_region_overlay()


func handle_unhandled_key(event: InputEventKey) -> bool:
	if event == null or not event.pressed or event.echo:
		return false
	match event.keycode:
		KEY_X:
			_on_expand_pressed()
			return true
		KEY_B:
			if box_btn:
				box_btn.button_pressed = not box_btn.button_pressed
			else:
				_on_box_toggled(not space.region_mode)
			return true
	return false


func _on_expand_pressed() -> void:
	if _syncing_expand_buttons:
		return
	var left_vis: bool = true if left_panel == null else left_panel.visible
	var bottom_vis: bool = true if bottom_panel == null else bottom_panel.visible
	var left_tog: bool = true if left_toggle == null else left_toggle.button_pressed
	var bottom_tog: bool = true if bottom_toggle == null else bottom_toggle.button_pressed
	# toggle_expand emits expand_changed → _apply_expand_state
	space.toggle_expand(left_vis, bottom_vis, left_tog, bottom_tog)


func _apply_expand_state(state: Dictionary) -> void:
	_syncing_expand_buttons = true
	if left_panel:
		left_panel.visible = bool(state.get("left_visible", true))
	if bottom_panel:
		bottom_panel.visible = bool(state.get("bottom_visible", true))
	if left_toggle:
		left_toggle.set_pressed_no_signal(bool(state.get("left_toggle", true)))
	if bottom_toggle:
		bottom_toggle.set_pressed_no_signal(bool(state.get("bottom_toggle", true)))
	var btn_text: String = space.expand_button_text()
	if expand_btn:
		expand_btn.text = btn_text
		expand_btn.set_pressed_no_signal(space.is_expanded())
	if expand_toolbar:
		expand_toolbar.text = "Restore Space" if space.is_expanded() else "Expand Space"
		expand_toolbar.set_pressed_no_signal(space.is_expanded())
	_syncing_expand_buttons = false
	_on_status(
		"Pattern Space expanded — press Expand/X to restore."
		if space.is_expanded()
		else "Pattern Space restored."
	)
	if host and host.has_method("call_deferred"):
		host.call_deferred("_refresh_split_layout")


func _on_box_toggled(is_on: bool) -> void:
	space.set_region_mode(is_on)
	if pattern_viewer and pattern_viewer.has_method("set_region_select_mode"):
		pattern_viewer.set_region_select_mode(is_on)
	if not is_on:
		_hide_region_overlay()


func _on_draft_pressed() -> void:
	space.draft_closure_from_selection()


func _on_point_hovered(idx: int) -> void:
	space.hover_at_index(idx)
	if pattern_viewer and pattern_viewer.has_method("set_point_hovered"):
		pattern_viewer.set_point_hovered(idx)


func _on_point_clicked(idx: int) -> void:
	space.inspect_at_index(idx)
	if pattern_viewer and pattern_viewer.has_method("set_point_selection"):
		pattern_viewer.set_point_selection(space.selected_point_indices)
	# Sync Dream Inbox / Closure editor when the point belongs to a theme pattern.
	if idx >= 0 and idx < space.points.size() and host != null:
		var point: Dictionary = space.points[idx]
		var pattern_id: int = int(point.get("pattern_id", -1))
		if pattern_id >= 0 and host.has_method("_on_viewer_pattern_selected"):
			host._on_viewer_pattern_selected(pattern_id)


func _on_region_drag_updated(screen_pos: Vector2) -> void:
	if not space.region_mode:
		return
	if not space.is_region_dragging():
		space.begin_region_drag(screen_pos)
	var box: Rect2 = space.update_region_drag(screen_pos)
	_show_region_overlay(box)


func _on_region_drag_ended(screen_pos: Vector2) -> void:
	if not space.region_mode:
		_hide_region_overlay()
		return
	var screen_positions: Array = []
	if pattern_viewer and pattern_viewer.has_method("point_screen_positions"):
		screen_positions = pattern_viewer.point_screen_positions()
	var indices: Array[int] = space.end_region_drag(screen_pos, screen_positions)
	_hide_region_overlay()
	if pattern_viewer and pattern_viewer.has_method("set_point_selection"):
		pattern_viewer.set_point_selection(indices)
	if indices.is_empty():
		_on_status("Region select: no points in box.")
	else:
		_on_status("Region select: %d points. Draft closure when ready." % indices.size())


func _on_region_draft(_candidate: Dictionary) -> void:
	if host and host.has_method("_set_spine_state"):
		host._set_spine_state("editing")
	if host != null:
		var tabs: TabContainer = host.get("bottom_tabs") as TabContainer
		if tabs and tabs.get_tab_count() > 0:
			# Closures tab is typically last; prefer by name when available.
			for i in range(tabs.get_tab_count()):
				var tab_title: String = str(tabs.get_tab_title(i)).to_lower()
				if "clos" in tab_title or "dream" in tab_title:
					tabs.current_tab = i
					return
			tabs.current_tab = tabs.get_tab_count() - 1


func _on_inspect(details: Dictionary) -> void:
	if inspect_panel == null:
		return
	if details.is_empty():
		inspect_panel.visible = false
		return
	inspect_panel.visible = true
	if inspect_theme:
		inspect_theme.text = "Theme: %s" % str(details.get("theme_label", "—"))
	if inspect_source:
		inspect_source.text = "Source: %s" % str(details.get("source", "—"))
	if inspect_snippet:
		inspect_snippet.text = str(details.get("snippet", ""))


func _on_hover(text: String) -> void:
	if hover_label:
		hover_label.text = text


func _on_status(msg: String) -> void:
	if status_cb.is_valid():
		status_cb.call(msg)


func _show_region_overlay(box: Rect2) -> void:
	if region_overlay == null:
		return
	region_overlay.visible = true
	region_overlay.position = box.position
	region_overlay.size = box.size


func _hide_region_overlay() -> void:
	if region_overlay:
		region_overlay.visible = false


func _on_host_gui_input(_event: InputEvent) -> void:
	pass
