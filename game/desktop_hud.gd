class_name DesktopHud
extends CanvasLayer

## The 2D overlay used when playing on a monitor. It never renders inside a
## headset; XRHud covers that case.

var _info: Label
var _status: Label
var _threat_overlay: ColorRect
var _result_overlay: ColorRect
var _result_label: Label


func _init() -> void:
	name = "GameHUD"
	_info = _label(Vector2(24, 20), 20, Color("#e7f2ff"))
	_status = _label(Vector2(24, 120), 28, Color("#71f3d0"))
	_threat_overlay = ColorRect.new()
	_threat_overlay.name = "ThreatWarningOverlay"
	_threat_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_threat_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_overlay.visible = false
	add_child(_threat_overlay)
	_result_overlay = ColorRect.new()
	_result_overlay.name = "ResultOverlay"
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_overlay.visible = false
	add_child(_result_overlay)
	_result_label = Label.new()
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 42)
	_result_label.add_theme_color_override("font_color", Color("#fff2e4"))
	_result_label.add_theme_color_override("font_outline_color", Color("#32050b"))
	_result_label.add_theme_constant_override("outline_size", 12)
	_result_overlay.add_child(_result_label)


func set_text(info: String, status: String) -> void:
	_info.text = info
	_status.text = status


func set_threat_warning(strength: float, flash: float) -> void:
	if strength <= 0.0:
		_threat_overlay.visible = false
		return
	var red := Color("#ff173d")
	var blue := Color("#315cff")
	var color := red.lerp(blue, flash)
	# Keep the warning readable without obscuring the maze.
	color.a = strength * lerpf(0.03, 0.16, absf(flash - 0.5) * 2.0)
	_threat_overlay.color = color
	_threat_overlay.visible = true


func show_result(text: String, won: bool) -> void:
	_result_label.text = text.replace("! ", "!\n\n")
	_result_label.add_theme_font_size_override("font_size", 42 if won else 54)
	_result_overlay.color = Color(0.015, 0.09, 0.075, 0.82) if won else Color(0.12, 0.015, 0.025, 0.84)
	_result_overlay.visible = true


func clear_result() -> void:
	_result_overlay.visible = false


func _label(at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label
