extends Node3D
class_name ProfessorActor

## The professor is a self-contained actor: visuals, footsteps, route chasing,
## grace period, and the timed destruction of a blocking movable wall.

const SPEED := 1.6
const BREAK_TIME := 2.5
const GRACE_TIME := 2.0
const WALKING_SOUND_PATH := "res://assets/audio/professor_walking.ogg"
const WALKING_SOUND_RADIUS := 6.0
const THREAT_RED := Color("#ff173d")
const THREAT_BLUE := Color("#315cff")

var world: MazeWorld
var player: MazePlayer
var _path: Array[Vector2i] = []
var _path_timer := 0.0
var _grace_timer := 0.0
var _break_cell := Vector2i(-1, -1)
var _break_timer := 0.0
var _audio: AudioStreamPlayer3D

## Blender-authored professor, exported facing front (glTF +Z).
const MODEL := preload("res://assets/models/professor/angry-professor.glb")
## Name tag floats just above the model's head (actor origin is at 1 m).
const TAG_HEIGHT := 1.05
const TURN_SPEED := 8.0


func setup(maze_world: MazeWorld, maze_player: MazePlayer) -> void:
	world = maze_world
	player = maze_player
	if get_node_or_null("Body") == null:
		_build_visuals()
	if _audio == null:
		_create_audio()


func reset() -> void:
	if world == null or player == null:
		return
	_path.clear()
	_path_timer = 0.0
	_grace_timer = GRACE_TIME
	_break_cell = Vector2i(-1, -1)
	_break_timer = 0.0
	_set_walking_audio(false)
	var cell := world.choose_professor_cell(MazeWorld.world_to_cell(_target_position()))
	global_position = MazeWorld.cell_to_world(cell) + Vector3.UP * 1.0
	_face_player(1.0)


func tick(delta: float) -> void:
	if world == null or player == null:
		return
	_place_name_tag()
	if _break_timer <= 0.0:
		_face_player(minf(TURN_SPEED * delta, 1.0))
	if _grace_timer > 0.0:
		_set_walking_audio(false)
		_grace_timer -= delta
		return
	if _break_timer > 0.0:
		_set_walking_audio(false)
		_break_timer -= delta
		rotation.y += delta * 2.0
		if _break_timer <= 0.0:
			_destroy_block(_break_cell)
			_break_cell = Vector2i(-1, -1)
		return
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
		var previous_position := global_position
		global_position = global_position.move_toward(next_position, SPEED * delta)
		_set_walking_audio(not global_position.is_equal_approx(previous_position))
	else:
		_set_walking_audio(false)


## Keeps the "PROFESSOR" tag above his head. top_level so the break-spin
## rotation doesn't swing it around.
func _place_name_tag() -> void:
	var tag := get_node_or_null("NameTag") as Label3D
	if tag == null:
		return
	tag.global_position = global_position + Vector3.UP * TAG_HEIGHT


## Turns the model's front (+Z) toward the player; weight 1.0 snaps.
func _face_player(weight: float) -> void:
	var to_player := _target_position() - global_position
	if Vector2(to_player.x, to_player.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(to_player.x, to_player.z), weight)


## Chase the player's head (floor-projected), not the XR play-area origin.
func _target_position() -> Vector3:
	return player.body_position()


func is_breaking() -> bool:
	return _break_timer > 0.0


func break_time_left() -> float:
	return maxf(_break_timer, 0.0)


## End-of-round hook used by main.gd. The professor stops ticking after a
## win/loss, so its looping walking sound must be stopped explicitly.
func stop_walking_audio() -> void:
	_set_walking_audio(false)


## Pulses the existing world-space light so XR players receive the same close
## warning as the desktop screen overlay.
func set_threat_warning(strength: float, flash: float) -> void:
	var light := get_node_or_null("ThreatLight") as OmniLight3D
	if light == null:
		return
	if strength <= 0.0:
		light.light_color = THREAT_RED
		light.light_energy = 1.2
		light.omni_range = 3.0
		return
	light.light_color = THREAT_RED.lerp(THREAT_BLUE, flash)
	light.light_energy = 1.2 + strength * lerpf(1.8, 5.0, absf(flash - 0.5) * 2.0)
	light.omni_range = 3.0 + strength * 3.0


func _destroy_block(cell: Vector2i) -> void:
	var block := world.block_at(cell)
	if block != null:
		world.remove_block(block)


func _build_visuals() -> void:
	var body := MODEL.instantiate() as Node3D
	body.name = "Body"
	# The model's feet are at its origin; the actor floats at 1 m.
	body.position.y = -1.0
	add_child(body)
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
	_audio.name = "ProfessorWalkingSound"
	var walking_stream := AudioStreamOggVorbis.load_from_file(WALKING_SOUND_PATH)
	walking_stream.loop = true
	_audio.stream = walking_stream
	_audio.max_distance = WALKING_SOUND_RADIUS
	_audio.unit_size = 1.0
	_audio.volume_db = -3.0
	add_child(_audio)


func _set_walking_audio(walking: bool) -> void:
	if _audio == null:
		return
	if walking and not _audio.playing:
		_audio.play()
	elif not walking and _audio.playing:
		_audio.stop()
