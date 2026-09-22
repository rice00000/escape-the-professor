# Escape the Professor

This is a small Godot XR prototype built on the original VR/AR@MIT XR template. Each round generates a larger 15x15 maze with side branches and a few loops, so there are multiple ways to reach the green exit. The professor appears in the starting area within view, then gives you a short head start before chasing. Orange wall blocks can be moved to open a route; the professor spends 2.5 seconds breaking a block that blocks his route.

## Run

Open the project folder in Godot 4.7 (or a compatible Godot 4 build) and run the main scene. OpenXR is used automatically when a headset runtime is available. Without a headset, the same scene starts in desktop mode.

## Controls

- Desktop: `WASD` moves forward/left/back/right relative to the view, mouse looks, `E` grabs/releases the orange block in front of you, `R` starts a new maze, `Esc` releases the mouse. A held block is translucent and stops colliding while carried. Release snaps it to a clear maze cell; if there is no safe space away from the player, it stays held until you move away.
- XR: use the existing left controller thumbstick for smooth movement, the right thumbstick for snap turning, and grip/pinch to grab orange blocks.
- The exit's spatial musical pulse becomes faster as you approach it. The professor has a separate low footstep/threat tone.

The maze, professor, blocks, exit, wood-like floor, tiled ceiling, fluorescent school lights, HUD and generated audio are created by `main.gd` at runtime with primitive Godot nodes. Shared block carrying lives in `scripts/grabbable_wall.gd`; player corridor clearance is in `scripts/maze_player.gd`; the existing XR grab scripts call the same block behavior. No external game assets are required.
