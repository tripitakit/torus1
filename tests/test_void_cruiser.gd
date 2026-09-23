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
	failures += _test_forward_hold_time_starts_at_zero()
	failures += _test_forward_hold_time_resets_on_first_press()
	failures += _test_forward_hold_time_accumulates_while_held()
	failures += _test_forward_hold_time_resets_on_release()
	failures += _test_forward_hold_time_resets_on_direction_reversal()
	failures += _test_forward_thrust_ramps_up_velocity_over_time()
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
