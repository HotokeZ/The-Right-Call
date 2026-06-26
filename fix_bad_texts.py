with open('scripts/maps/route_scene.gd', 'r', encoding='utf-8') as f:
    code = f.read()

# Update _get_scenario_options
old_func = '''func _get_scenario_options() -> Array:
	if _active_call.is_empty(): return []
	var transcript: Array = _active_call.get("transcript", [])
	if transcript.is_empty() and _active_call.has("transcript_en"):
		transcript = _active_call.get("transcript_en", [])
	for i in range(transcript.size() - 1, -1, -1):
		if typeof(transcript[i]) == TYPE_DICTIONARY and transcript[i].has("options"):
			return transcript[i].get("options", [])
	return _active_call.get("options", [])'''

new_func = '''func _get_scenario_options() -> Array:
	if _active_call.is_empty(): return []
	var transcript: Array = _active_call.get("transcript", [])
	if transcript.is_empty() and _active_call.has("transcript_en"):
		transcript = _active_call.get("transcript_en", [])
	for i in range(transcript.size() - 1, -1, -1):
		var item = transcript[i]
		if typeof(item) == TYPE_DICTIONARY and item.has("options"):
			var spk = String(item.get("speaker", "")).to_lower()
			if spk == "911" or spk == "dispatcher" or spk == "operator":
				return item.get("options", [])
	return _active_call.get("options", [])

func _get_scenario_bad_texts(fallback_defaults: Array) -> Array:
	var bad = []
	var scenario_opts: Array = _get_scenario_options()
	for opt in scenario_opts:
		if typeof(opt) == TYPE_DICTIONARY and String(opt.get("label", "")).to_lower() == "unsafe":
			var text = String(opt.get("text", "")).strip_edges()
			if text != "":
				bad.append(text)
	
	if bad.size() == 0:
		bad = fallback_defaults.duplicate()
	
	bad.shuffle()
	return bad'''

code = code.replace(old_func, new_func)

# Replace the three instances of hardcoded bad_texts
# Instance 1: location
loc_old = '''		var bad_texts = [
			"Please hold for a few minutes.",
			"Can you handle the situation yourself?",
			"Try to resolve it before units arrive."
		]
		bad_texts.shuffle()'''
loc_new = '''		var bad_texts = _get_scenario_bad_texts([
			"Please hold for a few minutes.",
			"Can you handle the situation yourself?",
			"Try to resolve it before units arrive."
		])'''
code = code.replace(loc_old, loc_new)

# Instance 2: complaint
comp_old = '''			var bad_texts = [
				"Are you sure this isn't a false alarm?",
				"Please calm down and call back later.",
				"We are busy, what do you want?"
			]
			bad_texts.shuffle()'''
comp_new = '''			var bad_texts = _get_scenario_bad_texts([
				"Are you sure this isn't a false alarm?",
				"Please calm down and call back later.",
				"We are busy, what do you want?"
			])'''
code = code.replace(comp_old, comp_new)

# Instance 3: _show_dispatcher_prompt
disp_old = '''		var bad_texts = [
			"There's nothing we can do right now.",
			"Try to confront them yourself.",
			"Please hold, we are very busy.",
			"Just wait there until the problem goes away.",
			"Are you sure you need emergency services?",
			"Hang up and try calling the non-emergency line."
		]
		bad_texts.shuffle()'''
disp_new = '''		var bad_texts = _get_scenario_bad_texts([
			"There's nothing we can do right now.",
			"Try to confront them yourself.",
			"Please hold, we are very busy.",
			"Just wait there until the problem goes away.",
			"Are you sure you need emergency services?",
			"Hang up and try calling the non-emergency line."
		])'''
code = code.replace(disp_old, disp_new)

with open('scripts/maps/route_scene.gd', 'w', encoding='utf-8') as f:
    f.write(code)
