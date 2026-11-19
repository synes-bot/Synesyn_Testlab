extends RefCounted
## Flat point-cloud model for Pattern Space item positions.
##
## Each point is one imported item with a 3D `space_position`, optional theme
## membership, and display fields for hover/inspect.

## Build points from discovered patterns (items should carry space_position when available).
static func build_from_patterns(patterns: Array) -> Array:
	var points: Array = []
	var seen: Dictionary = {}
	for p_any in patterns:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var pattern: Dictionary = p_any
		var pattern_id: int = int(pattern.get("id", -1))
		var theme_label: String = str(pattern.get("provisional_label", "")).strip_edges()
		var center: Vector3 = pattern.get("position", Vector3.ZERO)
		var items: Array = pattern.get("items", [])
		var item_i: int = 0
		for it_any in items:
			if typeof(it_any) != TYPE_DICTIONARY:
				continue
			var item: Dictionary = it_any
			var item_id: String = str(item.get("id", ""))
			if item_id.is_empty():
				item_id = "anon_%d_%d" % [pattern_id, item_i]
			if seen.has(item_id):
				item_i += 1
				continue
			seen[item_id] = true
			var pos: Vector3 = _resolve_item_position(item, center, item_i, items.size())
			points.append({
				"item_id": item_id,
				"content": str(item.get("content", "")),
				"source": _item_source(item),
				"space_position": pos,
				"pattern_id": pattern_id,
				"theme_label": theme_label,
				"item": item,
			})
			item_i += 1
	return points


static func _resolve_item_position(item: Dictionary, center: Vector3, index: int, total: int) -> Vector3:
	var stamped: Variant = item.get("space_position", null)
	if typeof(stamped) == TYPE_VECTOR3:
		return stamped as Vector3
	# Fallback: slight offset around cluster centre so co-located items remain pickable.
	var angle: float = TAU * float(index) / float(maxi(total, 1))
	var radius: float = 0.35
	return center + Vector3(cos(angle) * radius, sin(angle) * 0.15, sin(angle) * radius)


static func _item_source(item: Dictionary) -> String:
	var source: String = str(item.get("source", "")).strip_edges()
	if not source.is_empty():
		return source
	source = str(item.get("source_label", "")).strip_edges()
	if not source.is_empty():
		return source
	source = str(item.get("origin", "")).strip_edges()
	if not source.is_empty():
		return source
	var meta_any: Variant = item.get("metadata", {})
	if typeof(meta_any) == TYPE_DICTIONARY:
		source = str((meta_any as Dictionary).get("source", "")).strip_edges()
		if not source.is_empty():
			return source
	return "imported"


## Tooltip line: truncated snippet + source.
static func hover_tooltip(point: Dictionary, snippet_chars: int = 48) -> String:
	var snippet: String = str(point.get("content", "")).strip_edges().replace("\n", " ")
	if snippet.length() > snippet_chars:
		snippet = snippet.left(snippet_chars - 1) + "…"
	var source: String = str(point.get("source", "imported"))
	if snippet.is_empty():
		return source
	return "%s  ·  %s" % [snippet, source]


## Details payload for the inspect pane.
static func inspect_details(point: Dictionary) -> Dictionary:
	var theme_label: String = str(point.get("theme_label", "")).strip_edges()
	if theme_label.is_empty():
		theme_label = "(no theme)"
	return {
		"item_id": str(point.get("item_id", "")),
		"snippet": str(point.get("content", "")),
		"source": str(point.get("source", "imported")),
		"theme_label": theme_label,
		"pattern_id": int(point.get("pattern_id", -1)),
		"space_position": point.get("space_position", Vector3.ZERO),
	}


## Collect item dictionaries for a set of point indices (closure draft input).
static func items_for_indices(points: Array, indices: Array) -> Array:
	var out: Array = []
	for idx_any in indices:
		var idx: int = int(idx_any)
		if idx < 0 or idx >= points.size():
			continue
		var point: Dictionary = points[idx]
		var item_any: Variant = point.get("item", {})
		if typeof(item_any) == TYPE_DICTIONARY:
			out.append((item_any as Dictionary).duplicate(true))
	return out
