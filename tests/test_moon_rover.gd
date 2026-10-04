extends SceneTree

# The moon rover on the real moon, on a small scene: the planet, the moon,
# the rover and the world origin shift (no station, no ship).

const MoonScript = preload("res://scripts/moon.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonRoverScript = preload("res://scripts/moon_rover.gd")
const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

var _failures := 0
var _world: Node3D
var _moon: Node3D
var _rover: CharacterBody3D

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
	_rover = MoonRoverScript.new()
	_rover.name = "MoonRover"
	_world.add_child(_rover)
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.name = "WorldOriginRebase"
	rebase.tracked_node = NodePath("../MoonRover")
	_world.add_child(rebase)
	await physics_frame
	await physics_frame

	_failures += await _test_rover_rests_on_the_ground_as_the_moon_moves()
	_failures += await _test_rover_drives_along_the_ground()
	_failures += await _test_rover_stops_at_a_base_wall()
	_failures += await _test_patch_follows_the_rover()
	_failures += _test_look_comes_back_after_a_pause()
	_failures += _test_lights_toggle()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# A point on the base's flat ground at (x, z) in its frame, `height` up.
func _at_base(x: float, z: float, height: float) -> Vector3:
	var r: float = MoonScript.ground_radius()
	return _moon.base_transform() * Vector3(x, sqrt(r * r - x * x - z * z) - r + height, z)

func _in_base(point: Vector3) -> Vector3:
	return _moon.base_transform().affine_inverse() * point

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame

func _test_rover_rests_on_the_ground_as_the_moon_moves() -> int:
	var point := _at_base(400.0, 150.0, 0.0)
	_rover.controls = {"throttle": 0.0, "steer": 0.0, "handbrake": false}
	_rover.place(point, _at_base(400.0, 0.0, 0.0) - point)
	await _ticks(2)
	var start := _in_base(_rover.global_position)
	await _ticks(600)
	var moved := _in_base(_rover.global_position).distance_to(start)
	var height: float = _moon.ground_altitude(_rover.global_position)
	if moved > 0.1 or absf(height) > 0.05:
		print("FAIL _test_rover_rests_on_the_ground_as_the_moon_moves: moved %.3f m in the base's frame, %.3f m over the ground" % [moved, height])
		return 1
	return 0

func _test_rover_drives_along_the_ground() -> int:
	var point := _at_base(400.0, 150.0, 0.0)
	_rover.place(point, _at_base(400.0, 0.0, 0.0) - point)
	await _ticks(2)
	var start := _in_base(_rover.global_position)
	_rover.controls = {"throttle": 1.0, "steer": 0.0, "handbrake": false}
	await _ticks(300)
	var gone := _in_base(_rover.global_position).distance_to(start)
	var height: float = _moon.ground_altitude(_rover.global_position)
	_rover.controls = {"throttle": 0.0, "steer": 0.0, "handbrake": true}
	await _ticks(200)
	# 5 s at 3 m/s²: 37.5 m.
	if absf(gone - 37.5) > 1.5 or absf(height) > 0.05 or _rover.speed() > 0.01:
		print("FAIL _test_rover_drives_along_the_ground: %.2f m in 5 s, %.3f m over the ground, %.2f m/s after the handbrake" % [gone, height, _rover.speed()])
		return 1
	return 0

# An outer ring sector spans 230..290 m from the tower, 25..70 degrees, 6 m
# high: drive at its outer wall at 35 degrees from 320 m.
func _test_rover_stops_at_a_base_wall() -> int:
	var out := Vector2.from_angle(deg_to_rad(35.0))
	var point := _at_base(out.x * 320.0, out.y * 320.0, 0.0)
	_rover.place(point, _at_base(out.x * 250.0, out.y * 250.0, 0.0) - point)
	await _ticks(2)
	_rover.controls = {"throttle": 1.0, "steer": 0.0, "handbrake": false}
	await _ticks(600)
	var at := _in_base(_rover.global_position)
	var reach := Vector2(at.x, at.z).length()
	_rover.controls = {"throttle": 0.0, "steer": 0.0, "handbrake": true}
	await _ticks(60)
	if reach < 290.0 or reach > 294.0:
		print("FAIL _test_rover_stops_at_a_base_wall: %.2f m from the tower (wall at 290)" % reach)
		return 1
	return 0

func _test_patch_follows_the_rover() -> int:
	var patch := _moon.get_node("Patch")
	if not patch.get("_active"):
		print("FAIL _test_patch_follows_the_rover: the moon's patch is not following anything")
		return 1
	return 0

func _test_look_comes_back_after_a_pause() -> int:
	var look := Vector2(deg_to_rad(90.0), deg_to_rad(30.0))
	var held: Vector2 = MoonRoverScript.look_after(look, 1.0, 0.1)
	var back := look
	for i in range(30):
		back = MoonRoverScript.look_after(back, 2.0, 1.0 / 60.0)
	if held != look or back.length() > 1e-6:
		print("FAIL _test_look_comes_back_after_a_pause: held %s, back %s" % [held, back])
		return 1
	return 0

func _test_lights_toggle() -> int:
	var light := _rover.get_node("HeadlightL") as Light3D
	var on_at_start := light.visible
	var event := InputEventAction.new()
	event.action = "lights"
	event.pressed = true
	_rover._unhandled_input(event)
	var off: bool = not light.visible and not _rover.lights_on
	_rover._unhandled_input(event)
	if not on_at_start or not off or not light.visible:
		print("FAIL _test_lights_toggle: on %s, off after L %s, on again %s" % [on_at_start, off, light.visible])
		return 1
	return 0
