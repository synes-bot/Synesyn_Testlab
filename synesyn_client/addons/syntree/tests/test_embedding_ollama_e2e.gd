extends SceneTree
## Optional live Ollama e2e: prepare_embeddings_request + HTTP /api/embed.
## Skips cleanly (exit 0) when Ollama or the model is unavailable.

const OllamaModelScript = preload(
	"res://addons/syntree/scripts/services/ai/ai_model_loaders/ollama_model.gd"
)

const MODEL_CANDIDATES: Array[String] = ["all-minilm", "nomic-embed-text"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tags: Dictionary = await _get_json("http://127.0.0.1:11434/api/tags", HTTPClient.METHOD_GET, "")
	if not bool(tags.get("ok", false)):
		print("Ollama e2e SKIP: ollama unreachable")
		quit(0)
		return
	var installed: Array[String] = []
	var body_any: Variant = tags.get("body", {})
	if typeof(body_any) == TYPE_DICTIONARY:
		var models_any: Variant = (body_any as Dictionary).get("models", [])
		if typeof(models_any) == TYPE_ARRAY:
			for model_any: Variant in models_any:
				if typeof(model_any) != TYPE_DICTIONARY:
					continue
				var model_id: String = String(
					(model_any as Dictionary).get("name", "")
				).strip_edges()
				if not model_id.is_empty():
					installed.append(model_id)

	var chosen: String = ""
	for candidate: String in MODEL_CANDIDATES:
		for installed_id: String in installed:
			if installed_id.get_slice(":", 0) == candidate:
				chosen = installed_id
				break
		if not chosen.is_empty():
			break
	if chosen.is_empty():
		print("Ollama e2e SKIP: no recommended embedding model installed")
		quit(0)
		return

	var loader: RefCounted = OllamaModelScript.new()
	loader.call("set_base_origin", "http://127.0.0.1:11434")
	loader.call("set_model", "llama3.2")  # chat model deliberately different
	var body: Dictionary = loader.call(
		"prepare_embeddings_request",
		["Synesyn loader e2e"],
		chosen
	)
	if String(body.get("model", "")) != chosen:
		push_error("Ollama e2e FAIL: request body used wrong model")
		quit(1)
		return
	var url: String = String(loader.call("get_embeddings_url", ""))
	var headers: PackedStringArray = loader.call("get_embeddings_headers", "")
	var response: Dictionary = await _get_json(
		url,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if not bool(response.get("ok", false)):
		push_error("Ollama e2e FAIL: HTTP embed failed: %s" % str(response.get("error", "")))
		quit(1)
		return
	var vectors: Array = loader.call(
		"parse_embeddings_response",
		response.get("body", {})
	)
	if vectors.is_empty() or typeof(vectors[0]) != TYPE_ARRAY:
		push_error("Ollama e2e FAIL: no vectors parsed")
		quit(1)
		return
	var dim: int = (vectors[0] as Array).size()
	print("Ollama e2e PASS: model=%s dim=%d (chat model was llama3.2)" % [chosen, dim])
	quit(0)


func _get_json(url: String, method: int, body_text: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 60.0
	root.add_child(http)
	var err: int = http.request(url, PackedStringArray(["Content-Type: application/json"]), method, body_text)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "request_start_%d" % err}
	var completed: Array = await http.request_completed
	http.queue_free()
	if int(completed[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "result_%d" % int(completed[0])}
	var code: int = int(completed[1])
	var text: String = (completed[3] as PackedByteArray).get_string_from_utf8()
	if code < 200 or code >= 300:
		return {"ok": false, "error": "http_%d" % code, "details": text.left(200)}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "bad_json"}
	return {"ok": true, "body": parsed}
