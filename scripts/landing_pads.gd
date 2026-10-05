extends RefCounted

# Landing pads for the internal cruiser (game_mode.gd lands it, the pilot
# walks from there): one for every group of touching town and city lots
# (round the section's seam too), on the group's free lot nearest the
# group's middle, that lot cleared of buildings. A square SIZE wide, a slab
# THICK deep standing PROUD above the ground (low enough to walk onto),
# glowing H and edge strips raised on it, four lamps at its corners.

const SectionPlanScript = preload("res://scripts/section_plan.gd")
const LakeBoats = preload("res://scripts/lake_boats.gd")
const SpineTrain = preload("res://scripts/spine_train.gd")
const RoadTraffic = preload("res://scripts/road_traffic.gd")

const SIZE := 30.0
const THICK := 0.6
const PROUD := 0.05
# The H and the edge strips stand this high on the slab (thin plates would
# flicker with the 24-bit depth from afar).
const STRIP := 0.15

# Groups of touching TOWN and CITY lots: arrays of Vector2i (around, along).
static func groups(plan) -> Array:
	var seen := {}
	var found := []
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var start := Vector2i(around, along)
			if seen.has(start) or not _built_up(plan, start):
				continue
			var group := []
			var open := [start]
			seen[start] = true
			while not open.is_empty():
				var lot: Vector2i = open.pop_back()
				group.append(lot)
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next := Vector2i(posmod(lot.x + step.x, SectionPlanScript.LOTS_AROUND), lot.y + step.y)
					if next.y < 0 or next.y >= SectionPlanScript.LOTS_ALONG or seen.has(next) or not _built_up(plan, next):
						continue
					seen[next] = true
					open.append(next)
			found.append(group)
	return found

static func _built_up(plan, lot: Vector2i) -> bool:
	var zone: int = plan.zone_at(lot.x, lot.y)
	return zone == SectionPlanScript.Zone.TOWN or zone == SectionPlanScript.Zone.CITY

# A group's middle (plan x, z), the arc averaged round the seam.
static func group_middle(plan, group: Array) -> Vector2:
	var turn := Vector2.ZERO
	var z := 0.0
	for lot: Vector2i in group:
		var centre: Vector2 = plan.lot_center(lot.x, lot.y)
		turn += Vector2.from_angle(centre.x / plan.circumference() * TAU)
		z += centre.y
	return Vector2(fposmod(turn.angle(), TAU) / TAU * plan.circumference(), z / group.size())

# Lots already taken by the piers' platforms and the train's stations.
static func taken_lots(plan) -> Array:
	var lots: Array = LakeBoats.pier_lots(plan)
	for along in SpineTrain.station_lots(plan):
		lots.append(plan.lot_index(SpineTrain.STATION_COLUMN, along))
	return lots

# {lot, centre (plan x, z)} for each group with a free lot, in groups' order.
static func pads(plan) -> Array:
	var taken := taken_lots(plan)
	var found := []
	for group: Array in groups(plan):
		var middle := group_middle(plan, group)
		var best := Vector2i(-1, -1)
		var best_gap := INF
		for lot: Vector2i in group:
			if taken.has(plan.lot_index(lot.x, lot.y)):
				continue
			var gap: float = plan.surface_distance(plan.lot_center(lot.x, lot.y), middle)
			if gap < best_gap:
				best_gap = gap
				best = lot
		if best.x >= 0:
			found.append({"lot": best, "centre": plan.lot_center(best.x, best.y)})
	return found

static func pad_lots(plan) -> Array:
	var lots := []
	for pad: Dictionary in pads(plan):
		lots.append(plan.lot_index(pad.lot.x, pad.lot.y))
	return lots

static func drop_pad_buildings(plan, groups_by_chunk: Dictionary) -> void:
	var lots := pad_lots(plan)
	for key in groups_by_chunk.keys():
		groups_by_chunk[key] = (groups_by_chunk[key] as Array).filter(func(b: int) -> bool: return not lots.has(plan.building_lot[b]))
		if (groups_by_chunk[key] as Array).is_empty():
			groups_by_chunk.erase(key)

# The pad, centred on its slab (top at +THICK / 2), y up, for the
# structures' shader: 0 slab, 2 glowing strips, 4 white lamps.
static func pad_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := SIZE * 0.5
	var top := THICK * 0.5
	RoadTraffic._box(st, Vector3(-half, -top, -half), Vector3(half, top, half), 0.0)
	# Edge strips a metre in from the rim.
	for side: float in [-1.0, 1.0]:
		var a := Vector3(side * (half - 1.0) - 0.3, top, -half + 0.7)
		var b := Vector3(side * (half - 1.0) + 0.3, top + STRIP, half - 0.7)
		RoadTraffic._box(st, a.min(b), a.max(b), 2.0)
		a = Vector3(-half + 1.3, top, side * (half - 1.0) - 0.3)
		b = Vector3(half - 1.3, top + STRIP, side * (half - 1.0) + 0.3)
		RoadTraffic._box(st, a.min(b), a.max(b), 2.0)
	# The H.
	for side: float in [-1.0, 1.0]:
		RoadTraffic._box(st, Vector3(side * 5.0 - 0.8, top, -7.0), Vector3(side * 5.0 + 0.8, top + STRIP, 7.0), 2.0)
	RoadTraffic._box(st, Vector3(-4.2, top, -0.8), Vector3(4.2, top + STRIP, 0.8), 2.0)
	# Lamps at the corners.
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			RoadTraffic._box(st, Vector3(x * (half - 0.4) - 0.25, top, z * (half - 0.4) - 0.25), Vector3(x * (half - 0.4) + 0.25, top + 0.5, z * (half - 0.4) + 0.25), 4.0)
	st.index()
	return st.commit()
