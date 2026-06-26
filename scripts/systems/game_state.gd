extends Node

const MODES_PATH := "res://data/gameplay/difficulty_modes.json"
const TUTORIAL_PATH := "res://data/gameplay/tutorial_steps.json"
const SAVE_PATH := "user://player_progress.json"
# Temporary QA/testing override. Set to false before release.
const TEMP_FORCE_PROFRESSIONAL_MODE := true

# All mode IDs that carry per-mode progress (day counter, results, shift slot).
const _MODE_IDS := ["easy_multiple_choice", "profressional_nlp_dispatch"]

var modes_config: Dictionary = {}
var tutorial_config: Dictionary = {}
var progress: Dictionary = {
	"completed_tutorial": false,
	"passed_pre_assessment": false,
	"first_live_call_done": false,
	"selected_mode": "easy_multiple_choice",
	"profressional_difficulty": "easy",
	"certifications": [],
	"completed_modules": [],
	"locale": "en",
	"perfectionist_mode": true
}

func _ready() -> void:
	_load_configs()
	_load_progress()

func _load_configs() -> void:
	modes_config    = _load_json(MODES_PATH)
	tutorial_config = _load_json(TUTORIAL_PATH)

func _load_progress() -> void:
	var loaded = _load_json(SAVE_PATH)
	if typeof(loaded) == TYPE_DICTIONARY and not loaded.is_empty():
		progress.merge(loaded, true)
	_ensure_progress_shape()

func _ensure_progress_shape() -> void:
	# ── Scalar keys with defaults ─────────────────────────────────────────────
	_default_if_missing("completed_tutorial",   false)
	_default_if_missing("passed_pre_assessment", false)
	_default_if_missing("first_live_call_done", false)
	_default_if_missing("selected_mode",        "easy_multiple_choice")
	_default_if_missing("profressional_difficulty", "easy")
	_default_if_missing("locale",               "en")
	_default_if_missing("perfectionist_mode",   true)

	# ── Array-typed keys ─────────────────────────────────────────────────────
	if not progress.has("certifications") or typeof(progress["certifications"]) != TYPE_ARRAY:
		progress["certifications"] = []
	if not progress.has("completed_modules") or typeof(progress["completed_modules"]) != TYPE_ARRAY:
		progress["completed_modules"] = []

	# ── Per-mode namespaced keys — migrate legacy flat keys once ─────────────
	for mode_id in _MODE_IDS:
		_migrate_mode_keys(mode_id)

# ── Internal: set a key to its default value only if absent ──────────────────
func _default_if_missing(key: String, default_value: Variant) -> void:
	if not progress.has(key):
		progress[key] = default_value

# ── Internal: migrate/initialize per-mode progress keys for one mode ─────────
func _migrate_mode_keys(mode_id: String) -> void:
	var day_key   = "current_day_"     + mode_id
	var res_key   = "daily_results_"   + mode_id
	var shift_key = "saved_shift_"     + mode_id
	var is_normal = (mode_id == "easy_multiple_choice")

	# Day counter
	if not progress.has(day_key):
		progress[day_key] = (
			progress["current_day"] if (is_normal and progress.has("current_day"))
			else 1
		)

	# Daily results array
	if not progress.has(res_key) or typeof(progress[res_key]) != TYPE_ARRAY:
		if is_normal and progress.has("daily_results") and typeof(progress["daily_results"]) == TYPE_ARRAY:
			progress[res_key] = progress["daily_results"].duplicate()
		else:
			progress[res_key] = []

	# In-progress shift dictionary
	if not progress.has(shift_key) or typeof(progress[shift_key]) != TYPE_DICTIONARY:
		if is_normal and progress.has("saved_shift") and typeof(progress["saved_shift"]) == TYPE_DICTIONARY:
			progress[shift_key] = progress["saved_shift"].duplicate()
		else:
			progress[shift_key] = {}

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

# ── Internal: returns the active mode id (never empty) ───────────────────────
func _active_mode_id() -> String:
	return String(progress.get("selected_mode", "easy_multiple_choice"))

func get_current_day() -> int:
	return max(1, int(progress.get("current_day_" + _active_mode_id(), 1)))

func get_day_difficulty_scale() -> float:
	return clamp(1.0 + float(get_current_day() - 1) * 0.06, 1.0, 1.75)

func record_shift_result(score: int, calls_completed: int) -> Dictionary:
	var mode_id      = _active_mode_id()
	var completed_day = get_current_day()
	var res_key      = "daily_results_" + mode_id
	var day_key      = "current_day_"   + mode_id
	var results: Array = progress.get(res_key, [])
	results.append({
		"day": completed_day,
		"score": max(0, score),
		"calls_completed": max(0, calls_completed),
		"completed_at_unix": int(Time.get_unix_time_from_system())
	})
	progress[res_key] = results
	progress[day_key] = completed_day + 1
	save_progress()
	return {
		"completed_day":    completed_day,
		"next_day":         get_current_day(),
		"difficulty_scale": get_day_difficulty_scale()
	}

func get_latest_shift_result() -> Dictionary:
	var results: Array = progress.get("daily_results_" + _active_mode_id(), [])
	if results.is_empty():
		return {}
	var latest = results[results.size() - 1]
	return latest if typeof(latest) == TYPE_DICTIONARY else {}

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
	if mode_id == "profressional_nlp_dispatch" and TEMP_FORCE_PROFRESSIONAL_MODE:
		return true
	if mode.get("unlocked_by_default", false):
		return true
	var cert_id = String(mode.get("required_certification", ""))
	return cert_id == "" or has_certification(cert_id)

func is_profressional_mode_temporarily_forced() -> bool:
	return TEMP_FORCE_PROFRESSIONAL_MODE

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

func set_profressional_difficulty(diff: String) -> void:
	if diff in ["easy", "medium", "hard"]:
		progress["profressional_difficulty"] = diff
		save_progress()

func get_profressional_difficulty() -> String:
	return String(progress.get("profressional_difficulty", "easy"))

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

func reset_first_live_call_done() -> void:
	progress["first_live_call_done"] = false
	save_progress()

func get_first_live_call_done() -> bool:
	return bool(progress.get("first_live_call_done", false))

var _force_tutorial: bool = false
func set_force_tutorial(val: bool) -> void:
	_force_tutorial = val

func get_force_tutorial() -> bool:
	return _force_tutorial

func get_tutorial_steps() -> Array:
	return tutorial_config.get("steps", [])

func get_tutorial_title() -> String:
	return String(tutorial_config.get("title", "Tutorial"))

func get_tutorial_subtitle() -> String:
	return String(tutorial_config.get("subtitle", ""))

func translate(text: String) -> String:
	return text

func get_completed_modules_count() -> int:
	return (progress.get("completed_modules", []) as Array).size()

func is_module_completed(module_num: int) -> bool:
	return module_num in (progress.get("completed_modules", []) as Array)

func complete_module(module_num: int) -> void:
	var modules: Array = progress.get("completed_modules", [])
	if module_num in modules:
		return
	modules.append(module_num)
	progress["completed_modules"] = modules
	save_progress()

func grant_certification(cert_id: String) -> void:
	var certs: Array = progress.get("certifications", [])
	if cert_id in certs:
		return
	certs.append(cert_id)
	progress["certifications"] = certs
	save_progress()

func has_certification(cert_id: String) -> bool:
	return cert_id in (progress.get("certifications", []) as Array)

func reset_progress() -> void:
	progress = {
		"completed_tutorial": false,
		"passed_pre_assessment": false,
		"first_live_call_done": false,
		"selected_mode": "easy_multiple_choice",
		"profressional_difficulty": "easy",
		"certifications": [],
		"completed_modules": [],
		"locale": "en",
		"perfectionist_mode": true,
		"current_day_easy_multiple_choice": 1,
		"current_day_profressional_nlp_dispatch": 1,
		"daily_results_easy_multiple_choice": [],
		"daily_results_profressional_nlp_dispatch": [],
		"saved_shift_easy_multiple_choice": {},
		"saved_shift_profressional_nlp_dispatch": {}
	}
	save_progress()

func set_use_legacy_map(val: bool) -> void:
	progress["legacy_map"] = val
	save_progress()

func get_use_legacy_map() -> bool:
	return bool(progress.get("legacy_map", false))

func set_locale(locale: String) -> void:
	if locale in ["en", "tl", "taglish"]:
		progress["locale"] = locale
		save_progress()

func get_locale() -> String:
	return String(progress.get("locale", "en"))

func set_perfectionist_mode(val: bool) -> void:
	progress["perfectionist_mode"] = val
	save_progress()

func get_perfectionist_mode() -> bool:
	return bool(progress.get("perfectionist_mode", true))

# ── Saved-shift accessors ─────────────────────────────────────────────────────
func get_saved_shift() -> Dictionary:
	return _get_shift_dict("saved_shift_" + _active_mode_id())

func get_saved_shift_for_mode(mode_id: String) -> Dictionary:
	return _get_shift_dict("saved_shift_" + mode_id)

func save_shift_progress(shift_data: Dictionary) -> void:
	progress["saved_shift_" + _active_mode_id()] = shift_data
	save_progress()

func clear_shift_progress() -> void:
	progress["saved_shift_" + _active_mode_id()] = {}
	save_progress()

func clear_shift_progress_for_mode(mode_id: String) -> void:
	progress["saved_shift_" + mode_id] = {}
	save_progress()

# ── Internal: safe dictionary fetch for shift slots ──────────────────────────
func _get_shift_dict(key: String) -> Dictionary:
	var shift = progress.get(key)
	return shift if typeof(shift) == TYPE_DICTIONARY else {}

# Resets only Profressional mode data back to Day 1.
# All Normal mode keys (tutorial, pre-assessment, certifications, modules,
# locale, day counter, shift history, in-progress shift) are left completely
# untouched.
func reset_profressional_progress() -> void:
	progress["saved_shift_profressional_nlp_dispatch"]    = {}
	progress["current_day_profressional_nlp_dispatch"]    = 1
	progress["daily_results_profressional_nlp_dispatch"]  = []
	progress["profressional_difficulty"]                  = "easy"
	save_progress()

# Resets only Normal / Easy mode data back to Day 1.
# Professional mode keys, tutorial, pre-assessment, certifications, modules,
# and locale are all left completely untouched.
func reset_easy_progress() -> void:
	progress["saved_shift_easy_multiple_choice"]   = {}
	progress["current_day_easy_multiple_choice"]   = 1
	progress["daily_results_easy_multiple_choice"] = []
	save_progress()


func get_total_historical_calls() -> int:
	var total = 0
	for res in (progress.get("daily_results", []) as Array):
		if typeof(res) == TYPE_DICTIONARY:
			total += int(res.get("calls_completed", 0))
	return total

# ── Audio volume persistence ──────────────────────────────────────────────────
func set_audio_volumes(master: float, bgm: float, siren: float) -> void:
	progress["audio_master"] = master
	progress["audio_bgm"]    = bgm
	progress["audio_siren"]  = siren
	save_progress()

func get_audio_volumes() -> Dictionary:
	return {
		"master": float(progress.get("audio_master", 1.0)),
		"bgm":    float(progress.get("audio_bgm",    0.7)),
		"siren":  float(progress.get("audio_siren",  0.7)),
	}
