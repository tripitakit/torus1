extends SceneTree

# The pilot on foot on the real moon, on a small scene: the planet, the moon,
# the walker and the world origin shift.

const MoonScript = preload("res://scripts/moon.gd")
const MoonWalkerScript = preload("res://scripts/moon_walker.gd")
const OnFoot = preload("res://scripts/on_foot.gd")
const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

var _moon: Node3D
var _walker: CharacterBody3D

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
	_moon = MoonScript.new()
	_moon.name = "Moon"
	system.add_child(_moon)
	_walker = MoonWalkerScript.new()
	_walker.name = "MoonWalker"
	world.add_child(_walker)
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.name = "WorldOriginRebase"
	rebase.tracked_node = NodePath("../MoonWalker")
	world.add_child(rebase)
	await physics_frame
	await physics_frame
	var failures := 0
	failures += await _test_stands_as_the_moon_moves()
	failures += await _test_walks_and_jogs()
	failures += await _test_stops_at_a_base_wall()
	failures += await _test_jumps_and_lands()
	failures += _test_patch_follows_the_walker()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _at_base(x: float, z: float) -> Vector3:
	var r: float = MoonScript.ground_radius()
	return _moon.base_transform() * Vector3(x, sqrt(r * r - x * x - z * z) - r, z)

func _in_base(point: Vector3) -> Vector3:
	return _moon.base_transform().affine_inverse() * point

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame

func _still() -> Dictionary:
	return {"move": Vector2.ZERO, "jog": false, "jump": false}

func _test_stands_as_the_moon_moves() -> int:
	var point := _at_base(400.0, 150.0)
	_walker.controls = _still()
	_walker.place(point, _at_base(400.0, 0.0) - point)
	await _ticks(2)
	var start := _in_base(_walker.global_position)
	await _ticks(600)
	var moved := _in_base(_walker.global_position).distance_to(start)
	var height: float = _moon.ground_altitude(_walker.global_position)
	if moved > 0.1 or absf(height) > 0.05:
		print("FAIL _test_stands_as_the_moon_moves: moved %.3f m, %.3f m over the ground" % [moved, height])
		return 1
	return 0

func _test_walks_and_jogs() -> int:
	var point := _at_base(400.0, 150.0)
	_walker.place(point, _at_base(400.0, 0.0) - point)
	await _ticks(2)
	var start := _in_base(_walker.global_position)
	_walker.controls = {"move": Vector2(0.0, 1.0), "jog": false, "jump": false}
	await _ticks(300)
	var walked := _in_base(_walker.global_position).distance_to(start)
	start = _in_base(_walker.global_position)
	_walker.controls = {"move": Vector2(0.0, 1.0), "jog": true, "jump": false}
	await _ticks(300)
	var jogged := _in_base(_walker.global_position).distance_to(start)
	_walker.controls = _still()
	if absf(walked - 7.5) > 0.3 or absf(jogged - 20.0) > 0.5:
		print("FAIL _test_walks_and_jogs: %.2f m walking, %.2f m jogging in 5 s" % [walked, jogged])
		return 1
	return 0

# An outer ring sector spans 230..290 m from the tower: walk at its wall.
func _test_stops_at_a_base_wall() -> int:
	var out := Vector2.from_angle(deg_to_rad(35.0))
	var point := _at_base(out.x * 296.0, out.y * 296.0)
	_walker.place(point, _at_base(out.x * 250.0, out.y * 250.0) - point)
	await _ticks(2)
	_walker.controls = {"move": Vector2(0.0, 1.0), "jog": true, "jump": false}
	await _ticks(300)
	_walker.controls = _still()
	var at := _in_base(_walker.global_position)
	var reach := Vector2(at.x, at.z).length()
	if reach < 290.0 or reach > 291.0:
		print("FAIL _test_stops_at_a_base_wall: %.2f m from the tower (wall at 290)" % reach)
		return 1
	return 0

func _test_jumps_and_lands() -> int:
	var point := _at_base(400.0, 150.0)
	_walker.place(point, _at_base(400.0, 0.0) - point)
	await _ticks(2)
	_walker.controls = {"move": Vector2.ZERO, "jog": false, "jump": true}
	await _ticks(1)
	_walker.controls = _still()
	var air := 1
	for i in range(400):
		await physics_frame
		if not _walker.airborne:
			break
		air += 1
	var expected := OnFoot.air_time(OnFoot.JUMP_MOON, 1.62) * 60.0
	var height: float = _moon.ground_altitude(_walker.global_position)
	if absf(air - expected) > 6.0 or absf(height) > 0.05:
		print("FAIL _test_jumps_and_lands: %d ticks in the air (expected %.0f), %.3f m over the ground" % [air, expected, height])
		return 1
	return 0

func _test_patch_follows_the_walker() -> int:
	var patch := _moon.get_node("Patch")
	var here: Vector3 = _moon.global_transform.affine_inverse() * _walker.global_position
	if not patch.get("_active") or (patch.last_point as Vector3).distance_to(here) > 50.0:
		print("FAIL _test_patch_follows_the_walker: patch active %s" % patch.get("_active"))
		return 1
	return 0
