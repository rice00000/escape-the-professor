# Escape the Professor

This is a small Godot XR prototype built on the original VR/AR@MIT XR template. Each round generates a larger 15x15 maze with side branches and a few loops, so there are multiple ways to reach the green exit. The professor appears in the starting area within view, then gives you a short head start before chasing. Orange wall blocks can be moved to open a route; the professor spends 2.5 seconds breaking a block that blocks his route.

## Run

Open the project folder in Godot 4.7 (or a compatible Godot 4 build) and run the main scene. OpenXR is used automatically when a headset runtime is available. Without a headset, the same scene starts in desktop mode.

## Controls

- Desktop: `WASD` moves forward/left/back/right relative to the view, mouse looks, `E` grabs/releases the orange block in front of you, `R` starts a new maze, `Esc` releases the mouse. A held block is translucent and stops colliding while carried. Release snaps it to a clear maze cell; if there is no safe space away from the player, it stays held until you move away.
- XR: use the existing left controller thumbstick for smooth movement, the right thumbstick for snap turning, and grip/pinch to grab orange blocks.
- The exit's spatial musical pulse becomes faster as you approach it. The professor has a separate low footstep/threat tone.
- If the professor gets close enough to catch you, gameplay freezes and a restart prompt appears. Press `R` on desktop or `A`/`X` in XR to retry.

The runtime uses primitive Godot nodes and simple generated audio. Game-side behavior lives under `game/`: `maze_world.gd` builds each maze and exit, `professor.gd` owns the chasing actor and timed wall breaking, while `grabbable_wall.gd` and `maze_player.gd` handle interaction and corridor clearance. `main.gd` orchestrates input, rounds, HUD, and win/loss state. The XR template adapters remain under `scripts/` and call the same block behavior. No external game assets are required.

## Godot Assistant editor plugin

The project includes a `Godot Assistant` dock under `addons/godot_assistant`. It follows explicit Scene and FileSystem selections, shows the context that will be sent, answers questions about the selected node or asset, and includes an offline **Add audio** guide.

For AI chat, either launch Godot with an `OPENAI_API_KEY` environment variable or paste a key into the dock's password field for the current editor session. The key is never stored in the project. You can optionally set `OPENAI_MODEL`; otherwise the plugin uses `gpt-5`.
