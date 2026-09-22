extends Node3D
class_name ProfessorActor

## The professor is a self-contained actor: visuals, footsteps, route chasing,
## grace period, and the timed destruction of a blocking movable wall.

const SPEED := 1.6
const BREAK_TIME := 2.5
const GRACE_TIME := 2.0

var world: MazeWorld
var player: MazePlayer
var _material: Material
var _path: Array[Vector2i] = []
var _path_timer := 0.0
var _footstep_timer := 0.0
var _grace_timer := 0.0
var _break_cell := Vector2i(-1, -1)
var _break_timer := 0.0
var _audio: AudioStreamPlayer3D

const FACE_HEIGHT := 0.5
const FACE_OFFSET := 0.42


func setup(maze_world: MazeWorld, maze_player: MazePlayer, professor_material: Material) -> void:
	world = maze_world
	player = maze_player
	_material = professor_material
	if get_node_or_null("Body") == null:
		_build_visuals()
	if _audio == null:
		_create_audio()


func reset() -> void:
	if world == null or player == null:
		return
	_path.clear()
	_path_timer = 0.0
	_footstep_timer = 0.0
	_grace_timer = GRACE_TIME
	_break_cell = Vector2i(-1, -1)
	_break_timer = 0.0
	var cell := world.choose_professor_cell(MazeWorld.world_to_cell(_target_position()))
	global_position = MazeWorld.cell_to_world(cell) + Vector3.UP * 1.0


func tick(delta: float) -> void:
	if world == null or player == null:
		return
	_place_name_tag()
	if _grace_timer > 0.0:
		_grace_timer -= delta
		return
	if _break_timer > 0.0:
		_break_timer -= delta
		rotation.y += delta * 2.0
		if _break_timer <= 0.0:
			_destroy_block(_break_cell)
			_break_cell = Vector2i(-1, -1)
		return
	_footstep_timer -= delta
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = 0.22
		var from := MazeWorld.world_to_cell(global_position)
		var to := MazeWorld.world_to_cell(_target_position())
		_path = world.find_path(from, to, true)
		if _path.size() < 2:
			for cell in world.find_path(from, to, false):
				if world.block_at(cell) != null:
					_break_cell = cell
					_break_timer = BREAK_TIME
					break
	if _path.size() >= 2:
		var next_position := MazeWorld.cell_to_world(_path[1]) + Vector3.UP * 1.0
		global_position = global_position.move_toward(next_position, SPEED * delta)
		if _audio and _footstep_timer <= 0.0:
			_audio.play()
			_footstep_timer = 0.72


## Keeps the "PROFESSOR" tag on the face side that points at the player.
## top_level so the break-spin rotation doesn't swing it around.
func _place_name_tag() -> void:
	var tag := get_node_or_null("NameTag") as Label3D
	if tag == null:
		return
	var to_player := _target_position() - global_position
	to_player.y = 0.0
	var face_dir := to_player.normalized() if to_player.length() > 0.01 else Vector3.FORWARD
	tag.global_position = global_position + Vector3.UP * FACE_HEIGHT + face_dir * FACE_OFFSET


## Chase the player's head (floor-projected), not the XR play-area origin.
func _target_position() -> Vector3:
	return player.body_position()


func is_breaking() -> bool:
	return _break_timer > 0.0


func break_time_left() -> float:
	return maxf(_break_timer, 0.0)


func _destroy_block(cell: Vector2i) -> void:
	var block := world.block_at(cell)
	if block != null:
		world.remove_block(block)


func _build_visuals() -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.38
	body_mesh.height = 1.85
	body_mesh.material = _material
	body.mesh = body_mesh
	add_child(body)
	var hat := MeshInstance3D.new()
	hat.name = "Hat"
	var hat_mesh := CylinderMesh.new()
	hat_mesh.top_radius = 0.48
	hat_mesh.bottom_radius = 0.48
	hat_mesh.height = 0.18
	hat_mesh.material = _material
	hat.mesh = hat_mesh
	hat.position.y = 0.98
	add_child(hat)
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = "PROFESSOR"
	tag.font_size = 96
	tag.pixel_size = 0.0022
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.modulate = Color("#fff2c8")
	tag.outline_size = 24
	tag.outline_modulate = Color(0.25, 0.0, 0.03, 1.0)
	tag.top_level = true
	add_child(tag)
	var light := OmniLight3D.new()
	light.name = "ThreatLight"
	light.light_color = Color("#ff3a48")
	light.light_energy = 1.2
	light.omni_range = 3.0
	add_child(light)


func _create_audio() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "Footsteps"
	_audio.stream = Tone.make(92.0, 0.18, 0.20, 0.1)
	_audio.max_distance = MazeWorld.MAZE_SIZE * MazeWorld.CELL_SIZE
	_audio.unit_size = 1.0
	add_child(_audio)

