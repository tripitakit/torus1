extends SceneTree

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const SectionGenerator = preload("res://scripts/section_generator.gd")
const DockPadTexture = preload("res://scripts/dock_pad_texture.gd")
const Clock = preload("res://scripts/interior_clock.gd")
const TerrainDressingScript = preload("res://scripts/terrain_dressing.gd")
const RoadTraffic = preload("res://scripts/road_traffic.gd")
const SpineTrain = preload("res://scripts/spine_train.gd")
const AirTraffic = preload("res://scripts/air_traffic.gd")
const LakeBoats = preload("res://scripts/lake_boats.gd")
const TownWalkers = preload("res://scripts/town_walkers.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0
const BRIDGE_RADIUS := 600.0
const BRIDGE_LENGTH := 1834.0
const PERIOD := LENGTH + BRIDGE_LENGTH

func _init():
	var failures := 0
	failures += _test_docking_builds_sections_minus_one_and_zero_and_three_bridges()
	failures += _test_sections_of_320_dressed_chunks_flat_ones_sharing_one_shape()
	failures += _test_terrain_vertices_at_their_height_facing_the_axis()
	failures += _test_terrain_chunks_tile_the_whole_wall()
	failures += _test_both_caps_open_and_facing_in()
	failures += _test_twenty_suns_per_section_on_the_axis()
	failures += _test_every_bridge_has_its_tube_and_textured_dock_but_no_lights()
	failures += _test_spawn_above_the_docked_bridge_platform()
	failures += _test_nearest_dock_slot_and_ring_numbers()
	failures += _test_nearest_section_slot_and_ring_numbers()
	failures += _test_only_the_named_sign_lights()
	failures += _test_sections_come_from_their_ring_indices()
	failures += _test_plan_from_the_worker_thread_matches_a_direct_one()
	failures += _test_loading_elsewhere_unloads_far_sections()
	failures += _test_pads_built_and_found()
	failures += _test_axis_lights_reach_the_ground_without_distance_falloff()
	failures += _test_every_light_fades_out_by_25_km()
	failures += _test_at_most_64_lights_within_25_km_along_the_chain()
	failures += _test_every_lit_object_gets_at_most_eight_lights()
	failures += _test_building_at_docking_takes_under_three_seconds()
	failures += _test_tube_and_caps_are_textured()
	failures += _test_hour_at_a_point_follows_the_ring()
	failures += _test_suns_follow_the_hour()
	failures += _test_ambient_dims_at_night_and_comes_back()
	failures += _test_windows_follow_the_hour_only_inside()
	failures += _test_cars_in_the_chunks_and_dots_in_the_section()
	failures += _test_spine_through_sections_and_bridges()
	failures += _test_stations_with_pylons_from_the_ground()
	failures += _test_trains_where_the_timetable_says()
	failures += _test_lifts_move()
	failures += _test_cruisers_and_strobes_in_each_section()
	failures += _test_boats_on_the_lakes()
	failures += _test_bridge_docks_stay_clear()
	failures += _test_piers_with_their_life()
	failures += _test_walkers_in_the_town_chunks()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_world(docked := 0) -> Node3D:
	var world: Node3D = InteriorWorldScript.new()
	world.section_radius = RADIUS
	world.section_length = LENGTH
	world.bridge_radius = BRIDGE_RADIUS
	world.bridge_length = BRIDGE_LENGTH
	world.docked_bridge_index = docked
	world.build()
	return world

func _world_transform(node: Node) -> Transform3D:
	var xform := Transform3D()
	var current := node
	while current != null and current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform

func _section_start(slot: int) -> float:
	return -(slot + 0.5) * PERIOD - LENGTH * 0.5

# Every vertex of `mesh` placed by `xform`: at `radius` from the axis, normal
# pointing toward the axis.
func _check_wall(test_name: String, mesh: Mesh, xform: Transform3D, radius: float) -> int:
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(vertices.size()):
			var v: Vector3 = xform * vertices[i]
			var n: Vector3 = xform.basis * normals[i]
			if absf(Vector2(v.x, v.y).length() - radius) > 0.01:
				print("FAIL %s: vertex %s is %.3f m from the axis, expected %.1f" % [test_name, v, Vector2(v.x, v.y).length(), radius])
				return 1
			if n.dot(Vector3(-v.x, -v.y, 0.0)) <= 0.0:
				print("FAIL %s: normal %s at %s points away from the axis" % [test_name, n, v])
				return 1
	return 0

func _test_docking_builds_sections_minus_one_and_zero_and_three_bridges() -> int:
	var world := _make_world()
	var result := 0
	if world.get_loaded_section_slots() != [-1, 0] or world.get_bridge_slots() != [-1, 0, 1]:
		print("FAIL _test_docking_builds_sections_minus_one_and_zero_and_three_bridges: sections %s bridges %s" % [world.get_loaded_section_slots(), world.get_bridge_slots()])
		result = 1
	for slot in [-1, 0]:
		var section := world.get_node_or_null("Chain/Section_%d" % slot) as Node3D
		if section == null or not world.is_section_ready(slot) or not is_equal_approx(section.position.z, -(slot + 0.5) * PERIOD):
			print("FAIL _test_docking_builds_sections_minus_one_and_zero_and_three_bridges: section %d missing, not ready or misplaced" % slot)
			result = 1
	for slot in [-1, 0, 1]:
		var bridge := world.get_node_or_null("Chain/Bridge_%d" % slot) as Node3D
		if bridge == null or not is_equal_approx(bridge.position.z, -slot * PERIOD):
			print("FAIL _test_docking_builds_sections_minus_one_and_zero_and_three_bridges: bridge %d missing or misplaced" % slot)
			result = 1
	world.free()
	return result

func _test_sections_of_320_dressed_chunks_flat_ones_sharing_one_shape() -> int:
	# Flat chunks share the level-0 trimesh; chunks with relief own theirs.
	var world := _make_world()
	var result := 0
	var shared: Shape3D = world._chunk_shape
	var owned := {}
	for slot in [-1, 0]:
		var section := world.get_node("Chain/Section_%d" % slot)
		var plan = world.get_section_plan(slot)
		var chunks := section.find_children("Chunk_*", "StaticBody3D", false, false)
		if chunks.size() != 320:
			print("FAIL _test_sections_of_320_dressed_chunks_flat_ones_sharing_one_shape: section %d has %d chunks, expected 320" % [slot, chunks.size()])
			result = 1
		for chunk in chunks:
			var parts := String(chunk.name).split("_")
			var raised: bool = plan.chunk_has_relief(int(parts[1]), int(parts[2]))
			var shape: Shape3D = (chunk.get_node("Collision") as CollisionShape3D).shape
			var dressed: bool = chunk.get_node_or_null("Surface") != null or chunk.get_node_or_null("Water") != null
			var right: bool = (shape != shared and not owned.has(shape)) if raised else shape == shared
			if not right or not (shape is ConcavePolygonShape3D) or not dressed:
				print("FAIL _test_sections_of_320_dressed_chunks_flat_ones_sharing_one_shape: section %d %s (relief %s) not dressed or wrong shape" % [slot, chunk.name, raised])
				result = 1
				break
			if raised:
				owned[shape] = true
	world.free()
	return result

func _test_terrain_vertices_at_their_height_facing_the_axis() -> int:
	# In the chunk's own frame (the Surface and Water nodes sit at its origin).
	var world := _make_world()
	var plan = world.get_section_plan(0)
	for key in [Vector2i(3, 7), Vector2i(10, 12)]:
		var chunk: Node3D = world.get_node("Chain/Section_0/Chunk_%02d_%02d" % [key.x, key.y])
		var start := Vector2(key.x * 3 * plan.lot_width, key.y * 4 * plan.lot_length)
		for part in ["Surface", "Water"]:
			var node := chunk.get_node_or_null(part) as MeshInstance3D
			if node == null:
				continue
			for s in range(node.mesh.get_surface_count()):
				var arrays: Array = node.mesh.surface_get_arrays(s)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in range(vertices.size()):
					var v: Vector3 = vertices[i]
					var expected: float = RADIUS - plan.height_at(start.x + atan2(v.y, v.x) * RADIUS, start.y + v.z)
					if absf(Vector2(v.x, v.y).length() - expected) > 0.01 or normals[i].dot(Vector3(-v.x, -v.y, 0.0)) <= 0.0:
						print("FAIL _test_terrain_vertices_at_their_height_facing_the_axis: chunk %s vertex %s at %.3f, expected %.3f" % [key, v, Vector2(v.x, v.y).length(), expected])
						world.free()
						return 1
	world.free()
	return 0

func _test_terrain_chunks_tile_the_whole_wall() -> int:
	var world := _make_world()
	var result := 0
	for slot in [-1, 0]:
		var first: Node3D = world.get_node("Chain/Section_%d/Chunk_00_00" % slot)
		var last: Node3D = world.get_node("Chain/Section_%d/Chunk_15_19" % slot)
		var start: float = _section_start(slot)
		var first_z: float = _world_transform(first).origin.z
		var last_z: float = _world_transform(last).origin.z
		if not is_equal_approx(first_z, start) or not is_equal_approx(last_z + 1000.0, start + LENGTH):
			print("FAIL _test_terrain_chunks_tile_the_whole_wall: section %d chunks span %f..%f expected %f..%f" % [slot, first_z, last_z + 1000.0, start, start + LENGTH])
			result = 1
		var last_angle: float = atan2(last.transform.basis.x.y, last.transform.basis.x.x)
		if not is_equal_approx(fposmod(last_angle, TAU), 15.0 * TAU / 16.0):
			print("FAIL _test_terrain_chunks_tile_the_whole_wall: section %d last chunk turned %f rad" % [slot, last_angle])
			result = 1
	world.free()
	return result

func _cap_min_radius_and_facing(cap: Node3D) -> Array:
	var mesh: Mesh = (cap.get_node("Mesh") as MeshInstance3D).mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var min_radius := INF
	for v in vertices:
		min_radius = minf(min_radius, Vector2(v.x, v.y).length())
	var facing_z: float = (cap.transform.basis * normals[0]).z
	return [min_radius, facing_z]

func _test_both_caps_open_and_facing_in() -> int:
	var world := _make_world()
	var result := 0
	for slot in [-1, 0]:
		var section := world.get_node("Chain/Section_%d" % slot)
		# [name, local z in section lengths, facing along Z]
		for c in [["CapBehind", 0.5, -1.0], ["CapAhead", -0.5, 1.0]]:
			var cap := section.get_node_or_null(c[0]) as StaticBody3D
			if cap == null:
				print("FAIL _test_both_caps_open_and_facing_in: section %d has no %s" % [slot, c[0]])
				result = 1
				continue
			var info: Array = _cap_min_radius_and_facing(cap)
			if absf(info[0] - BRIDGE_RADIUS) > 0.01 or signf(info[1]) != c[2] or not is_equal_approx(cap.position.z, c[1] * LENGTH):
				print("FAIL _test_both_caps_open_and_facing_in: section %d %s hole %f facing %f at z %f" % [slot, c[0], info[0], info[1], cap.position.z])
				result = 1
			if not ((cap.get_node("Collision") as CollisionShape3D).shape is ConcavePolygonShape3D):
				print("FAIL _test_both_caps_open_and_facing_in: section %d %s has no trimesh collision" % [slot, c[0]])
				result = 1
	world.free()
	return result

func _test_twenty_suns_per_section_on_the_axis() -> int:
	var world := _make_world()
	var result := 0
	for slot in [-1, 0]:
		var section := world.get_node("Chain/Section_%d" % slot)
		var suns := section.find_children("Sun_*", "Node3D", false, false)
		if suns.size() != 20:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: section %d has %d suns" % [slot, suns.size()])
			result = 1
			continue
		var first: Node3D = section.get_node("Sun_00")
		if not _world_transform(first).origin.is_equal_approx(Vector3(0.0, 0.0, _section_start(slot) + 500.0)):
			print("FAIL _test_twenty_suns_per_section_on_the_axis: section %d Sun_00 at %s" % [slot, _world_transform(first).origin])
			result = 1
		var light := first.get_node_or_null("Light") as OmniLight3D
		if light == null or not is_equal_approx(light.omni_range, 2600.0) or light.shadow_enabled or first.get_node_or_null("Globe") == null:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: section %d Sun_00 light or globe wrong" % slot)
			result = 1
	world.free()
	return result

func _test_every_bridge_has_its_tube_and_textured_dock_but_no_lights() -> int:
	var world := _make_world()
	var result := 0
	for slot in [-1, 0, 1]:
		var bridge: Node3D = world.get_node("Chain/Bridge_%d" % slot)
		for k in range(4):
			var segment := bridge.get_node_or_null("Segment_%d" % k) as StaticBody3D
			if segment == null or not is_equal_approx(segment.position.z, -BRIDGE_LENGTH * 0.5 + k * BRIDGE_LENGTH / 4.0):
				print("FAIL _test_every_bridge_has_its_tube_and_textured_dock_but_no_lights: bridge %d Segment_%d missing or misplaced" % [slot, k])
				result = 1
				continue
			var mesh: Mesh = (segment.get_node("Mesh") as MeshInstance3D).mesh
			result = maxi(result, _check_wall("_test_every_bridge_has_its_tube_and_textured_dock_but_no_lights", mesh, _world_transform(segment), BRIDGE_RADIUS))
		# No suns of its own: the tube is lit by the sections' suns.
		if bridge.find_children("Light_*", "OmniLight3D", false, false).size() > 0:
			print("FAIL _test_every_bridge_has_its_tube_and_textured_dock_but_no_lights: bridge %d still has its own lights" % slot)
			result = 1
		var platform_mesh := bridge.get_node_or_null("Dock/Platform/Mesh") as MeshInstance3D
		if platform_mesh == null or platform_mesh.material_override != DockPadTexture.platform_material(60.0):
			print("FAIL _test_every_bridge_has_its_tube_and_textured_dock_but_no_lights: bridge %d platform does not wear the dock pad texture" % slot)
			result = 1
		var platform := bridge.get_node_or_null("Dock/Platform") as StaticBody3D
		var undock_sign := bridge.get_node_or_null("Dock/Sign") as Label3D
		if platform == null or not platform.position.is_equal_approx(Vector3(0.0, -BRIDGE_RADIUS + 2.0, 0.0)) or bridge.get_node_or_null("Dock/Light") == null:
			print("FAIL _test_every_bridge_has_its_tube_and_textured_dock_but_no_lights: bridge %d dock platform or light wrong" % slot)
			result = 1
		if undock_sign == null or undock_sign.text != "UNDOCK  [F]" or not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
			print("FAIL _test_every_bridge_has_its_tube_and_textured_dock_but_no_lights: bridge %d sign missing, wrong text or not idle" % slot)
			result = 1
	world.free()
	return result

func _test_spawn_above_the_docked_bridge_platform() -> int:
	var world := _make_world()
	var result := 0
	var platform := Vector3(0.0, -BRIDGE_RADIUS + 2.0, 0.0)
	for slot in [-1, 0, 1]:
		var expected: Vector3 = platform + Vector3(0.0, 0.0, -slot * PERIOD)
		if not world.get_dock_position(slot).is_equal_approx(expected):
			print("FAIL _test_spawn_above_the_docked_bridge_platform: dock %d at %s, expected %s" % [slot, world.get_dock_position(slot), expected])
			result = 1
	var spawn: Transform3D = world.get_spawn_transform()
	if not spawn.origin.is_equal_approx(platform + Vector3(0.0, 24.0, 0.0)) or not spawn.basis.is_equal_approx(Basis()):
		print("FAIL _test_spawn_above_the_docked_bridge_platform: spawn %s" % spawn)
		result = 1
	world.free()
	return result

func _test_nearest_dock_slot_and_ring_numbers() -> int:
	var world := _make_world()
	var result := 0
	for c in [[Vector3(0.0, 0.0, -0.4 * PERIOD), 0], [Vector3(100.0, -300.0, -0.6 * PERIOD), 1], [Vector3(0.0, 0.0, 0.7 * PERIOD), -1]]:
		if world.nearest_dock_slot(c[0]) != c[1]:
			print("FAIL _test_nearest_dock_slot_and_ring_numbers: %s gave slot %d, expected %d" % [c[0], world.nearest_dock_slot(c[0]), c[1]])
			result = 1
	world.free()
	var last: Node3D = InteriorWorldScript.new()
	last.docked_bridge_index = 1999
	last.ring_sections = 2000
	if last.get_bridge_ring_index(0) != 1999 or last.get_bridge_ring_index(1) != 0 or last.get_bridge_ring_index(-1) != 1998:
		print("FAIL _test_nearest_dock_slot_and_ring_numbers: from bridge 1999, slots -1/0/1 are bridges %d/%d/%d" % [last.get_bridge_ring_index(-1), last.get_bridge_ring_index(0), last.get_bridge_ring_index(1)])
		result = 1
	last.free()
	return result

func _test_nearest_section_slot_and_ring_numbers() -> int:
	# Craft z picks which section it is inside of (not the nearest bridge);
	# the section's true ring index wraps like the bridges' does.
	var world := _make_world()
	var result := 0
	for c in [[Vector3(0.0, 0.0, -0.5 * PERIOD), 0], [Vector3(0.0, 0.0, -1.5 * PERIOD), 1], [Vector3(0.0, 0.0, 0.5 * PERIOD), -1]]:
		if world.nearest_section_slot(c[0]) != c[1]:
			print("FAIL _test_nearest_section_slot_and_ring_numbers: %s gave slot %d, expected %d" % [c[0], world.nearest_section_slot(c[0]), c[1]])
			result = 1
	world.free()
	var last: Node3D = InteriorWorldScript.new()
	last.docked_bridge_index = 1999
	last.ring_sections = 2000
	if last.get_section_ring_index(0) != 0 or last.get_section_ring_index(-1) != 1999:
		print("FAIL _test_nearest_section_slot_and_ring_numbers: from bridge 1999, sections at slot -1/0 are %d/%d" % [last.get_section_ring_index(-1), last.get_section_ring_index(0)])
		result = 1
	last.free()
	return result

func _sign_color(world: Node3D, slot: int) -> Color:
	return (world.get_node("Chain/Bridge_%d/Dock/Sign" % slot) as Label3D).modulate

func _test_only_the_named_sign_lights() -> int:
	var world := _make_world()
	var result := 0
	world.set_undock_ready(1, true)
	for slot in [-1, 0, 1]:
		var expected: Color = InteriorWorldScript.SIGN_READY_COLOR if slot == 1 else InteriorWorldScript.SIGN_IDLE_COLOR
		if not _sign_color(world, slot).is_equal_approx(expected):
			print("FAIL _test_only_the_named_sign_lights: sign %d is %s with slot 1 ready" % [slot, _sign_color(world, slot)])
			result = 1
	world.set_undock_ready(1, false)
	for slot in [-1, 0, 1]:
		if not _sign_color(world, slot).is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
			print("FAIL _test_only_the_named_sign_lights: sign %d still lit when nothing is ready" % slot)
			result = 1
	world.free()
	return result

func _test_sections_come_from_their_ring_indices() -> int:
	# Docked at the last bridge: behind is section 1999, ahead is section 0.
	var world := _make_world(1999)
	var result := 0
	var behind = world.get_section_plan(-1)
	var ahead = world.get_section_plan(0)
	if behind == null or ahead == null or behind.section_index != 1999 or ahead.section_index != 0:
		print("FAIL _test_sections_come_from_their_ring_indices: expected sections 1999 and 0")
		world.free()
		return 1
	var groups: Dictionary = ahead.group_buildings_by_chunk()
	var key: Vector2i = groups.keys()[0]
	var buildings := world.get_node_or_null("Chain/Section_0/Chunk_%02d_%02d/Buildings" % [key.x, key.y])
	var drawn := 0
	if buildings != null:
		for node in buildings.get_children():
			drawn += (node as MultiMeshInstance3D).multimesh.instance_count
	if drawn != groups[key].size():
		print("FAIL _test_sections_come_from_their_ring_indices: chunk %s draws %d of the plan's %d buildings" % [key, drawn, groups[key].size()])
		result = 1
	world.free()
	return result

func _test_plan_from_the_worker_thread_matches_a_direct_one() -> int:
	var world := _make_world()
	var threaded = world.get_section_plan(0)
	var direct = SectionGenerator.generate(1, RADIUS, LENGTH)
	var result := 0
	if threaded == null or threaded.zones != direct.zones or threaded.crops != direct.crops or threaded.road_west != direct.road_west or threaded.road_south != direct.road_south or threaded.building_x != direct.building_x or threaded.building_z != direct.building_z or threaded.building_size != direct.building_size:
		print("FAIL _test_plan_from_the_worker_thread_matches_a_direct_one: plans differ")
		result = 1
	world.free()
	return result

func _test_loading_elsewhere_unloads_far_sections() -> int:
	var world := _make_world()
	world.load_now(-2.2 * PERIOD)
	var result := 0
	if world.get_loaded_section_slots() != [1, 2] or world.get_bridge_slots() != [1, 2, 3]:
		print("FAIL _test_loading_elsewhere_unloads_far_sections: sections %s bridges %s, expected [1, 2] and [1, 2, 3]" % [world.get_loaded_section_slots(), world.get_bridge_slots()])
		result = 1
	for gone in ["Chain/Section_-1", "Chain/Section_0", "Chain/Bridge_-1", "Chain/Bridge_0"]:
		if world.get_node_or_null(gone) != null:
			print("FAIL _test_loading_elsewhere_unloads_far_sections: %s still there" % gone)
			result = 1
	# Collider shapes of the unloaded sections are gone; the loaded ones'
	# are all still cached (they would grow by thousands per section).
	var in_use := {}
	for slot in world.get_loaded_section_slots():
		for chunk in world.get_node("Chain/Section_%d" % slot).find_children("Chunk_*", "StaticBody3D", false, false):
			for key in chunk.get_meta("shape_keys", []):
				in_use[key] = true
	if world._dressing._convex_shapes.size() != in_use.size():
		print("FAIL _test_loading_elsewhere_unloads_far_sections: %d collider shapes cached, the loaded sections use %d" % [world._dressing._convex_shapes.size(), in_use.size()])
		result = 1
	if not world.is_section_ready(1) or not world.is_section_ready(2):
		print("FAIL _test_loading_elsewhere_unloads_far_sections: sections 1 and 2 not ready")
		result = 1
	world.free()
	return result

func _axis_lights(world: Node3D) -> Array:
	var lights := []
	for slot in world.get_loaded_section_slots():
		for sun in world.get_node("Chain/Section_%d" % slot).find_children("Sun_*", "Node3D", false, false):
			lights.append(sun.get_node("Light"))
	return lights

func _test_axis_lights_reach_the_ground_without_distance_falloff() -> int:
	# With the default attenuation 1.0 a light falls off as 1/d: 2000 m from the
	# axis a sun gives ~6e-4 of its energy and the ground reads near-black.
	var world := _make_world()
	var result := 0
	for light: OmniLight3D in _axis_lights(world):
		if light.omni_attenuation > 0.1:
			print("FAIL _test_axis_lights_reach_the_ground_without_distance_falloff: %s omni_attenuation=%f" % [light.name, light.omni_attenuation])
			result = 1
			break
	world.free()
	return result

func _test_every_light_fades_out_by_25_km() -> int:
	var world := _make_world()
	var result := 0
	for light: OmniLight3D in world.find_children("*", "OmniLight3D", true, false):
		if not light.distance_fade_enabled or not is_equal_approx(light.distance_fade_begin, 24000.0) or not is_equal_approx(light.distance_fade_length, 1000.0):
			print("FAIL _test_every_light_fades_out_by_25_km: %s/%s fade %s %f %f" % [light.get_parent().name, light.name, light.distance_fade_enabled, light.distance_fade_begin, light.distance_fade_length])
			result = 1
			break
	world.free()
	return result

func _test_at_most_64_lights_within_25_km_along_the_chain() -> int:
	# The renderer draws at most max_renderable_lights per frame and drops the
	# rest in cull order. Lights past their fade distance are not drawn, so
	# what counts is how many sit within 25 km of the camera.
	var world := _make_world()
	world.load_now(-0.5 * PERIOD)  # 3 sections, 4 bridges: the most ever loaded
	var budget: int = ProjectSettings.get_setting("rendering/limits/opengl/max_renderable_lights")
	var positions := []
	for light in world.find_children("*", "OmniLight3D", true, false):
		positions.append(_world_transform(light).origin)
	var worst := 0
	var z := 0.5 * PERIOD
	while z >= -1.5 * PERIOD:
		var count := 0
		for p: Vector3 in positions:
			if p.distance_to(Vector3(0.0, 0.0, z)) < 25000.0:
				count += 1
		worst = maxi(worst, count)
		z -= 500.0
	print("  %d interior lights loaded, at most %d within 25 km" % [positions.size(), worst])
	world.free()
	if worst > budget:
		print("FAIL _test_at_most_64_lights_within_25_km_along_the_chain: %d lights within 25 km, renderer draws %d" % [worst, budget])
		return 1
	return 0

func _test_every_lit_object_gets_at_most_eight_lights() -> int:
	# The engine pairs a light with an object when their bounding boxes meet;
	# an omni light's box is a cube of +/- its range. Past 8, lights drop.
	var world := _make_world()
	world.load_now(-0.5 * PERIOD)
	var light_boxes := []
	for light: OmniLight3D in world.find_children("*", "OmniLight3D", true, false):
		var reach := Vector3.ONE * light.omni_range
		light_boxes.append(AABB(_world_transform(light).origin - reach, reach * 2.0))
	var result := 0
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		var override := (node as GeometryInstance3D).material_override as ShaderMaterial
		if node.name == "Globe" or node is Label3D or (override != null and override.shader.code.contains("unshaded")):
			continue  # unshaded objects (sun globes, cars, spine...) and the signs are not lit
		var geometry := node as GeometryInstance3D
		var local: AABB = geometry.custom_aabb if geometry.custom_aabb.has_volume() else geometry.get_aabb()
		var box: AABB = _world_transform(geometry) * local
		var count := 0
		for light_box: AABB in light_boxes:
			if light_box.intersects(box):
				count += 1
		if count > 8:
			print("FAIL _test_every_lit_object_gets_at_most_eight_lights: %s/%s is reached by %d lights" % [geometry.get_parent().name, geometry.name, count])
			result = 1
			break
	world.free()
	return result

func _test_building_at_docking_takes_under_three_seconds() -> int:
	# Built on docking, behind the fade to black: target 1.5 s, fail past 3 s.
	var start := Time.get_ticks_msec()
	var world := _make_world()
	var elapsed := Time.get_ticks_msec() - start
	print("  interior build: %d ms" % elapsed)
	world.free()
	if elapsed > 3000:
		print("FAIL _test_building_at_docking_takes_under_three_seconds: %d ms" % elapsed)
		return 1
	return 0

func _test_tube_and_caps_are_textured() -> int:
	# Tube and end walls carry UVs and the interior panel textures.
	var world := _make_world()
	var result := 0
	var tube := world._tube_mesh as ArrayMesh
	var cap := world._cap_mesh as ArrayMesh
	var tube_uv: PackedVector2Array = tube.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var cap_uv: PackedVector2Array = cap.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	if tube_uv.is_empty() or cap_uv.is_empty():
		print("FAIL _test_tube_and_caps_are_textured: missing UVs (tube %d, cap %d)" % [tube_uv.size(), cap_uv.size()])
		world.free()
		return 1
	var cap_min := Vector2(INF, INF)
	var cap_max := -cap_min
	for uv in cap_uv:
		cap_min = cap_min.min(uv)
		cap_max = cap_max.max(uv)
	if not cap_min.is_equal_approx(Vector2.ZERO) or not cap_max.is_equal_approx(Vector2(world.CAP_TEXTURE_REPEATS, 1.0)):
		print("FAIL _test_tube_and_caps_are_textured: cap UVs %s .. %s" % [cap_min, cap_max])
		result = 1
	var tube_max := 0.0
	for uv in tube_uv:
		tube_max = maxf(tube_max, uv.y)
	if tube_max != roundf(tube_max) or tube_max < 1.0:
		print("FAIL _test_tube_and_caps_are_textured: a tube piece spans %f repeats, not a whole number" % tube_max)
		result = 1
	for m in [world._tube_material, world._cap_material]:
		if m == null or m.albedo_texture == null or m.normal_texture == null or not m.emission_enabled:
			print("FAIL _test_tube_and_caps_are_textured: material %s lacks its textures" % m)
			result = 1
	world.free()
	return result

func _test_hour_at_a_point_follows_the_ring() -> int:
	var world := _make_world(5)
	world.forced_hour = 3.0
	var result := 0
	for z in [0.0, -10917.0, 15000.0]:
		var expected := Clock.hour_at(3.0, Clock.ring_position(z, 5, PERIOD), 2000)
		if absf(world.hour_at(Vector3(0.0, -1900.0, z)) - expected) > 0.0001:
			print("FAIL _test_hour_at_a_point_follows_the_ring: z %.0f gives %.4f, expected %.4f" % [z, world.hour_at(Vector3(0.0, -1900.0, z)), expected])
			result = 1
	world.free()
	return result

func _test_suns_follow_the_hour() -> int:
	var world := _make_world()
	var result := 0
	for hour in [0.0, 12.0, 18.5]:
		world.forced_hour = hour
		world.update_daylight(null)
		for light: OmniLight3D in _axis_lights(world):
			var h: float = world.hour_at(_world_transform(light).origin)
			if absf(light.light_energy - InteriorWorldScript.SUN_ENERGY * Clock.daylight(h)) > 0.001 or not light.light_color.is_equal_approx(Clock.sun_color(h)):
				print("FAIL _test_suns_follow_the_hour: at %.1f h %s has %.3f %s" % [h, light.name, light.light_energy, light.light_color])
				world.free()
				return 1
	world.forced_hour = 0.0
	world.update_daylight(null)
	var dim: OmniLight3D = world.get_node("Chain/Section_0/Sun_00/Light")
	if dim.light_energy > InteriorWorldScript.SUN_ENERGY * 0.2:
		print("FAIL _test_suns_follow_the_hour: midnight sun at %.3f" % dim.light_energy)
		result = 1
	world.free()
	return result

func _test_ambient_dims_at_night_and_comes_back() -> int:
	var world := _make_world()
	var env := Environment.new()
	env.ambient_light_energy = 0.25
	world.forced_hour = 0.0
	world.update_daylight(env)
	var result := 0
	if env.ambient_light_energy > 0.25 * 0.5:
		print("FAIL _test_ambient_dims_at_night_and_comes_back: night ambient %.3f" % env.ambient_light_energy)
		result = 1
	world.restore_ambient()
	if not is_equal_approx(env.ambient_light_energy, 0.25):
		print("FAIL _test_ambient_dims_at_night_and_comes_back: restored to %.3f" % env.ambient_light_energy)
		result = 1
	world.free()
	return result

func _test_windows_follow_the_hour_only_inside() -> int:
	# The interior's buildings read the hour; the moon base's (same shader,
	# its own material) keep their fixed glow.
	var dressing = TerrainDressingScript.new()
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = TerrainDressingScript.BUILDING_SHADER
	if dressing.building_material.get_shader_parameter("use_hour") != true or shader_material.get_shader_parameter("use_hour") == true:
		print("FAIL _test_windows_follow_the_hour_only_inside: use_hour %s inside, %s by default" % [dressing.building_material.get_shader_parameter("use_hour"), shader_material.get_shader_parameter("use_hour")])
		return 1
	return 0

func _test_cars_in_the_chunks_and_dots_in_the_section() -> int:
	# Every chunk with road carries its cars (near, up to NEAR_END); the
	# section carries all of them as far dots.
	var world := _make_world()
	var plan = world.get_section_plan(0)
	var by_chunk := RoadTraffic.chunk_instances(plan, RoadTraffic.loops(plan))
	var section := world.get_node("Chain/Section_0")
	var total := 0
	for key: Vector2i in by_chunk:
		var node := section.get_node_or_null("Chunk_%02d_%02d/Traffic" % [key.x, key.y]) as MultiMeshInstance3D
		var count: int = (by_chunk[key] as PackedFloat32Array).size() / RoadTraffic.FLOATS
		total += count
		if node == null or node.multimesh.instance_count != count or not is_equal_approx(node.visibility_range_end, RoadTraffic.NEAR_END) or node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			print("FAIL _test_cars_in_the_chunks_and_dots_in_the_section: chunk %s traffic %s" % [key, node])
			world.free()
			return 1
	var far := section.get_node_or_null("TrafficFar") as MultiMeshInstance3D
	var result := 0
	if far == null or far.multimesh.instance_count != total or total < 1000:
		print("FAIL _test_cars_in_the_chunks_and_dots_in_the_section: far %s, %d cars" % [far, total])
		result = 1
	world.free()
	return result

func _radial(angle: float) -> Vector3:
	return Vector3(cos(angle), sin(angle), 0.0)

# Distance of a point from the axis.
func _radius(p: Vector3) -> float:
	return Vector2(p.x, p.y).length()

func _box_of(body: CollisionObject3D) -> BoxShape3D:
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			return (child as CollisionShape3D).shape
	return null

func _test_spine_through_sections_and_bridges() -> int:
	var world := _make_world()
	var result := 0
	var angle := SpineTrain.spine_angle()
	var pieces := []
	for slot in world.get_loaded_section_slots():
		pieces.append([world.get_node_or_null("Chain/Section_%d/Spine" % slot), LENGTH])
	for slot in world.get_bridge_slots():
		pieces.append([world.get_node_or_null("Chain/Bridge_%d/Spine" % slot), BRIDGE_LENGTH])
	for piece in pieces:
		var body := piece[0] as StaticBody3D
		var box := _box_of(body) if body != null else null
		if body == null or box == null or absf(box.size.z - piece[1]) > 0.01 or not body.position.is_equal_approx(_radial(angle) * SpineTrain.SPINE_RADIUS):
			print("FAIL _test_spine_through_sections_and_bridges: spine piece %s" % body)
			result = 1
			break
		# Light rings round core and trains every RING_SPACING, one MultiMesh.
		var rings := body.get_node_or_null("Rings") as MultiMeshInstance3D
		if rings == null or rings.multimesh.instance_count != floori(piece[1] / SpineTrain.RING_SPACING):
			print("FAIL _test_spine_through_sections_and_bridges: %s rings %s" % [body.get_path(), rings.multimesh.instance_count if rings != null else -1])
			result = 1
			break
	world.free()
	return result

func _test_stations_with_pylons_from_the_ground() -> int:
	# Two stations a section at the plan's station lots; each pylon stands on
	# the ground there and reaches the platform under the spine; no building
	# left in its lot.
	var world := _make_world()
	var result := 0
	var angle := SpineTrain.spine_angle()
	for slot in world.get_loaded_section_slots():
		var plan = world.get_section_plan(slot)
		var zs := SpineTrain.station_z(plan)
		var lots := SpineTrain.station_lots(plan)
		for k in range(2):
			var station := world.get_node_or_null("Chain/Section_%d/Station_%d" % [slot, k]) as Node3D
			var pylon := station.get_node_or_null("Pylon") as StaticBody3D if station != null else null
			if station == null or pylon == null or _box_of(pylon) == null or station.get_node_or_null("Platform") == null or station.get_node_or_null("Hall") == null:
				print("FAIL _test_stations_with_pylons_from_the_ground: section %d station %d incomplete" % [slot, k])
				world.free()
				return 1
			var ground: float = RADIUS - plan.height_at((SpineTrain.STATION_COLUMN + 0.5) * plan.lot_width, zs[k])
			var base: Vector3 = pylon.position
			var top: Vector3 = pylon.transform * Vector3(0.0, _box_of(pylon).size.y, 0.0)
			if absf(base.z - (zs[k] - LENGTH * 0.5)) > 0.01 or absf(_radius(base) - ground) > 0.5 or absf(_radius(top) - SpineTrain.platform_radius()) > 0.5 or _radial(angle).dot(Vector3(base.x, base.y, 0.0).normalized()) < 0.9999:
				print("FAIL _test_stations_with_pylons_from_the_ground: section %d pylon %d from radius %.1f (ground %.1f) to %.1f at z %.1f" % [slot, k, _radius(base), ground, _radius(top), base.z])
				result = 1
			var lot: int = plan.lot_index(SpineTrain.STATION_COLUMN, lots[k])
			for indices in world._sections[slot].groups.values():
				for b in indices:
					if plan.building_lot[b] == lot:
						print("FAIL _test_stations_with_pylons_from_the_ground: building %d still in station lot" % b)
						world.free()
						return 1
	world.free()
	return result

func _test_trains_where_the_timetable_says() -> int:
	var world := _make_world()
	var result := 0
	var total := SpineTrain.period_time(PERIOD)
	for t in [10.0, 333.3]:
		world.update_trains(t)
		for slot in world.get_loaded_section_slots():
			var plan = world.get_section_plan(slot)
			for way in [SpineTrain.AHEAD, SpineTrain.BACK]:
				var train := world.get_node_or_null("Chain/Section_%d/%s" % [slot, "TrainAhead" if way == SpineTrain.AHEAD else "TrainBack"]) as AnimatableBody3D
				var u := SpineTrain.progress(SpineTrain.train_tau(t, way, total), SpineTrain.stops(way, SpineTrain.station_z(plan), LENGTH, BRIDGE_LENGTH), PERIOD)
				var z := SpineTrain.train_node_z(way, u, LENGTH, BRIDGE_LENGTH)
				if train == null or _box_of(train) == null or absf(train.position.z - z) > 0.01 or absf(_radius(train.position) - SpineTrain.SPINE_RADIUS) > 20.0 or train.sync_to_physics:
					print("FAIL _test_trains_where_the_timetable_says: section %d way %d train %s at %s, expected z %.1f" % [slot, way, train, train.position if train != null else Vector3.ZERO, z])
					result = 1
	world.free()
	return result

func _test_lifts_move() -> int:
	var world := _make_world()
	var lift := world.get_node_or_null("Chain/Section_0/Station_0/Lift_0") as Node3D
	if lift == null:
		print("FAIL _test_lifts_move: no lift")
		world.free()
		return 1
	world.update_lifts(0.0)
	var a := lift.position
	world.update_lifts(30.0)
	var result := 0
	if a.distance_to(lift.position) < 100.0:
		print("FAIL _test_lifts_move: moved %.1f m in 30 s" % a.distance_to(lift.position))
		result = 1
	world.free()
	return result

func _test_cruisers_and_strobes_in_each_section() -> int:
	var world := _make_world()
	var result := 0
	for slot in world.get_loaded_section_slots():
		var count := AirTraffic.cruiser_count(AirTraffic.lanes(world.get_section_plan(slot)))
		for node_name in ["AirTraffic", "AirLights"]:
			var node := world.get_node_or_null("Chain/Section_%d/%s" % [slot, node_name]) as MultiMeshInstance3D
			if node == null or node.multimesh.instance_count != count or count < AirTraffic.CRAFT.x or not node.custom_aabb.has_volume():
				print("FAIL _test_cruisers_and_strobes_in_each_section: section %d %s %s (%d cruisers)" % [slot, node_name, node, count])
				result = 1
	world.free()
	return result

func _test_boats_on_the_lakes() -> int:
	var world := _make_world()
	var result := 0
	var seen := 0
	for slot in world.get_loaded_section_slots():
		var count := LakeBoats.routes(world.get_section_plan(slot)).size()
		var node := world.get_node_or_null("Chain/Section_%d/Boats" % slot) as MultiMeshInstance3D
		seen += count
		if (count > 0 and (node == null or node.multimesh.instance_count != count)) or (count == 0 and node != null):
			print("FAIL _test_boats_on_the_lakes: section %d %s for %d boats" % [slot, node, count])
			result = 1
	if seen == 0:
		print("FAIL _test_boats_on_the_lakes: no boats at all")
		result = 1
	world.free()
	return result

func _test_bridge_docks_stay_clear() -> int:
	# The craft's dock in the bridge has no crowd (the life is on the lakes'
	# piers).
	var world := _make_world()
	var result := 0
	for slot in world.get_bridge_slots():
		if world.get_node("Chain/Bridge_%d/Dock" % slot).find_children("*", "MultiMeshInstance3D", true, false).size() > 0:
			print("FAIL _test_bridge_docks_stay_clear: bridge %d dock has a crowd" % slot)
			result = 1
	world.free()
	return result

func _test_piers_with_their_life() -> int:
	var world := _make_world()
	var result := 0
	for slot in world.get_loaded_section_slots():
		var plan = world.get_section_plan(slot)
		var piers := LakeBoats.piers(plan)
		var people := 0
		for k in range(piers.size()):
			var pier := world.get_node_or_null("Chain/Section_%d/Pier_%d" % [slot, k]) as StaticBody3D
			if pier == null or _box_of(pier) == null:
				print("FAIL _test_piers_with_their_life: section %d pier %d %s" % [slot, k, pier])
				world.free()
				return 1
			people += LakeBoats.pier_people(plan, piers[k]).size()
		var crowd := world.get_node_or_null("Chain/Section_%d/PierPeople" % slot) as MultiMeshInstance3D
		if not piers.is_empty() and (crowd == null or crowd.multimesh.instance_count != people or world.get_node_or_null("Chain/Section_%d/PierCarts" % slot) == null or world.get_node_or_null("Chain/Section_%d/PierDrones" % slot) == null):
			print("FAIL _test_piers_with_their_life: section %d crowd %s for %d people" % [slot, crowd, people])
			result = 1
		# No building left on a pier's land lot.
		var lots := LakeBoats.pier_lots(plan)
		for indices in world._sections[slot].groups.values():
			for b in indices:
				if lots.has(plan.building_lot[b]):
					print("FAIL _test_piers_with_their_life: building %d on a pier's lot" % b)
					world.free()
					return 1
	world.free()
	return result

func _test_walkers_in_the_town_chunks() -> int:
	var world := _make_world()
	var result := 0
	var plan = world.get_section_plan(0)
	var by_chunk := TownWalkers.loops_by_chunk(plan)
	if by_chunk.is_empty():
		print("FAIL _test_walkers_in_the_town_chunks: no walkers")
		world.free()
		return 1
	for key: Vector2i in by_chunk:
		# On the section's node, not the chunk's: the loop shader reads its data
		# from the instance basis and needs a frame that is never turned.
		var node := world.get_node_or_null("Chain/Section_0/Walkers_%02d_%02d" % [key.x, key.y]) as MultiMeshInstance3D
		if node == null or node.multimesh.instance_count != (by_chunk[key] as Array).size() or not is_equal_approx(node.visibility_range_end, TownWalkers.VISIBLE_TO) or not _world_transform(node).basis.is_equal_approx(Basis()):
			print("FAIL _test_walkers_in_the_town_chunks: chunk %s %s" % [key, node])
			result = 1
			break
	world.free()
	return result

# The docked-beside sections' landing pads stand on their towns; the
# nearest is found with its top's centre, up toward the axis.
func _test_pads_built_and_found() -> int:
	const LandingPads = preload("res://scripts/landing_pads.gd")
	var world := _make_world()
	var pads := world.find_children("Pad_*", "StaticBody3D", true, false)
	var result := 0
	if pads.is_empty():
		print("FAIL _test_pads_built_and_found: no pads in the loaded sections")
		world.free()
		return 1
	var slab := _world_transform(pads[0])
	var up := slab.basis.y.normalized()
	var top := slab.origin + up * LandingPads.THICK * 0.5
	var probe := top + up * 50.0 + slab.basis.x.normalized() * 5.0
	var found: Dictionary = world.nearest_pad(probe)
	var axis_up := -Vector3(top.x, top.y, 0.0).normalized()
	if found.is_empty() or (found.transform as Transform3D).origin.distance_to(top) > 0.01 or (found.transform as Transform3D).basis.y.normalized().dot(axis_up) < 0.999 or absf(found.distance - probe.distance_to(top)) > 0.01:
		print("FAIL _test_pads_built_and_found: %s, expected top %s" % [found, top])
		result = 1
	world.free()
	return result
