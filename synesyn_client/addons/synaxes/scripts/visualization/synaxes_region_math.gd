extends RefCounted
## Screen-space region selection helpers for Pattern Space points.
## Pure functions — safe for headless tests.

## Return indices of points whose projected screen position lies inside `box`.
## `screen_positions` is Array of Vector2 aligned with the point list.
static func indices_in_box(screen_positions: Array, box: Rect2) -> Array[int]:
	var out: Array[int] = []
	var normalized: Rect2 = box.abs()
	if normalized.size.x < 1.0 and normalized.size.y < 1.0:
		return out
	for i in range(screen_positions.size()):
		var pos_any: Variant = screen_positions[i]
		if typeof(pos_any) != TYPE_VECTOR2:
			continue
		if normalized.has_point(pos_any as Vector2):
			out.append(i)
	return out


## Build a Rect2 from drag start/end (either corner order).
static func box_from_drag(start_pos: Vector2, end_pos: Vector2) -> Rect2:
	return Rect2(start_pos, end_pos - start_pos).abs()


## True when the drag is large enough to count as a region (not a click).
static func is_meaningful_drag(start_pos: Vector2, end_pos: Vector2, min_px: float = 8.0) -> bool:
	return start_pos.distance_to(end_pos) >= min_px
