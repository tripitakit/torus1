extends RefCounted

# People walking in the towns and the city: in every built lot, PER_LOT
# people on a few walking loops (LoopTraffic, on the ground) placed at
# random in the open space between the buildings, CLEAR of every building
# and off the lot's edge roads. Moved by the shader; half of them go home at
# night (the material's night_hide).

const SectionPlanScript = preload("res://scripts/section_plan.gd")
const LoopTraffic = preload("res://scripts/loop_traffic.gd")

const PER_LOT := Vector2i(10, 20)
const LOOPS_PER_LOT := 5
const TRIES := 30
const LOOP_SIZES := Vector2(8.0, 30.0)
const CLEAR := 2.0
const ROAD_CLEAR := 2.0
const CORNER := 2.0
const SPEEDS := Vector2(1.0, 1.5)
const VISIBLE_TO := 500.0

static func _built(zone: int) -> bool:
	return zone == SectionPlanScript.Zone.TOWN or zone == SectionPlanScript.Zone.CITY

# Every walker as a loop (z in the section's frame, `lot` its lot index),
# by chunk: Vector2i(chunk around, chunk along) -> Array. Pure: safe on a
# worker thread.
static func loops_by_chunk(plan) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.section_index, "walkers"])
	var buildings := {}
	for b in range(plan.building_count()):
		var lot: int = plan.building_lot[b]
		if not buildings.has(lot):
			buildings[lot] = []
		buildings[lot].append(Rect2(plan.building_x[b] - plan.building_size[b].x * 0.5, plan.building_z[b] - plan.building_size[b].z * 0.5, plan.building_size[b].x, plan.building_size[b].z).grow(CLEAR))
	var found := {}
	var id := 0
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			if not _built(plan.zone_at(around, along)):
				continue
			var lot: int = plan.lot_index(around, along)
			var x0: float = around * plan.lot_width + SectionPlanScript.road_width(plan.road_on_west(around, along)) * 0.5 + ROAD_CLEAR
			var x1: float = (around + 1) * plan.lot_width - SectionPlanScript.road_width(plan.road_on_east(around, along)) * 0.5 - ROAD_CLEAR
			var z0: float = along * plan.lot_length + SectionPlanScript.road_width(plan.road_on_south(around, along)) * 0.5 + ROAD_CLEAR
			var z1: float = (along + 1) * plan.lot_length - SectionPlanScript.road_width(plan.road_on_north(around, along)) * 0.5 - ROAD_CLEAR
			var blocked: Array = buildings.get(lot, [])
			var rects := []
			for t in range(TRIES):
				if rects.size() >= LOOPS_PER_LOT:
					break
				var w := rng.randf_range(LOOP_SIZES.x, minf(LOOP_SIZES.y, x1 - x0))
				var h := rng.randf_range(LOOP_SIZES.x, minf(LOOP_SIZES.y, z1 - z0))
				var r := Rect2(rng.randf_range(x0, x1 - w), rng.randf_range(z0, z1 - h), w, h)
				if not blocked.any(func(box: Rect2) -> bool: return box.intersects(r)):
					rects.append(r)
			if rects.is_empty():
				continue
			var key := Vector2i(around / SectionPlanScript.CHUNK_LOTS_AROUND, along / SectionPlanScript.CHUNK_LOTS_ALONG)
			if not found.has(key):
				found[key] = []
			for k in range(rng.randi_range(PER_LOT.x, PER_LOT.y)):
				var r: Rect2 = rects[rng.randi() % rects.size()]
				var loop := LoopTraffic.make_loop(LoopTraffic.CYLINDER, r.position.x, r.position.y - plan.length * 0.5, r.size.x, r.size.y, CORNER, rng.randf_range(SPEEDS.x, SPEEDS.y), rng.randf(), plan.radius, id)
				if rng.randf() < 0.5:
					loop.laps = -loop.laps
				loop.lot = lot
				found[key].append(loop)
				id += 1
	return found

# The animated walkers drawn near the camera go in small groups, one per lot:
# [{loops, bounds}], the bounds (section frame) holding every walker's feet
# and head all round its loop. Pure: safe on a worker thread.
static func near_groups(loops: Array) -> Array:
	var by_lot := {}
	for loop: Dictionary in loops:
		if not by_lot.has(loop.lot):
			by_lot[loop.lot] = []
		by_lot[loop.lot].append(loop)
	var out := []
	for lot in by_lot:
		var bounds := AABB()
		var first := true
		# Each loop stays in its rect on the wall (x along the arc): its
		# corners and a few points along the arc, at the feet and the head.
		var rects := {}
		for loop: Dictionary in by_lot[lot]:
			rects[Rect2(loop.x0, loop.z0, loop.w, loop.h)] = loop.level
		for rect: Rect2 in rects:
			var level: float = rects[rect]
			for i in range(5):
				var angle := (rect.position.x + rect.size.x * i / 4.0) / level
				for r in [level, level - 2.0]:
					for z in [rect.position.y, rect.end.y]:
						var point := Vector3(cos(angle) * r, sin(angle) * r, z)
						if first:
							bounds = AABB(point, Vector3.ZERO)
							first = false
						else:
							bounds = bounds.expand(point)
		out.append({"loops": by_lot[lot], "bounds": bounds.grow(0.5)})
	return out

# How far (to the bounds' centre) a group stays drawn: DETAIL_TO past its
# farthest corner.
static func near_range(bounds: AABB) -> float:
	return LoopTraffic.DETAIL_TO + bounds.size.length() * 0.5 + 2.0
