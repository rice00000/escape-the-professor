class_name XRHud
extends Node3D

## Owns the two XR-only HUD elements from Task 3: a wrist "watch" panel
## (Label3D child of the left controller) and a world-space toast that
## lazily follows the player's head. main.gd is the only script that knows
## game state; it feeds this node status text and toast requests, and this
## node owns the per-frame follow/fade/visibility bookkeeping.

const TOAST_FOLLOW_DISTANCE := 1.4
const TOAST_HEIGHT_DROP := 0.35
const TOAST_REBEARING_DEGREES := 35.0
const TOAST_FADE_IN_SECONDS := 0.25
const TOAST_FADE_OUT_SECONDS := 0.4
const TOAST_FOLLOW_LERP_RATE := 3.0

var _left_controller: XRController3D
var _camera: XRCamera3D
var _wrist_label: Label3D
var _toast_label: Label3D

# Shared status text (round timer + exit distance), fed every frame by
# main.gd, reused by both the wrist panel and the "no active controller"
# fallback toast.
var _time_text := ""
var _exit_text := ""

# Toast state.
var _toast_seconds_left := 0.0
var _toast_sticky := false
var _toast_active := false
var _toast_fading_out := false
var _toast_alpha := 0.0
var _toast_has_bearing := false
var _toast_last_bearing := 0.0
var _toast_target := Vector3.ZERO
var _fallback_toast_showing := false


func setup(left_controller: XRController3D, camera: XRCamera3D) -> void:
	_left_controller = left_controller
	_camera = camera
	_build_wrist_label()
	_build_toast_label()


func _build_wrist_label() -> void:
	if _left_controller == null:
		return
	_wrist_label = Label3D.new()
	_wrist_label.name = "XRWristPanel"
	_wrist_label.position = Vector3(0.0, 0.03, 0.12)
	_wrist_label.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
	_wrist_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_wrist_label.no_depth_test = false
	_wrist_label.pixel_size = 0.0005
	_wrist_label.font_size = 32
	_wrist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_wrist_label.modulate = Color("#e7f2ff")
	_wrist_label.outline_size = 10
	_wrist_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_wrist_label.visible = false
	_left_controller.add_child(_wrist_label)


func _build_toast_label() -> void:
	_toast_label = Label3D.new()
	_toast_label.name = "XRToast"
	_toast_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_toast_label.no_depth_test = true
	_toast_label.render_priority = 100
	_toast_label.pixel_size = 0.0006
	_toast_label.font_size = 36
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate = Color(Color("#e7f2ff"), 0.0)
	_toast_label.outline_size = 12
	_toast_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.0)
	_toast_label.visible = false
	add_child(_toast_label)


## Called every frame by main.gd with the same timer/exit-distance strings
## the desktop HUD shows (e.g. "42s", "12.3m").
func set_status_text(time_text: String, exit_text: String) -> void:
	_time_text = time_text
	_exit_text = exit_text


## seconds <= 0 means sticky: stays until show_toast() is called again or
## clear_toast() is used. Otherwise it auto-hides after `seconds`.
func show_toast(text: String, seconds: float) -> void:
	if _toast_label:
		_toast_label.text = text
	_toast_seconds_left = seconds
	_toast_sticky = seconds <= 0.0
	_toast_active = true
	_toast_fading_out = false
	_fallback_toast_showing = false


func clear_toast() -> void:
	if _toast_active and not _toast_fading_out:
		_toast_fading_out = true
	_toast_sticky = false
	_toast_seconds_left = 0.0
	_fallback_toast_showing = false


func is_toast_idle() -> bool:
	return not _toast_active


## Drives wrist visibility/text, the "no controller" fallback toast, the
## toast's countdown/expiry, its head-follow position, and its fade alpha.
## Everything XR-only collapses to hidden when xr_running is false.
func update(delta: float, xr_running: bool) -> void:
	if not xr_running:
		if _wrist_label:
			_wrist_label.visible = false
		if _toast_active and not _toast_fading_out:
			_toast_fading_out = true
		_update_toast_fade(delta)
		return
	_update_wrist(xr_running)
	_update_toast_timers(delta)
	_update_toast_follow(delta)
	_update_toast_fade(delta)


func _update_wrist(xr_running: bool) -> void:
	if _wrist_label == null:
		return
	var active := xr_running and _left_controller != null and _left_controller.get_is_active()
	_wrist_label.visible = active
	if active:
		_wrist_label.text = "TIME %s\nEXIT %s" % [_time_text, _exit_text]


func _update_toast_timers(delta: float) -> void:
	var wrist_visible := _wrist_label != null and _wrist_label.visible
	if not wrist_visible and not _toast_active:
		# No wrist panel to glance at (hand tracking, controller asleep, ...)
		# and nothing else wants the toast right now: show a compact status
		# line instead so the player still has some info.
		if _toast_label:
			_toast_label.text = "TIME %s · EXIT %s" % [_time_text, _exit_text]
		_toast_seconds_left = 0.0
		_toast_sticky = true
		_toast_active = true
		_toast_fading_out = false
		_fallback_toast_showing = true
	elif wrist_visible and _fallback_toast_showing:
		clear_toast()
	elif _fallback_toast_showing and _toast_active and _toast_label:
		_toast_label.text = "TIME %s · EXIT %s" % [_time_text, _exit_text]

	if _toast_active and not _toast_sticky and not _toast_fading_out:
		_toast_seconds_left -= delta
		if _toast_seconds_left <= 0.0:
			_toast_fading_out = true


func _update_toast_follow(delta: float) -> void:
	if _camera == null or _toast_label == null:
		return
	var cam_transform := _camera.global_transform
	var forward := -cam_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return
	forward = forward.normalized()
	var bearing := atan2(forward.x, forward.z)
	var first_bearing := not _toast_has_bearing
	var recenter := first_bearing
	if not first_bearing:
		recenter = absf(wrapf(bearing - _toast_last_bearing, -PI, PI)) > deg_to_rad(TOAST_REBEARING_DEGREES)
	if recenter:
		_toast_last_bearing = bearing
		_toast_has_bearing = true
		_toast_target = cam_transform.origin + forward * TOAST_FOLLOW_DISTANCE - Vector3(0.0, TOAST_HEIGHT_DROP, 0.0)
		if first_bearing:
			_toast_label.global_position = _toast_target
	var weight := 1.0 - exp(-TOAST_FOLLOW_LERP_RATE * delta)
	_toast_label.global_position = _toast_label.global_position.lerp(_toast_target, weight)
	if _toast_label.global_position.distance_to(cam_transform.origin) > 0.01:
		_toast_label.look_at(cam_transform.origin, Vector3.UP)
		# look_at() points local -Z at the target; Label3D's readable side
		# faces local +Z, so flip 180 degrees to keep the text right-way
		# round to the player instead of mirrored/backwards.
		_toast_label.rotate_object_local(Vector3.UP, PI)


func _update_toast_fade(delta: float) -> void:
	if _toast_label == null:
		return
	var showing := _toast_active and not _toast_fading_out
	var target := 1.0 if showing else 0.0
	var duration := TOAST_FADE_IN_SECONDS if target > _toast_alpha else TOAST_FADE_OUT_SECONDS
	_toast_alpha = move_toward(_toast_alpha, target, delta / maxf(duration, 0.001))
	_toast_label.visible = _toast_alpha > 0.01
	var color := _toast_label.modulate
	color.a = _toast_alpha
	_toast_label.modulate = color
	var outline := _toast_label.outline_modulate
	outline.a = _toast_alpha * 0.9
	_toast_label.outline_modulate = outline
	if _toast_fading_out and _toast_alpha <= 0.001:
		_toast_active = false
		_toast_fading_out = false
