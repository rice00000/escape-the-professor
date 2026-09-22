extends Node
class_name MazePlayer

## Collision helper shared by desktop and XR locomotion: moves the XROrigin3D
## while keeping the player's head out of the maze walls.

const PLAYER_RADIUS := 0.30

var origin: XROrigin3D
var world: MazeWorld
var _head: Node3D


func setup(player_origin: XROrigin3D, maze_world: MazeWorld) -> void:
	origin = player_origin
	world = maze_world
	_head = origin.get_node_or_null("XRCamera3D") as Node3D if origin else null


## The body is where the head is, projected to the floor. XROrigin3D is only
## the play-area center; snap turn pivots around the head, which swings the
## origin sideways, so collision must be tested at the head, not the origin.
func body_position() -> Vector3:
	if _head == null:
		return origin.global_position
	var p := _head.global_position
	p.y = origin.global_position.y
	return p


func try_move(offset: Vector3) -> void:
	if origin == null:
		return
	var body := body_position()
	# If the body is already somewhere invalid (turned or leaned into a wall),
	# never lock the player in place: let any move through so they can step out.
	if not is_walkable(body) or is_walkable(body + offset):
		origin.global_position += offset
		return
	# Preserve the useful corridor sliding behavior for diagonal movement.
	var x_step := Vector3(offset.x, 0.0, 0.0)
	var z_step := Vector3(0.0, 0.0, offset.z)
	if is_walkable(body + x_step):
		origin.global_position += x_step
	elif is_walkable(body + z_step):
		origin.global_position += z_step


func is_walkable(world_position: Vector3) -> bool:
	var cell := MazeWorld.world_to_cell(world_position)
	if not _cell_is_open(cell):
		return false
	var local := world_position - MazeWorld.cell_to_world(cell)
	var edge := MazeWorld.CELL_SIZE * 0.5 - PLAYER_RADIUS
	# A cell can be traversed right up to an open neighbor, but never close
	# enough to a solid neighbor for the camera/body to enter its wall.
	if local.x > edge and not _cell_is_open(cell + Vector2i.RIGHT):
		return false
	if local.x < -edge and not _cell_is_open(cell + Vector2i.LEFT):
		return false
	if local.z > edge and not _cell_is_open(cell + Vector2i.DOWN):
		return false
	if local.z < -edge and not _cell_is_open(cell + Vector2i.UP):
		return false
	return true


func _cell_is_open(cell: Vector2i) -> bool:
	if world == null or not world.is_open(cell):
		return false
	var block := world.block_at(cell)
	if block == null or block.is_player_passable():
		return true
	# Never trap the player inside a wall that became solid around them.
	return MazeWorld.world_to_cell(body_position()) == cell
