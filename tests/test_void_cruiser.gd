extends SceneTree

const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")
const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")

func _init():
	var failures := 0
	failures += _test_apply_physics_step_moves_position()
	failures += _test_apply_physics_step_rotates_orientation()
	failures += _test_velocity_persists_across_steps_without_thrust()
	failures += _test_read_input_methods_do_not_crash_headless()
	failures += _test_mouse_look_is_independent_of_tick_rate()
	failures += _test_build_ship_mesh_adds_visible_mesh()
	failures += _test_ship_model_faces_forward()
	failures += _test_forward_hold_time_starts_at_zero()
	failures += _test_forward_hold_time_resets_on_first_press()
	failures += _test_forward_hold_time_accumulates_while_held()
	failures += _test_forward_hold_time_resets_on_release()
	failures += _test_forward_hold_time_resets_on_direction_reversal()
	failures += _test_forward_thrust_ramps_up_velocity_over_time()
	failures += _test_build_collision_shape_adds_box_shape()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_cruiser() -> Node3D:
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.thrust_power = 50.0
	cruiser.linear_damping = 0.0
	cruiser.torque_power = 2.0
	cruiser.angular_damping = 0.0
	return cruiser

func _test_apply_physics_step_moves_position() -> int:
	var cruiser := _make_cruiser()
	var start_position: Vector3 = cruiser.position
	cruiser._apply_physics_step(1.0, Vector3(0, 0, -1), Vector3.ZERO)
	var result := 0
	var expected_velocity := Vector3(0, 0, -50.0)
	if not cruiser.velocity.is_equal_approx(expected_velocity):
		print("FAIL _test_apply_physics_step_moves_position: velocity=%s expected=%s" % [cruiser.velocity, expected_velocity])
		result = 1
	var expected_position := start_position + expected_velocity * 1.0
	if not cruiser.position.is_equal_approx(expected_position):
		print("FAIL _test_apply_physics_step_moves_position: position=%s expected=%s" % [cruiser.position, expected_position])
		result = 1
	cruiser.free()
	return result

func _test_apply_physics_step_rotates_orientation() -> int:
	var cruiser := _make_cruiser()
	var original_basis: Basis = cruiser.transform.basis
	cruiser._apply_physics_step(0.5, Vector3.ZERO, Vector3(0, 1, 0))
	var result := 0
	var expected_angular_velocity := Vector3(0, 1.0, 0)
	if not cruiser.angular_velocity.is_equal_approx(expected_angular_velocity):
		print("FAIL _test_apply_physics_step_rotates_orientation: angular_velocity=%s expected=%s" % [cruiser.angular_velocity, expected_angular_velocity])
		result = 1
	var new_basis: Basis = cruiser.transform.basis
	var delta_basis: Basis = original_basis.inverse() * new_basis
	var expected_delta_basis := Basis(Vector3.UP, expected_angular_velocity.y * 0.5)
	if not delta_basis.y.is_equal_approx(expected_delta_basis.y) or not delta_basis.x.is_equal_approx(expected_delta_basis.x):
		print("FAIL _test_apply_physics_step_rotates_orientation: delta_basis=%s expected=%s" % [delta_basis, expected_delta_basis])
		result = 1
	cruiser.free()
	return result

func _test_velocity_persists_across_steps_without_thrust() -> int:
	var cruiser := _make_cruiser()
	cruiser._apply_physics_step(1.0, Vector3(0, 0, -1), Vector3.ZERO)
	var velocity_after_thrust: Vector3 = cruiser.velocity
	var position_after_thrust: Vector3 = cruiser.position
	cruiser._apply_physics_step(1.0, Vector3.ZERO, Vector3.ZERO)
	var result := 0
	if not cruiser.velocity.is_equal_approx(velocity_after_thrust):
		print("FAIL _test_velocity_persists_across_steps_without_thrust: velocity changed to %s, expected unchanged %s (damping=0)" % [cruiser.velocity, velocity_after_thrust])
		result = 1
	var expected_position := position_after_thrust + velocity_after_thrust * 1.0
	if not cruiser.position.is_equal_approx(expected_position):
		print("FAIL _test_velocity_persists_across_steps_without_thrust: position=%s expected=%s" % [cruiser.position, expected_position])
		result = 1
	cruiser.free()
	return result

func _test_read_input_methods_do_not_crash_headless() -> int:
	var cruiser := _make_cruiser()
	var thrust: Vector3 = cruiser._read_thrust_input()
	var torque: Vector3 = cruiser._read_torque_input(1.0 / 60.0)
	var result := 0
	if not thrust.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_read_input_methods_do_not_crash_headless: thrust=%s expected ZERO with no keys held" % thrust)
		result = 1
	if not torque.is_equal_approx(Vector3.ZERO):
		print("FAIL _test_read_input_methods_do_not_crash_headless: torque=%s expected ZERO with no input" % torque)
		result = 1
	cruiser.free()
	return result

func _test_mouse_look_is_independent_of_tick_rate() -> int:
	var fake_event := InputEventMouseMotion.new()
	fake_event.relative = Vector2(10, 0)

	var cruiser_a := _make_cruiser()
	cruiser_a._unhandled_input(fake_event)
	var torque_a: Vector3 = cruiser_a._read_torque_input(0.5)

	var cruiser_b := _make_cruiser()
	cruiser_b._unhandled_input(fake_event)
	var torque_b: Vector3 = cruiser_b._read_torque_input(0.25)

	var result := 0
	# The actual angular-velocity contribution (torque_input * delta, inside
	# compute_new_angular_velocity) must be the same regardless of tick rate
	# for the same physical mouse movement.
	var contribution_a := torque_a.y * 0.5
	var contribution_b := torque_b.y * 0.25
	if not is_equal_approx(contribution_a, contribution_b):
		print("FAIL _test_mouse_look_is_independent_of_tick_rate: contribution_a=%f contribution_b=%f" % [contribution_a, contribution_b])
		result = 1
	cruiser_a.free()
	cruiser_b.free()
	return result

func _test_build_ship_mesh_adds_visible_mesh() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_ship_mesh()
	var result := 0
	var model_node := cruiser.get_node_or_null("ShipModel")
	if model_node == null:
		print("FAIL _test_build_ship_mesh_adds_visible_mesh: no ShipModel child")
		result = 1
	else:
		var hull := model_node.find_child("Hull_Cargo", true, false)
		if hull == null or not (hull is MeshInstance3D):
			print("FAIL _test_build_ship_mesh_adds_visible_mesh: ShipModel has no Hull_Cargo MeshInstance3D")
			result = 1
	cruiser.free()
	return result

func _test_ship_model_faces_forward() -> int:
	# Blender's glTF exporter does not automatically align a model's nose
	# with Godot's -Z forward: this ship was authored nose-toward -Y in
	# Blender, which the exporter placed nose-toward +Z in Godot (facing
	# the chase camera instead of away from it). Corrected with a fixed
	# 180-degree yaw applied at instantiation; verify it stays applied.
	var cruiser := _make_cruiser()
	cruiser.build_ship_mesh()
	var result := 0
	var model_node := cruiser.get_node_or_null("ShipModel")
	if model_node == null:
		print("FAIL _test_ship_model_faces_forward: no ShipModel child")
		result = 1
	elif not is_equal_approx(wrapf(model_node.rotation_degrees.y, 0.0, 360.0), 180.0):
		print("FAIL _test_ship_model_faces_forward: ShipModel rotation_degrees.y=%f expected 180" % model_node.rotation_degrees.y)
		result = 1
	cruiser.free()
	return result

func _test_forward_hold_time_starts_at_zero() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	if not is_equal_approx(cruiser._forward_hold_time, 0.0):
		print("FAIL _test_forward_hold_time_starts_at_zero: _forward_hold_time=%f" % cruiser._forward_hold_time)
		result = 1
	cruiser.free()
	return result

func _test_forward_hold_time_resets_on_first_press() -> int:
	# The tick a key first goes down is a fresh hold: multiplier must start at
	# 1x, not carry over from whatever _forward_hold_sign was before.
	var cruiser := _make_cruiser()
	cruiser._update_forward_hold_time(1.0, 0.5)
	var result := 0
	if not is_equal_approx(cruiser._forward_hold_time, 0.0):
		print("FAIL _test_forward_hold_time_resets_on_first_press: _forward_hold_time=%f expected 0.0" % cruiser._forward_hold_time)
		result = 1
	cruiser.free()
	return result

func _test_forward_hold_time_accumulates_while_held() -> int:
	var cruiser := _make_cruiser()
	cruiser._update_forward_hold_time(1.0, 0.5)
	cruiser._update_forward_hold_time(1.0, 0.3)
	cruiser._update_forward_hold_time(1.0, 0.2)
	var result := 0
	if not is_equal_approx(cruiser._forward_hold_time, 0.5):
		print("FAIL _test_forward_hold_time_accumulates_while_held: _forward_hold_time=%f expected 0.5" % cruiser._forward_hold_time)
		result = 1
	cruiser.free()
	return result

func _test_forward_hold_time_resets_on_release() -> int:
	var cruiser := _make_cruiser()
	cruiser._update_forward_hold_time(1.0, 0.5)
	cruiser._update_forward_hold_time(1.0, 0.5)
	cruiser._update_forward_hold_time(0.0, 0.5)
	var result := 0
	if not is_equal_approx(cruiser._forward_hold_time, 0.0):
		print("FAIL _test_forward_hold_time_resets_on_release: _forward_hold_time=%f expected 0.0" % cruiser._forward_hold_time)
		result = 1
	cruiser.free()
	return result

func _test_forward_hold_time_resets_on_direction_reversal() -> int:
	var cruiser := _make_cruiser()
	cruiser._update_forward_hold_time(1.0, 0.5)
	cruiser._update_forward_hold_time(1.0, 0.5)
	cruiser._update_forward_hold_time(-1.0, 0.5)
	var result := 0
	if not is_equal_approx(cruiser._forward_hold_time, 0.0):
		print("FAIL _test_forward_hold_time_resets_on_direction_reversal: _forward_hold_time=%f expected 0.0" % cruiser._forward_hold_time)
		result = 1
	cruiser.free()
	return result

func _test_forward_thrust_ramps_up_velocity_over_time() -> int:
	var cruiser := _make_cruiser()
	var delta := 1.0
	var result := 0

	cruiser._update_forward_hold_time(1.0, delta)
	var multiplier_first_tick: float = VoidCruiserPhysics.compute_forward_thrust_multiplier(
		cruiser._forward_hold_time, cruiser.forward_thrust_ramp_duration, cruiser.forward_thrust_ramp_multiplier)
	if not is_equal_approx(multiplier_first_tick, 1.0):
		print("FAIL _test_forward_thrust_ramps_up_velocity_over_time: first-tick multiplier=%f expected 1.0" % multiplier_first_tick)
		result = 1

	var ticks_needed := int(cruiser.forward_thrust_ramp_duration / delta)
	for i in range(ticks_needed):
		cruiser._update_forward_hold_time(1.0, delta)
	var multiplier_max: float = VoidCruiserPhysics.compute_forward_thrust_multiplier(
		cruiser._forward_hold_time, cruiser.forward_thrust_ramp_duration, cruiser.forward_thrust_ramp_multiplier)
	if not is_equal_approx(multiplier_max, cruiser.forward_thrust_ramp_multiplier):
		print("FAIL _test_forward_thrust_ramps_up_velocity_over_time: after holding %fs multiplier=%f expected=%f" % [cruiser.forward_thrust_ramp_duration, multiplier_max, cruiser.forward_thrust_ramp_multiplier])
		result = 1

	cruiser.free()
	return result

func _test_build_collision_shape_adds_box_shape() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_collision_shape()
	var result := 0
	var shape_node := cruiser.get_node_or_null("CollisionShape3D")
	if shape_node == null or not (shape_node is CollisionShape3D):
		print("FAIL _test_build_collision_shape_adds_box_shape: no CollisionShape3D child")
		result = 1
	elif (shape_node as CollisionShape3D).shape == null or not ((shape_node as CollisionShape3D).shape is BoxShape3D):
		print("FAIL _test_build_collision_shape_adds_box_shape: shape is not a BoxShape3D")
		result = 1
	else:
		var box: BoxShape3D = (shape_node as CollisionShape3D).shape
		var expected := Vector3(15.0, 7.5, 30.0)
		if not box.size.is_equal_approx(expected):
			print("FAIL _test_build_collision_shape_adds_box_shape: size=%s expected=%s" % [box.size, expected])
			result = 1
	cruiser.free()
	return result
