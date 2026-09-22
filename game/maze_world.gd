extends Node3D
class_name MazeWorld

## Owns one generated round's grid, geometry, movable walls, and exit.

const MAZE_SIZE := 15
const CELL_SIZE := 1.65
const WALL_HEIGHT := 2.45

var maze: Array = []
var movable_blocks: Dictionary = {}
var block_cells: Array[Vector2i] = []
var exit_node: Node3D
var _player_origin: Node3D
var _materials: Dictionary


func build(seed_value: int, player_origin: Node3D, materials: Dictionary) -> void:
	_player_origin = player_origin
	_materials = materials
	maze.clear()
	movable_blocks.clear()
	block_cells.clear()
	for child in get_children():
		child.queue_free()
	_generate(seed_value)
	_build_geometry()


func _generate(seed_value: int) -> void:
	seed(seed_value)
	for row in MAZE_SIZE:
		var line: Array = []
		for col in MAZE_SIZE:
			line.append(false)
		maze.append(line)
	var stack: Array[Vector2i] = [Vector2i(1, 1)]
	maze[1][1] = true
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for direction in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var next: Vector2i = current + direction
			if next.x > 0 and next.y > 0 and next.x < MAZE_SIZE - 1 and next.y < MAZE_SIZE - 1 and not maze[next.y][next.x]:
				options.append(next)
		if options.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = options[randi() % options.size()]
		var between := current + (next - current) / 2
		maze[between.y][between.x] = true
		maze[next.y][next.x] = true
		stack.append(next)
	# Open a few extra edges so alternate professor routes remain possible.
	for row in range(1, MAZE_SIZE - 1):
		for col in range(1, MAZE_SIZE - 1):
			var horizontal := row % 2 == 1 and col % 2 == 0
			var vertical := row % 2 == 0 and col % 2 == 1
			if horizontal and maze[row][col - 1] and maze[row][col + 1] and randf() < 0.24:
				maze[row][col] = true
			elif vertical and maze[row - 1][col] and maze[row + 1][col] and randf() < 0.24:
				maze[row][col] = true


func _build_geometry() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "MazeFloor"
	floor_body.add_to_group("maze_wall")
	add_child(floor_body)
	_add_box(floor_body, Vector3(MAZE_SIZE * CELL_SIZE, 0.1, MAZE_SIZE * CELL_SIZE), Vector3.ZERO, _materials.floor, false)
	_add_wood_floor_detail()
	for row in MAZE_SIZE:
		for col in MAZE_SIZE:
			if maze[row][col]:
				continue
			var wall := StaticBody3D.new()
			wall.name = "Wall_%d_%d" % [col, row]
			wall.add_to_group("maze_wall")
			add_child(wall)
			_add_box(wall, Vector3(CELL_SIZE, WALL_HEIGHT, CELL_SIZE), cell_to_world(Vector2i(col, row)) + Vector3.UP * WALL_HEIGHT * 0.5, _materials.wall, false)
	var route := find_path(Vector2i(1, 1), Vector2i(MAZE_SIZE - 2, MAZE_SIZE - 2), false)
	for index in [max(2, int(route.size() / 3.0)), max(3, int(route.size() * 2.0 / 3.0))]:
		if index >= 1 and index < route.size() - 1 and not movable_blocks.has(route[index]):
			_create_movable_block(route[index])
	var exit_cell := Vector2i(MAZE_SIZE - 2, MAZE_SIZE - 2)
	exit_node = Node3D.new()
	exit_node.name = "Exit"
	exit_node.position = cell_to_world(exit_cell) + Vector3.UP * 0.08
	add_child(exit_node)
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.5
	ring_mesh.bottom_radius = 0.5
	ring_mesh.height = 0.08
	ring_mesh.radial_segments = 24
	ring_mesh.material = _materials.exit
	ring.mesh = ring_mesh
	exit_node.add_child(ring)
	var beacon := OmniLight3D.new()
	beacon.light_color = Color("#54e4be")
	beacon.light_energy = 2.8
	beacon.omni_range = 4.0
	exit_node.add_child(beacon)
	var exit_text := Label3D.new()
	exit_text.text = "EXIT"
	exit_text.modulate = Color("#8affdd")
	exit_text.font_size = 48
	exit_text.pixel_size = 0.0025
	exit_text.position.y = 0.9
	exit_node.add_child(exit_text)
	_add_ceiling_and_lights()


func _create_movable_block(cell: Vector2i) -> void:
	var block := GrabbableWall.new()
	block.name = "MovableWall_%d_%d" % [cell.x, cell.y]
	block.position = cell_to_world(cell) + Vector3.UP * (WALL_HEIGHT * 0.5)
	block.mass = 4.0
	block.freeze = false
	block.add_to_group("grabbable")
	block.add_to_group("movable_wall")
	block.set_meta("player_origin", _player_origin)
	add_child(block)
	_add_box(block, Vector3(CELL_SIZE * 0.92, WALL_HEIGHT * 0.92, CELL_SIZE * 0.92), Vector3.ZERO, _materials.movable, true)
	movable_blocks[cell] = block
	block_cells.append(cell)


func _add_box(parent: Node, size: Vector3, at: Vector3, material: Material, dynamic: bool) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = at
	parent.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	parent.add_child(collision)
	if dynamic:
		(parent as RigidBody3D).collision_layer = 1
		(parent as RigidBody3D).collision_mask = 1


func _add_wood_floor_detail() -> void:
	for index in range(-MAZE_SIZE / 2, MAZE_SIZE / 2 + 1):
		var seam := MeshInstance3D.new()
		var seam_mesh := BoxMesh.new()
		seam_mesh.size = Vector3(MAZE_SIZE * CELL_SIZE, 0.012, 0.022)
		seam_mesh.material = _materials.wood_seam
		seam.mesh = seam_mesh
		seam.position = Vector3(0.0, 0.058, index * CELL_SIZE)
		add_child(seam)
		var cross_seam := MeshInstance3D.new()
		var cross_mesh := BoxMesh.new()
		cross_mesh.size = Vector3(0.022, 0.013, MAZE_SIZE * CELL_SIZE)
		cross_mesh.material = _materials.wood_seam
		cross_seam.mesh = cross_mesh
		cross_seam.position = Vector3(index * CELL_SIZE, 0.059, 0.0)
		add_child(cross_seam)


func _add_ceiling_and_lights() -> void:
	var ceiling_body := StaticBody3D.new()
	ceiling_body.name = "SchoolCeiling"
	ceiling_body.add_to_group("maze_wall")
	add_child(ceiling_body)
	var span := MAZE_SIZE * CELL_SIZE + CELL_SIZE * 0.8
	_add_box(ceiling_body, Vector3(span, 0.14, span), Vector3(0.0, WALL_HEIGHT + 0.68, 0.0), _materials.ceiling, false)
	for row in [-5, 0, 5]:
		for col in [-5, 0, 5]:
			var fixture := MeshInstance3D.new()
			var fixture_mesh := BoxMesh.new()
			fixture_mesh.size = Vector3(CELL_SIZE * 1.25, 0.055, CELL_SIZE * 0.28)
			fixture_mesh.material = _materials.fluorescent
			fixture.mesh = fixture_mesh
			fixture.position = Vector3(col * CELL_SIZE, WALL_HEIGHT + 0.58, row * CELL_SIZE)
			add_child(fixture)
			var light := OmniLight3D.new()
			light.light_color = Color("#d8efff")
			light.light_energy = 2.1
			light.omni_range = CELL_SIZE * 3.5
			light.shadow_enabled = false
			light.position = fixture.position + Vector3.DOWN * 0.16
			add_child(light)


func choose_professor_cell(start_cell: Vector2i) -> Vector2i:
	var exit_cell := Vector2i(MAZE_SIZE - 2, MAZE_SIZE - 2)
	var player_exit_path := find_path(start_cell, exit_cell, false)
	var candidates: Array[Vector2i] = []
	for cell in [Vector2i(3, 1), Vector2i(1, 3), Vector2i(4, 1), Vector2i(1, 4), Vector2i(5, 1), Vector2i(1, 5)]:
		if is_open(cell) and not player_exit_path.has(cell) and has_grid_line_of_sight(start_cell, cell):
			candidates.append(cell)
	if not candidates.is_empty():
		return candidates[randi_range(0, candidates.size() - 1)]
	for cell in [Vector2i(2, 1), Vector2i(1, 2)]:
		if is_open(cell) and not player_exit_path.has(cell):
			return cell
	return Vector2i(MAZE_SIZE - 2, 1)


func has_grid_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	if from.x != to.x and from.y != to.y:
		return false
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var cursor := from + step
	while cursor != to:
		if not is_open(cursor):
			return false
		cursor += step
	return is_open(to)


func find_path(from: Vector2i, to: Vector2i, avoid_blocks: bool) -> Array[Vector2i]:
	if not is_open(from) or not is_open(to):
		return []
	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary = {from: from}
	for current in queue:
		if current == to:
			break
		for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = current + direction
			if not is_open(next) or came_from.has(next):
				continue
			if avoid_blocks and movable_blocks.has(next) and next != to:
				continue
			came_from[next] = current
			queue.append(next)
	if not came_from.has(to):
		return []
	var result: Array[Vector2i] = []
	var current := to
	while current != from:
		result.push_front(current)
		current = came_from[current]
	result.push_front(from)
	return result


func is_open(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAZE_SIZE and cell.y < MAZE_SIZE and not maze.is_empty() and maze[cell.y][cell.x]


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - (MAZE_SIZE - 1) * 0.5) * CELL_SIZE, 0.0, (cell.y - (MAZE_SIZE - 1) * 0.5) * CELL_SIZE)


func world_to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(roundi(world_position.x / CELL_SIZE + (MAZE_SIZE - 1) * 0.5), roundi(world_position.z / CELL_SIZE + (MAZE_SIZE - 1) * 0.5))
