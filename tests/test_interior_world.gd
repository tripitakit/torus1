extends SceneTree

const InteriorWorldScript = preload("res://scripts/interior_world.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0
const BRIDGE_RADIUS := 600.0
const BRIDGE_LENGTH := 1834.0

func _init():
	var failures := 0
	failures += _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape()
	failures += _test_terrain_vertices_on_the_wall_facing_the_axis()
	failures += _test_terrain_chunks_tile_the_whole_wall()
	failures += _test_near_cap_open_far_cap_closed_both_facing_in()
	failures += _test_twenty_suns_per_section_on_the_axis()
	failures += _test_bridge_tube_four_segments_facing_the_axis()
	failures += _test_dock_platform_spawn_and_sign()

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
	var arrays: Array = mesh.surface_get_arrays(0)
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

func _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape() -> int:
	var world := _make_world()
	var result := 0
	var first_mesh: Mesh = null
	var first_shape: Shape3D = null
	for section_name in ["SectionAhead", "SectionBehind"]:
		var section := world.get_node_or_null(section_name)
		if section == null:
			print("FAIL _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape: no %s" % section_name)
			result = 1
			continue
		var chunks := section.find_children("Chunk_*", "StaticBody3D", false, false)
		if chunks.size() != 320:
			print("FAIL _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape: %s has %d chunks, expected 320" % [section_name, chunks.size()])
			result = 1
		for chunk in chunks:
			var mesh: Mesh = (chunk.get_node("Mesh") as MeshInstance3D).mesh
			var shape: Shape3D = (chunk.get_node("Collision") as CollisionShape3D).shape
			if first_mesh == null:
				first_mesh = mesh
				first_shape = shape
			if mesh != first_mesh or shape != first_shape or not (shape is ConcavePolygonShape3D):
				print("FAIL _test_two_sections_of_320_chunks_sharing_one_mesh_and_shape: %s/%s does not share the chunk mesh and trimesh shape" % [section_name, chunk.name])
				result = 1
				break
	world.free()
	return result

func _test_terrain_vertices_on_the_wall_facing_the_axis() -> int:
	var world := _make_world()
	var chunk: Node3D = world.get_node("SectionAhead/Chunk_03_07")
	var mesh: Mesh = (chunk.get_node("Mesh") as MeshInstance3D).mesh
	var result := _check_wall("_test_terrain_vertices_on_the_wall_facing_the_axis", mesh, chunk.transform, RADIUS)
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
