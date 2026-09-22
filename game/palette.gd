class_name Palette

## The game's material set, keyed by the names MazeWorld.build() and the
## professor expect. Built once at startup and shared across rounds.


static func build() -> Dictionary:
	return {
		"floor": _material(Color("#765035"), 0.82),
		"wood_seam": _material(Color("#3d281d"), 0.9),
		"wall": _material(Color("#756b59"), 0.68),
		# GrabbableWall makes a transparent duplicate of this while a block is
		# held, so resting blocks stay solid and held blocks render through.
		"movable": _material(Color("#b76c39"), 0.3),
		"professor": _material(Color("#a62936"), 0.28),
		"exit": _material(Color("#54e4be"), 0.08, true),
		"ceiling": _material(Color("#cbc3ad"), 0.88),
		"fluorescent": _material(Color("#d9f6ff"), 0.24, true),
	}


static func _material(color: Color, roughness: float, emissive := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material
