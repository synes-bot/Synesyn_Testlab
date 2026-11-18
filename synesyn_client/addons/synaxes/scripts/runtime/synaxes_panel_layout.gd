extends RefCounted
## Vertical split defaults for SynAxes main scene.
## Keeps the Closures / Dream Inbox bottom panel usable at default window size.

const BOTTOM_FLOOR_PX := 320
const TOP_RATIO := 0.52
const TOP_MIN_PX := 180


static func apply_vsplit_default(vsplit: SplitContainer) -> void:
	if vsplit == null or vsplit.size.y <= 0:
		return
	var desired: int = int(vsplit.size.y * TOP_RATIO)
	desired = clampi(desired, TOP_MIN_PX, maxi(TOP_MIN_PX, int(vsplit.size.y) - BOTTOM_FLOOR_PX))
	vsplit.split_offset = desired


static func set_debug_overlay(pattern_viewer: Node, debug_info: Label, is_on: bool) -> void:
	if pattern_viewer != null and pattern_viewer.has_method("set_debug_overlay_visible"):
		pattern_viewer.set_debug_overlay_visible(is_on)
	elif debug_info != null:
		debug_info.visible = is_on
