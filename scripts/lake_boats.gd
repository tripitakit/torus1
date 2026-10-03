extends RefCounted

# Boats on a section's lakes. A lake is a group of water lots touching side
# by side (round the section too); its boats go round its largest rectangle
# of water lots, INSET from the shore, corners CORNER round
# (LoopTraffic, on the cylinder at the ground's radius). One boat every
# BOAT_SPACING of route, at least one a lake, the biggest lakes first, at
# most MAX_BOATS a section; all the boats of a lake at one speed (no
# overtaking), each lake its own way round.

const SectionPlanScript = preload("res://scripts/section_plan.gd")
const LoopTraffic = preload("res://scripts/loop_traffic.gd")
const RoadTraffic = preload("res://scripts/road_traffic.gd")

const INSET := 40.0
const CORNER := 30.0
const BOAT_SPACING := 500.0
const MAX_LAKES := 12
const MAX_BOATS := 40
const SPEEDS := Vector2(8.0, 12.0)
const PAINTS := [Color(0.92, 0.93, 0.95), Color(0.85, 0.87, 0.9), Color(0.32, 0.42, 0.55), Color(0.62, 0.64, 0.68), Color(0.45, 0.07, 0.08)]

# The lakes: arrays of lots Vector2i(around, along), biggest first.
static func lakes(plan) -> Array:
	var seen := {}
	var found := []
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var start := Vector2i(around, along)
			if seen.has(start) or plan.zone_at(around, along) != SectionPlanScript.Zone.WATER:
				continue
			var lake := []
			var queue := [start]
			seen[start] = true
			while not queue.is_empty():
				var lot: Vector2i = queue.pop_back()
				lake.append(lot)
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next := Vector2i(posmod(lot.x + step.x, SectionPlanScript.LOTS_AROUND), lot.y + step.y)
					if next.y < 0 or next.y >= SectionPlanScript.LOTS_ALONG or seen.has(next) or plan.zone_at(next.x, next.y) != SectionPlanScript.Zone.WATER:
						continue
					seen[next] = true
					queue.append(next)
			found.append(lake)
	found.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	return found

# The largest rectangle of water lots starting at one of the lake's lots
# (position: first lot, around may run on past the last column).
static func largest_rectangle(plan, lake: Array) -> Rect2i:
	var best := Rect2i(lake[0], Vector2i.ONE)
	for lot: Vector2i in lake:
		var rows := SectionPlanScript.LOTS_ALONG
		for width in range(1, SectionPlanScript.LOTS_AROUND + 1):
			var column := lot.x + width - 1
			var run := 0
			while lot.y + run < SectionPlanScript.LOTS_ALONG and run < rows and plan.zone_at(column, lot.y + run) == SectionPlanScript.Zone.WATER:
				run += 1
			rows = mini(rows, run)
			if rows == 0:
				break
			if width * rows > best.size.x * best.size.y:
				best = Rect2i(lot, Vector2i(width, rows))
	return best

# Every boat as a LoopTraffic loop (z in the section's frame).
static func routes(plan) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.section_index, "boats"])
	var found := []
	var id := 0
	for lake: Array in lakes(plan).slice(0, MAX_LAKES):
		if found.size() >= MAX_BOATS:
			break
		var rect := largest_rectangle(plan, lake)
		var x0: float = rect.position.x * plan.lot_width + INSET
		var z0: float = rect.position.y * plan.lot_length + INSET - plan.length * 0.5
		var w: float = rect.size.x * plan.lot_width - 2.0 * INSET
		var h: float = rect.size.y * plan.lot_length - 2.0 * INSET
		var probe := LoopTraffic.make_loop(LoopTraffic.CYLINDER, x0, z0, w, h, CORNER, 1.0, 0.0, plan.radius, 0)
		var boats := clampi(roundi(LoopTraffic.loop_length(probe) / BOAT_SPACING), 1, MAX_BOATS - found.size())
		var speed := rng.randf_range(SPEEDS.x, SPEEDS.y)
		var way := 1 if rng.randf() < 0.5 else -1
		var offset := rng.randf()
		for k in range(boats):
			var loop := LoopTraffic.make_loop(LoopTraffic.CYLINDER, x0, z0, w, h, CORNER, speed, fposmod(offset + float(k) / boats, 1.0), plan.radius, plan.section_index * 1000 + id)
			loop.laps *= way
			found.append(loop)
			id += 1
	return found

# A sci-fi hydrofoil about 11 m long, +Z forward, +X left, on the water at
# y = 0: faceted wedge hull, glass cabin, accent strips, twin tail fins, a
# white light at the bow and a flat white wake behind.
static func boat_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadTraffic._loft(st, [[-5.0, 1.4, 0.25, 1.0], [-2.0, 1.7, 0.1, 1.2], [3.0, 1.3, 0.2, 1.1], [5.6, 0.25, 0.6, 0.8]], 0.0)
	RoadTraffic._loft(st, [[-2.4, 0.95, 1.05, 1.35], [-0.6, 1.05, 1.05, 2.0], [1.6, 0.6, 1.05, 1.45]], 1.0)
	for side: float in [-1.0, 1.0]:
		RoadTraffic._box(st, Vector3(side * 1.62 - 0.06, 0.55, -4.0), Vector3(side * 1.62 + 0.06, 0.68, 2.6), 2.0)
		RoadTraffic._box(st, Vector3(side * 1.0 - 0.07, 1.1, -5.0), Vector3(side * 1.0 + 0.07, 2.0, -3.9), 0.0)
	RoadTraffic._box(st, Vector3(-0.25, 0.75, 5.3), Vector3(0.25, 0.9, 5.5), 3.0)
	# The wake: one face, up, spreading behind.
	RoadTraffic._face(st, [Vector3(1.2, 0.03, -5.0), Vector3(-1.2, 0.03, -5.0), Vector3(-3.5, 0.03, -16.0), Vector3(3.5, 0.03, -16.0)], Vector3(0.0, -1.0, -10.0), 5.0)
	st.index()
	return st.commit()
