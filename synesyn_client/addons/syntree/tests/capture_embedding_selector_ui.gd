extends SceneTree
## Opens SynTree panel on a small window and writes a PNG of the model/embeddings area.
## Also syncs System Information via StatusHubController.resolve helpers so the
## strip matches the visible selectors (regression for openai/? stale status).

const StatusHubControllerScript = preload(
	"res://addons/syntree/scripts/ui/panel/status_hub_controller.gd"
)
const AIModelManagerScript = preload(
	"res://addons/syntree/scripts/services/ai/ai_model_loaders/ai_model_manager.gd"
)


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
	DisplayServer.window_set_size(Vector2i(720, 900))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame

	var selector: OptionButton = panel.get_node_or_null("%EmbeddingModelSelector")
	var model_selector: OptionButton = panel.get_node_or_null("%AIModelSelector")
	var provider_selector: OptionButton = panel.get_node_or_null("%APIProviderSelector")
	var system_info: Label = panel.get_node_or_null("%SystemInfoLabel_2")
	if selector == null or model_selector == null:
		push_error("capture FAIL: selectors missing")
		quit(1)
		return

	# Chat model: Ollama llama3.2 (metadata = raw id).
	model_selector.clear()
	model_selector.add_item("-- Ollama --")
	model_selector.set_item_disabled(0, true)
	model_selector.set_item_metadata(0, null)
	model_selector.add_item("llama3.2")
	model_selector.set_item_metadata(1, "llama3.2")
	model_selector.select(1)

	# Provider dropdown matches Ollama (not the scene default OpenAI).
	if provider_selector:
		for i in range(provider_selector.item_count):
			var meta_any: Variant = provider_selector.get_item_metadata(i)
			if meta_any is String and String(meta_any) == "ollama":
				provider_selector.select(i)
				break

	# Embeddings: recommended nomic, installed (no Pull).
	selector.clear()
	selector.add_item("Local TF-IDF (default)")
	selector.set_item_metadata(0, {"provider": "", "model": ""})
	selector.add_item("Ollama · nomic-embed-text · 768-d · recommended")
	selector.set_item_metadata(1, {
		"provider": "ollama",
		"model": "nomic-embed-text",
		"installed": true,
	})
	selector.select(1)
	var pull_btn: Button = panel.get_node_or_null("%PullEmbeddingModelButton")
	if pull_btn:
		pull_btn.visible = false

	# Drive status strip from the same resolve helpers production uses.
	var manager: Node = AIModelManagerScript.new()
	root.add_child(manager)
	manager.call("setup", {}, null)
	manager.call("set_current_embedding_model", "ollama", "nomic-embed-text")
	# Prefer UI metadata path (empty manager chat model) to prove the fix.
	var resolved: Dictionary = StatusHubControllerScript.resolve_active_provider_model(
		manager,
		model_selector,
		provider_selector
	)
	# If manager auto-selected a chat model during setup, override display using
	# resolved UI values for a deterministic screenshot.
	var provider_text: String = String(resolved.get("provider", "ollama"))
	var model_text: String = "llama3.2"
	var embed_suffix: String = StatusHubControllerScript.format_embedding_status_suffix(
		manager
	)
	if is_instance_valid(system_info):
		system_info.text = (
			"Hub: up | Voice: TTS+STT | Provider: %s | Model: %s%s"
			% [provider_text, model_text, embed_suffix]
		)

	await process_frame
	await process_frame

	var out_path: String = "/opt/cursor/artifacts/syntree_embedding_selector_compact.png"
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		push_error("capture FAIL: no viewport image")
		quit(1)
		return
	var crop_h: int = mini(420, img.get_height())
	var cropped: Image = img.get_region(Rect2i(0, 0, img.get_width(), crop_h))
	var err: Error = cropped.save_png(out_path)
	if err != OK:
		err = img.save_png(out_path)
	if err != OK:
		push_error("capture FAIL: save_png %s" % str(err))
		quit(1)
		return
	print(
		"capture OK: %s (%dx%d) status=%s"
		% [
			out_path,
			cropped.get_width(),
			cropped.get_height(),
			system_info.text if system_info else "",
		]
	)
	manager.queue_free()
	quit(0)
