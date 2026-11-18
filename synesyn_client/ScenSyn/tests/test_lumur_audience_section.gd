extends SceneTree

## ScenarioLoader: [LUMUR_AUDIENCE] whitelist / pass-through (Lumur bridge opt-in).
## Covers JSON object body, flat key:value, absent section, and invalid JSON fallback.

const ScenarioLoaderScript = preload("res://ScenSyn/scripts/core/scenario_loader.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_flat_key_value_form()
	_test_json_object_form()
	_test_without_lumur_audience_unchanged()
	_test_invalid_json_falls_back_without_crash()
	_finish()


func _minimal_scenario_body() -> String:
	return (
		"[SCENARIO]\n"
		+ "Name: Lumur Audience Fixture\n"
		+ "Objective: Parse smoke.\n"
		+ "Location and Setting: A quiet room.\n"
		+ "\n"
		+ "[CHARACTERS]\n"
		+ "id: 0\n"
		+ "name: Narrator\n"
		+ "role: Narrator\n"
		+ "persona: Speaks plainly.\n"
	)


func _test_flat_key_value_form() -> void:
	var content: String = (
		_minimal_scenario_body()
		+ "\n"
		+ "[LUMUR_AUDIENCE]\n"
		+ "enabled: true\n"
		+ "min_dwell_s: 1.5\n"
		+ "debounce_s: 0.8\n"
		+ "gathering_action: advance_beat\n"
		+ "zone_left: -1.0,-0.2,0.2,0.9\n"
		+ "# comment lines are ignored\n"
	)
	var loader: RefCounted = ScenarioLoaderScript.new()
	var parsed: Dictionary = loader.parse_scenario_file(content)
	var scenario: Dictionary = parsed.get("scenario", {}) as Dictionary
	_expect(scenario.has("lumur_audience"), "Flat form: expected scenario.lumur_audience dict")
	_expect(not scenario.has("lumur_audience_text"), "Flat form: must not invent lumur_audience_text")
	var audience: Dictionary = scenario.get("lumur_audience", {}) as Dictionary
	_expect(str(audience.get("enabled", "")) == "true", "Flat form: enabled mismatch")
	_expect(str(audience.get("min_dwell_s", "")) == "1.5", "Flat form: min_dwell_s mismatch")
	_expect(str(audience.get("debounce_s", "")) == "0.8", "Flat form: debounce_s mismatch")
	_expect(str(audience.get("gathering_action", "")) == "advance_beat", "Flat form: gathering_action mismatch")
	_expect(str(audience.get("zone_left", "")).find("-1.0") >= 0, "Flat form: zone_left shorthand")


func _test_json_object_form() -> void:
	var content: String = (
		_minimal_scenario_body()
		+ "\n"
		+ "[LUMUR_AUDIENCE]\n"
		+ "{\n"
		+ "  \"enabled\": true,\n"
		+ "  \"min_dwell_s\": 1.5,\n"
		+ "  \"debounce_s\": 0.8,\n"
		+ "  \"zones\": [\n"
		+ "    {\"zone_id\": \"left\", \"kind\": \"rect\", \"u_min\": -1.0, \"u_max\": -0.2, \"v_min\": 0.2, \"v_max\": 0.9}\n"
		+ "  ],\n"
		+ "  \"zone_actions\": {\n"
		+ "    \"left\": {\"action\": \"choose_option\", \"option_index\": 0},\n"
		+ "    \"right\": {\"action\": \"choose_option\", \"option_index\": 1}\n"
		+ "  },\n"
		+ "  \"gathering_action\": \"advance_beat\",\n"
		+ "  \"intensity_parameter\": \"intensity\"\n"
		+ "}\n"
	)
	var loader: RefCounted = ScenarioLoaderScript.new()
	var parsed: Dictionary = loader.parse_scenario_file(content)
	var scenario: Dictionary = parsed.get("scenario", {}) as Dictionary
	_expect(scenario.has("lumur_audience"), "JSON form: expected scenario.lumur_audience dict")
	_expect(not scenario.has("lumur_audience_text"), "JSON form: must not invent lumur_audience_text")
	var audience: Dictionary = scenario.get("lumur_audience", {}) as Dictionary
	_expect(bool(audience.get("enabled", false)) == true, "JSON form: enabled should be bool true")
	_expect(float(audience.get("min_dwell_s", 0.0)) == 1.5, "JSON form: min_dwell_s typed float")
	var zones_any: Variant = audience.get("zones", [])
	_expect(typeof(zones_any) == TYPE_ARRAY, "JSON form: zones should be Array")
	var zones: Array = zones_any as Array
	_expect(zones.size() == 1, "JSON form: expected one zone")
	if zones.size() >= 1 and typeof(zones[0]) == TYPE_DICTIONARY:
		_expect(str((zones[0] as Dictionary).get("zone_id", "")) == "left", "JSON form: zone_id left")
	var actions_any: Variant = audience.get("zone_actions", {})
	_expect(typeof(actions_any) == TYPE_DICTIONARY, "JSON form: zone_actions should be Dictionary")
	var actions: Dictionary = actions_any as Dictionary
	_expect(actions.has("left") and actions.has("right"), "JSON form: zone_actions keys")
	if typeof(actions.get("left", null)) == TYPE_DICTIONARY:
		_expect(int((actions["left"] as Dictionary).get("option_index", -1)) == 0, "JSON form: left option_index")


func _test_without_lumur_audience_unchanged() -> void:
	var content: String = (
		_minimal_scenario_body()
		+ "\n"
		+ "[PLAYER_AUTO_INPUT]\n"
		+ "enabled: true\n"
		+ "template_echo: hello\n"
	)
	var loader: RefCounted = ScenarioLoaderScript.new()
	var parsed: Dictionary = loader.parse_scenario_file(content)
	var scenario: Dictionary = parsed.get("scenario", {}) as Dictionary
	_expect(not scenario.has("lumur_audience"), "Absent: must not invent lumur_audience")
	_expect(not scenario.has("lumur_audience_text"), "Absent: must not invent lumur_audience_text")
	_expect(scenario.has("player_auto_input"), "Absent: PLAYER_AUTO_INPUT still parses")
	var auto_input: Dictionary = scenario.get("player_auto_input", {}) as Dictionary
	_expect(str(auto_input.get("enabled", "")) == "true", "Absent: player_auto_input.enabled")
	_expect(str(scenario.get("name", "")) == "Lumur Audience Fixture", "Absent: scenario name")


func _test_invalid_json_falls_back_without_crash() -> void:
	# Looks like JSON (starts with '{') but is truncated — must not crash.
	var content: String = (
		_minimal_scenario_body()
		+ "\n"
		+ "[LUMUR_AUDIENCE]\n"
		+ "{\n"
		+ "  \"enabled\": true,\n"
		+ "  \"zones\": [\n"
	)
	var loader: RefCounted = ScenarioLoaderScript.new()
	var parsed: Dictionary = loader.parse_scenario_file(content)
	var scenario: Dictionary = parsed.get("scenario", {}) as Dictionary
	# Fallback flat parse may yield a partial/empty dict; either is fine so long as we continue.
	_expect(typeof(scenario) == TYPE_DICTIONARY, "Invalid JSON: scenario still a Dictionary")
	_expect(str(scenario.get("name", "")) == "Lumur Audience Fixture", "Invalid JSON: rest of scenario intact")
	_expect(not scenario.has("lumur_audience_text"), "Invalid JSON: no free-text fallback key")


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Lumur audience section tests: all passed")
		quit(0)
	for failure_message: String in _failures:
		print("FAIL: " + failure_message)
	quit(1)
