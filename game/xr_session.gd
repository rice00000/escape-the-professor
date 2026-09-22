class_name XRSession
extends Node

## Brings up OpenXR (with the retries Quest needs) and reports whether the
## game is currently rendering to a headset. Falls back to desktop mode when
## no runtime is available.

signal started

@export var target_refresh_rate := 72.0

const INIT_ATTEMPTS := 12
const INIT_RETRY_SECONDS := 0.5

var _interface: OpenXRInterface


func _ready() -> void:
	# Quest's OpenXR runtime can become ready just after the Android activity
	# starts. Defer so we do not incorrectly fall back to desktop mode.
	_try_initialize.call_deferred()


func is_running() -> bool:
	return _interface != null and _interface.is_initialized() and get_viewport().use_xr


func _try_initialize() -> void:
	_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if _interface == null:
		print("EscapeTheProfessor|INFO: OpenXR is unavailable; desktop mode enabled")
		return
	# The interface must be initialized explicitly, otherwise Godot never
	# submits frames and the headset stays on its loading dots. initialize()
	# fails while the runtime reports the headset as not worn, so retry.
	for attempt in INIT_ATTEMPTS:
		if _interface.is_initialized() or _interface.initialize():
			_enable()
			return
		print("EscapeTheProfessor|WARN: OpenXR initialize() failed on attempt %d" % (attempt + 1))
		await get_tree().create_timer(INIT_RETRY_SECONDS).timeout
	print("EscapeTheProfessor|INFO: no headset runtime; desktop mode enabled")


func _enable() -> void:
	print("EscapeTheProfessor|INFO: OpenXR initialized")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_viewport().use_xr = true
	if not _interface.session_begun.is_connected(_on_session_begun):
		_interface.session_begun.connect(_on_session_begun)
	started.emit()


func _on_session_begun() -> void:
	var rates := _interface.get_available_display_refresh_rates()
	if target_refresh_rate in rates:
		_interface.display_refresh_rate = target_refresh_rate
	elif not rates.is_empty():
		print("EscapeTheProfessor|WARN: requested refresh rate unavailable: ", rates)
	var actual := _interface.display_refresh_rate
	if actual > 0.0:
		Engine.physics_ticks_per_second = int(round(actual))
