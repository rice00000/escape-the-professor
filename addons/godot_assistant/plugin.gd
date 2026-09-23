@tool
extends EditorPlugin

## A small, context-aware assistant dock. It follows explicit editor
## selections rather than recording the screen or silently tracking clicks.

const API_URL := "https://api.openai.com/v1/responses"
const MAX_FILE_CONTEXT := 12000
const MAX_HISTORY_ITEMS := 12
const TEXT_EXTENSIONS := ["gd", "gdshader", "tscn", "tres", "cfg", "json", "md", "txt"]

var _dock: VBoxContainer
var _context_label: Label
var _chat: RichTextLabel
var _input: LineEdit
var _send: Button
var _api_key: LineEdit
var _model: LineEdit
var _request: HTTPRequest
var _selection: EditorSelection
var _file_system_dock: Object
var _context := "Nothing selected."
var _history: Array[Dictionary] = []


func _enter_tree() -> void:
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	# Use an editor-native icon so a freshly cloned project can enable the
	# plugin before Godot has imported this add-on's optional SVG artwork.
	var dock_icon := EditorInterface.get_base_control().get_theme_icon("Help", "EditorIcons")
	set_dock_tab_icon(_dock, dock_icon)
	_selection = EditorInterface.get_selection()
	_selection.selection_changed.connect(_refresh_node_context)
	_file_system_dock = EditorInterface.get_file_system_dock()
	if _file_system_dock != null and _file_system_dock.has_signal("selection_changed"):
		_file_system_dock.connect("selection_changed", _refresh_asset_context)
	_refresh_node_context()


func _exit_tree() -> void:
	if _selection != null and _selection.selection_changed.is_connected(_refresh_node_context):
		_selection.selection_changed.disconnect(_refresh_node_context)
	if _file_system_dock != null and _file_system_dock.has_signal("selection_changed") \
			and _file_system_dock.is_connected("selection_changed", _refresh_asset_context):
		_file_system_dock.disconnect("selection_changed", _refresh_asset_context)
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Godot Assistant"
	_dock.custom_minimum_size = Vector2(330, 440)

	var title := Label.new()
	title.text = "◆ Godot Assistant"
	title.add_theme_font_size_override("font_size", 18)
	_dock.add_child(title)

	var privacy := Label.new()
	privacy.text = "Only the context shown below is sent when you ask."
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.modulate = Color(0.72, 0.78, 0.86)
	_dock.add_child(privacy)

	var context_panel := PanelContainer.new()
	_dock.add_child(context_panel)
	_context_label = Label.new()
	_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_label.custom_minimum_size.y = 54
	context_panel.add_child(_context_label)

	var quick := HBoxContainer.new()
	_dock.add_child(quick)
	var explain := Button.new()
	explain.text = "What is this?"
	explain.pressed.connect(func(): _ask("Explain the selected Godot item. What does it do, and when would I use it?"))
	quick.add_child(explain)
	var audio := Button.new()
	audio.text = "Add audio"
	audio.pressed.connect(_show_audio_help)
	quick.add_child(audio)

	_chat = RichTextLabel.new()
	_chat.bbcode_enabled = true
	_chat.fit_content = false
	_chat.scroll_following = true
	_chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat.custom_minimum_size.y = 190
	_dock.add_child(_chat)
	_append_message("Assistant", "Select a node or asset, then ask a question. The Add audio button works without an API key.")

	var credentials := VBoxContainer.new()
	_dock.add_child(credentials)
	_api_key = LineEdit.new()
	_api_key.secret = true
	_api_key.placeholder_text = "Session API key (or set OPENAI_API_KEY)"
	credentials.add_child(_api_key)
	_model = LineEdit.new()
	_model.placeholder_text = "Model"
	_model.text = OS.get_environment("OPENAI_MODEL") if OS.has_environment("OPENAI_MODEL") else "gpt-5"
	credentials.add_child(_model)

	var composer := HBoxContainer.new()
	_dock.add_child(composer)
	_input = LineEdit.new()
	_input.placeholder_text = "Ask about Godot or the selection…"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_text: String): _send_question())
	composer.add_child(_input)
	_send = Button.new()
	_send.text = "Send"
	_send.pressed.connect(_send_question)
	composer.add_child(_send)

	_request = HTTPRequest.new()
	_request.timeout = 60.0
	_request.request_completed.connect(_on_request_completed)
	_dock.add_child(_request)


func _refresh_node_context() -> void:
	var nodes := _selection.get_selected_nodes() if _selection != null else []
	if nodes.is_empty():
		_refresh_asset_context()
		return
	var node := nodes[0] as Node
	var lines := [
		"Selected node: %s" % node.name,
		"Type: %s" % node.get_class(),
		"Scene path: %s" % str(node.get_path()),
	]
	var script := node.get_script() as Script
	if script != null:
		lines.append("Script: %s" % script.resource_path)
		if script.resource_path.ends_with(".gd"):
			lines.append("\nSelected script preview:\n" + script.source_code.left(MAX_FILE_CONTEXT))
	_set_context("\n".join(lines))


func _refresh_asset_context() -> void:
	var paths := EditorInterface.get_selected_paths()
	if paths.is_empty():
		_set_context("Nothing selected. Click a node in Scene or a file in FileSystem.")
		return
	var path: String = paths[0]
	var extension := path.get_extension().to_lower()
	var lines := ["Selected asset: %s" % path, "File type: .%s" % extension]
	if extension in TEXT_EXTENSIONS:
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			lines.append("\nFile preview:\n" + file.get_as_text().left(MAX_FILE_CONTEXT))
	_set_context("\n".join(lines))


func _set_context(value: String) -> void:
	_context = value
	var summary := value.get_slice("\n", 0)
	if value.contains("\n"):
		summary += "\n" + value.get_slice("\n", 1)
	_context_label.text = summary
	_context_label.tooltip_text = value


func _send_question() -> void:
	var question := _input.text.strip_edges()
	if question.is_empty():
		return
	_input.clear()
	_ask(question)


func _ask(question: String) -> void:
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_append_message("Assistant", "Please wait for the current answer.")
		return
	var key := _api_key.text.strip_edges()
	if key.is_empty() and OS.has_environment("OPENAI_API_KEY"):
		key = OS.get_environment("OPENAI_API_KEY")
	if key.is_empty():
		_append_message("Assistant", "Add an API key in the password field for this editor session, or launch Godot with OPENAI_API_KEY set. The key is not saved in the project.")
		return

	_append_message("You", question)
	var contextual_question := "Current Godot editor context:\n%s\n\nUser question:\n%s" % [_context, question]
	_history.append({"role": "user", "content": contextual_question})
	while _history.size() > MAX_HISTORY_ITEMS:
		_history.pop_front()
	var payload := {
		"model": _model.text.strip_edges() if not _model.text.strip_edges().is_empty() else "gpt-5",
		"instructions": "You are a concise Godot 4.7 editor assistant. Explain UI actions step by step using the exact Godot panel and property names. Base answers on the supplied selection context. Never claim you clicked or changed the project. If uncertain, say so.",
		"input": _history,
		"max_output_tokens": 700,
		"store": false,
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + key,
	])
	_send.disabled = true
	var error := _request.request(API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_send.disabled = false
		_append_message("Assistant", "Could not start the API request (error %d)." % error)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_send.disabled = false
	var raw := body.get_string_from_utf8()
	var data = JSON.parse_string(raw)
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var detail := raw.left(500)
		if data is Dictionary and data.has("error"):
			detail = str(data.error.get("message", detail))
		_append_message("Assistant", "API request failed (%d): %s" % [response_code, detail])
		return
	var answer := _extract_output_text(data)
	if answer.is_empty():
		answer = "The API returned no text response."
	_history.append({"role": "assistant", "content": answer})
	_append_message("Assistant", answer)


func _extract_output_text(data: Variant) -> String:
	if not data is Dictionary:
		return ""
	var pieces: Array[String] = []
	for item in data.get("output", []):
		if not item is Dictionary:
			continue
		for part in item.get("content", []):
			if part is Dictionary and part.get("type", "") == "output_text":
				pieces.append(str(part.get("text", "")))
	return "\n".join(pieces).strip_edges()


func _append_message(who: String, message: String) -> void:
	_chat.append_text("[b]%s[/b]\n%s\n\n" % [who, message])


func _show_audio_help() -> void:
	_append_message("Assistant", "To add audio in Godot:\n1. Drag a .wav or .ogg file into the FileSystem panel.\n2. Select the scene node that should own the sound.\n3. Click + Add Child Node.\n4. Choose AudioStreamPlayer for UI/music, AudioStreamPlayer2D for a 2D position, or AudioStreamPlayer3D for a sound in the 3D world.\n5. In Inspector, drag the imported audio asset into the Stream property.\n6. Enable Autoplay, or call $AudioStreamPlayer.play() from a script.\n\nFor your XR maze, use AudioStreamPlayer3D for sounds that should come from a professor, wall, or exit.")
