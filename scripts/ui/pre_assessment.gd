extends Control

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var questions: Array = [
	{
		"q": "What is the very first thing you should do in a severe emergency?",
		"options": ["Call the local emergency hotline (911)", "Try to solve it yourself", "Post a video about it"],
		"answer": 0,
		"hint": "Always get trained professionals on the way immediately."
	},
	{
		"q": "If a caller reports a building has collapsed with people trapped inside, which unit should you deploy?",
		"options": ["Fire Truck", "Ambulance", "Police"],
		"answer": 0,
		"hint": "The Fire Truck handles heavy technical operations like extrication of trapped victims."
	},
	{
		"q": "A caller is panicking because of a grease fire on the stove. What should they do?",
		"options": ["Throw a bucket of water on the stove", "Turn off the heat and smother it with a metal lid", "Try to carry the burning pan outside"],
		"answer": 1,
		"hint": "Never use water on a grease fire; it causes an explosion."
	},
	{
		"q": "Someone has a deep cut and is bleeding heavily. What is the best first aid step?",
		"options": ["Wash the cut with running water", "Apply firm, direct pressure with a clean cloth", "Remove the bandage to check the wound"],
		"answer": 1,
		"hint": "Direct pressure is the most effective immediate way to stop severe bleeding."
	},
	{
		"q": "A caller reports an armed robbery in progress. What should they do?",
		"options": ["Hide, stay quiet, and do not draw attention", "Run out to film their faces closely", "Yell at them to stop"],
		"answer": 0,
		"hint": "Your life is more important than property. Stay hidden."
	}
]

var _idx: int = 0
var _selected_choice: int = -1

@onready var count_label: Label = $CanvasLayer/Root/Margin/Layout/Body/BodyMargin/VBox/QuestionCountLabel
@onready var question_label: Label = $CanvasLayer/Root/Margin/Layout/Body/BodyMargin/VBox/QuestionLabel
@onready var choices_box: VBoxContainer = $CanvasLayer/Root/Margin/Layout/Body/BodyMargin/VBox/ChoicesBox
@onready var feedback_label: Label = $CanvasLayer/Root/Margin/Layout/Body/BodyMargin/VBox/FeedbackLabel

@onready var back_btn: Button = $CanvasLayer/Root/Margin/Layout/Footer/BackButton
@onready var next_btn: Button = $CanvasLayer/Root/Margin/Layout/Footer/NextButton

func _state() -> Node:
	return get_node_or_null("/root/GameState")

func _ready() -> void:
	back_btn.pressed.connect(_on_back_pressed)
	next_btn.pressed.connect(_on_next_pressed)
	_load_question()

func _load_question() -> void:
	_selected_choice = -1
	feedback_label.text = ""
	next_btn.disabled = true
	count_label.text = "Question %d of %d" % [_idx + 1, questions.size()]
	
	var q_data = questions[_idx]
	question_label.text = q_data["q"]
	
	for c in choices_box.get_children():
		c.queue_free()
		
	var i = 0
	for opt in q_data["options"]:
		var btn = Button.new()
		btn.text = opt
		btn.custom_minimum_size = Vector2(0, 40)
		
		# Adding basic multiple choice styling
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.35, 0.40, 1.0)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", style)
		
		var hover = style.duplicate()
		hover.bg_color = Color(0.2, 0.45, 0.50, 1.0)
		btn.add_theme_stylebox_override("hover", hover)
		
		btn.pressed.connect(Callable(self, "_on_choice_selected").bind(i))
		choices_box.add_child(btn)
		i += 1

func _on_choice_selected(choice_idx: int) -> void:
	_selected_choice = choice_idx
	var q_data = questions[_idx]
	
	if choice_idx == q_data["answer"]:
		feedback_label.add_theme_color_override("font_color", Color(0.1, 0.6, 0.1, 1.0))
		feedback_label.text = "Correct! " + q_data["hint"]
		
		# Color the correct button green
		for i in range(choices_box.get_child_count()):
			choices_box.get_child(i).disabled = true
			if i == choice_idx:
				var style = StyleBoxFlat.new()
				style.bg_color = Color(0.2, 0.6, 0.2, 1.0)
				choices_box.get_child(i).add_theme_stylebox_override("disabled", style)
			else:
				var style2 = StyleBoxFlat.new()
				style2.bg_color = Color(0.6, 0.6, 0.6, 1.0)
				choices_box.get_child(i).add_theme_stylebox_override("disabled", style2)
				
		if _idx == questions.size() - 1:
			next_btn.text = "Finish Quiz"
		else:
			next_btn.text = "Next Question"
		next_btn.disabled = false
	else:
		feedback_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 1.0))
		feedback_label.text = "Incorrect! Try again. Remember: " + q_data["hint"]

func _on_next_pressed() -> void:
	if _idx < questions.size() - 1:
		_idx += 1
		_load_question()
	else:
		var state = _state()
		if state:
			state.call("pass_pre_assessment")
		get_tree().change_scene_to_file(MENU_SCENE)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
