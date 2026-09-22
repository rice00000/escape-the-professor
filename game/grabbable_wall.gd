extends RigidBody3D
class_name GrabbableWall

## Shared behavior for desktop, controller, and hand tracking grabs.
## While held, the wall is kinematic, non-colliding, and easy to see through.

const HELD_TRANSPARENCY := 0.58
## After a drop the player can walk through the wall for this long; the
## professor is blocked immediately.
const PLAYER_PASS_SECONDS := 5.0
## A wall may not be dropped closer than this (horizontally) to the player.
const MIN_DROP_DISTANCE := 1.32

var held := false
var _saved_collision_layer := 1
var _saved_collision_mask := 1
var _saved_transparency: Dictionary = {}
var _saved_material_overrides: Dictionary = {}
var _last_valid_transform := Transform3D.IDENTITY
var _player_pass_left := 0.0


func _process(delta: float) -> void:
	if _player_pass_left > 0.0:
		_player_pass_left -= delta
		if _player_pass_left <= 0.0 and not held:
			_set_held_transparency(false)


func is_player_passable() -> bool:
	return held or _player_pass_left > 0.0


func begin_hold() -> bool:
	if held:
		return false
	held = true
	_player_pass_left = 0.0
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
		if horizontal.length() < MIN_DROP_DISTANCE:
			return false
	freeze = false
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask
	linear_velocity = velocity
	held = false
	# Stay see-through while the player can still walk through it.
	_player_pass_left = PLAYER_PASS_SECONDS
	return true


func _set_held_transparency(enabled: bool) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		if enabled:
			_saved_transparency[mesh] = mesh.transparency
			_saved_material_overrides[mesh] = mesh.material_override
			# GeometryInstance3D.transparency only affects a material that has a
			# transparent render mode. The maze material is intentionally opaque
			# at rest, so use a per-held duplicate instead of changing the shared
			# material used by every movable wall.
			var source_material: Material = mesh.material_override
			if source_material == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
				source_material = mesh.mesh.surface_get_material(0)
			if source_material is BaseMaterial3D:
				var held_material := (source_material as BaseMaterial3D).duplicate() as BaseMaterial3D
				held_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				# Keep the alpha on the material as well as the instance. Some
				# mobile render paths do not apply GeometryInstance3D.transparency
				# consistently when the source material was created as opaque.
				var held_color := held_material.albedo_color
				held_color.a = 1.0 - HELD_TRANSPARENCY
				held_material.albedo_color = held_color
				mesh.material_override = held_material
			mesh.transparency = 0.0
		else:
			mesh.transparency = float(_saved_transparency.get(mesh, 0.0))
			mesh.material_override = _saved_material_overrides.get(mesh, null)
	_saved_transparency.clear()
	_saved_material_overrides.clear()


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
