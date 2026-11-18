extends SceneTree
## Unit tests for SynTree embedding-model selection (independent of chat model).

const OllamaModelScript = preload(
	"res://addons/syntree/scripts/services/ai/ai_model_loaders/ollama_model.gd"
)
const OpenAIModelScript = preload(
	"res://addons/syntree/scripts/services/ai/ai_model_loaders/openai_model.gd"
)
const AIModelManagerScript = preload(
	"res://addons/syntree/scripts/services/ai/ai_model_loaders/ai_model_manager.gd"
)
const EmbeddingModelCatalogScript = preload(
	"res://addons/syntree/scripts/services/ai/embedding_model_catalog.gd"
)
const EmbeddingCacheScript = preload(
	"res://addons/synaxes/scripts/data_processing/embedding_cache.gd"
)
const RuntimeConfigScript = preload(
	"res://addons/synesyn_core/scripts/runtime_config.gd"
)
const StatusHubControllerScript = preload(
	"res://addons/syntree/scripts/ui/panel/status_hub_controller.gd"
)


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var failures: Array[String] = []

	_test_catalog(failures)
	_test_ollama_request_body(failures)
	_test_openai_request_body(failures)
	_test_badge_logic(failures)
	_test_manager_persistence(failures)
	_test_dim_mismatch_cache(failures)
	_test_scene_has_embedding_row(failures)
	_test_status_strip_resolution(failures)

	if failures.is_empty():
		print("Embedding model selection tests: all passed")
		quit(0)
		return
	for failure_text: String in failures:
		push_error(failure_text)
	quit(1)


func _test_catalog(failures: Array[String]) -> void:
	var recommended: Array[String] = EmbeddingModelCatalogScript.recommended_ollama_ids()
	if not recommended.has("nomic-embed-text") or not recommended.has("all-minilm"):
		failures.append("catalog missing recommended Ollama embedding models")
	if EmbeddingModelCatalogScript.expected_dim("nomic-embed-text") != 768:
		failures.append("nomic-embed-text expected dim should be 768")
	if EmbeddingModelCatalogScript.expected_dim("all-minilm") != 384:
		failures.append("all-minilm expected dim should be 384")
	if EmbeddingModelCatalogScript.expected_dim("text-embedding-3-small") != 1536:
		failures.append("text-embedding-3-small expected dim should be 1536")
	if not EmbeddingModelCatalogScript.is_openai_embedding_model("text-embedding-3-small"):
		failures.append("text-embedding-3-small should be recognised as OpenAI embed model")
	if EmbeddingModelCatalogScript.is_openai_embedding_model("gpt-4o"):
		failures.append("gpt-4o must NOT be treated as an embedding model")
	if not EmbeddingModelCatalogScript.looks_like_embedding_model("nomic-embed-text"):
		failures.append("nomic-embed-text should match name heuristic")
	if EmbeddingModelCatalogScript.looks_like_embedding_model("llama3.2"):
		failures.append("llama3.2 should not match embedding name heuristic")
	if EmbeddingModelCatalogScript.pull_hint("all-minilm") != "ollama pull all-minilm":
		failures.append("pull hint should be `ollama pull all-minilm`")


func _test_ollama_request_body(failures: Array[String]) -> void:
	var loader: RefCounted = OllamaModelScript.new()
	loader.call("set_model", "llama3.2")
	var body_default: Dictionary = loader.call(
		"prepare_embeddings_request",
		["hello"]
	)
	if String(body_default.get("model", "")) != "llama3.2":
		failures.append("Ollama embeddings without override should use chat model_name")
	var body_override: Dictionary = loader.call(
		"prepare_embeddings_request",
		["hello"],
		"nomic-embed-text"
	)
	if String(body_override.get("model", "")) != "nomic-embed-text":
		failures.append("Ollama embeddings must use selected embedding model id")
	if typeof(body_override.get("input", null)) != TYPE_ARRAY:
		failures.append("Ollama embeddings body must include input array")


func _test_openai_request_body(failures: Array[String]) -> void:
	var loader: RefCounted = OpenAIModelScript.new()
	loader.call("set_model", "gpt-4o-mini")
	var body_default: Dictionary = loader.call(
		"prepare_embeddings_request",
		["hello"]
	)
	if String(body_default.get("model", "")) != "text-embedding-3-small":
		failures.append("OpenAI default embedding model should be text-embedding-3-small")
	var body_override: Dictionary = loader.call(
		"prepare_embeddings_request",
		["hello"],
		"text-embedding-3-small"
	)
	if String(body_override.get("model", "")) != "text-embedding-3-small":
		failures.append("OpenAI embeddings must honour selected embedding model")
	if bool(loader.call("model_supports_embeddings", "gpt-4o")):
		failures.append("OpenAI chat models must not report embedding support")
	if not bool(loader.call("model_supports_embeddings", "text-embedding-3-small")):
		failures.append("OpenAI text-embedding-3-small must report embedding support")


func _test_badge_logic(failures: Array[String]) -> void:
	# Capabilities path
	if not EmbeddingModelCatalogScript.model_supports_embeddings(
		"ollama",
		"custom-embed",
		["embedding"]
	):
		failures.append("Ollama model with embedding capability should badge")
	if EmbeddingModelCatalogScript.model_supports_embeddings(
		"ollama",
		"llama3.2",
		["completion", "tools"]
	):
		failures.append("Ollama chat model without embedding capability must not badge")
	# Heuristic fallback when capabilities empty
	if not EmbeddingModelCatalogScript.model_supports_embeddings(
		"ollama",
		"nomic-embed-text",
		[]
	):
		failures.append("nomic-embed-text should badge via name heuristic")
	if EmbeddingModelCatalogScript.model_supports_embeddings("openai", "gpt-4o", []):
		failures.append("OpenAI gpt-4o must not get [embed] badge")
	if not EmbeddingModelCatalogScript.model_supports_embeddings(
		"openai",
		"text-embedding-3-small",
		[]
	):
		failures.append("OpenAI embedding model should get [embed] badge")


func _test_manager_persistence(failures: Array[String]) -> void:
	var manager: Node = AIModelManagerScript.new()
	root.add_child(manager)
	# Isolate config writes under a temp Documents-style override if available;
	# otherwise exercise in-memory + save path and restore previous values.
	var before: Dictionary = RuntimeConfigScript.load_config()
	var apps_before_any: Variant = before.get("apps", {})
	var apps_before: Dictionary = (
		apps_before_any.duplicate(true)
		if typeof(apps_before_any) == TYPE_DICTIONARY
		else {}
	)
	var syntree_before_any: Variant = apps_before.get("syntree", {})
	var syntree_before: Dictionary = (
		syntree_before_any.duplicate(true)
		if typeof(syntree_before_any) == TYPE_DICTIONARY
		else {}
	)

	manager.call("setup", {}, null)
	var set_result: Dictionary = manager.call(
		"set_current_embedding_model",
		"ollama",
		"nomic-embed-text"
	)
	if not bool(set_result.get("success", false)):
		failures.append("set_current_embedding_model should succeed for ollama/nomic-embed-text")
	if String(manager.call("get_current_embedding_model")) != "nomic-embed-text":
		failures.append("get_current_embedding_model should return nomic-embed-text")
	if String(manager.call("get_current_embedding_provider")) != "ollama":
		failures.append("get_current_embedding_provider should return ollama")

	var after: Dictionary = RuntimeConfigScript.load_config()
	var apps_after_any: Variant = after.get("apps", {})
	var apps_after: Dictionary = (
		apps_after_any if typeof(apps_after_any) == TYPE_DICTIONARY else {}
	)
	var syntree_after_any: Variant = apps_after.get("syntree", {})
	var syntree_after: Dictionary = (
		syntree_after_any if typeof(syntree_after_any) == TYPE_DICTIONARY else {}
	)
	if String(syntree_after.get("selected_embedding_model", "")) != "nomic-embed-text":
		failures.append("runtime config should persist selected_embedding_model")
	if String(syntree_after.get("selected_embedding_provider", "")) != "ollama":
		failures.append("runtime config should persist selected_embedding_provider")

	# Defaults include the new keys
	var defaults: Dictionary = RuntimeConfigScript.default_config()
	var default_syntree: Dictionary = (
		(defaults.get("apps", {}) as Dictionary).get("syntree", {})
	)
	if not default_syntree.has("selected_embedding_model"):
		failures.append("default_config must include selected_embedding_model")
	if not default_syntree.has("selected_embedding_provider"):
		failures.append("default_config must include selected_embedding_provider")

	# Clear selection
	manager.call("set_current_embedding_model", "", "")
	if not String(manager.call("get_current_embedding_model")).is_empty():
		failures.append("clearing embedding model should leave empty selection")

	# Restore prior config values so the test is not sticky on the machine.
	var restore: Dictionary = RuntimeConfigScript.load_config()
	var restore_apps_any: Variant = restore.get("apps", {})
	var restore_apps: Dictionary = (
		restore_apps_any.duplicate(true)
		if typeof(restore_apps_any) == TYPE_DICTIONARY
		else {}
	)
	restore_apps["syntree"] = syntree_before
	restore["apps"] = restore_apps
	RuntimeConfigScript.save_config(restore)

	manager.queue_free()


func _test_dim_mismatch_cache(failures: Array[String]) -> void:
	var cache: RefCounted = EmbeddingCacheScript.new()
	# Bypass disk: write directly into in-memory structure via public API.
	var texts: Array = ["alpha theme", "beta theme"]
	var vec_768_a: Array = []
	var vec_768_b: Array = []
	var vec_384_a: Array = []
	for _i in range(768):
		vec_768_a.append(0.1)
		vec_768_b.append(0.2)
	for _i in range(384):
		vec_384_a.append(0.3)

	var model_nomic: String = "ollama/nomic-embed-text"
	var model_mini: String = "ollama/all-minilm"
	cache.call("put_cached_batch", texts, [vec_768_a, vec_768_b], model_nomic, 768)
	cache.call("put_cached_batch", [texts[0]], [vec_384_a], model_mini, 384)

	var hit_nomic: Dictionary = cache.call("get_cached_batch", texts, model_nomic, 768)
	if not hit_nomic.has(0) or (hit_nomic[0] as Array).size() != 768:
		failures.append("nomic cache lookup at dim 768 should hit")
	var hit_mini: Dictionary = cache.call("get_cached_batch", [texts[0]], model_mini, 384)
	if not hit_mini.has(0) or (hit_mini[0] as Array).size() != 384:
		failures.append("all-minilm cache lookup at dim 384 should hit")
	# Exact dim miss must not return the other model's vectors.
	var miss_wrong_dim: Dictionary = cache.call(
		"get_cached_batch",
		texts,
		model_nomic,
		384
	)
	if miss_wrong_dim.has(0) and miss_wrong_dim[0] != null:
		failures.append("nomic lookup at dim 384 must not return 768-d vectors")
	# Different model_id must not mix.
	var miss_other_model: Dictionary = cache.call(
		"get_cached_batch",
		texts,
		model_mini,
		768
	)
	if miss_other_model.has(0) and miss_other_model[0] != null:
		failures.append("all-minilm lookup at dim 768 must not hit nomic entries")


func _test_scene_has_embedding_row(failures: Array[String]) -> void:
	var scene: PackedScene = load("res://addons/syntree/scenes/syntree_panel.tscn")
	if scene == null:
		failures.append("syntree_panel.tscn failed to load")
		return
	var scene_state: SceneState = scene.get_state()
	var has_selector: bool = false
	var has_pull: bool = false
	for node_index: int in range(scene_state.get_node_count()):
		var node_id: String = String(scene_state.get_node_name(node_index))
		if node_id == "EmbeddingModelSelector":
			has_selector = true
		elif node_id == "PullEmbeddingModelButton":
			has_pull = true
	if not has_selector:
		failures.append("syntree_panel.tscn must include EmbeddingModelSelector")
	if not has_pull:
		failures.append("syntree_panel.tscn must include PullEmbeddingModelButton")


func _test_status_strip_resolution(failures: Array[String]) -> void:
	## Regression: UI shows Ollama/llama3.2 but strip said openai / ? when the
	## manager was empty and the API-provider dropdown still defaulted to OpenAI.
	var model_selector := OptionButton.new()
	root.add_child(model_selector)
	model_selector.add_item("-- Ollama --")
	model_selector.set_item_disabled(0, true)
	model_selector.add_item("llama3.2  [embed]")
	model_selector.set_item_metadata(1, "llama3.2")
	model_selector.select(1)

	var provider_selector := OptionButton.new()
	root.add_child(provider_selector)
	provider_selector.add_item("OpenAI")
	provider_selector.set_item_metadata(0, "openai")
	provider_selector.add_item("Ollama")
	provider_selector.set_item_metadata(1, "ollama")
	provider_selector.select(0)  # stale default — must NOT win over model metadata

	var fake_manager := _FakeStatusModelManager.new()
	fake_manager.current_model = ""
	fake_manager.embedding_model = "nomic-embed-text"
	fake_manager.embedding_provider = "ollama"

	var resolved: Dictionary = StatusHubControllerScript.resolve_active_provider_model(
		fake_manager,
		model_selector,
		provider_selector
	)
	if String(resolved.get("model", "")) != "llama3.2":
		failures.append(
			"status strip should resolve model from selector metadata, got '%s'"
			% String(resolved.get("model", ""))
		)
	if String(resolved.get("provider", "")) != "ollama":
		failures.append(
			"status strip should resolve provider from manager for UI model, got '%s'"
			% String(resolved.get("provider", ""))
		)

	# Manager current model wins over UI.
	fake_manager.current_model = "gemma4:26b"
	var resolved_mgr: Dictionary = StatusHubControllerScript.resolve_active_provider_model(
		fake_manager,
		model_selector,
		provider_selector
	)
	if String(resolved_mgr.get("model", "")) != "gemma4:26b":
		failures.append("manager current model should win over selector")
	if String(resolved_mgr.get("provider", "")) != "ollama":
		failures.append("manager provider for gemma4:26b should be ollama")

	var embed_suffix: String = StatusHubControllerScript.format_embedding_status_suffix(
		fake_manager
	)
	if embed_suffix != " | Embed: ollama/nomic-embed-text":
		failures.append(
			"embedding status suffix wrong: '%s'" % embed_suffix
		)
	fake_manager.embedding_model = ""
	var local_suffix: String = StatusHubControllerScript.format_embedding_status_suffix(
		fake_manager
	)
	if local_suffix != " | Embed: local":
		failures.append("empty embedding selection should show Embed: local")

	# Strip badge suffixes from display text fallback.
	var cleaned: String = StatusHubControllerScript._strip_model_display_suffixes(
		"nomic-embed-text  [embed]"
	)
	if cleaned != "nomic-embed-text":
		failures.append("badge strip failed: '%s'" % cleaned)

	model_selector.queue_free()
	provider_selector.queue_free()


class _FakeStatusModelManager:
	extends RefCounted

	var current_model: String = ""
	var embedding_model: String = ""
	var embedding_provider: String = ""

	func get_current_model() -> String:
		return current_model

	func get_provider_for_model(model_name: String) -> String:
		var resolved: String = model_name.strip_edges()
		if resolved.is_empty():
			return ""
		# Enough for the status-strip unit test.
		if (
			resolved.begins_with("llama")
			or resolved.begins_with("gemma")
			or resolved.begins_with("nomic")
			or resolved.begins_with("all-minilm")
		):
			return "ollama"
		if resolved.begins_with("gpt") or resolved.begins_with("text-embedding"):
			return "openai"
		return "ollama"

	func get_current_embedding_model() -> String:
		return embedding_model

	func get_current_embedding_provider() -> String:
		return embedding_provider
