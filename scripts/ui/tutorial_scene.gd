extends Control

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const THEME_BG := Color8(255, 244, 229)
const TEXT_DARK := Color8(44, 54, 72)

var _steps: Array = []
var _index: int = 0

@onready var root_bg: ColorRect = $CanvasLayer/Root
@onready var title_label: Label = $CanvasLayer/Root/Margin/Layout/Header/TitleLabel
@onready var subtitle_label: Label = $CanvasLayer/Root/Margin/Layout/Header/SubtitleLabel
@onready var step_counter_label: Label = $CanvasLayer/Root/Margin/Layout/Body/BodyMargin/Content/StepCounterLabel
@onready var step_title_label: Label = $CanvasLayer/Root/Margin/Layout/Body/BodyMargin/Content/StepTitleLabel
@onready var step_body_label: Label = $CanvasLayer/Root/Margin/Layout/Body/BodyMargin/Content/StepBodyLabel
@onready var coach_tip_label: Label = $CanvasLayer/Root/Margin/Layout/Body/BodyMargin/Content/CoachTipLabel
@onready var back_button: Button = $CanvasLayer/Root/Margin/Layout/Footer/BackButton
@onready var next_button: Button = $CanvasLayer/Root/Margin/Layout/Footer/NextButton
@onready var finish_button: Button = $CanvasLayer/Root/Margin/Layout/Footer/FinishButton

func _state() -> Node:
	return get_node_or_null("/root/GameState")

func _ready() -> void:
	var state = _state()
	if state:
		_steps = state.call("get_tutorial_steps")
		title_label.text = String(state.call("get_tutorial_title"))
		subtitle_label.text = String(state.call("get_tutorial_subtitle"))
	else:
		_steps = []
		title_label.text = "Tutorial"
		subtitle_label.text = "Game state system unavailable."
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	finish_button.pressed.connect(_on_finish_pressed)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_apply_kids_theme()
	_refresh_step()

func _on_viewport_resized() -> void:
	_apply_kids_theme()

func _style_footer_button(btn: Button, base_color: Color, hover_color: Color, is_mobile: bool) -> void:
	if btn == null:
		return
	btn.custom_minimum_size = Vector2(0, 74 if is_mobile else 52)
	btn.add_theme_font_size_override("font_size", 23 if is_mobile else 17)
	btn.add_theme_color_override("font_color", TEXT_DARK)

	var normal = StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.border_width_left = 3
	normal.border_width_top = 3
	normal.border_width_right = 3
	normal.border_width_bottom = 3
	normal.border_color = Color(1.0, 1.0, 1.0, 0.8)

	var hover = normal.duplicate()
	hover.bg_color = hover_color

	var disabled = normal.duplicate()
	disabled.bg_color = Color(0.72, 0.76, 0.8, 0.85)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("disabled", disabled)

func _apply_kids_theme() -> void:
	var vp_width = get_viewport().get_visible_rect().size.x
	var is_mobile = vp_width <= 900.0

	if root_bg:
		root_bg.color = THEME_BG

	var body_panel: PanelContainer = get_node_or_null("CanvasLayer/Root/Margin/Layout/Body")
	if body_panel:
		var body_style = StyleBoxFlat.new()
		body_style.bg_color = Color8(255, 238, 208)
		body_style.corner_radius_top_left = 22
		body_style.corner_radius_top_right = 22
		body_style.corner_radius_bottom_left = 22
		body_style.corner_radius_bottom_right = 22
		body_style.border_width_left = 4
		body_style.border_width_top = 4
		body_style.border_width_right = 4
		body_style.border_width_bottom = 4
		body_style.border_color = Color8(255, 160, 86)
		body_panel.add_theme_stylebox_override("panel", body_style)

	if title_label:
		title_label.add_theme_font_size_override("font_size", 42 if is_mobile else 32)
		title_label.add_theme_color_override("font_color", TEXT_DARK)
	if subtitle_label:
		subtitle_label.add_theme_font_size_override("font_size", 22 if is_mobile else 17)
		subtitle_label.add_theme_color_override("font_color", Color8(72, 82, 98))
	if step_counter_label:
		step_counter_label.add_theme_font_size_override("font_size", 20 if is_mobile else 15)
		step_counter_label.add_theme_color_override("font_color", Color8(72, 82, 98))
	if step_title_label:
		step_title_label.add_theme_font_size_override("font_size", 36 if is_mobile else 28)
		step_title_label.add_theme_color_override("font_color", TEXT_DARK)
	if step_body_label:
		step_body_label.add_theme_font_size_override("font_size", 26 if is_mobile else 20)
		step_body_label.add_theme_color_override("font_color", TEXT_DARK)
	if coach_tip_label:
		coach_tip_label.add_theme_font_size_override("font_size", 22 if is_mobile else 17)
		coach_tip_label.add_theme_color_override("font_color", Color8(140, 88, 34))

	_style_footer_button(back_button, Color8(255, 205, 104), Color8(255, 219, 135), is_mobile)
	_style_footer_button(next_button, Color8(92, 195, 255), Color8(117, 210, 255), is_mobile)
	_style_footer_button(finish_button, Color8(109, 205, 119), Color8(132, 220, 140), is_mobile)

func _refresh_step() -> void:
	if _steps.is_empty():
		step_counter_label.text = "No tutorial steps configured."
		step_title_label.text = "Tutorial unavailable"
		step_body_label.text = "Add tutorial steps to data/gameplay/tutorial_steps.json."
		coach_tip_label.text = ""
		back_button.disabled = true
		next_button.disabled = true
		finish_button.disabled = false
		return

	var step: Dictionary = _steps[_index]
	step_counter_label.text = "Lesson %d of %d" % [_index + 1, _steps.size()]
	step_title_label.text = String(step.get("title", "Untitled lesson"))
	step_body_label.text = String(step.get("body", ""))
	coach_tip_label.text = "Coach tip: %s" % String(step.get("coach_tip", ""))
	back_button.disabled = _index == 0
	next_button.disabled = _index >= _steps.size() - 1
	finish_button.disabled = _index < _steps.size() - 1

func _on_back_pressed() -> void:
	if _index > 0:
		_index -= 1
		_refresh_step()

func _on_next_pressed() -> void:
	if _index < _steps.size() - 1:
		_index += 1
		_refresh_step()

func _on_finish_pressed() -> void:
	var state = _state()
	if state:
		state.call("complete_tutorial")
	get_tree().change_scene_to_file(MENU_SCENE)
