extends RefCounted

# The moon's ground height, in metres above MoonOrbit.RADIUS, for a direction
# in the moon's own axes. The sum of:
#  - NASA's LOLA heights (tools/moon_maps.py), bilinear;
#  - small craters, 20 to 400 m across, too small for that map: on a grid on
#    each face of a cube blown up onto the sphere, four sizes, each cell
#    with a fixed pseudo-random crater or none (fresh: deep bowl and sharp
#    rim; old: half as deep, rounded);
#  - the flat ground under Base Selene.
# Pure and the same every time: the surface mesh, the patch under the ship
# and the ship's ground contact all read it. Thread-safe once loaded (call
# load_heights() on the main thread first).

const MoonOrbit = preload("res://scripts/moon_orbit.gd")

const HEIGHTS_PATH := "res://assets/moon/heights.bin"
const WIDTH := 4096
const HEIGHT := 2048
# Craters by size: [smallest, largest diameter (m), share of cells with one].
const OCTAVES := [[200.0, 400.0, 0.35], [100.0, 200.0, 0.45], [50.0, 100.0, 0.55], [20.0, 50.0, 0.6]]
# A cell is this many largest diameters wide: a crater (reaching 2 radii out
# with its ejecta) touches only its own and the neighbouring cells.
const CELL_DIAMETERS := 2.0
const FRESH_SHARE := 0.3
const DEPTH := 0.2  # of the diameter, fresh
const RIM := 0.04  # of the diameter, fresh
const EJECTA_REACH := 2.0  # radii
# Flat under the base out to FLAT_RADIUS, blending into the ground by
# BLEND_RADIUS (metres along the surface).
const FLAT_RADIUS := 1200.0
const BLEND_RADIUS := 2500.0

static var _bytes := PackedByteArray()
static var _base_height := NAN

static func load_heights() -> void:
	if _bytes.is_empty():
		_bytes = FileAccess.get_file_as_bytes(HEIGHTS_PATH)
		_base_height = nasa_height(MoonOrbit.base_direction())

# The ground's height at `direction` (unit, moon axes); `detail` 0..1 scales
# the small craters (0: NASA's map only).
static func height(direction: Vector3, detail := 1.0) -> float:
	load_heights()
	var from_base := MoonOrbit.RADIUS * acos(clampf(direction.dot(MoonOrbit.base_direction()), -1.0, 1.0))
	if from_base < FLAT_RADIUS:
		return _base_height
	var natural := nasa_height(direction)
	if detail > 0.0:
		natural += crater_height(direction) * detail
	if from_base < BLEND_RADIUS:
		return lerpf(_base_height, natural, smoothstep(FLAT_RADIUS, BLEND_RADIUS, from_base))
	return natural

# The flat ground's height under the base.
static func base_height() -> float:
	load_heights()
	return _base_height

static func nasa_height(direction: Vector3) -> float:
	load_heights()
	var longitude := atan2(direction.z, -direction.x)
	var latitude := asin(clampf(direction.y, -1.0, 1.0))
	var u := (longitude / TAU + 0.5) * WIDTH - 0.5
	var v := (0.5 - latitude / PI) * HEIGHT - 0.5
	var x0 := floori(u)
	var y0 := floori(v)
	var fx := u - x0
	var fy := v - y0
	var xa := posmod(x0, WIDTH)
	var xb := posmod(x0 + 1, WIDTH)
	var ya := clampi(y0, 0, HEIGHT - 1)
	var yb := clampi(y0 + 1, 0, HEIGHT - 1)
	var top := lerpf(_sample(xa, ya), _sample(xb, ya), fx)
	var bottom := lerpf(_sample(xa, yb), _sample(xb, yb), fx)
	return lerpf(top, bottom, fy)

static func _sample(x: int, y: int) -> float:
	return _bytes.decode_s16((y * WIDTH + x) * 2)

# The small craters' height at `direction` (their sum).
static func crater_height(direction: Vector3) -> float:
	var total := 0.0
	var major := maxf(absf(direction.x), maxf(absf(direction.y), absf(direction.z)))
	for axis in range(3):
		# This face, and a neighbour's near its edge (a crater belongs to the
		# face its centre is on, and may reach across).
		var along: float = direction[axis]
		if absf(along) < major * 0.995:
			continue
		var s: float = direction[(axis + 1) % 3] / absf(along)
		var t: float = direction[(axis + 2) % 3] / absf(along)
		var face := axis * 2 + (0 if along > 0.0 else 1)
		# Face units per metre of surface here (the gnomonic stretch).
		var stretch := (1.0 + s * s + t * t) / MoonOrbit.RADIUS
		for octave in range(OCTAVES.size()):
			var largest: float = OCTAVES[octave][1]
			var cell: float = largest * CELL_DIAMETERS / MoonOrbit.RADIUS
			var reach: float = largest * 0.5 * EJECTA_REACH * stretch
			var share: float = OCTAVES[octave][2]
			for ci in range(floori((s - reach) / cell), floori((s + reach) / cell) + 1):
				for cj in range(floori((t - reach) / cell), floori((t + reach) / cell) + 1):
					var bits := _hash(face, octave, ci, cj)
					if _part(bits, 0) >= share:
						continue
					var cs := (ci + _part(bits, 1)) * cell
					var ct := (cj + _part(bits, 2)) * cell
					if absf(cs) > 1.0 or absf(ct) > 1.0 or absf(cs - s) > reach or absf(ct - t) > reach:
						continue
					var on_face := Vector3.ZERO
					on_face[axis] = 1.0 if along > 0.0 else -1.0
					on_face[(axis + 1) % 3] = cs
					on_face[(axis + 2) % 3] = ct
					var more := _mix(bits)
					var radius: float = lerpf(OCTAVES[octave][0], largest, _part(more, 0)) * 0.5
					var x: float = (direction - on_face.normalized()).length() * MoonOrbit.RADIUS / radius
					if x < EJECTA_REACH:
						total += _profile(x, radius, _part(more, 1) < FRESH_SHARE)
	return total

# The crater in a face's cell, or empty: {centre (unit), radius, fresh}.
static func _crater(face: int, octave: int, i: int, j: int) -> Dictionary:
	var bits := _hash(face, octave, i, j)
	if _part(bits, 0) >= OCTAVES[octave][2]:
		return {}
	var cell: float = OCTAVES[octave][1] * CELL_DIAMETERS / MoonOrbit.RADIUS
	var s := (i + _part(bits, 1)) * cell
	var t := (j + _part(bits, 2)) * cell
	if absf(s) > 1.0 or absf(t) > 1.0:
		return {}
	var axis := face / 2
	var on_face := Vector3.ZERO
	on_face[axis] = 1.0 if face % 2 == 0 else -1.0
	on_face[(axis + 1) % 3] = s
	on_face[(axis + 2) % 3] = t
	var more := _mix(bits)
	var diameter := lerpf(OCTAVES[octave][0], OCTAVES[octave][1], _part(more, 0))
	return {"centre": on_face.normalized(), "radius": diameter * 0.5, "fresh": _part(more, 1) < FRESH_SHARE}

# Height at `x` radii from a crater's centre: a bowl up to the rim, then the
# ejecta sloping away to nothing at EJECTA_REACH. Old craters half as deep,
# their rims rounded.
static func _profile(x: float, radius: float, fresh: bool) -> float:
	var depth := DEPTH * 2.0 * radius
	var rim := RIM * 2.0 * radius
	if not fresh:
		depth *= 0.5
		rim *= 0.5
	if x < 1.0:
		var rise := x * x if fresh else smoothstep(0.0, 1.0, x)
		return -depth + (depth + rim) * rise
	return rim * (1.0 - smoothstep(1.0, EJECTA_REACH, x))

# A fresh (or old) crater near `near`, for tests: {centre, radius} or empty.
static func find_crater(fresh: bool, near: Vector3) -> Dictionary:
	var major := 0
	for axis in range(3):
		if absf(near[axis]) > absf(near[major]):
			major = axis
	var face := major * 2 + (0 if near[major] > 0.0 else 1)
	var s: float = near[(major + 1) % 3] / absf(near[major])
	var t: float = near[(major + 2) % 3] / absf(near[major])
	for octave in range(1, OCTAVES.size()):
		var cell: float = OCTAVES[octave][1] * CELL_DIAMETERS / MoonOrbit.RADIUS
		for di in range(20):
			for dj in range(20):
				var crater := _crater(face, octave, floori(s / cell) + di, floori(t / cell) + dj)
				if not crater.is_empty() and crater.fresh == fresh:
					return crater
	return {}

static func _mix(value: int) -> int:
	value = (value ^ (value >> 30)) * -4658895280553007687
	value = (value ^ (value >> 27)) * -7723592293110705685
	return value ^ (value >> 31)

# A cell's 64 pseudo-random bits.
static func _hash(face: int, octave: int, i: int, j: int) -> int:
	return _mix(face * 73856093 + octave * 19349663 + i * 83492791 + j * 2654435761)

# The `k`-th 16 bits of `bits` (k 0..3) as a number in [0, 1).
static func _part(bits: int, k: int) -> float:
	return float((bits >> (16 * k)) & 0xFFFF) / 65536.0
