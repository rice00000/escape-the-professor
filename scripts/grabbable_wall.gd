extends RigidBody3D
class_name GrabbableWall

## Shared behavior for desktop, controller, and hand tracking grabs.
## While held, the wall is kinematic, non-colliding, and easy to see through.

const HELD_TRANSPARENCY := 0.58

var held := false
var _saved_collision_layer := 1
var _saved_collision_mask := 1
var _saved_transparency: Dictionary = {}
var _last_valid_transform := Transform3D.IDENTITY


func begin_hold() -> bool:
	if held:
		return false
	held = true
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	# A carried wall should not block the player or its own placement query.
	collision_layer = 0
	collision_mask = 0
	_last_valid_transform = global_transform
	_set_held_transparency(true)
	return true


func set_held_transform(candidate: Transform3D) -> bool:
	if not held:
		return false
	if not _overlaps_maze_wall(candidate):
		global_transform = candidate
		_last_valid_transform = candidate
		return true
	return false


func drop_with_velocity(velocity: Vector3) -> bool:
	if not held:
		return true
	# Keep the last known clear transform if a tracked hand/controller ended
	# inside a wall between physics ticks.
	if _overlaps_maze_wall(global_transform):
		global_transform = _last_valid_transform
	if _overlaps_maze_wall(global_transform):
		return false
	var player := get_meta("player_origin", null) as Node3D
	if player != null:
		var horizontal := Vector2(global_position.x - player.global_position.x, global_position.z - player.global_position.z)
		if horizontal.length() < 1.32:
			return false
	freeze = false
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask
	linear_velocity = velocity
	held = false
	_set_held_transparency(false)
	return true


func _set_held_transparency(enabled: bool) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		if enabled:
			_saved_transparency[mesh] = mesh.transparency
			mesh.transparency = HELD_TRANSPARENCY
		else:
			mesh.transparency = float(_saved_transparency.get(mesh, 0.0))
	_saved_transparency.clear()


func _overlaps_maze_wall(candidate: Transform3D) -> bool:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null or get_world_3d() == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = candidate * shape_node.transform
	query.collision_mask = 1
	query.exclude = [self]
	for hit in get_world_3d().direct_space_state.intersect_shape(query):
		var collider := hit.get("collider") as Node
		if collider != null and (collider.is_in_group("maze_wall") or collider.is_in_group("movable_wall")):
			return true
	return false
