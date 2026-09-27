extends SceneTree

# The approach guide on the real scene (station, ports, origin shift).

const ApproachGuide = preload("res://scripts/approach_guide.gd")

var _failures := 0
var _scene: Node3D
var _cruiser: CharacterBody3D
var _station: Node3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	_cruiser = _scene.get_node("VoidCruiser")
	_station = _scene.get_node("PlanetSystem/TorusStation")
	_cruiser.set_physics_process(false)
	_station.set_process(false)

	_failures += await _test_guide_shows_near_a_dock_on_the_line_to_its_port()
	_failures += await _test_guide_hides_far_from_every_dock()
	_failures += await _test_guide_curves_around_a_section()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# Parks the ship `distance` out from port 0 along its outward axis and
# `along` metres along the bridge's axis. Being far from the origin, this
# always makes the world shift on the next tick.
func _park(distance: float, along: float = 0.0) -> void:
	var port: Node3D = _station.get_docking_port(0)
	_cruiser.global_position = port.global_position + port.global_transform.basis.x.normalized() * distance + port.global_transform.basis.y.normalized() * along
	_cruiser.velocity = Vector3.ZERO
	for i in range(3):
		await physics_frame
		await process_frame

func _test_guide_shows_near_a_dock_on_the_line_to_its_port() -> int:
	await _park(5000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	var result := 0
	if not guide.visible or not guide.global_position.is_equal_approx(_cruiser.global_position):
		print("FAIL _test_guide_shows_near_a_dock_on_the_line_to_its_port: visible %s, at %s (ship at %s)" % [guide.visible, guide.global_position, _cruiser.global_position])
		return 1
	var points: PackedVector3Array = (guide.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var port: Vector3 = _station.get_docking_port(0).global_position
	var gates := ApproachGuide.gate_distances(_cruiser.global_position.distance_to(port))
	if points.size() != gates.size() * 8 or gates.is_empty():
		print("FAIL _test_guide_shows_near_a_dock_on_the_line_to_its_port: %d points for %d gates" % [points.size(), gates.size()])
		return 1
	var centre := Vector3.ZERO
	for k in range(8):
		centre += points[k]
	centre = guide.global_position + centre / 8.0
	var expected: Vector3 = _cruiser.global_position + (port - _cruiser.global_position).normalized() * gates[0]
	if centre.distance_to(expected) > 1.0:
		print("FAIL _test_guide_shows_near_a_dock_on_the_line_to_its_port: first gate at %s, expected %s" % [centre, expected])
		result = 1
	return result

func _test_guide_hides_far_from_every_dock() -> int:
	await _park(15000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if guide.visible:
		print("FAIL _test_guide_hides_far_from_every_dock: shown 15 km from the nearest dock")
		return 1
	return 0

func _test_guide_curves_around_a_section() -> int:
	# 6 km along the ring and 2.5 km out: the straight line to the pad would
	# cut through the neighbouring section.
	await _park(2500.0, 6000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if not guide.visible:
		print("FAIL _test_guide_curves_around_a_section: guide hidden")
		return 1
	var points: PackedVector3Array = (guide.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var to_bridge: Transform3D = _station.get_node("Bridge0").global_transform.affine_inverse()
	var half_gap: float = _station.get_bridge_length() * 0.5
	for g in range(points.size() / 8):
		var centre := Vector3.ZERO
		for k in range(8):
			centre += points[g * 8 + k]
		var local: Vector3 = to_bridge * (guide.global_position + centre / 8.0)
		if absf(local.y) > half_gap and Vector2(local.x, local.z).length() < _station.section_radius:
			print("FAIL _test_guide_curves_around_a_section: gate %d inside a section (%s in the bridge's frame)" % [g, local])
			return 1
	return 0
