import re

with open('G:/Code/BFP - Copy (5)/new-game-project/scripts/maps/route_scene.gd', 'r', encoding='utf-8') as f:
    code = f.read()

p1 = r'''func _point_coach_at\(target: Control, prompt: String\) -> void:
	if not _is_interactive_tutorial:
		return
	if target == null or not target.is_visible_in_tree\(\):
		_hide_coach_pointer\(\)
		return
	_ensure_coach_pointer\(\)
	if _coach_pointer_label == null:
		return
	if _coach_pointer_tween:
		_coach_pointer_tween.kill\(\)
		_coach_pointer_tween = null
		
	if _tutorial_proceed_lbl:
		_tutorial_proceed_lbl.visible = true

	_coach_pointer_label.text = "%s" % prompt
	_coach_pointer_label.custom_minimum_size = Vector2\(400, 30\)
	_coach_pointer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var target_rect = target.get_global_rect\(\)
	var w = target.get_viewport\(\) as Window
	if w and w != get_viewport\(\):
		target_rect.position \+= Vector2\(w.position\)
		
	var vp = get_viewport\(\).get_visible_rect\(\).size'''

r1 = '''func _point_coach_at(target: Control, prompt: String) -> void:
	if not _is_interactive_tutorial:
		return
	if target == null or not target.is_visible_in_tree():
		_hide_coach_pointer()
		return
	_ensure_coach_pointer()
	if _coach_pointer_label == null:
		return
	if _coach_pointer_tween:
		_coach_pointer_tween.kill()
		_coach_pointer_tween = null
		
	var top_parent: Node = self
	if target.is_inside_tree():
		top_parent = target.get_viewport()
	var canvas = top_parent.get_node_or_null("TutorialTopLayer")
	if canvas == null:
		canvas = CanvasLayer.new()
		canvas.name = "TutorialTopLayer"
		canvas.layer = 128
		top_parent.add_child(canvas)
		
	if _coach_pointer_label.get_parent() != canvas:
		if _coach_pointer_label.get_parent():
			_coach_pointer_label.get_parent().remove_child(_coach_pointer_label)
		canvas.add_child(_coach_pointer_label)
		
	if _tutorial_proceed_lbl:
		_tutorial_proceed_lbl.visible = true

	_coach_pointer_label.text = "%s" % prompt
	_coach_pointer_label.custom_minimum_size = Vector2(400, 30)
	_coach_pointer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var target_rect = target.get_global_rect()
		
	var vp = top_parent.get_visible_rect().size'''

code = re.sub(p1, r1, code)

p2 = r'''func _show_tutorial_focus\(target: Variant\) -> void:
	if not _is_interactive_tutorial:
		return
	if target == null:
		_hide_tutorial_focus\(\)
		return
	_ensure_tutorial_focus_layer\(\)
	if _tutorial_focus_layer == null:
		return
	_tutorial_focus_target = target
	_tutorial_focus_layer.visible = true'''

r2 = '''func _show_tutorial_focus(target: Variant) -> void:
	if not _is_interactive_tutorial:
		return
	if target == null:
		_hide_tutorial_focus()
		return
	_ensure_tutorial_focus_layer()
	if _tutorial_focus_layer == null:
		return
		
	var top_parent: Node = self
	if typeof(target) == TYPE_OBJECT and target is Node and target.is_inside_tree():
		top_parent = target.get_viewport()
	var canvas = top_parent.get_node_or_null("TutorialTopLayer")
	if canvas == null:
		canvas = CanvasLayer.new()
		canvas.name = "TutorialTopLayer"
		canvas.layer = 128
		top_parent.add_child(canvas)
		
	if _tutorial_focus_layer.get_parent() != canvas:
		if _tutorial_focus_layer.get_parent():
			_tutorial_focus_layer.get_parent().remove_child(_tutorial_focus_layer)
		canvas.add_child(_tutorial_focus_layer)
		canvas.move_child(_tutorial_focus_layer, -1)
		
	_tutorial_focus_target = target
	_tutorial_focus_layer.visible = true'''

code = re.sub(p2, r2, code)

p3 = r'''	var vp = get_viewport\(\).get_visible_rect\(\).size
	var rect: Rect2
	if _tutorial_focus_target is Control:
		rect = _tutorial_focus_target.get_global_rect\(\)
		var w = _tutorial_focus_target.get_viewport\(\) as Window
		if w and w != get_viewport\(\):
			rect.position \+= Vector2\(w.position\)
		rect = rect.grow\(8.0\)
	elif _tutorial_focus_target is Window:
		rect = Rect2\(_tutorial_focus_target.position, _tutorial_focus_target.size\).grow\(8.0\)'''

r3 = '''	var top_parent: Viewport = get_viewport()
	if typeof(_tutorial_focus_target) == TYPE_OBJECT and _tutorial_focus_target is Node and _tutorial_focus_target.is_inside_tree():
		top_parent = _tutorial_focus_target.get_viewport()
		
	var vp = top_parent.get_visible_rect().size
	var rect: Rect2
	if _tutorial_focus_target is Control:
		rect = _tutorial_focus_target.get_global_rect()
		rect = rect.grow(8.0)
	elif _tutorial_focus_target is Window:
		rect = Rect2(Vector2.ZERO, _tutorial_focus_target.size).grow(8.0)'''

code = re.sub(p3, r3, code)

with open('G:/Code/BFP - Copy (5)/new-game-project/scripts/maps/route_scene.gd', 'w', encoding='utf-8') as f:
    f.write(code)

print("Replaced.")
