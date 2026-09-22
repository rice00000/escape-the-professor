extends Node
class_name MazePlayer

## Small collision and camera helper used by the desktop and XR locomotion.

const PLAYER_RADIUS := 0.30

var origin: XROrigin3D
var camera: Camera3D
var maze: Array
var movable_blocks: Dictionary
var maze_size := 15
var cell_size := 1.65


func setup(player_origin: XROrigin3D, player_camera: Camera3D, grid: Array, blocks: Dictionary, size: int, spacing: float) -> void:
	origin = player_origin
	camera = player_camera
	maze = grid
	movable_blocks = blocks
	maze_size = size
	cell_size = spacing


func try_move(offset: Vector3, ignored_block: RigidBody3D = null) -> void:
	if origin == null:
		return
	var next := origin.global_position + offset
	if is_walkable(next, ignored_block):
		origin.global_position = next
		return
	# Preserve the useful corridor sliding behavior for diagonal movement.
	var x_only := origin.global_position + Vector3(offset.x, 0.0, 0.0)
	var z_only := origin.global_position + Vector3(0.0, 0.0, offset.z)
	if is_walkable(x_only, ignored_block):
		origin.global_position = x_only
	elif is_walkable(z_only, ignored_block):
		origin.global_position = z_only


func is_walkable(world_position: Vector3, ignored_block: RigidBody3D = null) -> bool:
	var cell := world_to_cell(world_position)
	if not _cell_is_open(cell, ignored_block):
		return false
	var local := world_position - cell_to_world(cell)
	var edge := cell_size * 0.5 - PLAYER_RADIUS
	# A cell can be traversed right up to an open neighbor, but never close
	# enough to a solid neighbor for the camera/body to enter its wall.
	if local.x > edge and not _cell_is_open(cell + Vector2i.RIGHT, ignored_block):
		return false
	if local.x < -edge and not _cell_is_open(cell + Vector2i.LEFT, ignored_block):
		return false
	if local.z > edge and not _cell_is_open(cell + Vector2i.DOWN, ignored_block):
		return false
	if local.z < -edge and not _cell_is_open(cell + Vector2i.UP, ignored_block):
		return false
	return true


func _cell_is_open(cell: Vector2i, ignored_block: RigidBody3D) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= maze_size or cell.y >= maze_size:
		return false
	if maze.is_empty() or not maze[cell.y][cell.x]:
		return false
	if movable_blocks.has(cell) and movable_blocks[cell] != ignored_block:
		return false
	return true


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - (maze_size - 1) * 0.5) * cell_size, 0.0, (cell.y - (maze_size - 1) * 0.5) * cell_size)


func world_to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(roundi(world_position.x / cell_size + (maze_size - 1) * 0.5), roundi(world_position.z / cell_size + (maze_size - 1) * 0.5))
