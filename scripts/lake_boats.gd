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
# Piers: the deck PIER_WIDTH wide, DECK_HEIGHT above the water, reaching
# from SHORE_OVERLAP onto the land to BOAT_CLEAR short of the route; the
# platform PLATFORM_HALF either way, on the land.
const PIER_WIDTH := 12.0
const DECK_HEIGHT := 2.0
const SHORE_OVERLAP := 2.0
const BOAT_CLEAR := 3.0
const PLATFORM_HALF := 12.0
const PIER_PEOPLE := 8
const PIER_CARTS := 2
const PIER_DRONES := 2
const PEOPLE_CORNER := 1.5
const CART_LANE := 6.0
const CART_CORNER := 3.0
const DRONE_CORNER := 5.0
const DRONE_HEIGHT := 15.0
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

# The lakes that get boats, biggest first: {rect (lots), boats, speed,
# way, offset}. Shared by routes and piers so both see the same lakes.
static func _lakes_with_boats(plan) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.section_index, "boats"])
	var found := []
	var total := 0
	for lake: Array in lakes(plan).slice(0, MAX_LAKES):
		if total >= MAX_BOATS:
			break
		var rect := largest_rectangle(plan, lake)
		var route := _route_loop(plan, rect, 1.0)
		var boats := clampi(roundi(LoopTraffic.loop_length(route) / BOAT_SPACING), 1, MAX_BOATS - total)
		found.append({"rect": rect, "boats": boats, "speed": rng.randf_range(SPEEDS.x, SPEEDS.y), "way": 1 if rng.randf() < 0.5 else -1, "offset": rng.randf()})
		total += boats
	return found

# The route round a lake's rectangle of lots, inset (z in the section's frame).
static func _route_loop(plan, rect: Rect2i, speed: float) -> Dictionary:
	var x0: float = rect.position.x * plan.lot_width + INSET
	var z0: float = rect.position.y * plan.lot_length + INSET - plan.length * 0.5
	var w: float = rect.size.x * plan.lot_width - 2.0 * INSET
	var h: float = rect.size.y * plan.lot_length - 2.0 * INSET
	return LoopTraffic.make_loop(LoopTraffic.CYLINDER, x0, z0, w, h, CORNER, speed, 0.0, plan.radius, 0)

# Every boat as a LoopTraffic loop (z in the section's frame); on a lake
# with a pier each boat stops at its end once a lap, the boats a lap's share
# apart in time.
static func routes(plan) -> Array:
	var found := []
	var id := 0
	for lake: Dictionary in _lakes_with_boats(plan):
		var pier := _pier(plan, lake.rect)
		for k in range(lake.boats):
			var loop := _route_loop(plan, lake.rect, lake.speed)
			loop.phase = fposmod(lake.offset + float(k) / lake.boats, 1.0) * LoopTraffic.loop_length(loop)
			loop.id = plan.section_index * 1000 + id
			loop.laps *= lake.way
			if not pier.is_empty():
				LoopTraffic.with_stop(loop, pier.stop, lake.speed, 0.0)
				loop.phase = fposmod(lake.offset + float(k) / lake.boats, 1.0) * LoopTraffic.lap_time(loop)
			found.append(loop)
			id += 1
	return found

# A pier on every lake with boats that has flat land on its rectangle's
# shore: see _pier.
static func piers(plan) -> Array:
	var found := []
	for lake: Dictionary in _lakes_with_boats(plan):
		var pier := _pier(plan, lake.rect)
		if not pier.is_empty():
			found.append(pier)
	return found

# The pier of a lake rectangle (plan x, z): a deck PIER_WIDTH wide from the
# shore to just short of the route, a loading platform on the land behind
# it; {deck, platform, end (where the boats stop), stop (metres round the
# route), lot (the land lot), axis (0: deck along x, 1: along z)}. On the
# side's land lot nearest the side's middle whose middle lies on the
# route's straight; empty if none.
static func _pier(plan, rect: Rect2i) -> Dictionary:
	var lw: float = plan.lot_width
	var ll: float = plan.lot_length
	var route := _route_loop(plan, rect, 1.0)
	var c := CORNER
	var a: float = route.w - 2.0 * c
	var b: float = route.h - 2.0 * c
	var q := PI * 0.5 * c
	var x0r: float = route.x0
	var z0r: float = route.z0 + plan.length * 0.5
	var best := {}
	var best_gap := INF
	for side in range(4):
		var count := rect.size.x if side % 2 == 0 else rect.size.y
		for i in range(count):
			var lot: Vector2i
			if side == 0:
				lot = Vector2i(rect.position.x + i, rect.position.y - 1)
			elif side == 1:
				lot = Vector2i(rect.position.x + rect.size.x, rect.position.y + i)
			elif side == 2:
				lot = Vector2i(rect.position.x + i, rect.position.y + rect.size.y)
			else:
				lot = Vector2i(rect.position.x - 1, rect.position.y + i)
			if lot.y < 0 or lot.y >= SectionPlanScript.LOTS_ALONG:
				continue
			var zone: int = plan.zone_at(lot.x, lot.y)
			if zone == SectionPlanScript.Zone.WATER or SectionPlanScript.is_raised(zone):
				continue
			var gap := absf(i + 0.5 - count * 0.5)
			if gap >= best_gap:
				continue
			var pier := {}
			var half := PIER_WIDTH * 0.5
			if side % 2 == 0:
				var px: float = (lot.x + 0.5) * lw
				if px < x0r + c + half or px > x0r + route.w - c - half:
					continue
				var shore: float = rect.position.y * ll if side == 0 else (rect.position.y + rect.size.y) * ll
				var line: float = shore + INSET if side == 0 else shore - INSET
				var out := -1.0 if side == 0 else 1.0
				var near_end: float = line - BOAT_CLEAR * -out
				pier.deck = Rect2(px - half, minf(shore + out * SHORE_OVERLAP, near_end), PIER_WIDTH, absf(near_end - (shore + out * SHORE_OVERLAP)))
				pier.platform = Rect2(px - PLATFORM_HALF, shore + (0.0 if side == 2 else -2.0 * PLATFORM_HALF), 2.0 * PLATFORM_HALF, 2.0 * PLATFORM_HALF)
				pier.end = Vector2(px, near_end)
				pier.stop = (px - (x0r + c)) if side == 0 else (a + q + b + q + (x0r + route.w - c - px))
				pier.axis = 1
			else:
				var pz: float = (lot.y + 0.5) * ll
				if pz < z0r + c + half or pz > z0r + route.h - c - half:
					continue
				var shore_x: float = (rect.position.x + rect.size.x) * lw if side == 1 else rect.position.x * lw
				var line_x: float = shore_x - INSET if side == 1 else shore_x + INSET
				var out_x := 1.0 if side == 1 else -1.0
				var near_x: float = line_x + BOAT_CLEAR * out_x
				pier.deck = Rect2(minf(shore_x + out_x * SHORE_OVERLAP, near_x), pz - half, absf(near_x - (shore_x + out_x * SHORE_OVERLAP)), PIER_WIDTH)
				pier.platform = Rect2(shore_x + (0.0 if side == 1 else -2.0 * PLATFORM_HALF), pz - PLATFORM_HALF, 2.0 * PLATFORM_HALF, 2.0 * PLATFORM_HALF)
				pier.end = Vector2(near_x, pz)
				pier.stop = (a + q + (pz - (z0r + c))) if side == 1 else (2.0 * a + b + 3.0 * q + (z0r + route.h - c - pz))
				pier.axis = 0
			pier.lot = lot
			best = pier
			best_gap = gap
	return best

# The pier's land lot indices (their buildings make room for the platform).
static func pier_lots(plan) -> Array:
	var lots := []
	for pier: Dictionary in piers(plan):
		lots.append(plan.lot_index(pier.lot.x, pier.lot.y))
	return lots

static func drop_pier_buildings(plan, groups: Dictionary) -> void:
	var lots := pier_lots(plan)
	for key in groups.keys():
		groups[key] = (groups[key] as Array).filter(func(b: int) -> bool: return not lots.has(plan.building_lot[b]))
		if (groups[key] as Array).is_empty():
			groups.erase(key)

# A loop over plan rectangle `r` (x, z) at `height` above the ground, its x
# measured at that radius (LoopTraffic's cylinder).
static func _loop_over(plan, r: Rect2, corner: float, speed: float, phase_share: float, height: float, id: int) -> Dictionary:
	var level: float = plan.radius - height
	var scale: float = level / plan.radius
	return LoopTraffic.make_loop(LoopTraffic.CYLINDER, r.position.x * scale, r.position.y - plan.length * 0.5, r.size.x * scale, r.size.y, corner, speed, phase_share, level, id)

# People walking round square loops on the platform.
static func pier_people(plan, pier: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.section_index, pier.lot, "people"])
	var found := []
	var centre: Vector2 = (pier.platform as Rect2).get_center()
	for k in range(PIER_PEOPLE):
		var half := rng.randf_range(3.0, PLATFORM_HALF - 2.0)
		var loop := _loop_over(plan, Rect2(centre - Vector2(half, half), Vector2(2.0 * half, 2.0 * half)), PEOPLE_CORNER, rng.randf_range(1.2, 1.6), rng.randf(), DECK_HEIGHT, k)
		if rng.randf() < 0.5:
			loop.laps = -loop.laps
		found.append(loop)
	return found

# The strip from the platform's middle to the deck's end, `width` across.
static func _run(pier: Dictionary, width: float) -> Rect2:
	var centre: Vector2 = (pier.platform as Rect2).get_center()
	var end: Vector2 = pier.end
	var run := Rect2(centre, Vector2.ZERO).expand(end)
	if pier.axis == 1:
		return Rect2(centre.x - width * 0.5, run.position.y, width, run.size.y)
	return Rect2(run.position.x, centre.y - width * 0.5, run.size.x, width)

# Carts shuttling along the deck and back.
static func pier_carts(plan, pier: Dictionary) -> Array:
	var found := []
	for k in range(PIER_CARTS):
		found.append(_loop_over(plan, _run(pier, CART_LANE), CART_CORNER, 4.0, float(k) / PIER_CARTS, DECK_HEIGHT, k))
	return found

# Drones flying from the platform to the deck's end and back.
static func pier_drones(plan, pier: Dictionary) -> Array:
	var found := []
	for k in range(PIER_DRONES):
		found.append(_loop_over(plan, _run(pier, 2.0 * DRONE_CORNER), DRONE_CORNER, 3.0, float(k) / PIER_DRONES, DRONE_HEIGHT, k))
	return found

# A sci-fi hydrofoil about 11 m long, +Z forward, +X left, on the water at
# y = 0: faceted wedge hull, glass cabin, accent strips, twin tail fins, a
# white light at the bow. (A flat wake on the water flickered against it.)
static func boat_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadTraffic._loft(st, [[-5.0, 1.4, 0.25, 1.0], [-2.0, 1.7, 0.1, 1.2], [3.0, 1.3, 0.2, 1.1], [5.6, 0.25, 0.6, 0.8]], 0.0)
	RoadTraffic._loft(st, [[-2.4, 0.95, 1.05, 1.35], [-0.6, 1.05, 1.05, 2.0], [1.6, 0.6, 1.05, 1.45]], 1.0)
	for side: float in [-1.0, 1.0]:
		RoadTraffic._box(st, Vector3(side * 1.62 - 0.06, 0.55, -4.0), Vector3(side * 1.62 + 0.06, 0.68, 2.6), 2.0)
		RoadTraffic._box(st, Vector3(side * 1.0 - 0.07, 1.1, -5.0), Vector3(side * 1.0 + 0.07, 2.0, -3.9), 0.0)
	RoadTraffic._box(st, Vector3(-0.25, 0.75, 5.3), Vector3(0.25, 0.9, 5.5), 3.0)
	st.index()
	return st.commit()

# A pier deck or platform `size` (x across, y thick, z along), centred: hull
# with glowing strips along its top edges.
static func pier_mesh(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	RoadTraffic._box(st, -half, half, 0.0)
	for side: float in [-1.0, 1.0]:
		RoadTraffic._box(st, Vector3(side * half.x - 0.2, half.y - 0.3, -half.z), Vector3(side * half.x + 0.2, half.y + 0.1, half.z), 2.0)
		RoadTraffic._box(st, Vector3(-half.x, half.y - 0.3, side * half.z - 0.2), Vector3(half.x, half.y + 0.1, side * half.z + 0.2), 2.0)
	st.index()
	return st.commit()
