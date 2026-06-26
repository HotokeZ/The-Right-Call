with open('scripts/maps/route_scene.gd', 'r', encoding='utf-8') as f:
    code = f.read()

# Helper function to clean text for Normal mode
clean_func = '''func _clean_option_text_for_normal_mode(text: String) -> String:
	var lower = text.to_lower()
	var stripped = text
	
	# English prefixes
	var en_prefixes = [
		"i am sending help right away. ",
		"i am sending help. ",
		"i will send someone. ",
		"i am sending an ambulance. "
	]
	for p in en_prefixes:
		if lower.begins_with(p):
			stripped = text.substr(p.length()).strip_edges()
			lower = stripped.to_lower()
	
	# Tagalog prefixes
	var tl_prefixes = [
		"padating na po ang tulong. "
	]
	for p in tl_prefixes:
		if lower.begins_with(p):
			stripped = text.substr(p.length()).strip_edges()
			lower = stripped.to_lower()
			
	# Cleanup any leftover dots or spaces
	if stripped == "." or stripped == ".." or stripped == "..." or stripped == "":
		return ""
		
	# Capitalize first letter if needed
	if stripped.length() > 0:
		stripped = stripped.left(1).to_upper() + stripped.substr(1)
		
	return stripped

func _get_scenario_bad_texts(fallback_defaults: Array) -> Array:'''

code = code.replace("func _get_scenario_bad_texts(fallback_defaults: Array) -> Array:", clean_func)

# Now update _get_scenario_bad_texts to use it and filter out empty strings
bad_texts_old = '''func _get_scenario_bad_texts(fallback_defaults: Array) -> Array:
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

bad_texts_new = '''func _get_scenario_bad_texts(fallback_defaults: Array) -> Array:
	var bad = []
	var scenario_opts: Array = _get_scenario_options()
	for opt in scenario_opts:
		if typeof(opt) == TYPE_DICTIONARY and String(opt.get("label", "")).to_lower() == "unsafe":
			var text = String(opt.get("text", "")).strip_edges()
			text = _clean_option_text_for_normal_mode(text)
			if text != "":
				bad.append(text)
	
	if bad.size() == 0:
		bad = fallback_defaults.duplicate()
	
	bad.shuffle()
	return bad'''

code = code.replace(bad_texts_old, bad_texts_new)

# Now update _show_player_choices to use it
show_choices_old = '''		if _choices_box:
			var options: Array = _get_scenario_options()
			var safe_opts: Array = []
			var unsafe_opts: Array = []
			
			for opt in options:
				if typeof(opt) == TYPE_DICTIONARY:
					var text = String(opt.get("text", ""))
					var label = String(opt.get("label", "")).to_lower()
					if label == "safe":
						safe_opts.append(opt)
					elif label == "unsafe":
						unsafe_opts.append(opt)'''

show_choices_new = '''		if _choices_box:
			var options: Array = _get_scenario_options()
			var safe_opts: Array = []
			var unsafe_opts: Array = []
			
			for opt in options:
				if typeof(opt) == TYPE_DICTIONARY:
					var text = String(opt.get("text", ""))
					var clean_text = _clean_option_text_for_normal_mode(text)
					if clean_text == "":
						continue
						
					var new_opt = opt.duplicate()
					new_opt["text"] = clean_text
					
					var label = String(opt.get("label", "")).to_lower()
					if label == "safe":
						safe_opts.append(new_opt)
					elif label == "unsafe":
						unsafe_opts.append(new_opt)
						
			if safe_opts.is_empty():
				safe_opts.append({
					"text": "Evacuate the area immediately and ensure your safety.",
					"label": "safe",
					"explanation": "Standard safety protocol when no other safe options are available."
				})'''

code = code.replace(show_choices_old, show_choices_new)

with open('scripts/maps/route_scene.gd', 'w', encoding='utf-8') as f:
    f.write(code)
