extends SceneTree

const TorusStationScript = preload("res://scripts/torus_station.gd")

func _init():
	var failures := 0
	failures += _test_build_station_child_count()
	failures += _test_section_and_bridge_mesh_shape()
	failures += _test_rebuild_does_not_leak()

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
