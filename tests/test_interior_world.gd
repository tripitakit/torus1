extends SceneTree

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const SectionGenerator = preload("res://scripts/section_generator.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0
const BRIDGE_RADIUS := 600.0
const BRIDGE_LENGTH := 1834.0
const PERIOD := LENGTH + BRIDGE_LENGTH

func _init():
	var failures := 0
	failures += _test_docking_builds_sections_minus_one_and_zero_and_three_bridges()
	failures += _test_sections_of_320_dressed_chunks_sharing_one_collision_shape()
	failures += _test_terrain_vertices_on_the_wall_facing_the_axis()
	failures += _test_terrain_chunks_tile_the_whole_wall()
	failures += _test_both_caps_open_and_facing_in()
	failures += _test_twenty_suns_per_section_on_the_axis()
	failures += _test_every_bridge_has_its_tube_lights_and_dock()
	failures += _test_spawn_above_the_docked_bridge_platform()
	failures += _test_nearest_dock_slot_and_ring_numbers()
	failures += _test_only_the_named_sign_lights()
	failures += _test_sections_come_from_their_ring_indices()
	failures += _test_plan_from_the_worker_thread_matches_a_direct_one()
	failures += _test_loading_elsewhere_unloads_far_sections()
	failures += _test_axis_lights_reach_the_ground_without_distance_falloff()
	failures += _test_every_light_fades_out_by_25_km()
	failures += _test_at_most_64_lights_within_25_km_along_the_chain()
	failures += _test_every_lit_object_gets_at_most_eight_lights()
	failures += _test_building_at_docking_takes_under_three_seconds()

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

func _test_sections_of_320_dressed_chunks_sharing_one_collision_shape() -> int:
	var world := _make_world()
	var result := 0
	var first_shape: Shape3D = null
	for slot in [-1, 0]:
		var section := world.get_node("Chain/Section_%d" % slot)
		var chunks := section.find_children("Chunk_*", "StaticBody3D", false, false)
		if chunks.size() != 320:
			print("FAIL _test_sections_of_320_dressed_chunks_sharing_one_collision_shape: section %d has %d chunks, expected 320" % [slot, chunks.size()])
			result = 1
		for chunk in chunks:
			var shape: Shape3D = (chunk.get_node("Collision") as CollisionShape3D).shape
			if first_shape == null:
				first_shape = shape
			var dressed: bool = chunk.get_node_or_null("Surface") != null or chunk.get_node_or_null("Water") != null
			if shape != first_shape or not (shape is ConcavePolygonShape3D) or not dressed:
				print("FAIL _test_sections_of_320_dressed_chunks_sharing_one_collision_shape: section %d %s not dressed or not sharing the trimesh shape" % [slot, chunk.name])
				result = 1
				break
	world.free()
	return result

func _test_terrain_vertices_on_the_wall_facing_the_axis() -> int:
	var world := _make_world()
	var chunk: Node3D = world.get_node("Chain/Section_0/Chunk_03_07")
	var result := 0
	for part in ["Surface", "Water"]:
		var node := chunk.get_node_or_null(part) as MeshInstance3D
		if node:
			result = maxi(result, _check_wall("_test_terrain_vertices_on_the_wall_facing_the_axis", node.mesh, _world_transform(chunk), RADIUS))
	world.free()
	return result

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

func _test_every_bridge_has_its_tube_lights_and_dock() -> int:
	var world := _make_world()
	var result := 0
	for slot in [-1, 0, 1]:
		var bridge: Node3D = world.get_node("Chain/Bridge_%d" % slot)
		for k in range(4):
			var segment := bridge.get_node_or_null("Segment_%d" % k) as StaticBody3D
			if segment == null or not is_equal_approx(segment.position.z, -BRIDGE_LENGTH * 0.5 + k * BRIDGE_LENGTH / 4.0):
				print("FAIL _test_every_bridge_has_its_tube_lights_and_dock: bridge %d Segment_%d missing or misplaced" % [slot, k])
				result = 1
				continue
			var mesh: Mesh = (segment.get_node("Mesh") as MeshInstance3D).mesh
			result = maxi(result, _check_wall("_test_every_bridge_has_its_tube_lights_and_dock", mesh, _world_transform(segment), BRIDGE_RADIUS))
		for k in range(3):
			var light := bridge.get_node_or_null("Light_%d" % k) as OmniLight3D
			if light == null or not light.position.is_equal_approx(Vector3(0.0, 0.0, BRIDGE_LENGTH * (k - 1) / 3.0)):
				print("FAIL _test_every_bridge_has_its_tube_lights_and_dock: bridge %d Light_%d missing or misplaced" % [slot, k])
				result = 1
		var platform := bridge.get_node_or_null("Dock/Platform") as StaticBody3D
		var undock_sign := bridge.get_node_or_null("Dock/Sign") as Label3D
		if platform == null or not platform.position.is_equal_approx(Vector3(0.0, -BRIDGE_RADIUS + 2.0, 0.0)) or bridge.get_node_or_null("Dock/Light") == null:
			print("FAIL _test_every_bridge_has_its_tube_lights_and_dock: bridge %d dock platform or light wrong" % slot)
			result = 1
		if undock_sign == null or undock_sign.text != "UNDOCK  [F]" or not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
			print("FAIL _test_every_bridge_has_its_tube_lights_and_dock: bridge %d sign missing, wrong text or not idle" % slot)
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
	var buildings := world.get_node("Chain/Section_0/Chunk_%02d_%02d/Buildings" % [key.x, key.y]) as MultiMeshInstance3D
	if buildings == null or buildings.multimesh.instance_count != groups[key].size():
		print("FAIL _test_sections_come_from_their_ring_indices: chunk %s does not hold the plan's %d buildings" % [key, groups[key].size()])
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
	for slot in world.get_bridge_slots():
		for k in range(3):
			lights.append(world.get_node("Chain/Bridge_%d/Light_%d" % [slot, k]))
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
		if node.name == "Globe" or node is Label3D:
			continue  # unshaded sun globes and the signs are not lit
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
