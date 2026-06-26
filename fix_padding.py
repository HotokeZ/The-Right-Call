import re

with open('G:/Code/BFP - Copy (5)/new-game-project/scripts/maps/route_scene.gd', 'r', encoding='utf-8') as f:
    code = f.read()

p = r'''		if action_area is BoxContainer:
			action_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var parent_margin = action_area.get_parent\(\)
			if parent_margin and parent_margin is Control:
				parent_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			action_area.vertical = false
			action_area.custom_minimum_size = Vector2\(800, 0\)
			
			var spacer1 = Control.new\(\)
			spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer1.custom_minimum_size = Vector2\(200, 0\)
			var spacer2 = Control.new\(\)
			spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer2.custom_minimum_size = Vector2\(200, 0\)
			action_area.add_child\(spacer1\)
			action_area.add_child\(spacer2\)
			
			if _shift_review_other_button:
				action_area.move_child\(_shift_review_other_button, 0\)
			action_area.move_child\(spacer1, 1\)
			action_area.move_child\(_shift_review_dialog.get_ok_button\(\), 2\)
			action_area.move_child\(spacer2, 3\)
			if _shift_review_proceed_button:
				action_area.move_child\(_shift_review_proceed_button, 4\)'''

r = '''		if action_area is BoxContainer:
			action_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var parent_margin = action_area.get_parent()
			if parent_margin and parent_margin is Control:
				parent_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if parent_margin is VBoxContainer:
					var bottom_pad = Control.new()
					bottom_pad.custom_minimum_size = Vector2(0, 16)
					parent_margin.add_child(bottom_pad)
					parent_margin.move_child(bottom_pad, -1)
			action_area.vertical = false
			action_area.custom_minimum_size = Vector2(800, 0)
			
			var left_pad = Control.new()
			left_pad.custom_minimum_size = Vector2(24, 0)
			var right_pad = Control.new()
			right_pad.custom_minimum_size = Vector2(24, 0)
			
			var spacer1 = Control.new()
			spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer1.custom_minimum_size = Vector2(200, 0)
			var spacer2 = Control.new()
			spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer2.custom_minimum_size = Vector2(200, 0)
			
			action_area.add_child(left_pad)
			action_area.add_child(right_pad)
			action_area.add_child(spacer1)
			action_area.add_child(spacer2)
			
			var idx = 0
			action_area.move_child(left_pad, idx)
			idx += 1
			if _shift_review_other_button:
				action_area.move_child(_shift_review_other_button, idx)
				idx += 1
			action_area.move_child(spacer1, idx)
			idx += 1
			action_area.move_child(_shift_review_dialog.get_ok_button(), idx)
			idx += 1
			action_area.move_child(spacer2, idx)
			idx += 1
			if _shift_review_proceed_button:
				action_area.move_child(_shift_review_proceed_button, idx)
				idx += 1
			action_area.move_child(right_pad, idx)'''

code = re.sub(p, r, code)

with open('G:/Code/BFP - Copy (5)/new-game-project/scripts/maps/route_scene.gd', 'w', encoding='utf-8') as f:
    f.write(code)

print("Replaced.")
