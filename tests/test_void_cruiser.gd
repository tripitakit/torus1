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
	failures += _test_cruise_key_toggles_the_lock()
	failures += _test_pressing_w_a_s_or_d_turns_cruise_off()
	failures += _test_roll_mouse_and_up_down_leave_cruise_on()
	failures += _test_process_shows_cruise_on_hud()
	failures += _test_speed_does_not_fade_but_spin_does()
	failures += _test_ramp_without_drag_reaches_about_45_km_s_in_10_s()
	failures += _test_cruise_holds_instead_of_pushing()
	failures += _test_one_flight_mode_and_no_orbit_line()
	failures += _test_circular_orbit_holds()
	failures += _test_diving_through_the_planet_does_not_fling_the_ship()
	failures += _test_cruise_holds_velocity_in_strong_gravity()
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
	failures += _test_approach_guide_hidden_without_a_station()
	failures += _test_process_feeds_the_velocity_cross()
	failures += _test_process_feeds_the_navball()
	failures += _test_brake_key_toggles_and_turns_cruise_off()
	failures += _test_thrust_keys_release_the_brake()
	failures += _test_brake_stops_the_ship_at_ten_times_thrust()
	failures += _test_sphere_entry_finds_where_a_move_enters_the_planet()
	failures += _test_crashes_on_the_planet_instead_of_passing_through()
	failures += _test_restart_forgets_the_mouse_moved_on_the_crash_screen()

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

func _orbiting_cruiser() -> Node3D:
	# A ship in the ring's frame around a planet at the origin (off-tree, so
	# the planet is set by hand instead of read from the scene).
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.has_planet = true
	cruiser.planet_center = Vector3.ZERO
	cruiser.planet_axis = Vector3.UP
	return cruiser

func _test_circular_orbit_holds() -> int:
	# A true circular orbit at 2500 km from the centre, seen from the ring's
	# frame. Without the forces the ship would fly straight and end ~87 km
	# higher after 600 s.
	var cruiser := _orbiting_cruiser()
	var r0 := 2.5e6
	var circular: float = sqrt(cruiser.planet_gm / r0)
	cruiser.position = Vector3(r0, 0.0, 0.0)
	cruiser.velocity = Vector3(0.0, 0.0, -circular) - cruiser.ring_omega().cross(cruiser.position)
	for i in range(36000):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	var drift: float = cruiser.position.length() - r0
	if absf(drift) > 50.0:
		print("FAIL _test_circular_orbit_holds: radius off by %.1f m after 600 s" % drift)
		result = 1
	cruiser.free()
	return result

func _test_cruise_holds_velocity_in_strong_gravity() -> int:
	# 2000 km from the centre gravity is ~1.2 m/s^2: the lock cancels it.
	var cruiser := _orbiting_cruiser()
	cruiser.position = Vector3(2.0e6, 0.0, 0.0)
	cruiser.velocity = Vector3(0.0, 0.0, -300.0)
	_press(cruiser, "cruise")
	for i in range(120):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if not cruiser.velocity.is_equal_approx(Vector3(0.0, 0.0, -300.0)):
		print("FAIL _test_cruise_holds_velocity_in_strong_gravity: velocity drifted to %s" % cruiser.velocity)
		result = 1
	# Z (dorsal thrust) changes it; the lock then holds the new velocity.
	Input.action_press("move_up")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_up")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	if not cruiser.cruise_locked or absf(cruiser.velocity.y - 150.0) > 0.5 or absf(cruiser.velocity.z + 300.0) > 0.5:
		print("FAIL _test_cruise_holds_velocity_in_strong_gravity: after Z velocity %s, cruise %s (expected y ~150, z -300, still locked)" % [cruiser.velocity, cruiser.cruise_locked])
		result = 1
	cruiser.free()
	return result

func _test_diving_through_the_planet_does_not_fling_the_ship() -> int:
	# The planet has no collision. A dive 200 m off the centre, 1000 km
	# inside, at 2 km/s: with 1/r^2 all the way in, the 60 Hz step shoots
	# the ship out at hundreds of km/s. A uniform-sphere pull tops out near
	# 2.1 km/s at the centre.
	var cruiser := _orbiting_cruiser()
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

func _test_speed_does_not_fade_but_spin_does() -> int:
	# Pure inertia on motion; the drag stays on rotation so the mouse does
	# not leave the ship spinning.
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.velocity = Vector3(0.0, 0.0, -100.0)
	cruiser.angular_velocity = Vector3(0.2, 0.0, 0.0)
	for i in range(120):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if absf(cruiser.velocity.length() - 100.0) > 1e-6:
		print("FAIL _test_speed_does_not_fade_but_spin_does: speed %f after 2 s, expected 100" % cruiser.velocity.length())
		result = 1
	if absf(cruiser.angular_velocity.length() - 0.05) > 0.001:
		print("FAIL _test_speed_does_not_fade_but_spin_does: spin %f after 2 s, expected 0.05 (halved every second)" % cruiser.angular_velocity.length())
		result = 1
	cruiser.free()
	return result

func _test_ramp_without_drag_reaches_about_45_km_s_in_10_s() -> int:
	# 150 m/s^2 ramped 1x -> 10x -> 100x over 10 s, nothing to slow it:
	# 150 * (5 * 5.5 + 5 * 55) = 45 375 m/s.
	var cruiser: Node3D = VoidCruiserScript.new()
	Input.action_press("move_forward")
	for i in range(600):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var result := 0
	var speed: float = cruiser.velocity.length()
	if speed < 44500.0 or speed > 46000.0 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_ramp_without_drag_reaches_about_45_km_s_in_10_s: velocity %s (speed %.0f)" % [cruiser.velocity, speed])
		result = 1
	cruiser.free()
	return result

func _test_cruise_holds_instead_of_pushing() -> int:
	var cruiser := _make_cruiser()
	_press(cruiser, "cruise")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if not cruiser.cruise_locked or not cruiser.velocity.is_zero_approx():
		print("FAIL _test_cruise_holds_instead_of_pushing: cruise %s velocity %s" % [cruiser.cruise_locked, cruiser.velocity])
		result = 1
	cruiser.free()
	return result

func _test_one_flight_mode_and_no_orbit_line() -> int:
	var cruiser: Node3D = VoidCruiserScript.new()
	var result := 0
	if "flight_assist" in cruiser or cruiser.has_method("build_orbit_line"):
		print("FAIL _test_one_flight_mode_and_no_orbit_line: flight assist or the orbit line are still there")
		result = 1
	cruiser.free()
	return result

func _test_approach_guide_hidden_without_a_station() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_approach_guide()
	cruiser._process(0.016)
	var result := 0
	var lines := cruiser.get_node_or_null("ApproachGuide") as MeshInstance3D
	if lines == null or not lines.top_level or lines.visible or not (lines.mesh is ArrayMesh):
		print("FAIL _test_approach_guide_hidden_without_a_station: guide missing, not top-level, not a mesh, or shown with no station")
		result = 1
	# The motion marker is gone: the gates are the whole guide.
	if cruiser.get_node_or_null("HeadingMarker") != null:
		print("FAIL _test_approach_guide_hidden_without_a_station: the HeadingMarker is still built")
		result = 1
	cruiser.free()
	return result

func _test_process_feeds_the_velocity_cross() -> int:
	var cruiser := _make_cruiser()
	cruiser.build_proximity_sensors()
	cruiser.build_cockpit()
	cruiser.velocity = Vector3(2.0, 0.0, -50.0)
	cruiser._process(0.016)
	var cross = cruiser.get_node("Cockpit/Hud/VelocityCross")
	var result := 0
	if not cross.components.is_equal_approx(Vector3(2.0, 0.0, 50.0)):
		print("FAIL _test_process_feeds_the_velocity_cross: cross got %s, expected (2, 0, 50)" % cross.components)
		result = 1
	cruiser.free()
	return result

func _test_process_feeds_the_navball() -> int:
	# Planet at the origin, axis +Y, ship on +X: the reference is the
	# identity. Rolled upside down, the top of the ball shows down.
	var cruiser := _make_cruiser()
	cruiser.has_planet = true
	cruiser.planet_center = Vector3.ZERO
	cruiser.planet_axis = Vector3.UP
	cruiser.position = Vector3(1000.0, 0.0, 0.0)
	cruiser.transform.basis = Basis(Vector3.BACK, PI)
	cruiser.build_proximity_sensors()
	cruiser.build_cockpit()
	cruiser._process(0.016)
	var navball = cruiser.get_node("Cockpit/Hud/Navball")
	var result := 0
	var top: Vector3 = navball.attitude() * Vector3(0.0, 1.0, 0.0)
	if not top.is_equal_approx(Vector3(0.0, -1.0, 0.0)) or not navball.attitude().is_equal_approx(cruiser.attitude_matrix()):
		print("FAIL _test_process_feeds_the_navball: the top of the ball shows %s, expected down" % top)
		result = 1
	var loose := _make_cruiser()
	if not loose.attitude_matrix().is_equal_approx(Basis(Vector3.RIGHT, Vector3.UP, Vector3(0.0, 0.0, -1.0))):
		print("FAIL _test_process_feeds_the_navball: without a planet the reference is not the identity")
		result = 1
	loose.free()
	cruiser.free()
	return result

func _test_brake_key_toggles_and_turns_cruise_off() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	_press(cruiser, "cruise")
	_press(cruiser, "brake")
	if not cruiser.brake_engaged or cruiser.cruise_locked:
		print("FAIL _test_brake_key_toggles_and_turns_cruise_off: B gave brake %s, cruise %s" % [cruiser.brake_engaged, cruiser.cruise_locked])
		result = 1
	_press(cruiser, "cruise")
	if cruiser.brake_engaged or not cruiser.cruise_locked:
		print("FAIL _test_brake_key_toggles_and_turns_cruise_off: C after B gave brake %s, cruise %s" % [cruiser.brake_engaged, cruiser.cruise_locked])
		result = 1
	cruiser.cruise_locked = false
	_press(cruiser, "brake")
	_press(cruiser, "brake")
	if cruiser.brake_engaged:
		print("FAIL _test_brake_key_toggles_and_turns_cruise_off: a second B left the brake on")
		result = 1
	cruiser.free()
	return result

func _test_thrust_keys_release_the_brake() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	for action in ["move_forward", "move_backward", "move_left", "move_right", "move_up", "move_down"]:
		_press(cruiser, "brake")
		_press(cruiser, action)
		if cruiser.brake_engaged:
			print("FAIL _test_thrust_keys_release_the_brake: %s left the brake on" % action)
			result = 1
			cruiser.brake_engaged = false
	# Rolling does not.
	_press(cruiser, "brake")
	_press(cruiser, "roll_left")
	if not cruiser.brake_engaged:
		print("FAIL _test_thrust_keys_release_the_brake: rolling let go of the brake")
		result = 1
	cruiser.free()
	return result

func _test_brake_stops_the_ship_at_ten_times_thrust() -> int:
	# Away from any dock the brake stops the ship: 50 m/s^2 base thrust,
	# 500 m/s^2 braking, so 300 m/s takes 0.6 s.
	var cruiser := _make_cruiser()
	var result := 0
	cruiser.velocity = Vector3(300.0, 0.0, 0.0)
	_press(cruiser, "brake")
	for i in range(20):
		cruiser._physics_process(1.0 / 60.0)
	if absf(cruiser.velocity.x - (300.0 - 500.0 / 3.0)) > 0.5:
		print("FAIL _test_brake_stops_the_ship_at_ten_times_thrust: %s after 1/3 s, expected %.1f m/s" % [cruiser.velocity, 300.0 - 500.0 / 3.0])
		result = 1
	for i in range(40):
		cruiser._physics_process(1.0 / 60.0)
	if not cruiser.velocity.is_zero_approx() or not cruiser.brake_engaged:
		print("FAIL _test_brake_stops_the_ship_at_ten_times_thrust: %s after 1 s, brake %s" % [cruiser.velocity, cruiser.brake_engaged])
		result = 1
	cruiser.free()
	return result

func _test_sphere_entry_finds_where_a_move_enters_the_planet() -> int:
	var result := 0
	var centre := Vector3(0.0, -2000.0, 0.0)
	# [from, to, expected fraction]: straight down through the top of a
	# 1000 m sphere; a miss beside it; a move that stops short; already in.
	for c in [[Vector3(0.0, -500.0, 0.0), Vector3(0.0, -1500.0, 0.0), 0.5], [Vector3(1500.0, -500.0, 0.0), Vector3(1500.0, -3500.0, 0.0), -1.0], [Vector3(0.0, 0.0, 0.0), Vector3(0.0, -900.0, 0.0), -1.0], [Vector3(0.0, -1500.0, 0.0), Vector3(0.0, -1600.0, 0.0), 0.0]]:
		var t: float = VoidCruiserPhysics.sphere_entry(c[0], c[1], centre, 1000.0)
		if not is_equal_approx(t, c[2]):
			print("FAIL _test_sphere_entry_finds_where_a_move_enters_the_planet: %s -> %s gave %f, expected %f" % [c[0], c[1], t, c[2]])
			result = 1
	return result

func _test_crashes_on_the_planet_instead_of_passing_through() -> int:
	# 6 km/s straight down from 100 m over a 1000 m planet: in one tick the
	# move would cross the whole surface. The ship stops on it instead (10 m
	# up), still, crashed, and thrust no longer moves it.
	var cruiser := _make_cruiser()
	cruiser.has_planet = true
	cruiser.planet_center = Vector3.ZERO
	cruiser.planet_radius = 1000.0
	cruiser.position = Vector3(0.0, 1100.0, 0.0)
	cruiser.velocity = Vector3(0.0, -6000.0, 0.0)
	var result := 0
	var told := [false]
	cruiser.crashed.connect(func(): told[0] = true)
	cruiser._physics_process(1.0 / 60.0)
	if not cruiser.is_crashed or not told[0] or not cruiser.velocity.is_zero_approx() or absf(cruiser.position.length() - (1000.0 + cruiser.PLANET_CLEARANCE)) > 0.01:
		print("FAIL _test_crashes_on_the_planet_instead_of_passing_through: crashed %s (signal %s), at %s, velocity %s" % [cruiser.is_crashed, told[0], cruiser.position, cruiser.velocity])
		result = 1
	var at := cruiser.position
	Input.action_press("move_forward")
	for i in range(30):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	if not cruiser.position.is_equal_approx(at):
		print("FAIL _test_crashes_on_the_planet_instead_of_passing_through: the wreck moved to %s" % cruiser.position)
		result = 1
	cruiser.free()
	return result

func _test_restart_forgets_the_mouse_moved_on_the_crash_screen() -> int:
	# Mouse moved while the crash screen is up must not spin the ship once it
	# flies again, nor must W held through it resume a half-built ramp.
	var cruiser := _make_cruiser()
	cruiser.has_planet = true
	cruiser.planet_center = Vector3.ZERO
	cruiser.planet_radius = 1000.0
	cruiser.position = Vector3(0.0, 1100.0, 0.0)
	cruiser.velocity = Vector3(0.0, -6000.0, 0.0)
	cruiser._physics_process(1.0 / 60.0)
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(3000.0, 0.0)
	cruiser._unhandled_input(mouse)
	for i in range(10):
		cruiser._physics_process(1.0 / 60.0)
	# GameMode moves the ship away (to a dock) before it flies again.
	cruiser.position = Vector3(0.0, 5000.0, 0.0)
	cruiser.restart_after_crash()
	cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if cruiser.is_crashed or cruiser.angular_velocity.length() > 1e-6:
		print("FAIL _test_restart_forgets_the_mouse_moved_on_the_crash_screen: spinning at %s after restart" % cruiser.angular_velocity)
		result = 1
	cruiser.free()
	return result
