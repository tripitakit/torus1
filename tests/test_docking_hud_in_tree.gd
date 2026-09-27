extends SceneTree

# The approach guide on the real scene (station, ports, origin shift).

const ApproachGuide = preload("res://scripts/approach_guide.gd")
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")

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

	_failures += await _test_guide_leaves_along_the_nose()
	_failures += await _test_guide_shows_15_km_out()
	_failures += await _test_guide_hides_far_from_every_dock()
	_failures += await _test_guide_hides_on_the_last_100_m()
	_failures += await _test_guide_curves_around_a_section()
	_failures += await _test_marker_turns_cyan_inside_the_first_gate()
	_failures += await _test_marker_hides_when_still()
	_failures += await _test_guide_keeps_its_shape_near_the_switch()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# Parks the ship `distance` out from port 0 along its outward axis and
# `along` metres along the bridge's axis, nose on a point `aside` metres
# across the bridge from the port, at rest with the port. Being far from
# the origin, this always makes the world shift on the next tick.
func _park(distance: float, along: float = 0.0, aside: float = 0.0) -> void:
	var port: Node3D = _station.get_docking_port(0)
	var at: Vector3 = port.global_position + port.global_transform.basis.x.normalized() * distance + port.global_transform.basis.y.normalized() * along
	var aim: Vector3 = port.global_position + port.global_transform.basis.z.normalized() * aside
	_cruiser.global_transform = Transform3D(Basis.looking_at(aim - at, port.global_transform.basis.y), at)
	_cruiser.velocity = _station.get_docking_port_velocity(0)
	for i in range(3):
		await physics_frame
		await process_frame

func _points(node_name: String) -> PackedVector3Array:
	var lines: MeshInstance3D = _cruiser.get_node(node_name)
	return (lines.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _centre(points: PackedVector3Array, square: int) -> Vector3:
	var centre := Vector3.ZERO
	for k in range(8):
		centre += points[square * 8 + k]
	return centre / 8.0

func _test_guide_leaves_along_the_nose() -> int:
	# Nose 2 km to the side of the dock: the gates still start dead ahead.
	await _park(5000.0, 0.0, 2000.0)
	var guide: MeshInstance3D = _cruiser.get_node("ApproachGuide")
	if not guide.visible or not guide.global_position.is_equal_approx(_cruiser.global_position):
		print("FAIL _test_guide_leaves_along_the_nose: visible %s, at %s (ship at %s)" % [guide.visible, guide.global_position, _cruiser.global_position])
		return 1
	# The path bends toward the dock from the start, so the first gate sits
	# a little off the nose line: within 2 degrees is the middle of the view.
	var nose: Vector3 = -_cruiser.global_transform.basis.z.normalized()
	var first := _centre(_points("ApproachGuide"), 0)
	if rad_to_deg(first.angle_to(nose)) > 2.0:
		print("FAIL _test_guide_leaves_along_the_nose: first gate at %s, %.1f degrees off the nose %s" % [first, rad_to_deg(first.angle_to(nose)), nose])
		return 1
	return 0

func _test_guide_shows_15_km_out() -> int:
	await _park(15000.0)
	if not (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible:
		print("FAIL _test_guide_shows_15_km_out: hidden 15 km from a dock")
		return 1
	return 0

func _test_guide_hides_far_from_every_dock() -> int:
	await _park(25000.0)
	if (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible or (_cruiser.get_node("HeadingMarker") as MeshInstance3D).visible:
		print("FAIL _test_guide_hides_far_from_every_dock: shown 25 km from the nearest dock")
		return 1
	return 0

func _test_guide_hides_on_the_last_100_m() -> int:
	# 95 m out with the nose turned away: the path out and back is over
	# 100 m long, enough for a gate, but the dock itself is too close.
	await _park(95.0)
	var port: Node3D = _station.get_docking_port(0)
	_cruiser.global_transform = Transform3D(Basis.looking_at(port.global_transform.basis.x, port.global_transform.basis.y), _cruiser.global_position)
	_cruiser.velocity = _station.get_docking_port_velocity(0) - _cruiser.global_transform.basis.z * 5.0
	await process_frame
	if (_cruiser.get_node("ApproachGuide") as MeshInstance3D).visible or (_cruiser.get_node("HeadingMarker") as MeshInstance3D).visible:
		print("FAIL _test_guide_hides_on_the_last_100_m: shown 95 m from the dock")
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
	var points := _points("ApproachGuide")
	var to_bridge: Transform3D = _station.get_node("Bridge0").global_transform.affine_inverse()
	var half_gap: float = _station.get_bridge_length() * 0.5
	for g in range(points.size() / 8):
		var local: Vector3 = to_bridge * (guide.global_position + _centre(points, g))
		if absf(local.y) > half_gap and Vector2(local.x, local.z).length() < _station.section_radius:
			print("FAIL _test_guide_curves_around_a_section: gate %d inside a section (%s in the bridge's frame)" % [g, local])
			return 1
	return 0

func _test_marker_turns_cyan_inside_the_first_gate() -> int:
	var result := 0
	await _park(5000.0)
	var marker: MeshInstance3D = _cruiser.get_node("HeadingMarker")
	var nose: Vector3 = -_cruiser.global_transform.basis.z.normalized()
	var side: Vector3 = _cruiser.global_transform.basis.x.normalized()
	# [velocity relative to the dock, expected colour]: 2 m/s sideways in 50
	# puts the marker 4 m off the first gate's centre, 10 m/s puts it 20 m.
	for c in [[nose * 50.0, VoidCruiserScript.MARKER_ON_PATH_COLOR], [nose * 50.0 + side * 2.0, VoidCruiserScript.MARKER_ON_PATH_COLOR], [nose * 50.0 + side * 10.0, VoidCruiserScript.MARKER_OFF_PATH_COLOR]]:
		_cruiser.velocity = _station.get_docking_port_velocity(0) + c[0]
		await process_frame
		var colour: Color = (marker.material_override as StandardMaterial3D).albedo_color
		if not marker.visible or not colour.is_equal_approx(c[1]):
			print("FAIL _test_marker_turns_cyan_inside_the_first_gate: moving %s, visible %s, colour %s" % [c[0], marker.visible, colour])
			result = 1
			continue
		var centre := _centre(_points("HeadingMarker"), 0)
		var expected: Vector3 = c[0].normalized() * ApproachGuide.FIRST_GATE
		if centre.distance_to(expected) > 1.0:
			print("FAIL _test_marker_turns_cyan_inside_the_first_gate: marker at %s, expected %s" % [centre, expected])
			result = 1
	return result

func _test_marker_hides_when_still() -> int:
	await _park(5000.0)
	if (_cruiser.get_node("HeadingMarker") as MeshInstance3D).visible:
		print("FAIL _test_marker_hides_when_still: shown at rest with the dock")
		return 1
	return 0

func _test_guide_keeps_its_shape_near_the_switch() -> int:
	# Where the single curve only just clears the rim, the guide keeps the
	# shape it had last frame: the ship carries the choice.
	var result := 0
	var bridge: Node3D = _station.get_node("Bridge0")
	var port: Node3D = _station.get_docking_port(0)
	var pad: Vector3 = port.transform.origin
	var pad_angle := atan2(pad.x, pad.z) + 1.5
	var ship := Vector3.ZERO
	var nose := Vector3.ZERO
	for step in range(4001):
		var candidate := Vector3(sin(pad_angle) * 4000.0, 4000.0 - step, cos(pad_angle) * 4000.0)
		var toward: Vector3 = (pad - candidate).normalized()
		if not ApproachGuide.over_rim(candidate, toward, pad, _station.section_radius, _station.get_bridge_length() * 0.5, false) and ApproachGuide.over_rim(candidate, toward, pad, _station.section_radius, _station.get_bridge_length() * 0.5, true):
			ship = candidate
			nose = toward
			break
	for held in [true, false]:
		_cruiser.global_transform = bridge.global_transform * Transform3D(Basis.looking_at(nose, Vector3.UP), ship)
		_cruiser.velocity = Vector3.ZERO
		_cruiser._guide_over_rim = held
		await physics_frame
		await process_frame
		var expected := PackedVector3Array()
		for point in ApproachGuide.approach_path(ship, nose, pad, _station.section_radius, _station.get_bridge_length() * 0.5, _station.get_bridge_radius(), held):
			expected.append(bridge.global_transform * point - _cruiser.global_position)
		var gates := ApproachGuide.gate_centres(expected)
		var points := _points("ApproachGuide")
		if _cruiser._guide_over_rim != held or points.size() != gates.size() * 8 or _centre(points, gates.size() - 1).distance_to(gates[gates.size() - 1][0]) > 1.0:
			print("FAIL _test_guide_keeps_its_shape_near_the_switch: held %s, now %s, %d points for %d gates" % [held, _cruiser._guide_over_rim, points.size(), gates.size()])
			result = 1
	return result
