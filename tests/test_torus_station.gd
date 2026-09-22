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
	failures += _test_sections_have_stripe_marker()
	failures += _test_rotate_sections_applies_correct_local_y_angle()
	failures += _test_rotate_sections_does_not_rotate_bridges()

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
	return station

func _test_build_station_child_count() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if station.get_child_count() != 8:
		print("FAIL _test_build_station_child_count: expected 8 children, got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_section_and_bridge_mesh_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var section: MeshInstance3D = station.get_node("Section0")
	var bridge: MeshInstance3D = station.get_node("Bridge0")
	var failed := false
	if not (section.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Section0.mesh is not CylinderMesh")
		failed = true
	else:
		var cyl: CylinderMesh = section.mesh
		if not is_equal_approx(cyl.top_radius, 30.0) or not is_equal_approx(cyl.height, 80.0):
			print("FAIL _test_section_and_bridge_mesh_shape: Section0 top_radius=%f height=%f" % [cyl.top_radius, cyl.height])
			failed = true
	if not (bridge.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Bridge0.mesh is not CylinderMesh")
		failed = true
	station.free()
	return 1 if failed else 0

func _test_rebuild_does_not_leak() -> int:
	var station := _make_station(4)
	station.build_station()
	station.build_station()
	var result := 0
	if station.get_child_count() != 8:
		print("FAIL _test_rebuild_does_not_leak: expected 8 children after rebuild, got %d" % station.get_child_count())
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
	if station.get_child_count() != 9:
		print("FAIL _test_build_station_preserves_unrelated_children: expected 9 children (8 generated + Marker), got %d" % station.get_child_count())
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
		var bridge: MeshInstance3D = station.get_node("Bridge%d" % i)
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
	var section0: MeshInstance3D = station.get_node("Section0")
	var expected_torus_radius := 900.0 + 1500.0
	if not is_equal_approx(section0.transform.origin.length(), expected_torus_radius):
		print("FAIL _test_uses_planet_node_radius_when_set: Section0 distance=%f expected=%f" % [section0.transform.origin.length(), expected_torus_radius])
		result = 1
	station.free()
	return result

func _test_sections_have_stripe_marker() -> int:
	var station := _make_station(4)
	station.build_station()
	var section: MeshInstance3D = station.get_node("Section0")
	var result := 0
	var stripe := section.get_node_or_null("Stripe")
	if stripe == null or not (stripe is MeshInstance3D) or not ((stripe as MeshInstance3D).mesh is BoxMesh):
		print("FAIL _test_sections_have_stripe_marker: Section0 has no Stripe MeshInstance3D with a BoxMesh")
		result = 1
	else:
		# Offset must be along local Z (radially outward in the ring's horizontal
		# plane, visible from the top-down verification camera), not local X
		# (which maps to world UP for every section and is invisible from above).
		var expected_offset := Vector3(0.0, 0.0, 30.0)
		if not (stripe as MeshInstance3D).transform.origin.is_equal_approx(expected_offset):
			print("FAIL _test_sections_have_stripe_marker: Stripe offset=%s expected=%s" % [(stripe as MeshInstance3D).transform.origin, expected_offset])
			result = 1
	station.free()
	return result

func _test_rotate_sections_applies_correct_local_y_angle() -> int:
	var station := _make_station(4)
	station.build_station()
	var section: MeshInstance3D = station.get_node("Section0")
	var original_basis: Basis = section.transform.basis
	var delta := 0.1
	station._rotate_sections(delta)
	var new_basis: Basis = section.transform.basis
	var delta_basis: Basis = original_basis.inverse() * new_basis
	var expected_omega: float = TorusGeometry.compute_section_angular_velocity(30.0)
	var expected_delta_basis := Basis(Vector3.UP, expected_omega * delta)
	var result := 0
	if not delta_basis.x.is_equal_approx(expected_delta_basis.x) \
			or not delta_basis.y.is_equal_approx(expected_delta_basis.y) \
			or not delta_basis.z.is_equal_approx(expected_delta_basis.z):
		print("FAIL _test_rotate_sections_applies_correct_local_y_angle: delta_basis=%s expected=%s" % [delta_basis, expected_delta_basis])
		result = 1
	station.free()
	return result

func _test_rotate_sections_does_not_rotate_bridges() -> int:
	var station := _make_station(4)
	station.build_station()
	var bridge: MeshInstance3D = station.get_node("Bridge0")
	var original_basis: Basis = bridge.transform.basis
	station._rotate_sections(0.1)
	var result := 0
	if not bridge.transform.basis.is_equal_approx(original_basis):
		print("FAIL _test_rotate_sections_does_not_rotate_bridges: bridge basis changed")
		result = 1
	station.free()
	return result
