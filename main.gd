## Escape the Professor
## Runtime-only prototype built on the XR template's existing OpenXR origin.
## The maze is deliberately made from primitive meshes so every round can differ.

extends Node3D

var xr_interface: OpenXRInterface
@export var target_refresh_rate := 72.0

const MAZE_SIZE := 15
const CELL_SIZE := 1.65
const WALL_HEIGHT := 2.45
const PLAYER_HEIGHT := 1.6
const PROFESSOR_SPEED := 1.6
const BREAK_TIME := 2.5
const PROFESSOR_GRACE_TIME := 2.0

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
var professor_grace_timer := 0.0
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
var player_collision: MazePlayer
var held_desktop_block: GrabbableWall
var desktop_hold_transform := Transform3D.IDENTITY
var camera_pitch := 0.0
var last_e_down := false

var floor_material: StandardMaterial3D
var wall_material: StandardMaterial3D
var movable_material: StandardMaterial3D
var professor_material: StandardMaterial3D
var exit_material: StandardMaterial3D
var ceiling_material: StandardMaterial3D
var fluorescent_material: StandardMaterial3D
var wood_seam_material: StandardMaterial3D


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
	floor_material = _material(Color("#765035"), 0.82)
	wood_seam_material = _material(Color("#3d281d"), 0.9)
	wall_material = _material(Color("#756b59"), 0.68)
	movable_material = _material(Color("#b76c39"), 0.3)
	professor_material = _material(Color("#a62936"), 0.28)
	exit_material = _material(Color("#54e4be"), 0.08, true)
	ceiling_material = _material(Color("#cbc3ad"), 0.88)
	fluorescent_material = _material(Color("#d9f6ff"), 0.24, true)


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
	player_collision = MazePlayer.new()
	player_collision.name = "MazePlayer"
	add_child(player_collision)
	player_collision.setup(player_origin, desktop_camera, maze, movable_blocks, MAZE_SIZE, CELL_SIZE)


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
	professor_grace_timer = PROFESSOR_GRACE_TIME
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
	# Make the starting pocket a readable two-way junction. This gives the
	# player an immediate choice and leaves a side branch for the professor.
	maze[1][2] = true
	maze[2][1] = true
	# A few opened wall cells turn the perfect maze into a maze with loops and
	# alternate escapes. Keep the openings sparse so the corridors still feel
	# tense and legible.
	for row in range(1, MAZE_SIZE - 1):
		for col in range(1, MAZE_SIZE - 1):
			if maze[row][col]:
				continue
			var horizontal_wall := row % 2 == 1 and col % 2 == 0
			var vertical_wall := row % 2 == 0 and col % 2 == 1
			if horizontal_wall and maze[row][col - 1] and maze[row][col + 1] and randf() < 0.24:
				maze[row][col] = true
			elif vertical_wall and maze[row - 1][col] and maze[row + 1][col] and randf() < 0.24:
				maze[row][col] = true
	maze[MAZE_SIZE - 2][MAZE_SIZE - 2] = true


func _build_maze() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "MazeFloor"
	floor_body.add_to_group("maze_floor")
	maze_root.add_child(floor_body)
	_add_box(floor_body, Vector3(MAZE_SIZE * CELL_SIZE, 0.1, MAZE_SIZE * CELL_SIZE), Vector3.ZERO, floor_material, false)
	_add_wood_floor_detail()
	_add_ceiling_and_lights()
	for row in MAZE_SIZE:
		for col in MAZE_SIZE:
			if not maze[row][col]:
				var wall := StaticBody3D.new()
				wall.name = "Wall_%d_%d" % [col, row]
				wall.add_to_group("maze_wall")
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
	var block := GrabbableWall.new()
	block.name = "MovableWall_%d_%d" % [cell.x, cell.y]
	block.position = _cell_to_world(cell) + Vector3.UP * (WALL_HEIGHT * 0.5)
	block.mass = 4.0
	block.freeze = false
	block.add_to_group("grabbable")
	block.add_to_group("movable_wall")
	block.set_meta("player_origin", player_origin)
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


func _add_wood_floor_detail() -> void:
	# Thin seams sell the plank floor while keeping the walkable surface flat.
	for index in range(-MAZE_SIZE / 2, MAZE_SIZE / 2 + 1):
		var seam := MeshInstance3D.new()
		var seam_mesh := BoxMesh.new()
		seam_mesh.size = Vector3(MAZE_SIZE * CELL_SIZE, 0.012, 0.022)
		seam_mesh.material = wood_seam_material
		seam.mesh = seam_mesh
		seam.position = Vector3(0.0, 0.058, index * CELL_SIZE)
		maze_root.add_child(seam)
	for index in range(-MAZE_SIZE / 2, MAZE_SIZE / 2 + 1):
		var seam := MeshInstance3D.new()
		var seam_mesh := BoxMesh.new()
		seam_mesh.size = Vector3(0.022, 0.013, MAZE_SIZE * CELL_SIZE)
		seam_mesh.material = wood_seam_material
		seam.mesh = seam_mesh
		seam.position = Vector3(index * CELL_SIZE, 0.059, 0.0)
		maze_root.add_child(seam)


func _add_ceiling_and_lights() -> void:
	var ceiling_body := StaticBody3D.new()
	ceiling_body.name = "SchoolCeiling"
	ceiling_body.add_to_group("maze_wall")
	maze_root.add_child(ceiling_body)
	var map_span := MAZE_SIZE * CELL_SIZE + CELL_SIZE * 0.8
	_add_box(ceiling_body, Vector3(map_span, 0.14, map_span), Vector3(0.0, WALL_HEIGHT + 0.68, 0.0), ceiling_material, false)
	# Repeated cool fixtures create the flat, institutional backrooms feeling.
	var fixture_cells := [-5, 0, 5]
	for row in fixture_cells:
		for col in fixture_cells:
			var fixture := MeshInstance3D.new()
			var fixture_mesh := BoxMesh.new()
			fixture_mesh.size = Vector3(CELL_SIZE * 1.25, 0.055, CELL_SIZE * 0.28)
			fixture_mesh.material = fluorescent_material
			fixture.mesh = fixture_mesh
			fixture.position = Vector3(col * CELL_SIZE, WALL_HEIGHT + 0.58, row * CELL_SIZE)
			maze_root.add_child(fixture)
			var light := OmniLight3D.new()
			light.light_color = Color("#d8efff")
			light.light_energy = 2.1
			light.omni_range = CELL_SIZE * 3.5
			light.shadow_enabled = false
			light.position = fixture.position + Vector3.DOWN * 0.16
			maze_root.add_child(light)


func _place_player_and_professor() -> void:
	var start_cell := Vector2i(1, 1)
	if player_origin:
		player_origin.global_position = _cell_to_world(start_cell)
		player_origin.rotation = Vector3.ZERO
	var professor_cell := _choose_professor_cell(start_cell)
	# Keep the origin level; tilting the origin would also tilt the desktop
	# camera and XR headset. The professor remains comfortably inside the view.
	var professor_target := _cell_to_world(professor_cell)
	if player_origin:
		# Face the professor down the open starting branch so desktop and XR
		# players see the threat immediately after a new round starts.
		player_origin.look_at(professor_target, Vector3.UP)
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


func _choose_professor_cell(start_cell: Vector2i) -> Vector2i:
	var exit_cell := Vector2i(MAZE_SIZE - 2, MAZE_SIZE - 2)
	var player_exit_path := _find_path(start_cell, exit_cell, false)
	var candidates: Array[Vector2i] = []
	# Cardinal cells keep line of sight unambiguous in the narrow corridors.
	for cell in [Vector2i(3, 1), Vector2i(1, 3), Vector2i(4, 1), Vector2i(1, 4), Vector2i(5, 1), Vector2i(1, 5)]:
		if cell.x < 0 or cell.y < 0 or cell.x >= MAZE_SIZE or cell.y >= MAZE_SIZE:
			continue
		if not maze[cell.y][cell.x] or player_exit_path.has(cell):
			continue
		if _has_grid_line_of_sight(start_cell, cell):
			candidates.append(cell)
	if not candidates.is_empty():
		return candidates[randi_range(0, candidates.size() - 1)]
	# The generated starting pocket should make the branch candidates above
	# available. Keep a safe fallback for unusual future generator changes.
	for cell in [Vector2i(2, 1), Vector2i(1, 2)]:
		if maze[cell.y][cell.x] and not player_exit_path.has(cell):
			return cell
	return Vector2i(MAZE_SIZE - 2, 1)


func _has_grid_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	if from.x != to.x and from.y != to.y:
		return false
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var cursor := from + step
	while cursor != to:
		if not maze[cursor.y][cursor.x]:
			return false
		cursor += step
	return maze[to.y][to.x]


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
	_sync_movable_block_cells()
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
		direction = _desktop_movement_direction(input)
	else:
		var camera := get_node_or_null("XROrigin3D/XRCamera3D") as Node3D
		var basis := camera.global_transform.basis if camera else player_origin.global_transform.basis
		direction = basis.x * input.x - basis.z * input.y
	direction.y = 0.0
	if direction.length() > 0.01: _try_move_player(direction.normalized() * 2.35 * delta)


func _desktop_movement_direction(input: Vector2) -> Vector3:
	var basis := player_origin.global_transform.basis
	# Input.get_vector uses negative Y for W. Multiplying by +Z makes W
	# follow Godot's forward (-Z) direction instead of walking backward.
	return basis.x * input.x + basis.z * input.y


func _try_move_player(offset: Vector3) -> void:
	if player_collision:
		player_collision.try_move(offset, held_desktop_block)


func _is_walkable(world_position: Vector3) -> bool:
	return player_collision == null or player_collision.is_walkable(world_position, held_desktop_block)


func _handle_desktop_grab() -> void:
	if _xr_is_running() or player_origin == null: return
	var down := Input.is_key_pressed(KEY_E)
	if down and not last_e_down:
		if held_desktop_block:
			# The release remains latched until the block has room away from the
			# player. This prevents an easy E press from trapping the player.
			if _prepare_desktop_drop() and held_desktop_block.drop_with_velocity(Vector3.ZERO):
				held_desktop_block = null
		else:
			held_desktop_block = _nearest_block(2.4)
			if held_desktop_block and held_desktop_block.begin_hold():
				desktop_hold_transform = held_desktop_block.global_transform
	last_e_down = down
	if held_desktop_block and is_instance_valid(held_desktop_block):
		var target := desktop_camera.global_transform
		target.origin = desktop_camera.global_position - desktop_camera.global_transform.basis.z * 1.25
		if held_desktop_block.set_held_transform(target):
			desktop_hold_transform = target
		else:
			# Keep the most recent clear pose when the camera faces a solid wall.
			held_desktop_block.global_transform = desktop_hold_transform


func _prepare_desktop_drop() -> bool:
	if held_desktop_block == null or player_origin == null:
		return false
	var start := _world_to_cell(held_desktop_block.global_position)
	var candidates := [start, start + Vector2i.RIGHT, start + Vector2i.LEFT, start + Vector2i.DOWN, start + Vector2i.UP]
	for cell in candidates:
		if cell.x < 0 or cell.y < 0 or cell.x >= MAZE_SIZE or cell.y >= MAZE_SIZE:
			continue
		if not maze[cell.y][cell.x] or (movable_blocks.has(cell) and movable_blocks[cell] != held_desktop_block):
			continue
		var center := _cell_to_world(cell) + Vector3.UP * (WALL_HEIGHT * 0.5)
		var horizontal := Vector2(center.x - player_origin.global_position.x, center.z - player_origin.global_position.z)
		if horizontal.length() < 1.32:
			continue
		var candidate := desktop_hold_transform
		candidate.origin = center
		if held_desktop_block.set_held_transform(candidate):
			desktop_hold_transform = candidate
			return true
	return false


func _sync_movable_block_cells() -> void:
	var remaps: Array[Array] = []
	var occupied: Dictionary = {}
	for cell in movable_blocks.keys():
		var block := movable_blocks[cell] as GrabbableWall
		if block == null or block.held:
			continue
		var new_cell := _world_to_cell(block.global_position)
		if new_cell == cell or occupied.has(new_cell):
			occupied[cell] = block
			continue
		if new_cell.x < 0 or new_cell.y < 0 or new_cell.x >= MAZE_SIZE or new_cell.y >= MAZE_SIZE or not maze[new_cell.y][new_cell.x]:
			continue
		if movable_blocks.has(new_cell) and movable_blocks[new_cell] != block:
			continue
		occupied[new_cell] = block
		remaps.append([cell, new_cell, block])
	for remap in remaps:
		movable_blocks.erase(remap[0])
		movable_blocks[remap[1]] = remap[2]


func _nearest_block(max_distance: float) -> GrabbableWall:
	var best: GrabbableWall
	var best_distance := max_distance
	if desktop_camera == null:
		return best
	var camera_position := desktop_camera.global_position
	var camera_forward := -desktop_camera.global_transform.basis.z
	for block in movable_blocks.values():
		if block is GrabbableWall and is_instance_valid(block):
			var to_block: Vector3 = block.global_position - camera_position
			var distance: float = to_block.length()
			var facing: float = camera_forward.dot(to_block.normalized()) if distance > 0.01 else 1.0
			if facing < 0.25 or distance > max_distance:
				continue
			if distance < best_distance:
				best = block
				best_distance = distance
	return best


func _update_professor(delta: float) -> void:
	if professor == null or player_origin == null: return
	if professor_grace_timer > 0.0:
		professor_grace_timer -= delta
		return
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
