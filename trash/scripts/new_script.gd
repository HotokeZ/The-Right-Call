extends Node

@onready var npc_label: Label = $Label2
@onready var input_box = null
@onready var chat: RichTextLabel = get_node_or_null("RichTextLabel")

const KEY_ENTER := 16777221
const KEY_KP_ENTER := 16777222

var scenario: String = "grease_fire"
var original_prompt: String = "NPC: The pan is on fire!"

func _ready() -> void:
	if npc_label:
		npc_label.text = original_prompt
	# Find a sensible input control: prefer LineEdit (single-line), fall back to TextEdit
	if not input_box:
		input_box = get_node_or_null("LineEdit")
		if not input_box:
			input_box = get_node_or_null("TextEdit")
		# As a last resort, search children for the first LineEdit/TextEdit
		if not input_box:
			for c in get_children():
				if c is LineEdit or c is TextEdit:
					input_box = c
					break
	if input_box:
		# If the input control is a LineEdit, use its `text_entered` signal (single-line input).
		# Otherwise fall back to TextEdit's `gui_input` handling.
		if input_box is LineEdit:
			# LineEdit signal name differs between Godot versions: try common names
			if input_box.has_signal("text_entered") and not input_box.is_connected("text_entered", Callable(self, "_on_lineedit_text_entered")):
				input_box.connect("text_entered", Callable(self, "_on_lineedit_text_entered"))
			elif input_box.has_signal("text_submitted") and not input_box.is_connected("text_submitted", Callable(self, "_on_lineedit_text_entered")):
				input_box.connect("text_submitted", Callable(self, "_on_lineedit_text_entered"))
			else:
				print("Warning: LineEdit has no known submit signal (text_entered/text_submitted)")
		else:
			# assume TextEdit-like
			if not input_box.is_connected("gui_input", Callable(self, "_on_textedit_gui_input")):
				input_box.connect("gui_input", Callable(self, "_on_textedit_gui_input"))
		# give focus to the input box so the player can type immediately
		input_box.grab_focus()
	if chat:
		chat.bbcode_enabled = true
		chat.clear()
		# Use helper to append so we support multiple Godot versions
		append_chat_line("[b]%s[/b]\n" % original_prompt)

func _process(_delta: float) -> void:
	# Sending is handled by TextEdit gui_input to avoid triggering on other mapped
	# actions like Space (which can be bound to ui_accept). Leave _process empty.
	pass


func _send_input() -> void:
	if not input_box:
		return
	# Read text from the input control (LineEdit vs TextEdit compatibility)
	var raw_text: String = ""
	if input_box is LineEdit:
		raw_text = str(input_box.text).strip_edges()
	else:
		# TextEdit exposes get_text() on some versions
		if input_box.has_method("get_text"):
			raw_text = str(input_box.get_text()).strip_edges()
		else:
			raw_text = str(input_box.text).strip_edges()

	# Sanitize input: allow letters, digits, spaces, apostrophes and hyphens
	var allowed_chars: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 '-"
	var cleaned: String = ""
	for ch in raw_text:
		if allowed_chars.find(ch) != -1:
			cleaned += ch
	cleaned = cleaned.strip_edges()
	if cleaned == "":
		return
	var text: String = cleaned
	# Add player's line to chat (if present)
	if chat:
		append_chat_line("[b]You:[/b] %s\n" % text)

	# Show sending activity in the chat
	if chat:
		append_chat_line("[i]Sending...[/i]\n")

	# Build arguments for the CLI wrapper
	var args: Array = ["backend/cli.py", "--scenario", scenario, text]
	var out: Array = []

	# OS.execute signature expects: (exe, args, output_array, blocking)
	var exit_code: int = OS.execute("python", args, out, true)

	# exit_code and output handled below; omit raw debug printing in console
	if exit_code != 0:
		var err_msg := "NPC: Error running classifier (exit %d)" % exit_code
		npc_label.text = err_msg
		if chat:
			append_chat_line("[color=red]%s[/color]\n" % err_msg)
			append_chat_line("[color=red]Output:[/color] %s\n" % str(out))
		return

	var json_str: String = ""
	for line in out:
		json_str += str(line) + "\n"
	json_str = json_str.strip_edges()
	var parse_result = JSON.parse_string(json_str)
	var res: Dictionary = {}
	# Handle different return shapes from JSON.parse_string across Godot versions.
	# Sometimes it returns the parsed value directly (a Dictionary with our keys),
	# other times it returns a wrapper Dictionary with keys like 'error' and 'result'.
	if parse_result is Dictionary:
		# If it's a wrapper with an 'error' key, check for parse errors first.
		if parse_result.has("error") and parse_result.get("error") != OK:
			npc_label.text = "NPC: Error parsing classifier output"
			if chat:
				append_chat_line("[color=red]Parse error: %s[/color]\n" % str(parse_result.get("error")))
			return
		# If the parsed object itself contains the label, use it directly.
		if parse_result.has("label"):
			res = parse_result
		# Otherwise, expect a 'result' key that contains the real object.
		elif parse_result.has("result"):
			var inner = parse_result.get("result")
			if inner is Dictionary:
				res = inner
			else:
				# Unexpected shape — try to coerce or treat as empty
				res = {}
		else:
			# No 'label' or 'result' — treat the whole dict as the result
			res = parse_result
	else:
		# Fallback: some Godot versions return an object with `error` and `result` attributes
		if parse_result.error != OK:
			npc_label.text = "NPC: Error parsing classifier output"
			return
		res = parse_result.result
	var label: String = res.get("label", "unknown")
	var reason: String = res.get("reason", "")
	var message: String = res.get("message", "")

	# Update Label or chat with the result and a human-friendly message
	if chat:
		var display_text: String
		if message != "":
			display_text = message
		else:
			display_text = "%s - %s" % [label, reason]

		var color_tag_start: String
		if label == "safe":
			color_tag_start = "[color=green]"
		elif label == "unsafe":
			color_tag_start = "[color=red]"
		else:
			color_tag_start = "[color=orange]"

		append_chat_line("%s[b]AI:[/b] %s[/color]\n" % [color_tag_start, display_text])
	else:
		npc_label.text = "%s\nResult: %s - %s\n" % [original_prompt, label, reason]
		# show matches if available
		var matches = res.get("matches", [])
		if matches.size() > 0:
			append_chat_line("[b]Points:[/b]\n")
			var i := 1
			for m in matches:
				var neg := " (negated)" if m.get("negated", false) else ""
				var inapp := " (inapplicable)" if not m.get("applicable", true) else ""
				append_chat_line("  %d. %s — %s%s%s\n" % [i, m.get("phrase"), m.get("type"), neg, inapp])
				i += 1
		var counts = res.get("counts", null)
		if counts:
			var counts_line := "[i]Counts:[/i] safe_unneg=%d, safe_neg=%d, unsafe_unneg=%d, unsafe_neg=%d\n" % [counts.get("safe_unneg",0), counts.get("safe_neg",0), counts.get("unsafe_unneg",0), counts.get("unsafe_neg",0)]
			append_chat_line(counts_line)
		if res.has("score"):
			append_chat_line("[i]Score:[/i] %s\n" % str(res.get("score")))
		# scroll to bottom
		chat.scroll_to_line(chat.get_line_count())


	# Clear the input control appropriately for LineEdit/TextEdit
	if input_box is LineEdit:
		input_box.text = ""
	elif input_box.has_method("set_text"):
		input_box.set_text("")
	else:
		input_box.text = ""


func _on_textedit_gui_input(event: InputEvent) -> void:
	# Handle Enter inside the TextEdit: send when user presses the accept action
	if event is InputEventKey:
		# Check for Enter / keypad Enter only, avoid triggering on Space
		if event.pressed and not event.echo:
			var sc := -1
			if event.has_method("get_scancode"):
				sc = event.get_scancode()
			elif event.has("scancode"):
				sc = event.scancode
			elif event.has_method("get_keycode"):
				sc = event.get_keycode()
			elif event.has("keycode"):
				sc = event.keycode
			if sc == KEY_ENTER or sc == KEY_KP_ENTER:
				# Prevent newline from being inserted and handle the event
				event.accept()
				if get_tree():
					get_tree().set_input_as_handled()
				_send_input()


func _on_lineedit_text_entered(_new_text: String) -> void:
	# LineEdit sends this when Enter is pressed. Delegate to _send_input.
	_send_input()


func append_chat_line(line: String) -> void:
	if not chat:
		return
	# Prefer append_bbcode when available (Godot 3.x)
	if chat.has_method("append_bbcode"):
		chat.append_bbcode(line)
		return
	# Try get_bbcode/set_bbcode
	if chat.has_method("get_bbcode") and chat.has_method("set_bbcode"):
		var cur: String = str(chat.get_bbcode())
		chat.set_bbcode(cur + line)
		return
	# Try get_text/set_text
	if chat.has_method("get_text") and chat.has_method("set_text"):
		var cur_t: String = str(chat.get_text())
		chat.set_text(cur_t + line)
		return
	# If none of the methods exist, silently ignore the append.
	# If none available, silently ignore
	return
