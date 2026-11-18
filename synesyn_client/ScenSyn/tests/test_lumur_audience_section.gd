extends SceneTree

## ScenarioLoader: [LUMUR_AUDIENCE] whitelist / pass-through (Lumur bridge opt-in).

const ScenarioLoaderScript = preload("res://ScenSyn/scripts/core/scenario_loader.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_with_lumur_audience_section()
	_test_without_lumur_audience_unchanged()
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


func _test_with_lumur_audience_section() -> void:
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
	_expect(scenario.has("lumur_audience"), "Expected scenario.lumur_audience dict")
	_expect(not scenario.has("lumur_audience_text"), "Must not fall back to lumur_audience_text when whitelisted")
	var audience: Dictionary = scenario.get("lumur_audience", {}) as Dictionary
	_expect(str(audience.get("enabled", "")) == "true", "enabled should parse as string true")
	_expect(str(audience.get("min_dwell_s", "")) == "1.5", "min_dwell_s mismatch")
	_expect(str(audience.get("debounce_s", "")) == "0.8", "debounce_s mismatch")
	_expect(str(audience.get("gathering_action", "")) == "advance_beat", "gathering_action mismatch")
	_expect(str(audience.get("zone_left", "")).find("-1.0") >= 0, "zone_left shorthand should pass through")


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
	_expect(not scenario.has("lumur_audience"), "Absent [LUMUR_AUDIENCE] must not invent lumur_audience")
	_expect(not scenario.has("lumur_audience_text"), "Absent section must not invent lumur_audience_text")
	_expect(scenario.has("player_auto_input"), "Existing PLAYER_AUTO_INPUT parse must still work")
	var auto_input: Dictionary = scenario.get("player_auto_input", {}) as Dictionary
	_expect(str(auto_input.get("enabled", "")) == "true", "player_auto_input.enabled mismatch")
	_expect(str(scenario.get("name", "")) == "Lumur Audience Fixture", "Scenario name should still parse")


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
