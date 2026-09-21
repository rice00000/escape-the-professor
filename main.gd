## Escape the Professor
## Runtime-only prototype built on the XR template's existing OpenXR origin.
## The maze is deliberately made from primitive meshes so every round can differ.

extends Node3D

var xr_interface: OpenXRInterface
@export var target_refresh_rate := 72.0

const MAZE_SIZE := 11
const CELL_SIZE := 1.65
const WALL_HEIGHT := 2.45
const PLAYER_HEIGHT := 1.6
const PROFESSOR_SPEED := 1.45
const BREAK_TIME := 2.5

var maze: Array = []
var movable_blocks: Dictionary = {}
var block_cells: Array[Vector2i] = []
var maze_root: Node3D
var professor: Node3D
var professor_light: OmniLight3D
var exit_node: Node3D
var exit_audio: AudioStreamPlayer3D
var professor_audio: AudioStreamPlayer3D
var pulse_timer := 0.0
var professor_timer := 0.0
var path_timer := 0.0
var break_cell := Vector2i(-1, -1)
var break_timer := 0.0
var professor_path: Array[Vector2i] = []
var round_seed := 0
var round_time := 0.0
var game_state := "playing"
var desktop_camera: Camera3D
var hud: Label
var status_label: Label
var player_origin: XROrigin3D
var held_desktop_block: RigidBody3D
var camera_pitch := 0.0
var last_e_down := false

var floor_material: StandardMaterial3D
var wall_material: StandardMaterial3D
var movable_material: StandardMaterial3D
var professor_material: StandardMaterial3D
var exit_material: StandardMaterial3D


func _ready() -> void:
	player_origin = get_node_or_null("XROrigin3D") as XROrigin3D
	_try_initialize_openxr()
	_hide_template_demo()
	_setup_materials()
	_setup_desktop_camera()
	_setup_hud()
	_start_round()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _try_initialize_openxr() -> void:
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null:
		print("EscapeTheProfessor|INFO: OpenXR is unavailable; desktop mode enabled")
		return
	if not xr_interface.is_initialized() and not xr_interface.initialize():
		print("EscapeTheProfessor|INFO: no headset runtime; desktop mode enabled")
		return
	print("EscapeTheProfessor|INFO: OpenXR initialized")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_viewport().use_xr = true
	if not xr_interface.session_begun.is_connected(_on_session_begun):
		xr_interface.session_begun.connect(_on_session_begun)


func _on_session_begun() -> void:
	var rates := xr_interface.get_available_display_refresh_rates()
	if target_refresh_rate in rates:
		xr_interface.display_refresh_rate = target_refresh_rate
	elif not rates.is_empty():
		print("EscapeTheProfessor|WARN: requested refresh rate unavailable: ", rates)
	var actual := xr_interface.display_refresh_rate
	if actual > 0.0:
		Engine.physics_ticks_per_second = int(round(actual))


func _hide_template_demo() -> void:
	# Keep the XR setup, visuals, hands and controller grabbers. Hide the sample table.
	for node_name in ["Floor", "Table", "Props", "PassthroughTutorialText"]:
		var node := get_node_or_null(node_name)
		if node:
			if node is Node3D or node is CanvasItem:
				node.visible = false
			if node is CollisionObject3D:
				node.collision_layer = 0
				node.collision_mask = 0
	var movement := get_node_or_null("XROrigin3D/XRMovement")
	if movement:
		# Movement is implemented here so XR and desktop use the same simple wall checks.
		movement.set_process(false)


func _setup_materials() -> void:
	floor_material = _material(Color("#172338"), 0.75)
	wall_material = _material(Color("#3e5871"), 0.42)
	movable_material = _material(Color("#b76c39"), 0.3)
	professor_material = _material(Color("#a62936"), 0.28)
	exit_material = _material(Color("#54e4be"), 0.08, true)


func _material(color: Color, roughness: float, emission := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
	return mat


func _setup_desktop_camera() -> void:
	if player_origin == null:
		return
	desktop_camera = Camera3D.new()
	desktop_camera.name = "DesktopCamera"
	desktop_camera.position = Vector3(0.0, PLAYER_HEIGHT, 0.0)
	desktop_camera.current = true
	desktop_camera.fov = 76.0
	player_origin.add_child(desktop_camera)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "GameHUD"
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(24, 20)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Color("#e7f2ff"))
	canvas.add_child(hud)
	status_label = Label.new()
	status_label.position = Vector2(24, 120)
	status_label.add_theme_font_size_override("font_size", 28)
	status_label.add_theme_color_override("font_color", Color("#71f3d0"))
	canvas.add_child(status_label)


func _start_round() -> void:
	round_seed = randi()
	seed(round_seed)
	maze.clear()
	block_cells.clear()
	movable_blocks.clear()
	game_state = "playing"
	round_time = 0.0
	break_cell = Vector2i(-1, -1)
	break_timer = 0.0
	professor_path.clear()
	if maze_root and is_instance_valid(maze_root):
		maze_root.queue_free()
	maze_root = Node3D.new()
	maze_root.name = "ProceduralMaze"
	add_child(maze_root)
	_generate_maze()
	_build_maze()
	_place_player_and_professor()
	_create_audio()
	_update_hud()


func _generate_maze() -> void:
	for row in MAZE_SIZE:
		var line: Array = []
		for col in MAZE_SIZE:
			line.append(false)
		maze.append(line)
	var stack: Array[Vector2i] = [Vector2i(1, 1)]
	maze[1][1] = true
	var directions := [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for direction in directions:
			var next: Vector2i = current + direction
			if next.x > 0 and next.x < MAZE_SIZE - 1 and next.y > 0 and next.y < MAZE_SIZE - 1 and not maze[next.y][next.x]:
				options.append(next)
		if options.is_empty():
			stack.pop_back()
		else:
			var next: Vector2i = options[randi_range(0, options.size() - 1)]
			var between := current + (next - current) / 2
			maze[between.y][between.x] = true
			maze[next.y][next.x] = true
			stack.append(next)
	maze[MAZE_SIZE - 2][MAZE_SIZE - 2] = true


func _build_maze() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "MazeFloor"
	maze_root.add_child(floor_body)
	_add_box(floor_body, Vector3(MAZE_SIZE * CELL_SIZE, 0.1, MAZE_SIZE * CELL_SIZE), Vector3.ZERO, floor_material, false)
	for row in MAZE_SIZE:
		for col in MAZE_SIZE:
			if not maze[row][col]:
				var wall := StaticBody3D.new()
				wall.name = "Wall_%d_%d" % [col, row]
				maze_root.add_child(wall)
				_add_box(wall, Vector3(CELL_SIZE, WALL_HEIGHT, CELL_SIZE), _cell_to_world(Vector2i(col, row)) + Vector3.UP * WALL_HEIGHT * 0.5, wall_material, false)
	var route := _find_path(Vector2i(1, 1), Vector2i(MAZE_SIZE - 2, MAZE_SIZE - 2), false)
	var candidate_indices := [max(2, int(route.size() / 3.0)), max(3, int(route.size() * 2.0 / 3.0))]
	for index in candidate_indices:
		if index >= 1 and index < route.size() - 1:
			var cell: Vector2i = route[index]
			if not movable_blocks.has(cell):
				_create_movable_block(cell)
	var exit_cell := Vector2i(MAZE_SIZE - 2, MAZE_SIZE - 2)
	exit_node = Node3D.new()
	exit_node.name = "Exit"
	exit_node.position = _cell_to_world(exit_cell) + Vector3.UP * 0.08
	maze_root.add_child(exit_node)
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.5
	ring_mesh.bottom_radius = 0.5
	ring_mesh.height = 0.08
	ring_mesh.radial_segments = 24
	ring_mesh.material = exit_material
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


func _create_movable_block(cell: Vector2i) -> void:
	var block := RigidBody3D.new()
	block.name = "MovableWall_%d_%d" % [cell.x, cell.y]
	block.position = _cell_to_world(cell) + Vector3.UP * (WALL_HEIGHT * 0.5)
	block.mass = 4.0
	block.freeze = false
	block.add_to_group("grabbable")
	block.add_to_group("movable_wall")
	maze_root.add_child(block)
	_add_box(block, Vector3(CELL_SIZE * 0.92, WALL_HEIGHT * 0.92, CELL_SIZE * 0.92), Vector3.ZERO, movable_material, true)
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
		# The template grab areas use their default mask (layer 1).
		(parent as RigidBody3D).collision_layer = 1
		(parent as RigidBody3D).collision_mask = 1


func _place_player_and_professor() -> void:
	if player_origin:
		player_origin.global_position = _cell_to_world(Vector2i(1, 1))
		player_origin.rotation = Vector3.ZERO
	var professor_cell := Vector2i(MAZE_SIZE - 2, 1)
	professor = Node3D.new()
	professor.name = "Professor"
	professor.position = _cell_to_world(professor_cell) + Vector3.UP * 1.0
	maze_root.add_child(professor)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.38
	body_mesh.height = 1.85
	body_mesh.material = professor_material
	body.mesh = body_mesh
	body.position.y = 0.0
	professor.add_child(body)
	var hat := MeshInstance3D.new()
	var hat_mesh := CylinderMesh.new()
	hat_mesh.top_radius = 0.48
	hat_mesh.bottom_radius = 0.48
	hat_mesh.height = 0.18
	hat_mesh.material = professor_material
	hat.mesh = hat_mesh
	hat.position.y = 0.98
	professor.add_child(hat)
	professor_light = OmniLight3D.new()
	professor_light.light_color = Color("#ff3a48")
	professor_light.light_energy = 1.2
	professor_light.omni_range = 3.0
	professor.add_child(professor_light)


func _create_audio() -> void:
	if exit_audio and is_instance_valid(exit_audio): exit_audio.queue_free()
	if professor_audio and is_instance_valid(professor_audio): professor_audio.queue_free()
	exit_audio = AudioStreamPlayer3D.new()
	exit_audio.name = "ExitMusicalPulse"
	exit_audio.stream = _tone_stream(660.0, 0.22, 0.16, 0.0)
	exit_audio.max_distance = MAZE_SIZE * CELL_SIZE * 1.4
	exit_audio.unit_size = 1.5
	exit_node.add_child(exit_audio)
	professor_audio = AudioStreamPlayer3D.new()
	professor_audio.name = "ProfessorFootsteps"
	professor_audio.stream = _tone_stream(92.0, 0.18, 0.20, 0.1)
	professor_audio.max_distance = MAZE_SIZE * CELL_SIZE
	professor_audio.unit_size = 1.0
	professor.add_child(professor_audio)


func _tone_stream(frequency: float, duration: float, volume: float, second_frequency: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / rate
		var envelope := minf(1.0, t * 40.0) * minf(1.0, (duration - t) * 16.0)
		var value := sin(TAU * frequency * t)
		if second_frequency > 0.0: value = (value + sin(TAU * second_frequency * t) * 0.35) / 1.35
		var sample := int(clampf(value * envelope * volume, -1.0, 1.0) * 32767.0)
		bytes[i * 2] = sample & 255
		bytes[i * 2 + 1] = (sample >> 8) & 255
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _process(delta: float) -> void:
	if game_state != "playing":
		_update_hud()
		return
	round_time += delta
	_handle_desktop_look()
	_handle_player_movement(delta)
	_handle_desktop_grab()
	_update_professor(delta)
	_update_exit_audio(delta)
	_check_end_conditions()
	_update_hud()


func _handle_desktop_look() -> void:
	if desktop_camera == null or _xr_is_running(): return
	if Input.is_key_pressed(KEY_ESCAPE): Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not _xr_is_running() and desktop_camera:
		var motion := event as InputEventMouseMotion
		player_origin.rotate_y(-motion.relative.x * 0.0024)
		camera_pitch = clampf(camera_pitch - motion.relative.y * 0.0024, -1.25, 1.25)
		desktop_camera.rotation.x = camera_pitch


func _handle_player_movement(delta: float) -> void:
	if player_origin == null: return
	var input := Vector2.ZERO
	if not _xr_is_running():
		input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_key_pressed(KEY_A): input.x -= 1.0
		if Input.is_key_pressed(KEY_D): input.x += 1.0
		if Input.is_key_pressed(KEY_W): input.y -= 1.0
		if Input.is_key_pressed(KEY_S): input.y += 1.0
	else:
		var controller := get_node_or_null("XROrigin3D/XRControllerLeft") as XRController3D
		if controller: input = controller.get_vector2("primary")
	if input.length() < 0.1: return
	input = input.limit_length(1.0)
	var direction: Vector3
	if not _xr_is_running():
		var basis := player_origin.global_transform.basis
		direction = basis.x * input.x - basis.z * input.y
	else:
		var camera := get_node_or_null("XROrigin3D/XRCamera3D") as Node3D
		var basis := camera.global_transform.basis if camera else player_origin.global_transform.basis
		direction = basis.x * input.x - basis.z * input.y
	direction.y = 0.0
	if direction.length() > 0.01: _try_move_player(direction.normalized() * 2.35 * delta)


func _try_move_player(offset: Vector3) -> void:
	var next := player_origin.global_position + offset
	if _is_walkable(next):
		player_origin.global_position = next
	else:
		var x_only := player_origin.global_position + Vector3(offset.x, 0.0, 0.0)
		var z_only := player_origin.global_position + Vector3(0.0, 0.0, offset.z)
		if _is_walkable(x_only): player_origin.global_position = x_only
		elif _is_walkable(z_only): player_origin.global_position = z_only


func _is_walkable(world_position: Vector3) -> bool:
	var cell := _world_to_cell(world_position)
	if cell.x < 0 or cell.y < 0 or cell.x >= MAZE_SIZE or cell.y >= MAZE_SIZE: return false
	if not maze[cell.y][cell.x]: return false
	if movable_blocks.has(cell) and movable_blocks[cell] != held_desktop_block: return false
	return true


func _handle_desktop_grab() -> void:
	if _xr_is_running() or player_origin == null: return
	var down := Input.is_key_pressed(KEY_E)
	if down and not last_e_down:
		if held_desktop_block:
			held_desktop_block.freeze = false
			held_desktop_block = null
		else:
			held_desktop_block = _nearest_block(2.4)
			if held_desktop_block: held_desktop_block.freeze = true
	last_e_down = down
	if held_desktop_block and is_instance_valid(held_desktop_block):
		var target := desktop_camera.global_position - desktop_camera.global_transform.basis.z * 1.25
		held_desktop_block.global_position = target


func _nearest_block(max_distance: float) -> RigidBody3D:
	var best: RigidBody3D
	var best_distance := max_distance
	for block in movable_blocks.values():
		if block is RigidBody3D and is_instance_valid(block):
			var distance := player_origin.global_position.distance_to(block.global_position)
			if distance < best_distance:
				best = block
				best_distance = distance
	return best


func _update_professor(delta: float) -> void:
	if professor == null or player_origin == null: return
	professor_timer -= delta
	path_timer -= delta
	if break_timer > 0.0:
		break_timer -= delta
		professor.rotation.y += delta * 2.0
		if break_timer <= 0.0:
			_destroy_movable_block(break_cell)
			break_cell = Vector2i(-1, -1)
		return
	if path_timer <= 0.0:
		path_timer = 0.22
		var professor_cell := _world_to_cell(professor.global_position)
		var player_cell := _world_to_cell(player_origin.global_position)
		professor_path = _find_path(professor_cell, player_cell, true)
		if professor_path.size() < 2:
			var unblocked_path := _find_path(professor_cell, player_cell, false)
			for path_cell in unblocked_path:
				if movable_blocks.has(path_cell):
					break_cell = path_cell
					break_timer = BREAK_TIME
					break
	if professor_path.size() >= 2:
		var next_position := _cell_to_world(professor_path[1]) + Vector3.UP * 1.0
		professor.global_position = professor.global_position.move_toward(next_position, PROFESSOR_SPEED * delta)
		if professor_audio and professor_timer <= 0.0:
			professor_audio.play()
			professor_timer = 0.72


func _destroy_movable_block(cell: Vector2i) -> void:
	if not movable_blocks.has(cell): return
	var block: RigidBody3D = movable_blocks[cell]
	movable_blocks.erase(cell)
	block_cells.erase(cell)
	if is_instance_valid(block): block.queue_free()


func _update_exit_audio(delta: float) -> void:
	if exit_node == null or exit_audio == null or player_origin == null: return
	var distance := player_origin.global_position.distance_to(exit_node.global_position)
	var interval := clampf(0.95 * distance / (MAZE_SIZE * CELL_SIZE), 0.16, 0.95)
	pulse_timer -= delta
	if pulse_timer <= 0.0:
		exit_audio.play()
		pulse_timer = interval


func _check_end_conditions() -> void:
	if player_origin == null or professor == null or exit_node == null: return
	if player_origin.global_position.distance_to(exit_node.global_position) < 0.75:
		game_state = "won"
		status_label.text = "ESCAPED! Press R for a new maze"
		if exit_audio: exit_audio.play()
	elif player_origin.global_position.distance_to(professor.global_position) < 0.95:
		game_state = "lost"
		status_label.text = "CAUGHT BY THE PROFESSOR! Press R to retry"


func _update_hud() -> void:
	if hud == null: return
	var exit_distance := 0.0
	if player_origin and exit_node: exit_distance = player_origin.global_position.distance_to(exit_node.global_position)
	var break_text := ""
	if break_timer > 0.0: break_text = "\nProfessor is breaking a wall: %.1fs" % break_timer
	hud.text = "ESCAPE THE PROFESSOR\nTime: %02d s   Exit: %.1f m\nWASD + mouse: move/look   E: grab/release   R: restart   Esc: mouse" % [int(round_time), exit_distance] + break_text
	if game_state == "playing": status_label.text = "Find the green EXIT. Move a wall if you need to."


func _find_path(from: Vector2i, to: Vector2i, avoid_blocks: bool) -> Array[Vector2i]:
	if from.x < 0 or from.y < 0 or to.x < 0 or to.y < 0: return []
	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary = {from: from}
	var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to: break
		for direction in directions:
			var next: Vector2i = current + direction
			if next.x < 0 or next.y < 0 or next.x >= MAZE_SIZE or next.y >= MAZE_SIZE: continue
			if not maze[next.y][next.x] or came_from.has(next): continue
			if avoid_blocks and movable_blocks.has(next) and next != to: continue
			came_from[next] = current
			queue.append(next)
	if not came_from.has(to): return []
	var result: Array[Vector2i] = []
	var current := to
	while current != from:
		result.push_front(current)
		current = came_from[current]
	result.push_front(from)
	return result


func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - (MAZE_SIZE - 1) * 0.5) * CELL_SIZE, 0.0, (cell.y - (MAZE_SIZE - 1) * 0.5) * CELL_SIZE)


func _world_to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(roundi(world_position.x / CELL_SIZE + (MAZE_SIZE - 1) * 0.5), roundi(world_position.z / CELL_SIZE + (MAZE_SIZE - 1) * 0.5))


func _xr_is_running() -> bool:
	return xr_interface != null and xr_interface.is_initialized() and get_viewport().use_xr


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R: _start_round()
		elif event.keycode == KEY_ESCAPE and not _xr_is_running(): Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
