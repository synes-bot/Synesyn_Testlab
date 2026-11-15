extends SceneTree
## Opens SynTree panel on a small window and writes a PNG of the model/embeddings area.


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene: PackedScene = load("res://addons/syntree/scenes/syntree_panel.tscn")
	if scene == null:
		push_error("capture FAIL: panel scene missing")
		quit(1)
		return
	var panel: Control = scene.instantiate()
	root.add_child(panel)
	# Force a compact dock-like size
	DisplayServer.window_set_size(Vector2i(720, 900))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	# Populate embedding selector if controller exists
	if panel.has_method("_setup_model_settings_controller"):
		pass
	var selector: OptionButton = panel.get_node_or_null("%EmbeddingModelSelector")
	var model_selector: OptionButton = panel.get_node_or_null("%AIModelSelector")
	if selector == null:
		push_error("capture FAIL: EmbeddingModelSelector missing")
		quit(1)
		return
	# Ensure the embedding row is visible even before manager inject
	selector.clear()
	selector.add_item("Local TF-IDF (default)")
	selector.add_item("Ollama · nomic-embed-text · 768-d · recommended")
	selector.add_item("Ollama · all-minilm · 384-d · small  [not installed]")
	selector.select(1)
	var pull_btn: Button = panel.get_node_or_null("%PullEmbeddingModelButton")
	if pull_btn:
		pull_btn.visible = true
	if model_selector:
		model_selector.clear()
		model_selector.add_item("-- Ollama --")
		model_selector.set_item_disabled(0, true)
		model_selector.add_item("llama3.2")
		model_selector.add_item("nomic-embed-text  [embed]")
		model_selector.select(1)
	await process_frame
	await process_frame

	var out_path: String = "/opt/cursor/artifacts/syntree_embedding_selector_compact.png"
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		push_error("capture FAIL: no viewport image")
		quit(1)
		return
	# Crop top portion where model/embeddings live if tall
	var crop_h: int = mini(420, img.get_height())
	var cropped: Image = img.get_region(Rect2i(0, 0, img.get_width(), crop_h))
	var err: Error = cropped.save_png(out_path)
	if err != OK:
		# Fallback: full frame
		err = img.save_png(out_path)
	if err != OK:
		push_error("capture FAIL: save_png %s" % str(err))
		quit(1)
		return
	print("capture OK: %s (%dx%d)" % [out_path, cropped.get_width(), cropped.get_height()])
	quit(0)
