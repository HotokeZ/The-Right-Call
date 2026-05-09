extends Control

const ROUTE_SCENE := "res://scenes/maps/route_scene.tscn"
const TUTORIAL_SCENE := "res://scenes/ui/tutorial_scene.tscn"
const PRE_ASSESS_SCENE := "res://scenes/ui/pre_assessment.tscn"
const THEME_BG := Color8(255, 244, 229)
const TEXT_DARK := Color8(44, 54, 72)

@onready var root_bg: ColorRect = $CanvasLayer/Root
@onready var title_label: Label = $CanvasLayer/Root/Margin/Layout/Hero/HeroMargin/HeroContent/TitleLabel
@onready var subtitle_label: Label = $CanvasLayer/Root/Margin/Layout/Hero/HeroMargin/HeroContent/SubtitleLabel
@onready var status_label: Label = $CanvasLayer/Root/Margin/Layout/Hero/HeroMargin/HeroContent/StatusLabel
@onready var tutorial_button: Button = $CanvasLayer/Root/Margin/Layout/Actions/TutorialButton
@onready var pre_assess_button: Button = $CanvasLayer/Root/Margin/Layout/Actions/PreAssessButton
@onready var easy_button: Button = $CanvasLayer/Root/Margin/Layout/Actions/EasyButton
@onready var certified_button: Button = $CanvasLayer/Root/Margin/Layout/Actions/CertifiedButton
@onready var certification_label: Label = $CanvasLayer/Root/Margin/Layout/CertificationCard/CertificationMargin/CertificationLabel

var _difficulty_popup: ConfirmationDialog
var _save_popup: ConfirmationDialog

func _ready() -> void:
	tutorial_button.pressed.connect(_on_tutorial_pressed)
	pre_assess_button.pressed.connect(_on_pre_assess_pressed)
	easy_button.pressed.connect(_on_easy_pressed)
	certified_button.pressed.connect(_on_certified_pressed)
	get_viewport().size_changed.connect(_on_viewport_resized)
	
	_difficulty_popup = ConfirmationDialog.new()
	_difficulty_popup.title = "Select Certified Difficulty"
	
	var vbox = VBoxContainer.new()
	vbox.name = "DiffVBox"
	
	var msg_label = Label.new()
	msg_label.text = "Select your dispatch difficulty. Harder modes take longer to resolve.\nMedium unlocks after 3 shifts, Hard after 6 shifts."
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(msg_label)
	
	var e_btn = Button.new()
	e_btn.text = "Easy"
	e_btn.pressed.connect(_on_difficulty_easy)
	vbox.add_child(e_btn)
	var m_btn = Button.new()
	m_btn.text = "Medium"
	m_btn.pressed.connect(func(): _on_difficulty_custom_action("medium"))
	vbox.add_child(m_btn)
	var h_btn = Button.new()
	h_btn.text = "Hard"
	h_btn.pressed.connect(func(): _on_difficulty_custom_action("hard"))
	vbox.add_child(h_btn)
	var c_btn = Button.new()
	c_btn.text = "Cancel Menu"
	c_btn.pressed.connect(_difficulty_popup.hide)
	vbox.add_child(c_btn)
	
	_difficulty_popup.add_child(vbox)
	_difficulty_popup.get_ok_button().hide()
	_difficulty_popup.get_cancel_button().hide()
	add_child(_difficulty_popup)
	
	_save_popup = ConfirmationDialog.new()
	_save_popup.title = "Progress Found"
	var svbox = VBoxContainer.new()
	
	var smsg = Label.new()
	smsg.text = "You have a saved shift or day progress. What would you like to do?"
	smsg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	smsg.custom_minimum_size = Vector2(400, 0)
	svbox.add_child(smsg)
	
	var continue_btn = Button.new()
	continue_btn.text = "Continue Shift"
	continue_btn.pressed.connect(_on_continue_shift)
	svbox.add_child(continue_btn)
	
	var restart_shift_btn = Button.new()
	restart_shift_btn.text = "Restart Shift (Clear current shift progress)"
	restart_shift_btn.pressed.connect(_on_restart_shift)
	svbox.add_child(restart_shift_btn)
	
	var restart_all_btn = Button.new()
	restart_all_btn.text = "Restart to Day 1 (Clear ALL progress)"
	restart_all_btn.pressed.connect(_on_restart_all)
	svbox.add_child(restart_all_btn)
	
	var scan_btn = Button.new()
	scan_btn.text = "Cancel Menu"
	scan_btn.pressed.connect(_save_popup.hide)
	svbox.add_child(scan_btn)
	
	_save_popup.add_child(svbox)
	_save_popup.get_ok_button().hide()
	_save_popup.get_cancel_button().hide()
	add_child(_save_popup)
	
	_apply_kids_theme()
	_refresh_ui()

func _on_viewport_resized() -> void:
	_apply_kids_theme()

func _style_action_button(btn: Button, base_color: Color, hover_color: Color, text_color: Color, is_mobile: bool) -> void:
	if btn == null:
		return
	btn.custom_minimum_size = Vector2(0, 76 if is_mobile else 56)
	btn.add_theme_font_size_override("font_size", 24 if is_mobile else 18)
	btn.add_theme_color_override("font_color", text_color)

	var normal = StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.corner_radius_top_left = 14
	normal.corner_radius_top_right = 14
	normal.corner_radius_bottom_left = 14
	normal.corner_radius_bottom_right = 14
	normal.border_width_left = 3
	normal.border_width_top = 3
	normal.border_width_right = 3
	normal.border_width_bottom = 3
	normal.border_color = Color(1.0, 1.0, 1.0, 0.75)

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

	var hero_panel: PanelContainer = get_node_or_null("CanvasLayer/Root/Margin/Layout/Hero")
	if hero_panel:
		var hero_style = StyleBoxFlat.new()
		hero_style.bg_color = Color8(255, 236, 203)
		hero_style.corner_radius_top_left = 24
		hero_style.corner_radius_top_right = 24
		hero_style.corner_radius_bottom_left = 24
		hero_style.corner_radius_bottom_right = 24
		hero_style.border_width_left = 4
		hero_style.border_width_top = 4
		hero_style.border_width_right = 4
		hero_style.border_width_bottom = 4
		hero_style.border_color = Color8(255, 160, 86)
		hero_panel.add_theme_stylebox_override("panel", hero_style)

	var cert_panel: PanelContainer = get_node_or_null("CanvasLayer/Root/Margin/Layout/CertificationCard")
	if cert_panel:
		var cert_style = StyleBoxFlat.new()
		cert_style.bg_color = Color8(207, 233, 244)
		cert_style.corner_radius_top_left = 16
		cert_style.corner_radius_top_right = 16
		cert_style.corner_radius_bottom_left = 16
		cert_style.corner_radius_bottom_right = 16
		cert_style.border_width_left = 3
		cert_style.border_width_top = 3
		cert_style.border_width_right = 3
		cert_style.border_width_bottom = 3
		cert_style.border_color = Color8(85, 168, 211)
		cert_panel.add_theme_stylebox_override("panel", cert_style)

	if title_label:
		title_label.add_theme_font_size_override("font_size", 44 if is_mobile else 36)
		title_label.add_theme_color_override("font_color", TEXT_DARK)
	if subtitle_label:
		subtitle_label.add_theme_font_size_override("font_size", 22 if is_mobile else 18)
		subtitle_label.add_theme_color_override("font_color", Color8(72, 82, 98))
	if status_label:
		status_label.add_theme_font_size_override("font_size", 24 if is_mobile else 18)
		status_label.add_theme_color_override("font_color", TEXT_DARK)
	if certification_label:
		certification_label.add_theme_font_size_override("font_size", 21 if is_mobile else 16)
		certification_label.add_theme_color_override("font_color", TEXT_DARK)

	_style_action_button(tutorial_button, Color8(255, 174, 66), Color8(255, 193, 96), TEXT_DARK, is_mobile)
	_style_action_button(pre_assess_button, Color8(255, 196, 112), Color8(255, 210, 136), TEXT_DARK, is_mobile)
	_style_action_button(easy_button, Color8(84, 198, 255), Color8(112, 212, 255), TEXT_DARK, is_mobile)
	_style_action_button(certified_button, Color8(120, 198, 115), Color8(142, 212, 138), TEXT_DARK, is_mobile)

func _state() -> Node:
	return get_node_or_null("/root/GameState")

func _refresh_ui() -> void:
	var state = _state()
	if state == null:
		status_label.text = "Game state system unavailable."
		easy_button.disabled = true
		certified_button.disabled = true
		return

	var mode: Dictionary = state.call("get_selected_mode")
	var completed_tutorial: bool = bool(state.call("has_completed_tutorial"))
	var passed_pre_assessment: bool = bool(state.call("has_passed_pre_assessment"))

	if not passed_pre_assessment:
		status_label.text = "Welcome! Please pass the pre-assessment first before live dispatch training."
		tutorial_button.disabled = true
		easy_button.disabled = true
		certified_button.disabled = true
		pre_assess_button.disabled = false
		pre_assess_button.text = "Take Pre-Assessment"
	elif not completed_tutorial:
		status_label.text = "Pre-assessment passed. Start the tutorial next before entering live emergency calls."
		tutorial_button.disabled = false
		easy_button.disabled = true
		certified_button.disabled = true
		pre_assess_button.disabled = true
		pre_assess_button.text = "Pre-Assessment (Passed)"
	else:
		status_label.text = "Tutorial completed. Easy mode is ready, and certified mode will unlock after BFP certification."
		tutorial_button.disabled = false
		easy_button.disabled = false
		pre_assess_button.disabled = true
		pre_assess_button.text = "Pre-Assessment (Passed)"

	var day_number := 1
	if state.has_method("get_current_day"):
		day_number = int(state.call("get_current_day"))
	status_label.text += "\nCurrent shift day: Day %d" % day_number

	if state.has_method("get_latest_shift_result"):
		var latest: Dictionary = state.call("get_latest_shift_result")
		if not latest.is_empty():
			status_label.text += "\nLast saved day score: Day %d | %d pts" % [int(latest.get("day", 1)), int(latest.get("score", 0))]

	easy_button.text = "Play Easy Mode"
	var certified_mode: Dictionary = state.call("get_mode", "certified_nlp_dispatch")
	certified_button.text = certified_mode.get("title", "Certified Dispatcher")
	var force_certified_for_test := state.has_method("is_certified_mode_temporarily_forced") and bool(state.call("is_certified_mode_temporarily_forced"))
	var certified_unlocked: bool = bool(state.call("is_mode_unlocked", "certified_nlp_dispatch")) and (force_certified_for_test or (passed_pre_assessment and completed_tutorial))
	certified_button.disabled = not certified_unlocked
	if force_certified_for_test:
		certification_label.text = "Certification status: temporary test override enabled"
	elif certified_unlocked:
		certification_label.text = "Certification status: unlocked"
	else:
		certification_label.text = "Certification required: BFP Sta. Cruz Dispatch Certification"

	if not mode.is_empty():
		status_label.text += "\nCurrent selected mode: %s" % mode.get("title", "Easy")

func _on_tutorial_pressed() -> void:
	get_tree().change_scene_to_file(TUTORIAL_SCENE)

func _on_pre_assess_pressed() -> void:
	get_tree().change_scene_to_file(PRE_ASSESS_SCENE)

func _on_easy_pressed() -> void:
	var state = _state()
	if state:
		state.call("select_mode", "easy_multiple_choice")
	get_tree().change_scene_to_file(ROUTE_SCENE)

func _on_certified_pressed() -> void:
	var state = _state()
	if state == null:
		status_label.text = "Game state system unavailable."
		return
	if not bool(state.call("is_mode_unlocked", "certified_nlp_dispatch")):
		status_label.text = String(state.call("get_mode_lock_reason", "certified_nlp_dispatch"))
		return
		
	var saved_shift = state.call("get_saved_shift")
	if not saved_shift.is_empty():
		_save_popup.popup_centered()
	else:
		_difficulty_popup.popup_centered()

func _on_continue_shift() -> void:
	_save_popup.hide()
	var state = _state()
	if state:
		state.call("select_mode", "certified_nlp_dispatch")
	get_tree().change_scene_to_file(ROUTE_SCENE)

func _on_restart_shift() -> void:
	_save_popup.hide()
	var state = _state()
	if state:
		state.call("clear_shift_progress")
	_difficulty_popup.popup_centered()

func _on_restart_all() -> void:
	_save_popup.hide()
	var state = _state()
	if state:
		state.call("reset_progress")
		state.call("complete_tutorial")
		state.call("pass_pre_assessment")
		# Give back the certification so they can still play certified mode
		state.call("grant_certification", "bfp_sta_cruz_dispatch")
		state.call("clear_shift_progress")
	_difficulty_popup.popup_centered()

func _on_difficulty_custom_action(action: StringName) -> void:
	var state = _state()
	var current_day = int(state.call("get_current_day")) if state else 1
	var action_str = String(action)
	
	if action_str == "medium":
		if current_day <= 3:
			if _difficulty_popup.get_node("DiffVBox").get_child(0) is Label:
				_difficulty_popup.get_node("DiffVBox").get_child(0).text = "Medium difficulty will be unlocked after completing 3 shifts. (You are on Day %d)" % current_day
			return
		state.call("set_certified_difficulty", "medium")
	elif action_str == "hard":
		if current_day <= 6:
			if _difficulty_popup.get_node("DiffVBox").get_child(0) is Label:
				_difficulty_popup.get_node("DiffVBox").get_child(0).text = "Hard difficulty will be unlocked after completing 6 shifts. (You are on Day %d)" % current_day
			return
		state.call("set_certified_difficulty", "hard")
		
	_difficulty_popup.hide()
	if state:
		state.call("select_mode", "certified_nlp_dispatch")
	get_tree().change_scene_to_file(ROUTE_SCENE)

func _on_difficulty_easy() -> void:
	var state = _state()
	if state:
		state.call("set_certified_difficulty", "easy")
		state.call("select_mode", "certified_nlp_dispatch")
	get_tree().change_scene_to_file(ROUTE_SCENE)
