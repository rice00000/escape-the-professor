extends Node3D

## Escape the Professor: round orchestration.
## 123
## Everything with real behavior lives in game/ as a small node; this script
## wires them together, owns the round state, and writes the HUD text.
##   XRSession        brings up OpenXR, or leaves us in desktop mode
##   MazeWorld        the maze, its movable walls and the exit beacon
##   MazePlayer       moves the XROrigin3D while respecting the walls
##   ProfessorActor   the chaser
##   DesktopControls  keyboard/mouse play      XRLocomotion    headset play
##   XRRestartInput   A/X restart button       DesktopHud / XRHud  the two HUDs

enum State { PLAYING, WON, LOST }

const WIN_DISTANCE := 0.75
const CAUGHT_DISTANCE := 0.95
const THREAT_WARNING_DISTANCE := 4.5
const THREAT_FLASH_SPEED := 1.6
const LOSE_SOUND := preload("res://assets/audio/you_lose_fast.mp3")
const CONTROLS_HINT_SECONDS := 7.0
const CONTROLS_HINT := "Left stick: move  ·  Right stick: turn\nGrip: grab wall  ·  Hold A: restart"

@onready var _origin: XROrigin3D = $XROrigin3D
@onready var _xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var _left_controller: XRController3D = $XROrigin3D/XRControllerLeft
@onready var _right_controller: XRController3D = $XROrigin3D/XRControllerRight

var xr: XRSession
var world: MazeWorld
var player: MazePlayer
var professor: ProfessorActor
var desktop: DesktopControls
var xr_move: XRLocomotion
var xr_restart: XRRestartInput
var desktop_hud: DesktopHud
var xr_hud: XRHud
var lose_audio: AudioStreamPlayer

var state := State.PLAYING
var round_time := 0.0
var _threat_phase := 0.0
var _materials := Palette.build()
## The sticky (no timeout) XR toast currently requested, "" for none.
var _sticky_toast := ""


func _ready() -> void:
	_hide_template_demo()

	xr = XRSession.new()
	_add(xr, "XRSession")
	world = MazeWorld.new()
	_add(world, "MazeWorld")
	player = MazePlayer.new()
	_add(player, "MazePlayer")
	player.setup(_origin, world)
	professor = ProfessorActor.new()
	_add(professor, "Professor")

	desktop = DesktopControls.new()
	_add(desktop, "DesktopControls")
	desktop.setup(_origin, player, world)
	xr_move = XRLocomotion.new()
	_add(xr_move, "XRLocomotion")
	xr_move.setup(_origin, _xr_camera, _left_controller, _right_controller, player)
	xr_restart = XRRestartInput.new()
	_add(xr_restart, "XRRestartInput")
	xr_restart.setup(_left_controller, _right_controller)
	xr_restart.restart_requested.connect(_start_round)

	desktop_hud = DesktopHud.new()
	_add(desktop_hud, "DesktopHud")
	xr_hud = XRHud.new()
	_add(xr_hud, "XRHud")
	xr_hud.setup(_left_controller, _xr_camera)
	lose_audio = AudioStreamPlayer.new()
	lose_audio.stream = LOSE_SOUND
	_add(lose_audio, "LoseSound")

	_start_round()


func _add(node: Node, node_name: String) -> void:
	node.name = node_name
	add_child(node)


## The scene still carries the XR template's demo room. Hide it and take it
## out of physics; the maze replaces it.
func _hide_template_demo() -> void:
	for node_name in ["Floor", "Table", "Props", "PassthroughTutorialText"]:
		var node := get_node_or_null(node_name)
		if node == null:
			continue
		node.set("visible", false)
		for body in [node] + node.find_children("*", "CollisionObject3D", true, false):
			if body is CollisionObject3D:
				body.collision_layer = 0
				body.collision_mask = 0
	var template_movement := get_node_or_null("XROrigin3D/XRMovement")
	if template_movement:
		template_movement.set_process(false)


func _start_round() -> void:
	state = State.PLAYING
	round_time = 0.0
	lose_audio.stop()
	_threat_phase = 0.0
	_sticky_toast = ""
	desktop.release()
	desktop_hud.clear_result()
	world.build(randi(), _origin, _materials)
	_origin.global_position = MazeWorld.cell_to_world(MazeWorld.START_CELL)
	_origin.rotation = Vector3.ZERO
	professor.setup(world, player)
	professor.reset()
	xr_hud.show_toast(CONTROLS_HINT, CONTROLS_HINT_SECONDS)


func _process(delta: float) -> void:
	var xr_running := xr.is_running()
	desktop.enabled = not xr_running
	xr_restart.tick(delta, state == State.PLAYING)
	if state == State.PLAYING:
		_play_frame(delta, xr_running)
	_update_hud(delta, xr_running)


func _play_frame(delta: float, xr_running: bool) -> void:
	round_time += delta
	if xr_running:
		xr_move.tick(delta)
	else:
		desktop.tick(delta)
	professor.tick(delta)

	var body := player.body_position()
	var exit_distance := body.distance_to(world.exit_node.global_position)
	world.exit_pulse.tick(delta, exit_distance)
	if exit_distance < WIN_DISTANCE:
		_finish_round(State.WON)
	elif _floor_distance(body, professor.global_position) < CAUGHT_DISTANCE:
		_finish_round(State.LOST)


## Enter an end state once, leaving this node processing so the HUD and
## restart controls still work while every gameplay object is frozen.
func _finish_round(result: State) -> void:
	if state != State.PLAYING:
		return
	state = result
	desktop.release()
	for block in world.blocks:
		if is_instance_valid(block):
			block.lock_for_round_end()
	professor.stop_walking_audio()
	world.exit_pulse.stop()
	if result == State.WON:
		world.exit_pulse.play()
	else:
		lose_audio.play()
	desktop_hud.show_result(_status_text(false), result == State.WON)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_start_round()


# --- HUD -------------------------------------------------------------------

func _update_hud(delta: float, xr_running: bool) -> void:
	_update_threat_warning(delta)
	var time_text := "%02d" % int(round_time)
	var exit_text := "%.1f" % _exit_distance()
	var breaking := _breaking_text()
	var info := "ESCAPE THE PROFESSOR\nTime: %s s   Exit: %s m\nWASD + mouse: move/look   E: grab/release   R: restart   Esc: mouse" % [time_text, exit_text]
	if not breaking.is_empty():
		info += "\n" + breaking
	desktop_hud.set_text(info, _status_text(xr_running))

	xr_hud.set_status_text(time_text + "s", exit_text + "m")
	_set_sticky_toast(_toast_text(xr_running))
	xr_hud.update(delta, xr_running)


## A close professor creates a siren-like red/blue pulse. Desktop gets a
## translucent screen flash; XR sees the professor's world-space threat light.
func _update_threat_warning(delta: float) -> void:
	var strength := 0.0
	if state == State.PLAYING:
		var distance := _floor_distance(player.body_position(), professor.global_position)
		strength = clampf(
			(THREAT_WARNING_DISTANCE - distance) / (THREAT_WARNING_DISTANCE - CAUGHT_DISTANCE),
			0.0,
			1.0
		)
	if strength > 0.0:
		_threat_phase = fmod(_threat_phase + delta * TAU * THREAT_FLASH_SPEED, TAU)
	else:
		_threat_phase = 0.0
	var flash := (sin(_threat_phase) + 1.0) * 0.5
	desktop_hud.set_threat_warning(strength, flash)
	professor.set_threat_warning(strength, flash)


## The one-line round status shown on the desktop HUD and, once the round is
## over, as the XR toast.
func _status_text(xr_running: bool) -> String:
	var restart := "Press A/X" if xr_running else "Press R"
	match state:
		State.WON:
			return "ESCAPED! %s for a new maze" % restart
		State.LOST:
			return "YOU LOSE! GO BACK TO CLASS — %s to retry" % restart
	return "Find the green EXIT. Move a wall if you need to."


## What the sticky XR toast should say right now. Highest priority first:
## round result, restart-hold progress, then the professor's wall breaking.
func _toast_text(xr_running: bool) -> String:
	if state != State.PLAYING:
		return _status_text(xr_running)
	var progress := xr_restart.hold_progress()
	if progress > 0.0:
		var filled := int(round(progress * 5.0))
		return "Restarting... " + "#".repeat(filled) + "-".repeat(5 - filled)
	return _breaking_text()


func _breaking_text() -> String:
	if professor.is_breaking():
		return "Professor is breaking a wall  %.1fs" % professor.break_time_left()
	return ""


## Shows `text` as a sticky toast, or clears the toast when it becomes "".
## Only talks to XRHud when the text changes, so timed toasts such as the
## controls hint are left alone in between.
func _set_sticky_toast(text: String) -> void:
	if text == _sticky_toast:
		return
	_sticky_toast = text
	if text.is_empty():
		xr_hud.clear_toast()
	else:
		xr_hud.show_toast(text, 0.0)


# --- Helpers ---------------------------------------------------------------

func _exit_distance() -> float:
	return player.body_position().distance_to(world.exit_node.global_position)


## Distance ignoring height: the professor floats above the floor while the
## player's body position sits on it.
func _floor_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
