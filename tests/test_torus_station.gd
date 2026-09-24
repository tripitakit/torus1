extends SceneTree

const TorusStationScript = preload("res://scripts/torus_station.gd")
const PlanetScript = preload("res://scripts/planet.gd")
const TorusGeometry = preload("res://scripts/torus_geometry.gd")

func _init():
	var failures := 0
	failures += _test_build_station_child_count()
	failures += _test_section_and_bridge_mesh_shape()
	failures += _test_rebuild_does_not_leak()
	failures += _test_build_station_preserves_unrelated_children()
	failures += _test_bridge_positions_are_distinct_and_close_the_ring()
	failures += _test_uses_planet_node_radius_when_set()
	failures += _test_sections_have_no_stripe_marker()
	failures += _test_rotate_sections_applies_correct_local_y_angle()
	failures += _test_rotate_sections_also_rotates_bridges()
	failures += _test_sections_and_bridges_share_one_hull_material()
	failures += _test_sections_share_one_mesh_resource()
	failures += _test_bridges_share_one_mesh_resource()
	failures += _test_hull_material_has_emission_and_ao()
	failures += _test_sections_are_animatable_bodies()
	failures += _test_bridges_are_animatable_bodies()
	failures += _test_sections_have_matching_collision_shape()
	failures += _test_bridges_have_matching_collision_shape()
	failures += _test_section_collision_shapes_are_shared()
	failures += _test_bridge_collision_shapes_are_shared()
	failures += _test_each_bridge_has_a_docking_collar()
	failures += _test_docking_collars_share_mesh_and_shape()
	failures += _test_rotate_sections_does_not_rotate_docking_collars()
	failures += _test_bridge_radius_and_length_helpers()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_station(num_sections: int) -> Node3D:
	var station: Node3D = TorusStationScript.new()
	station.planet_radius = 500.0
	station.orbit_altitude = 1500.0
	station.num_sections = num_sections
	station.section_radius = 30.0
	station.section_length = 80.0
	station.target_gravity_g = 1.0
	return station

func _test_build_station_child_count() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if station.get_child_count() != 12:
		print("FAIL _test_build_station_child_count: expected 12 children, got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_section_and_bridge_mesh_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var section_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var bridge_mesh: MeshInstance3D = station.get_node("Bridge0").get_node("Mesh")
	var failed := false
	if not (section_mesh.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Section0/Mesh.mesh is not CylinderMesh")
		failed = true
	else:
		var cyl: CylinderMesh = section_mesh.mesh
		if not is_equal_approx(cyl.top_radius, 30.0) or not is_equal_approx(cyl.height, 80.0):
			print("FAIL _test_section_and_bridge_mesh_shape: Section0/Mesh top_radius=%f height=%f" % [cyl.top_radius, cyl.height])
			failed = true
	if not (bridge_mesh.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Bridge0/Mesh.mesh is not CylinderMesh")
		failed = true
	station.free()
	return 1 if failed else 0

func _test_rebuild_does_not_leak() -> int:
	var station := _make_station(4)
	station.build_station()
	station.build_station()
	var result := 0
	if station.get_child_count() != 12:
		print("FAIL _test_rebuild_does_not_leak: expected 12 children after rebuild, got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_build_station_preserves_unrelated_children() -> int:
	var station := _make_station(4)
	var marker := Node3D.new()
	marker.name = "Marker"
	station.add_child(marker)
	station.build_station()
	var result := 0
	if station.get_node_or_null("Marker") == null:
		print("FAIL _test_build_station_preserves_unrelated_children: Marker was removed by build_station()")
		result = 1
	if station.get_child_count() != 13:
		print("FAIL _test_build_station_preserves_unrelated_children: expected 13 children (12 generated + Marker), got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_bridge_positions_are_distinct_and_close_the_ring() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var torus_radius := 500.0 + 1500.0
	var step := TAU / 4.0
	for i in range(4):
		var bridge: AnimatableBody3D = station.get_node("Bridge%d" % i)
		var expected_theta := i * step + step * 0.5
		var expected_pos := Vector3(cos(expected_theta), 0.0, sin(expected_theta)) * torus_radius
		if not bridge.transform.origin.is_equal_approx(expected_pos):
			print("FAIL _test_bridge_positions_are_distinct_and_close_the_ring: Bridge%d origin=%s expected=%s" % [i, bridge.transform.origin, expected_pos])
			result = 1
	station.free()
	return result

func _test_uses_planet_node_radius_when_set() -> int:
	var station := _make_station(4)
	station.planet_radius = 500.0
	var planet: MeshInstance3D = PlanetScript.new()
	planet.name = "Planet"
	planet.planet_radius = 900.0
	station.add_child(planet)
	station.planet_node = NodePath("Planet")
	station.build_station()
	var result := 0
	var section0: AnimatableBody3D = station.get_node("Section0")
	var expected_torus_radius := 900.0 + 1500.0
	if not is_equal_approx(section0.transform.origin.length(), expected_torus_radius):
		print("FAIL _test_uses_planet_node_radius_when_set: Section0 distance=%f expected=%f" % [section0.transform.origin.length(), expected_torus_radius])
		result = 1
	station.free()
	return result

func _test_sections_have_no_stripe_marker() -> int:
	# The orange rotation-marker stripe was removed at the user's request:
	# a section is only its hull mesh and collision shape.
	var station := _make_station(4)
	station.build_station()
	var section: AnimatableBody3D = station.get_node("Section0")
	var result := 0
	if section.get_node_or_null("Stripe") != null:
		print("FAIL _test_sections_have_no_stripe_marker: Section0 still has a Stripe child")
		result = 1
	var mesh_count := section.find_children("*", "MeshInstance3D", true, false).size()
	if mesh_count != 1:
		print("FAIL _test_sections_have_no_stripe_marker: Section0 has %d meshes, expected 1 (hull only)" % mesh_count)
		result = 1
	station.free()
	return result

func _test_rotate_sections_applies_correct_local_y_angle() -> int:
	var station := _make_station(4)
	station.build_station()
	var section: AnimatableBody3D = station.get_node("Section0")
	var original_basis: Basis = section.transform.basis
	var delta := 0.1
	station._rotate_sections(delta)
	var new_basis: Basis = section.transform.basis
	var delta_basis: Basis = original_basis.inverse() * new_basis
	var expected_omega: float = TorusGeometry.compute_section_angular_velocity(30.0, TorusGeometry.GRAVITY_1G)
	var expected_delta_basis := Basis(Vector3.UP, expected_omega * delta)
	var result := 0
	if not delta_basis.x.is_equal_approx(expected_delta_basis.x) \
			or not delta_basis.y.is_equal_approx(expected_delta_basis.y) \
			or not delta_basis.z.is_equal_approx(expected_delta_basis.z):
		print("FAIL _test_rotate_sections_applies_correct_local_y_angle: delta_basis=%s expected=%s" % [delta_basis, expected_delta_basis])
		result = 1
	station.free()
	return result

func _test_rotate_sections_also_rotates_bridges() -> int:
	# Bridges rotate rigidly together with the sections they connect — the
	# whole ring spins as one piece, not sections-spin/bridges-fixed.
	var station := _make_station(4)
	station.build_station()
	var bridge: AnimatableBody3D = station.get_node("Bridge0")
	var original_basis: Basis = bridge.transform.basis
	var delta := 0.1
	station._rotate_sections(delta)
	var new_basis: Basis = bridge.transform.basis
	var delta_basis: Basis = original_basis.inverse() * new_basis
	var expected_omega: float = TorusGeometry.compute_section_angular_velocity(30.0, TorusGeometry.GRAVITY_1G)
	var expected_delta_basis := Basis(Vector3.UP, expected_omega * delta)
	var result := 0
	if not delta_basis.x.is_equal_approx(expected_delta_basis.x) \
			or not delta_basis.y.is_equal_approx(expected_delta_basis.y) \
			or not delta_basis.z.is_equal_approx(expected_delta_basis.z):
		print("FAIL _test_rotate_sections_also_rotates_bridges: delta_basis=%s expected=%s" % [delta_basis, expected_delta_basis])
		result = 1
	station.free()
	return result

func _test_sections_and_bridges_share_one_hull_material() -> int:
	# Sections+bridges must all reference the SAME material resource, not a
	# fresh StandardMaterial3D per mesh — with num_sections in the thousands,
	# per-object materials would duplicate a GPU resource needlessly.
	var station := _make_station(4)
	station.build_station()
	var section0_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var section1_mesh: MeshInstance3D = station.get_node("Section1").get_node("Mesh")
	var bridge0_mesh: MeshInstance3D = station.get_node("Bridge0").get_node("Mesh")
	var result := 0
	if section0_mesh.material_override == null:
		print("FAIL _test_sections_and_bridges_share_one_hull_material: Section0/Mesh has no material_override")
		result = 1
	elif section0_mesh.material_override != section1_mesh.material_override:
		print("FAIL _test_sections_and_bridges_share_one_hull_material: Section0 and Section1 use different material resources")
		result = 1
	elif section0_mesh.material_override != bridge0_mesh.material_override:
		print("FAIL _test_sections_and_bridges_share_one_hull_material: Section0 and Bridge0 use different material resources")
		result = 1
	station.free()
	return result

func _test_sections_share_one_mesh_resource() -> int:
	# With num_sections in the thousands, a fresh CylinderMesh per section
	# would duplicate identical geometry in GPU memory thousands of times.
	var station := _make_station(4)
	station.build_station()
	var section0_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var section1_mesh: MeshInstance3D = station.get_node("Section1").get_node("Mesh")
	var result := 0
	if section0_mesh.mesh == null or section0_mesh.mesh != section1_mesh.mesh:
		print("FAIL _test_sections_share_one_mesh_resource: Section0 and Section1 use different mesh resources")
		result = 1
	station.free()
	return result

func _test_bridges_share_one_mesh_resource() -> int:
	var station := _make_station(4)
	station.build_station()
	var bridge0_mesh: MeshInstance3D = station.get_node("Bridge0").get_node("Mesh")
	var bridge1_mesh: MeshInstance3D = station.get_node("Bridge1").get_node("Mesh")
	var result := 0
	if bridge0_mesh.mesh == null or bridge0_mesh.mesh != bridge1_mesh.mesh:
		print("FAIL _test_bridges_share_one_mesh_resource: Bridge meshes differ between instances")
		result = 1
	station.free()
	return result

func _test_hull_material_has_emission_and_ao() -> int:
	var station := _make_station(4)
	station.build_station()
	var section_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var mat: StandardMaterial3D = section_mesh.material_override
	var result := 0
	if not mat.emission_enabled or mat.emission_texture == null:
		print("FAIL _test_hull_material_has_emission_and_ao: emission not enabled or no emission_texture")
		result = 1
	# Emission operator is additive (color + texture): a non-black base color
	# would make the whole hull glow, not just the lights painted in the texture.
	if not mat.emission.is_equal_approx(Color(0, 0, 0)):
		print("FAIL _test_hull_material_has_emission_and_ao: base emission color=%s expected black" % mat.emission)
		result = 1
	if not mat.ao_enabled or mat.ao_texture == null:
		print("FAIL _test_hull_material_has_emission_and_ao: ao not enabled or no ao_texture")
		result = 1
	station.free()
	return result

func _test_sections_are_animatable_bodies() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if not (station.get_node("Section0") is AnimatableBody3D):
		print("FAIL _test_sections_are_animatable_bodies: Section0 is not an AnimatableBody3D")
		result = 1
	station.free()
	return result

func _test_bridges_are_animatable_bodies() -> int:
	# Bridges now rotate every frame together with sections — same reasoning
	# as sections: Godot recommends against moving a StaticBody3D every
	# frame, and a body under continuous external transform control should
	# be an AnimatableBody3D instead.
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if not (station.get_node("Bridge0") is AnimatableBody3D):
		print("FAIL _test_bridges_are_animatable_bodies: Bridge0 is not an AnimatableBody3D")
		result = 1
	station.free()
	return result

# The collision shape must be a convex prism whose corners are exactly the
# side-wall corners of the visible CylinderMesh (not a CylinderShape3D: see
# test_torus_station_physics.gd). Returns an error message, or "" if it matches.
func _prism_mismatch(body: Node, expected_radius: float) -> String:
	var collision := body.get_node_or_null("Collision")
	if collision == null or not (collision is CollisionShape3D) or not ((collision as CollisionShape3D).shape is ConvexPolygonShape3D):
		return "%s has no CollisionShape3D with a ConvexPolygonShape3D" % body.name
	var points: PackedVector3Array = ((collision as CollisionShape3D).shape as ConvexPolygonShape3D).points
	var mesh: CylinderMesh = (body.get_node("Mesh") as MeshInstance3D).mesh
	if not is_equal_approx(mesh.top_radius, expected_radius):
		return "%s mesh radius=%f expected %f" % [body.name, mesh.top_radius, expected_radius]
	if points.size() != mesh.radial_segments * 2:
		return "%s prism has %d points, expected %d (2 per radial segment)" % [body.name, points.size(), mesh.radial_segments * 2]
	var mesh_vertices: PackedVector3Array = mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
	for point in points:
		var found := false
		for vertex in mesh_vertices:
			if point.is_equal_approx(vertex):
				found = true
				break
		if not found:
			return "%s prism point %s is not a vertex of the visible mesh" % [body.name, point]
		if not is_equal_approx(absf(point.y), mesh.height * 0.5) or not is_equal_approx(Vector2(point.x, point.z).length(), expected_radius):
			return "%s prism point %s is not on the side wall rim" % [body.name, point]
	return ""

func _test_sections_have_matching_collision_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var mismatch := _prism_mismatch(station.get_node("Section0"), 30.0)
	if mismatch != "":
		print("FAIL _test_sections_have_matching_collision_shape: " + mismatch)
		result = 1
	station.free()
	return result

func _test_bridges_have_matching_collision_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var mismatch := _prism_mismatch(station.get_node("Bridge0"), 9.0)
	if mismatch != "":
		print("FAIL _test_bridges_have_matching_collision_shape: " + mismatch)
		result = 1
	station.free()
	return result

func _test_section_collision_shapes_are_shared() -> int:
	var station := _make_station(4)
	station.build_station()
	var shape0: Shape3D = (station.get_node("Section0").get_node("Collision") as CollisionShape3D).shape
	var shape1: Shape3D = (station.get_node("Section1").get_node("Collision") as CollisionShape3D).shape
	var result := 0
	if shape0 == null or shape0 != shape1:
		print("FAIL _test_section_collision_shapes_are_shared: Section0 and Section1 use different collision shape resources")
		result = 1
	station.free()
	return result

func _test_bridge_collision_shapes_are_shared() -> int:
	var station := _make_station(4)
	station.build_station()
	var shape0: Shape3D = (station.get_node("Bridge0").get_node("Collision") as CollisionShape3D).shape
	var shape1: Shape3D = (station.get_node("Bridge1").get_node("Collision") as CollisionShape3D).shape
	var result := 0
	if shape0 == null or shape0 != shape1:
		print("FAIL _test_bridge_collision_shapes_are_shared: Bridge0 and Bridge1 use different collision shape resources")
		result = 1
	station.free()
	return result

func _test_each_bridge_has_a_docking_collar() -> int:
	# Small station: bridge radius 9 -> collar radii 9.45 / 11.25, port at 11.34.
	var station := _make_station(4)
	station.build_station()
	var result := 0
	for i in range(4):
		var collar := station.get_node_or_null("DockingCollar%d" % i)
		if collar == null or not (collar is StaticBody3D):
			print("FAIL _test_each_bridge_has_a_docking_collar: no DockingCollar%d StaticBody3D" % i)
			result = 1
			continue
		var bridge: Node3D = station.get_node("Bridge%d" % i)
		if not (collar as Node3D).transform.is_equal_approx(bridge.transform):
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d transform differs from Bridge%d" % [i, i])
			result = 1
		var mesh_node := collar.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_node == null or not (mesh_node.mesh is TorusMesh):
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d has no TorusMesh" % i)
			result = 1
		else:
			var torus: TorusMesh = mesh_node.mesh
			if not is_equal_approx(torus.inner_radius, 9.45) or not is_equal_approx(torus.outer_radius, 11.25):
				print("FAIL _test_each_bridge_has_a_docking_collar: radii %f / %f expected 9.45 / 11.25" % [torus.inner_radius, torus.outer_radius])
				result = 1
		var collision := collar.get_node_or_null("Collision") as CollisionShape3D
		if collision == null or not (collision.shape is ConcavePolygonShape3D):
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d has no ConcavePolygonShape3D" % i)
			result = 1
		var port := collar.get_node_or_null("Port") as Node3D
		if port == null or not port.position.is_equal_approx(Vector3(11.34, 0.0, 0.0)):
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d Port missing or at %s, expected (11.34, 0, 0)" % [i, str(port.position) if port else "none"])
			result = 1
		elif port.get_node_or_null("Platform") == null:
			print("FAIL _test_each_bridge_has_a_docking_collar: DockingCollar%d/Port has no Platform" % i)
			result = 1
	station.free()
	return result

func _test_docking_collars_share_mesh_and_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var mesh0: Mesh = (station.get_node("DockingCollar0/Mesh") as MeshInstance3D).mesh
	var mesh1: Mesh = (station.get_node("DockingCollar1/Mesh") as MeshInstance3D).mesh
	var shape0: Shape3D = (station.get_node("DockingCollar0/Collision") as CollisionShape3D).shape
	var shape1: Shape3D = (station.get_node("DockingCollar1/Collision") as CollisionShape3D).shape
	if mesh0 == null or mesh0 != mesh1 or shape0 == null or shape0 != shape1:
		print("FAIL _test_docking_collars_share_mesh_and_shape: collars do not share one mesh and one shape")
		result = 1
	station.free()
	return result

func _test_rotate_sections_does_not_rotate_docking_collars() -> int:
	# The collar must stay still so its port can be docked at.
	var station := _make_station(4)
	station.build_station()
	var collar: Node3D = station.get_node("DockingCollar0")
	var bridge: Node3D = station.get_node("Bridge0")
	var collar_before: Transform3D = collar.transform
	var bridge_before: Transform3D = bridge.transform
	station._rotate_sections(1.0)
	var result := 0
	if not collar.transform.is_equal_approx(collar_before):
		print("FAIL _test_rotate_sections_does_not_rotate_docking_collars: the collar rotated")
		result = 1
	if bridge.transform.is_equal_approx(bridge_before):
		print("FAIL _test_rotate_sections_does_not_rotate_docking_collars: the bridge did not rotate (test setup broken)")
		result = 1
	station.free()
	return result

func _test_bridge_radius_and_length_helpers() -> int:
	var station := _make_station(4)
	var result := 0
	if not is_equal_approx(station.get_bridge_radius(), 9.0):
		print("FAIL _test_bridge_radius_and_length_helpers: bridge radius %f expected 9.0" % station.get_bridge_radius())
		result = 1
	var expected_length: float = TorusGeometry.compute_bridge_length(500.0, 1500.0, 4, 80.0)
	if not is_equal_approx(station.get_bridge_length(), expected_length):
		print("FAIL _test_bridge_radius_and_length_helpers: bridge length %f expected %f" % [station.get_bridge_length(), expected_length])
		result = 1
	station.free()
	return result
