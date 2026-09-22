extends Node3D

## Round orchestration for Escape the Professor.
## World construction and actor behavior live in game/; this node owns input,
## XR setup, HUD, round state, and the desktop fallback.

var xr_interface: OpenXRInterface
@export var target_refresh_rate := 72.0

const PLAYER_HEIGHT := 1.6
const PLAYER_SPEED := 2.35
## Degrees rotated per right-stick snap turn (Task 1).
const SNAP_TURN_DEGREES := 30.0
const SNAP_TURN_DEADZONE_ON := 0.6
const SNAP_TURN_DEADZONE_OFF := 0.3
## Seconds the A/X button must be held during play before it restarts the round.
const RESTART_HOLD_SECONDS := 1.0

var maze_world: MazeWorld
var maze: Array = []
var movable_blocks: Dictionary = {}
var block_cells: Array[Vector2i] = []
var professor: ProfessorActor
var exit_audio: AudioStreamPlayer3D
var pulse_timer := 0.0
var round_time := 0.0
var game_state := "playing"

var desktop_camera: Camera3D
var hud: Label
var status_label: Label
var xr_hud: XRHud
var player_origin: XROrigin3D
var player_collision: MazePlayer
var held_desktop_block: GrabbableWall
var desktop_hold_transform := Transform3D.IDENTITY
var camera_pitch := 0.0
var last_e_down := false
var xrinput_log_timer := 0.0

## Right-stick snap turn latch (Task 1): true while |stick.x| is above the
## "on" deadzone, so holding the stick over only fires one turn. Cleared once
## the stick returns below the "off" deadzone.
var _right_turn_latched := false
var _turn_count := 0
var _last_turn_direction := "none"

## A/X restart-hold state (Task 2).
var _restart_button_was_pressed := false
var _restart_holding := false
var _restart_hold_time := 0.0

## Tracks whether the "professor is breaking a wall" toast is the one
## currently showing, so we know when to clear it (and not stomp on some
## other toast that started showing in the meantime).
var _professor_toast_active := false

## Distance (meters, after XRServer.world_scale) between thumb tip and index
## tip below which a hand counts as "pinching" for the walk-forward fallback.
## Matches the pinch/release band scripts/xr_grab_hands.gd already uses for
## grabbing walls, so the gesture feels consistent across the game.
const HAND_WALK_PINCH_DISTANCE := 0.028

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
	# Quest's OpenXR runtime can become ready just after the Android activity
	# starts. Defer initialization so we do not incorrectly fall back to desktop mode.
	call_deferred("_try_initialize_openxr")
	_hide_template_demo()
	_setup_materials()
	_setup_desktop_camera()
	_setup_hud()
	_setup_xr_hud()
	professor = ProfessorActor.new()
	professor.name = "Professor"
	add_child(professor)
	_start_round()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _try_initialize_openxr() -> void:
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null:
		print("EscapeTheProfessor|INFO: OpenXR is unavailable; desktop mode enabled")
		return
	# Quest included: the interface must be initialized explicitly, otherwise
	# Godot never submits frames and the headset stays on its loading dots.
	# initialize() fails while the runtime reports the headset as not worn, so
	# retry for a few seconds before falling back to desktop mode.
	for attempt in 12:
		if xr_interface.is_initialized():
			_enable_openxr()
			return
		if xr_interface.initialize():
			print("EscapeTheProfessor|INFO: OpenXR initialize() succeeded on attempt %d" % (attempt + 1))
			_enable_openxr()
			return
		print("EscapeTheProfessor|WARN: OpenXR initialize() failed on attempt %d" % (attempt + 1))
		await get_tree().create_timer(0.5).timeout
	print("EscapeTheProfessor|INFO: no headset runtime; desktop mode enabled")


func _enable_openxr() -> void:
	print("EscapeTheProfessor|INFO: OpenXR initialized")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_viewport().use_xr = true
	if not xr_interface.session_begun.is_connected(_on_session_begun):
		xr_interface.session_begun.connect(_on_session_begun)
	# session_begun can fire before we connect to it on Quest, so show the
	# controls hint as soon as XR rendering is switched on as well.
	_show_controls_hint_toast()


func _on_session_begun() -> void:
	var rates := xr_interface.get_available_display_refresh_rates()
	if target_refresh_rate in rates:
		xr_interface.display_refresh_rate = target_refresh_rate
	elif not rates.is_empty():
		print("EscapeTheProfessor|WARN: requested refresh rate unavailable: ", rates)
	var actual := xr_interface.display_refresh_rate
	if actual > 0.0:
		Engine.physics_ticks_per_second = int(round(actual))
	# Session just came alive inside the headset; give the player the control
	# hint here too (in addition to _start_round()), since the very first
	# _start_round() call during _ready() usually runs before OpenXR finishes
	# initializing and _xr_is_running() is still false at that point.
	_show_controls_hint_toast()


## Bilingual controls reminder shown for a few seconds at round start.
func _show_controls_hint_toast() -> void:
	if xr_hud == null or not _xr_is_running():
		return
	xr_hud.show_toast("Left stick: move  ·  Right stick: turn\nGrip: grab wall  ·  Hold A: restart", 7.0)


func _hide_template_demo() -> void:
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
		movement.set_process(false)


func _setup_materials() -> void:
	floor_material = _material(Color("#765035"), 0.82)
	wood_seam_material = _material(Color("#3d281d"), 0.9)
	wall_material = _material(Color("#756b59"), 0.68)
	# GrabbableWall supplies a per-held transparent duplicate of this opaque
	# material, so resting blocks stay solid and held blocks render through.
	movable_material = _material(Color("#b76c39"), 0.3)
	professor_material = _material(Color("#a62936"), 0.28)
	exit_material = _material(Color("#54e4be"), 0.08, true)
	ceiling_material = _material(Color("#cbc3ad"), 0.88)
	fluorescent_material = _material(Color("#d9f6ff"), 0.24, true)


func _material(color: Color, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material


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


## CanvasLayer HUDs never render inside the headset, so XR gets its own HUD:
## a wrist "watch" panel plus a world-space toast, both owned by the XRHud
## helper node (game/xr_hud.gd). See _update_xr_hud() for the per-frame feed
## and _update_xr_toasts()/_check_end_conditions()/etc. for toast triggers.
func _setup_xr_hud() -> void:
	var left_controller := get_node_or_null("XROrigin3D/XRControllerLeft") as XRController3D
	var camera := get_node_or_null("XROrigin3D/XRCamera3D") as XRCamera3D
	xr_hud = XRHud.new()
	xr_hud.name = "XRHud"
	add_child(xr_hud)
	xr_hud.setup(left_controller, camera)


func _start_round() -> void:
	var seed_value := randi()
	round_time = 0.0
	game_state = "playing"
	if maze_world and is_instance_valid(maze_world):
		maze_world.queue_free()
	maze_world = MazeWorld.new()
	maze_world.name = "MazeWorld"
	add_child(maze_world)
	maze_world.build(seed_value, player_origin, {
		"floor": floor_material,
		"wall": wall_material,
		"movable": movable_material,
		"exit": exit_material,
		"ceiling": ceiling_material,
		"fluorescent": fluorescent_material,
		"wood_seam": wood_seam_material,
	})
	maze = maze_world.maze
	movable_blocks = maze_world.movable_blocks
	block_cells = maze_world.block_cells
	if player_collision:
		player_collision.setup(player_origin, desktop_camera, maze, movable_blocks, MazeWorld.MAZE_SIZE, MazeWorld.CELL_SIZE)
	if player_origin:
		player_origin.global_position = _cell_to_world(Vector2i(1, 1))
		player_origin.rotation = Vector3.ZERO
	if professor:
		professor.setup(maze_world, player_origin, professor_material)
		professor.reset()
	_create_exit_audio()
	_professor_toast_active = false
	_show_controls_hint_toast()
	_update_hud()


func _create_exit_audio() -> void:
	if exit_audio and is_instance_valid(exit_audio):
		exit_audio.queue_free()
	exit_audio = AudioStreamPlayer3D.new()
	exit_audio.name = "ExitMusicalPulse"
	exit_audio.stream = _tone_stream(660.0, 0.22, 0.16, 0.0)
	exit_audio.max_distance = MazeWorld.MAZE_SIZE * MazeWorld.CELL_SIZE * 1.4
	exit_audio.unit_size = 1.5
	maze_world.exit_node.add_child(exit_audio)


func _tone_stream(frequency: float, duration: float, volume: float, second_frequency: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var time := float(i) / rate
		var envelope := minf(1.0, time * 40.0) * minf(1.0, (duration - time) * 16.0)
		var value := sin(TAU * frequency * time)
		if second_frequency > 0.0:
			value = (value + sin(TAU * second_frequency * time) * 0.35) / 1.35
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
	_handle_xr_restart_input(delta)
	if game_state != "playing":
		_update_hud()
		_update_xr_toasts()
		_update_xr_hud(delta)
		return
	round_time += delta
	_handle_desktop_look()
	_handle_player_movement(delta)
	_handle_desktop_grab()
	_sync_movable_block_cells()
	if professor:
		professor.tick(delta)
	_update_exit_audio(delta)
	_check_end_conditions()
	_update_xr_toasts()
	_update_hud()
	_update_xr_hud(delta)


func _handle_desktop_look() -> void:
	if desktop_camera == null or _xr_is_running():
		return
	if Input.is_key_pressed(KEY_ESCAPE):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not _xr_is_running() and desktop_camera:
		var motion := event as InputEventMouseMotion
		player_origin.rotate_y(-motion.relative.x * 0.0024)
		camera_pitch = clampf(camera_pitch - motion.relative.y * 0.0024, -1.25, 1.25)
		desktop_camera.rotation.x = camera_pitch


func _handle_player_movement(delta: float) -> void:
	if player_origin == null:
		return
	if not _xr_is_running():
		var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_key_pressed(KEY_A): input.x -= 1.0
		if Input.is_key_pressed(KEY_D): input.x += 1.0
		if Input.is_key_pressed(KEY_W): input.y -= 1.0
		if Input.is_key_pressed(KEY_S): input.y += 1.0
		if input.length() < 0.1:
			return
		input = input.limit_length(1.0)
		var desktop_basis := player_origin.global_transform.basis
		var direction := desktop_basis.x * input.x + desktop_basis.z * input.y
		direction.y = 0.0
		if direction.length() > 0.01:
			_try_move_player(direction.normalized() * PLAYER_SPEED * delta)
		return
	_handle_xr_player_movement(delta)


## XR movement: left thumbstick drives walking, a hand-pinch "walk forward"
## gesture covers hand-tracking mode with no controllers held, and the right
## thumbstick is turn-only (see _handle_xr_snap_turn()) rather than a
## movement fallback, so it can't fight the snap turn.
func _handle_xr_player_movement(delta: float) -> void:
	var left_controller := get_node_or_null("XROrigin3D/XRControllerLeft") as XRController3D
	var right_controller := get_node_or_null("XROrigin3D/XRControllerRight") as XRController3D
	var left_stick := left_controller.get_vector2("primary") if left_controller else Vector2.ZERO
	var right_stick := right_controller.get_vector2("primary") if right_controller else Vector2.ZERO
	var left_pinch := _hand_pinch_value(0)
	var right_pinch := _hand_pinch_value(1)

	_handle_xr_snap_turn(delta, right_controller, right_stick)

	var input := Vector2.ZERO
	var hand_forward := false
	var source := "none"
	if left_stick.length() >= 0.1:
		input = left_stick
		source = "left_stick"
	elif left_pinch > 0.5 or right_pinch > 0.5:
		hand_forward = true
		source = "hand"

	xrinput_log_timer += delta
	if xrinput_log_timer >= 2.0:
		xrinput_log_timer = 0.0
		print("EscapeTheProfessor|XRINPUT: left_active=%s right_active=%s left_primary=%s right_primary=%s left_pinch=%.2f right_pinch=%.2f source=%s last_turn=%s turn_count=%d" % [
			left_controller.get_is_active() if left_controller else false,
			right_controller.get_is_active() if right_controller else false,
			left_stick, right_stick, left_pinch, right_pinch, source, _last_turn_direction, _turn_count])

	var camera := get_node_or_null("XROrigin3D/XRCamera3D") as Node3D
	var xr_basis := camera.global_transform.basis if camera else player_origin.global_transform.basis
	var direction: Vector3
	if hand_forward:
		direction = -xr_basis.z
	else:
		if input.length() < 0.1:
			return
		input = input.limit_length(1.0)
		direction = xr_basis.x * input.x - xr_basis.z * input.y
	direction.y = 0.0
	if direction.length() > 0.01:
		_try_move_player(direction.normalized() * PLAYER_SPEED * delta)


## Pinch strength for a hand-tracked walk-forward gesture, reusing the same
## tracker lookup and thumb/index fingertip distance check that
## scripts/xr_grab_hands.gd already relies on for grabbing walls. Returns 1.0
## while pinching, 0.0 otherwise (0.0 also covers "not currently hand
## tracked", e.g. controllers are awake).
func _hand_pinch_value(hand_index: int) -> float:
	var tracker := XRServer.get_tracker(XRHandVisuals.HAND_TRACKERS[hand_index]) as XRHandTracker
	if tracker == null or not tracker.get_has_tracking_data():
		return 0.0
	var source := tracker.get_hand_tracking_source()
	if source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER or source == XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED:
		return 0.0
	var thumb := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
	var index := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	var distance := thumb.distance_to(index) * XRServer.world_scale
	return 1.0 if distance < HAND_WALK_PINCH_DISTANCE else 0.0


## Right-stick snap turn (Task 1). Rotates XROrigin3D around the camera's
## global position projected onto the origin's floor height, so the player's
## feet don't slide, matching the pivot math scripts/xr_move.gd already used
## for its (disabled) snap turn.
func _handle_xr_snap_turn(delta: float, right_controller: XRController3D, right_stick: Vector2) -> void:
	if player_origin == null or right_controller == null:
		return
	var x := right_stick.x
	if absf(x) < SNAP_TURN_DEADZONE_OFF:
		_right_turn_latched = false
		return
	if absf(x) < SNAP_TURN_DEADZONE_ON or _right_turn_latched:
		return
	_right_turn_latched = true
	var camera := get_node_or_null("XROrigin3D/XRCamera3D") as Node3D
	var pivot := camera.global_position if camera else player_origin.global_position
	pivot.y = player_origin.global_position.y
	var angle := deg_to_rad(SNAP_TURN_DEGREES) * -signf(x)
	var t := player_origin.global_transform
	t = t.translated(-pivot)
	t = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * t
	t = t.translated(pivot)
	player_origin.global_transform = t
	_turn_count += 1
	_last_turn_direction = "right" if x > 0.0 else "left"
	print("EscapeTheProfessor|XRINPUT: snap turn fired direction=%s count=%d stick_x=%.2f" % [_last_turn_direction, _turn_count, x])


## A/X restart parity for keyboard R (Task 2). Both controllers count, since
## the action works on either hand. While "playing", the button must be held
## for RESTART_HOLD_SECONDS, with progress mirrored on the toast HUD; on
## "won"/"lost" a single press restarts immediately.
func _handle_xr_restart_input(delta: float) -> void:
	if not _xr_is_running():
		return
	var left_controller := get_node_or_null("XROrigin3D/XRControllerLeft") as XRController3D
	var right_controller := get_node_or_null("XROrigin3D/XRControllerRight") as XRController3D
	var pressed := (left_controller != null and left_controller.get_is_active() and left_controller.is_button_pressed("ax_button")) \
		or (right_controller != null and right_controller.get_is_active() and right_controller.is_button_pressed("ax_button"))

	if game_state != "playing":
		if pressed and not _restart_button_was_pressed:
			_start_round()
		_restart_holding = false
		_restart_hold_time = 0.0
		_restart_button_was_pressed = pressed
		return

	if pressed:
		_restart_hold_time += delta
		_restart_holding = true
		var progress := clampf(_restart_hold_time / RESTART_HOLD_SECONDS, 0.0, 1.0)
		if xr_hud:
			xr_hud.show_toast(_restart_progress_text(progress), 0.0)
		if _restart_hold_time >= RESTART_HOLD_SECONDS:
			_restart_hold_time = 0.0
			_restart_holding = false
			_restart_button_was_pressed = false
			_start_round()
			return
	elif _restart_holding:
		_restart_holding = false
		_restart_hold_time = 0.0
		if xr_hud:
			xr_hud.clear_toast()
	_restart_button_was_pressed = pressed


func _restart_progress_text(progress: float) -> String:
	var filled := int(round(progress * 5.0))
	var bar := "#".repeat(filled) + "-".repeat(5 - filled)
	return "Restarting... %s" % bar


## Toasts that are driven by ongoing game state rather than a one-shot event:
## the professor-breaking-a-wall status. Restart-hold owns the toast while
## it's active (see _handle_xr_restart_input()), so this backs off then.
func _update_xr_toasts() -> void:
	if xr_hud == null or not _xr_is_running():
		return
	if _restart_holding:
		return
	if game_state == "playing" and professor and professor.is_breaking():
		xr_hud.show_toast("Professor is breaking a wall  %.1fs" % professor.break_time_left(), 0.0)
		_professor_toast_active = true
	elif _professor_toast_active:
		xr_hud.clear_toast()
		_professor_toast_active = false


## Feeds the wrist panel + fallback toast their shared status text (same
## source data as the desktop HUD's timer/exit-distance line) and lets the
## XRHud node advance its own follow/fade animation.
func _update_xr_hud(delta: float) -> void:
	if xr_hud == null:
		return
	xr_hud.set_status_text("%02ds" % int(round_time), "%.1fm" % _exit_distance())
	xr_hud.update(delta, _xr_is_running())


func _exit_distance() -> float:
	if player_origin and maze_world and maze_world.exit_node:
		return _body_position().distance_to(maze_world.exit_node.global_position)
	return 0.0


func _restart_prompt() -> String:
	return "Press A/X" if _xr_is_running() else "Press R"


## Forwarding API onto the XRHud toast (Task 3b). seconds <= 0 is sticky.
func _show_toast(text: String, seconds: float) -> void:
	if xr_hud:
		xr_hud.show_toast(text, seconds)


func _clear_toast() -> void:
	if xr_hud:
		xr_hud.clear_toast()


func _try_move_player(offset: Vector3) -> void:
	if player_collision:
		player_collision.try_move(offset, held_desktop_block)


## Player's real floor position (head projected down), not the play-area origin.
func _body_position() -> Vector3:
	return player_collision.body_position() if player_collision else player_origin.global_position


func _is_walkable(world_position: Vector3) -> bool:
	return player_collision == null or player_collision.is_walkable(world_position, held_desktop_block)


func _handle_desktop_grab() -> void:
	if _xr_is_running() or player_origin == null:
		return
	var down := Input.is_key_pressed(KEY_E)
	if down and not last_e_down:
		if held_desktop_block:
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
			held_desktop_block.global_transform = desktop_hold_transform


func _prepare_desktop_drop() -> bool:
	if held_desktop_block == null or player_origin == null:
		return false
	var start := _world_to_cell(held_desktop_block.global_position)
	for cell in [start, start + Vector2i.RIGHT, start + Vector2i.LEFT, start + Vector2i.DOWN, start + Vector2i.UP]:
		if not maze_world.is_open(cell) or (movable_blocks.has(cell) and movable_blocks[cell] != held_desktop_block):
			continue
		var center := _cell_to_world(cell) + Vector3.UP * (MazeWorld.WALL_HEIGHT * 0.5)
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
		if not maze_world.is_open(new_cell) or (movable_blocks.has(new_cell) and movable_blocks[new_cell] != block):
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
		if not block is GrabbableWall or not is_instance_valid(block):
			continue
		var to_block: Vector3 = block.global_position - camera_position
		var distance := to_block.length()
		var facing := camera_forward.dot(to_block.normalized()) if distance > 0.01 else 1.0
		if facing >= 0.25 and distance <= max_distance and distance < best_distance:
			best = block
			best_distance = distance
	return best


func _update_exit_audio(delta: float) -> void:
	if maze_world == null or exit_audio == null or player_origin == null:
		return
	var distance := _body_position().distance_to(maze_world.exit_node.global_position)
	pulse_timer -= delta
	if pulse_timer <= 0.0:
		exit_audio.play()
		pulse_timer = clampf(0.95 * distance / (MazeWorld.MAZE_SIZE * MazeWorld.CELL_SIZE), 0.16, 0.95)


func _check_end_conditions() -> void:
	if player_origin == null or professor == null or maze_world == null:
		return
	if _body_position().distance_to(maze_world.exit_node.global_position) < 0.75:
		game_state = "won"
		status_label.text = "ESCAPED! %s for a new maze" % _restart_prompt()
		if exit_audio: exit_audio.play()
		if xr_hud and _xr_is_running():
			xr_hud.show_toast("ESCAPED!  Press A for a new maze", 0.0)
	elif _body_position().distance_to(professor.global_position) < 0.95:
		game_state = "lost"
		status_label.text = "CAUGHT BY THE PROFESSOR! %s to retry" % _restart_prompt()
		if xr_hud and _xr_is_running():
			xr_hud.show_toast("CAUGHT BY THE PROFESSOR  ·  Press A to retry", 0.0)


func _update_hud() -> void:
	if hud == null:
		return
	var exit_distance := _exit_distance()
	var break_text := ""
	if professor and professor.is_breaking():
		break_text = "\nProfessor is breaking a wall: %.1fs" % professor.break_time_left()
	hud.text = "ESCAPE THE PROFESSOR\nTime: %02d s   Exit: %.1f m\nWASD + mouse: move/look   E: grab/release   R: restart   Esc: mouse" % [int(round_time), exit_distance] + break_text
	if game_state == "playing":
		status_label.text = "Find the green EXIT. Move a wall if you need to."


func _find_path(from: Vector2i, to: Vector2i, avoid_blocks: bool) -> Array[Vector2i]:
	return maze_world.find_path(from, to, avoid_blocks) if maze_world else []


func _cell_to_world(cell: Vector2i) -> Vector3:
	return maze_world.cell_to_world(cell) if maze_world else Vector3.ZERO


func _world_to_cell(world_position: Vector3) -> Vector2i:
	return maze_world.world_to_cell(world_position) if maze_world else Vector2i.ZERO


func _xr_is_running() -> bool:
	return xr_interface != null and xr_interface.is_initialized() and get_viewport().use_xr


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_start_round()
		elif event.keycode == KEY_ESCAPE and not _xr_is_running():
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
