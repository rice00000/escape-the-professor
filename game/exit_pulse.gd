class_name ExitPulse
extends AudioStreamPlayer3D

## The exit's "musical pulse" beacon. Beats faster the closer the player is.

const MIN_INTERVAL := 0.16
const MAX_INTERVAL := 0.95

var _timer := 0.0


func _init() -> void:
	name = "ExitMusicalPulse"
	stream = Tone.make(660.0, 0.22, 0.16)
	max_distance = MazeWorld.MAZE_SIZE * MazeWorld.CELL_SIZE * 1.4
	unit_size = 1.5


## Call once per frame with the player's distance to the exit.
func tick(delta: float, player_distance: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	play()
	var span := MazeWorld.MAZE_SIZE * MazeWorld.CELL_SIZE
	_timer = clampf(MAX_INTERVAL * player_distance / span, MIN_INTERVAL, MAX_INTERVAL)
