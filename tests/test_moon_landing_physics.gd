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
	# Down past 30 km, then back up past 32 km.
	for tick in range(800):
		if tick == 240:
			_ship.velocity = _moon.up_at(_ship.global_position) * 400.0
		await physics_frame
		var now: Vector3 = _ship.ring_velocity()
		if tick != 240 and tick != 241:
			worst = maxf(worst, now.distance_to(previous))
		previous = now
		if _ship.in_moon_frame != was:
			switches += 1
			was = _ship.in_moon_frame
	if switches != 2 or _ship.in_moon_frame or worst > 0.1:
		print("FAIL _test_attach_and_detach_keep_the_true_velocity: %d frame switches, attached at the end %s, largest jump %.3f m/s" % [switches, _ship.in_moon_frame, worst])
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
