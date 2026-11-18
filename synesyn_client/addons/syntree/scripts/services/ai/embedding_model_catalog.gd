extends RefCounted
class_name EmbeddingModelCatalog
## Catalog of embedding models SynTree exposes independently of the chat model.
## Keep product-generic: no hardcoded remote servers or channels.

## Recommended Ollama embedding models (tested locally). First is the default suggestion.
const RECOMMENDED_OLLAMA: Array = [
	{
		"id": "nomic-embed-text",
		"dim": 768,
		"size_hint": "274 MB",
		"label": "nomic-embed-text · 768-d · recommended",
	},
	{
		"id": "all-minilm",
		"dim": 384,
		"size_hint": "46 MB",
		"label": "all-minilm · 384-d · small",
	},
]

## OpenAI embedding models SynTree lists when a key is present.
## Only models that go to /v1/embeddings — never chat completions models.
const OPENAI_EMBEDDING_MODELS: Array = [
	{
		"id": "text-embedding-3-small",
		"dim": 1536,
		"label": "text-embedding-3-small · 1536-d",
	},
]

const DEFAULT_OLLAMA_EMBEDDING_MODEL := "nomic-embed-text"
const DEFAULT_OPENAI_EMBEDDING_MODEL := "text-embedding-3-small"

## Name-family heuristics when /api/show capabilities are missing.
const _NAME_HINTS: Array[String] = [
	"nomic-embed",
	"all-minilm",
	"minilm",
	"bge-",
	"e5-",
	"gte-",
	"snowflake-arctic-embed",
	"mxbai-embed",
	"jina-embeddings",
	"embeddinggemma",
	"embed",
]


static func recommended_ollama_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry_any: Variant in RECOMMENDED_OLLAMA:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var model_id: String = String((entry_any as Dictionary).get("id", "")).strip_edges()
		if not model_id.is_empty():
			ids.append(model_id)
	return ids


static func openai_embedding_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry_any: Variant in OPENAI_EMBEDDING_MODELS:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var model_id: String = String((entry_any as Dictionary).get("id", "")).strip_edges()
		if not model_id.is_empty():
			ids.append(model_id)
	return ids


static func expected_dim(model_id: String) -> int:
	var resolved: String = _base_name(model_id)
	for entry_any: Variant in RECOMMENDED_OLLAMA:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		if _base_name(String(entry.get("id", ""))) == resolved:
			return int(entry.get("dim", 0))
	for entry_any: Variant in OPENAI_EMBEDDING_MODELS:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		if _base_name(String(entry.get("id", ""))) == resolved:
			return int(entry.get("dim", 0))
	if resolved.begins_with("text-embedding-3-large"):
		return 3072
	if resolved.begins_with("text-embedding"):
		return 1536
	return 0


static func is_openai_embedding_model(model_id: String) -> bool:
	var resolved: String = _base_name(model_id)
	if resolved.is_empty():
		return false
	if resolved.begins_with("text-embedding"):
		return true
	for known: String in openai_embedding_ids():
		if _base_name(known) == resolved:
			return true
	return false


static func capabilities_include_embedding(capabilities: Array) -> bool:
	for capability_any: Variant in capabilities:
		if String(capability_any).strip_edges().to_lower() == "embedding":
			return true
	return false


static func looks_like_embedding_model(model_id: String) -> bool:
	var resolved: String = _base_name(model_id).to_lower()
	if resolved.is_empty():
		return false
	if is_openai_embedding_model(resolved):
		return true
	for hint: String in _NAME_HINTS:
		if resolved.find(hint) >= 0:
			return true
	return false


static func model_supports_embeddings(
	provider_id: String,
	model_id: String,
	capabilities: Array = []
) -> bool:
	var provider_key: String = provider_id.strip_edges().to_lower()
	var resolved_model: String = model_id.strip_edges()
	if resolved_model.is_empty():
		return false
	if provider_key == "openai":
		return is_openai_embedding_model(resolved_model)
	if provider_key == "ollama":
		if not capabilities.is_empty():
			return capabilities_include_embedding(capabilities)
		return looks_like_embedding_model(resolved_model)
	return false


static func display_label_for(
	provider_id: String,
	model_id: String,
	is_installed: bool = true
) -> String:
	var provider_key: String = provider_id.strip_edges().to_lower()
	var resolved: String = model_id.strip_edges()
	for entry_any: Variant in RECOMMENDED_OLLAMA:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		if _base_name(String(entry.get("id", ""))) == _base_name(resolved):
			var label_text: String = String(entry.get("label", resolved))
			if provider_key == "ollama" and not is_installed:
				return "%s  [not installed]" % label_text
			return label_text
	for entry_any: Variant in OPENAI_EMBEDDING_MODELS:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		if _base_name(String(entry.get("id", ""))) == _base_name(resolved):
			return String(entry.get("label", resolved))
	var dim: int = expected_dim(resolved)
	var base_label: String = resolved if dim <= 0 else "%s · %d-d" % [resolved, dim]
	if provider_key == "ollama" and not is_installed:
		return "%s  [not installed]" % base_label
	return base_label


static func pull_hint(model_id: String) -> String:
	var resolved: String = model_id.strip_edges()
	if resolved.is_empty():
		return ""
	return "ollama pull %s" % resolved


static func _base_name(model_id: String) -> String:
	return model_id.strip_edges().get_slice(":", 0).to_lower()
