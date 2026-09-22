class_name XRLocomotion
extends Node

## Headset movement: the left thumbstick walks, the right thumbstick snap
## turns, and a thumb/index pinch walks forward when playing with tracked
## hands and no controllers.

const WALK_SPEED := 2.35
const STICK_DEADZONE := 0.1
## Degrees rotated per right-stick snap turn.
const SNAP_TURN_DEGREES := 30.0
## The stick must pass DEADZONE_ON to fire a turn and fall back below
## DEADZONE_OFF before it can fire again, so holding it over turns once.
const SNAP_TURN_DEADZONE_ON := 0.6
const SNAP_TURN_DEADZONE_OFF := 0.3
## Thumb-to-index distance (meters, after world scale) that counts as a pinch.
const PINCH_DISTANCE := 0.028

var _origin: XROrigin3D
var _camera: XRCamera3D
var _left: XRController3D
var _right: XRController3D
var _player: MazePlayer
var _turn_latched := false


func setup(origin: XROrigin3D, camera: XRCamera3D, left: XRController3D, right: XRController3D, player: MazePlayer) -> void:
	_origin = origin
	_camera = camera
	_left = left
	_right = right
	_player = player


func tick(delta: float) -> void:
	if _right:
		_snap_turn(_right.get_vector2("primary").x)
	var direction := _walk_direction()
	if direction != Vector3.ZERO:
		_player.try_move(direction.normalized() * WALK_SPEED * delta)


## World-space, floor-plane direction the player wants to walk, or ZERO.
func _walk_direction() -> Vector3:
	var basis := _camera.global_transform.basis if _camera else _origin.global_transform.basis
	var stick := _left.get_vector2("primary") if _left else Vector2.ZERO
	var direction := Vector3.ZERO
	if stick.length() >= STICK_DEADZONE:
		stick = stick.limit_length(1.0)
		direction = basis.x * stick.x - basis.z * stick.y
	elif _is_pinching(0) or _is_pinching(1):
		direction = -basis.z
	direction.y = 0.0
	return direction if direction.length() > 0.01 else Vector3.ZERO


## Rotates the origin around the player's body so their feet stay put.
func _snap_turn(stick_x: float) -> void:
	if absf(stick_x) < SNAP_TURN_DEADZONE_OFF:
		_turn_latched = false
		return
	if absf(stick_x) < SNAP_TURN_DEADZONE_ON or _turn_latched:
		return
	_turn_latched = true
	var pivot := _player.body_position()
	var angle := deg_to_rad(SNAP_TURN_DEGREES) * -signf(stick_x)
	var t := _origin.global_transform.translated(-pivot)
	t = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * t
	_origin.global_transform = t.translated(pivot)


## True while the given hand (0 left, 1 right) is tracked as a real hand and
## its thumb and index fingertips are touching.
func _is_pinching(hand_index: int) -> bool:
	var tracker := XRServer.get_tracker(XRHandVisuals.HAND_TRACKERS[hand_index]) as XRHandTracker
	if tracker == null or not tracker.get_has_tracking_data():
		return false
	var source := tracker.get_hand_tracking_source()
	if source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER or source == XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED:
		return false
	var thumb := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
	var index := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	return thumb.distance_to(index) * XRServer.world_scale < PINCH_DISTANCE
