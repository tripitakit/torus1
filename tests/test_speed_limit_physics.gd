extends SceneTree

# The speed limit on the real ship, in a small world: the planet (the ring's
# centre and axis) and the void-cruiser, no station: the ring's surface is
# worked out from its radius.

const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")
const SpeedLimit = preload("res://scripts/speed_limit.gd")

var _failures := 0
var _ship: CharacterBody3D

func _initialize():
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var system := Node3D.new()
	system.name = "PlanetSystem"
	system.position = Vector3(0.0, -4000.0, -6959600.0)
	world.add_child(system)
	var planet := Node3D.new()
	planet.name = "Planet"
	system.add_child(planet)
	_ship = VoidCruiserScript.new()
	_ship.name = "VoidCruiser"
	world.add_child(_ship)
	await physics_frame
	await physics_frame

	_failures += await _test_full_thrust_stops_at_the_open_limit()
	_failures += await _test_coming_near_the_ring_brakes_down()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_full_thrust_stops_at_the_open_limit() -> int:
	# 100 km above the ring (the limit there: Torus1's braking curve),
	# nose along the motion just under it, full thrust for 2 s: held at it.
	_ship.global_position = Vector3(0.0, 100000.0, 0.0)
	_ship.global_transform.basis = Basis.looking_at(Vector3.RIGHT, Vector3.UP)
	var here: float = _ship.current_speed_limit()
	_ship.velocity = Vector3.RIGHT * (here - 100.0)
	Input.action_press("move_forward")
	var fastest := 0.0
	for tick in range(120):
		await physics_frame
		fastest = maxf(fastest, _ship.velocity.length())
	Input.action_release("move_forward")
	var limit: float = _ship.speed_limit
	if limit < SpeedLimit.NEAR_LIMIT * 2.0 or fastest > limit + 0.5 or fastest < limit - 30.0:
		print("FAIL _test_full_thrust_stops_at_the_open_limit: limit %.0f, fastest %.1f" % [_ship.speed_limit, fastest])
		return 1
	return 0

func _test_coming_near_the_ring_brakes_down() -> int:
	# 8 km off the ring's surface at 3000 m/s: the computer brakes to 1000
	# (10x the base thrust: under 2 s), showing it meanwhile.
	_ship.global_position = Vector3(0.0, 0.0, 0.0)
	_ship.velocity = Vector3.RIGHT * 3000.0
	await physics_frame
	var braking: bool = _ship.limit_braking
	# Braking: the net acceleration against the motion, at the brake's
	# strength; the engines' share all of it (the pulls here are tiny).
	var net: Vector3 = _ship.accel_net
	var thrust: Vector3 = _ship.accel_thrust
	if net.normalized().dot(-_ship.velocity.normalized()) < 0.999 or absf(net.length() - 1500.0) > 20.0 or thrust.distance_to(net - _ship.accel_external) > 0.001 or _ship.accel_external.length() > 1.0:
		print("FAIL _test_coming_near_the_ring_brakes_down: accelerations net %s, thrust %s, external %s" % [net, thrust, _ship.accel_external])
		return 1
	for tick in range(180):
		await physics_frame
	var speed := _ship.velocity.length()
	if absf(_ship.speed_limit - SpeedLimit.NEAR_LIMIT) > 0.1 or not braking or absf(speed - SpeedLimit.NEAR_LIMIT) > 1.0 or _ship.limit_braking:
		print("FAIL _test_coming_near_the_ring_brakes_down: limit %.0f, braking %s, %.1f m/s after 3 s" % [_ship.speed_limit, braking, speed])
		return 1
	return 0
