## TEMPLATE FILE ############################
# Picking things up with hands!
#############################################

extends Area3D
class_name XRHandGrabber


## Which hand
@export_enum("Left", "Right") var hand := 0

## Distance between fingertips that a valid grab is registered. The two distinct
## values are used for hysteresis. In short, the pinch initiates when distance
## goes below pinch distance, and releases only when it crosses release distance.
## This is to prevent flickering in the middle and is a useful concept to remember.
@export_range(0.005, 0.1) var pinch_distance := 0.02
@export_range(0.005, 0.1) var release_distance := 0.04

## If set, only objects in this group can be grabbed via hands.
@export var required_group := ""

## Multiplies how hard objects are thrown. Sometimes it can feel more satisfying to
## bump this up to ~1.2 ish
@export_range(0.5, 2) var throw_strength := 1.0

var _held: RigidBody3D = null
var _pinching := false

# Same ideas as the other controller grab script.
var _grab_offset := Transform3D.IDENTITY
var _last_position := Vector3.ZERO
var _velocity := Vector3.ZERO


func _ready() -> void:
	# Ensure the script is a child of the XROrigin3D.
	if get_parent() as XROrigin3D == null:
		push_error("XRHandGrabber|FATAL: this node must be a child of an XROrigin3D")
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	var tracker := _find_tracker()

	# If hand tracking disables, stop tracking and drop the object
	if not _actually_tracking(tracker):

		# Drop the object
		if _pinching:
			_pinching = false
			_release()

		return

	# Compute the center pinch point
	var thumb_pos := _joint_position(tracker, XRHandTracker.HAND_JOINT_THUMB_TIP)
	var index_pos := _joint_position(tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	position = (thumb_pos + index_pos) * 0.5

	# Pinch edge detection with hysteresis
	var distance := thumb_pos.distance_to(index_pos)
	if not _pinching and (distance < pinch_distance):
		_pinching = true
		_grab()
	elif _pinching and (distance > release_distance):
		_pinching = false
		_release()

	if _held == null:
		return

	# Check to see if object was deleted since. Stops the hand from staying grabbed to a "ghost" object.
	if not is_instance_valid(_held):
		_held = null
		return

	# Move the held object to the grab point.
	_held.global_transform = global_transform * _grab_offset

	# Measure the velocity and start moving the target throw velocity to the current one.
	# Feel free to adjust the 0.4 to see how different values feel.
	var frame_velocity := (_held.global_position - _last_position) / delta
	_velocity = _velocity.lerp(frame_velocity, 0.4)
	_last_position = _held.global_position


func _grab() -> void:
	if _held != null:
		return

	var body := _nearest_body()
	if body == null:
		return

	_held = body

	# Stop physics from acting on the grabbed object. This will still allow it to push things around
	_held.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_held.freeze = true

	# We use affine inverse here as we cannot confirm the transformation doesn't have a scale.
	# Use the regular inverse method ONLY when you know the transform is rotation+translation (no scale)

	# lin algebra wise this looks something like this: We WANT the translation of the object with respect to our hand
	# We have the hand's global transform, H, and to translate the object's global transform, O, to one local to our hand,
	# We want an offset such that H * off = O. With simple algebra, we can see that off = inv(H) * O. This is what we compute lin algebra ryan out :salute:
	_grab_offset = global_transform.affine_inverse() * _held.global_transform
	_last_position = _held.global_position
	_velocity = Vector3.ZERO


func _release() -> void:
	if _held == null:
		return

	# Set the objects velocity to throw. Also unfreeze physics
	if is_instance_valid(_held):
		_held.freeze = false
		_held.linear_velocity = _velocity * throw_strength

	# Reset members for next grab
	_held = null
	_velocity = Vector3.ZERO


## Closest grabbable body currently inside the grab volume, or null
func _nearest_body() -> RigidBody3D:
	var best: RigidBody3D = null
	var best_distance := INF

	for body in get_overlapping_bodies():
		var rigid := body as RigidBody3D

		# Skip anything that isnt a loose physics body. You can modify this if you'd rather
		# be able to grab something specific thats frozen too. Your call.
		if rigid == null or rigid.freeze:
			continue
		if required_group != "" and not rigid.is_in_group(required_group):
			continue

		# Compute if the given body is closer. distance_squared_to is faster and an acceptable
		# metric for this.
		var distance := global_position.distance_squared_to(rigid.global_position)
		if distance < best_distance:
			best_distance = distance
			best = rigid

	return best


func _find_tracker() -> XRHandTracker:
	return XRServer.get_tracker(XRHandVisuals.HAND_TRACKERS[hand]) as XRHandTracker


# Same check as xr_hands.gd
func _actually_tracking(tracker: XRHandTracker) -> bool:
	if tracker == null or not tracker.get_has_tracking_data():
		return false

	var source := tracker.get_hand_tracking_source()
	return (source != XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
		and source != XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED)


# Joint position in XROrigin3D space. Same conversion xr_hands.gd uses to place its meshes.
#
# The way this transform works, is that we first scale the point according to world scale, then we apply
# the transformation from tracking space to godot node-space.
func _joint_position(tracker: XRHandTracker, joint: int) -> Vector3:
	return XRServer.get_reference_frame() * (tracker.get_hand_joint_transform(joint).origin * XRServer.world_scale)
