class_name DesktopHud
extends CanvasLayer

## The 2D overlay used when playing on a monitor. It never renders inside a
## headset; XRHud covers that case.

var _info: Label
var _status: Label


func _init() -> void:
	name = "GameHUD"
	_info = _label(Vector2(24, 20), 20, Color("#e7f2ff"))
	_status = _label(Vector2(24, 120), 28, Color("#71f3d0"))


func set_text(info: String, status: String) -> void:
	_info.text = info
	_status.text = status


func _label(at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label
