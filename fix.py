import re

file_path = 'scripts/maps/route_scene.gd'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix audio manager bug
audio_bug = '''	var am = get_node_or_null("/root/AudioManager")
	if am:
		var am = get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_click"):
			am.play_click()'''
audio_fix = '''	var am = get_node_or_null("/root/AudioManager")
	if am:
		am.play_click()'''

if audio_bug in content:
    content = content.replace(audio_bug, audio_fix)
    print("Fixed audio bug")
else:
    print("Audio bug not found")

# Fix button disable bug
button_bug = '''	_has_dispatched_vehicle = true
	if _selected_mode_id == "easy_multiple_choice":
		_dispatch_phase_unlocked = false
	var btn = _vehicle_buttons.get(vehicle_id)

	var selected_vehicle = _canonical_vehicle_id(vehicle_id)'''
button_fix = '''	_has_dispatched_vehicle = true
	if _selected_mode_id == "easy_multiple_choice":
		_dispatch_phase_unlocked = false
	var btn = _vehicle_buttons.get(vehicle_id)
	if btn:
		btn.disabled = true

	var selected_vehicle = _canonical_vehicle_id(vehicle_id)'''

if button_bug in content:
    content = content.replace(button_bug, button_fix)
    print("Fixed button bug")
else:
    print("Button bug not found")

# Fix dispatch logic
match = re.search(r'	else:\n\s+dispatch_title = "[^"]+"\n\s+dispatch_explanation = "Recommended unit\(s\): \%s\\n\%s" \% \[recommended_str, _mismatch_vehicle_detail\(selected_vehicle, recommended_list, incident_type\)\]\n\s+if _assignment_label:\n\s+_assignment_label\.text = "Unit sent\. Recommended was \%s\." \% recommended_str\n\n\s+if _feedback_dialog:\n\s+if _selected_mode_id == "easy_multiple_choice":\n\s+_feedback_popup_context = "vehicle_dispatch"', content)

if match:
    replacement = '''	else:
		if _selected_mode_id == "easy_multiple_choice":
			dispatch_title = "Incorrect Unit Sent"
			dispatch_explanation = "This unit cannot handle the emergency. Please recall them and send the recommended unit(s): %s\\n\\nReason:\\n%s" % [recommended_str, _mismatch_vehicle_detail(selected_vehicle, recommended_list, incident_type)]
			if _assignment_label:
				_assignment_label.text = "Incorrect unit sent. Try again."
			
			_has_dispatched_vehicle = false 
			_dispatch_phase_unlocked = true

			if _feedback_dialog:
				_feedback_popup_context = ""
				_apply_dialog_color_and_juice(false, true)
				_feedback_dialog.dialog_text = "%s\\n\\nYour Dispatch: %s\\n\\nWhy:\\n%s" % [dispatch_title, selected_name, dispatch_explanation]
				_feedback_dialog.popup_centered(Vector2i(760, 320))
				_apply_dialog_juice(false, true)
				
			if btn:
				btn.disabled = false 
			_set_vehicle_buttons_enabled(true)
			return
		else:
			dispatch_title = "Incorrect Dispatch Sent"
			dispatch_explanation = "Recommended unit(s): %s\\n%s" % [recommended_str, _mismatch_vehicle_detail(selected_vehicle, recommended_list, incident_type)]
			if _assignment_label:
				_assignment_label.text = "Unit sent. Recommended was %s." % recommended_str

	if _feedback_dialog:
		if _selected_mode_id == "easy_multiple_choice":
			_feedback_popup_context = "vehicle_dispatch"'''
    content = content[:match.start()] + replacement + content[match.end():]
    print("Fixed dispatch logic")
else:
    print("Dispatch logic not found")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

