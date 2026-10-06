extends RefCounted

# Plans in the Moonbase Alpha style (Selene, the far-side outposts): rooms on
# a 1.2 m panel grid, floor at y = 0, rects on the floor (x, z); from the
# rooms and doors, the solid walls and which room a point is in. Pure.

const WALL_THICK := 0.2
# Long walls in pieces no longer than this (each lit by its own lights).
const WALL_PIECE := 12.0

# One solid wall per line: every room's edges on it joined (the tunnel's
# own sides are the scene's), the doorways cut out, each piece reaching half
# a thickness past ends that are not a doorway (corners close), as tall as
# the tallest room it bounds, in pieces of WALL_PIECE at most:
# {from, to (Vector2 on the floor), height, window (Main Mission's far
# room edges listed in `windows`: [{room, edge: "z0"|"z1"|"x0"|"x1"}]), normal (Vector2), rooms: [room on the -normal side, on the +normal
# side] ("" for none)}.
static func walls(rooms: Array, doors: Array, windows: Array = []) -> Array:
	var lines := {}
	for room in rooms:
		if room.zone == "tube":
			continue
		var r: Rect2 = room.rect
		var top: float = room.floor + room.height
		for edge in [["z", r.position.y, r.position.x, r.end.x], ["z", r.end.y, r.position.x, r.end.x], ["x", r.position.x, r.position.y, r.end.y], ["x", r.end.x, r.position.y, r.end.y]]:
			var key := "%s:%.3f" % [edge[0], edge[1]]
			if not lines.has(key):
				lines[key] = {"axis": edge[0], "at": edge[1], "spans": []}
			lines[key].spans.append([edge[2], edge[3], top])
	var out := []
	for key in lines:
		var line: Dictionary = lines[key]
		var spans: Array = line.spans
		spans.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		var merged := []
		for span in spans:
			if not merged.is_empty() and span[0] <= merged[-1][1] + 0.001:
				merged[-1][1] = maxf(merged[-1][1], span[1])
				merged[-1][2] = maxf(merged[-1][2], span[2])
			else:
				merged.append(span.duplicate())
		# The doorways on this line, along it.
		var gaps := []
		for door in doors:
			var on_line: bool = (door.axis == "x" and line.axis == "z" and is_equal_approx(door.centre.z, line.at)) or (door.axis == "z" and line.axis == "x" and is_equal_approx(door.centre.x, line.at))
			if on_line:
				var c: float = door.centre.x if door.axis == "x" else door.centre.z
				gaps.append(Vector2(c - door.width * 0.5, c + door.width * 0.5))
		for span in merged:
			var pieces := [[span[0], span[1], false, false]]
			for gap: Vector2 in gaps:
				var next := []
				for piece in pieces:
					if gap.y <= piece[0] + 0.001 or gap.x >= piece[1] - 0.001:
						next.append(piece)
						continue
					if gap.x > piece[0] + 0.001:
						next.append([piece[0], gap.x, piece[2], true])
					if gap.y < piece[1] - 0.001:
						next.append([gap.y, piece[1], true, piece[3]])
				pieces = next
			for piece in pieces:
				var lo: float = piece[0] - (0.0 if piece[2] else WALL_THICK * 0.5)
				var hi: float = piece[1] + (0.0 if piece[3] else WALL_THICK * 0.5)
				var count := ceili((hi - lo) / WALL_PIECE - 1e-6)
				for i in range(count):
					var s0 := lo + (hi - lo) * i / count
					var s1 := lo + (hi - lo) * (i + 1) / count
					out.append(_wall(rooms, windows, line.axis, line.at, s0, s1, span[2]))
	return out

static func _wall(rooms: Array, windows: Array, axis: String, at: float, s0: float, s1: float, height: float) -> Dictionary:
	var a := Vector2(s0, at) if axis == "z" else Vector2(at, s0)
	var b := Vector2(s1, at) if axis == "z" else Vector2(at, s1)
	var normal := Vector2(0.0, 1.0) if axis == "z" else Vector2(1.0, 0.0)
	var mid := (a + b) * 0.5
	var probe := WALL_THICK
	var minus := room_at(rooms, Vector3(mid.x - normal.x * probe, 0.0, mid.y - normal.y * probe))
	var plus := room_at(rooms, Vector3(mid.x + normal.x * probe, 0.0, mid.y + normal.y * probe))
	var window := false
	for spec in windows:
		var r: Rect2 = _rect(rooms, spec.room)
		var edges := {"z0": ["z", r.position.y, r.position.x, r.end.x], "z1": ["z", r.end.y, r.position.x, r.end.x], "x0": ["x", r.position.x, r.position.y, r.end.y], "x1": ["x", r.end.x, r.position.y, r.end.y]}
		var edge: Array = edges[spec.edge]
		var along := mid.x if axis == "z" else mid.y
		if axis == edge[0] and is_equal_approx(at, edge[1]) and along > edge[2] and along < edge[3]:
			window = true
	return {"from": a, "to": b, "height": height, "window": window, "normal": normal, "rooms": [minus, plus]}

static func room_at(rooms: Array, point: Vector3) -> String:
	for room in rooms:
		if (room.rect as Rect2).has_point(Vector2(point.x, point.z)):
			return room.name
	return ""

static func _rect(rooms: Array, name: String) -> Rect2:
	for room in rooms:
		if room.name == name:
			return room.rect
	return Rect2()
