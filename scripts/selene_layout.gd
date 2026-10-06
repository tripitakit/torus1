extends RefCounted

# The plan of Selene's interior (after Moonbase Alpha): rooms on a 1.2 m
# panel grid, floor at y = 0, rects on the floor (x, z). Two zones far
# apart, joined only by the Travel Tube's tunnel: the dock (the hangar
# under the pad, the Eagle's lift) and the centre (reception, corridors,
# Main Mission, medical, quarters, lounge). Pure data, for the scene and
# the crew.

const AlphaPlan = preload("res://scripts/alpha_plan.gd")

const DOCK_X := 200.0
const WALL_PIECE := AlphaPlan.WALL_PIECE
const WALL_THICK := AlphaPlan.WALL_THICK
const OFFICE_FLOOR := 0.6
# The comm post at the crossing of the main and side corridors (its
# footprint POST_SIZE square).
const POST := Vector3(0.0, 0.0, -9.0)
const POST_SIZE := 1.0
# Around the post: north, south, east, west (the crew walk round it).
const ROUND_N := Vector3(0.0, 0.0, -6.6)
const ROUND_S := Vector3(0.0, 0.0, -11.4)
const ROUND_E := Vector3(1.5, 0.0, -9.0)
const ROUND_W := Vector3(-1.5, 0.0, -9.0)
# Where to go from the post for each place on its signs.
const DESTINATIONS := {
	"MAIN MISSION": Vector3(0.0, 0.0, -1.0),
	"MEDICAL CENTRE": Vector3(-1.0, 0.0, 0.0),
	"CREW QUARTERS": Vector3(-1.0, 0.0, 0.0),
	"RECREATION": Vector3(1.0, 0.0, 0.0),
	"TRAVEL TUBE": Vector3(0.0, 0.0, 1.0),
}

static func _r(name: String, label: String, x0: float, z0: float, x1: float, z1: float, height: float, zone: String, floor: float = 0.0) -> Dictionary:
	return {"name": name, "label": label, "rect": Rect2(x0, z0, x1 - x0, z1 - z0), "height": height, "zone": zone, "floor": floor}

# {name, label (shown in the HUD), rect, height, zone, floor}.
static func rooms() -> Array:
	return [
		_r("dock", "PAD 1 HANGAR", DOCK_X - 6.0, -6.0, DOCK_X + 6.0, 6.0, 8.0, "dock"),
		_r("tube_dock", "TRAVEL TUBE", DOCK_X - 2.4, 6.0, DOCK_X + 2.4, 9.6, 3.0, "dock"),
		_r("tube_centre", "TRAVEL TUBE", -2.4, 6.0, 2.4, 9.6, 3.0, "centre"),
		_r("tunnel", "TRAVEL TUBE", 2.4, 6.0, DOCK_X - 2.4, 9.6, 3.6, "tube"),
		_r("reception", "TRAVEL TUBE RECEPTION", -3.6, 0.0, 3.6, 6.0, 3.6, "centre"),
		_r("corridor", "MAIN CORRIDOR", -2.4, -21.6, 2.4, 0.0, 3.6, "centre"),
		_r("side_left", "CORRIDOR", -12.0, -10.5, -2.4, -7.5, 3.6, "centre"),
		_r("side_right", "CORRIDOR", 2.4, -10.5, 12.0, -7.5, 3.6, "centre"),
		_r("main_mission", "MAIN MISSION", -12.0, -36.0, 12.0, -21.6, 6.0, "centre"),
		_r("office", "COMMANDER'S OFFICE", 12.0, -32.4, 18.0, -25.2, 5.4, "centre", OFFICE_FLOOR),
		_r("medical", "MEDICAL CENTRE", -21.6, -12.6, -12.0, -5.4, 3.6, "centre"),
		_r("quarters_a", "CREW QUARTERS", -9.6, -15.3, -4.8, -10.5, 3.6, "centre"),
		_r("quarters_b", "CREW QUARTERS", -9.6, -7.5, -4.8, -2.7, 3.6, "centre"),
		_r("lounge", "RECREATION", 12.0, -13.8, 21.6, -4.2, 3.6, "centre"),
	]

static func _d(a: String, b: String, x: float, z: float, width: float, axis: String, kind: String) -> Dictionary:
	return {"a": a, "b": b, "centre": Vector3(x, 0.0, z), "width": width, "axis": axis, "kind": kind}

# {a, b, centre, width, axis (the wall it is in runs along x or z), kind:
# "open" (a gap), "door" and "double" (sliding), "office" (the sliding glass
# wall), "tunnel" (where the tube's tunnel meets a station)}.
static func doors() -> Array:
	return [
		_d("reception", "corridor", 0.0, 0.0, 4.8, "x", "open"),
		_d("reception", "tube_centre", 0.0, 6.0, 1.8, "x", "door"),
		_d("tube_centre", "tunnel", 2.4, 7.8, 3.6, "z", "tunnel"),
		_d("tunnel", "tube_dock", DOCK_X - 2.4, 7.8, 3.6, "z", "tunnel"),
		_d("dock", "tube_dock", DOCK_X, 6.0, 1.8, "x", "door"),
		_d("corridor", "main_mission", 0.0, -21.6, 3.6, "x", "double"),
		_d("corridor", "side_left", -2.4, -9.0, 3.0, "z", "open"),
		_d("corridor", "side_right", 2.4, -9.0, 3.0, "z", "open"),
		_d("side_left", "medical", -12.0, -9.0, 1.8, "z", "door"),
		_d("side_left", "quarters_a", -7.2, -10.5, 1.2, "x", "door"),
		_d("side_left", "quarters_b", -7.2, -7.5, 1.2, "x", "door"),
		_d("side_right", "lounge", 12.0, -9.0, 2.4, "z", "double"),
		_d("main_mission", "office", 12.0, -28.8, 4.8, "z", "office"),
	]

# Selene's solid walls (AlphaPlan.walls), Main Mission's far wall a window.
static func walls() -> Array:
	return AlphaPlan.walls(rooms(), doors(), [{"room": "main_mission", "edge": "z0"}])

static func room_at(point: Vector3) -> String:
	return AlphaPlan.room_at(rooms(), point)

static func room_rect(name: String) -> Rect2:
	for room in rooms():
		if room.name == name:
			return room.rect
	return Rect2()

# The rooms whose walls get the corridors' light panels and glowing strip.
static func corridors() -> Array:
	return ["corridor", "side_left", "side_right", "reception"]

# The window's room and what is painted beyond it.
static func window_view() -> Dictionary:
	return {"room": "main_mission", "kind": "moon"}

static func lift_centre() -> Vector3:
	return Vector3(DOCK_X, 0.0, 0.0)

# Where the Travel Tube's car stands at each stop (its middle, on the
# floor): the car runs along X between them.
static func tube_stops() -> Dictionary:
	return {"dock": Transform3D(Basis(), Vector3(DOCK_X, 0.0, 7.8)), "centre": Transform3D(Basis(), Vector3(0.0, 0.0, 7.8))}

# The comm post's signs, one per face: {normal (out of that face), lines:
# [[place, arrow]]}, the arrow as one reading that face sees it.
static func post_signs() -> Array:
	var out := []
	for normal in [Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0)]:
		var ahead: Vector3 = -normal
		var right := ahead.cross(Vector3.UP)
		var lines := []
		for place: String in DESTINATIONS:
			var way: Vector3 = DESTINATIONS[place]
			var arrow := "←"
			if way.dot(ahead) > 0.5:
				arrow = "↑"
			elif way.dot(ahead) < -0.5:
				arrow = "↓"
			elif way.dot(right) > 0.5:
				arrow = "→"
			lines.append([place, arrow])
		out.append({"normal": normal, "lines": lines})
	return out

# Main Mission's desks: two rows of four facing the Big Screen (-X), a
# chair close behind each.
static func _desk_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for x in [-7.0, -3.5]:
		for z in [-24.6, -27.4, -30.2, -33.0]:
			spots.append(Vector3(x, 0.0, z))
	return spots

static func seats() -> Array:
	var out := []
	for spot in _desk_spots():
		out.append(Transform3D(Basis(Vector3.UP, PI * 0.5), spot + Vector3(0.9, 0.0, 0.0)))
	return out

# The seats taken: four of the eight.
static func crew_seats() -> Array:
	var all := seats()
	return [all[0], all[2], all[5], all[7]]

static func _f(kind: String, x: float, z: float, size: Vector3, turn: float = 0.0, floor: float = 0.0) -> Dictionary:
	return {"kind": kind, "transform": Transform3D(Basis(Vector3.UP, turn), Vector3(x, floor, z)), "size": size}

# {kind, transform (on the floor), size (x across, y up, z along before
# the turn)}.
static func furniture() -> Array:
	var out := []
	for spot in _desk_spots():
		out.append(_f("desk", spot.x, spot.z, Vector3(0.8, 0.75, 1.6)))
	for seat: Transform3D in seats():
		out.append(_f("chair", seat.origin.x, seat.origin.z, Vector3(0.5, 0.9, 0.5), PI * 0.5))
	out.append(_f("big_screen", -11.85, -28.8, Vector3(0.3, 3.6, 6.0)))
	for z in [-23.6, -34.0]:
		out.append(_f("computer_bank", -11.6, z, Vector3(0.6, 2.6, 2.4)))
	for x in [-4.0, 0.0, 4.0]:
		out.append(_f("window_console", x, -35.4, Vector3(3.0, 1.0, 0.8)))
	for x in [-10.2, 10.2]:
		out.append(_f("plant", x, -22.5, Vector3(0.5, 1.2, 0.5)))
	out.append(_f("office_desk", 15.6, -28.8, Vector3(1.0, 0.75, 2.0), 0.0, OFFICE_FLOOR))
	out.append(_f("post", POST.x, POST.z, Vector3(POST_SIZE, 2.8, POST_SIZE)))
	for x in [-1.9, 1.9]:
		out.append(_f("plant", x, -1.5, Vector3(0.5, 1.2, 0.5)))
	for z in [-4.5, -14.0, -18.0]:
		for x in [-2.15, 2.15]:
			out.append(_f("wall_bank", x, z, Vector3(0.3, 2.4, 2.4)))
	out.append(_f("reception_desk", -2.6, 4.2, Vector3(0.8, 0.75, 1.4)))
	for x in [-20.4, -17.9, -15.4]:
		out.append(_f("bed", x, -11.5, Vector3(0.9, 0.6, 2.0)))
	out.append(_f("cabinet", -19.0, -5.8, Vector3(2.4, 2.0, 0.6)))
	out.append(_f("scanner", -13.2, -6.0, Vector3(1.0, 1.6, 0.6)))
	out.append(_f("bed", -8.9, -13.0, Vector3(0.9, 0.5, 2.0)))
	out.append(_f("room_desk", -5.3, -14.7, Vector3(0.8, 0.75, 1.0)))
	out.append(_f("chair", -6.1, -14.7, Vector3(0.5, 0.9, 0.5), -PI * 0.5))
	out.append(_f("bed", -8.9, -5.0, Vector3(0.9, 0.5, 2.0)))
	out.append(_f("room_desk", -5.3, -3.3, Vector3(0.8, 0.75, 1.0)))
	out.append(_f("chair", -6.1, -3.3, Vector3(0.5, 0.9, 0.5), -PI * 0.5))
	for spot in [Vector2(15.2, -6.5), Vector2(18.7, -6.5), Vector2(17.0, -11.8)]:
		out.append(_f("table_set", spot.x, spot.y, Vector3(2.2, 0.75, 2.2)))
	out.append(_f("dispenser", 21.2, -9.0, Vector3(0.6, 1.8, 0.6)))
	for x in [DOCK_X - 5.0, DOCK_X + 5.0]:
		for z in [-5.0, 5.0]:
			out.append(_f("pillar", x, z, Vector3(0.8, 8.0, 0.8)))
	out.append(_f("booth", DOCK_X + 5.0, 0.0, Vector3(1.8, 2.6, 3.0)))
	return out

# The ramp up to the Commander's office (drawn as three steps): its rect
# on Main Mission's floor, rising toward +X to OFFICE_FLOOR.
static func office_ramp() -> Rect2:
	return Rect2(10.2, -31.2, 1.8, 4.8)

static func _route(department: String, points: Array) -> Dictionary:
	return {"department": department, "points": PackedVector3Array(points)}

# The walkers' ways, there and back again: one per department and one
# more in Main Mission.
static func routes() -> Array:
	var v := func(x: float, z: float) -> Vector3: return Vector3(x, 0.0, z)
	return [
		_route("main_mission", [v.call(1.5, 3.0), v.call(0.0, 0.5), ROUND_N, ROUND_E, ROUND_S, v.call(0.0, -20.6), v.call(0.0, -22.6), v.call(7.0, -23.4), v.call(7.0, -33.5)]),
		_route("medical", [v.call(-14.0, -8.0), v.call(-13.0, -9.0), ROUND_W, ROUND_N, v.call(0.0, -2.0)]),
		_route("technical", [v.call(16.5, -9.0), v.call(12.0, -9.0), ROUND_E, ROUND_S, v.call(0.0, -20.6), v.call(0.0, -22.6), v.call(5.0, -24.0)]),
		_route("security", [v.call(-1.5, 4.0), v.call(0.0, 0.5), ROUND_N, ROUND_W, v.call(-7.2, -9.0), v.call(-7.2, -12.9)]),
		_route("command", [v.call(-7.2, -5.1), v.call(-7.2, -9.0), ROUND_W, ROUND_S, v.call(0.0, -20.6), v.call(0.0, -22.6), v.call(6.0, -28.0)]),
		_route("main_mission", [v.call(3.5, -24.0), v.call(3.5, -34.0)]),
	]

# The crew at work standing: {department, transform (facing their work)}.
static func workers() -> Array:
	return [
		{"department": "medical", "transform": Transform3D(Basis(), Vector3(-17.9, 0.0, -9.9))},
		{"department": "command", "transform": Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(16.8, OFFICE_FLOOR, -26.4))},
	]
