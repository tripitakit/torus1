extends SceneTree

# Real in-tree physics tests, separate from test_torus_station.gd's off-tree
# unit tests. Nodes here are genuinely added to a processed SceneTree frame
# (via `_initialize()` + `await physics_frame`, not the synchronous `_init()`
# every other test in this project uses), so AnimatableBody3D's
# sync_to_physics behavior actually engages. Verified empirically during the
# code review for docs/superpowers/plans/2026-09-23-station-collisions.md:
# off-tree tests cannot exercise this at all (see that plan's Global
# Constraints), but in-tree tests like these can and must, since this is
# exactly the class of bug (AnimatableBody3D default sync_to_physics=true
# silently drops transform changes made outside _physics_process, and
# ignores a parent's transform changes) that off-tree tests structurally
# cannot catch.

const TorusStationScript = preload("res://scripts/torus_station.gd")
const TorusGeometry = preload("res://scripts/torus_geometry.gd")

var _failures := 0

func _initialize():
	await process_frame
	await physics_frame
	await physics_frame

	_failures += await _test_section_rotation_accumulates_across_physics_ticks()
	_failures += await _test_bridge_rotation_accumulates_across_physics_ticks()
	_failures += await _test_section_stays_aligned_with_parent_after_shift()
	_failures += await _test_rotating_hull_resting_on_section_does_not_jump()
	_failures += await _test_rotating_hull_resting_on_bridge_does_not_jump()
	_failures += await _test_nearest_bridge_index_finds_each_port()
	_failures += await _test_rotating_hull_resting_on_docking_collar_does_not_jump()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _make_station() -> Node3D:
	var station: Node3D = TorusStationScript.new()
	station.planet_radius = 500.0
	station.orbit_altitude = 1500.0
	station.num_sections = 4
	station.section_radius = 30.0
	station.section_length = 80.0
	station.target_gravity_g = 1.0
	return station

func _test_section_rotation_accumulates_across_physics_ticks() -> int:
	# _rotate_sections is called from _process(), which can fire several
	# times between two physics ticks (e.g. a display refresh rate above the
	# physics tick rate). Each call must still contribute its rotation —
	# AnimatableBody3D's default sync_to_physics=true drops all but a
	# fraction of the intermediate changes (see the Critical finding in the
	# code review that led to this test).
	var station := _make_station()
	root.add_child(station)
	# The station's own _process() would also call _rotate_sections() every
	# real frame while this test awaits physics_frame, on top of (and
	# double-counting alongside) the explicit calls below. Disable it so
	# only this test's own calls drive the rotation.
	station.set_process(false)
	station.build_station()
	var section: Node3D = station.get_node("Section0")
	# Section0 sits at a non-identity orientation (it's placed around the
	# ring, not at the origin facing +Z) — measure the rotation actually
	# applied as a basis delta, same technique
	# test_torus_station.gd's _test_rotate_sections_applies_correct_local_y_angle
	# uses, not a raw Euler angle read (which is ambiguous for a compound,
	# already-rotated starting orientation).
	var original_basis: Basis = section.transform.basis

	var sub_delta := 0.02
	var calls_per_tick := 3
	var num_ticks := 3
	for tick in range(num_ticks):
		for sub in range(calls_per_tick):
			station._rotate_sections(sub_delta)
		await physics_frame

	var new_basis: Basis = section.transform.basis
	var delta_basis: Basis = original_basis.inverse() * new_basis

	# Expected angle from the same formula _rotate_sections uses internally,
	# recomputed independently here (not just restating the implementation).
	var target_gravity: float = TorusGeometry.GRAVITY_1G * station.target_gravity_g
	var omega: float = TorusGeometry.compute_section_angular_velocity(station.section_radius, target_gravity)
	var total_expected_angle: float = omega * sub_delta * calls_per_tick * num_ticks
	var expected_delta_basis := Basis(Vector3.UP, total_expected_angle)

	var result := 0
	if not delta_basis.x.is_equal_approx(expected_delta_basis.x) \
			or not delta_basis.y.is_equal_approx(expected_delta_basis.y) \
			or not delta_basis.z.is_equal_approx(expected_delta_basis.z):
		print("FAIL _test_section_rotation_accumulates_across_physics_ticks: delta_basis=%s expected=%s (a smaller-than-expected delta would mean sync_to_physics is silently dropping intermediate rotations)" % [delta_basis, expected_delta_basis])
		result = 1
	station.free()
	return result

func _test_bridge_rotation_accumulates_across_physics_ticks() -> int:
	# Same bug class as the section test above, now checked on a bridge:
	# bridges also rotate every frame (together with sections) and are also
	# AnimatableBody3D, so they need sync_to_physics=false too.
	var station := _make_station()
	root.add_child(station)
	station.set_process(false)
	station.build_station()
	var bridge: Node3D = station.get_node("Bridge0")
	var original_basis: Basis = bridge.transform.basis

	var sub_delta := 0.02
	var calls_per_tick := 3
	var num_ticks := 3
	for tick in range(num_ticks):
		for sub in range(calls_per_tick):
			station._rotate_sections(sub_delta)
		await physics_frame

	var new_basis: Basis = bridge.transform.basis
	var delta_basis: Basis = original_basis.inverse() * new_basis

	var target_gravity: float = TorusGeometry.GRAVITY_1G * station.target_gravity_g
	var omega: float = TorusGeometry.compute_section_angular_velocity(station.section_radius, target_gravity)
	var total_expected_angle: float = omega * sub_delta * calls_per_tick * num_ticks
	var expected_delta_basis := Basis(Vector3.UP, total_expected_angle)

	var result := 0
	if not delta_basis.x.is_equal_approx(expected_delta_basis.x) \
			or not delta_basis.y.is_equal_approx(expected_delta_basis.y) \
			or not delta_basis.z.is_equal_approx(expected_delta_basis.z):
		print("FAIL _test_bridge_rotation_accumulates_across_physics_ticks: delta_basis=%s expected=%s" % [delta_basis, expected_delta_basis])
		result = 1
	station.free()
	return result

func _test_section_stays_aligned_with_parent_after_shift() -> int:
	# Mirrors what WorldOriginRebase does: shift a parent's position and
	# expect children (including physics bodies) to move with it. With
	# AnimatableBody3D's default sync_to_physics=true, the physics server
	# owns the transform and ignores a parent-driven change, leaving the
	# section's collider (and visuals) behind at the old position — see the
	# Critical finding in the code review that led to this test.
	var parent := Node3D.new()
	root.add_child(parent)
	var station := _make_station()
	parent.add_child(station)
	station.build_station()
	var section: Node3D = station.get_node("Section0")

	var section_position_before: Vector3 = section.global_position
	var offset := Vector3(6000.0, 0.0, 0.0)
	parent.position -= offset
	await physics_frame
	await physics_frame

	var expected_position: Vector3 = section_position_before - offset
	var result := 0
	if not section.global_position.is_equal_approx(expected_position):
		print("FAIL _test_section_stays_aligned_with_parent_after_shift: section.global_position=%s expected=%s (drift=%s)" % [section.global_position, expected_position, section.global_position - expected_position])
		result = 1
	station.free()
	parent.free()
	return result

# Full-scale radii (2000 m sections, 600 m bridges): the bug only shows at
# this size. 200 sections keep the build fast.
func _make_full_scale_station() -> Node3D:
	var station: Node3D = TorusStationScript.new()
	station.planet_radius = 500000.0
	station.orbit_altitude = 1500000.0
	station.num_sections = 200
	station.section_radius = 2000.0
	station.section_length = 20000.0
	station.target_gravity_g = 0.7
	return station

# A ship-sized box, not moving, turning like the mouse turns the ship, while
# resting on a hull. Returns the biggest distance it was shoved in one tick.
func _biggest_shove_while_turning_on(body: Node3D, surface_radius: float, along_axis: float) -> float:
	var hull := CharacterBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(15.0, 7.5, 30.0)
	shape_node.shape = box
	hull.add_child(shape_node)
	root.add_child(hull)
	var axis: Vector3 = body.global_transform.basis.y.normalized()
	var outward: Vector3 = (Vector3.UP - axis * Vector3.UP.dot(axis)).normalized()
	hull.global_position = body.global_position + axis * along_axis + outward * (surface_radius + 3.75 + 0.05)
	await physics_frame
	var biggest := 0.0
	for tick in range(240):
		var before: Vector3 = hull.global_position
		hull.move_and_collide(Vector3.ZERO)
		hull.rotate_object_local(Vector3.RIGHT, -0.7 / 60.0)
		hull.rotate_object_local(Vector3.UP, -1.4 / 60.0)
		await physics_frame
		biggest = maxf(biggest, hull.global_position.distance_to(before))
	hull.free()
	return biggest

func _test_rotating_hull_resting_on_section_does_not_jump() -> int:
	# Flight-log repro of the "teleport": with CylinderShape3D sections, a
	# still ship turning against the hull was shoved up to ~100 m per tick
	# (4.7 km in 4 s) by bad contacts from Godot's cylinder collision.
	var station := _make_full_scale_station()
	root.add_child(station)
	station.build_station()
	await physics_frame
	var biggest: float = await _biggest_shove_while_turning_on(station.get_node("Section0"), station.section_radius, -2709.0)
	var result := 0
	if biggest > 2.0:
		print("FAIL _test_rotating_hull_resting_on_section_does_not_jump: a still, turning hull was shoved %.1f m in one tick" % biggest)
		result = 1
	station.free()
	return result

func _test_rotating_hull_resting_on_bridge_does_not_jump() -> int:
	var station := _make_full_scale_station()
	root.add_child(station)
	station.build_station()
	await physics_frame
	var biggest: float = await _biggest_shove_while_turning_on(station.get_node("Bridge0"), station.section_radius * 0.3, 0.0)
	var result := 0
	if biggest > 2.0:
		print("FAIL _test_rotating_hull_resting_on_bridge_does_not_jump: a still, turning hull was shoved %.1f m in one tick" % biggest)
		result = 1
	station.free()
	return result

func _test_nearest_bridge_index_finds_each_port() -> int:
	var station := _make_station()
	root.add_child(station)
	station.set_process(false)
	station.build_station()
	await process_frame
	var result := 0
	for i in range(station.num_sections):
		var port: Node3D = station.get_docking_port(i)
		if port != station.get_node("DockingCollar%d/Port" % i):
			print("FAIL _test_nearest_bridge_index_finds_each_port: get_docking_port(%d) is not DockingCollar%d/Port" % [i, i])
			result = 1
			continue
		var index: int = station.nearest_bridge_index(port.global_position)
		if index != i:
			print("FAIL _test_nearest_bridge_index_finds_each_port: port %d resolved to bridge %d" % [i, index])
			result = 1
	station.free()
	return result

func _test_rotating_hull_resting_on_docking_collar_does_not_jump() -> int:
	# Same failure mode as the teleport bug, on the collar's trimesh shape.
	var station := _make_full_scale_station()
	root.add_child(station)
	station.set_process(false)
	station.build_station()
	await physics_frame
	var outer_radius: float = station.get_bridge_radius() * 1.25
	var biggest: float = await _biggest_shove_while_turning_on(station.get_node("DockingCollar0"), outer_radius, 0.0)
	var result := 0
	if biggest > 2.0:
		print("FAIL _test_rotating_hull_resting_on_docking_collar_does_not_jump: a still, turning hull was shoved %.1f m in one tick" % biggest)
		result = 1
	station.free()
	return result
