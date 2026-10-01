extends SceneTree

# The void-cruiser near the moon, with real physics on a small scene: the
# planet, the moon, the ship and the world origin shift (no station).

const MoonScript = preload("res://scripts/moon.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")
const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

var _failures := 0
var _world: Node3D
var _moon: Node3D
var _ship: CharacterBody3D

func _initialize():
	_world = Node3D.new()
	_world.name = "World"
	root.add_child(_world)
	var system := Node3D.new()
	system.name = "PlanetSystem"
	system.position = Vector3(0.0, -4000.0, -6959600.0)
	_world.add_child(system)
	var planet := Node3D.new()
	planet.name = "Planet"
	system.add_child(planet)
	_moon = MoonScript.new()
	_moon.name = "Moon"
	system.add_child(_moon)
	_ship = VoidCruiserScript.new()
	_ship.name = "VoidCruiser"
	_world.add_child(_ship)
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.name = "WorldOriginRebase"
	rebase.tracked_node = NodePath("../VoidCruiser")
	_world.add_child(rebase)
	await physics_frame
	await physics_frame

	_failures += await _test_attach_and_detach_keep_the_true_velocity()
	_failures += await _test_carried_with_the_moon()
	_failures += await _test_moon_gravity_pulls_down()
	_failures += _test_landing_ok_limits()
	_failures += await _test_soft_level_touch_lands()
	_failures += await _test_landed_ship_stays_put_for_many_ticks()
	_failures += await _test_up_thrust_takes_off()
	_failures += await _test_fast_touch_crashes()
	_failures += await _test_sideways_touch_crashes()
	_failures += await _test_tilted_touch_crashes()
	_failures += await _test_soft_landing_on_a_pad()
	_failures += await _test_hitting_a_sector_bounces()
	_failures += await _test_guide_points_at_the_nearest_pad()
	_failures += await _test_altitude_reads_zero_landed_away_from_the_pads()
	_failures += await _test_tilted_landing_rests_its_lowest_corner_on_the_ground()
	_failures += await _test_idle_ship_levels_itself_low_over_the_moon()
	_failures += await _test_thrust_eases_off_near_the_ground()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# A point `height` above the moon in moon-local direction `direction`.
func _above(direction: Vector3, height: float) -> Vector3:
	return _moon.to_global(direction.normalized() * (MoonOrbit.RADIUS + height))

# The ship at `point`, level (its up the local up), moving with the moon's
# surface plus `extra` (world), in the ring's frame, not attached yet.
func _place(point: Vector3, extra := Vector3.ZERO) -> void:
	var up: Vector3 = _moon.up_at(point)
	var side := up.cross(Vector3(0.0, 0.0, 1.0)).normalized()
	_ship.in_moon_frame = false
	_ship.is_landed = false
	_ship.brake_engaged = false
	_ship.cruise_locked = false
	_ship.angular_velocity = Vector3.ZERO
	_ship.global_transform = Transform3D(Basis(side, up, side.cross(up)), point)
	_ship.velocity = MoonOrbit.to_ring_velocity(Vector3.ZERO, point - _moon.planet_centre(), _moon.axis(), _moon.relative_rate()) + extra

# Waits until the ship has joined the moon's frame (a tick after _place):
# only then is a velocity set by a test relative to the moon.
func _attached() -> void:
	for tick in range(10):
		await physics_frame
		if _ship.in_moon_frame:
			await physics_frame
			return

func _moon_local() -> Vector3:
	return _moon.to_local(_ship.global_position)

func _test_attach_and_detach_keep_the_true_velocity() -> int:
	var direction := Vector3(0.2, 0.9, 0.4)
	_place(_above(direction, 31000.0), -_moon.up_at(_above(direction, 31000.0)) * 400.0)
	var result := 0
	var switches := 0
	var was: bool = _ship.in_moon_frame
	var previous: Vector3 = _ship.ring_velocity()
	var worst := 0.0
	# Position too: each tick's step (from the planet's centre, which the
	# origin shift moves with the ship) matches the true velocity.
	var place: Vector3 = _ship.global_position - _moon.planet_centre()
	var worst_step := 0.0
	# Down past 30 km, then back up past 32 km.
	for tick in range(800):
		if tick == 240:
			_ship.velocity = _moon.up_at(_ship.global_position) * 400.0
		await physics_frame
		var now: Vector3 = _ship.ring_velocity()
		var here: Vector3 = _ship.global_position - _moon.planet_centre()
		if tick != 240 and tick != 241:
			worst = maxf(worst, now.distance_to(previous))
			worst_step = maxf(worst_step, (here - place).distance_to(now / 60.0))
		place = here
		previous = now
		if _ship.in_moon_frame != was:
			switches += 1
			was = _ship.in_moon_frame
	if switches != 2 or _ship.in_moon_frame or worst > 0.1 or worst_step > 0.5:
		print("FAIL _test_attach_and_detach_keep_the_true_velocity: %d frame switches, attached at the end %s, largest jump %.3f m/s, step off by %.2f m" % [switches, _ship.in_moon_frame, worst, worst_step])
		result = 1
	return result

func _test_carried_with_the_moon() -> int:
	_place(_above(Vector3(-0.3, 0.7, 0.5), 10000.0))
	await physics_frame
	_ship.brake_engaged = true
	var start := _moon_local()
	var moon_start: Vector3 = _moon.global_position
	for tick in range(120):
		await physics_frame
	var result := 0
	var drift: float = _moon_local().distance_to(start)
	if not _ship.in_moon_frame or drift > 0.01 or _moon.global_position.distance_to(moon_start) < 3000.0:
		print("FAIL _test_carried_with_the_moon: attached %s, drifted %.4f m, moon moved %.0f m" % [_ship.in_moon_frame, drift, _moon.global_position.distance_to(moon_start)])
		result = 1
	_ship.brake_engaged = false
	return result

func _test_moon_gravity_pulls_down() -> int:
	var point := _above(Vector3(0.5, 0.5, -0.6), 10000.0)
	_place(point)
	await physics_frame
	for tick in range(60):
		await physics_frame
	var up: Vector3 = _moon.up_at(_ship.global_position)
	var down: float = -_ship.velocity.dot(up)
	var across: float = (_ship.velocity + up * down).length()
	var result := 0
	if not _ship.in_moon_frame or down < 0.8 or down > 1.0 or across > 0.05:
		print("FAIL _test_moon_gravity_pulls_down: attached %s, falling %.3f m/s, across %.3f m/s after 1 s" % [_ship.in_moon_frame, down, across])
		result = 1
	return result

var _crashes := 0

func _on_crashed() -> void:
	_crashes += 1

func _test_landing_ok_limits() -> int:
	var up := Vector3(0.0, 1.0, 0.0)
	var level := Vector3(0.0, 1.0, 0.0)
	var tilted_24 := Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(24.0)) * level
	var tilted_26 := Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(26.0)) * level
	var cases := [
		[Vector3(1.9, -4.9, 0.0), tilted_24, true],
		[Vector3(0.0, -5.1, 0.0), level, false],
		[Vector3(2.1, -1.0, 0.0), level, false],
		[Vector3(0.0, -1.0, 0.0), tilted_26, false],
		[Vector3(0.0, -1.0, 1.0), level, true],
	]
	for c in cases:
		if VoidCruiserScript.landing_ok(c[0], up, c[1]) != c[2]:
			print("FAIL _test_landing_ok_limits: velocity %s, ship up %s gave %s" % [c[0], c[1], not c[2]])
			return 1
	return 0

# The ship `height` metres (bottom of the hull) above the ground, moving at
# `velocity` in the moon's frame, level or tilted by `tilt` degrees; waits
# up to 20 s for it to land or crash.
# `velocity`: x across (the ship's side), y up.
func _drop(direction: Vector3, height: float, velocity: Vector2, tilt := 0.0) -> void:
	var point := _above(direction, height + VoidCruiserScript.HALF_HEIGHT)
	if _ship.is_crashed:
		_ship.restart_after_crash()
	_place(point)
	await _attached()
	var up: Vector3 = _moon.up_at(_ship.global_position)
	var level: Basis = _ship.global_transform.basis
	_ship.global_transform.basis = Basis(level.x.normalized(), deg_to_rad(tilt)) * level
	var side: Vector3 = level.x.normalized()
	_ship.velocity = up * velocity.y + side * velocity.x
	if not _ship.crashed.is_connected(_on_crashed):
		_ship.crashed.connect(_on_crashed)
	_crashes = 0
	for tick in range(1200):
		await physics_frame
		if _ship.is_landed or _ship.is_crashed:
			return

func _test_soft_level_touch_lands() -> int:
	var direction := Vector3(0.1, 0.8, -0.6)
	await _drop(direction, 5.0, Vector2(0.0, -1.0))
	var height: float = _moon.altitude(_ship.global_position)
	if not _ship.is_landed or _crashes != 0 or absf(height - VoidCruiserScript.HALF_HEIGHT) > 0.05 or _ship.velocity != Vector3.ZERO:
		print("FAIL _test_soft_level_touch_lands: landed %s, crashes %d, centre %.3f m up, velocity %s" % [_ship.is_landed, _crashes, height, _ship.velocity])
		return 1
	return 0

func _test_landed_ship_stays_put_for_many_ticks() -> int:
	# Ten seconds: the moon carries the ship ~19 km, so the world origin
	# shifts several times under it.
	var start := _moon_local()
	var system: Node3D = _world.get_node("PlanetSystem")
	var system_start := system.position
	for tick in range(600):
		await physics_frame
	var drift: float = _moon_local().distance_to(start)
	if not _ship.is_landed or drift > 0.01 or system.position.distance_to(system_start) < 5000.0:
		print("FAIL _test_landed_ship_stays_put_for_many_ticks: landed %s, drifted %.4f m, world shifted %.0f m" % [_ship.is_landed, drift, system.position.distance_to(system_start)])
		return 1
	return 0

func _test_up_thrust_takes_off() -> int:
	# Near the ground the thrust is eased to about 2 m/s2 (landing_assist):
	# a lift-off is gentle, several seconds to 10 m.
	Input.action_press("move_up")
	for tick in range(300):
		await physics_frame
	Input.action_release("move_up")
	await physics_frame
	var height: float = _moon.altitude(_ship.global_position)
	if _ship.is_landed or height < 10.0:
		print("FAIL _test_up_thrust_takes_off: landed %s, %.1f m up" % [_ship.is_landed, height])
		return 1
	return 0

func _crash_check(test_name: String) -> int:
	var crashed: bool = _ship.is_crashed and _ship.crashed_on_moon and _crashes == 1
	_ship.restart_after_crash()
	if not crashed or _ship.is_landed:
		print("FAIL %s: crashed %s on the moon %s (%d signals), landed %s" % [test_name, _ship.is_crashed, _ship.crashed_on_moon, _crashes, _ship.is_landed])
		return 1
	return 0

func _test_fast_touch_crashes() -> int:
	await _drop(Vector3(-0.4, 0.8, 0.1), 5.0, Vector2(0.0, -8.0))
	return _crash_check("_test_fast_touch_crashes")

func _test_sideways_touch_crashes() -> int:
	await _drop(Vector3(0.3, 0.9, 0.3), 5.0, Vector2(4.0, -1.0))
	return _crash_check("_test_sideways_touch_crashes")

func _test_tilted_touch_crashes() -> int:
	await _drop(Vector3(-0.2, 0.9, -0.4), 5.0, Vector2(0.0, -1.0), 30.0)
	return _crash_check("_test_tilted_touch_crashes")

# A point of the base's tangent plane (x east, z south), `height` above the
# sphere under it.
func _at_base(x: float, z: float, height: float) -> Vector3:
	var r := MoonOrbit.RADIUS
	return _moon.base_transform() * Vector3(x, sqrt(r * r - x * x - z * z) - r + height, z)

func _test_soft_landing_on_a_pad() -> int:
	var pad: Transform3D = _moon.pad_transform(2)
	var point: Vector3 = pad.origin + pad.basis.y.normalized() * (5.0 + VoidCruiserScript.HALF_HEIGHT)
	_place(point)
	await physics_frame
	_ship.velocity = -_moon.up_at(_ship.global_position) * 1.0
	_crashes = 0
	for tick in range(600):
		await physics_frame
		if _ship.is_landed or _ship.is_crashed:
			break
	var above: float = (_ship.global_position - _moon.pad_transform(2).origin).dot(_moon.up_at(_ship.global_position))
	var result := 0
	if not _ship.is_landed or _crashes != 0 or absf(above - VoidCruiserScript.HALF_HEIGHT) > 0.1:
		print("FAIL _test_soft_landing_on_a_pad: landed %s, crashes %d, centre %.3f m over the pad top" % [_ship.is_landed, _crashes, above])
		result = 1
	return result

func _test_hitting_a_sector_bounces() -> int:
	# An outer ring sector spans 230..290 m from the tower, 25..70 degrees,
	# 6 m high: come at its outer wall at 35 degrees, 20 m/s, level, low;
	# the bow 3 m off it, before the moon's pull brings the hull down.
	var out := Vector2.from_angle(deg_to_rad(35.0))
	_place(_at_base(out.x * 308.0, out.y * 308.0, 5.0))
	await _attached()
	var inward: Vector3 = (_at_base(out.x * 250.0, out.y * 250.0, 5.0) - _ship.global_position).normalized()
	_ship.velocity = inward * 20.0
	_crashes = 0
	var bounced := false
	for tick in range(120):
		await physics_frame
		if _ship.velocity.dot(inward) < 0.0:
			bounced = true
			break
	var result := 0
	if not bounced or _ship.is_landed or _ship.is_crashed or _crashes != 0:
		print("FAIL _test_hitting_a_sector_bounces: bounced %s, landed %s, crashed %s" % [bounced, _ship.is_landed, _ship.is_crashed])
		result = 1
	return result

func _test_guide_points_at_the_nearest_pad() -> int:
	# 300 m over pad 5 (hull bottom): the panel names it and reads 300 m, the
	# guide lines show.
	var pad: Transform3D = _moon.pad_transform(5)
	_place(pad.origin + pad.basis.y.normalized() * (300.0 + VoidCruiserScript.HALF_HEIGHT))
	await physics_frame
	_ship.brake_engaged = true
	await process_frame
	await process_frame
	var readout: Dictionary = _ship.moon_readout()
	var guide := _ship.get_node("ApproachGuide") as MeshInstance3D
	var result := 0
	if readout.get("pad", "") != "PAD 5" or readout.get("alt", "") != "ALT 300 m" or not guide.visible:
		print("FAIL _test_guide_points_at_the_nearest_pad: %s / %s, guide shown %s" % [readout.get("pad", ""), readout.get("alt", ""), guide.visible])
		result = 1
	_ship.brake_engaged = false
	return result

func _test_altitude_reads_zero_landed_away_from_the_pads() -> int:
	# 10 km from the base, inside the guide's range: the ground curves away
	# under the pads' plane, the panel must still read the real height.
	var point := _at_base(10000.0, 0.0, 5.0 + VoidCruiserScript.HALF_HEIGHT)
	_place(point)
	await _attached()
	_ship.velocity = -_moon.up_at(_ship.global_position) * 1.0
	for tick in range(600):
		await physics_frame
		if _ship.is_landed or _ship.is_crashed:
			break
	var alt: String = _ship.moon_readout().get("alt", "")
	if not _ship.is_landed or alt != "ALT 0 m":
		print("FAIL _test_altitude_reads_zero_landed_away_from_the_pads: landed %s, crashed %s, panel %s, altitude %.2f" % [_ship.is_landed, _ship.is_crashed, alt, _moon.altitude(_ship.global_position)])
		return 1
	return 0

func _test_tilted_landing_rests_its_lowest_corner_on_the_ground() -> int:
	# 20 degrees nose-down (within the 25 allowed): the hull's lowest corner
	# rests on the ground, not metres into it.
	await _drop(Vector3(0.6, 0.7, -0.3), 12.0, Vector2(0.0, -1.0), 20.0)
	var lowest := INF
	for x in [-7.5, 7.5]:
		for y in [-3.75, 3.75]:
			for z in [-15.0, 15.0]:
				lowest = minf(lowest, _moon.altitude(_ship.global_transform * Vector3(x, y, z)))
	if not _ship.is_landed or lowest < -0.05 or lowest > 0.1:
		print("FAIL _test_tilted_landing_rests_its_lowest_corner_on_the_ground: landed %s, lowest corner %.2f m up" % [_ship.is_landed, lowest])
		return 1
	return 0

const LandingAssist = preload("res://scripts/landing_assist.gd")

func _test_idle_ship_levels_itself_low_over_the_moon() -> int:
	# 100 m up, pitched 20 and rolled 15 degrees, hovering (brake), hands
	# off: within 3 s it is level, its nose's heading unchanged.
	if _ship.is_crashed:
		_ship.restart_after_crash()
	_place(_above(Vector3(-0.5, 0.7, 0.4), 100.0 + VoidCruiserScript.HALF_HEIGHT))
	await _attached()
	var up: Vector3 = _moon.up_at(_ship.global_position)
	var hull: Basis = _ship.global_transform.basis
	hull = hull.rotated(hull.x.normalized(), deg_to_rad(20.0))
	hull = hull.rotated(hull.z.normalized(), deg_to_rad(15.0))
	_ship.global_transform.basis = hull
	_ship.brake_engaged = true
	var heading_before: Vector3 = _moon.global_transform.basis.inverse() * LandingAssist.heading_of(hull, up)
	for tick in range(180):
		await physics_frame
	up = _moon.up_at(_ship.global_position)
	var tilt: float = rad_to_deg(acos(clampf(_ship.global_transform.basis.y.normalized().dot(up), -1.0, 1.0)))
	var heading_after: Vector3 = _moon.global_transform.basis.inverse() * LandingAssist.heading_of(_ship.global_transform.basis, up)
	var turned: float = rad_to_deg(heading_before.angle_to(heading_after))
	_ship.brake_engaged = false
	if tilt > 2.0 or turned > 1.0:
		print("FAIL _test_idle_ship_levels_itself_low_over_the_moon: %.2f degrees off level, nose turned %.2f degrees" % [tilt, turned])
		return 1
	return 0

func _test_thrust_eases_off_near_the_ground() -> int:
	# 50 m up: the thrust scale follows the altitude (2 m/s2 near the floor,
	# 1x from 300 m).
	_place(_above(Vector3(0.4, 0.6, 0.6), 50.0 + VoidCruiserScript.HALF_HEIGHT))
	await _attached()
	_ship.brake_engaged = true
	await physics_frame
	var expected := LandingAssist.thrust_factor(_ship.landing_altitude())
	_ship.brake_engaged = false
	if absf(_ship.thrust_scale - expected) > 0.01 or _ship.thrust_scale > 0.3:
		print("FAIL _test_thrust_eases_off_near_the_ground: scale %.3f at %.1f m, expected %.3f" % [_ship.thrust_scale, _ship.landing_altitude(), expected])
		return 1
	return 0
