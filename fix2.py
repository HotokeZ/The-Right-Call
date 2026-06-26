import re

file_path = 'scripts/maps/route_scene.gd'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

bug = '''	if _selected_mode_id == "easy_multiple_choice":
		_start_dispatch_phase()
	else:
		if _response_prompt_label:
			_response_prompt_label.text = "Type your response to the caller:"
		if _typed_row:
			_typed_row.visible = true
		if _is_interactive_tutorial and _typed_submit_button:
			_point_coach_at(_typed_submit_button, "Submit")'''

fix = '''	if _selected_mode_id == "easy_multiple_choice":
		if _response_prompt_label:
			_response_prompt_label.text = "Select the best response:"
		if _choices_box:
			var options: Array = _active_call.get("options", [])
			var safe_opts: Array = []
			var unsafe_opts: Array = []
			
			for i in range(options.size()):
				if String(options[i].get("label", "unsafe")).to_lower() == "safe":
					safe_opts.append(i)
				else:
					unsafe_opts.append(i)
					
			var diff = "easy"
			var game_state = get_node_or_null("/root/GameState")
			if game_state and game_state.has_method("get_profressional_difficulty"):
				diff = String(game_state.call("get_profressional_difficulty"))
				
			var num_unsafe = 1
			if diff == "medium": num_unsafe = 2
			elif diff == "hard": num_unsafe = 3
			
			unsafe_opts.shuffle()
			var final_opts: Array = []
			
			if safe_opts.size() > 0:
				safe_opts.shuffle()
				final_opts.append(safe_opts[0])
			
			for i in range(min(num_unsafe, unsafe_opts.size())):
				final_opts.append(unsafe_opts[i])
				
			final_opts.shuffle()
			
			for idx in final_opts:
				var btn = Button.new()
				btn.text = String(options[idx].get("text", ""))
				btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_style_choice_button(btn, _ui_scale_factor())
				btn.pressed.connect(Callable(self, "_on_choice_option_pressed").bind(idx))
				_choices_box.add_child(btn)
	else:
		if _response_prompt_label:
			_response_prompt_label.text = "Type your response to the caller:"
		if _typed_row:
			_typed_row.visible = true
		if _is_interactive_tutorial and _typed_submit_button:
			_point_coach_at(_typed_submit_button, "Submit")'''

if bug in content:
    content = content.replace(bug, fix)
    print("Fixed _show_player_choices")
else:
    print("Could not find bug block")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

