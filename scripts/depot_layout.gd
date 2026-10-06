extends RefCounted

# The Nuclear Waste Disposal Area 2 monitoring depot (far side,
# Tsiolkovskiy), in the Moonbase Alpha style: the airlock behind the hatch to
# the surface, the monitor room beyond with its watch consoles under the
# window on the silo field, the radiation screen, the silo map table,
# computer banks. Floor at y = 0, the hatch toward +Z.

const AlphaPlan = preload("res://scripts/alpha_plan.gd")

static func _r(name: String, label: String, x0: float, z0: float, x1: float, z1: float, height: float) -> Dictionary:
	return {"name": name, "label": label, "rect": Rect2(x0, z0, x1 - x0, z1 - z0), "height": height, "zone": "outpost", "floor": 0.0}

static func rooms() -> Array:
	return [
		_r("airlock", "AIRLOCK", -2.4, 0.0, 2.4, 4.8, 3.0),
		_r("monitor", "AREA 2 MONITORING", -6.0, -12.0, 6.0, 0.0, 4.2),
	]

static func doors() -> Array:
	return [
		{"a": "airlock", "b": "monitor", "centre": Vector3(0.0, 0.0, 0.0), "width": 1.8, "axis": "x", "kind": "door"},
		{"a": "airlock", "b": "outside", "centre": Vector3(0.0, 0.0, 4.8), "width": 1.8, "axis": "x", "kind": "hatch"},
	]

static func walls() -> Array:
	return AlphaPlan.walls(rooms(), doors(), [{"room": "monitor", "edge": "z0"}])

static func room_at(point: Vector3) -> String:
	return AlphaPlan.room_at(rooms(), point)

static func room_rect(name: String) -> Rect2:
	return AlphaPlan._rect(rooms(), name)

static func corridors() -> Array:
	return ["airlock"]

static func window_view() -> Dictionary:
	return {"room": "monitor", "kind": "field"}

# The hatch's middle on the floor; -Z of its basis points into the airlock.
static func hatch() -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, 0.0, 4.8))

# Where the pilot stands coming in: just inside the hatch, facing in.
static func spawn() -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, 0.0, 3.4))

static func _f(kind: String, x: float, z: float, size: Vector3, turn: float = 0.0) -> Dictionary:
	return {"kind": kind, "transform": Transform3D(Basis(Vector3.UP, turn), Vector3(x, 0.0, z)), "size": size}

static func furniture() -> Array:
	var out := []
	for x in [-3.6, 0.0, 3.6]:
		out.append(_f("window_console", x, -11.4, Vector3(3.0, 1.0, 0.8)))
	for z in [-3.4, -7.0]:
		out.append(_f("desk", -3.8, z, Vector3(0.8, 0.75, 1.6)))
		out.append(_f("chair", -2.9, z, Vector3(0.5, 0.9, 0.5), PI * 0.5))
	out.append(_f("radiation_screen", -5.85, -5.2, Vector3(0.3, 2.4, 4.0)))
	out.append(_f("map_table", 1.6, -6.0, Vector3(1.6, 0.9, 2.4)))
	for z in [-3.0, -8.4]:
		out.append(_f("computer_bank", 5.6, z, Vector3(0.6, 2.6, 2.4)))
	out.append(_f("plant", 5.4, -0.6, Vector3(0.5, 1.2, 0.5)))
	for z in [1.0, 2.2, 3.4]:
		out.append(_f("suit_locker", -2.0, z, Vector3(0.6, 2.0, 1.0)))
	out.append(_f("bench", 2.0, 2.2, Vector3(0.5, 0.45, 2.4)))
	return out
