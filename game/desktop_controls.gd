class_name DesktopControls
extends Node

## Keyboard + mouse play: a first-person camera under the XROrigin3D, WASD
## walking, and E to pick up / put down the nearest movable wall.

const CAMERA_HEIGHT := 1.6
const WALK_SPEED := 2.35
const LOOK_SENSITIVITY := 0.0024
const MAX_PITCH := 1.25
const GRAB_REACH := 2.4
const HOLD_DISTANCE := 1.25

## Set false while XR is running so mouse/keyboard input is ignored.
var enabled := true
var camera: Camera3D
var held_block: GrabbableWall

var _origin: XROrigin3D
var _player: MazePlayer
var _world: MazeWorld
var _pitch := 0.0
var _grab_key_was_down := false
var _hold_transform := Transform3D.IDENTITY


func setup(origin: XROrigin3D, player: MazePlayer, world: MazeWorld) -> void:
	_origin = origin
	_player = player
	_world = world
	camera = Camera3D.new()
	camera.name = "DesktopCamera"
	camera.position = Vector3(0.0, CAMERA_HEIGHT, 0.0)
	camera.fov = 76.0
	camera.current = true
	_origin.add_child(camera)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Forget any held wall, e.g. when the maze is rebuilt.
func release() -> void:
	held_block = null


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_origin.rotate_y(-motion.relative.x * LOOK_SENSITIVITY)
		_pitch = clampf(_pitch - motion.relative.y * LOOK_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
		camera.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func tick(delta: float) -> void:
	if not enabled:
		return
	_walk(delta)
	_grab()


func _walk(delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	input.x += float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	input.y += float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	if input.length() < 0.1:
		return
	input = input.limit_length(1.0)
	var basis := _origin.global_transform.basis
	var direction := basis.x * input.x + basis.z * input.y
	_player.try_move(direction.normalized() * WALK_SPEED * delta)


func _grab() -> void:
	if held_block != null and not is_instance_valid(held_block):
		held_block = null
	var grab_key_down := Input.is_key_pressed(KEY_E)
	if grab_key_down and not _grab_key_was_down:
		if held_block:
			_drop()
		else:
			_pick_up()
	_grab_key_was_down = grab_key_down
	if held_block:
		_carry()


func _pick_up() -> void:
	held_block = _nearest_block()
	if held_block and held_block.begin_hold():
		_hold_transform = held_block.global_transform
	else:
		held_block = null


## Keep the held wall floating in front of the camera; if that spot is inside
## a wall, leave it at the last clear position.
func _carry() -> void:
	var target := camera.global_transform
	target.origin -= target.basis.z * HOLD_DISTANCE
	if held_block.set_held_transform(target):
		_hold_transform = target
	else:
		held_block.global_transform = _hold_transform


## Snap the wall into the nearest free cell that is not on top of the player,
## then let it go.
func _drop() -> void:
	var start := MazeWorld.world_to_cell(held_block.global_position)
	var player_position := _origin.global_position
	for cell in [start, start + Vector2i.RIGHT, start + Vector2i.LEFT, start + Vector2i.DOWN, start + Vector2i.UP]:
		if not _world.is_free(cell, held_block):
			continue
		var center := MazeWorld.cell_to_world(cell) + Vector3.UP * (MazeWorld.WALL_HEIGHT * 0.5)
		if Vector2(center.x - player_position.x, center.z - player_position.z).length() < GrabbableWall.MIN_DROP_DISTANCE:
			continue
		var candidate := _hold_transform
		candidate.origin = center
		if held_block.set_held_transform(candidate):
			_hold_transform = candidate
			if held_block.drop_with_velocity(Vector3.ZERO):
				held_block = null
			return


## The closest movable wall roughly in front of the camera, or null.
func _nearest_block() -> GrabbableWall:
	var best: GrabbableWall
	var best_distance := GRAB_REACH
	var camera_position := camera.global_position
	var camera_forward := -camera.global_transform.basis.z
	for block in _world.blocks:
		if not is_instance_valid(block):
			continue
		var to_block := block.global_position - camera_position
		var distance := to_block.length()
		var facing := camera_forward.dot(to_block.normalized()) if distance > 0.01 else 1.0
		if facing >= 0.25 and distance < best_distance:
			best = block
			best_distance = distance
	return best
