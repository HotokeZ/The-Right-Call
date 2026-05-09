extends Node

const MODES_PATH := "res://data/gameplay/difficulty_modes.json"
const TUTORIAL_PATH := "res://data/gameplay/tutorial_steps.json"
const SAVE_PATH := "user://player_progress.json"
# Temporary QA/testing override. Set to false before release.
const TEMP_FORCE_CERTIFIED_MODE := true

var modes_config: Dictionary = {}
var tutorial_config: Dictionary = {}
var progress: Dictionary = {
	"completed_tutorial": false,
	"passed_pre_assessment": false,
	"first_live_call_done": false,
	"selected_mode": "easy_multiple_choice",
	"certified_difficulty": "easy",
	"certifications": [],
	"locale": "en"
}

func _ready() -> void:
	_load_configs()
	_load_progress()

func _load_configs() -> void:
	modes_config = _load_json(MODES_PATH)
	tutorial_config = _load_json(TUTORIAL_PATH)

func _load_progress() -> void:
	var loaded = _load_json(SAVE_PATH)
	if typeof(loaded) == TYPE_DICTIONARY and not loaded.is_empty():
		progress.merge(loaded, true)
	_ensure_progress_shape()

func _ensure_progress_shape() -> void:
	if not progress.has("completed_tutorial"):
		progress["completed_tutorial"] = false
	if not progress.has("passed_pre_assessment"):
		progress["passed_pre_assessment"] = false
	if not progress.has("first_live_call_done"):
		progress["first_live_call_done"] = false
	if not progress.has("selected_mode"):
		progress["selected_mode"] = "easy_multiple_choice"
	if not progress.has("certified_difficulty"):
		progress["certified_difficulty"] = "easy"
	if not progress.has("certifications") or typeof(progress["certifications"]) != TYPE_ARRAY:
		progress["certifications"] = []
	if not progress.has("locale"):
		progress["locale"] = "en"
	if not progress.has("current_day"):
		progress["current_day"] = 1
	if not progress.has("daily_results") or typeof(progress["daily_results"]) != TYPE_ARRAY:
		progress["daily_results"] = []

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}

func save_progress() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(progress, "\t"))

func get_current_day() -> int:
	return max(1, int(progress.get("current_day", 1)))

func get_day_difficulty_scale() -> float:
	var day_index = get_current_day() - 1
	return clamp(1.0 + float(day_index) * 0.06, 1.0, 1.75)

func record_shift_result(score: int, calls_completed: int) -> Dictionary:
	var completed_day = get_current_day()
	var results: Array = progress.get("daily_results", [])
	results.append({
		"day": completed_day,
		"score": max(0, score),
		"calls_completed": max(0, calls_completed),
		"completed_at_unix": int(Time.get_unix_time_from_system())
	})
	progress["daily_results"] = results
	progress["current_day"] = completed_day + 1
	save_progress()
	return {
		"completed_day": completed_day,
		"next_day": get_current_day(),
		"difficulty_scale": get_day_difficulty_scale()
	}

func get_latest_shift_result() -> Dictionary:
	var results: Array = progress.get("daily_results", [])
	if results.is_empty():
		return {}
	var latest = results[results.size() - 1]
	if typeof(latest) == TYPE_DICTIONARY:
		return latest
	return {}

func get_modes() -> Array:
	return modes_config.get("modes", [])

func get_mode(mode_id: String) -> Dictionary:
	for mode in get_modes():
		if mode.get("id", "") == mode_id:
			return mode
	return {}

func is_mode_unlocked(mode_id: String) -> bool:
	var mode = get_mode(mode_id)
	if mode.is_empty():
		return false
	if mode_id == "certified_nlp_dispatch" and TEMP_FORCE_CERTIFIED_MODE:
		return true
	if mode.get("unlocked_by_default", false):
		return true
	var cert_id = String(mode.get("required_certification", ""))
	return cert_id == "" or has_certification(cert_id)

func is_certified_mode_temporarily_forced() -> bool:
	return TEMP_FORCE_CERTIFIED_MODE

func get_mode_lock_reason(mode_id: String) -> String:
	var mode = get_mode(mode_id)
	if mode.is_empty():
		return "Mode not found."
	if is_mode_unlocked(mode_id):
		return ""
	var cert_id = String(mode.get("required_certification", ""))
	if cert_id == "":
		return "This mode is currently unavailable."
	return "Complete the required certification in the e-learning app first: %s" % cert_id

func select_mode(mode_id: String) -> bool:
	if not is_mode_unlocked(mode_id):
		return false
	progress["selected_mode"] = mode_id
	save_progress()
	return true

func get_selected_mode() -> Dictionary:
	return get_mode(String(progress.get("selected_mode", "easy_multiple_choice")))

func set_certified_difficulty(diff: String) -> void:
	if diff in ["easy", "medium", "hard"]:
		progress["certified_difficulty"] = diff
		save_progress()

func get_certified_difficulty() -> String:
	return String(progress.get("certified_difficulty", "easy"))

func complete_tutorial() -> void:
	progress["completed_tutorial"] = true
	save_progress()

func has_completed_tutorial() -> bool:
	return bool(progress.get("completed_tutorial", false))

func pass_pre_assessment() -> void:
	progress["passed_pre_assessment"] = true
	save_progress()

func has_passed_pre_assessment() -> bool:
	return bool(progress.get("passed_pre_assessment", false))

func set_first_live_call_done() -> void:
	progress["first_live_call_done"] = true
	save_progress()

func get_first_live_call_done() -> bool:
	return bool(progress.get("first_live_call_done", false))

func get_tutorial_steps() -> Array:
	return tutorial_config.get("steps", [])

func get_tutorial_title() -> String:
	return String(tutorial_config.get("title", "Tutorial"))

func get_tutorial_subtitle() -> String:
	return String(tutorial_config.get("subtitle", ""))

func grant_certification(cert_id: String) -> void:
	var certs: Array = progress.get("certifications", [])
	if cert_id in certs:
		return
	certs.append(cert_id)
	progress["certifications"] = certs
	save_progress()

func has_certification(cert_id: String) -> bool:
	var certs: Array = progress.get("certifications", [])
	return cert_id in certs

func reset_progress() -> void:
	progress = {
		"completed_tutorial": false,
		"passed_pre_assessment": false,
		"first_live_call_done": false,
		"selected_mode": "easy_multiple_choice",
		"certified_difficulty": "easy",
		"certifications": [],
		"locale": "en",
		"current_day": 1,
		"daily_results": [],
		"saved_shift": {}
	}
	save_progress()

func set_locale(locale: String) -> void:
	if locale in ["en", "tl", "taglish"]:
		progress["locale"] = locale
		save_progress()

func get_locale() -> String:
	return String(progress.get("locale", "en"))

func get_saved_shift() -> Dictionary:
	var shift = progress.get("saved_shift")
	if typeof(shift) == TYPE_DICTIONARY:
		return shift
	return {}

func save_shift_progress(shift_data: Dictionary) -> void:
	progress["saved_shift"] = shift_data
	save_progress()

func clear_shift_progress() -> void:
	if progress.has("saved_shift"):
		progress["saved_shift"] = {}
		save_progress()

