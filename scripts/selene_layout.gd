extends RefCounted

# The plan of Selene's interior (after Moonbase Alpha): rooms on a 1.2 m
# panel grid, floor at y = 0, rects on the floor (x, z). Two zones far
# apart, joined only by the Travel Tube: the dock under the pad (the
# Eagle's lift) and the centre (reception, corridors, Main Mission,
# medical, quarters, lounge). Pure data, for the scene and the crew.

const DOCK_X := 200.0
const CORRIDOR_HEIGHT := 2.4
# Long walls in pieces no longer than this (each lit by its own lights).
const WALL_PIECE := 12.0
const OFFICE_FLOOR := 0.6
# The comm post at the crossing of the main and side corridors.
const POST := Vector3(0.0, 0.0, -9.0)
# Around the post: north, south, east, west (the crew walk round it).
const ROUND_N := Vector3(0.0, 0.0, -6.8)
const ROUND_S := Vector3(0.0, 0.0, -11.2)
const ROUND_E := Vector3(1.0, 0.0, -9.0)
const ROUND_W := Vector3(-1.0, 0.0, -9.0)

static func _r(name: String, label: String, x0: float, z0: float, x1: float, z1: float, height: float, zone: String, floor: float = 0.0) -> Dictionary:
	return {"name": name, "label": label, "rect": Rect2(x0, z0, x1 - x0, z1 - z0), "height": height, "zone": zone, "floor": floor}

# {name, label (shown in the HUD), rect, height, zone, floor}.
static func rooms() -> Array:
	return [
		_r("dock", "PAD 1 DOCK", DOCK_X - 6.0, -4.8, DOCK_X + 6.0, 4.8, 4.8, "dock"),
		_r("tube_dock", "TRAVEL TUBE", DOCK_X - 1.2, 4.8, DOCK_X + 1.2, 8.4, 2.4, "dock"),
		_r("tube_centre", "TRAVEL TUBE", -1.2, 4.8, 1.2, 8.4, 2.4, "centre"),
		_r("reception", "TRAVEL TUBE RECEPTION", -2.4, 0.0, 2.4, 4.8, 2.4, "centre"),
		_r("corridor", "MAIN CORRIDOR", -1.2, -18.0, 1.2, 0.0, 2.4, "centre"),
		_r("side_left", "CORRIDOR", -10.8, -9.9, -1.2, -8.1, 2.4, "centre"),
		_r("side_right", "CORRIDOR", 1.2, -9.9, 10.8, -8.1, 2.4, "centre"),
		_r("main_mission", "MAIN MISSION", -10.0, -30.0, 10.0, -18.0, 4.8, "centre"),
		_r("office", "COMMANDER'S OFFICE", 10.0, -27.6, 16.0, -20.4, 4.2, "centre", OFFICE_FLOOR),
		_r("medical", "MEDICAL CENTRE", -20.4, -12.6, -10.8, -5.4, 2.4, "centre"),
		_r("quarters_a", "CREW QUARTERS", -8.4, -14.7, -3.6, -9.9, 2.4, "centre"),
		_r("quarters_b", "CREW QUARTERS", -8.4, -8.1, -3.6, -3.3, 2.4, "centre"),
		_r("lounge", "RECREATION", 10.8, -13.8, 20.4, -4.2, 2.4, "centre"),
	]

static func _d(a: String, b: String, x: float, z: float, width: float, axis: String, kind: String) -> Dictionary:
	return {"a": a, "b": b, "centre": Vector3(x, 0.0, z), "width": width, "axis": axis, "kind": kind}

# {a, b, centre, width, axis (the wall it is in runs along x or z), kind:
# "open" (a gap), "door" and "double" (sliding), "office" (the sliding wall)}.
static func doors() -> Array:
	return [
		_d("reception", "corridor", 0.0, 0.0, 2.4, "x", "open"),
		_d("reception", "tube_centre", 0.0, 4.8, 1.2, "x", "door"),
		_d("corridor", "main_mission", 0.0, -18.0, 2.4, "x", "double"),
		_d("corridor", "side_left", -1.2, -9.0, 1.8, "z", "open"),
		_d("corridor", "side_right", 1.2, -9.0, 1.8, "z", "open"),
		_d("side_left", "medical", -10.8, -9.0, 1.2, "z", "door"),
		_d("side_left", "quarters_a", -6.0, -9.9, 1.2, "x", "door"),
		_d("side_left", "quarters_b", -6.0, -8.1, 1.2, "x", "door"),
		_d("side_right", "lounge", 10.8, -9.0, 1.2, "z", "door"),
		_d("main_mission", "office", 10.0, -24.0, 4.8, "z", "office"),
		_d("dock", "tube_dock", DOCK_X, 4.8, 1.2, "x", "door"),
	]

# Every room's walls, cut at its doors and in pieces of WALL_PIECE at most:
# {from, to (Vector2 on the floor), floor, height, room, inward (Vector2),
# window (Main Mission's far wall)}.
static func walls() -> Array:
	var out := []
	for room in rooms():
		var r: Rect2 = room.rect
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for k in range(4):
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % 4]
			var along := (b - a).normalized()
			var inward := Vector2(-along.y, along.x)
			var window: bool = room.name == "main_mission" and is_equal_approx(a.y, r.position.y) and is_equal_approx(b.y, r.position.y)
			# The gaps of the doors on this edge, as distances from a.
			var gaps := []
			for door in doors():
				if door.a != room.name and door.b != room.name:
					continue
				var c := Vector2(door.centre.x, door.centre.z)
				var off := c - a
				if absf(off.cross(along)) > 0.01:
					continue
				var at := off.dot(along)
				if at > 0.0 and at < a.distance_to(b):
					gaps.append(Vector2(at - door.width * 0.5, at + door.width * 0.5))
			gaps.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
			var start := 0.0
			var spans := []
			for gap: Vector2 in gaps:
				if gap.x > start + 0.01:
					spans.append(Vector2(start, gap.x))
				start = gap.y
			if a.distance_to(b) > start + 0.01:
				spans.append(Vector2(start, a.distance_to(b)))
			for span: Vector2 in spans:
				var pieces := ceili((span.y - span.x) / WALL_PIECE - 1e-6)
				for i in range(pieces):
					var s0 := span.x + (span.y - span.x) * i / pieces
					var s1 := span.x + (span.y - span.x) * (i + 1) / pieces
					out.append({"from": a + along * s0, "to": a + along * s1, "floor": room.floor, "height": room.height,
						"room": room.name, "inward": inward, "window": window})
	return out

static func room_at(point: Vector3) -> String:
	for room in rooms():
		if (room.rect as Rect2).has_point(Vector2(point.x, point.z)):
			return room.name
	return ""

static func lift_centre() -> Vector3:
	return Vector3(DOCK_X, 0.0, 0.0)

# Inside each Travel Tube cabin, facing its door.
static func tube_stops() -> Dictionary:
	return {"dock": Transform3D(Basis(), Vector3(DOCK_X, 0.0, 7.2)), "centre": Transform3D(Basis(), Vector3(0.0, 0.0, 7.2))}

# Main Mission's desks: two rows of four facing the Big Screen (-X), a
# chair close behind each.
static func _desk_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for x in [-6.0, -2.5]:
		for z in [-20.6, -23.0, -25.4, -27.8]:
			spots.append(Vector3(x, 0.0, z))
	return spots

static func seats() -> Array:
	var out := []
	for spot in _desk_spots():
		out.append(Transform3D(Basis(Vector3.UP, PI * 0.5), spot + Vector3(0.9, 0.0, 0.0)))
	return out

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
	out.append(_f("big_screen", -9.85, -24.0, Vector3(0.3, 3.0, 5.0)))
	out.append(_f("console", 8.5, -29.6, Vector3(2.4, 1.2, 0.6)))
	out.append(_f("office_desk", 13.6, -24.0, Vector3(1.0, 0.75, 2.0), 0.0, OFFICE_FLOOR))
	out.append(_f("post", POST.x, POST.z, Vector3(0.6, 2.4, 0.6)))
	out.append(_f("reception_desk", -1.6, 3.4, Vector3(0.8, 0.75, 1.4)))
	for x in [-19.0, -16.5, -14.0]:
		out.append(_f("bed", x, -11.5, Vector3(0.9, 0.6, 2.0)))
	out.append(_f("cabinet", -17.0, -5.75, Vector3(2.4, 2.0, 0.6)))
	out.append(_f("bed", -7.7, -12.6, Vector3(0.9, 0.5, 2.0)))
	out.append(_f("room_desk", -4.1, -14.1, Vector3(0.8, 0.75, 1.0)))
	out.append(_f("chair", -4.9, -14.1, Vector3(0.5, 0.9, 0.5), -PI * 0.5))
	out.append(_f("bed", -7.7, -5.0, Vector3(0.9, 0.5, 2.0)))
	out.append(_f("room_desk", -4.1, -3.9, Vector3(0.8, 0.75, 1.0)))
	out.append(_f("chair", -4.9, -3.9, Vector3(0.5, 0.9, 0.5), -PI * 0.5))
	for spot in [Vector2(14.0, -6.5), Vector2(17.5, -6.5), Vector2(15.75, -11.8)]:
		out.append(_f("table_set", spot.x, spot.y, Vector3(2.2, 0.75, 2.2)))
	out.append(_f("dispenser", 20.0, -9.0, Vector3(0.6, 1.8, 0.6)))
	return out

# The ramp up to the Commander's office (drawn as three steps): its rect
# on Main Mission's floor, rising toward +X to OFFICE_FLOOR.
static func office_ramp() -> Rect2:
	return Rect2(8.2, -26.4, 1.8, 4.8)

static func _route(department: String, points: Array) -> Dictionary:
	return {"department": department, "points": PackedVector3Array(points)}

# The walkers' ways, there and back again; Main Mission, medical, technical,
# security, command.
static func routes() -> Array:
	var v := func(x: float, z: float) -> Vector3: return Vector3(x, 0.0, z)
	return [
		_route("main_mission", [v.call(0.8, 2.4), v.call(0.0, 0.5), ROUND_N, ROUND_E, ROUND_S, v.call(0.0, -17.0), v.call(0.0, -19.0), v.call(6.0, -19.8), v.call(6.0, -28.5)]),
		_route("medical", [v.call(-13.0, -8.0), v.call(-12.0, -9.0), ROUND_W, ROUND_N, v.call(0.0, -2.0)]),
		_route("technical", [v.call(15.0, -9.0), v.call(10.8, -9.0), ROUND_E, ROUND_S, v.call(0.0, -17.0), v.call(0.0, -19.0), v.call(4.0, -19.5)]),
		_route("security", [v.call(0.8, 3.6), v.call(0.0, 0.5), ROUND_N, ROUND_W, v.call(-6.0, -9.0), v.call(-6.0, -12.3)]),
		_route("command", [v.call(-6.0, -5.7), v.call(-6.0, -9.0), ROUND_W, ROUND_S, v.call(0.0, -17.0), v.call(0.0, -19.0), v.call(5.0, -23.0)]),
		_route("medical", [v.call(-19.0, -7.5), v.call(-12.5, -7.5)]),
		_route("technical", [v.call(0.0, -1.0), ROUND_N, ROUND_W, ROUND_S, v.call(0.0, -16.5)]),
		_route("security", [v.call(12.0, -9.0), v.call(19.0, -9.0)]),
		_route("main_mission", [v.call(-0.8, 2.4), v.call(0.0, 0.5), ROUND_N, ROUND_E, v.call(10.8, -9.0), v.call(12.0, -9.0)]),
		_route("main_mission", [v.call(3.0, -21.0), v.call(3.0, -29.0)]),
	]

# The crew at work standing: {department, transform (facing their work)}.
static func workers() -> Array:
	return [
		{"department": "medical", "transform": Transform3D(Basis(), Vector3(-16.5, 0.0, -9.9))},
		{"department": "medical", "transform": Transform3D(Basis(), Vector3(-14.0, 0.0, -9.9))},
		{"department": "technical", "transform": Transform3D(Basis(), Vector3(8.5, 0.0, -28.8))},
		{"department": "command", "transform": Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(14.8, OFFICE_FLOOR, -22.0))},
	]
