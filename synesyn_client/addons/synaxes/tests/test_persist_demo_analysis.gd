extends SceneTree
## REQ-NDP-017: local Discover on demo (no context graph id) must still persist
## projection / cluster / json.analysis_run so Reload last analysis can work.

const HubPipelineScript = preload(
	"res://addons/synaxes/scripts/runtime/synaxes_hub_pipeline.gd"
)
const TestDataGeneratorScript = preload(
	"res://addons/synaxes/scripts/integration/test_data_generator.gd"
)
const TextEmbedderScript = preload(
	"res://addons/synaxes/scripts/data_processing/text_embedder.gd"
)


class FakeHub:
	extends Node
	var created: Array = []
	var events: Array = []

	func create_artifact_inline_json(
		artifact_type: String, inline_json: Dictionary, metadata: Dictionary = {}
	) -> Dictionary:
		var aid: String = "art_fake_%d" % (created.size() + 1)
		created.append({
			"id": aid,
			"artifact_type": artifact_type,
			"inline_json": inline_json,
			"metadata": metadata,
		})
		return {"ok": true, "id": aid}

	func create_event(
		event_type: String,
		payload: Dictionary = {},
		metadata: Dictionary = {},
		source_id: String = "",
		seq: int = 0
	) -> Dictionary:
		events.append({
			"event_type": event_type,
			"payload": payload,
			"metadata": metadata,
			"source_id": source_id,
			"seq": seq,
		})
		return {"ok": true}

	func create_entity(
		_entity_type: String,
		_entity_name: String,
		_summary: String = "",
		_tags: Array = [],
		_metadata: Dictionary = {}
	) -> Dictionary:
		return {"ok": true, "id": "ent_fake"}

	func create_relation(
		_relation_type: String,
		_from_entity_id: String,
		_to_entity_id: String,
		_weight: float = 0.0,
		_metadata: Dictionary = {}
	) -> Dictionary:
		return {"ok": true, "id": "rel_fake"}

	func get_or_create_entity(
		entity_type: String,
		entity_name: String,
		summary: String = "",
		tags: Array = [],
		metadata: Dictionary = {}
	) -> Dictionary:
		return await create_entity(entity_type, entity_name, summary, tags, metadata)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: int = 0
	failures += await _test_persist_without_context_graph()
	if failures == 0:
		print("SynAxes persist demo analysis: all passed")
		quit(0)
	else:
		push_error("SynAxes persist demo analysis failures: %d" % failures)
		quit(1)


func _test_persist_without_context_graph() -> int:
	var fake_hub: FakeHub = FakeHub.new()
	root.add_child(fake_hub)

	var pipeline: RefCounted = HubPipelineScript.new()
	pipeline.hub = fake_hub
	pipeline.seq_fn = func() -> int: return 1

	var gen: RefCounted = TestDataGeneratorScript.new()
	gen.set_data_type("text")
	gen.set_item_count(8)
	var data: Array = gen.generate_test_data()
	# Replace random demo vectors with TF-IDF so dim-reduction has real floats.
	var embedder: RefCounted = TextEmbedderScript.new()
	var texts: Array = []
	for it_any in data:
		texts.append(str((it_any as Dictionary).get("content", "")))
	var vectors: Array = embedder.embed_batch(texts, 32)
	for i in range(data.size()):
		var it: Dictionary = (data[i] as Dictionary).duplicate()
		it["vector"] = vectors[i]
		data[i] = it

	# Minimal cluster patterns matching discovery_engine cluster shape.
	var patterns: Array = [
		{
			"type": "cluster",
			"id": 0,
			"confidence": 0.8,
			"position": Vector3(0.1, 0.2, 0.3),
			"items": [data[0], data[1]],
		},
		{
			"type": "cluster",
			"id": 1,
			"confidence": 0.7,
			"position": Vector3(-0.1, 0.0, 0.2),
			"items": [data[2], data[3]],
		},
	]

	var persist_res: Dictionary = await pipeline.persist_analysis_results_to_hub(
		patterns,
		data,
		"",  # empty context graph — demo path
		0,
		0,
		2,
	)
	var proj_id: String = str(persist_res.get("projection_artifact_id", ""))
	var cluster_id: String = str(persist_res.get("cluster_artifact_id", ""))
	var run_id: String = str(persist_res.get("analysis_run_artifact_id", ""))
	if proj_id.is_empty() or cluster_id.is_empty() or run_id.is_empty():
		push_error(
			"FAIL: expected projection/cluster/analysis_run ids, got %s" % str(persist_res)
		)
		return 1

	var types_seen: Dictionary = {}
	for entry_any in fake_hub.created:
		var entry: Dictionary = entry_any
		types_seen[str(entry.get("artifact_type", ""))] = true
	if not types_seen.has("coords.projection_3d"):
		push_error("FAIL: missing coords.projection_3d artifact")
		return 1
	if not types_seen.has("graph.cluster_result"):
		push_error("FAIL: missing graph.cluster_result artifact")
		return 1
	if not types_seen.has("json.analysis_run"):
		push_error("FAIL: missing json.analysis_run artifact")
		return 1

	# Provenance must remain an object even without a context-graph input.
	for entry_any in fake_hub.created:
		var entry: Dictionary = entry_any
		var meta: Dictionary = entry.get("metadata", {})
		var prov_any: Variant = meta.get("provenance", null)
		if typeof(prov_any) != TYPE_DICTIONARY:
			push_error("FAIL: metadata.provenance missing for %s" % entry.get("artifact_type"))
			return 1

	print(
		"OK persist without context graph: proj=%s cluster=%s run=%s created=%d"
		% [proj_id, cluster_id, run_id, fake_hub.created.size()]
	)
	return 0
