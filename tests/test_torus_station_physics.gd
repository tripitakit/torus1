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
