extends RefCounted
## Expand / restore state for Pattern Space filling the main panel.

var is_expanded: bool = false
var _saved_left_visible: bool = true
var _saved_bottom_visible: bool = true
var _saved_left_toggle: bool = true
var _saved_bottom_toggle: bool = true


func toggle(
	left_visible: bool,
	bottom_visible: bool,
	left_toggle_pressed: bool,
	bottom_toggle_pressed: bool,
) -> Dictionary:
	## Returns desired visibility: {expanded, left_visible, bottom_visible, left_toggle, bottom_toggle}.
	if is_expanded:
		return collapse()
	return expand(left_visible, bottom_visible, left_toggle_pressed, bottom_toggle_pressed)


func expand(
	left_visible: bool,
	bottom_visible: bool,
	left_toggle_pressed: bool,
	bottom_toggle_pressed: bool,
) -> Dictionary:
	_saved_left_visible = left_visible
	_saved_bottom_visible = bottom_visible
	_saved_left_toggle = left_toggle_pressed
	_saved_bottom_toggle = bottom_toggle_pressed
	is_expanded = true
	return {
		"expanded": true,
		"left_visible": false,
		"bottom_visible": false,
		"left_toggle": false,
		"bottom_toggle": false,
	}


func collapse() -> Dictionary:
	is_expanded = false
	return {
		"expanded": false,
		"left_visible": _saved_left_visible,
		"bottom_visible": _saved_bottom_visible,
		"left_toggle": _saved_left_toggle,
		"bottom_toggle": _saved_bottom_toggle,
	}


func button_text() -> String:
	return "Restore" if is_expanded else "Expand"
