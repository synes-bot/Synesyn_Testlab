extends RefCounted
## Builds the SynAxes Import source ItemList ordering.
##
## When Hub has no material, demo rows lead (and are preselected) so users do not
## accidentally import an empty Hub source. When Hub has graphs, Hub rows lead and
## demos stay visually distinct.

const SOURCE_LABEL_HUB_CONTEXT := "Hub: Context Graphs"
const SOURCE_LABEL_HUB_EMBEDDINGS := "Hub: Saved Embeddings"
const SOURCE_LABEL_SCENSYN_SESSIONS := "ScenSyn: Session Data"

const _DEFAULT_DEMOS: Array[String] = [
	"Demo: Text Samples",
	"Demo: Semantic Samples",
	"Demo: Image Samples",
]
const _DEMO_COLOR := Color(0.55, 0.42, 0.12, 1.0)


static func rebuild(source_list: ItemList, hub_material_count: int) -> void:
	if source_list == null:
		return

	var demo_labels: Array[String] = []
	for i in range(source_list.item_count):
		var lbl: String = source_list.get_item_text(i)
		if lbl.begins_with("Demo:") or lbl.begins_with("★ Demo:"):
			demo_labels.append(lbl.replace("★ ", ""))
	if demo_labels.is_empty():
		demo_labels = _DEFAULT_DEMOS.duplicate()

	source_list.clear()
	var demos_first: bool = hub_material_count <= 0
	if demos_first:
		_add_demo_rows(source_list, demo_labels, true)
		_add_separator(source_list, "── Hub / session sources ──")
		source_list.add_item(SOURCE_LABEL_HUB_CONTEXT)
		source_list.add_item(SOURCE_LABEL_HUB_EMBEDDINGS)
		source_list.add_item(SOURCE_LABEL_SCENSYN_SESSIONS)
		if source_list.item_count > 0:
			source_list.select(0)
	else:
		source_list.add_item(SOURCE_LABEL_HUB_CONTEXT)
		source_list.add_item(SOURCE_LABEL_HUB_EMBEDDINGS)
		source_list.add_item(SOURCE_LABEL_SCENSYN_SESSIONS)
		_add_separator(source_list, "── Demo / sample data ──")
		_add_demo_rows(source_list, demo_labels, false)


static func normalize_import_label(raw_label: String) -> String:
	return raw_label.replace("★ ", "").strip_edges()


static func _add_separator(source_list: ItemList, text: String) -> void:
	var sep_idx: int = source_list.item_count
	source_list.add_item(text)
	source_list.set_item_disabled(sep_idx, true)
	source_list.set_item_selectable(sep_idx, false)


static func _add_demo_rows(source_list: ItemList, demo_labels: Array[String], emphasize: bool) -> void:
	for demo_lbl in demo_labels:
		var display: String = ("★ %s" % demo_lbl) if emphasize else demo_lbl
		source_list.add_item(display)
		var idx: int = source_list.item_count - 1
		source_list.set_item_custom_fg_color(idx, _DEMO_COLOR)
		source_list.set_item_tooltip(
			idx,
			"Sample data for trying SynAxes. Safe to import — not Hub material.",
		)
