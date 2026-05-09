extends Node2D

@export var map_texture_path: String = "res://assets/maps/map.png"
@export var route_json_res_path: String = "res://data/routes/citywide_patrol_route.json"
@export var station_json_res_path: String = "res://data/gameplay/service_stations.json"
@export var main_menu_scene_path: String = "res://scenes/ui/main_menu.tscn"
@export var dispatch_initial_delay_s: float = 2.0
@export var dispatch_between_calls_min_s: float = 5.0
@export var dispatch_between_calls_max_s: float = 10.0
@export var transcript_tick_s: float = 0.9
@export var shift_duration_s: int = 300
@export var shift_min_score: int = 250
@export var max_waiting_calls: int = 3
@export var responder_speed_multiplier: float = 2.2
@export var responder_follow_smoothing: float = 10.0
@export var use_safe_road_overlay: bool = true
@export var road_inner_width_px: float = 8.0
@export var road_outline_width_px: float = 12.0
@export var road_inner_color: Color = Color8(243, 246, 252)
@export var road_outline_color: Color = Color8(126, 144, 168)

# Runtime map state
var _map_sprite: Sprite2D
var _map_high_sprite: Sprite2D = null
var _world_node: Node2D
var _img_w: int = 0
var _img_h: int = 0
var _current_scale: float = 1.0
var _min_scale: float = 1.0
var _max_scale: float = 4.0
var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _user_zoomed: bool = false
var _call_active: bool = false  # When true, map input is frozen
var _follow_dispatched_vehicle: bool = false
var _follow_vehicle_pos_valid: bool = false
var _follow_vehicle_world_pos: Vector2 = Vector2.ZERO
var _station_layer: Node2D = null
var _station_markers: Array = []
var _road_overlay_layer: Node2D = null

# Existing HUD nodes from scene
var _mode_label: Label
var _hint_label: Label
var _home_button: Button
var _hud_content: VBoxContainer

# Dispatch UI state
var _dim_overlay: ColorRect
var _dispatch_panel: PanelContainer
var _close_button: Button
var _tab_container: HBoxContainer
var _panel_header_label: Label
var _incident_summary_label: Label
var _incoming_label: Label
var _answer_button: Button
var _transcript_label: RichTextLabel
var _response_prompt_label: Label
var _choices_box: VBoxContainer
var _hint_button: Button
var _hint_display_label: RichTextLabel
var _typed_row: HBoxContainer
var _typed_input: LineEdit
var _typed_submit_button: Button
var _response_feedback_label: Label
var _assignment_label: Label
var _timeline_label: Label
var _end_call_button: Button
var _manual_panel: PanelContainer
var _manual_text: RichTextLabel
var _vehicle_buttons: Dictionary = {}
var _vehicle_grid: GridContainer
var _dispatch_phase_unlocked: bool = false

# Dispatch gameplay state
var _route_points_px: Array = []
var _pending_call: Dictionary = {}
var _active_call: Dictionary = {}
var _active_call_marker: Node2D = null
var _active_call_world_position: Vector2 = Vector2.ZERO
var _transcript_index: int = 0
var _awaiting_dispatch: bool = false
var _has_dispatched_vehicle: bool = false
var _services_arrived: bool = false
var _pending_resolution_s: float = 0.0
var _response_quality: String = "uncertain"
var _selected_mode_id: String = "easy_multiple_choice"
var _selected_locale: String = "en"
var _current_day: int = 1
var _day_difficulty_scale: float = 1.0
var _queued_calls: Array = []
var _conversation_log: Array = []  # Running log of {speaker, text} for LLM context
var _call_sequence: int = 0

# Interactive transcript state
var _is_interactive_tutorial: bool = false
var _tutorial_panel: PanelContainer = null
var _tutorial_label: Label = null
var _caller_lines: Array = []  # Filtered: only Caller/System lines
var _caller_line_index: int = 0  # Which caller line we're on
var _interactive_phase: int = 0  # 0=waiting, 1+=response round N
var _player_responded_this_round: bool = false
var _intake_stage: int = -1
var _location_revealed: bool = false
var _complaint_revealed: bool = false
var _awaiting_dispatcher_prompt: bool = false
var _expected_dispatcher_prompt_text: String = ""
var _professional_scored_tags: Dictionary = {}
var _coach_pointer_label: Label = null
var _coach_pointer_tween: Tween = null
var _tutorial_focus_layer: Control = null
var _tutorial_focus_blocks: Array = []
var _tutorial_focus_target: Control = null
var _tutorial_focus_tween: Tween = null

# Scoring
var _call_score: int = 0
var _total_score: int = 0
var _calls_completed: int = 0
var _call_start_time: float = 0.0
var _score_label: Label
var _shift_label: Label
var _feedback_dialog: AcceptDialog
var _feedback_popup_context: String = ""
var _kid_message_dialog: AcceptDialog
var _minimized_call_button: Button
var _next_day_button: Button
var _offscreen_indicator: Area2D
var _offscreen_indicator_arrow: Polygon2D
var _shift_remaining_s: int = 0
var _shift_time_complete_announced: bool = false
var _shift_ready_announced: bool = false
var _pending_day_restart: bool = false
var _post_shift_action: String = ""
var _shift_review_dialog: AcceptDialog
var _shift_review_list: VBoxContainer
var _shift_review_other_button: Button
var _other_options_dialog: AcceptDialog
var _other_options_list: VBoxContainer
var _shift_call_reviews: Array = []
var _current_call_review: Dictionary = {}

# Timers
var _transcript_timer: Timer
var _next_call_timer: Timer
var _arrival_timer: Timer
var _resolution_timer: Timer
var _shift_timer: Timer

# Helpers
var _dispatch_rng := RandomNumberGenerator.new()
var _scenario_generator: RefCounted
var _patrol_manager: Node = null

# Groq API Integration for HTML5 LLM
var _groq_http: HTTPRequest = null
const GROQ_API_KEY: String = "" # Add your key here before playing
var _is_waiting_for_llm: bool = false
var _intake_location_asked: bool = false
var _intake_emergency_asked: bool = false

func _ready() -> void:
	_groq_http = HTTPRequest.new()
	add_child(_groq_http)
	
	var state = get_node_or_null("/root/GameState")
	if state and not state.call("get_first_live_call_done"):
		_is_interactive_tutorial = true
	if state:
		if state.has_method("get_locale"):
			_selected_locale = String(state.call("get_locale"))
		if state.has_method("get_current_day"):
			_current_day = max(1, int(state.call("get_current_day")))
		if state.has_method("get_day_difficulty_scale"):
			_day_difficulty_scale = max(1.0, float(state.call("get_day_difficulty_scale")))
		if state.has_method("get_saved_shift"):
			var saved = state.call("get_saved_shift")
			if not saved.is_empty() and saved.has("total_score"):
				_total_score = int(saved.get("total_score", 0))
				_calls_completed = int(saved.get("calls_completed", 0))
				_shift_call_reviews = saved.get("shift_call_reviews", [])
				_shift_remaining_s = int(saved.get("shift_remaining_s", _shift_remaining_s))

	if _shift_remaining_s <= 0:
		_shift_remaining_s = max(1, shift_duration_s)

	_dispatch_rng.randomize()
	_map_sprite = $Map
	_world_node = $World

	_init_map_dimensions()
	
	if ResourceLoader.exists("res://assets/maps/map_high.png"):
		_map_high_sprite = Sprite2D.new()
		_map_high_sprite.name = "MapHigh"
		var tex_high = load("res://assets/maps/map_high.png")
		_map_high_sprite.texture = tex_high
		_map_high_sprite.centered = false
		_map_high_sprite.modulate.a = 0.0
		_map_sprite.get_parent().add_child(_map_high_sprite)
		_map_sprite.get_parent().move_child(_map_high_sprite, _map_sprite.get_index() + 1)
		_map_high_sprite.scale = _map_sprite.scale
		_map_high_sprite.position = _map_sprite.position

	_fit_map_to_viewport()
	_configure_world_route_source()

	get_viewport().connect("size_changed", Callable(self, "_on_viewport_resized"))
	_add_vehicle_manager()

	_setup_hud()
	_setup_scenario_generator()
	_load_route_points_for_calls()
	_setup_dispatch_ui()
	_apply_kid_friendly_ui()
	_setup_dispatch_timers()
	if _is_interactive_tutorial:
		_create_tutorial_ui()
	_schedule_next_call(dispatch_initial_delay_s)

func _create_tutorial_ui() -> void:
	_tutorial_panel = PanelContainer.new()
	_tutorial_panel.custom_minimum_size = Vector2(300, 64)
	_tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.5, 0.7, 0.95)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.9, 0.8, 0.2, 1.0)
	_tutorial_panel.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 12.0
	hbox.offset_top = 8.0
	hbox.offset_right = -12.0
	hbox.offset_bottom = -8.0
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	_tutorial_panel.add_child(hbox)
	
	var icon = Label.new()
	icon.text = "COACH:"
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))
	hbox.add_child(icon)
	
	_tutorial_label = Label.new()
	_tutorial_label.text = "Waiting for your first emergency call..."
	_tutorial_label.add_theme_font_size_override("font_size", 20)
	_tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_tutorial_label)
	
	var canvas = get_node_or_null("CanvasLayer")
	if canvas:
		canvas.add_child(_tutorial_panel)
		canvas.move_child(_tutorial_panel, -1)
	else:
		add_child(_tutorial_panel)
	_layout_tutorial_panel()

func _layout_tutorial_panel() -> void:
	if _tutorial_panel == null:
		return
	var vp_size = get_viewport().get_visible_rect().size
	var panel_width = clamp(vp_size.x - 24.0, 300.0, 860.0)
	_tutorial_panel.anchor_left = 0.5
	_tutorial_panel.anchor_right = 0.5
	_tutorial_panel.anchor_top = 0.0
	_tutorial_panel.anchor_bottom = 0.0
	_tutorial_panel.offset_left = -panel_width * 0.5
	_tutorial_panel.offset_right = panel_width * 0.5
	_tutorial_panel.offset_top = 10.0
	_tutorial_panel.offset_bottom = 78.0

func _set_intake_state(location_known: bool, complaint_known: bool) -> void:
	_location_revealed = location_known
	_complaint_revealed = complaint_known
	if _incident_summary_label:
		if _complaint_revealed:
			_incident_summary_label.text = "Complaint: %s" % String(_active_call.get("title", "Emergency"))
		else:
			_incident_summary_label.text = "Complaint: Ask the caller first"
	if _incoming_label:
		var location_text = "Unknown"
		if _location_revealed:
			location_text = String(_active_call.get("location", "Unknown"))
		_incoming_label.text = "Location: %s\nSeverity: %s\nWaiting calls: %d" % [
			location_text,
			String(_active_call.get("severity", "medium")).capitalize(),
			_queued_calls.size()
		]

func _ensure_coach_pointer() -> void:
	if _coach_pointer_label != null:
		return
	var canvas = get_node_or_null("CanvasLayer")
	if canvas == null:
		return
	_coach_pointer_label = Label.new()
	_coach_pointer_label.name = "CoachPointer"
	_coach_pointer_label.visible = false
	_coach_pointer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach_pointer_label.add_theme_font_size_override("font_size", 20)
	_coach_pointer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	_coach_pointer_label.add_theme_constant_override("outline_size", 5)
	_coach_pointer_label.add_theme_color_override("font_outline_color", Color(0.15, 0.2, 0.35, 0.95))
	canvas.add_child(_coach_pointer_label)

func _ensure_tutorial_focus_layer() -> void:
	if _tutorial_focus_layer != null:
		return
	var canvas = get_node_or_null("CanvasLayer")
	if canvas == null:
		return
	_tutorial_focus_layer = Control.new()
	_tutorial_focus_layer.name = "TutorialFocusLayer"
	_tutorial_focus_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tutorial_focus_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_focus_layer.visible = false
	canvas.add_child(_tutorial_focus_layer)
	canvas.move_child(_tutorial_focus_layer, -1)

	_tutorial_focus_blocks.clear()
	for _i in range(4):
		var block = ColorRect.new()
		block.color = Color(0.0, 0.0, 0.08, 0.52)
		block.mouse_filter = Control.MOUSE_FILTER_STOP
		block.visible = false
		_tutorial_focus_layer.add_child(block)
		_tutorial_focus_blocks.append(block)

func _update_tutorial_focus_layout() -> void:
	if _tutorial_focus_layer == null or _tutorial_focus_target == null:
		return
	if not _tutorial_focus_target.is_visible_in_tree():
		_hide_coach_pointer()
		return

	var vp = get_viewport().get_visible_rect().size
	var rect = _tutorial_focus_target.get_global_rect().grow(8.0)
	var left = clamp(rect.position.x, 0.0, vp.x)
	var top = clamp(rect.position.y, 0.0, vp.y)
	var right = clamp(rect.position.x + rect.size.x, 0.0, vp.x)
	var bottom = clamp(rect.position.y + rect.size.y, 0.0, vp.y)

	var top_block: ColorRect = _tutorial_focus_blocks[0]
	top_block.position = Vector2(0.0, 0.0)
	top_block.size = Vector2(vp.x, top)
	top_block.visible = true

	var bottom_block: ColorRect = _tutorial_focus_blocks[1]
	bottom_block.position = Vector2(0.0, bottom)
	bottom_block.size = Vector2(vp.x, max(0.0, vp.y - bottom))
	bottom_block.visible = true

	var left_block: ColorRect = _tutorial_focus_blocks[2]
	left_block.position = Vector2(0.0, top)
	left_block.size = Vector2(left, max(0.0, bottom - top))
	left_block.visible = true

	var right_block: ColorRect = _tutorial_focus_blocks[3]
	right_block.position = Vector2(right, top)
	right_block.size = Vector2(max(0.0, vp.x - right), max(0.0, bottom - top))
	right_block.visible = true

func _show_tutorial_focus(target: Control) -> void:
	if not _is_interactive_tutorial:
		return
	if target == null:
		_hide_tutorial_focus()
		return
	_ensure_tutorial_focus_layer()
	if _tutorial_focus_layer == null:
		return
	_tutorial_focus_target = target
	_tutorial_focus_layer.visible = true
	_update_tutorial_focus_layout()
	if _tutorial_focus_tween:
		_tutorial_focus_tween.kill()
		_tutorial_focus_tween = null
	_tutorial_focus_tween = create_tween()
	for block in _tutorial_focus_blocks:
		if block is ColorRect:
			var cr: ColorRect = block
			cr.color = Color(0.0, 0.0, 0.08, 0.0)
			_tutorial_focus_tween.parallel().tween_property(cr, "color:a", 0.52, 0.2)

func _hide_tutorial_focus() -> void:
	_tutorial_focus_target = null
	if _tutorial_focus_tween:
		_tutorial_focus_tween.kill()
		_tutorial_focus_tween = null
	if _tutorial_focus_layer:
		_tutorial_focus_layer.visible = false
	for block in _tutorial_focus_blocks:
		if block is ColorRect:
			(block as ColorRect).visible = false

func _hide_coach_pointer() -> void:
	if _coach_pointer_tween:
		_coach_pointer_tween.kill()
		_coach_pointer_tween = null
	if _coach_pointer_label:
		_coach_pointer_label.visible = false
	_hide_tutorial_focus()

func _point_coach_at(target: Control, prompt: String) -> void:
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

	_coach_pointer_label.text = "%s >>>" % prompt
	var target_rect = target.get_global_rect()
	var base_pos = Vector2(
		target_rect.position.x + max(6.0, target_rect.size.x * 0.12),
		target_rect.position.y - 28.0
	)
	_coach_pointer_label.global_position = base_pos
	_coach_pointer_label.visible = true
	_show_tutorial_focus(target)
	if _coach_pointer_label.get_parent():
		_coach_pointer_label.get_parent().move_child(_coach_pointer_label, -1)
	_coach_pointer_tween = create_tween()
	_coach_pointer_tween.set_loops()
	_coach_pointer_tween.tween_property(_coach_pointer_label, "global_position:y", base_pos.y - 8.0, 0.45)
	_coach_pointer_tween.tween_property(_coach_pointer_label, "global_position:y", base_pos.y, 0.45)

func _start_intake_prompt() -> void:
	_intake_stage = 0
	_clear_choice_buttons()
	if _selected_mode_id != "easy_multiple_choice":
		if _typed_row:
			_typed_row.visible = true
		if _typed_input:
			_typed_input.placeholder_text = "Ask for exact location and callback number..."
			_typed_input.grab_focus()
		if _response_prompt_label:
			_response_prompt_label.text = "Intake step 1/2: Ask for location first (and callback number)."
		return

	if _typed_row:
		_typed_row.visible = false
	if _response_prompt_label:
		_response_prompt_label.text = "Intake step 1/2: Ask for exact location."
	if _choices_box:
		var location_btn = Button.new()
		location_btn.text = "What is your exact location?"
		location_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_choice_button(location_btn, _ui_scale_factor())
		location_btn.pressed.connect(Callable(self, "_on_intake_question_pressed").bind(0))
		_choices_box.add_child(location_btn)
		_animate_choice_button_attention(location_btn)
		if _is_interactive_tutorial:
			if _tutorial_label:
				_tutorial_label.text = "First step: ask where the caller is."
			_point_coach_at(location_btn, "Ask location")

func _on_intake_question_pressed(step: int) -> void:
	if _active_call.is_empty():
		return
	_clear_choice_buttons()
	if step == 0:
		_append_transcript_line("Dispatcher", "What is your exact location?")
		_append_transcript_line("Caller", "We are at %s." % String(_active_call.get("location", "Unknown location")))
		_set_intake_state(true, false)
		_intake_stage = 1
		if _response_prompt_label:
			_response_prompt_label.text = "Intake step 2/2: Ask what happened."
		if _choices_box:
			var complaint_btn = Button.new()
			complaint_btn.text = "Tell me what happened."
			complaint_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_style_choice_button(complaint_btn, _ui_scale_factor())
			complaint_btn.pressed.connect(Callable(self, "_on_intake_question_pressed").bind(1))
			_choices_box.add_child(complaint_btn)
			_animate_choice_button_attention(complaint_btn)
			if _is_interactive_tutorial:
				if _tutorial_label:
					_tutorial_label.text = "Great. Next ask what is happening."
				_point_coach_at(complaint_btn, "Ask complaint")
		return

	_append_transcript_line("Dispatcher", "Tell me what happened.")
	_append_transcript_line("Caller", String(_active_call.get("title", "There is an emergency and we need help.")))
	_set_intake_state(true, true)
	_intake_stage = -1
	if _is_interactive_tutorial and _tutorial_label:
		_tutorial_label.text = "Nice intake. Now make a safe response choice."
	_begin_call_transcript_after_intake()

func _begin_call_transcript_after_intake(skip_first_caller_line: bool = false) -> void:
	_caller_lines.clear()
	var transcript: Array = _active_call.get("transcript", [])
	for raw_line in transcript:
		if typeof(raw_line) != TYPE_DICTIONARY:
			continue
		var line: Dictionary = raw_line
		var speaker = String(line.get("speaker", "Caller")).strip_edges()
		var text = String(line.get("text", "")).strip_edges()
		if text == "":
			continue
		if _is_redundant_911_intake_prompt(speaker, text):
			continue
		_caller_lines.append({"speaker": speaker, "text": text})
	_caller_line_index = 0
	if skip_first_caller_line and _caller_lines.size() > 0:
		if String(_caller_lines[0].get("speaker", "")) == "Caller":
			_caller_line_index = 1
	
	if _caller_lines.is_empty() or _caller_line_index >= _caller_lines.size():
		_show_player_choices()
	else:
		_play_next_caller_line()

func _is_redundant_911_intake_prompt(speaker: String, text: String) -> bool:
	if speaker.to_lower() != "911":
		return false
	var msg = text.to_lower()
	if _text_has_any(msg, [
		"exact location",
		"your location",
		"where are you",
		"state your location",
		"address",
		"located"
	]):
		return true
	if _text_has_any(msg, [
		"what happened",
		"what is your emergency",
		"what's your emergency",
		"nature of your emergency",
		"what are you reporting",
		"describe the emergency",
		"what is the situation",
		"anong emergency"
	]):
		return true
	return false

func _record_response_review(chosen_text: String, label: String, explanation: String, options: Array) -> void:
	if _current_call_review.is_empty():
		return
	var safe_options: Array[String] = []
	var other_options: Array = []
	var all_options: Array = []
	var skipped_selected := false
	for raw_opt in options:
		if typeof(raw_opt) != TYPE_DICTIONARY:
			continue
		var opt: Dictionary = raw_opt
		var opt_text = String(opt.get("text", ""))
		var opt_label = String(opt.get("label", "")).to_lower()
		var opt_explanation = String(opt.get("explanation", opt.get("feedback", ""))).strip_edges()
		var opt_payload = {
			"text": opt_text,
			"label": opt_label,
			"impact": _impact_summary_for_label(opt_label),
			"explanation": opt_explanation
		}
		all_options.append(opt_payload)
		if opt_label == "safe":
			safe_options.append(opt_text)
		if not skipped_selected and opt_text == chosen_text:
			skipped_selected = true
			continue
		other_options.append(opt_payload)
	var correct = String(label).to_lower() == "safe"
	_current_call_review["checks_total"] = int(_current_call_review.get("checks_total", 0)) + 1
	if correct:
		_current_call_review["checks_correct"] = int(_current_call_review.get("checks_correct", 0)) + 1
	var new_resp = {
		"chosen_text": chosen_text,
		"label": label,
		"correct": correct,
		"safe_options": safe_options,
		"all_options": all_options,
		"other_options": other_options,
		"explanation": explanation
	}
	
	if not _current_call_review.has("responses"):
		_current_call_review["responses"] = []
	var arr: Array = _current_call_review["responses"]
	arr.append(new_resp)
	
	# Also set "response" to the last one for backward compatibility with other scripts
	_current_call_review["response"] = new_resp

func _impact_summary_for_label(label: String) -> String:
	match String(label).to_lower():
		"safe":
			return "Likely better outcome: this option generally improves safety and response quality."
		"unsafe":
			return "Likely worse outcome: this option can increase danger or delay effective help."
		_:
			return "Mixed outcome: this option may help partially but is not the strongest choice."

func _record_vehicle_review(selected_vehicle: String, recommended_str: String, correct: bool, explanation: String) -> void:
	if _current_call_review.is_empty():
		return
	_current_call_review["checks_total"] = int(_current_call_review.get("checks_total", 0)) + 1
	if correct:
		_current_call_review["checks_correct"] = int(_current_call_review.get("checks_correct", 0)) + 1
		
	var new_disp = {
		"selected": _vehicle_name(selected_vehicle),
		"recommended": recommended_str,
		"correct": correct,
		"explanation": explanation
	}
	
	if not _current_call_review.has("dispatches"):
		_current_call_review["dispatches"] = []
	var arr: Array = _current_call_review["dispatches"]
	arr.append(new_disp)
	
	# Keep single key for backward compatibility
	_current_call_review["dispatch"] = new_disp

func _build_shift_review_detail(review: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Location: %s" % String(review.get("location", "Unknown")))
	var protocol_hits: Array = review.get("protocol_hits", [])
	if not protocol_hits.is_empty():
		lines.append("Professional protocol checkpoints:")
		for hit in protocol_hits:
			lines.append("- %s" % String(hit))
		lines.append("")
	var responses: Array = review.get("responses", [])
	if responses.size() == 0 and not review.get("response", {}).is_empty():
		responses = [review.get("response", {})]
		
	if not responses.is_empty():
		var idx = 1
		for response in responses:
			var safe_opts_arr: Array = response.get("safe_options", [])
			var safe_opts = ""
			if not safe_opts_arr.is_empty():
				var safe_bits: Array[String] = []
				for entry in safe_opts_arr:
					safe_bits.append(String(entry))
				safe_opts = " | ".join(PackedStringArray(safe_bits))
			lines.append("Response #%d chosen: %s" % [idx, String(response.get("chosen_text", ""))])
			lines.append("Response #%d result: %s" % [idx, "Correct" if bool(response.get("correct", false)) else "Needs improvement"])
			if safe_opts != "" and idx == 1:
				lines.append("Best safe option(s): %s" % safe_opts)
			var response_explanation = String(response.get("explanation", "")).strip_edges()
			if response_explanation != "":
				lines.append("Why: %s" % response_explanation)
			lines.append("")
			idx += 1
	var dispatches: Array = review.get("dispatches", [])
	if dispatches.is_empty():
		var d = review.get("dispatch", {})
		if not d.is_empty():
			dispatches = [d]
			
	for dispatch in dispatches:
		lines.append("Dispatch sent: %s" % String(dispatch.get("selected", "")))
		lines.append("Recommended unit(s): %s" % String(dispatch.get("recommended", "")))
		lines.append("Dispatch result: %s" % ("Correct" if bool(dispatch.get("correct", false)) else "Not ideal"))
		var dispatch_explanation = String(dispatch.get("explanation", "")).strip_edges()
		if dispatch_explanation != "":
			lines.append("Why: %s" % dispatch_explanation)
		lines.append("")
	return "\n".join(lines)

func _detail_target_height(detail: RichTextLabel) -> float:
	if detail == null:
		return 80.0
	var h = float(detail.get_content_height()) + 10.0
	if h <= 12.0:
		h = 56.0 + float(detail.text.length()) * 0.2
	return clamp(h, 56.0, 420.0)

func _animate_accordion_clip(clip: Control, detail: RichTextLabel, target_height: float, open: bool) -> void:
	if clip == null or detail == null:
		return
	if clip.has_meta("accordion_tween"):
		var running = clip.get_meta("accordion_tween")
		if running is Tween:
			(running as Tween).kill()

	var tw = create_tween()
	clip.set_meta("accordion_tween", tw)
	var current_size = clip.custom_minimum_size
	var goal_h = target_height if open else 0.0
	tw.tween_property(clip, "custom_minimum_size", Vector2(current_size.x, goal_h), 0.2)
	tw.parallel().tween_property(detail, "modulate:a", 1.0 if open else 0.0, 0.16)

func _toggle_accordion_animated(clips: Array, details: Array, toggles: Array, heights: Array, target_index: int, show_text: String, hide_text: String) -> void:
	if target_index < 0 or target_index >= clips.size():
		return
	if target_index >= details.size() or target_index >= heights.size():
		return

	var should_open = true
	if clips[target_index] is Control:
		should_open = (clips[target_index] as Control).custom_minimum_size.y <= 1.0

	for i in range(clips.size()):
		if not (clips[i] is Control) or i >= details.size() or i >= heights.size() or not (details[i] is RichTextLabel):
			continue
		var open = should_open and i == target_index
		_animate_accordion_clip(clips[i], details[i], float(heights[i]), open)
		if i < toggles.size() and toggles[i] is Button:
			(toggles[i] as Button).text = hide_text if open else show_text

func _populate_shift_review_list() -> void:
	if _shift_review_list == null:
		return
	for child in _shift_review_list.get_children():
		child.queue_free()

	# Inject the dialog text directly into the scrollable list as a wrapped Label to prevent boundary overlaps
	if _shift_review_dialog != null and _shift_review_dialog.dialog_text != "":
		var popup_msg = _shift_review_dialog.dialog_text
		_shift_review_dialog.dialog_text = ""
		var sum_lbl = Label.new()
		sum_lbl.text = popup_msg
		sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sum_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sum_lbl.add_theme_font_size_override("font_size", 16)
		sum_lbl.add_theme_color_override("font_color", Color8(34, 46, 62))
		_shift_review_list.add_child(sum_lbl)
		
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 12)
		_shift_review_list.add_child(spacer)

	if _shift_call_reviews.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No completed calls were recorded this shift."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_font_size_override("font_size", 17)
		empty_label.add_theme_color_override("font_color", Color8(34, 46, 62))
		_shift_review_list.add_child(empty_label)
		return

	var detail_clips: Array = []
	var detail_nodes: Array = []
	var detail_heights: Array = []
	var toggle_nodes: Array = []

	for review in _shift_call_reviews:
		if typeof(review) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = review
		var card = PanelContainer.new()
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color8(255, 238, 208)
		card_style.corner_radius_top_left = 10
		card_style.corner_radius_top_right = 10
		card_style.corner_radius_bottom_left = 10
		card_style.corner_radius_bottom_right = 10
		card_style.border_width_left = 2
		card_style.border_width_top = 2
		card_style.border_width_right = 2
		card_style.border_width_bottom = 2
		card_style.border_color = Color8(255, 160, 86)
		card.add_theme_stylebox_override("panel", card_style)
		_shift_review_list.add_child(card)

		var card_margin = MarginContainer.new()
		card_margin.add_theme_constant_override("margin_left", 12)
		card_margin.add_theme_constant_override("margin_top", 10)
		card_margin.add_theme_constant_override("margin_right", 12)
		card_margin.add_theme_constant_override("margin_bottom", 10)
		card.add_child(card_margin)

		var box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		card_margin.add_child(box)

		var row = HBoxContainer.new()
		box.add_child(row)

		var complaint = Label.new()
		complaint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		complaint.text = "Call %d: %s" % [int(item.get("call_number", 0)), String(item.get("title", "Emergency"))]
		complaint.add_theme_font_size_override("font_size", 17)
		complaint.add_theme_color_override("font_color", Color8(26, 36, 52))
		row.add_child(complaint)

		var checks_total = int(item.get("checks_total", 0))
		var checks_correct = int(item.get("checks_correct", 0))
		var score = int(item.get("score", 0))
		var summary = Label.new()
		summary.text = "Score %d | %d/%d" % [score, checks_correct, checks_total]
		summary.add_theme_font_size_override("font_size", 16)
		summary.add_theme_color_override("font_color", Color8(52, 82, 109))
		row.add_child(summary)

		var toggle = Button.new()
		toggle.text = "Show details"
		toggle.custom_minimum_size = Vector2(128, 32)
		_style_choice_button(toggle, 0.88)
		row.add_child(toggle)

		var detail_clip = VBoxContainer.new()
		detail_clip.clip_contents = true
		detail_clip.custom_minimum_size = Vector2(0, 0)
		detail_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(detail_clip)

		var detail = RichTextLabel.new()
		detail.bbcode_enabled = false
		detail.fit_content = true
		detail.scroll_active = false
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.text = _build_shift_review_detail(item)
		detail.add_theme_font_size_override("normal_font_size", 15)
		detail.add_theme_color_override("default_color", Color8(34, 46, 62))
		detail.modulate.a = 0.0
		detail_clip.add_child(detail)

		var card_index = detail_nodes.size()
		detail_clips.append(detail_clip)
		detail_nodes.append(detail)
		detail_heights.append(_detail_target_height(detail))
		toggle_nodes.append(toggle)

		toggle.pressed.connect(func():
			_toggle_accordion_animated(detail_clips, detail_nodes, toggle_nodes, detail_heights, card_index, "Show details", "Hide details")
		)

func _show_shift_review(title: String, summary: String, post_action: String = "") -> void:
	if _shift_review_dialog == null:
		_show_kid_message(title, summary)
		return
	_post_shift_action = post_action
	_shift_review_dialog.title = title
	_shift_review_dialog.dialog_text = summary
	_populate_shift_review_list()
	
	var state = get_node_or_null("/root/GameState")
	if state and state.has_method("clear_shift_progress"):
		state.call("clear_shift_progress")
		
	_shift_review_dialog.popup_centered(Vector2i(820, 560))

func _collect_unselected_options(item: Dictionary) -> Array:
	var responses: Array = item.get("responses", [])
	if responses.size() == 0 and not item.get("response", {}).is_empty():
		responses = [item.get("response", {})]
		
	var others: Array = []
	if responses.size() > 0:
		var response = responses[0] # Use the options from the first response mapping
		var chosen_text = String(response.get("chosen_text", "")).strip_edges()
		others = response.get("other_options", []).duplicate(true)
		if others.is_empty():
			var all_opts: Array = response.get("all_options", [])
			for raw_all in all_opts:
				if typeof(raw_all) != TYPE_DICTIONARY:
					continue
				var all_opt: Dictionary = raw_all
				if String(all_opt.get("text", "")).strip_edges() == chosen_text:
					continue
				others.append(all_opt)
	return others

func _build_other_options_card_detail(item: Dictionary, others: Array) -> String:
	var lines: Array[String] = []
	var response: Dictionary = item.get("response", {})
	var chosen_text = String(response.get("chosen_text", "")).strip_edges()
	if chosen_text != "":
		lines.append("You chose: %s" % chosen_text)
		lines.append("")
	var option_number = 1
	for raw_opt in others:
		if typeof(raw_opt) != TYPE_DICTIONARY:
			continue
		var opt: Dictionary = raw_opt
		lines.append("Alternative %d: %s" % [option_number, String(opt.get("text", ""))])
		var expl = String(opt.get("explanation", "")).strip_edges()
		if expl != "":
			lines.append("If chosen: %s" % expl)
		lines.append("")
		option_number += 1
	return "\n".join(PackedStringArray(lines))

func _populate_other_options_tiles() -> void:
	if _other_options_list == null:
		return
	for child in _other_options_list.get_children():
		child.queue_free()

	if _shift_call_reviews.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No call reviews are available yet."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_font_size_override("font_size", 17)
		empty_label.add_theme_color_override("font_color", Color8(34, 46, 62))
		_other_options_list.add_child(empty_label)
		return

	var added_count = 0
	var detail_clips: Array = []
	var detail_nodes: Array = []
	var detail_heights: Array = []
	var toggle_nodes: Array = []
	for review in _shift_call_reviews:
		if typeof(review) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = review
		var others = _collect_unselected_options(item)
		if others.is_empty():
			continue
		added_count += 1

		var card = PanelContainer.new()
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color8(255, 238, 208)
		card_style.corner_radius_top_left = 10
		card_style.corner_radius_top_right = 10
		card_style.corner_radius_bottom_left = 10
		card_style.corner_radius_bottom_right = 10
		card_style.border_width_left = 2
		card_style.border_width_top = 2
		card_style.border_width_right = 2
		card_style.border_width_bottom = 2
		card_style.border_color = Color8(255, 160, 86)
		card.add_theme_stylebox_override("panel", card_style)
		_other_options_list.add_child(card)

		var card_margin = MarginContainer.new()
		card_margin.add_theme_constant_override("margin_left", 12)
		card_margin.add_theme_constant_override("margin_top", 10)
		card_margin.add_theme_constant_override("margin_right", 12)
		card_margin.add_theme_constant_override("margin_bottom", 10)
		card.add_child(card_margin)

		var box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		card_margin.add_child(box)

		var row = HBoxContainer.new()
		box.add_child(row)

		var title = Label.new()
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text = "Call %d: %s" % [int(item.get("call_number", 0)), String(item.get("title", "Emergency"))]
		title.add_theme_font_size_override("font_size", 17)
		title.add_theme_color_override("font_color", Color8(26, 36, 52))
		row.add_child(title)

		var toggle = Button.new()
		toggle.text = "Show alternatives"
		toggle.custom_minimum_size = Vector2(190, 34)
		_style_choice_button(toggle, 0.86)
		row.add_child(toggle)

		var detail_clip = VBoxContainer.new()
		detail_clip.clip_contents = true
		detail_clip.custom_minimum_size = Vector2(0, 0)
		detail_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(detail_clip)

		var detail = RichTextLabel.new()
		detail.bbcode_enabled = false
		detail.fit_content = true
		detail.scroll_active = false
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.text = _build_other_options_card_detail(item, others)
		detail.add_theme_font_size_override("normal_font_size", 15)
		detail.add_theme_color_override("default_color", Color8(34, 46, 62))
		detail.modulate.a = 0.0
		detail_clip.add_child(detail)

		var card_index = detail_nodes.size()
		detail_clips.append(detail_clip)
		detail_nodes.append(detail)
		detail_heights.append(_detail_target_height(detail))
		toggle_nodes.append(toggle)

		toggle.pressed.connect(func():
			_toggle_accordion_animated(detail_clips, detail_nodes, toggle_nodes, detail_heights, card_index, "Show alternatives", "Hide alternatives")
		)

	if added_count == 0:
		var none_label = Label.new()
		none_label.text = "No alternative answers were captured for this shift yet."
		none_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none_label.add_theme_font_size_override("font_size", 17)
		none_label.add_theme_color_override("font_color", Color8(34, 46, 62))
		_other_options_list.add_child(none_label)

func _on_shift_review_custom_action(action: String) -> void:
	if action != "review_other_options":
		return
	if _other_options_dialog == null or _other_options_list == null:
		return
	_other_options_dialog.dialog_text = ""
	_populate_other_options_tiles()
	_other_options_dialog.popup_centered(Vector2i(860, 620))

func _on_shift_review_dialog_confirmed() -> void:
	var action = _post_shift_action
	_post_shift_action = ""
	var tree = get_tree()
	if tree == null:
		return
	if action == "restart_day":
		_pending_day_restart = false
		tree.reload_current_scene()
	elif action == "return_menu":
		tree.change_scene_to_file(main_menu_scene_path)
	elif action == "reload_scene":
		tree.reload_current_scene()

func _open_shift_review_for_manual_end(post_action: String, title: String, summary: String) -> void:
	var state = get_node_or_null("/root/GameState")
	if state and state.has_method("record_shift_result"):
		state.call("record_shift_result", _total_score, _calls_completed)
	_show_shift_review(title, summary, post_action)

func _init_map_dimensions() -> void:
	var img_w = 0
	var img_h = 0

	if ResourceLoader.exists(map_texture_path):
		var tex: Texture2D = load(map_texture_path)
		if tex:
			_map_sprite.texture = tex
			_map_sprite.centered = false
			var sz = tex.get_size()
			img_w = int(sz.x)
			img_h = int(sz.y)

	if img_w == 0 or img_h == 0:
		img_w = int(_world_node.image_width)
		img_h = int(_world_node.image_height)

	_img_w = img_w
	_img_h = img_h

# Two-finger zoom state
var _touch_points: Dictionary = {}

func _fit_map_to_viewport() -> void:
	if _img_w <= 0 or _img_h <= 0:
		return
	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return

	var fit_scale = max(vp_size.x / float(_img_w), vp_size.y / float(_img_h))
	_current_scale = fit_scale
	_min_scale = fit_scale
	_max_scale = fit_scale * 4.0

	var scaled_w = _img_w * fit_scale
	var scaled_h = _img_h * fit_scale
	var offset = Vector2((vp_size.x - scaled_w) * 0.5, (vp_size.y - scaled_h) * 0.5)

	_map_sprite.scale = Vector2(fit_scale, fit_scale)
	_world_node.scale = Vector2(fit_scale, fit_scale)
	_map_sprite.position = offset
	_world_node.position = offset
	
	if _map_high_sprite:
		_map_high_sprite.scale = Vector2(fit_scale, fit_scale)
		_map_high_sprite.position = offset
		_update_map_lod(fit_scale)

func _configure_world_route_source() -> void:
	_world_node.route_file_path = route_json_res_path
	_world_node.image_width = _img_w
	_world_node.image_height = _img_h

func _add_vehicle_manager() -> void:
	if not ResourceLoader.exists("res://scripts/vehicles/multi_patrol_manager.gd"):
		return
	var mgr_script = load("res://scripts/vehicles/multi_patrol_manager.gd")
	if mgr_script == null:
		return
	var mgr = mgr_script.new()
	mgr.route_file_path = route_json_res_path
	mgr.bounds_file_path = "res://assets/maps/map.bounds.json"
	mgr.station_file_path = station_json_res_path
	mgr.image_width = _img_w
	mgr.image_height = _img_h
	_world_node.add_child(mgr)
	_patrol_manager = mgr
	if _patrol_manager.has_signal("response_arrived"):
		_patrol_manager.connect("response_arrived", Callable(self, "_on_response_arrived"))
	if _patrol_manager.has_signal("response_position_updated"):
		_patrol_manager.connect("response_position_updated", Callable(self, "_on_response_position_updated"))
	_setup_service_station_markers()

func _on_viewport_resized() -> void:
	if _user_zoomed:
		return
	_fit_map_to_viewport()
	_apply_kid_friendly_ui()
	_layout_tutorial_panel()
	_update_tutorial_focus_layout()

func _station_label_short(vtype: String) -> String:
	match vtype:
		"fire_truck":
			return "FIRE"
		"ambulance":
			return "HOSP"
		_:
			return "POLICE"

func _add_rect_poly(parent: Node2D, center: Vector2, size: Vector2, color: Color, z_index: int = 0) -> void:
	var half = size * 0.5
	var poly = Polygon2D.new()
	poly.z_index = z_index
	poly.color = color
	poly.polygon = PackedVector2Array([
		Vector2(center.x - half.x, center.y - half.y),
		Vector2(center.x + half.x, center.y - half.y),
		Vector2(center.x + half.x, center.y + half.y),
		Vector2(center.x - half.x, center.y + half.y)
	])
	parent.add_child(poly)

func _build_station_building_badge(parent: Node2D, vtype: String) -> void:
	# Type-specific mini building, inspired by kid-friendly city-map icons.
	match vtype:
		"fire_truck":
			_add_rect_poly(parent, Vector2(0, -31), Vector2(24, 7), Color8(78, 121, 196), 2)
			_add_rect_poly(parent, Vector2(0, -24), Vector2(30, 18), Color8(226, 68, 68), 2)
			_add_rect_poly(parent, Vector2(0, -19), Vector2(10, 8), Color8(44, 54, 72), 3)
			_add_rect_poly(parent, Vector2(-9, -26), Vector2(5, 4), Color8(255, 241, 182), 3)
			_add_rect_poly(parent, Vector2(0, -26), Vector2(5, 4), Color8(255, 241, 182), 3)
			_add_rect_poly(parent, Vector2(9, -26), Vector2(5, 4), Color8(255, 241, 182), 3)
		"ambulance":
			_add_rect_poly(parent, Vector2(0, -31), Vector2(30, 6), Color8(146, 205, 255), 2)
			_add_rect_poly(parent, Vector2(0, -24), Vector2(30, 18), Color8(187, 231, 255), 2)
			_add_rect_poly(parent, Vector2(0, -24), Vector2(9, 3), Color8(229, 71, 71), 3)
			_add_rect_poly(parent, Vector2(0, -24), Vector2(3, 9), Color8(229, 71, 71), 3)
			_add_rect_poly(parent, Vector2(-9, -18), Vector2(6, 4), Color8(96, 154, 196), 3)
			_add_rect_poly(parent, Vector2(9, -18), Vector2(6, 4), Color8(96, 154, 196), 3)
		_:
			_add_rect_poly(parent, Vector2(0, -31), Vector2(26, 6), Color8(58, 92, 163), 2)
			_add_rect_poly(parent, Vector2(0, -24), Vector2(30, 18), Color8(89, 136, 222), 2)
			_add_rect_poly(parent, Vector2(0, -18), Vector2(9, 8), Color8(35, 51, 77), 3)
			_add_rect_poly(parent, Vector2(0, -27), Vector2(7, 3), Color8(255, 214, 96), 3)
			_add_rect_poly(parent, Vector2(-9, -26), Vector2(5, 4), Color8(202, 224, 255), 3)
			_add_rect_poly(parent, Vector2(9, -26), Vector2(5, 4), Color8(202, 224, 255), 3)

func _setup_service_station_markers() -> void:
	if _world_node == null:
		return
	if _station_layer and is_instance_valid(_station_layer):
		_station_layer.queue_free()
	_station_markers.clear()

	_station_layer = Node2D.new()
	_station_layer.name = "ServiceStations"
	_world_node.add_child(_station_layer)

	var station_data: Array = []
	if _patrol_manager and _patrol_manager.has_method("get_service_station_markers"):
		station_data = _patrol_manager.call("get_service_station_markers")

	for st_any in station_data:
		if typeof(st_any) != TYPE_DICTIONARY:
			continue
		var st: Dictionary = st_any
		var pos_any = st.get("position", Vector2.ZERO)
		if not (pos_any is Vector2):
			continue
		var pos: Vector2 = pos_any
		var station_node = Node2D.new()
		station_node.position = pos
		station_node.z_index = 2
		_station_layer.add_child(station_node)

		_build_station_building_badge(station_node, String(st.get("type", "police")))

		var tag = Label.new()
		tag.text = String(st.get("name", "Station"))
		tag.position = Vector2(-78, -8)
		tag.size = Vector2(156, 14)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 8)
		tag.add_theme_color_override("font_color", Color8(34, 48, 66))
		tag.add_theme_constant_override("outline_size", 2)
		tag.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
		station_node.add_child(tag)

		_station_markers.append(station_node)

func _ui_scale_factor() -> float:
	var width = get_viewport().get_visible_rect().size.x
	if width <= 480.0:
		return 1.45
	if width <= 768.0:
		return 1.3
	if width <= 1024.0:
		return 1.15
	return 1.0

func _style_dispatch_button(btn: Button, base: Color, hover: Color, scale: float) -> void:
	if btn == null:
		return
	btn.custom_minimum_size = Vector2(0, round(42.0 * scale))
	btn.add_theme_font_size_override("font_size", int(round(15.0 * scale)))

	var normal = StyleBoxFlat.new()
	normal.bg_color = base
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(1.0, 1.0, 1.0, 0.75)

	var hov = normal.duplicate()
	hov.bg_color = hover

	var dis = normal.duplicate()
	dis.bg_color = Color(0.78, 0.78, 0.8, 0.75)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_stylebox_override("disabled", dis)
	btn.add_theme_color_override("font_color", Color8(44, 54, 72))

func _style_choice_button(btn: Button, scale: float = 1.0) -> void:
	if btn == null:
		return
	btn.custom_minimum_size = Vector2(0, round(48.0 * scale))
	btn.add_theme_font_size_override("font_size", int(round(18.0 * scale)))
	btn.add_theme_color_override("font_color", Color8(32, 42, 58))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

	var normal = StyleBoxFlat.new()
	normal.bg_color = Color8(255, 225, 158)
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color8(247, 159, 49)

	var hover = normal.duplicate()
	hover.bg_color = Color8(255, 236, 182)

	var pressed = normal.duplicate()
	pressed.bg_color = Color8(252, 211, 122)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)

func _set_choice_button_pulse(value: float, btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var pulse = clamp(value, 0.0, 1.0)
	for name in ["normal", "hover", "pressed"]:
		var sb = btn.get_theme_stylebox(name)
		if sb is StyleBoxFlat:
			var flat: StyleBoxFlat = sb
			flat.shadow_size = int(round(2.0 + pulse * 7.0))
			flat.shadow_offset = Vector2.ZERO
			flat.shadow_color = Color(1.0, 0.78, 0.34, 0.22 + pulse * 0.42)

func _animate_choice_button_attention(btn: Button, index: int = 0) -> void:
	if btn == null:
		return
	var delay = min(float(index) * 0.04, 0.2)
	btn.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_set_choice_button_pulse(0.0, btn)
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(delay)
	tween.tween_property(btn, "modulate:a", 1.0, 0.25)
	for _i in range(3):
		tween.tween_method(_set_choice_button_pulse.bind(btn), 0.0, 1.0, 0.22)
		tween.tween_method(_set_choice_button_pulse.bind(btn), 1.0, 0.0, 0.22)
	tween.tween_interval(5.0)
	tween.tween_callback(_restart_choice_button_pulse.bind(btn, index))

func _restart_choice_button_pulse(btn: Button, index: int) -> void:
	if btn == null or not is_instance_valid(btn) or not btn.is_visible_in_tree():
		return
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	for _i in range(3):
		tween.tween_method(_set_choice_button_pulse.bind(btn), 0.0, 1.0, 0.22)
		tween.tween_method(_set_choice_button_pulse.bind(btn), 1.0, 0.0, 0.22)
	tween.tween_interval(5.0)
	tween.tween_callback(_restart_choice_button_pulse.bind(btn, index))

func _show_kid_message(title: String, message: String) -> void:
	if _kid_message_dialog == null:
		return
	_kid_message_dialog.title = title
	_kid_message_dialog.dialog_text = ""
	
	var scroll = _kid_message_dialog.get_node_or_null("CustomScroll")
	var lbl = null
	if scroll == null:
		scroll = ScrollContainer.new()
		scroll.name = "CustomScroll"
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, 180)
		var m = MarginContainer.new()
		m.add_theme_constant_override("margin_left", 16)
		m.add_theme_constant_override("margin_right", 16)
		m.add_theme_constant_override("margin_top", 16)
		m.add_theme_constant_override("margin_bottom", 16)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(m)
		lbl = Label.new()
		lbl.name = "CustomLabel"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color8(22, 62, 105))
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.add_child(lbl)
		_kid_message_dialog.add_child(scroll)
	else:
		lbl = scroll.get_child(0).get_node("CustomLabel")
		
	lbl.text = message
	var vp_size = get_viewport().get_visible_rect().size
	var popup_w = int(clamp(vp_size.x * 0.86, 420.0, 760.0))
	var popup_h = int(clamp(vp_size.y * 0.42, 220.0, 360.0))
	_kid_message_dialog.popup_centered(Vector2i(popup_w, popup_h))

func _format_shift_time(total_seconds: int) -> String:
	var clamped_seconds = max(0, total_seconds)
	var minutes = clamped_seconds / 60
	var seconds = clamped_seconds % 60
	return "%02d:%02d" % [minutes, seconds]

func _max_calls_per_shift() -> int:
	return 10

func _remaining_shift_call_slots() -> int:
	var in_flight_calls = _queued_calls.size()
	if not _active_call.is_empty() or _call_active:
		in_flight_calls += 1
	elif not _pending_call.is_empty():
		in_flight_calls += 1
	var used_calls = _calls_completed + in_flight_calls
	return max(0, _max_calls_per_shift() - used_calls)

func _is_shift_window_open() -> bool:
	return _shift_remaining_s <= 0 or _calls_completed >= _max_calls_per_shift()

func _can_end_shift() -> bool:
	return _is_shift_window_open() and _total_score >= shift_min_score

func _shift_end_block_reason() -> String:
	var reasons: Array[String] = []
	if not _is_shift_window_open():
		reasons.append("Shift unlock: wait %s or complete %d/%d calls" % [_format_shift_time(_shift_remaining_s), _calls_completed, _max_calls_per_shift()])
	if _total_score < shift_min_score:
		reasons.append("Score: %d/%d (need %d more points)" % [_total_score, shift_min_score, shift_min_score - _total_score])
	if _calls_completed >= _max_calls_per_shift() and _total_score < shift_min_score:
		reasons.append("Daily call limit reached. Day restart required.")
	return "\n".join(reasons)

func _update_shift_ui() -> void:
	var calls_text = "Calls: %d/%d" % [_calls_completed, _max_calls_per_shift()]
	if _shift_label:
		if _can_end_shift():
			_shift_label.text = "Shift: READY | %s" % calls_text
			_shift_label.add_theme_color_override("font_color", Color8(45, 121, 84))
		elif _total_score >= shift_min_score:
			_shift_label.text = "Shift: Score Ready | %s" % calls_text
			_shift_label.add_theme_color_override("font_color", Color8(44, 54, 72))
		else:
			_shift_label.text = "Shift: Need %d pts | %s" % [shift_min_score - _total_score, calls_text]
			_shift_label.add_theme_color_override("font_color", Color8(167, 74, 42))

	if _next_day_button:
		_next_day_button.visible = _can_end_shift()
		_next_day_button.text = "Proceed to Day %d" % (_current_day + 1)

	if _home_button:
		_home_button.tooltip_text = "Pause"

func _apply_kid_friendly_ui() -> void:
	var scale = _ui_scale_factor()
	var is_mobile = scale > 1.0
	var hud_panel: PanelContainer = get_node_or_null("CanvasLayer/HUDPanel")
	if hud_panel:
		hud_panel.offset_bottom = max(hud_panel.offset_bottom, 232.0)

	if _mode_label:
		_mode_label.add_theme_font_size_override("font_size", int(round(22.0 * scale)))
		_mode_label.add_theme_color_override("font_color", Color8(22, 62, 105))
		_mode_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_mode_label.clip_text = true
	if _hint_label:
		_hint_label.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
		_hint_label.add_theme_color_override("font_color", Color8(30, 84, 55))
		_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint_label.custom_minimum_size = Vector2(0, round(72.0 * scale))
		_hint_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _score_label:
		_score_label.add_theme_font_size_override("font_size", int(round(24.0 * scale)))
	if _shift_label:
		_shift_label.add_theme_font_size_override("font_size", int(round(18.0 * scale)))

	if _dispatch_panel:
		if is_mobile:
			_dispatch_panel.anchor_left = 0.02
			_dispatch_panel.anchor_right = 0.98
			_dispatch_panel.anchor_top = 0.02
			_dispatch_panel.anchor_bottom = 0.98
		else:
			_dispatch_panel.anchor_left = 0.08
			_dispatch_panel.anchor_right = 0.92
			_dispatch_panel.anchor_top = 0.03
			_dispatch_panel.anchor_bottom = 0.97

		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color8(234, 247, 255)
		panel_style.corner_radius_top_left = 18
		panel_style.corner_radius_top_right = 18
		panel_style.corner_radius_bottom_left = 18
		panel_style.corner_radius_bottom_right = 18
		panel_style.border_width_left = 3
		panel_style.border_width_top = 3
		panel_style.border_width_right = 3
		panel_style.border_width_bottom = 3
		panel_style.border_color = Color8(89, 181, 255)
		_dispatch_panel.add_theme_stylebox_override("panel", panel_style)

	if _panel_header_label:
		_panel_header_label.add_theme_font_size_override("font_size", int(round(24.0 * scale)))
		_panel_header_label.add_theme_color_override("font_color", Color8(22, 62, 105))
	if _incident_summary_label:
		_incident_summary_label.add_theme_font_size_override("font_size", int(round(18.0 * scale)))
		_incident_summary_label.add_theme_color_override("font_color", Color8(44, 54, 72))
	if _incoming_label:
		_incoming_label.add_theme_font_size_override("font_size", int(round(13.0 * scale)))
		_incoming_label.add_theme_color_override("font_color", Color8(72, 82, 98))
	if _transcript_label:
		_transcript_label.add_theme_font_size_override("normal_font_size", int(round(16.0 * scale)))
		_transcript_label.add_theme_color_override("default_color", Color8(44, 54, 72))
	if _response_prompt_label:
		_response_prompt_label.add_theme_font_size_override("font_size", int(round(16.0 * scale)))
		_response_prompt_label.add_theme_color_override("font_color", Color8(22, 109, 168))
	if _timeline_label:
		_timeline_label.add_theme_font_size_override("font_size", int(round(15.0 * scale)))
		_timeline_label.add_theme_color_override("font_color", Color8(216, 124, 29))
	if _response_feedback_label:
		_response_feedback_label.add_theme_font_size_override("font_size", int(round(14.0 * scale)))
		_response_feedback_label.add_theme_color_override("font_color", Color8(45, 121, 84))
	if _assignment_label:
		_assignment_label.add_theme_font_size_override("font_size", int(round(14.0 * scale)))
		_assignment_label.add_theme_color_override("font_color", Color8(44, 54, 72))

	_style_dispatch_button(_answer_button, Color8(104, 214, 130), Color8(126, 228, 149), scale)
	_style_dispatch_button(_typed_submit_button, Color8(104, 193, 255), Color8(129, 205, 255), scale)
	_style_dispatch_button(_end_call_button, Color8(255, 180, 75), Color8(255, 195, 104), scale)
	_style_dispatch_button(_hint_button, Color8(171, 221, 255), Color8(191, 231, 255), scale)

	if _close_button:
		_style_dispatch_button(_close_button, Color8(255, 140, 112), Color8(255, 161, 135), scale)
		_close_button.custom_minimum_size = Vector2(round(58.0 * scale), round(52.0 * scale))
		_close_button.add_theme_font_size_override("font_size", int(round(24.0 * scale)))

	if _typed_input:
		_typed_input.custom_minimum_size = Vector2(0, round(42.0 * scale))
		_typed_input.add_theme_font_size_override("font_size", int(round(15.0 * scale)))
		_typed_input.add_theme_color_override("font_color", Color8(18, 30, 46))
		_typed_input.add_theme_color_override("font_placeholder_color", Color8(84, 106, 132))
		var kid_input_style = StyleBoxFlat.new()
		kid_input_style.bg_color = Color8(252, 254, 255)
		kid_input_style.corner_radius_top_left = 10
		kid_input_style.corner_radius_top_right = 10
		kid_input_style.corner_radius_bottom_left = 10
		kid_input_style.corner_radius_bottom_right = 10
		kid_input_style.border_width_left = 2
		kid_input_style.border_width_top = 2
		kid_input_style.border_width_right = 2
		kid_input_style.border_width_bottom = 2
		kid_input_style.border_color = Color8(101, 168, 227)
		_typed_input.add_theme_stylebox_override("normal", kid_input_style)
		var kid_input_focus = kid_input_style.duplicate()
		kid_input_focus.border_color = Color8(53, 130, 202)
		_typed_input.add_theme_stylebox_override("focus", kid_input_focus)

	if _minimized_call_button:
		_minimized_call_button.custom_minimum_size = Vector2(0, round(42.0 * scale))
		_minimized_call_button.add_theme_font_size_override("font_size", int(round(14.0 * scale)))
	if _next_day_button:
		_next_day_button.custom_minimum_size = Vector2(0, round(44.0 * scale))
		_next_day_button.add_theme_font_size_override("font_size", int(round(15.0 * scale)))

	for key in _vehicle_buttons.keys():
		var btn: Button = _vehicle_buttons[key]
		if btn:
			btn.expand_icon = true
			btn.custom_minimum_size = Vector2(0, round(94.0 * scale))
			btn.add_theme_font_size_override("font_size", int(round(17.0 * scale)))
			if key == "fire_truck":
				_style_dispatch_button(btn, Color8(255, 153, 143), Color8(255, 173, 165), scale)
			elif key == "ambulance":
				_style_dispatch_button(btn, Color8(141, 228, 159), Color8(163, 236, 178), scale)
			elif key == "police":
				_style_dispatch_button(btn, Color8(133, 184, 255), Color8(154, 198, 255), scale)
			else:
				_style_dispatch_button(btn, Color8(255, 214, 128), Color8(255, 223, 153), scale)

func _input(event) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.ctrl_pressed and key_event.shift_pressed and key_event.keycode == KEY_F8:
			_activate_test_shift_cheat()
			return

	# ── Freeze map input while a call is active ──
	if _call_active:
		return

	var hovered = get_viewport().gui_get_hovered_control()
	if hovered != null:
		if event is InputEventMouseButton:
			var mouse_release := event as InputEventMouseButton
			if mouse_release.button_index == MOUSE_BUTTON_LEFT and not mouse_release.pressed:
				_dragging = false
		elif event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if not touch.pressed:
				_touch_points.erase(touch.index)
				if _touch_points.is_empty():
					_dragging = false
		return

	# Mouse Input
	if event is InputEventMouseButton:
		var mouse_btn := event as InputEventMouseButton
		if mouse_btn.pressed:
			if mouse_btn.button_index == MOUSE_BUTTON_LEFT:
				_dragging = true
				_drag_last = mouse_btn.position
			elif mouse_btn.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mouse_btn.position, 1.1)
			elif mouse_btn.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mouse_btn.position, 1.0 / 1.1)
		else:
			if mouse_btn.button_index == MOUSE_BUTTON_LEFT:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging and _touch_points.is_empty():
		var motion := event as InputEventMouseMotion
		var delta = motion.position - _drag_last
		_drag_last = motion.position
		_world_node.position += delta
		_map_sprite.position += delta
		if _map_high_sprite:
			_map_high_sprite.position += delta
		_clamp_map_position()

	# Touch Input
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_points[touch.index] = touch.position
			if _touch_points.size() == 1:
				_dragging = true
				_drag_last = touch.position
		else:
			_touch_points.erase(touch.index)
			if _touch_points.is_empty():
				_dragging = false

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touch_points.has(drag.index):
			_touch_points[drag.index] = drag.position

		if _touch_points.size() == 1 and _dragging:
			var delta = drag.position - _drag_last
			_drag_last = drag.position
			_world_node.position += delta
			_map_sprite.position += delta
			if _map_high_sprite:
				_map_high_sprite.position += delta
			_clamp_map_position()
			
		elif _touch_points.size() == 2:
			var pts = _touch_points.values()
			var p1: Vector2 = pts[0]
			var p2: Vector2 = pts[1]
			
			var current_dist = p1.distance_to(p2)
			
			# Reconstruct previous distance using velocity
			var old_p1 = p1
			var old_p2 = p2
			if drag.position == p1:
				old_p1 = p1 - drag.velocity * get_process_delta_time()
			else:
				old_p2 = p2 - drag.velocity * get_process_delta_time()
				
			var old_dist = old_p1.distance_to(old_p2)
			
			if old_dist > 5.0 and current_dist > 5.0:
				var center = (p1 + p2) * 0.5
				var zoom_factor = current_dist / old_dist
				_zoom_at(center, zoom_factor)

func _activate_test_shift_cheat() -> void:
	_total_score = max(_total_score, shift_min_score)
	_shift_remaining_s = 0
	_shift_time_complete_announced = true
	_shift_ready_announced = true
	if _shift_timer:
		_shift_timer.stop()
	if _score_label:
		_score_label.text = "Score: %d" % _total_score
	_update_shift_ui()
	if _hint_label:
		_hint_label.text = "Testing cheat active: shift completion unlocked. Press Home to open evaluation."
	_show_kid_message("Testing Cheat Enabled", "Shift completion is unlocked for quick testing.\nUse Ctrl+Shift+F8 in route scene to re-apply anytime.")

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_scale = clamp(_current_scale * factor, _min_scale, _max_scale)
	var actual_factor = 1.0
	if _current_scale != 0.0:
		actual_factor = new_scale / _current_scale

	var delta_world = (1.0 - actual_factor) * (screen_pos - _world_node.position)
	var delta_map = (1.0 - actual_factor) * (screen_pos - _map_sprite.position)
	_world_node.position += delta_world
	_map_sprite.position += delta_map
	if _map_high_sprite:
		_map_high_sprite.position += delta_map
		
	_current_scale = new_scale
	_world_node.scale = Vector2(_current_scale, _current_scale)
	_map_sprite.scale = Vector2(_current_scale, _current_scale)
	if _map_high_sprite:
		_map_high_sprite.scale = Vector2(_current_scale, _current_scale)
		_update_map_lod(_current_scale)
		
	_user_zoomed = true
	_clamp_map_position()

func _clamped_map_offset(offset: Vector2) -> Vector2:
	var vp_size = get_viewport().get_visible_rect().size
	var scaled_w = float(_img_w) * _current_scale
	var scaled_h = float(_img_h) * _current_scale
	var out = offset

	var max_x = 0.0
	var min_x = vp_size.x - scaled_w
	var max_y = 0.0
	var min_y = vp_size.y - scaled_h

	if scaled_w <= vp_size.x:
		out.x = (vp_size.x - scaled_w) * 0.5
	else:
		out.x = clamp(out.x, min_x, max_x)

	if scaled_h <= vp_size.y:
		out.y = (vp_size.y - scaled_h) * 0.5
	else:
		out.y = clamp(out.y, min_y, max_y)

	return out

func _clamp_map_position() -> void:
	var clamped = _clamped_map_offset(_map_sprite.position)
	_map_sprite.position = clamped
	_world_node.position = clamped
	if _map_high_sprite:
		_map_high_sprite.position = clamped

func _update_map_lod(scale_val: float) -> void:
	if _map_high_sprite == null:
		return
	var fade_start = _min_scale * 1.35
	var fade_end = _min_scale * 2.2
	if scale_val <= fade_start:
		_map_high_sprite.modulate.a = 0.0
	elif scale_val >= fade_end:
		_map_high_sprite.modulate.a = 1.0
	else:
		_map_high_sprite.modulate.a = (scale_val - fade_start) / (fade_end - fade_start)

func _setup_hud() -> void:
	_mode_label = get_node_or_null("CanvasLayer/HUDPanel/HUDMargin/HUDContent/ModeLabel")
	_hint_label = get_node_or_null("CanvasLayer/HUDPanel/HUDMargin/HUDContent/HintLabel")
	_hud_content = get_node_or_null("CanvasLayer/HUDPanel/HUDMargin/HUDContent")
	var hud_panel: PanelContainer = get_node_or_null("CanvasLayer/HUDPanel")
	if hud_panel:
		hud_panel.offset_bottom = max(hud_panel.offset_bottom, 232.0)
	_home_button = get_node_or_null("CanvasLayer/HUDPanel/HUDMargin/HUDContent/HomeButton")
	if _home_button == null:
		_home_button = get_node_or_null("CanvasLayer/SettingsButton")
	if _home_button:
		# Add a nice little hover style override to the settings button
		var hover = StyleBoxFlat.new()
		hover.bg_color = Color(1.0, 1.0, 1.0, 0.1)
		hover.corner_radius_top_left = 6
		hover.corner_radius_top_right = 6
		hover.corner_radius_bottom_left = 6
		hover.corner_radius_bottom_right = 6
		_home_button.add_theme_stylebox_override("hover", hover)
		_home_button.pressed.connect(_on_home_pressed)

	if _hud_content and _minimized_call_button == null:
		_minimized_call_button = Button.new()
		_minimized_call_button.name = "ReturnToCallButton"
		_minimized_call_button.text = "Return to Call"
		_minimized_call_button.visible = false
		_minimized_call_button.custom_minimum_size = Vector2(0, 34)
		_minimized_call_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var min_style = StyleBoxFlat.new()
		min_style.bg_color = Color(0.8, 0.2, 0.25, 0.95)
		min_style.corner_radius_top_left = 8
		min_style.corner_radius_top_right = 8
		min_style.corner_radius_bottom_left = 8
		min_style.corner_radius_bottom_right = 8
		min_style.border_width_left = 2
		min_style.border_width_top = 2
		min_style.border_width_right = 2
		min_style.border_width_bottom = 2
		min_style.border_color = Color.WHITE
		_minimized_call_button.add_theme_stylebox_override("normal", min_style)
		_minimized_call_button.add_theme_stylebox_override("hover", min_style)
		_minimized_call_button.add_theme_color_override("font_color", Color.WHITE)
		_minimized_call_button.pressed.connect(_on_minimized_call_pressed)
		if _home_button and _home_button.get_parent() == _hud_content:
			_hud_content.add_child(_minimized_call_button)
			_hud_content.move_child(_minimized_call_button, _home_button.get_index())
		else:
			_hud_content.add_child(_minimized_call_button)

	if _hud_content and _next_day_button == null:
		_next_day_button = Button.new()
		_next_day_button.name = "ProceedNextDayButton"
		_next_day_button.text = "Proceed to Day %d" % (_current_day + 1)
		_next_day_button.visible = false
		_next_day_button.custom_minimum_size = Vector2(0, 36)
		_next_day_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var next_style = StyleBoxFlat.new()
		next_style.bg_color = Color(0.22, 0.62, 0.36, 0.95)
		next_style.corner_radius_top_left = 8
		next_style.corner_radius_top_right = 8
		next_style.corner_radius_bottom_left = 8
		next_style.corner_radius_bottom_right = 8
		next_style.border_width_left = 2
		next_style.border_width_top = 2
		next_style.border_width_right = 2
		next_style.border_width_bottom = 2
		next_style.border_color = Color(1.0, 1.0, 1.0, 0.9)
		_next_day_button.add_theme_stylebox_override("normal", next_style)
		_next_day_button.add_theme_stylebox_override("hover", next_style)
		_next_day_button.add_theme_color_override("font_color", Color.WHITE)
		_next_day_button.pressed.connect(_on_proceed_next_day_pressed)
		if _home_button and _home_button.get_parent() == _hud_content:
			_hud_content.add_child(_next_day_button)
			_hud_content.move_child(_next_day_button, _home_button.get_index())
		else:
			_hud_content.add_child(_next_day_button)

	# Add score label (top-left area of HUD)
	var canvas = get_node_or_null("CanvasLayer")
	if canvas:
		_score_label = Label.new()
		_score_label.name = "ScoreLabel"
		_score_label.text = "Score: 0"
		_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_score_label.offset_top = 16.0
		_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_score_label.add_theme_font_size_override("font_size", 26)
		_score_label.add_theme_constant_override("outline_size", 8)
		_score_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		_score_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		canvas.add_child(_score_label)

		_shift_label = Label.new()
		_shift_label.name = "ShiftLabel"
		_shift_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_shift_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_shift_label.offset_top = 50.0
		_shift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_shift_label.add_theme_font_size_override("font_size", 20)
		_shift_label.add_theme_constant_override("outline_size", 5)
		_shift_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.95))
		canvas.add_child(_shift_label)
		_update_shift_ui()

		_feedback_dialog = AcceptDialog.new()
		_feedback_dialog.name = "FeedbackDialog"
		_feedback_dialog.title = "Action Feedback"
		_feedback_dialog.exclusive = true
		_feedback_dialog.dialog_autowrap = true
		var feedback_style = StyleBoxFlat.new()
		feedback_style.bg_color = Color8(255, 244, 229)
		feedback_style.corner_radius_top_left = 14
		feedback_style.corner_radius_top_right = 14
		feedback_style.corner_radius_bottom_left = 14
		feedback_style.corner_radius_bottom_right = 14
		feedback_style.border_width_left = 3
		feedback_style.border_width_top = 3
		feedback_style.border_width_right = 3
		feedback_style.border_width_bottom = 3
		feedback_style.border_color = Color8(255, 160, 86)
		_feedback_dialog.add_theme_stylebox_override("panel", feedback_style)
		_feedback_dialog.add_theme_stylebox_override("embedded_border", feedback_style)
		_feedback_dialog.add_theme_color_override("title_color", Color8(44, 54, 72))
		var dialog_label = _feedback_dialog.get_label()
		if dialog_label:
			dialog_label.custom_minimum_size = Vector2(360, 0)
			dialog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dialog_label.add_theme_font_size_override("font_size", 19)
			dialog_label.add_theme_color_override("font_color", Color8(44, 54, 72))
		var feedback_ok = _feedback_dialog.get_ok_button()
		if feedback_ok:
			feedback_ok.add_theme_font_size_override("font_size", 17)
			feedback_ok.add_theme_color_override("font_color", Color8(44, 54, 72))
			var feedback_ok_style = StyleBoxFlat.new()
			feedback_ok_style.bg_color = Color8(255, 205, 104)
			feedback_ok_style.corner_radius_top_left = 10
			feedback_ok_style.corner_radius_top_right = 10
			feedback_ok_style.corner_radius_bottom_left = 10
			feedback_ok_style.corner_radius_bottom_right = 10
			feedback_ok_style.border_width_left = 2
			feedback_ok_style.border_width_top = 2
			feedback_ok_style.border_width_right = 2
			feedback_ok_style.border_width_bottom = 2
			feedback_ok_style.border_color = Color(1.0, 1.0, 1.0, 0.85)
			feedback_ok.add_theme_stylebox_override("normal", feedback_ok_style)
			feedback_ok.add_theme_stylebox_override("hover", feedback_ok_style)
			feedback_ok.add_theme_stylebox_override("pressed", feedback_ok_style)
		_feedback_dialog.confirmed.connect(_on_feedback_popup_closed)
		canvas.add_child(_feedback_dialog)

		_kid_message_dialog = AcceptDialog.new()
		_kid_message_dialog.name = "KidMessageDialog"
		_kid_message_dialog.title = "Great Job!"
		_kid_message_dialog.exclusive = false
		_kid_message_dialog.dialog_autowrap = true
		var kid_style = StyleBoxFlat.new()
		kid_style.bg_color = Color8(255, 244, 229)
		kid_style.corner_radius_top_left = 14
		kid_style.corner_radius_top_right = 14
		kid_style.corner_radius_bottom_left = 14
		kid_style.corner_radius_bottom_right = 14
		kid_style.border_width_left = 3
		kid_style.border_width_top = 3
		kid_style.border_width_right = 3
		kid_style.border_width_bottom = 3
		kid_style.border_color = Color8(255, 160, 86)
		_kid_message_dialog.add_theme_stylebox_override("panel", kid_style)
		_kid_message_dialog.add_theme_stylebox_override("embedded_border", kid_style)
		_kid_message_dialog.add_theme_color_override("title_color", Color8(44, 54, 72))
		var msg_label = _kid_message_dialog.get_label()
		if msg_label:
			msg_label.custom_minimum_size = Vector2(420, 0)
			msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			msg_label.add_theme_font_size_override("font_size", 20)
			msg_label.add_theme_color_override("font_color", Color8(44, 54, 72))
		var ok_btn = _kid_message_dialog.get_ok_button()
		if ok_btn:
			ok_btn.add_theme_font_size_override("font_size", 18)
			ok_btn.add_theme_color_override("font_color", Color8(44, 54, 72))
			var ok_style = StyleBoxFlat.new()
			ok_style.bg_color = Color8(255, 205, 104)
			ok_style.corner_radius_top_left = 10
			ok_style.corner_radius_top_right = 10
			ok_style.corner_radius_bottom_left = 10
			ok_style.corner_radius_bottom_right = 10
			ok_style.border_width_left = 2
			ok_style.border_width_top = 2
			ok_style.border_width_right = 2
			ok_style.border_width_bottom = 2
			ok_style.border_color = Color(1.0, 1.0, 1.0, 0.85)
			ok_btn.add_theme_stylebox_override("normal", ok_style)
			ok_btn.add_theme_stylebox_override("hover", ok_style)
			ok_btn.add_theme_stylebox_override("pressed", ok_style)
		_kid_message_dialog.confirmed.connect(_on_kid_message_dialog_confirmed)
		canvas.add_child(_kid_message_dialog)

		_shift_review_dialog = AcceptDialog.new()
		_shift_review_dialog.name = "ShiftReviewDialog"
		_shift_review_dialog.title = "Shift Review"
		_shift_review_dialog.dialog_autowrap = true
		_shift_review_dialog.exclusive = true
		_shift_review_dialog.borderless = true
		var review_style = StyleBoxFlat.new()
		review_style.bg_color = Color8(255, 244, 229)
		review_style.corner_radius_top_left = 14
		review_style.corner_radius_top_right = 14
		review_style.corner_radius_bottom_left = 14
		review_style.corner_radius_bottom_right = 14
		review_style.border_width_left = 3
		review_style.border_width_top = 3
		review_style.border_width_right = 3
		review_style.border_width_bottom = 3
		review_style.border_color = Color8(255, 160, 86)
		_shift_review_dialog.add_theme_stylebox_override("panel", review_style)
		_shift_review_dialog.add_theme_stylebox_override("embedded_border", review_style)
		_shift_review_dialog.add_theme_color_override("title_color", Color8(30, 38, 54))
		var review_label = _shift_review_dialog.get_label()
		if review_label:
			review_label.custom_minimum_size = Vector2(640, 56)
			review_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			review_label.add_theme_font_size_override("font_size", 19)
			review_label.add_theme_color_override("font_color", Color8(34, 46, 62))
		var review_ok = _shift_review_dialog.get_ok_button()
		if review_ok:
			review_ok.add_theme_font_size_override("font_size", 17)
			review_ok.add_theme_color_override("font_color", Color8(34, 46, 62))
			_style_choice_button(review_ok, 0.95)
		_shift_review_other_button = _shift_review_dialog.add_button("Review Other Options", false, "review_other_options")
		if _shift_review_other_button:
			_style_choice_button(_shift_review_other_button, 0.92)
			_shift_review_other_button.custom_minimum_size = Vector2(220, 40)
		var review_scroll = ScrollContainer.new()
		review_scroll.custom_minimum_size = Vector2(720, 360)
		review_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		review_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_shift_review_dialog.add_child(review_scroll)
		_shift_review_list = VBoxContainer.new()
		_shift_review_list.add_theme_constant_override("separation", 10)
		_shift_review_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		review_scroll.add_child(_shift_review_list)
		_shift_review_dialog.confirmed.connect(_on_shift_review_dialog_confirmed)
		_shift_review_dialog.custom_action.connect(_on_shift_review_custom_action)
		canvas.add_child(_shift_review_dialog)

		_other_options_dialog = AcceptDialog.new()
		_other_options_dialog.name = "OtherOptionsDialog"
		_other_options_dialog.title = "Other Options Review"
		_other_options_dialog.dialog_autowrap = true
		_other_options_dialog.exclusive = true
		_other_options_dialog.borderless = true
		_other_options_dialog.add_theme_stylebox_override("panel", review_style)
		_other_options_dialog.add_theme_stylebox_override("embedded_border", review_style)
		_other_options_dialog.add_theme_color_override("title_color", Color8(30, 38, 54))
		var other_lbl = _other_options_dialog.get_label()
		if other_lbl:
			other_lbl.custom_minimum_size = Vector2(640, 24)
			other_lbl.add_theme_font_size_override("font_size", 18)
			other_lbl.add_theme_color_override("font_color", Color8(34, 46, 62))
			other_lbl.text = ""
		var other_ok = _other_options_dialog.get_ok_button()
		if other_ok:
			_style_choice_button(other_ok, 0.92)
			other_ok.custom_minimum_size = Vector2(120, 38)
		var other_scroll = ScrollContainer.new()
		other_scroll.custom_minimum_size = Vector2(760, 420)
		other_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		other_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_other_options_dialog.add_child(other_scroll)
		_other_options_list = VBoxContainer.new()
		_other_options_list.add_theme_constant_override("separation", 10)
		_other_options_list.custom_minimum_size = Vector2(740, 420)
		_other_options_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_other_options_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		other_scroll.add_child(_other_options_list)
		canvas.add_child(_other_options_dialog)

	var state = get_node_or_null("/root/GameState")
	if state == null:
		return
	var mode: Dictionary = state.call("get_selected_mode")
	_selected_mode_id = String(mode.get("id", "easy_multiple_choice"))
	if state.has_method("get_locale"):
		_selected_locale = String(state.call("get_locale"))
	if state.has_method("get_current_day"):
		_current_day = max(1, int(state.call("get_current_day")))
	if state.has_method("get_day_difficulty_scale"):
		_day_difficulty_scale = max(1.0, float(state.call("get_day_difficulty_scale")))

	if _mode_label:
		_mode_label.text = "Mode: %s | Day %d" % [String(mode.get("title", "Dispatch Mode")), _current_day]
	if _hint_label:
		if String(mode.get("input_style", "multiple_choice")) == "typed_nlp":
			_hint_label.text = "Ask location and complaint first, then guide and dispatch. Day pace x%.2f" % _day_difficulty_scale
		else:
			_hint_label.text = "Tap alerts, ask location and complaint, answer safely, dispatch the best unit. Day pace x%.2f" % _day_difficulty_scale

var _pause_dialog: ConfirmationDialog

func _on_home_pressed() -> void:
	if _pause_dialog == null:
		_pause_dialog = ConfirmationDialog.new()
		_pause_dialog.title = "Paused"
		_pause_dialog.dialog_text = "Game paused. Resume to continue or exit to main menu."
		_pause_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		get_node("CanvasLayer").add_child(_pause_dialog)
		var ok_btn = _pause_dialog.get_ok_button()
		if ok_btn:
			ok_btn.text = "Exit to Menu"
		var cancel_btn = _pause_dialog.get_cancel_button()
		if cancel_btn:
			cancel_btn.text = "Resume"
			
		var early_btn = _pause_dialog.add_button("End Shift Early", true, "early_end")
			
		_pause_dialog.confirmed.connect(func():
			var tree = get_tree()
			if tree:
				tree.paused = false
				tree.change_scene_to_file(main_menu_scene_path)
		)
		
		_pause_dialog.custom_action.connect(func(action):
			if action == "early_end":
				_pause_dialog.hide()
				var tree = get_tree()
				if tree: tree.paused = false
				_force_early_end_shift()
		)

		_pause_dialog.about_to_popup.connect(func():
			var tree = get_tree()
			if tree:
				tree.paused = true
		)
		_pause_dialog.canceled.connect(func():
			var tree = get_tree()
			if tree:
				tree.paused = false
		)
	else:
		_pause_dialog.title = "Paused"
		_pause_dialog.dialog_text = "Game paused. Resume to continue or exit to main menu."
		
	_pause_dialog.popup_centered()

func _force_early_end_shift() -> void:
	if _shift_timer:
		_shift_timer.stop()
	
	if _total_score < shift_min_score:
		_pending_day_restart = false
		if _hint_label:
			_hint_label.text = "Shift failed: minimum score not reached. Day %d will restart." % _current_day
		_show_shift_review(
			"Shift Failed",
			"You completed %d calls and scored %d points. Minimum required score is %d. Day %d will restart after you close this review." % [_calls_completed, _total_score, shift_min_score, _current_day],
			"restart_day"
		)
	else:
		if _hint_label:
			_hint_label.text = "Day complete! Requirements met. Tap Proceed to Day %d." % (_current_day + 1)
		_open_shift_review_for_manual_end(
			"reload_scene",
			"Shift Evaluation",
			"Review Day %d performance, then continue to Day %d." % [_current_day, _current_day + 1]
		)

func _on_proceed_next_day_pressed() -> void:
	if not _can_end_shift():
		_show_kid_message("Shift In Progress", _shift_end_block_reason())
		return
	_open_shift_review_for_manual_end(
		"reload_scene",
		"Shift Evaluation",
		"Review Day %d performance, then continue to Day %d." % [_current_day, _current_day + 1]
	)

func _on_kid_message_dialog_confirmed() -> void:
	if not _pending_day_restart:
		return
	_pending_day_restart = false
	var tree = get_tree()
	if tree:
		tree.reload_current_scene()

func _setup_scenario_generator() -> void:
	if not ResourceLoader.exists("res://scripts/systems/emergency_scenario_generator.gd"):
		return
	var gen_script = load("res://scripts/systems/emergency_scenario_generator.gd")
	if gen_script:
		_scenario_generator = gen_script.new()

func _load_route_points_for_calls() -> void:
	_route_points_px.clear()
	if not FileAccess.file_exists(route_json_res_path):
		return
	var file = FileAccess.open(route_json_res_path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	var points_root = parsed
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("points"):
		points_root = parsed.get("points")
	if typeof(points_root) != TYPE_ARRAY:
		return

	for p in points_root:
		var nx = 0.0
		var ny = 0.0
		if typeof(p) == TYPE_DICTIONARY:
			nx = float(p.get("x", 0.0))
			ny = float(p.get("y", 0.0))
		elif typeof(p) == TYPE_ARRAY and p.size() >= 2:
			nx = float(p[0])
			ny = float(p[1])
		else:
			continue
		_route_points_px.append(Vector2(nx * float(_img_w), ny * float(_img_h)))

	_setup_safe_road_overlay()

func _setup_safe_road_overlay() -> void:
	if _world_node == null:
		return
	if _road_overlay_layer and is_instance_valid(_road_overlay_layer):
		_road_overlay_layer.queue_free()
		_road_overlay_layer = null
	if not use_safe_road_overlay:
		return
	if _route_points_px.size() < 2:
		return

	_road_overlay_layer = Node2D.new()
	_road_overlay_layer.name = "RoadOverlay"
	_road_overlay_layer.z_index = -2
	_world_node.add_child(_road_overlay_layer)
	_world_node.move_child(_road_overlay_layer, 0)

	var outline = Line2D.new()
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	outline.antialiased = true
	outline.default_color = road_outline_color
	outline.width = max(road_outline_width_px, road_inner_width_px + 2.0)
	_road_overlay_layer.add_child(outline)

	var inner = Line2D.new()
	inner.joint_mode = Line2D.LINE_JOINT_ROUND
	inner.begin_cap_mode = Line2D.LINE_CAP_ROUND
	inner.end_cap_mode = Line2D.LINE_CAP_ROUND
	inner.antialiased = true
	inner.default_color = road_inner_color
	inner.width = max(2.0, road_inner_width_px)
	_road_overlay_layer.add_child(inner)

	for p in _route_points_px:
		outline.add_point(p)
		inner.add_point(p)

func _setup_dispatch_timers() -> void:
	_transcript_timer = Timer.new()
	_transcript_timer.wait_time = transcript_tick_s
	_transcript_timer.one_shot = false
	_transcript_timer.timeout.connect(_on_transcript_tick)
	add_child(_transcript_timer)

	_next_call_timer = Timer.new()
	_next_call_timer.one_shot = true
	_next_call_timer.timeout.connect(_on_next_call_timeout)
	add_child(_next_call_timer)

	_arrival_timer = Timer.new()
	_arrival_timer.one_shot = true
	_arrival_timer.timeout.connect(_on_arrival_timeout)
	add_child(_arrival_timer)

	_resolution_timer = Timer.new()
	_resolution_timer.one_shot = true
	_resolution_timer.timeout.connect(_on_resolution_timeout)
	add_child(_resolution_timer)

	_shift_timer = Timer.new()
	_shift_timer.wait_time = 1.0
	_shift_timer.one_shot = false
	_shift_timer.timeout.connect(_on_shift_tick)
	add_child(_shift_timer)
	_shift_timer.start()

func _on_shift_tick() -> void:
	if _shift_remaining_s <= 0:
		if _shift_timer:
			_shift_timer.stop()
		return

	_shift_remaining_s -= 1
	_update_shift_ui()

	if _shift_remaining_s == 0 and not _shift_time_complete_announced:
		_shift_time_complete_announced = true
		if _total_score >= shift_min_score:
			if not _shift_ready_announced:
				_shift_ready_announced = true
				_show_kid_message("Shift Complete!", "Awesome work! You can now end your shift.")
		elif _hint_label:
			_hint_label.text = "Shift timer ended. Keep taking calls until you reach %d points." % shift_min_score

func _setup_dispatch_ui() -> void:
	var canvas = get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = CanvasLayer.new()
		canvas.name = "CanvasLayer"
		add_child(canvas)

	# ── Full-screen dim overlay ──────────────────────────────────────
	_dim_overlay = ColorRect.new()
	_dim_overlay.name = "DimOverlay"
	_dim_overlay.color = Color(0.0, 0.0, 0.05, 0.65)
	_dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim_overlay.visible = false
	canvas.add_child(_dim_overlay)

	# ── Main dispatch panel (centered, 911 Operator style) ─────────
	_dispatch_panel = PanelContainer.new()
	_dispatch_panel.name = "DispatchPanel"
	# Use anchor-based sizing so it always fits the viewport
	_dispatch_panel.anchor_left = 0.06
	_dispatch_panel.anchor_right = 0.94
	_dispatch_panel.anchor_top = 0.02
	_dispatch_panel.anchor_bottom = 0.98
	_dispatch_panel.offset_left = 0
	_dispatch_panel.offset_right = 0
	_dispatch_panel.offset_top = 0
	_dispatch_panel.offset_bottom = 0

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.14, 0.97)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.75, 0.15, 0.2, 1.0)
	_dispatch_panel.add_theme_stylebox_override("panel", panel_style)
	_dispatch_panel.visible = false
	canvas.add_child(_dispatch_panel)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 0)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_right", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	_dispatch_panel.add_child(margin)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 0)
	margin.add_child(outer_vbox)

	# ── Tab header row (INFO | DIALOG | ON SITE) ───────────────────
	_tab_container = HBoxContainer.new()
	_tab_container.add_theme_constant_override("separation", 0)
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_tab_container)

	var tab_names := ["INFO", "DIALOG", "ON SITE"]
	for i in range(tab_names.size()):
		var tab_btn = Button.new()
		tab_btn.text = tab_names[i]
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.custom_minimum_size = Vector2(0, 36)
		tab_btn.flat = true
		var tab_style_normal = StyleBoxFlat.new()
		if i == 1:  # DIALOG tab is active by default
			tab_style_normal.bg_color = Color(0.75, 0.15, 0.2, 1.0)
		else:
			tab_style_normal.bg_color = Color(0.12, 0.14, 0.22, 1.0)
		tab_style_normal.corner_radius_top_left = 4 if i == 0 else 0
		tab_style_normal.corner_radius_top_right = 4 if i == tab_names.size() - 1 else 0
		tab_style_normal.border_width_bottom = 2
		tab_style_normal.border_color = Color(0.75, 0.15, 0.2, 1.0)
		tab_btn.add_theme_stylebox_override("normal", tab_style_normal)
		tab_btn.add_theme_stylebox_override("hover", tab_style_normal)
		tab_btn.add_theme_stylebox_override("pressed", tab_style_normal)
		tab_btn.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96, 1.0))
		tab_btn.add_theme_font_size_override("font_size", 14)
		_tab_container.add_child(tab_btn)

	# ── Close (X) button overlaid on top-right ─────────────────────
	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.flat = true
	_close_button.custom_minimum_size = Vector2(52, 52)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.6, 0.1, 0.15, 1.0)
	close_style.corner_radius_top_right = 4
	_close_button.add_theme_stylebox_override("normal", close_style)
	var close_hover = StyleBoxFlat.new()
	close_hover.bg_color = Color(0.85, 0.2, 0.25, 1.0)
	close_hover.corner_radius_top_right = 4
	_close_button.add_theme_stylebox_override("hover", close_hover)
	_close_button.add_theme_color_override("font_color", Color.WHITE)
	_close_button.add_theme_font_size_override("font_size", 24)
	_close_button.pressed.connect(_on_close_call_panel)
	# Position the X on the top right corner of tab bar
	var last_tab = _tab_container.get_child(_tab_container.get_child_count() - 1)
	if last_tab:
		last_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Content area (padded) ──────────────────────────────────────
	var content_margin = MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 16)
	content_margin.add_theme_constant_override("margin_top", 12)
	content_margin.add_theme_constant_override("margin_right", 16)
	content_margin.add_theme_constant_override("margin_bottom", 16)
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(content_margin)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_margin.add_child(scroll)

	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	# ── Header: "INCOMING CALL:" ───────────────────────────────────
	var header_row = HBoxContainer.new()
	content.add_child(header_row)

	_panel_header_label = Label.new()
	_panel_header_label.text = "INCOMING CALL:"
	_panel_header_label.add_theme_font_size_override("font_size", 22)
	_panel_header_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 1.0))
	_panel_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_panel_header_label)

	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	header_row.add_child(_close_button)

	# ── Location info ──────────────────────────────────────────────
	_incident_summary_label = Label.new()
	_incident_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_incident_summary_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 1.0))
	_incident_summary_label.add_theme_font_size_override("font_size", 16)
	_incident_summary_label.custom_minimum_size = Vector2(0, 34)
	content.add_child(_incident_summary_label)

	_incoming_label = Label.new()
	_incoming_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_incoming_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85, 1.0))
	_incoming_label.add_theme_font_size_override("font_size", 13)
	_incoming_label.custom_minimum_size = Vector2(0, 42)
	content.add_child(_incoming_label)

	# ── Transcript area (dark inner panel) ─────────────────────────
	var transcript_panel = PanelContainer.new()
	var transcript_style = StyleBoxFlat.new()
	transcript_style.bg_color = Color(0.04, 0.05, 0.1, 1.0)
	transcript_style.corner_radius_top_left = 4
	transcript_style.corner_radius_top_right = 4
	transcript_style.corner_radius_bottom_left = 4
	transcript_style.corner_radius_bottom_right = 4
	transcript_style.border_width_left = 1
	transcript_style.border_width_top = 1
	transcript_style.border_width_right = 1
	transcript_style.border_width_bottom = 1
	transcript_style.border_color = Color(0.2, 0.25, 0.35, 0.8)
	transcript_panel.add_theme_stylebox_override("panel", transcript_style)
	transcript_panel.custom_minimum_size = Vector2(0, 170)
	content.add_child(transcript_panel)

	var transcript_margin = MarginContainer.new()
	transcript_margin.add_theme_constant_override("margin_left", 10)
	transcript_margin.add_theme_constant_override("margin_top", 8)
	transcript_margin.add_theme_constant_override("margin_right", 10)
	transcript_margin.add_theme_constant_override("margin_bottom", 8)
	transcript_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	transcript_panel.add_child(transcript_margin)

	_transcript_label = RichTextLabel.new()
	_transcript_label.bbcode_enabled = true
	_transcript_label.scroll_following = true
	_transcript_label.fit_content = false
	_transcript_label.add_theme_color_override("default_color", Color(0.78, 0.84, 0.95, 1.0))
	_transcript_label.add_theme_font_size_override("normal_font_size", 14)
	transcript_margin.add_child(_transcript_label)

	# ── Answer button ──────────────────────────────────────────────
	_answer_button = Button.new()
	_answer_button.text = "Answer Call"
	_answer_button.disabled = true
	_answer_button.custom_minimum_size = Vector2(0, 48)
	var answer_style = StyleBoxFlat.new()
	answer_style.bg_color = Color(0.08, 0.42, 0.18, 1.0)
	answer_style.corner_radius_top_left = 4
	answer_style.corner_radius_top_right = 4
	answer_style.corner_radius_bottom_left = 4
	answer_style.corner_radius_bottom_right = 4
	_answer_button.add_theme_stylebox_override("normal", answer_style)
	var answer_hover = answer_style.duplicate()
	answer_hover.bg_color = Color(0.1, 0.52, 0.22, 1.0)
	_answer_button.add_theme_stylebox_override("hover", answer_hover)
	var answer_disabled = answer_style.duplicate()
	answer_disabled.bg_color = Color(0.15, 0.18, 0.25, 0.6)
	_answer_button.add_theme_stylebox_override("disabled", answer_disabled)
	_answer_button.add_theme_color_override("font_color", Color.WHITE)
	_answer_button.add_theme_font_size_override("font_size", 15)
	_answer_button.pressed.connect(_on_answer_call_pressed)
	content.add_child(_answer_button)

	# ── Response prompt label ──────────────────────────────────────
	_response_prompt_label = Label.new()
	_response_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_response_prompt_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6, 1.0))
	_response_prompt_label.add_theme_font_size_override("font_size", 14)
	content.add_child(_response_prompt_label)

	# ── Multiple choice box ────────────────────────────────────────
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	content.add_child(_choices_box)

	# ── Hint System ───────────────────────────────────────────────
	_hint_button = Button.new()
	_hint_button.text = "Need a Hint?"
	_hint_button.visible = false
	_hint_button.custom_minimum_size = Vector2(0, 40)
	var hint_btn_style = StyleBoxFlat.new()
	hint_btn_style.bg_color = Color(0.2, 0.4, 0.6, 1.0)
	hint_btn_style.corner_radius_top_left = 4
	hint_btn_style.corner_radius_top_right = 4
	hint_btn_style.corner_radius_bottom_left = 4
	hint_btn_style.corner_radius_bottom_right = 4
	_hint_button.add_theme_stylebox_override("normal", hint_btn_style)
	_hint_button.add_theme_color_override("font_color", Color.WHITE)
	_hint_button.pressed.connect(_on_hint_button_pressed)
	content.add_child(_hint_button)

	_hint_display_label = RichTextLabel.new()
	_hint_display_label.bbcode_enabled = true
	_hint_display_label.fit_content = true
	_hint_display_label.visible = false
	var hint_lbl_style = StyleBoxFlat.new()
	hint_lbl_style.bg_color = Color(0.1, 0.2, 0.3, 1.0)
	hint_lbl_style.content_margin_left = 8
	hint_lbl_style.content_margin_top = 8
	hint_lbl_style.content_margin_right = 8
	hint_lbl_style.content_margin_bottom = 8
	hint_lbl_style.corner_radius_top_left = 4
	hint_lbl_style.corner_radius_top_right = 4
	hint_lbl_style.corner_radius_bottom_left = 4
	hint_lbl_style.corner_radius_bottom_right = 4
	_hint_display_label.add_theme_stylebox_override("normal", hint_lbl_style)
	content.add_child(_hint_display_label)

	# ── Typed input row (hidden by default) ────────────────────────
	_typed_row = HBoxContainer.new()
	_typed_row.visible = false
	_typed_row.add_theme_constant_override("separation", 8)
	content.add_child(_typed_row)

	_typed_input = LineEdit.new()
	_typed_input.placeholder_text = "Type your dispatch guidance here..."
	_typed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_typed_input.custom_minimum_size = Vector2(0, 44)
	var typed_style = StyleBoxFlat.new()
	typed_style.bg_color = Color8(250, 253, 255)
	typed_style.corner_radius_top_left = 4
	typed_style.corner_radius_top_right = 4
	typed_style.corner_radius_bottom_left = 4
	typed_style.corner_radius_bottom_right = 4
	typed_style.border_width_left = 1
	typed_style.border_width_top = 1
	typed_style.border_width_right = 1
	typed_style.border_width_bottom = 1
	typed_style.border_color = Color8(78, 141, 196)
	_typed_input.add_theme_stylebox_override("normal", typed_style)
	var typed_focus = typed_style.duplicate()
	typed_focus.bg_color = Color8(255, 255, 255)
	typed_focus.border_width_left = 2
	typed_focus.border_width_top = 2
	typed_focus.border_width_right = 2
	typed_focus.border_width_bottom = 2
	typed_focus.border_color = Color8(48, 128, 198)
	_typed_input.add_theme_stylebox_override("focus", typed_focus)
	_typed_input.add_theme_color_override("font_color", Color8(22, 33, 49))
	_typed_input.add_theme_color_override("font_placeholder_color", Color8(92, 112, 136))
	_typed_input.add_theme_color_override("caret_color", Color8(18, 103, 170))
	_typed_input.add_theme_color_override("selection_color", Color8(166, 218, 255, 190))
	if _typed_input.has_signal("text_submitted"):
		_typed_input.text_submitted.connect(_on_typed_text_submitted)
	_typed_row.add_child(_typed_input)

	_typed_submit_button = Button.new()
	_typed_submit_button.text = "Submit"
	_typed_submit_button.custom_minimum_size = Vector2(96, 44)
	var submit_btn_style = StyleBoxFlat.new()
	submit_btn_style.bg_color = Color(0.18, 0.45, 0.7, 1.0)
	submit_btn_style.corner_radius_top_left = 4
	submit_btn_style.corner_radius_top_right = 4
	submit_btn_style.corner_radius_bottom_left = 4
	submit_btn_style.corner_radius_bottom_right = 4
	_typed_submit_button.add_theme_stylebox_override("normal", submit_btn_style)
	_typed_submit_button.add_theme_color_override("font_color", Color.WHITE)
	_typed_submit_button.pressed.connect(_on_typed_submit_pressed)
	_typed_row.add_child(_typed_submit_button)

	# ── Feedback label ─────────────────────────────────────────────
	_response_feedback_label = Label.new()
	_response_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_response_feedback_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.78, 1.0))
	_response_feedback_label.add_theme_font_size_override("font_size", 13)
	content.add_child(_response_feedback_label)

	# ── Assignment label ───────────────────────────────────────────
	_assignment_label = Label.new()
	_assignment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assignment_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95, 1.0))
	_assignment_label.add_theme_font_size_override("font_size", 13)
	content.add_child(_assignment_label)

	# ── Vehicle dispatch grid ──────────────────────────────────────
	_vehicle_grid = GridContainer.new()
	_vehicle_grid.columns = 3
	_vehicle_grid.add_theme_constant_override("h_separation", 6)
	_vehicle_grid.add_theme_constant_override("v_separation", 6)
	_vehicle_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vehicle_grid.visible = false
	content.add_child(_vehicle_grid)

	_add_vehicle_button(_vehicle_grid, "fire_truck", "Dispatch Fire Truck", "res://assets/ui/icons/fire_truck.svg")
	_add_vehicle_button(_vehicle_grid, "ambulance", "Dispatch Ambulance", "res://assets/ui/icons/ambulance.svg")
	_add_vehicle_button(_vehicle_grid, "police", "Dispatch Police", "res://assets/ui/icons/police.svg")
	_set_vehicle_buttons_enabled(false)

	# ── Timeline label ─────────────────────────────────────────────
	_timeline_label = Label.new()
	_timeline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_timeline_label.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4, 1.0))
	_timeline_label.add_theme_font_size_override("font_size", 13)
	content.add_child(_timeline_label)

	# ── End call button ────────────────────────────────────────────
	_end_call_button = Button.new()
	_end_call_button.text = "End Call"
	_end_call_button.disabled = true
	_end_call_button.custom_minimum_size = Vector2(0, 46)
	var end_style = StyleBoxFlat.new()
	end_style.bg_color = Color(0.6, 0.12, 0.16, 1.0)
	end_style.corner_radius_top_left = 4
	end_style.corner_radius_top_right = 4
	end_style.corner_radius_bottom_left = 4
	end_style.corner_radius_bottom_right = 4
	_end_call_button.add_theme_stylebox_override("normal", end_style)
	var end_hover = end_style.duplicate()
	end_hover.bg_color = Color(0.8, 0.18, 0.22, 1.0)
	_end_call_button.add_theme_stylebox_override("hover", end_hover)
	var end_disabled = end_style.duplicate()
	end_disabled.bg_color = Color(0.15, 0.18, 0.25, 0.6)
	_end_call_button.add_theme_stylebox_override("disabled", end_disabled)
	_end_call_button.add_theme_color_override("font_color", Color.WHITE)
	_end_call_button.pressed.connect(_on_end_call_pressed)
	content.add_child(_end_call_button)

	# ── Guidebook panel (unchanged position) ───────────────────────
	_setup_manual_panel(canvas)

	# ── Off-screen Indicator ─────────────────────────────────────────
	_offscreen_indicator = Area2D.new()
	_offscreen_indicator.name = "OffscreenIndicator"
	_offscreen_indicator.input_pickable = true
	_offscreen_indicator.visible = false
	canvas.add_child(_offscreen_indicator)

	var call_bg = Polygon2D.new()
	var call_bg_pts = PackedVector2Array()
	for i in range(24):
		var angle = (float(i) / 24.0) * TAU
		call_bg_pts.append(Vector2(cos(angle) * 16.0, sin(angle) * 16.0))
	call_bg.polygon = call_bg_pts
	call_bg.color = Color(0.9, 0.2, 0.24, 0.95)
	_offscreen_indicator.add_child(call_bg)

	var call_stem = Polygon2D.new()
	call_stem.polygon = PackedVector2Array([
		Vector2(-2.5, -10.0), Vector2(2.5, -10.0), Vector2(1.8, 2.0), Vector2(-1.8, 2.0)
	])
	call_stem.color = Color.WHITE
	_offscreen_indicator.add_child(call_stem)

	var call_dot = Polygon2D.new()
	var call_dot_pts = PackedVector2Array()
	for i in range(10):
		var angle = (float(i) / 10.0) * TAU
		call_dot_pts.append(Vector2(cos(angle) * 2.4, sin(angle) * 2.4 + 7.0))
	call_dot.polygon = call_dot_pts
	call_dot.color = Color.WHITE
	_offscreen_indicator.add_child(call_dot)

	_offscreen_indicator_arrow = Polygon2D.new()
	_offscreen_indicator_arrow.polygon = PackedVector2Array([
		Vector2(24.0, 0.0), Vector2(12.0, -5.0), Vector2(12.0, 5.0)
	])
	_offscreen_indicator_arrow.color = Color(0.95, 0.95, 1.0, 0.95)
	_offscreen_indicator.add_child(_offscreen_indicator_arrow)
	
	var indicator_collision = CollisionShape2D.new()
	var indicator_shape = CircleShape2D.new()
	indicator_shape.radius = 22.0
	indicator_collision.shape = indicator_shape
	_offscreen_indicator.add_child(indicator_collision)
	
	_offscreen_indicator.input_event.connect(_on_offscreen_indicator_clicked)

	_set_dispatch_panel_waiting_state("Stand by for incoming calls.")

func _on_minimized_call_pressed() -> void:
	if _active_call.is_empty():
		if _minimized_call_button:
			_minimized_call_button.visible = false
		return
	if _minimized_call_button:
		_minimized_call_button.visible = false
	if _dispatch_panel:
		_dispatch_panel.visible = true
	if _dim_overlay:
		_dim_overlay.visible = true
	_call_active = true
	if _hint_label:
		_hint_label.text = "Call reopened. Continue transcript, then dispatch unit."
	if _is_interactive_tutorial and _answer_button and not _answer_button.disabled:
		_point_coach_at(_answer_button, "Tap Answer")

func _on_offscreen_indicator_clicked(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _active_call_marker != null and is_instance_valid(_active_call_marker):
			_pan_map_to_world_point(_active_call_marker.position)

func _pan_map_to_world_point(world_point: Vector2) -> void:
	if _world_node == null or _map_sprite == null:
		return
	var viewport_center = get_viewport().get_visible_rect().size * 0.5
	var target_offset = _clamped_map_offset(viewport_center - world_point * _current_scale)
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(_world_node, "position", target_offset, 0.42)
	tween.parallel().tween_property(_map_sprite, "position", target_offset, 0.42)

func _minimize_call_during_dispatch() -> void:
	if _dispatch_panel:
		_dispatch_panel.visible = false
	if _dim_overlay:
		_dim_overlay.visible = false
	if _minimized_call_button:
		_minimized_call_button.visible = true

func _restore_call_after_dispatch() -> void:
	if _minimized_call_button:
		_minimized_call_button.visible = false
	if _dispatch_panel:
		_dispatch_panel.visible = true
	if _dim_overlay:
		_dim_overlay.visible = true

func _setup_manual_panel(canvas: Node) -> void:
	_manual_panel = PanelContainer.new()
	_manual_panel.name = "ManualPanel"
	_manual_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_manual_panel.offset_left = -580.0
	_manual_panel.offset_top = 630.0
	_manual_panel.offset_right = -16.0
	_manual_panel.offset_bottom = 1000.0
	var manual_style = StyleBoxFlat.new()
	manual_style.bg_color = Color(0.08, 0.1, 0.18, 0.96)
	manual_style.corner_radius_top_left = 6
	manual_style.corner_radius_top_right = 6
	manual_style.corner_radius_bottom_left = 6
	manual_style.corner_radius_bottom_right = 6
	manual_style.border_width_left = 2
	manual_style.border_width_top = 2
	manual_style.border_width_right = 2
	manual_style.border_width_bottom = 2
	manual_style.border_color = Color(0.4, 0.5, 0.65, 0.8)
	_manual_panel.add_theme_stylebox_override("panel", manual_style)
	_manual_panel.visible = false
	canvas.add_child(_manual_panel)

	var manual_margin = MarginContainer.new()
	manual_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	manual_margin.add_theme_constant_override("margin_left", 14)
	manual_margin.add_theme_constant_override("margin_top", 14)
	manual_margin.add_theme_constant_override("margin_right", 14)
	manual_margin.add_theme_constant_override("margin_bottom", 14)
	_manual_panel.add_child(manual_margin)

	_manual_text = RichTextLabel.new()
	_manual_text.fit_content = false
	_manual_text.scroll_active = true
	_manual_text.bbcode_enabled = true
	_manual_text.text = _build_manual_text()
	_manual_text.add_theme_color_override("default_color", Color(0.85, 0.9, 0.95, 1.0))
	manual_margin.add_child(_manual_text)

func _add_vehicle_button(parent: Node, vehicle_id: String, label_text: String, icon_path: String) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 88)
	btn.expand_icon = true
	btn.add_theme_font_size_override("font_size", 17)
	btn.icon = _load_icon(icon_path)
	btn.tooltip_text = "Tap to dispatch this unit"
	btn.pressed.connect(Callable(self, "_on_vehicle_button_pressed").bind(vehicle_id))
	parent.add_child(btn)
	_vehicle_buttons[vehicle_id] = btn

func _load_icon(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if tex is Texture2D:
		return tex
	return null

func _build_manual_text() -> String:
	var lines = [
		"[b]Emergency Guidebook[/b]",
		"",
		"1. Respond to emergency callers quickly and accurately.",
		"2. Keep the caller calm and confirm exact location.",
		"3. Protect lives before property.",
		"4. Never advise dangerous actions (example: water on grease fire).",
		"5. Dispatch the best unit for incident type.",
		"",
		"[b]Call Flow[/b]",
		"- Wait for an emergency alert pin on the map.",
		"- Click the alert pin to open the conversation panel.",
		"- Answer the caller (multiple choice or typed NLP mode).",
		"- Dispatch the correct emergency vehicle.",
		"- End call only after services arrive.",
		"",
		"[b]Quick Unit Matching[/b]",
		"- Fire Truck: active fire, smoke, burning structures.",
		"- Ambulance: transport patients safely to hospital for medical emergencies, injuries, breathing problems, AND technical operations like extrication of trapped victims or building collapse.",
		"- Police: violence, threats, criminal activity."
	]
	return "\n".join(lines)

func _on_manual_button_pressed() -> void:
	if _manual_panel:
		_manual_panel.visible = not _manual_panel.visible


func _schedule_next_call(delay_s: float) -> void:
	if _remaining_shift_call_slots() <= 0:
		if _active_call.is_empty() and not _call_active:
			_set_dispatch_panel_waiting_state("Daily call limit reached for this shift.")
		return
	if _next_call_timer:
		_next_call_timer.start(max(0.2, delay_s))
	if _active_call.is_empty() and not _call_active:
		_set_dispatch_panel_waiting_state("Stand by. New incident coming soon.")
	if _is_interactive_tutorial and _tutorial_label:
		_tutorial_label.text = "An emergency call is coming! Wait for it to appear."

func _set_dispatch_panel_waiting_state(message: String) -> void:
	if _panel_header_label:
		_panel_header_label.text = "INCOMING CALL"
	if _incident_summary_label:
		_incident_summary_label.text = ""
	if _incoming_label:
		_incoming_label.text = message
	if _dispatch_panel:
		_dispatch_panel.visible = false
	if _answer_button:
		_answer_button.disabled = true
		_answer_button.text = "Answer Call"
	if _response_prompt_label:
		_response_prompt_label.text = ""
	if _response_feedback_label:
		_response_feedback_label.text = ""
	if _assignment_label:
		_assignment_label.text = ""
	if _timeline_label:
		_timeline_label.text = ""
	if _end_call_button:
		_end_call_button.text = "End Call"
		_end_call_button.disabled = true
	_dispatch_phase_unlocked = false
	if _vehicle_grid:
		_vehicle_grid.visible = false
	_set_vehicle_buttons_enabled(false)
	_hide_coach_pointer()

func _on_next_call_timeout() -> void:
	if not _pending_call.is_empty():
		return
	if _active_call_marker and is_instance_valid(_active_call_marker):
		return
	if not _queued_calls.is_empty():
		return
	if _remaining_shift_call_slots() <= 0:
		if _hint_label:
			_hint_label.text = "Daily call limit reached for this shift."
		return
	if _route_points_px.is_empty():
		_set_dispatch_panel_waiting_state("Route data unavailable. Check route JSON.")
		_schedule_next_call(dispatch_between_calls_max_s)
		return
	var generated = _generate_call_scenario()
	if generated.is_empty():
		_schedule_next_call(dispatch_between_calls_max_s)
		return
	if not generated.has("marker_pos"):
		generated["marker_pos"] = _pick_random_road_position()

	# If a call is still being handled, queue the new emergency so it can be answered next.
	if not _active_call.is_empty() or _call_active:
		if _queued_calls.size() < max_waiting_calls and _remaining_shift_call_slots() > 0:
			_queued_calls.append(generated)
			if _response_feedback_label:
				_response_feedback_label.text = "New emergency reported. Waiting queue: %d" % _queued_calls.size()
			if _hint_label:
				_hint_label.text = "Another emergency has been reported and queued while units are still resolving the previous call."
			_update_end_call_button_state()
			if _has_dispatched_vehicle:
				_schedule_background_emergency_if_needed()
		return

	_pending_call = generated
	_spawn_call_marker()

func _generate_call_scenario() -> Dictionary:
	if _is_interactive_tutorial and _calls_completed == 0:
		return {
			"type": "fire",
			"severity": "medium",
			"title": "Tutorial Fire",
			"location": "123 Training Av. (Tutorial)",
			"recommended_vehicle": "fire_truck",
			"transcript": [
				{"speaker": "Caller", "text": "Help! There is a small fire in my kitchen!"},
				{"speaker": "911", "text": "Are you safe? Can you evacuate?"},
				{"speaker": "Caller", "text": "I am safe outside, but the fire is spreading."},
				{"speaker": "911", "text": "Stay on the line. I need to give you instructions."},
				{"speaker": "Caller", "text": "Okay, please tell me what we should do!"}
			],
			"options": [
				{
					"text": "Go to the kitchen and try to put it out with water.",
					"label": "unsafe",
					"explanation": "Never use water on an unknown kitchen fire (it might be a grease fire!).",
					"feedback": "Dangerous advice!"
				},
				{
					"text": "Stay outside, do not re-enter, and wait for the fire truck.",
					"label": "safe",
					"explanation": "The safest action is to evacuate and wait for professionals.",
					"feedback": "Correct! Prioritize life safety above all."
				}
			]
		}

	if _scenario_generator and _scenario_generator.has_method("generate_scenario"):
		var generated = _scenario_generator.call("generate_scenario", _selected_mode_id, _selected_locale, _current_day)
		if typeof(generated) == TYPE_DICTIONARY:
			return generated
	return {
		"type": "fire",
		"severity": "medium",
		"title": "Fallback Emergency",
		"location": "Santa Cruz center",
		"recommended_vehicle": "fire_truck",
		"transcript": [
			{"speaker": "911", "text": "911, what is your emergency?"},
			{"speaker": "Caller", "text": "There is smoke inside our building!"}
		],
		"options": [
			{"text": "Evacuate everyone and dispatch a fire truck.", "label": "safe", "feedback": "Good response."},
			{"text": "Ignore and wait.", "label": "unsafe", "feedback": "Unsafe response."}
		]
	}

func _spawn_call_marker() -> void:
	if _pending_call.is_empty():
		return
	if _active_call_marker and is_instance_valid(_active_call_marker):
		_active_call_marker.queue_free()

	var marker = Node2D.new()
	marker.name = "EmergencyCallMarker"
	var marker_pos = _pending_call.get("marker_pos", _pick_random_road_position())
	if marker_pos is Vector2:
		marker.position = marker_pos
	else:
		marker.position = _pick_random_road_position()

	var area = Area2D.new()
	area.input_pickable = true
	var shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = 28.0
	shape.shape = circle_shape
	area.add_child(shape)
	area.input_event.connect(Callable(self, "_on_call_marker_input_event").bind(marker))
	marker.add_child(area)

	# Red circle background
	var bg_circle = Polygon2D.new()
	var circle_pts = PackedVector2Array()
	for i in range(32):
		var angle = (float(i) / 32.0) * TAU
		circle_pts.append(Vector2(cos(angle) * 22.0, sin(angle) * 22.0))
	bg_circle.polygon = circle_pts
	bg_circle.color = Color(0.85, 0.15, 0.2, 1.0)
	marker.add_child(bg_circle)

	# White "!" exclamation mark — stem (tall rectangle)
	var stem = Polygon2D.new()
	stem.polygon = PackedVector2Array([
		Vector2(-3, -14), Vector2(3, -14), Vector2(2, 3), Vector2(-2, 3)
	])
	stem.color = Color.WHITE
	marker.add_child(stem)

	# White "!" exclamation mark — dot (small circle)
	var dot = Polygon2D.new()
	var dot_pts = PackedVector2Array()
	for i in range(12):
		var angle = (float(i) / 12.0) * TAU
		dot_pts.append(Vector2(cos(angle) * 3.0, sin(angle) * 3.0 + 9.0))
	dot.polygon = dot_pts
	dot.color = Color.WHITE
	marker.add_child(dot)

	_world_node.add_child(marker)
	_active_call_marker = marker

	var tw = marker.create_tween()
	tw.set_loops()
	tw.tween_property(marker, "scale", Vector2(1.2, 1.2), 0.45)
	tw.tween_property(marker, "scale", Vector2.ONE, 0.45)

	if _hint_label:
		_hint_label.text = "Incoming emergency call! Click the alert icon to answer."
	if _is_interactive_tutorial and _tutorial_label:
		_tutorial_label.text = "Click the red '!' alert icon on the map to open the call."

func _on_call_marker_input_event(_viewport: Node, event: InputEvent, _shape_idx: int, marker: Node2D) -> void:
	if event is InputEventMouseButton:
		var mouse = event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			_dragging = false
			_open_call_from_marker(marker)

func _process(_delta: float) -> void:
	_update_dispatched_vehicle_follow(_delta)
	if _tutorial_focus_target != null:
		_update_tutorial_focus_layout()
	if _active_call_marker != null and is_instance_valid(_active_call_marker) and _offscreen_indicator != null:
		var vp_rect = get_viewport_rect()
		
		# Getting global position on screen by taking canvas transform into account
		var canvas_transform = get_canvas_transform()
		var marker_screen_pos = canvas_transform * _active_call_marker.global_position
		
		# Define a safe margin (how close to edge before it's "offscreen")
		var margin = 32.0
		var padded_rect = vp_rect.grow(-margin)
		
		if not padded_rect.has_point(marker_screen_pos) and not _call_active:
			_offscreen_indicator.visible = true
			
			# Clamp indicator position to screen edges
			var ind_pos = marker_screen_pos
			ind_pos.x = clamp(ind_pos.x, margin, vp_rect.size.x - margin)
			ind_pos.y = clamp(ind_pos.y, margin, vp_rect.size.y - margin)
			_offscreen_indicator.position = ind_pos
			
			# Keep bubble upright; rotate only compass arrow toward call location.
			_offscreen_indicator.rotation = 0.0
			if _offscreen_indicator_arrow:
				_offscreen_indicator_arrow.rotation = ind_pos.angle_to_point(marker_screen_pos)
			
			# Pulse animation for the call indicator
			_offscreen_indicator.scale = Vector2.ONE * (1.0 + sin(Time.get_ticks_msec() / 220.0) * 0.12)
		else:
			_offscreen_indicator.visible = false
	elif _offscreen_indicator != null:
		_offscreen_indicator.visible = false

func _update_dispatched_vehicle_follow(delta: float) -> void:
	if not _follow_dispatched_vehicle or not _follow_vehicle_pos_valid:
		return
	if _world_node == null or _map_sprite == null:
		return
	var viewport_center = get_viewport().get_visible_rect().size * 0.5
	var target_offset = _clamped_map_offset(viewport_center - _follow_vehicle_world_pos * _current_scale)
	var blend = clamp(delta * max(1.0, responder_follow_smoothing), 0.0, 1.0)
	_world_node.position = _world_node.position.lerp(target_offset, blend)
	_map_sprite.position = _map_sprite.position.lerp(target_offset, blend)

func _on_response_position_updated(_vehicle_id: String, world_position: Vector2) -> void:
	_follow_vehicle_world_pos = world_position
	_follow_vehicle_pos_valid = true

func _open_call_from_marker(marker: Node2D) -> void:
	if marker != _active_call_marker:
		return
	if _pending_call.is_empty():
		return

	_active_call_world_position = marker.position
	_pan_map_to_world_point(marker.position)
	if _active_call_marker and is_instance_valid(_active_call_marker):
		_active_call_marker.queue_free()
	_active_call_marker = null

	_active_call = _pending_call.duplicate(true)
	_pending_call.clear()
	_call_sequence += 1
	_transcript_index = 0
	_conversation_log.clear()
	_intake_location_asked = false
	_intake_emergency_asked = false
	_awaiting_dispatch = false
	_services_arrived = false
	_response_quality = "uncertain"
	_dispatch_phase_unlocked = false
	_has_dispatched_vehicle = false
	_is_waiting_for_llm = false
	_call_active = true
	if _minimized_call_button:
		_minimized_call_button.visible = false

	if _dim_overlay:
		_dim_overlay.visible = true
	if _dispatch_panel:
		_dispatch_panel.visible = true
	if _panel_header_label:
		_panel_header_label.text = "CALL #%d | %s" % [_call_sequence, String(_active_call.get("type", "Emergency")).to_upper()]
	_set_intake_state(false, false)
	_intake_stage = 0

	if _hint_label:
		_hint_label.text = "Call active. Ask location and complaint, then guide and dispatch."
	if _is_interactive_tutorial and _tutorial_label:
		_tutorial_label.text = "Click 'Answer Call' to connect to the citizen."

	if _transcript_label:
		_transcript_label.clear()
	_append_transcript_line("System", "Call connected. Recording live transcript...")

	_clear_choice_buttons()
	if _typed_row:
		_typed_row.visible = false
	if _typed_input:
		_typed_input.text = ""
	if _response_feedback_label:
		_response_feedback_label.text = ""
	if _response_prompt_label:
		_response_prompt_label.text = "Press Answer Call to begin transcription."
	if _assignment_label:
		_assignment_label.text = ""
	if _timeline_label:
		_timeline_label.text = ""
	_set_vehicle_buttons_enabled(false)
	if _vehicle_grid:
		_vehicle_grid.visible = false

	if _answer_button:
		_answer_button.disabled = false
		_answer_button.text = "Answer Call"
		if _is_interactive_tutorial:
			_point_coach_at(_answer_button, "Tap Answer")
	if _end_call_button:
		_end_call_button.text = "End Call"
		_end_call_button.disabled = true

func _on_answer_call_pressed() -> void:
	if _active_call.is_empty():
		return
	if _answer_button:
		_answer_button.disabled = true
		_answer_button.text = "Call In Progress"

	# Add the complete transcript for the interactive steps
	_caller_lines.clear()
	_caller_line_index = 0
	_interactive_phase = 0
	_player_responded_this_round = false
	_intake_stage = 0
	_professional_scored_tags.clear()
	_call_score = 0
	_call_start_time = Time.get_ticks_msec() / 1000.0
	_current_call_review = {
		"call_number": _call_sequence,
		"title": String(_active_call.get("title", "Emergency")),
		"type": String(_active_call.get("type", "unknown")),
		"location": String(_active_call.get("location", "Unknown")),
		"checks_total": 0,
		"checks_correct": 0,
		"score": 0,
		"protocol_hits": [],
		"response": {},
		"dispatch": {}
	}

	_has_dispatched_vehicle = false
	_dispatch_phase_unlocked = false
	_set_vehicle_buttons_enabled(false)
	if _vehicle_grid:
		_vehicle_grid.visible = false
	if _assignment_label:
		_assignment_label.text = "Finish the caller conversation first. Dispatch buttons unlock after response review."

	if _response_prompt_label:
		_response_prompt_label.text = "Begin intake by asking location first."

	_start_intake_prompt()

	if _is_interactive_tutorial and _tutorial_label:
		_tutorial_label.text = "Start with intake. Ask where they are and what happened."

func _play_next_caller_line() -> void:
	if _caller_line_index < _caller_lines.size():
		var line: Dictionary = _caller_lines[_caller_line_index]
		var speaker = String(line.get("speaker", "Caller"))
		var text = String(line.get("text", ""))
		
		if speaker == "911":
			_show_dispatcher_prompt(text)
		else:
			_append_transcript_line(speaker, text)
			_caller_line_index += 1
			if _transcript_timer:
				_transcript_timer.start()
	else:
		_show_player_choices()

func _show_dispatcher_prompt(text: String) -> void:
	_clear_choice_buttons()
	if _selected_mode_id != "easy_multiple_choice":
		_awaiting_dispatcher_prompt = true
		_expected_dispatcher_prompt_text = text
		if _typed_row:
			_typed_row.visible = true
		if _typed_input:
			_typed_input.placeholder_text = "Type what you want to ask the caller..."
			_typed_input.grab_focus()
		if _response_prompt_label:
			_response_prompt_label.text = "Type your next question to the caller."
		return

	if _typed_row:
		_typed_row.visible = false
	if _response_prompt_label:
		_response_prompt_label.text = "Ask the caller:"
	
	if _choices_box:
		var btn = Button.new()
		btn.text = text
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_choice_button(btn, _ui_scale_factor())
		btn.pressed.connect(Callable(self, "_on_dispatcher_prompt_pressed").bind(text))
		_choices_box.add_child(btn)
		_animate_choice_button_attention(btn)

func _on_dispatcher_prompt_pressed(text: String) -> void:
	_clear_choice_buttons()
	_append_transcript_line("Dispatcher", text)
	if _response_prompt_label:
		_response_prompt_label.text = "Caller is responding..."
	_caller_line_index += 1
	if _transcript_timer:
		_transcript_timer.start()

func _on_transcript_tick() -> void:
	# In the new interactive flow, the timer is used as a delay between
	# caller lines when continuing after player responds
	if _transcript_timer:
		_transcript_timer.stop()
	_play_next_caller_line()

func _show_player_choices() -> void:
	_clear_choice_buttons()
	if _typed_row:
		_typed_row.visible = false

	if _selected_mode_id == "easy_multiple_choice":
		var options: Array = _active_call.get("options", [])
		if _response_prompt_label:
			_response_prompt_label.text = "Choose one response option below:"
		for i in range(options.size()):
			var option: Dictionary = options[i]
			var btn = Button.new()
			btn.text = String(option.get("text", "Option"))
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_style_choice_button(btn, _ui_scale_factor())
			btn.pressed.connect(Callable(self, "_on_choice_option_pressed").bind(i))
			if _choices_box:
				_choices_box.add_child(btn)
			_animate_choice_button_attention(btn, i)
		if _hint_button:
			_hint_button.visible = true
		if _is_interactive_tutorial:
			_point_coach_at(_choices_box, "Pick safest")
	else:
		if _response_prompt_label:
			_response_prompt_label.text = "Type your response to the caller:"
		if _typed_row:
			_typed_row.visible = true
		if _is_interactive_tutorial and _typed_submit_button:
			_point_coach_at(_typed_submit_button, "Submit")

	if _is_interactive_tutorial and _tutorial_label:
		_tutorial_label.text = "Click the safest response. Never instruct them to use water on this fire!"

func _start_dispatch_phase() -> void:
	_clear_choice_buttons()
	if _typed_row:
		_typed_row.visible = false
	if not _has_dispatched_vehicle:
		_dispatch_phase_unlocked = true
		if _vehicle_grid:
			_vehicle_grid.visible = true
		_set_vehicle_buttons_enabled(true)
		if _response_prompt_label:
			_response_prompt_label.text = "Now dispatch the best emergency vehicle."
		if _assignment_label:
			_assignment_label.text = "Dispatch is unlocked: tap one emergency unit now."
	else:
		if _response_prompt_label:
			_response_prompt_label.text = "Keep caller calm while units travel to the scene."

	if _is_interactive_tutorial and _tutorial_label:
		_tutorial_label.text = "Excellent. Now click the Fire Truck below to dispatch help!"
		var coached_vehicle = _vehicle_buttons.get("fire_truck", null)
		if coached_vehicle == null:
			coached_vehicle = _vehicle_buttons.get(String(_active_call.get("recommended_vehicle", "")), null)
		if coached_vehicle is Control:
			_point_coach_at(coached_vehicle, "Dispatch")
	_update_end_call_button_state()

func _on_choice_option_pressed(option_idx: int) -> void:
	if _active_call.is_empty() or _player_responded_this_round:
		return
	var options: Array = _active_call.get("options", [])
	if option_idx < 0 or option_idx >= options.size():
		return

	_player_responded_this_round = true
	var selected: Dictionary = options[option_idx]
	var chosen_text = String(selected.get("text", ""))
	_append_transcript_line("Dispatcher", chosen_text)
	var label = String(selected.get("label", "uncertain"))
	var explanation = String(selected.get("explanation", ""))
	if explanation.is_empty():
		explanation = String(selected.get("feedback", ""))
	_record_response_review(chosen_text, label, explanation, options)
	_score_and_show_feedback(label, chosen_text, explanation)

func _on_typed_submit_pressed() -> void:
	if _active_call.is_empty():
		return
	var user_text = _typed_input.text.strip_edges() if _typed_input else ""
	if user_text == "":
		if _response_feedback_label:
			_response_feedback_label.text = "Please type a response first."
		return

	# (Silent tracking now happens via the LLM response below)
	if _has_dispatched_vehicle and _selected_mode_id != "easy_multiple_choice":
		_handle_post_dispatch_chat(user_text)
		return

	if _awaiting_dispatcher_prompt:
		_awaiting_dispatcher_prompt = false
		_score_professional_turn(user_text)
		_append_transcript_line("Dispatcher", user_text)
		if _typed_input:
			_typed_input.text = ""
		if _response_prompt_label:
			_response_prompt_label.text = "Caller is responding..."
		_caller_line_index += 1
		if _transcript_timer:
			_transcript_timer.start()
		return

	if _is_waiting_for_llm:
		return

	_score_professional_turn(user_text)
	_append_transcript_line("Dispatcher", user_text)
	if _typed_input:
		_typed_input.text = ""
	
	_is_waiting_for_llm = true
	if _typed_input:
		_typed_input.editable = false
	var result: Dictionary = {}
	if _groq_http != null:
		var raw_groq = await _call_groq_evaluate_and_reply(user_text)
		if not raw_groq.is_empty():
			result = raw_groq
	
	if _typed_input:
		_typed_input.editable = true
		_typed_input.grab_focus()

	if result.is_empty():
		# Fallback keyword logic
		if _scenario_generator and _scenario_generator.has_method("evaluate_typed_response"):
			result = _scenario_generator.call("evaluate_typed_response", _active_call, user_text)
		else:
			result = {"label": "uncertain", "feedback": "Response received.", "hint": ""}
		
	var label = String(result.get("label", "uncertain"))
	var feedback = String(result.get("feedback", ""))
	var hint = String(result.get("hint", ""))
	
	var caller_reply = String(result.get("caller_reply", ""))
	if _intake_stage >= 0:
		_silent_intake_tracking_from_llm(result, caller_reply != "")
	if caller_reply == "":
		caller_reply = _build_caller_chatbot_reply(user_text, label)
	
	if caller_reply != "":
		_append_transcript_line("Caller", caller_reply)
		
	var explanation = feedback
	if not hint.is_empty():
		explanation += "\n\nHint: " + hint
	_record_response_review(user_text, label, explanation, _active_call.get("options", []))
	_score_and_show_feedback(label, user_text, explanation)
	
	_is_waiting_for_llm = false
	if _typed_input:
		_typed_input.editable = true
		_typed_input.grab_focus()

func _on_typed_text_submitted(_new_text: String) -> void:
	_on_typed_submit_pressed()

func _handle_post_dispatch_chat(user_text: String) -> void:
	if _is_waiting_for_llm:
		return
	_is_waiting_for_llm = true
	if _typed_input:
		_typed_input.editable = false
		_typed_input.text = ""
	if _response_prompt_label:
		_response_prompt_label.text = "Caller is responding..."
		
	_append_transcript_line("Dispatcher", user_text)
	_score_professional_turn(user_text)

	var caller_reply = ""
	var label = "uncertain"
	var feedback = ""
	if _groq_http:
		var result = await _call_groq_evaluate_and_reply(user_text)
		if not result.is_empty():
			caller_reply = String(result.get("caller_reply", ""))
			label = String(result.get("label", "uncertain"))
			feedback = String(result.get("feedback", ""))
			
	if caller_reply == "":
		caller_reply = _build_enroute_caller_reply(user_text)
		
	if caller_reply != "":
		_append_transcript_line("Caller", caller_reply)
		
	_record_response_review(user_text, label, feedback, [])
		
	if _response_feedback_label:
		_response_feedback_label.text = "Good. Keep the caller safe and provide updates until units arrive."
	if _response_prompt_label:
		_response_prompt_label.text = "Units are en route. Continue pre-arrival instructions and gather updates."
		
	_is_waiting_for_llm = false
	if _typed_input:
		_typed_input.editable = true
		_typed_input.grab_focus()

func _build_enroute_caller_reply(user_text: String) -> String:
	# Fallback: keyword matching
	var msg = user_text.to_lower()
	if _text_has_any(msg, ["evacuate", "outside", "exit", "leave", "safe area"]):
		return "Understood. We're evacuating now and moving to a safer spot."
	if _text_has_any(msg, ["stay low", "smoke", "cover", "breathe"]):
		return "Okay, we're staying low and covering our nose and mouth."
	if _text_has_any(msg, ["weapons", "armed", "gun", "knife"]):
		return "No weapons seen right now."
	if _text_has_any(msg, ["how many", "who", "injured", "patient"]):
		return "There are two adults and one child here. One adult has minor burns."
	if _text_has_any(msg, ["unlock", "door", "light", "pets", "gate"]):
		return "Copy, we'll unlock the gate and secure our dog inside."
	if _text_has_any(msg, ["stay on the line", "updates", "tell me"]):
		return "We'll stay on the line and keep giving updates."
	return "We're still waiting and following your instructions."
func _silent_intake_tracking_from_llm(result: Dictionary, _caller_reply_sent: bool = false) -> void:
	if _intake_stage < 0: return
	
	var is_ready = result.get("ready_for_dispatch", false) == true
	var caller_text = String(result.get("caller_reply", "")).to_lower()
	var actual_loc = String(_active_call.get("location", "")).to_lower()
	
	if not is_ready and actual_loc != "":
		var loc_words = actual_loc.split(" ", false)
		for w in loc_words:
			var word = w.strip_edges().replace(",", "").replace(".", "").to_lower()
			if word.length() > 3 and caller_text.contains(word):
				# Heuristic: One significant word from the address was mentioned.
				is_ready = true
				break
		
	if is_ready:
		_intake_location_asked = true
		_intake_emergency_asked = true
		_set_intake_state(true, true)
		
		_intake_stage = -1
		_dispatch_phase_unlocked = true
		_set_vehicle_buttons_enabled(true)
		if _vehicle_grid:
			_vehicle_grid.visible = true
		if _assignment_label:
			_assignment_label.text = "Dispatch unlocked! AI detected you have sufficient details."
		if _typed_row:
			_typed_row.visible = true
		if _typed_input:
			_typed_input.placeholder_text = "Give safety guidance (evacuate, hazards, updates) while units travel..."
			_typed_input.grab_focus()
		if _response_prompt_label:
			_response_prompt_label.text = "Units are en route. Continue pre-arrival instructions and gather updates."
		_begin_call_transcript_after_intake(result.has("caller_reply") and result.get("caller_reply") != "")

func _text_has_any(text: String, needles: Array) -> bool:
	for raw in needles:
		var needle = String(raw).to_lower()
		if needle != "" and text.find(needle) >= 0:
			return true
	return false

func _score_professional_turn(user_text: String) -> void:
	if _selected_mode_id == "easy_multiple_choice":
		return
	var msg = user_text.to_lower()
	var earned: Array[String] = []

	if _text_has_any(msg, ["911", "address", "location", "where"]):
		if _award_professional_checkpoint("opening_location", "Opening + Location", 8):
			earned.append("Opening + Location")
	if _text_has_any(msg, ["apartment", "unit", "landmark", "gate", "code", "near"]):
		if _award_professional_checkpoint("location_verify", "Location Verification", 4):
			earned.append("Location Verification")
	if _text_has_any(msg, ["callback", "phone", "contact", "number"]):
		if _award_professional_checkpoint("callback_number", "Callback Number", 4):
			earned.append("Callback Number")
	if _text_has_any(msg, ["what happened", "happened", "emergency", "incident"]):
		if _award_professional_checkpoint("what_happened", "4W: What", 5):
			earned.append("4W: What")
	if _text_has_any(msg, ["who", "how many", "inside", "suspect", "patient"]):
		if _award_professional_checkpoint("who_involved", "4W: Who", 5):
			earned.append("4W: Who")
	if _text_has_any(msg, ["when", "how long", "minutes ago", "just now"]):
		if _award_professional_checkpoint("when_happened", "4W: When", 5):
			earned.append("4W: When")
	if _text_has_any(msg, ["weapon", "armed", "gun", "knife"]):
		if _award_professional_checkpoint("weapons", "Weapons Check", 6):
			earned.append("Weapons Check")
	if _text_has_any(msg, ["cpr", "heimlich", "stay low", "stay quiet", "evacuate", "do not", "keep away", "leave now"]):
		if _award_professional_checkpoint("pre_arrival", "Pre-Arrival Instruction", 7):
			earned.append("Pre-Arrival Instruction")
	if _text_has_any(msg, ["unlock", "porch light", "pets", "stay on the line", "update me", "if anything changes"]):
		if _award_professional_checkpoint("scene_safety", "Post-Dispatch Safety", 6):
			earned.append("Post-Dispatch Safety")

	if not earned.is_empty() and _response_feedback_label:
		_response_feedback_label.text = "Response logged. Continue gathering critical details and safety updates."

func _award_professional_checkpoint(id: String, label: String, points: int) -> bool:
	if _professional_scored_tags.has(id):
		return false
	_professional_scored_tags[id] = true
	var awarded_points = 15
	_call_score += awarded_points
	if not _current_call_review.is_empty():
		_current_call_review["checks_total"] = int(_current_call_review.get("checks_total", 0)) + 1
		_current_call_review["checks_correct"] = int(_current_call_review.get("checks_correct", 0)) + 1
		var hits: Array = _current_call_review.get("protocol_hits", [])
		hits.append("%s (+%d)" % [label, awarded_points])
		_current_call_review["protocol_hits"] = hits
	return true

func _build_caller_chatbot_reply(user_text: String, label: String) -> String:
	# Fallback: keyword matching
	var msg = user_text.to_lower()
	var incident_type = String(_active_call.get("type", "")).to_lower()
	var location = String(_active_call.get("location", "the location"))

	if _text_has_any(msg, ["location", "where", "address", "saan", "lugar", "pwesto"]):
		return "We're at %s, near the main road." % location
	if _text_has_any(msg, ["what happened", "happened", "emergency", "incident", "ano", "nangyari", "saklolo", "tulong"]):
		return "There is an emergency here. We need help right now."
	if _text_has_any(msg, ["what started", "cause", "start", "dahilan"]):
		if incident_type == "fire":
			return "I think it started in the kitchen area."
		return "It just happened so fast."
	if _text_has_any(msg, ["callback", "phone", "number", "numero", "kontak"]):
		return "You can call me back at this number."
	if _text_has_any(msg, ["evac", "outside", "exit", "labas", "alis"]):
		return "Okay, we're moving everyone outside to a safer area now."
	if _text_has_any(msg, ["stay calm", "breathe", "kalma", "hinga"]):
		return "Thank you, that helps. I'm trying to stay calm and follow your instructions."
	
	if label == "safe":
		return "Understood. We'll do that and wait for help."
	if label == "unsafe":
		return "I'm not sure if that's safe... is there another way?"
	return "Please stay on the line with us. What should we do next?"


func _call_groq_evaluate_and_reply(dispatcher_text: String) -> Dictionary:
	"""Call Groq API directly from GDScript to get evaluation and caller reply.
	Returns empty dictionary if request fails."""
	if _active_call.is_empty(): return {}
	
	var incident_type = String(_active_call.get("type", "fire"))
	var location = String(_active_call.get("location", "Unknown"))
	var severity = String(_active_call.get("severity", "medium"))
	var title = String(_active_call.get("title", "Emergency Incident"))
	
	var transcript_text = ""
	for t in _conversation_log.slice(-20):
		transcript_text += "  " + String(t.get("speaker", "")) + ": " + String(t.get("text", "")) + "\n"
		
	var scenario_backstory = ""
	if typeof(_active_call.get("transcript")) == TYPE_ARRAY:
		for t in _active_call["transcript"]:
			if typeof(t) == TYPE_DICTIONARY:
				var sp = String(t.get("speaker", "Caller"))
				var txt = String(t.get("text", ""))
				if "{location}" in txt:
					txt = txt.replace("{location}", location)
				scenario_backstory += "- " + sp + ": " + txt + "\n"
				
	var arrival_status = "HAVE ARRIVED ON SCENE" if _services_arrived else "Still traveling (NOT on scene yet)"
	var sys_prompt = """You are an AI orchestrator for a 911 simulator.

TRUE BACKSTORY / INITIAL SITUATION:
(This is the exact situation the caller is reporting. Do NOT invent new details outside of this scope unless directly asked a question by the dispatcher):
%s

SCENARIO METADATA:
- Type: %s
- Title: %s
- Location: %s
- Severity: %s
- Emergency Services Status: %s

CONVERSATION LOG:
%s

Task:
Evaluate if the dispatcher's instruction is "safe", "unsafe", or "uncertain" (e.g. asking an open question). Provide short feedback for the dispatcher.
Determine if BOTH the exact address/location AND the nature of the emergency are now known (either because the dispatcher asked or the caller volunteered them).
If BOTH are known, you MUST set "ready_for_dispatch" to true. Do not be overly strict; if the caller mentions a street name, landmark, or building, the address is gathered. 
IMPORTANT: A callback number is NOT strictly required to unlock dispatch. If you have the location and the emergency, unlock it immediately.

Then, generate the caller's next reply (1-3 sentences, emotionally appropriate). 
IMPORTANT: The caller must ALWAYS reply in English. Even if the SCENARIO METADATA or the dispatcher speaks in Tagalog/Filipino, you MUST translate the information and reply ONLY in English. Never use Tagalog in your "caller_reply".
IMPORTANT: Do not repeat word-for-word any lines provided in the TRUE BACKSTORY. Use those lines as factual context only. Generate natural, fresh dialogue based on those facts.
IMPORTANT: Never use "Sir" or "Ma'am" or any gendered pronouns to address the operator. Use gender-neutral phrasing.
IMPORTANT: The caller MUST directly answer any questions the dispatcher asks. If the dispatcher asks for the address or location, YOU MUST PROVIDE IT, even if you already mentioned it earlier in the call. Never refuse to give the location if asked.
IMPORTANT: Do not ignore valid questions to panic. If a new detail is asked (e.g. 'what did he steal?' or 'what kind of weapon?'), you MUST invent a plausible short detail if it is not in the backstory, and directly answer the question naturally.
CRITICAL RULE 1: If the dispatcher directly asks for the address or location (or uses words like 'lokasyon', 'saan kayo', 'address'), YOU MUST reply by giving the exact "Location" listed in the SCENARIO METADATA. 
CRITICAL RULE 2: Do NOT penalize the dispatcher for asking what the emergency is at the start of the call. If the dispatcher says "911, what's your emergency", "What is your emergency?", "What happened?", or similar, this is ALWAYS "safe" and correct.
CRITICAL RULE 3: Giving emergency pre-arrival instructions (like first aid, CPR, applying pressure to wounds, restraining a suspect cooperatively, or safety/evacuation orders) while responders are on the way is HIGHLY ENCOURAGED and MUST be evaluated as "safe". Never penalize a dispatcher for offering medical or tactical advice before responders arrive.
CRITICAL RULE 4: If the caller's own message already contains a specific location (like a street name, building, or landmark) AND a clear nature of emergency, you MUST set "ready_for_dispatch" to true immediately, as the dispatcher now has the necessary info to send help.

Output valid JSON ONLY:
{
  "label": "safe",
  "feedback": "...",
  "ready_for_dispatch": true,
  "caller_reply": "..."
}""" % [scenario_backstory, incident_type, title, location, severity, arrival_status, transcript_text]

	var payload = {
		"model": "llama-3.1-8b-instant",
		"messages": [
			{"role": "system", "content": sys_prompt},
			{"role": "user", "content": "The dispatcher just said: \"%s\"\nPlease follow the task instructions and output JSON ONLY. (Note: The dispatcher's current message is already in the conversation log provided above as the last entry)." % dispatcher_text}
		],
		"response_format": {"type": "json_object"},
		"temperature": 0.5,
		"max_tokens": 150
	}
	
	var headers = [
		"Authorization: Bearer " + GROQ_API_KEY, 
		"Content-Type: application/json",
		"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
	]
	var err = _groq_http.request("https://api.groq.com/openai/v1/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK: return {}
	
	var result = await _groq_http.request_completed
	if result[1] != 200:
		return {}
		
	var body = JSON.parse_string(result[3].get_string_from_utf8())
	if typeof(body) != TYPE_DICTIONARY or not body.has("choices"): return {}
	
	var content = body["choices"][0]["message"]["content"]
	var data = JSON.parse_string(content)
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}

func _score_and_show_feedback(label: String, chosen_text: String, explanation: String) -> void:
	_clear_choice_buttons()
	if _typed_row and _selected_mode_id == "easy_multiple_choice":
		_typed_row.visible = false
	_response_quality = label

	# Score the response
	match label:
		"safe":
			_call_score += 20
		"uncertain":
			_call_score += 5
		"unsafe":
			_call_score -= 10

	if _response_feedback_label:
		_response_feedback_label.text = explanation

	if _feedback_dialog:
		if _selected_mode_id != "easy_multiple_choice":
			_on_feedback_popup_closed()
			return
		var title_text = ""
		if label == "safe":
			title_text = "✅ Excellent Choice! (+20 pts)"
		elif label == "unsafe":
			title_text = "⚠️ Dangerous Choice! (-10 pts)"
		else:
			title_text = "✅ Okay Choice (+5 pts)"
			
		_feedback_popup_context = "response"
		_feedback_dialog.dialog_text = "%s\n\nYour Action: %s\n\nWhy:\n%s" % [title_text, chosen_text, explanation]
		_feedback_dialog.popup_centered()
	else:
		_on_feedback_popup_closed()

func _on_feedback_popup_closed() -> void:
	if _feedback_popup_context != "response":
		_feedback_popup_context = ""
		return
	_feedback_popup_context = ""

	if _response_feedback_label:
		if _selected_mode_id == "easy_multiple_choice":
			if _has_dispatched_vehicle:
				_response_feedback_label.text = "Action recorded. Keep caller calm while units travel to the scene."
			else:
				_response_feedback_label.text = "Action recorded. Dispatch required vehicles now."
	_start_dispatch_phase()
	_update_end_call_button_state()

func _append_transcript_line(speaker: String, text: String) -> void:
	# Track conversation for LLM context
	_conversation_log.append({"speaker": speaker, "text": text})
	if _transcript_label:
		var color := "#c5d1e8"  # default light blue
		if speaker == "911":
			color = "#7ab8e6"  # blue for dispatcher
		elif speaker == "Caller":
			color = "#e8c97a"  # warm gold for caller
		elif speaker == "System":
			color = "#8a9ab5"  # muted for system
		elif speaker == "Dispatcher":
			color = "#7ae89a"  # green for player
		_transcript_label.append_text("[color=%s]- %s[/color]\n" % [color, text])

func _clear_choice_buttons() -> void:
	if _hint_button:
		_hint_button.visible = false
	if _hint_display_label:
		_hint_display_label.visible = false
	if _choices_box == null:
		return
	for child in _choices_box.get_children():
		child.queue_free()

func _on_hint_button_pressed() -> void:
	if _active_call.is_empty():
		return
	
	_hint_button.visible = false
	var options = _active_call.get("options", [])
	var hint_text = "Proceed with caution."
	
	for opt in options:
		if opt.get("label", "") == "safe":
			hint_text = String(opt.get("explanation", "Choose the option that prioritizes life safety."))
			break
			
	if _hint_display_label:
		_hint_display_label.visible = true
		_hint_display_label.text = "[color=#f39c12]Hint:[/color] " + hint_text

func _set_vehicle_buttons_enabled(enabled: bool) -> void:
	for key in _vehicle_buttons.keys():
		var btn: Button = _vehicle_buttons[key]
		if btn:
			btn.disabled = not enabled

func _educational_vehicle_detail(vehicle_id: String, incident_type: String) -> String:
	match vehicle_id:
		"fire_truck":
			if incident_type == "fire":
				return "Fire trucks carry high-pressure hoses, breathing equipment, ladders, and tools to suppress flames and evacuate people safely."
			return "Fire crews specialize in scene stabilization and hazard control during dangerous incidents."
		"ambulance":
			return "Ambulance teams provide life-saving medical care, bleeding control, oxygen support, and fast transport to the hospital."
		"police":
			return "Police officers secure the area, manage suspects, protect bystanders, and keep responders safe while the incident is handled."
		_:
			return "This unit can respond, but matching the exact emergency type improves outcomes and response speed."

func _mismatch_vehicle_detail(selected_vehicle: String, recommended_list: Array[String], incident_type: String) -> String:
	var rec_details = PackedStringArray()
	for r in recommended_list:
		rec_details.append(_vehicle_name(r) + " should be prioritized because " + _educational_vehicle_detail(r, incident_type))
	var recommended_detail = "\n- ".join(rec_details)
	return "%s will still respond, but with reduced efficiency.\n\nBest practice:\n- %s" % [_vehicle_name(selected_vehicle), recommended_detail]

func _schedule_background_emergency_if_needed() -> void:
	if _next_call_timer == null:
		return
	if _remaining_shift_call_slots() <= 0:
		return
	if not _queued_calls.is_empty():
		return
	if _queued_calls.size() >= max_waiting_calls:
		return
	if not _next_call_timer.is_stopped():
		return
	var base_delay = _dispatch_rng.randf_range(dispatch_between_calls_min_s, dispatch_between_calls_max_s)
	var followup_delay = max(2.0, (base_delay * 0.55) / clamp(_day_difficulty_scale, 1.0, 1.75))
	_next_call_timer.start(followup_delay)

func _can_take_next_queued_call_now() -> bool:
	return _call_active and _has_dispatched_vehicle and _player_responded_this_round and not _queued_calls.is_empty()

func _update_end_call_button_state() -> void:
	if _end_call_button == null:
		return
	if _services_arrived:
		_end_call_button.text = "End Call"
		_end_call_button.disabled = false
		return
	if _can_take_next_queued_call_now():
		_end_call_button.text = "Take Next Queued Call (%d)" % _queued_calls.size()
		_end_call_button.disabled = false
		return
	_end_call_button.text = "End Call"
	_end_call_button.disabled = true

func _on_vehicle_button_pressed(vehicle_id: String) -> void:
	if _has_dispatched_vehicle and _selected_mode_id == "easy_multiple_choice":
		return
	if _active_call.is_empty() or not _call_active:
		return
	if not _dispatch_phase_unlocked:
		if _response_feedback_label:
			_response_feedback_label.text = "Finish the caller conversation first. Dispatch unlocks after response review."
		return

	_has_dispatched_vehicle = true
	if _selected_mode_id == "easy_multiple_choice":
		_dispatch_phase_unlocked = false
	var btn = _vehicle_buttons.get(vehicle_id)
	if btn:
		btn.disabled = true

	var selected_vehicle = _canonical_vehicle_id(vehicle_id)
	var recommended_raw = _active_call.get("recommended_vehicle", "")
	var recommended_list: Array[String] = []
	if typeof(recommended_raw) == TYPE_ARRAY:
		for r in recommended_raw:
			if String(r) != "": recommended_list.append(_canonical_vehicle_id(String(r)))
	else:
		var parts = String(recommended_raw).split(",")
		for p in parts:
			var s = p.strip_edges()
			if s != "": recommended_list.append(_canonical_vehicle_id(s))
			
	var rec_names = PackedStringArray()
	for r in recommended_list:
		rec_names.append(_vehicle_name(r))
	var recommended_str = ", ".join(rec_names)

	var selected_name = _vehicle_name(selected_vehicle)
	
	if _transcript_label:
		_transcript_label.append_text("[color=#7ae89a]- Dispatching %s to %s.[/color]\n" % [selected_name, String(_active_call.get("location", "scene"))])

	var correct_dispatch = recommended_list.has(selected_vehicle)
	var dispatch_title = ""
	var dispatch_explanation = ""
	var incident_type = String(_active_call.get("type", "fire"))
	if correct_dispatch:
		_call_score += 15
		dispatch_title = "✅ Great Dispatch! (+15 pts)"
		dispatch_explanation = "%s is a good unit for this emergency.\n\n%s" % [selected_name, _educational_vehicle_detail(selected_vehicle, incident_type)]
		if _assignment_label:
			_assignment_label.text = "Unit sent! (+15 pts) You can dispatch more units if needed."
	else:
		dispatch_title = "⚠️ Dispatch Sent"
		dispatch_explanation = "Recommended unit(s): %s\n%s" % [recommended_str, _mismatch_vehicle_detail(selected_vehicle, recommended_list, incident_type)]
		if _assignment_label:
			_assignment_label.text = "Unit sent. Recommended was %s." % recommended_str

	if _feedback_dialog:
		if _selected_mode_id == "easy_multiple_choice":
			_feedback_popup_context = "vehicle_dispatch"
			_feedback_dialog.dialog_text = "%s\n\nYour Dispatch: %s\n\nWhy:\n%s" % [dispatch_title, selected_name, dispatch_explanation]
			_feedback_dialog.popup_centered(Vector2i(760, 320))
	_record_vehicle_review(selected_vehicle, recommended_str, correct_dispatch, dispatch_explanation)

	if _selected_mode_id == "easy_multiple_choice":
		_set_vehicle_buttons_enabled(false)
	if _vehicle_grid:
		_vehicle_grid.visible = true
	_services_arrived = false

	var severity = String(_active_call.get("severity", "medium"))
	var base_travel_s = _travel_time_for(severity, correct_dispatch)
	var speed_mult = max(1.0, responder_speed_multiplier)
	var travel_s = max(0.8, base_travel_s / speed_mult)
	_pending_resolution_s = _resolution_time_for(severity, correct_dispatch, _response_quality)
	_follow_dispatched_vehicle = _selected_mode_id == "easy_multiple_choice"
	_follow_vehicle_pos_valid = false
	if _timeline_label:
		_timeline_label.text = "Unit en route. ETA %.0fs" % travel_s
	if _response_prompt_label and _player_responded_this_round:
		_response_prompt_label.text = "Keep caller calm while units travel to the scene."
	if _selected_mode_id != "easy_multiple_choice":
		if _typed_row:
			_typed_row.visible = true
		if _typed_input:
			_typed_input.placeholder_text = "Continue talking to caller while units are en route..."
			_typed_input.grab_focus()
	
	# Professional mode keeps the live call dialog open while units travel.
	if _selected_mode_id == "easy_multiple_choice":
		_minimize_call_during_dispatch()
	
	if _patrol_manager and _patrol_manager.has_method("dispatch_response_unit"):
		var requested_travel_s = travel_s
		if _selected_mode_id != "easy_multiple_choice":
			requested_travel_s = 0.0
		_patrol_manager.call("dispatch_response_unit", selected_vehicle, _active_call_world_position, requested_travel_s)
	if _arrival_timer:
		# Fallback only: primary arrival is now event-driven from actual responder movement.
		_arrival_timer.start(travel_s + 0.6)

	if _is_interactive_tutorial and _tutorial_label:
		_tutorial_label.text = "Unit dispatched! Just wait for them to arrive."
		_hide_coach_pointer()

	# Realism: new emergencies can still be reported while this call is resolving.
	_schedule_background_emergency_if_needed()
	_update_end_call_button_state()

func _on_arrival_timeout() -> void:
	# Fallback path in case a responder signal is missed.
	if not _call_active or not _has_dispatched_vehicle:
		return
	_on_response_arrived("", _active_call_world_position)

func _on_response_arrived(_vehicle_id: String, _world_position: Vector2) -> void:
	if _active_call.is_empty() or not _call_active:
		return
	if not _has_dispatched_vehicle:
		return
	if _services_arrived:
		return
	_follow_dispatched_vehicle = false
	_follow_vehicle_pos_valid = false
	_services_arrived = true
	if _arrival_timer:
		_arrival_timer.stop()
	
	# Restore call window only for easy mode where we minimized it.
	if _selected_mode_id == "easy_multiple_choice":
		_restore_call_after_dispatch()
	else:
		if _resolution_timer:
			_resolution_timer.start(_pending_resolution_s)
	
	_update_end_call_button_state()
	if _timeline_label:
		_timeline_label.text = "Emergency services arrived on scene. Call will auto-complete when incident is resolved."
	_append_transcript_line("System", "Units have arrived on scene. Operation in progress...")
	if _response_prompt_label and _selected_mode_id != "easy_multiple_choice":
		_response_prompt_label.text = "Units are handling the scene. Keep the caller safe."
	if _is_interactive_tutorial and _tutorial_label:
		_tutorial_label.text = "Units arrived. Great job, moving to the next call."
	
	# Easy mode can auto-close instantly. Certified Mode auto-closes via resolution timer.
	if _selected_mode_id == "easy_multiple_choice":
		_complete_current_call(true, false, "Units arrived and secured the scene. Call closed.")

func _on_resolution_timeout() -> void:
	if _active_call.is_empty():
		return
	if _timeline_label:
		_timeline_label.text = "On-site response completed. Call ending in 2 seconds..."
	_append_transcript_line("System", "Incident operation completed.")

	var auto_end_timer = Timer.new()
	auto_end_timer.wait_time = 2.0
	auto_end_timer.one_shot = true
	auto_end_timer.timeout.connect(Callable(self, "_on_end_call_pressed"))
	auto_end_timer.timeout.connect(auto_end_timer.queue_free)
	add_child(auto_end_timer)
	auto_end_timer.start()

func _complete_current_call(include_speed_bonus: bool, show_completion_popup: bool, closure_line: String) -> void:
	_append_transcript_line("Dispatcher", closure_line)

	var elapsed = (Time.get_ticks_msec() / 1000.0) - _call_start_time
	var speed_bonus = 0
	if include_speed_bonus:
		var day_penalty = float(max(0, _current_day - 1))
		var fast_threshold = max(16.0, 30.0 - (day_penalty * 1.5))
		var medium_threshold = max(fast_threshold + 12.0, 60.0 - (day_penalty * 2.5))
		if elapsed < fast_threshold:
			speed_bonus = 10
		elif elapsed < medium_threshold:
			speed_bonus = 5

	_call_score += speed_bonus
	_call_score = max(_call_score, 0)
	_total_score += _call_score
	_calls_completed += 1
	var details_str = ""
	if not _current_call_review.is_empty():
		_current_call_review["score"] = _call_score
		_shift_call_reviews.append(_current_call_review.duplicate(true))
		if _selected_mode_id != "easy_multiple_choice":
			details_str = "\n\n--- Evaluation Details ---\n" + _build_shift_review_detail(_current_call_review)
		_current_call_review.clear()

	var speed_text = " (Speed bonus: +%d)" % speed_bonus if speed_bonus > 0 else ""
	_append_transcript_line("System", "Call Score: %d pts%s" % [_call_score, speed_text])
	_append_transcript_line("System", "Total Score: %d pts (%d calls completed)" % [_total_score, _calls_completed])

	if _score_label:
		_score_label.text = "Score: %d" % _total_score
	_update_shift_ui()
	_save_shift_state_to_game_state()
	
	if _shift_remaining_s <= 0 and _total_score >= shift_min_score and not _shift_ready_announced:
		_shift_ready_announced = true
		_show_kid_message("Shift Complete!", "You reached %d points. End shift is now unlocked." % shift_min_score)

	if _arrival_timer:
		_arrival_timer.stop()
	if _resolution_timer:
		_resolution_timer.stop()
	if _transcript_timer:
		_transcript_timer.stop()

	_active_call.clear()
	_pending_call.clear()
	_response_quality = "uncertain"
	_awaiting_dispatch = false
	_has_dispatched_vehicle = false
	_services_arrived = false
	_follow_dispatched_vehicle = false
	_follow_vehicle_pos_valid = false
	_call_active = false
	_caller_lines.clear()
	_caller_line_index = 0
	_interactive_phase = 0
	_player_responded_this_round = false
	_intake_stage = -1
	_set_intake_state(false, false)

	if _is_interactive_tutorial:
		_is_interactive_tutorial = false
		_hide_coach_pointer()
		if _tutorial_panel:
			_tutorial_panel.queue_free()
			_tutorial_panel = null

		var state = get_node_or_null("/root/GameState")
		if state:
			state.call("set_first_live_call_done")
	_interactive_phase = 0
	_player_responded_this_round = false

	if _dim_overlay:
		_dim_overlay.visible = false
	_set_vehicle_buttons_enabled(false)
	if _end_call_button:
		_end_call_button.disabled = true
		_end_call_button.text = "End Call"
	if _answer_button:
		_answer_button.disabled = true
		_answer_button.text = "Answer Call"
	_clear_choice_buttons()
	if _typed_row:
		_typed_row.visible = false
	if _typed_input:
		_typed_input.text = ""
	if _response_prompt_label:
		_response_prompt_label.text = ""
	if _response_feedback_label:
		_response_feedback_label.text = ""
	if _assignment_label:
		_assignment_label.text = ""
	if _timeline_label:
		_timeline_label.text = ""
	if _dispatch_panel:
		_dispatch_panel.visible = false
	if _vehicle_grid:
		_vehicle_grid.visible = false
	if _minimized_call_button:
		_minimized_call_button.visible = false

	if _hint_label:
		_hint_label.text = "Call ended. Score: %d | Total: %d. Waiting for next alert." % [_call_score, _total_score]

	if _calls_completed >= _max_calls_per_shift():
		if _next_call_timer:
			_next_call_timer.stop()
		_queued_calls.clear()
		_pending_call.clear()
		_update_shift_ui()
		if _total_score < shift_min_score:
			_pending_day_restart = false
			if _hint_label:
				_hint_label.text = "Shift failed: minimum score not reached. Day %d will restart." % _current_day
			_show_shift_review(
				"Shift Failed",
				"You completed %d calls and scored %d points. Minimum required score is %d. Day %d will restart after you close this review." % [_calls_completed, _total_score, shift_min_score, _current_day],
				"restart_day"
			)
			return
		if _hint_label:
			_hint_label.text = "Day complete! Requirements met. Tap Proceed to Day %d." % (_current_day + 1)
		_show_shift_review(
			"Day Complete",
			"Great work! You met the shift requirements. Tap 'Proceed to Day %d' in the status box after reviewing your calls." % (_current_day + 1),
			""
		)
		return

	if show_completion_popup:
		var popup_msg = "Nice work! You helped the caller stay safe.\nCall score: %d\nTotal score: %d%s" % [_call_score, _total_score, details_str]
		_show_kid_message("Mission Complete!", popup_msg)

	if not _queued_calls.is_empty():
		if _next_call_timer:
			_next_call_timer.stop()
		_pending_call = _queued_calls.pop_front().duplicate(true)
		_spawn_call_marker()
		if _hint_label:
			_hint_label.text = "A queued emergency is ready now. Remaining waiting calls: %d" % _queued_calls.size()
		return

	var base_delay = _dispatch_rng.randf_range(dispatch_between_calls_min_s, dispatch_between_calls_max_s)
	var next_delay = max(2.0, base_delay / clamp(_day_difficulty_scale, 1.0, 1.75))
	_schedule_next_call(next_delay)

func _on_end_call_pressed() -> void:
	if _active_call.is_empty():
		return
	if not _services_arrived:
		if _can_take_next_queued_call_now():
			_complete_current_call(false, false, "Call handed off to responders. Switching to the next queued emergency.")
			return
		if _response_feedback_label:
			_response_feedback_label.text = "You can end now only after arrival, or take the next queued call once conversation + dispatch are done."
		return

	_complete_current_call(true, true, "Call closed. Stay safe.")

func _on_close_call_panel() -> void:
	# Hide the panel to minimize it and re-enable map interactions.
	if _active_call.is_empty():
		if _dispatch_panel:
			_dispatch_panel.visible = false
		if _dim_overlay:
			_dim_overlay.visible = false
		if _minimized_call_button:
			_minimized_call_button.visible = false
		_hide_coach_pointer()
		_call_active = false
		return

	if _dim_overlay:
		_dim_overlay.visible = false
	if _dispatch_panel:
		_dispatch_panel.visible = false
	_call_active = false
	if _minimized_call_button:
		_minimized_call_button.visible = true
		var severity = String(_active_call.get("severity", "medium")).to_upper()
		var call_type = String(_active_call.get("type", "Emergency")).to_upper()
		_minimized_call_button.text = "Return to Call [%s: %s]" % [severity, call_type]
	if _hint_label:
		_hint_label.text = "Call minimized. Use 'Return to Call' in the status box."
	_hide_coach_pointer()

func _pick_random_road_position() -> Vector2:
	if _route_points_px.is_empty():
		return Vector2(float(_img_w) * 0.5, float(_img_h) * 0.5)
	var idx = _dispatch_rng.randi_range(0, _route_points_px.size() - 1)
	var base: Vector2 = _route_points_px[idx]
	var jitter = Vector2(_dispatch_rng.randf_range(-16.0, 16.0), _dispatch_rng.randf_range(-16.0, 16.0))
	var pos = base + jitter
	pos.x = clamp(pos.x, 24.0, float(_img_w) - 24.0)
	pos.y = clamp(pos.y, 24.0, float(_img_h) - 24.0)
	return pos

func _icon_for_call_type(call_type: String) -> Texture2D:
	match call_type:
		"fire":
			return _load_icon("res://assets/ui/icons/fire_truck.svg")
		"police":
			return _load_icon("res://assets/ui/icons/police.svg")
		"criminal":
			return _load_icon("res://assets/ui/icons/police.svg")
		_:
			return _load_icon("res://assets/ui/icons/ambulance.svg")

func _travel_time_for(_severity: String, correct_vehicle: bool) -> float:
	var state = get_node_or_null("/root/GameState")
	var difficulty = state.call("get_certified_difficulty") if state != null else "easy"
	
	if _selected_mode_id != "certified_nlp_dispatch":
		difficulty = "easy"
		
	var base = 10.0
	match difficulty:
		"easy":
			base = randf_range(10.0, 15.0)
		"medium":
			base = randf_range(30.0, 45.0)
		"hard":
			base = randf_range(60.0, 90.0)
			
	if not correct_vehicle:
		base += 15.0
	return base

func _resolution_time_for(severity: String, correct_vehicle: bool, response_quality: String) -> float:
	var base = 10.0
	match severity:
		"low":
			base = 8.0
		"medium":
			base = 14.0
		"high":
			base = 20.0
	if not correct_vehicle:
		base += 6.0
	if response_quality == "unsafe":
		base += 6.0
	elif response_quality == "safe":
		base = max(6.0, base - 2.0)
	return base

func _vehicle_name(vehicle_id: String) -> String:
	match _canonical_vehicle_id(vehicle_id):
		"fire_truck":
			return "Fire Truck"
		"ambulance":
			return "Ambulance"
		"police":
			return "Police Unit"
		_:
			return "Response Unit"

func _canonical_vehicle_id(vehicle_id: String) -> String:
	var key = vehicle_id.to_lower().strip_edges()
	match key:
		"police_mobile", "police_car", "patrol_car", "police_unit":
			return "police"
		"firetruck", "fire truck":
			return "fire_truck"
		"ems", "emergency_unit", "emergency":
			return "ambulance"
		_:
			return key

func _save_shift_state_to_game_state() -> void:
	var state = get_node_or_null("/root/GameState")
	if state and state.has_method("save_shift_progress"):
		var shift_data = {
			"total_score": _total_score,
			"calls_completed": _calls_completed,
			"shift_call_reviews": _shift_call_reviews,
			"shift_remaining_s": _shift_remaining_s
		}
		state.call("save_shift_progress", shift_data)
		
		
