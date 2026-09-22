class_name XRRestartInput
extends Node

## A/X on either controller restarts the round: held for HOLD_SECONDS while
## playing (so a stray press does not wipe a good run), a single press once
## the round is over.

signal restart_requested

const HOLD_SECONDS := 1.0

var _left: XRController3D
var _right: XRController3D
var _was_pressed := false
var _hold_time := 0.0


func setup(left: XRController3D, right: XRController3D) -> void:
	_left = left
	_right = right


## 0.0 when the button is not held, rising to 1.0 as the hold completes.
func hold_progress() -> float:
	return clampf(_hold_time / HOLD_SECONDS, 0.0, 1.0)


func tick(delta: float, playing: bool) -> void:
	var pressed := _is_pressed(_left) or _is_pressed(_right)
	var just_pressed := pressed and not _was_pressed
	_was_pressed = pressed
	if not playing:
		_hold_time = 0.0
		if just_pressed:
			restart_requested.emit()
		return
	_hold_time = _hold_time + delta if pressed else 0.0
	if _hold_time >= HOLD_SECONDS:
		_hold_time = 0.0
		_was_pressed = false
		restart_requested.emit()


func _is_pressed(controller: XRController3D) -> bool:
	return controller != null and controller.get_is_active() and controller.is_button_pressed("ax_button")
