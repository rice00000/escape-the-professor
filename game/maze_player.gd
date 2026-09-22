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


## The body is where the head is, projected to the floor. XROrigin3D is only
## the play-area center; snap turn pivots around the head, which swings the
## origin sideways, so collision must be tested at the head, not the origin.
func body_position() -> Vector3:
	var head := origin.get_node_or_null("XRCamera3D") as Node3D if origin else null
	if head == null:
		return origin.global_position
	var p := head.global_position
	p.y = origin.global_position.y
	return p


func try_move(offset: Vector3, ignored_block: RigidBody3D = null) -> void:
	if origin == null:
		return
	var body := body_position()
	# If the body is already somewhere invalid (turned or leaned into a wall),
	# never lock the player in place: let any move through so they can step out.
	if not is_walkable(body, ignored_block):
		origin.global_position += offset
		return
	if is_walkable(body + offset, ignored_block):
		origin.global_position += offset
		return
	# Preserve the useful corridor sliding behavior for diagonal movement.
	var x_step := Vector3(offset.x, 0.0, 0.0)
	var z_step := Vector3(0.0, 0.0, offset.z)
	if is_walkable(body + x_step, ignored_block):
		origin.global_position += x_step
	elif is_walkable(body + z_step, ignored_block):
		origin.global_position += z_step


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
		var block = movable_blocks[cell]
		if block is GrabbableWall and (block as GrabbableWall).is_player_passable():
			return true
		# Never trap the player inside a wall that became solid around them.
		if origin != null and world_to_cell(body_position()) == cell:
			return true
		return false
	return true


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - (maze_size - 1) * 0.5) * cell_size, 0.0, (cell.y - (maze_size - 1) * 0.5) * cell_size)


func world_to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(roundi(world_position.x / cell_size + (maze_size - 1) * 0.5), roundi(world_position.z / cell_size + (maze_size - 1) * 0.5))
