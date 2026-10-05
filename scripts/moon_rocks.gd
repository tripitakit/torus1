extends Node3D

# Stones and boulders on the moon, a child of the moon (its axes). Three
# sizes, each on a grid on the plane of the cube face under the player (as
# MoonTerrain's craters): at most one stone a cell, picked by the cell's
# hash, so the same stones lie in the same place every time. More on crater
# rims and their ejecta (where the small craters lift the ground), none on
# Base Selene and its pads, few on its flat ground.

const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonPatch = preload("res://scripts/moon_patch.gd")

enum { PEBBLE, ROCK, BOULDER }
# cell (m), chance a cell has one, size range (m), drawn within `reach`,
# rebuilt every `step` the player moves.
const CLASSES := [
	{"cell": 2.0, "chance": 0.6, "low": 0.1, "high": 0.3, "reach": 60.0, "step": 20.0},
	{"cell": 8.0, "chance": 0.35, "low": 0.3, "high": 0.8, "reach": 200.0, "step": 50.0},
	{"cell": 40.0, "chance": 0.6, "low": 0.8, "high": 4.0, "reach": 600.0, "step": 150.0},
]
# Round Base Selene (metres along the surface from its tower).
const NONE_WITHIN := 700.0
const SPARSE_WITHIN := 1200.0
const FULL_FROM := 2500.0
const SPARSE := 0.05
# Crater rims raise the chance by up to this many times over.
const RIM_BOOST := 3.0
# The hash's octave numbers for the stones (the craters use 0..3).
const HASH_OCTAVE := 10

# How much likelier a stone is at `direction` (moon axes, unit) than on
# plain ground: 0 at the base, up to 1 + RIM_BOOST on crater rims.
static func density(direction: Vector3) -> float:
	var from_base := MoonOrbit.RADIUS * acos(clampf(direction.dot(MoonOrbit.base_direction()), -1.0, 1.0))
	if from_base < NONE_WITHIN:
		return 0.0
	var share := SPARSE
	if from_base >= SPARSE_WITHIN:
		share = lerpf(SPARSE, 1.0, smoothstep(SPARSE_WITHIN, FULL_FROM, from_base))
	return share * (1.0 + clampf(MoonTerrain.crater_height(direction), 0.0, RIM_BOOST))

# The stones of size `kind` in the cells over the face plane's rectangle
# `low`..`high` (metres): {direction, size, spin, squash, shape}.
static func stones_in(face: int, kind: int, low: Vector2, high: Vector2) -> Array:
	var cls: Dictionary = CLASSES[kind]
	var cell: float = cls.cell
	var most: float = cls.chance * (1.0 + RIM_BOOST)
	var found := []
	for i in range(floori(low.x / cell), floori(high.x / cell) + 1):
		for j in range(floori(low.y / cell), floori(high.y / cell) + 1):
			var bits := MoonTerrain._hash(face, HASH_OCTAVE + kind, i, j)
			var roll := MoonTerrain._part(bits, 0)
			if roll >= most:
				continue
			var uv := (Vector2(i, j) + Vector2(MoonTerrain._part(bits, 1), MoonTerrain._part(bits, 2))) * cell
			var direction := MoonPatch.plane_direction(face, uv)
			if roll >= cls.chance * density(direction):
				continue
			var more := MoonTerrain._mix(bits)
			var small := MoonTerrain._part(more, 0)
			found.append({
				"direction": direction,
				"size": lerpf(cls.low, cls.high, small * small),
				"spin": MoonTerrain._part(more, 1) * TAU,
				"squash": lerpf(0.55, 0.9, MoonTerrain._part(more, 2)),
				"shape": mini(2, int(MoonTerrain._part(more, 3) * 3.0)),
			})
	return found
