extends RefCounted
## Embedding cache: avoids re-embedding the same content across sessions.
##
## Cache key: hash(content_text) + model_id + dim
## Storage: user://synaxes_embedding_cache.json (persists across sessions)

const CACHE_PATH := "user://synaxes_embedding_cache.json"
const MAX_ENTRIES := 5000  # Evict oldest when exceeded

var _cache: Dictionary = {}  # key -> {vector, ts}
var _is_loaded: bool = false

func _ensure_loaded() -> void:
	if _is_loaded:
		return
	_is_loaded = true
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if not f:
		return
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_DICTIONARY:
		_cache = parsed

func save() -> void:
	# Evict oldest entries if over limit
	if _cache.size() > MAX_ENTRIES:
		var entries: Array = []
		for cache_key in _cache:
			var entry: Dictionary = _cache[cache_key]
			entries.append({"key": cache_key, "ts": int(entry.get("ts", 0))})
		entries.sort_custom(func(a, b): return a["ts"] < b["ts"])
		var to_remove := entries.size() - MAX_ENTRIES
		for i in range(to_remove):
			_cache.erase(entries[i]["key"])

	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(_cache))
	f.close()

## Build a cache key from content text, model identifier, and vector dimension.
static func make_key(content: String, model_id: String, dim: int) -> String:
	return "%d_%s_%d" % [content.hash(), model_id, dim]

## Look up a cached vector. Returns the vector Array or null if not cached.
func get_vector(cache_key: String) -> Variant:
	_ensure_loaded()
	if _cache.has(cache_key):
		var entry: Dictionary = _cache[cache_key]
		return entry.get("vector", null)
	return null

## Store a vector in the cache.
func put_vector(cache_key: String, vector: Array) -> void:
	_ensure_loaded()
	_cache[cache_key] = {"vector": vector, "ts": int(Time.get_unix_time_from_system())}

## Batch lookup: returns {index -> vector} for items that are cached.
## When `dim` > 0, looks up the exact key. When `dim` == 0, scans for any
## stored dim under the same content+model_id and returns the first match.
## Callers must reject mismatched dims across a batch (do not mix models).
func get_cached_batch(texts: Array, model_id: String, dim: int) -> Dictionary:
	_ensure_loaded()
	var result: Dictionary = {}
	for i in range(texts.size()):
		var content_text: String = str(texts[i])
		if dim > 0:
			var cache_key: String = make_key(content_text, model_id, dim)
			if _cache.has(cache_key):
				result[i] = (_cache[cache_key] as Dictionary).get("vector", null)
			continue
		# dim == 0: find any entry for this content+model (prefix before final _dim).
		var content_hash: int = content_text.hash()
		var prefix: String = "%d_%s_" % [content_hash, model_id]
		for stored_key_any: Variant in _cache.keys():
			var stored_key: String = String(stored_key_any)
			if not stored_key.begins_with(prefix):
				continue
			result[i] = (_cache[stored_key] as Dictionary).get("vector", null)
			break
	return result


## Remove all entries for a model_id (any dim). Used when switching embedding
## models would otherwise mix incompatible vector widths.
func invalidate_model(model_id: String) -> int:
	_ensure_loaded()
	var removed: int = 0
	var keys_to_erase: Array[String] = []
	for stored_key_any: Variant in _cache.keys():
		var stored_key: String = String(stored_key_any)
		# Keys are "{hash}_{model_id}_{dim}". model_id may contain underscores.
		if stored_key.find("_%s_" % model_id) >= 0:
			keys_to_erase.append(stored_key)
	for erase_key: String in keys_to_erase:
		_cache.erase(erase_key)
		removed += 1
	return removed

## Batch store: caches vectors for all items.
func put_cached_batch(texts: Array, vectors: Array, model_id: String, dim: int) -> void:
	_ensure_loaded()
	for i in range(mini(texts.size(), vectors.size())):
		var cache_key := make_key(str(texts[i]), model_id, dim)
		_cache[cache_key] = {"vector": vectors[i], "ts": int(Time.get_unix_time_from_system())}

## Number of entries in cache.
func entry_count() -> int:
	_ensure_loaded()
	return _cache.size()
