extends SceneTree

const InteriorWorldScript = preload("res://scripts/interior_world.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0
const BRIDGE_RADIUS := 600.0
const BRIDGE_LENGTH := 1834.0

func _init():
	var failures := 0
	failures += _test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape()
	failures += _test_terrain_vertices_on_the_wall_facing_the_axis()
	failures += _test_terrain_chunks_tile_the_whole_wall()
	failures += _test_near_cap_open_far_cap_closed_both_facing_in()
	failures += _test_twenty_suns_per_section_on_the_axis()
	failures += _test_bridge_tube_four_segments_facing_the_axis()
	failures += _test_dock_platform_spawn_and_sign()
	failures += _test_all_interior_lights_fit_the_renderer_budget()
	failures += _test_axis_lights_reach_the_ground_without_distance_falloff()
	failures += _test_sections_come_from_their_indices()
	failures += _test_every_lit_object_gets_at_most_eight_lights()
	failures += _test_building_both_sections_takes_under_three_seconds()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_world() -> Node3D:
	var world: Node3D = InteriorWorldScript.new()
	world.section_radius = RADIUS
	world.section_length = LENGTH
	world.bridge_radius = BRIDGE_RADIUS
	world.bridge_length = BRIDGE_LENGTH
	world.build()
	return world

func _section_start(side: float) -> float:
	var center: float = side * (BRIDGE_LENGTH + LENGTH) * 0.5
	return center - LENGTH * 0.5

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

func _test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape() -> int:
	var world := _make_world()
	var result := 0
	var first_shape: Shape3D = null
	for section_name in ["SectionAhead", "SectionBehind"]:
		var section := world.get_node_or_null(section_name)
		if section == null:
			print("FAIL _test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape: no %s" % section_name)
			result = 1
			continue
		var chunks := section.find_children("Chunk_*", "StaticBody3D", false, false)
		if chunks.size() != 320:
			print("FAIL _test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape: %s has %d chunks, expected 320" % [section_name, chunks.size()])
			result = 1
		for chunk in chunks:
			var shape: Shape3D = (chunk.get_node("Collision") as CollisionShape3D).shape
			if first_shape == null:
				first_shape = shape
			var dressed: bool = chunk.get_node_or_null("Surface") != null or chunk.get_node_or_null("Water") != null
			if shape != first_shape or not (shape is ConcavePolygonShape3D) or not dressed or chunk.get_node_or_null("Mesh") != null:
				print("FAIL _test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape: %s/%s not dressed, still has the old Mesh, or does not share the trimesh shape" % [section_name, chunk.name])
				result = 1
				break
	world.free()
	return result

func _test_terrain_vertices_on_the_wall_facing_the_axis() -> int:
	var world := _make_world()
	var chunk: Node3D = world.get_node("SectionAhead/Chunk_03_07")
	var result := 0
	for part in ["Surface", "Water"]:
		var node := chunk.get_node_or_null(part) as MeshInstance3D
		if node:
			result = maxi(result, _check_wall("_test_terrain_vertices_on_the_wall_facing_the_axis", node.mesh, chunk.transform, RADIUS))
	world.free()
	return result

func _test_terrain_chunks_tile_the_whole_wall() -> int:
	var world := _make_world()
	var result := 0
	for side in [-1.0, 1.0]:
		var section_name := "SectionAhead" if side < 0.0 else "SectionBehind"
		var first: Node3D = world.get_node("%s/Chunk_00_00" % section_name)
		var last: Node3D = world.get_node("%s/Chunk_15_19" % section_name)
		var start: float = _section_start(side)
		if not is_equal_approx(first.transform.origin.z, start) or not is_equal_approx(last.transform.origin.z + 1000.0, start + LENGTH):
			print("FAIL _test_terrain_chunks_tile_the_whole_wall: %s chunks span %f..%f expected %f..%f" % [section_name, first.transform.origin.z, last.transform.origin.z + 1000.0, start, start + LENGTH])
			result = 1
		var last_angle: float = atan2(last.transform.basis.x.y, last.transform.basis.x.x)
		if not is_equal_approx(fposmod(last_angle, TAU), 15.0 * TAU / 16.0):
			print("FAIL _test_terrain_chunks_tile_the_whole_wall: %s last chunk turned %f rad, expected %f" % [section_name, last_angle, 15.0 * TAU / 16.0])
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

func _test_near_cap_open_far_cap_closed_both_facing_in() -> int:
	var world := _make_world()
	var result := 0
	for side in [-1.0, 1.0]:
		var section_name := "SectionAhead" if side < 0.0 else "SectionBehind"
		var near_cap: Node3D = world.get_node("%s/NearCap" % section_name)
		var far_cap: Node3D = world.get_node("%s/FarCap" % section_name)
		var near: Array = _cap_min_radius_and_facing(near_cap)
		var far: Array = _cap_min_radius_and_facing(far_cap)
		# Into the section = the direction of `side` along Z for the near cap.
		if absf(near[0] - BRIDGE_RADIUS) > 0.01 or signf(near[1]) != side or not is_equal_approx(near_cap.transform.origin.z, side * BRIDGE_LENGTH * 0.5):
			print("FAIL _test_near_cap_open_far_cap_closed_both_facing_in: %s near cap hole %f facing %f at z %f" % [section_name, near[0], near[1], near_cap.transform.origin.z])
			result = 1
		if far[0] > 0.01 or signf(far[1]) != -side:
			print("FAIL _test_near_cap_open_far_cap_closed_both_facing_in: %s far cap hole %f facing %f" % [section_name, far[0], far[1]])
			result = 1
		if not (near_cap is StaticBody3D) or not ((near_cap.get_node("Collision") as CollisionShape3D).shape is ConcavePolygonShape3D):
			print("FAIL _test_near_cap_open_far_cap_closed_both_facing_in: %s near cap has no trimesh collision" % section_name)
			result = 1
	world.free()
	return result

func _test_twenty_suns_per_section_on_the_axis() -> int:
	var world := _make_world()
	var result := 0
	for side in [-1.0, 1.0]:
		var section_name := "SectionAhead" if side < 0.0 else "SectionBehind"
		var section := world.get_node(section_name)
		var suns := section.find_children("Sun_*", "Node3D", false, false)
		if suns.size() != 20:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: %s has %d suns" % [section_name, suns.size()])
			result = 1
			continue
		var first: Node3D = section.get_node("Sun_00")
		if not first.position.is_equal_approx(Vector3(0.0, 0.0, _section_start(side) + 500.0)):
			print("FAIL _test_twenty_suns_per_section_on_the_axis: %s Sun_00 at %s" % [section_name, first.position])
			result = 1
		var light := first.get_node_or_null("Light") as OmniLight3D
		if light == null or not is_equal_approx(light.omni_range, 2600.0) or light.shadow_enabled:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: %s Sun_00 light missing, wrong range, or casting shadows" % section_name)
			result = 1
		if first.get_node_or_null("Globe") == null:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: %s Sun_00 has no Globe" % section_name)
			result = 1
	world.free()
	return result

func _test_bridge_tube_four_segments_facing_the_axis() -> int:
	var world := _make_world()
	var result := 0
	for k in range(4):
		var segment := world.get_node_or_null("BridgeTube/Segment_%d" % k) as StaticBody3D
		if segment == null:
			print("FAIL _test_bridge_tube_four_segments_facing_the_axis: no Segment_%d" % k)
			result = 1
			continue
		if not is_equal_approx(segment.position.z, -BRIDGE_LENGTH * 0.5 + k * BRIDGE_LENGTH / 4.0):
			print("FAIL _test_bridge_tube_four_segments_facing_the_axis: Segment_%d at z %f" % [k, segment.position.z])
			result = 1
		var mesh: Mesh = (segment.get_node("Mesh") as MeshInstance3D).mesh
		result = maxi(result, _check_wall("_test_bridge_tube_four_segments_facing_the_axis", mesh, segment.transform, BRIDGE_RADIUS))
	for k in range(3):
		var light := world.get_node_or_null("BridgeLight_%d" % k) as OmniLight3D
		if light == null or not light.position.is_equal_approx(Vector3(0.0, 0.0, BRIDGE_LENGTH * (k - 1) / 3.0)):
			print("FAIL _test_bridge_tube_four_segments_facing_the_axis: BridgeLight_%d missing or misplaced" % k)
			result = 1
	world.free()
	return result

func _test_dock_platform_spawn_and_sign() -> int:
	var world := _make_world()
	var result := 0
	var platform := world.get_node_or_null("Dock/Platform") as StaticBody3D
	var expected_platform := Vector3(0.0, -BRIDGE_RADIUS + 2.0, 0.0)
	if platform == null or not platform.position.is_equal_approx(expected_platform):
		print("FAIL _test_dock_platform_spawn_and_sign: platform missing or not at %s" % expected_platform)
		world.free()
		return 1
	if not world.get_dock_position().is_equal_approx(expected_platform):
		print("FAIL _test_dock_platform_spawn_and_sign: get_dock_position()=%s" % world.get_dock_position())
		result = 1
	var spawn: Transform3D = world.get_spawn_transform()
	if not spawn.origin.is_equal_approx(expected_platform + Vector3(0.0, 24.0, 0.0)) or not spawn.basis.is_equal_approx(Basis()):
		print("FAIL _test_dock_platform_spawn_and_sign: spawn %s expected 24 m above the platform, facing -Z" % spawn)
		result = 1
	var undock_sign := world.get_node_or_null("Dock/Sign") as Label3D
	if undock_sign == null or undock_sign.text != "UNDOCK  [F]":
		print("FAIL _test_dock_platform_spawn_and_sign: no sign reading 'UNDOCK  [F]'")
		world.free()
		return 1
	if not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
		print("FAIL _test_dock_platform_spawn_and_sign: sign does not start idle")
		result = 1
	world.set_undock_ready(true)
	if not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_READY_COLOR):
		print("FAIL _test_dock_platform_spawn_and_sign: sign not lit when ready")
		result = 1
	world.set_undock_ready(false)
	if not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
		print("FAIL _test_dock_platform_spawn_and_sign: sign still lit when not ready")
		result = 1
	world.free()
	return result

func _test_all_interior_lights_fit_the_renderer_budget() -> int:
	# The Compatibility renderer draws at most max_renderable_lights omni lights
	# per frame and drops the rest in cull order, not by distance: past the
	# limit, whole stretches of ground go black depending on where you look.
	var world := _make_world()
	var budget: int = ProjectSettings.get_setting("rendering/limits/opengl/max_renderable_lights")
	var count := world.find_children("*", "OmniLight3D", true, false).size()
	var result := 0
	if count > budget:
		print("FAIL _test_all_interior_lights_fit_the_renderer_budget: %d omni lights, renderer draws at most %d per frame" % [count, budget])
		result = 1
	world.free()
	return result

func _test_axis_lights_reach_the_ground_without_distance_falloff() -> int:
	# With the default attenuation 1.0 a light falls off as 1/d: 2000 m from the
	# axis a sun gives ~6e-4 of its energy and the ground reads near-black.
	var world := _make_world()
	var result := 0
	var lights: Array = []
	for section_name in ["SectionAhead", "SectionBehind"]:
		for sun in world.get_node(section_name).find_children("Sun_*", "Node3D", false, false):
			lights.append(sun.get_node("Light"))
	for k in range(3):
		lights.append(world.get_node("BridgeLight_%d" % k))
	for light: OmniLight3D in lights:
		if light.omni_attenuation > 0.1:
			print("FAIL _test_axis_lights_reach_the_ground_without_distance_falloff: %s omni_attenuation=%f, expected <= 0.1" % [light.get_path() if light.is_inside_tree() else light.name, light.omni_attenuation])
			result = 1
			break
	world.free()
	return result

func _world_transform(node: Node) -> Transform3D:
	var xform := Transform3D()
	var current := node
	while current != null and current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform

func _test_sections_come_from_their_indices() -> int:
	var world: Node3D = InteriorWorldScript.new()
	world.behind_section_index = 5
	world.ahead_section_index = 6
	world.build()
	var result := 0
	var behind = world.get_section_plan(1.0)
	var ahead = world.get_section_plan(-1.0)
	if behind.section_index != 5 or ahead.section_index != 6:
		print("FAIL _test_sections_come_from_their_indices: behind %d ahead %d, expected 5 and 6" % [behind.section_index, ahead.section_index])
		result = 1
	var groups: Dictionary = ahead.group_buildings_by_chunk()
	var key: Vector2i = groups.keys()[0]
	var buildings := world.get_node("SectionAhead/Chunk_%02d_%02d/Buildings" % [key.x, key.y]) as MultiMeshInstance3D
	if buildings == null or buildings.multimesh.instance_count != groups[key].size():
		print("FAIL _test_sections_come_from_their_indices: chunk %s does not hold the plan's %d buildings" % [key, groups[key].size()])
		result = 1
	world.free()
	return result

func _test_every_lit_object_gets_at_most_eight_lights() -> int:
	# The engine pairs a light with an object when their bounding boxes meet;
	# an omni light's box is a cube of +/- its range. Past 8, lights drop.
	var world := _make_world()
	var light_boxes := []
	for light: OmniLight3D in world.find_children("*", "OmniLight3D", true, false):
		var reach := Vector3.ONE * light.omni_range
		light_boxes.append(AABB(_world_transform(light).origin - reach, reach * 2.0))
	var result := 0
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		if node.name == "Globe" or node is Label3D:
			continue  # unshaded sun globes and the sign are not lit
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

func _test_building_both_sections_takes_under_three_seconds() -> int:
	# Built on docking, behind the fade to black: target 1.5 s, fail past 3 s.
	var start := Time.get_ticks_msec()
	var world := _make_world()
	var elapsed := Time.get_ticks_msec() - start
	print("  interior build: %d ms" % elapsed)
	world.free()
	if elapsed > 3000:
		print("FAIL _test_building_both_sections_takes_under_three_seconds: %d ms" % elapsed)
		return 1
	return 0
