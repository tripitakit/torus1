extends SceneTree

# Landing pads for the internal cruiser: one for every group of touching
# town and city lots, on the group's lot nearest its middle, that lot
# cleared of buildings.

const LandingPads = preload("res://scripts/landing_pads.gd")
const SectionGenerator = preload("res://scripts/section_generator.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")
const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const TerrainDressing = preload("res://scripts/terrain_dressing.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0

var _plans := []

func _initialize():
	for index in [0, 7, 42, 311]:
		_plans.append(SectionGenerator.generate(index, RADIUS, LENGTH))
	var failures := 0
	failures += _test_one_pad_per_group()
	failures += _test_pad_on_the_lot_nearest_the_middle()
	failures += _test_pad_lot_has_no_buildings()
	failures += _test_groups_wrap_round()
	failures += _test_flat_ground_collision_matches_the_drawn_chords()
	failures += _test_pads_stand_proud_of_the_collision_ground()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_one_pad_per_group() -> int:
	var total := 0
	for plan in _plans:
		var groups: Array = LandingPads.groups(plan)
		var pads: Array = LandingPads.pads(plan)
		total += pads.size()
		if pads.size() != groups.size():
			print("FAIL _test_one_pad_per_group: section %d, %d groups, %d pads" % [plan.section_index, groups.size(), pads.size()])
			return 1
	if total == 0:
		print("FAIL _test_one_pad_per_group: no pads at all")
		return 1
	return 0

func _test_pad_on_the_lot_nearest_the_middle() -> int:
	for plan in _plans:
		var groups: Array = LandingPads.groups(plan)
		var pads: Array = LandingPads.pads(plan)
		for k in range(groups.size()):
			var group: Array = groups[k]
			var lot: Vector2i = pads[k].lot
			if not group.has(lot):
				print("FAIL _test_pad_on_the_lot_nearest_the_middle: pad lot %s not in its group" % lot)
				return 1
			var middle: Vector2 = LandingPads.group_middle(plan, group)
			var mine: float = plan.surface_distance(plan.lot_center(lot.x, lot.y), middle)
			for other: Vector2i in group:
				if plan.surface_distance(plan.lot_center(other.x, other.y), middle) < mine - 1e-6 and not LandingPads.taken_lots(plan).has(plan.lot_index(other.x, other.y)):
					print("FAIL _test_pad_on_the_lot_nearest_the_middle: lot %s nearer than %s" % [other, lot])
					return 1
			if pads[k].centre.distance_to(plan.lot_center(lot.x, lot.y)) > 1e-6:
				print("FAIL _test_pad_on_the_lot_nearest_the_middle: pad off its lot's middle")
				return 1
	return 0

func _test_pad_lot_has_no_buildings() -> int:
	for plan in _plans:
		var groups: Dictionary = plan.group_buildings_by_chunk()
		LandingPads.drop_pad_buildings(plan, groups)
		var lots: Array = LandingPads.pad_lots(plan)
		for key in groups:
			for b: int in groups[key]:
				if lots.has(plan.building_lot[b]):
					print("FAIL _test_pad_lot_has_no_buildings: building %d left on a pad lot" % b)
					return 1
	return 0

func _test_groups_wrap_round() -> int:
	var plan = SectionPlan.new()
	plan.radius = RADIUS
	plan.length = LENGTH
	plan.lot_width = TAU * RADIUS / SectionPlan.LOTS_AROUND
	plan.lot_length = LENGTH / SectionPlan.LOTS_ALONG
	plan.zones.resize(SectionPlan.LOTS_AROUND * SectionPlan.LOTS_ALONG)
	plan.zones.fill(SectionPlan.Zone.FIELD)
	plan.zones[plan.lot_index(0, 10)] = SectionPlan.Zone.TOWN
	plan.zones[plan.lot_index(SectionPlan.LOTS_AROUND - 1, 10)] = SectionPlan.Zone.CITY
	plan.zones[plan.lot_index(20, 40)] = SectionPlan.Zone.TOWN
	var groups: Array = LandingPads.groups(plan)
	if groups.size() != 2:
		print("FAIL _test_groups_wrap_round: %d groups" % groups.size())
		return 1
	return 0

# Flat chunks' collision band has the drawn ground's chords (RELIEF_POINTS_PER_LOT
# a lot): the feet stand on what is drawn.
func _test_flat_ground_collision_matches_the_drawn_chords() -> int:
	if InteriorWorldScript.CHUNK_ARC_SEGMENTS != SectionPlan.CHUNK_LOTS_AROUND * SectionPlan.RELIEF_POINTS_PER_LOT:
		print("FAIL _test_flat_ground_collision_matches_the_drawn_chords: %d strips a chunk" % InteriorWorldScript.CHUNK_ARC_SEGMENTS)
		return 1
	return 0

# The collision ground 20 m across from a pad's middle (still on its chord):
# with relief its real triangles, flat the band's chord.
func _ground_beside(plan, pad: Dictionary, frame: Transform3D) -> float:
	var up := frame.basis.y.normalized()
	var probe: Vector3 = frame.origin + frame.basis.x.normalized() * 20.0
	var lot: Vector2i = pad.lot
	var ca := lot.x / SectionPlan.CHUNK_LOTS_AROUND
	var cl := lot.y / SectionPlan.CHUNK_LOTS_ALONG
	if plan.chunk_has_relief(ca, cl):
		var chunk := Transform3D(Basis(Vector3(0.0, 0.0, 1.0), ca * TAU / InteriorWorldScript.CHUNKS_AROUND), Vector3(0.0, 0.0, -LENGTH * 0.5 + cl * InteriorWorldScript.CHUNK_LENGTH))
		var faces: PackedVector3Array = TerrainDressing.relief_collision_faces(plan, ca, cl)
		for i in range(0, faces.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(probe + up * 5.0, -up, chunk * faces[i], chunk * faces[i + 1], chunk * faces[i + 2])
			if hit != null:
				return ((hit as Vector3) - probe).dot(up)
		return INF
	var strip := TAU / InteriorWorldScript.CHUNKS_AROUND / InteriorWorldScript.CHUNK_ARC_SEGMENTS
	var angle := atan2(probe.y, probe.x)
	var middle := (floorf(angle / strip) + 0.5) * strip
	var ground := RADIUS * cos(strip * 0.5) / cos(angle - middle)
	return Vector2(probe.x, probe.y).length() - ground

func _test_pads_stand_proud_of_the_collision_ground() -> int:
	var relief := 0
	var flat := 0
	for plan in _plans:
		for pad: Dictionary in LandingPads.pads(plan):
			var frame: Transform3D = InteriorWorldScript.pad_frame(plan, pad, RADIUS, LENGTH)
			var bottom_of_proud: Vector3 = frame.origin + frame.basis.y.normalized() * (LandingPads.THICK * 0.5 - LandingPads.PROUD)
			var gap: float = _ground_beside(plan, pad, Transform3D(frame.basis, bottom_of_proud))
			if absf(gap) > 0.02:
				print("FAIL _test_pads_stand_proud_of_the_collision_ground: section %d lot %s, ground %.3f m off the pad's foot" % [plan.section_index, pad.lot, gap])
				return 1
			if plan.chunk_has_relief(pad.lot.x / SectionPlan.CHUNK_LOTS_AROUND, pad.lot.y / SectionPlan.CHUNK_LOTS_ALONG):
				relief += 1
			else:
				flat += 1
	if relief == 0 or flat == 0:
		print("FAIL _test_pads_stand_proud_of_the_collision_ground: %d pads on relief, %d flat (need both)" % [relief, flat])
		return 1
	return 0
