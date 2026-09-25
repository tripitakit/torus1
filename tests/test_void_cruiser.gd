extends SceneTree

const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")
const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")
const FlyingCraftScript = preload("res://scripts/flying_craft.gd")

func _init():
	var failures := 0
	failures += _test_apply_physics_step_moves_position()
	failures += _test_apply_physics_step_rotates_orientation()
	failures += _test_velocity_persists_across_steps_without_thrust()
	failures += _test_read_input_methods_do_not_crash_headless()
	failures += _test_mouse_look_is_independent_of_tick_rate()
	failures += _test_mouse_turns_at_a_sixth_of_the_original_rate()
	failures += _test_forward_hold_time_starts_at_zero()
	failures += _test_forward_hold_time_resets_on_first_press()
	failures += _test_forward_hold_time_accumulates_while_held()
	failures += _test_forward_hold_time_resets_on_release()
	failures += _test_forward_hold_time_resets_on_direction_reversal()
	failures += _test_forward_thrust_ramps_to_100x_over_ten_seconds()
	failures += _test_top_speed_about_21_6_km_s_after_the_full_ramp()
	failures += _test_cruise_key_toggles_the_lock()
	failures += _test_cruise_flies_to_top_speed_with_no_keys_held()
	failures += _test_cruise_carries_on_the_ramp_from_a_held_w()
	failures += _test_pressing_w_a_s_or_d_turns_cruise_off()
	failures += _test_roll_mouse_and_up_down_leave_cruise_on()
	failures += _test_process_shows_cruise_on_hud()
	failures += _test_tab_toggles_flight_assist_and_drops_cruise()
	failures += _test_without_assist_speed_and_spin_do_not_fade()
	failures += _test_without_assist_thrust_is_1x_and_unbounded()
	failures += _test_cruise_without_assist_does_not_push_forward()
	failures += _test_circular_orbit_holds_without_assist()
	failures += _test_diving_through_the_planet_does_not_fling_the_ship()
	failures += _test_cruise_without_assist_holds_velocity_in_strong_gravity()
	failures += _test_orbit_readout_on_the_ring()
	failures += _test_process_shows_orbit_on_hud()
	failures += _test_orbit_line_has_256_points_around_the_planet()
	failures += _test_orbit_line_hidden_without_planet()
	failures += _test_build_collision_shape_adds_box_shape()
	failures += _test_build_navigation_lights_adds_port_and_starboard_and_tail()
	failures += _test_build_navigation_lights_port_is_red_on_the_left()
	failures += _test_build_navigation_lights_starboard_is_green_on_the_right()
	failures += _test_build_navigation_lights_tail_is_white_toward_the_stern()
	failures += _test_build_headlights_adds_two_spotlights_near_the_nose()
	failures += _test_build_proximity_sensors_adds_six_rays_on_hull_faces()
	failures += _test_read_proximity_distances_off_tree_reports_no_hit()
	failures += _test_build_cockpit_adds_cockpit_at_pilot_eye()
	failures += _test_process_shows_ship_speed_on_hud()
	failures += _test_nav_light_markers_hidden_from_onboard_cameras()
	failures += _test_ship_model_is_gone()
	failures += _test_void_cruiser_flies_with_the_shared_flying_craft()

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

func _test_mouse_turns_at_a_sixth_of_the_original_rate() -> int:
	# Tuned in game: first 2/3 of the original 0.01 sensitivity, then 1/4 of that.
	var fake_event := InputEventMouseMotion.new()
	fake_event.relative = Vector2(30, 0)
	var cruiser := _make_cruiser()
	cruiser._unhandled_input(fake_event)
	var delta := 0.5
	var torque: Vector3 = cruiser._read_torque_input(delta)
	var result := 0
	var turn: float = torque.y * delta
	var expected: float = -30.0 * 0.01 / 6.0
	if not is_equal_approx(turn, expected):
		print("FAIL _test_mouse_turns_at_a_sixth_of_the_original_rate: 30 px gave yaw contribution %f, expected %f" % [turn, expected])
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

func _test_forward_thrust_ramps_to_100x_over_ten_seconds() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	cruiser._update_forward_hold_time(1.0, 1.0)
	if not is_equal_approx(cruiser.forward_thrust_multiplier(), 1.0):
		print("FAIL _test_forward_thrust_ramps_to_100x_over_ten_seconds: first-tick multiplier %f, expected 1" % cruiser.forward_thrust_multiplier())
		result = 1
	for i in range(5):
		cruiser._update_forward_hold_time(1.0, 1.0)
	if not is_equal_approx(cruiser.forward_thrust_multiplier(), 10.0):
		print("FAIL _test_forward_thrust_ramps_to_100x_over_ten_seconds: after 5 s multiplier %f, expected 10" % cruiser.forward_thrust_multiplier())
		result = 1
	for i in range(5):
		cruiser._update_forward_hold_time(1.0, 1.0)
	if not is_equal_approx(cruiser.forward_thrust_multiplier(), 100.0):
		print("FAIL _test_forward_thrust_ramps_to_100x_over_ten_seconds: after 10 s multiplier %f, expected 100" % cruiser.forward_thrust_multiplier())
		result = 1
	cruiser.free()
	return result

func _test_top_speed_about_21_6_km_s_after_the_full_ramp() -> int:
	# thrust 150 x 100, damping 0.5: v = 15000 / ln 2 ~ 21.6 km/s (21.8 with
	# 60 Hz steps). 20 s: 10 s of ramp, then 10 s to settle.
	var cruiser: Node3D = VoidCruiserScript.new()
	Input.action_press("move_forward")
	for i in range(1200):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var result := 0
	var speed: float = cruiser.velocity.length()
	if speed < 21000.0 or speed > 22500.0 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_top_speed_about_21_6_km_s_after_the_full_ramp: velocity %s (speed %.0f)" % [cruiser.velocity, speed])
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

func _test_build_navigation_lights_adds_port_and_starboard_and_tail() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_navigation_lights()
	var result := 0
	for light_name in ["PortLight", "StarboardLight", "TailLight"]:
		var light_node := cruiser.get_node_or_null(light_name)
		if light_node == null or not (light_node is OmniLight3D):
			print("FAIL _test_build_navigation_lights_adds_port_and_starboard_and_tail: no %s OmniLight3D child" % light_name)
			result = 1
	cruiser.free()
	return result

func _test_build_navigation_lights_port_is_red_on_the_left() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_navigation_lights()
	var result := 0
	var port_light: OmniLight3D = cruiser.get_node_or_null("PortLight")
	if port_light == null:
		print("FAIL _test_build_navigation_lights_port_is_red_on_the_left: no PortLight child")
		result = 1
	else:
		if not port_light.light_color.is_equal_approx(Color.RED):
			print("FAIL _test_build_navigation_lights_port_is_red_on_the_left: light_color=%s expected RED" % port_light.light_color)
			result = 1
		if port_light.position.x >= 0.0:
			print("FAIL _test_build_navigation_lights_port_is_red_on_the_left: position.x=%f expected negative (left)" % port_light.position.x)
			result = 1
	cruiser.free()
	return result

func _test_build_navigation_lights_starboard_is_green_on_the_right() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_navigation_lights()
	var result := 0
	var starboard_light: OmniLight3D = cruiser.get_node_or_null("StarboardLight")
	if starboard_light == null:
		print("FAIL _test_build_navigation_lights_starboard_is_green_on_the_right: no StarboardLight child")
		result = 1
	else:
		if not starboard_light.light_color.is_equal_approx(Color.GREEN):
			print("FAIL _test_build_navigation_lights_starboard_is_green_on_the_right: light_color=%s expected GREEN" % starboard_light.light_color)
			result = 1
		if starboard_light.position.x <= 0.0:
			print("FAIL _test_build_navigation_lights_starboard_is_green_on_the_right: position.x=%f expected positive (right)" % starboard_light.position.x)
			result = 1
	cruiser.free()
	return result

func _test_build_navigation_lights_tail_is_white_toward_the_stern() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_navigation_lights()
	var result := 0
	var tail_light: OmniLight3D = cruiser.get_node_or_null("TailLight")
	if tail_light == null:
		print("FAIL _test_build_navigation_lights_tail_is_white_toward_the_stern: no TailLight child")
		result = 1
	else:
		if not tail_light.light_color.is_equal_approx(Color.WHITE):
			print("FAIL _test_build_navigation_lights_tail_is_white_toward_the_stern: light_color=%s expected WHITE" % tail_light.light_color)
			result = 1
		if tail_light.position.z <= 0.0:
			print("FAIL _test_build_navigation_lights_tail_is_white_toward_the_stern: position.z=%f expected positive (aft, +Z is tail)" % tail_light.position.z)
			result = 1
	cruiser.free()
	return result

func _test_build_headlights_adds_two_spotlights_near_the_nose() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_headlights()
	var result := 0
	for light_name in ["HeadlightLeft", "HeadlightRight"]:
		var light_node := cruiser.get_node_or_null(light_name)
		if light_node == null or not (light_node is SpotLight3D):
			print("FAIL _test_build_headlights_adds_two_spotlights_near_the_nose: no %s SpotLight3D child" % light_name)
			result = 1
		else:
			var spot: SpotLight3D = light_node
			if spot.position.z >= 0.0:
				print("FAIL _test_build_headlights_adds_two_spotlights_near_the_nose: %s position.z=%f expected negative (nose, -Z is forward)" % [light_name, spot.position.z])
				result = 1
			# Tuned in game: reaches far in open space without blowing out to
			# white at close range.
			var tuned := {"light_energy": 18.0, "spot_range": 8000.0, "spot_angle": 45.0, "spot_attenuation": 0.8}
			for property in tuned:
				if not is_equal_approx(spot.get(property), tuned[property]):
					print("FAIL _test_build_headlights_adds_two_spotlights_near_the_nose: %s %s=%f expected %f (tuned value)" % [light_name, property, spot.get(property), tuned[property]])
					result = 1
			if spot.shadow_enabled:
				# Shadow-mapped self-shadowing on the station's large-radius
				# curved hull produces flickering acne bands at range (shadow
				# map precision breaks down at kilometer scale); disabled by
				# design, not an oversight.
				print("FAIL _test_build_headlights_adds_two_spotlights_near_the_nose: %s shadow_enabled=true expected false (shadow acne at station scale)" % light_name)
				result = 1
	cruiser.free()
	return result

func _test_build_proximity_sensors_adds_six_rays_on_hull_faces() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_proximity_sensors()
	var result := 0
	# name: [position on the hull face, target_position (20 km outward)]
	var expected := {
		"SensorBow": [Vector3(0.0, 0.0, -15.0), Vector3(0.0, 0.0, -20000.0)],
		"SensorStern": [Vector3(0.0, 0.0, 15.0), Vector3(0.0, 0.0, 20000.0)],
		"SensorPort": [Vector3(-7.5, 0.0, 0.0), Vector3(-20000.0, 0.0, 0.0)],
		"SensorStarboard": [Vector3(7.5, 0.0, 0.0), Vector3(20000.0, 0.0, 0.0)],
		"SensorDorsal": [Vector3(0.0, 3.75, 0.0), Vector3(0.0, 20000.0, 0.0)],
		"SensorVentral": [Vector3(0.0, -3.75, 0.0), Vector3(0.0, -20000.0, 0.0)],
	}
	for sensor_name in expected:
		var node := cruiser.get_node_or_null(sensor_name)
		if node == null or not (node is RayCast3D):
			print("FAIL _test_build_proximity_sensors_adds_six_rays_on_hull_faces: no %s RayCast3D child" % sensor_name)
			result = 1
			continue
		var ray: RayCast3D = node
		var expected_position: Vector3 = expected[sensor_name][0]
		var expected_target: Vector3 = expected[sensor_name][1]
		if not ray.position.is_equal_approx(expected_position):
			print("FAIL _test_build_proximity_sensors_adds_six_rays_on_hull_faces: %s position=%s expected=%s" % [sensor_name, ray.position, expected_position])
			result = 1
		if not ray.target_position.is_equal_approx(expected_target):
			print("FAIL _test_build_proximity_sensors_adds_six_rays_on_hull_faces: %s target_position=%s expected=%s" % [sensor_name, ray.target_position, expected_target])
			result = 1
	cruiser.free()
	return result

func _test_read_proximity_distances_off_tree_reports_no_hit() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_proximity_sensors()
	var distances: Dictionary = cruiser.read_proximity_distances()
	var result := 0
	for key in ["bow", "stern", "port", "starboard", "dorsal", "ventral"]:
		if not distances.has(key):
			print("FAIL _test_read_proximity_distances_off_tree_reports_no_hit: missing key %s" % key)
			result = 1
		elif not is_equal_approx(distances[key], -1.0):
			print("FAIL _test_read_proximity_distances_off_tree_reports_no_hit: %s=%s expected -1.0 (no physics frame, no hit)" % [key, distances[key]])
			result = 1
	if distances.size() != 6:
		print("FAIL _test_read_proximity_distances_off_tree_reports_no_hit: %d keys, expected 6" % distances.size())
		result = 1
	cruiser.free()
	return result

func _test_build_cockpit_adds_cockpit_at_pilot_eye() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_cockpit()
	var result := 0
	var cockpit := cruiser.get_node_or_null("Cockpit")
	if cockpit == null:
		print("FAIL _test_build_cockpit_adds_cockpit_at_pilot_eye: no Cockpit child")
		result = 1
	else:
		if not (cockpit as Node3D).position.is_equal_approx(Vector3(0.0, 0.5, -8.0)):
			print("FAIL _test_build_cockpit_adds_cockpit_at_pilot_eye: position=%s expected (0, 0.5, -8)" % (cockpit as Node3D).position)
			result = 1
		if cockpit.get_node_or_null("PilotCamera") == null:
			print("FAIL _test_build_cockpit_adds_cockpit_at_pilot_eye: Cockpit was not built (no PilotCamera)")
			result = 1
	cruiser.free()
	return result

func _test_process_shows_ship_speed_on_hud() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_proximity_sensors()
	cruiser.build_cockpit()
	cruiser.velocity = Vector3(30.0, 0.0, -40.0)
	cruiser._process(0.016)
	var result := 0
	var speed_label: Label = cruiser.get_node("Cockpit/Hud/Panel/Lines/SpeedLabel")
	if speed_label.text != "SPEED  50 m/s":
		print("FAIL _test_process_shows_ship_speed_on_hud: SpeedLabel='%s' expected 'SPEED  50 m/s'" % speed_label.text)
		result = 1
	var bow_label: Label = cruiser.get_node("Cockpit/Hud/Panel/Lines/BowLabel")
	if bow_label.text != "BOW  —":
		print("FAIL _test_process_shows_ship_speed_on_hud: BowLabel='%s' expected 'BOW  —' (off-tree: no hit)" % bow_label.text)
		result = 1
	cruiser.free()
	return result

func _test_nav_light_markers_hidden_from_onboard_cameras() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_navigation_lights()
	var result := 0
	for light_name in ["PortLight", "StarboardLight", "TailLight"]:
		var marker: MeshInstance3D = cruiser.get_node("%s/Marker" % light_name)
		if marker.layers != 4:
			print("FAIL _test_nav_light_markers_hidden_from_onboard_cameras: %s marker layers=%d expected 4 (SHIP_EXTERIOR_LAYER)" % [light_name, marker.layers])
			result = 1
	cruiser.free()
	return result

func _test_ship_model_is_gone() -> int:
	# First-person cockpit: the ship has no exterior model any more.
	var cruiser := _make_cruiser()
	var result := 0
	if cruiser.has_method("build_ship_mesh"):
		print("FAIL _test_ship_model_is_gone: void_cruiser.gd still has build_ship_mesh()")
		result = 1
	for path in ["res://assets/models/void_cruiser.glb", "res://assets/models/void_cruiser.glb.import"]:
		if FileAccess.file_exists(path):
			print("FAIL _test_ship_model_is_gone: %s still exists" % path)
			result = 1
	cruiser.free()
	return result

func _test_void_cruiser_flies_with_the_shared_flying_craft() -> int:
	# The internal-cruiser reuses the same flight model: it lives in one place.
	var cruiser := _make_cruiser()
	var result := 0
	if (cruiser.get_script() as Script).get_base_script() != FlyingCraftScript:
		print("FAIL _test_void_cruiser_flies_with_the_shared_flying_craft: void_cruiser.gd does not extend flying_craft.gd")
		result = 1
	cruiser.free()
	return result

func _press(cruiser: Node, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	cruiser._unhandled_input(event)

func _test_cruise_key_toggles_the_lock() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	if cruiser.cruise_locked:
		print("FAIL _test_cruise_key_toggles_the_lock: cruise on from the start")
		result = 1
	_press(cruiser, "cruise")
	if not cruiser.cruise_locked:
		print("FAIL _test_cruise_key_toggles_the_lock: C did not turn cruise on")
		result = 1
	_press(cruiser, "cruise")
	if cruiser.cruise_locked:
		print("FAIL _test_cruise_key_toggles_the_lock: a second C did not turn cruise off")
		result = 1
	cruiser.free()
	return result

func _test_cruise_flies_to_top_speed_with_no_keys_held() -> int:
	# Same as holding W for 20 s: 100x after 10 s, then ~21.6 km/s.
	var cruiser: Node3D = VoidCruiserScript.new()
	_press(cruiser, "cruise")
	for i in range(1200):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	var speed: float = cruiser.velocity.length()
	if speed < 21000.0 or speed > 22500.0 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_cruise_flies_to_top_speed_with_no_keys_held: velocity %s (speed %.0f)" % [cruiser.velocity, speed])
		result = 1
	cruiser.free()
	return result

func _test_cruise_carries_on_the_ramp_from_a_held_w() -> int:
	# W held 5 s (10x), C pressed, W let go: the ramp goes on, no restart.
	var cruiser := _make_cruiser()
	Input.action_press("move_forward")
	for i in range(300):
		cruiser._physics_process(1.0 / 60.0)
	_press(cruiser, "cruise")
	Input.action_release("move_forward")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if not cruiser.cruise_locked or cruiser.forward_thrust_multiplier() < 20.0:
		print("FAIL _test_cruise_carries_on_the_ramp_from_a_held_w: cruise %s, multiplier %f after 6 s (expected about 28)" % [cruiser.cruise_locked, cruiser.forward_thrust_multiplier()])
		result = 1
	cruiser.free()
	return result

func _test_pressing_w_a_s_or_d_turns_cruise_off() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		_press(cruiser, "cruise")
		_press(cruiser, action)
		if cruiser.cruise_locked:
			print("FAIL _test_pressing_w_a_s_or_d_turns_cruise_off: %s left cruise on" % action)
			result = 1
			cruiser.cruise_locked = false
	cruiser.free()
	return result

func _test_roll_mouse_and_up_down_leave_cruise_on() -> int:
	var cruiser := _make_cruiser()
	_press(cruiser, "cruise")
	for action in ["roll_left", "roll_right", "move_up", "move_down"]:
		_press(cruiser, action)
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(40.0, -25.0)
	cruiser._unhandled_input(mouse)
	var result := 0
	if not cruiser.cruise_locked:
		print("FAIL _test_roll_mouse_and_up_down_leave_cruise_on: cruise turned off")
		result = 1
	cruiser.free()
	return result

func _test_process_shows_cruise_on_hud() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_proximity_sensors()
	cruiser.build_cockpit()
	var label: Label = cruiser.get_node("Cockpit/Hud/Panel/Lines/CruiseLabel")
	var result := 0
	_press(cruiser, "cruise")
	cruiser._process(0.016)
	if not label.visible:
		print("FAIL _test_process_shows_cruise_on_hud: CRUISE hidden while cruising")
		result = 1
	_press(cruiser, "move_left")
	cruiser._process(0.016)
	if label.visible:
		print("FAIL _test_process_shows_cruise_on_hud: CRUISE still shown after A")
		result = 1
	cruiser.free()
	return result

func _test_tab_toggles_flight_assist_and_drops_cruise() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	if not cruiser.flight_assist:
		print("FAIL _test_tab_toggles_flight_assist_and_drops_cruise: assist off at start")
		result = 1
	_press(cruiser, "cruise")
	_press(cruiser, "flight_assist")
	if cruiser.flight_assist or cruiser.cruise_locked:
		print("FAIL _test_tab_toggles_flight_assist_and_drops_cruise: after Tab assist %s cruise %s, expected both off" % [cruiser.flight_assist, cruiser.cruise_locked])
		result = 1
	_press(cruiser, "flight_assist")
	if not cruiser.flight_assist:
		print("FAIL _test_tab_toggles_flight_assist_and_drops_cruise: a second Tab did not turn assist back on")
		result = 1
	cruiser.free()
	return result

func _test_without_assist_speed_and_spin_do_not_fade() -> int:
	# Default damping 0.5 would halve both every second; without assist, none.
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.flight_assist = false
	cruiser.velocity = Vector3(0.0, 0.0, -100.0)
	cruiser.angular_velocity = Vector3(0.2, 0.0, 0.0)
	for i in range(120):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if absf(cruiser.velocity.length() - 100.0) > 1e-6 or absf(cruiser.angular_velocity.length() - 0.2) > 1e-9:
		print("FAIL _test_without_assist_speed_and_spin_do_not_fade: speed %f spin %f after 2 s" % [cruiser.velocity.length(), cruiser.angular_velocity.length()])
		result = 1
	cruiser.free()
	return result

func _test_without_assist_thrust_is_1x_and_unbounded() -> int:
	# 150 m/s^2 for 10 s: 1500 m/s, no ramp and no drag to cap it.
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.flight_assist = false
	Input.action_press("move_forward")
	for i in range(600):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var result := 0
	if absf(cruiser.velocity.length() - 1500.0) > 5.0 or not is_equal_approx(cruiser.forward_thrust_multiplier(), 1.0):
		print("FAIL _test_without_assist_thrust_is_1x_and_unbounded: speed %.1f (expected 1500), multiplier %f" % [cruiser.velocity.length(), cruiser.forward_thrust_multiplier()])
		result = 1
	cruiser.free()
	return result

func _test_cruise_without_assist_does_not_push_forward() -> int:
	# Without assist C holds the current velocity instead of pushing.
	var cruiser := _make_cruiser()
	cruiser.flight_assist = false
	_press(cruiser, "cruise")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if not cruiser.cruise_locked or not cruiser.velocity.is_zero_approx():
		print("FAIL _test_cruise_without_assist_does_not_push_forward: cruise %s velocity %s" % [cruiser.cruise_locked, cruiser.velocity])
		result = 1
	cruiser.free()
	return result

func _orbiting_cruiser() -> Node3D:
	# A ship in the ring's frame around a planet at the origin (off-tree, so
	# the planet is set by hand instead of read from the scene).
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.has_planet = true
	cruiser.planet_center = Vector3.ZERO
	cruiser.planet_axis = Vector3.UP
	return cruiser

func _test_circular_orbit_holds_without_assist() -> int:
	# A true circular orbit at 2500 km from the centre, seen from the ring's
	# frame. Without the forces the ship would fly straight and end ~87 km
	# higher after 600 s.
	var cruiser := _orbiting_cruiser()
	cruiser.flight_assist = false
	var r0 := 2.5e6
	var circular: float = sqrt(cruiser.planet_gm / r0)
	cruiser.position = Vector3(r0, 0.0, 0.0)
	cruiser.velocity = Vector3(0.0, 0.0, -circular) - cruiser.ring_omega().cross(cruiser.position)
	for i in range(36000):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	var drift: float = cruiser.position.length() - r0
	if absf(drift) > 50.0:
		print("FAIL _test_circular_orbit_holds_without_assist: radius off by %.1f m after 600 s" % drift)
		result = 1
	cruiser.free()
	return result

func _test_cruise_without_assist_holds_velocity_in_strong_gravity() -> int:
	# 2000 km from the centre gravity is ~1.2 m/s^2: the lock cancels it.
	var cruiser := _orbiting_cruiser()
	cruiser.flight_assist = false
	cruiser.position = Vector3(2.0e6, 0.0, 0.0)
	cruiser.velocity = Vector3(0.0, 0.0, -300.0)
	_press(cruiser, "cruise")
	for i in range(120):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if not cruiser.velocity.is_equal_approx(Vector3(0.0, 0.0, -300.0)):
		print("FAIL _test_cruise_without_assist_holds_velocity_in_strong_gravity: velocity drifted to %s" % cruiser.velocity)
		result = 1
	# Z (dorsal thrust) changes it; the lock then holds the new velocity.
	Input.action_press("move_up")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_up")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	if not cruiser.cruise_locked or absf(cruiser.velocity.y - 150.0) > 0.5 or absf(cruiser.velocity.z + 300.0) > 0.5:
		print("FAIL _test_cruise_without_assist_holds_velocity_in_strong_gravity: after Z velocity %s, cruise %s (expected y ~150, z -300, still locked)" % [cruiser.velocity, cruiser.cruise_locked])
		result = 1
	cruiser.free()
	return result

func _test_orbit_readout_on_the_ring() -> int:
	var cruiser := _orbiting_cruiser()
	cruiser.position = Vector3(cruiser.ring_radius, 0.0, 0.0)
	var readout: Dictionary = cruiser.orbit_readout()
	var expected: float = cruiser.ring_radius - cruiser.planet_radius
	var result := 0
	if absf(readout.altitude - expected) > 1.0 or absf(readout.periapsis - expected) > 1.0 or absf(readout.apoapsis - expected) > 1.0:
		print("FAIL _test_orbit_readout_on_the_ring: %s, expected all about %.1f" % [readout, expected])
		result = 1
	var loose: Node3D = VoidCruiserScript.new()
	if not loose.orbit_readout().is_empty():
		print("FAIL _test_orbit_readout_on_the_ring: a ship without a planet reports an orbit")
		result = 1
	loose.free()
	cruiser.free()
	return result

func _test_process_shows_orbit_on_hud() -> int:
	var cruiser := _orbiting_cruiser()
	cruiser.build_proximity_sensors()
	cruiser.build_cockpit()
	cruiser.position = Vector3(cruiser.ring_radius + 10000.0, 0.0, 0.0)
	cruiser._process(0.016)
	var altitude: Label = cruiser.get_node("Cockpit/Hud/Panel/Lines/AltitudeLabel")
	var assist: Label = cruiser.get_node("Cockpit/Hud/Panel/Lines/AssistLabel")
	var result := 0
	if altitude.text != "ALTITUDE  5222 km" or assist.text != "ASSIST  ON":
		print("FAIL _test_process_shows_orbit_on_hud: '%s' / '%s'" % [altitude.text, assist.text])
		result = 1
	cruiser.free()
	return result

func _test_orbit_line_has_256_points_around_the_planet() -> int:
	var cruiser := _orbiting_cruiser()
	cruiser.planet_center = Vector3(10.0, -20.0, 30.0)
	cruiser.position = cruiser.planet_center + Vector3(cruiser.ring_radius, 0.0, 0.0)
	cruiser.build_orbit_line()
	cruiser._process(0.016)
	var line := cruiser.get_node_or_null("OrbitLine") as MeshInstance3D
	var result := 0
	if line == null or not line.visible or not line.top_level or not line.position.is_equal_approx(cruiser.planet_center):
		print("FAIL _test_orbit_line_has_256_points_around_the_planet: line missing, hidden, not top-level or not on the planet")
		cruiser.free()
		return 1
	var mesh := line.mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_LINE_STRIP or points.size() != 256:
		print("FAIL _test_orbit_line_has_256_points_around_the_planet: %d points, primitive %d" % [points.size(), mesh.surface_get_primitive_type(0)])
		result = 1
	for p in points:
		# At rest on the ring the orbit is the ring's circle.
		if absf(p.length() - cruiser.ring_radius) > 2.0:
			print("FAIL _test_orbit_line_has_256_points_around_the_planet: point at %.1f m from the centre" % p.length())
			result = 1
			break
	cruiser._process(0.016)
	if (line.mesh as ArrayMesh).get_surface_count() != 1:
		print("FAIL _test_orbit_line_has_256_points_around_the_planet: surfaces pile up (%d)" % (line.mesh as ArrayMesh).get_surface_count())
		result = 1
	cruiser.free()
	return result

func _test_orbit_line_hidden_without_planet() -> int:
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.build_orbit_line()
	cruiser._process(0.016)
	var result := 0
	if (cruiser.get_node("OrbitLine") as MeshInstance3D).visible:
		print("FAIL _test_orbit_line_hidden_without_planet: line shown with no planet")
		result = 1
	cruiser.free()
	return result

func _test_diving_through_the_planet_does_not_fling_the_ship() -> int:
	# The planet has no collision. A dive 200 m off the centre, 1000 km
	# inside, at 2 km/s: with 1/r^2 all the way in, the 60 Hz step shoots
	# the ship out at hundreds of km/s. A uniform-sphere pull tops out near
	# 2.1 km/s at the centre.
	var cruiser := _orbiting_cruiser()
	cruiser.flight_assist = false
	cruiser.planet_axis = Vector3.RIGHT  # no centrifugal push along the dive
	cruiser.position = Vector3(200.0, 0.0, 1.0e6)
	cruiser.velocity = Vector3(0.0, 0.0, -2000.0)
	var fastest := 0.0
	for i in range(36000):
		cruiser._physics_process(1.0 / 60.0)
		fastest = maxf(fastest, cruiser.velocity.length())
	var result := 0
	if fastest > 3000.0:
		print("FAIL _test_diving_through_the_planet_does_not_fling_the_ship: reached %.0f m/s" % fastest)
		result = 1
	cruiser.free()
	return result
