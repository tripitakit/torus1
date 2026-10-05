extends SceneTree

# Boulders as obstacles on the real moon (small scene): their spheres only
# near the one walking or driving, kept with the moon as it moves, and they
# stop the walker and the rover.

const MoonScript = preload("res://scripts/moon.gd")
const MoonRocks = preload("res://scripts/moon_rocks.gd")
const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonPatch = preload("res://scripts/moon_patch.gd")
const MoonWalkerScript = preload("res://scripts/moon_walker.gd")
const MoonRoverScript = preload("res://scripts/moon_rover.gd")
const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

var _world: Node3D
var _moon: Node3D
var _rebase: Node
var _boulder := {}

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
	_rebase = WorldOriginRebaseScript.new()
	_rebase.name = "WorldOriginRebase"
	_world.add_child(_rebase)
	await physics_frame
	_boulder = _big_boulder()
	var failures := 0
	if _boulder.is_empty():
		print("FAIL: no big boulder found to test with")
		failures += 1
	else:
		failures += await _test_boulder_shapes_near_the_walker_only()
		failures += await _test_boulder_shapes_follow_the_moon()
		failures += await _test_walker_stops_at_a_boulder()
		failures += await _test_rover_stops_at_a_boulder()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# A boulder over 2 m on open ground far from the base.
func _big_boulder() -> Dictionary:
	var place := MoonOrbit.direction_of(-20.0, 40.0)
	var face := MoonPatch.face_of(place, -1)
	var plane := MoonPatch.plane_coords(place, face)
	for stone: Dictionary in MoonRocks.stones_in(face, MoonRocks.BOULDER, plane - Vector2.ONE * 2000.0, plane + Vector2.ONE * 2000.0):
		if stone.size > 2.0 and MoonTerrain.crater_height(stone.direction) < 0.5:
			return stone
	return {}

# A point `metres` from the boulder on the ground, and the way to it.
func _beside(metres: float) -> Array:
	var d: Vector3 = _boulder.direction
	var side := d.cross(Vector3.UP).normalized()
	var at := d.rotated(side, metres / MoonOrbit.RADIUS).normalized()
	var point: Vector3 = _moon.to_global(at * (MoonOrbit.RADIUS + MoonTerrain.height(at)))
	var target: Vector3 = _moon.to_global(d * (MoonOrbit.RADIUS + MoonTerrain.height(d)))
	return [point, target - point]

func _centre() -> Vector3:
	var d: Vector3 = _boulder.direction
	return _moon.to_global(d * (MoonOrbit.RADIUS + MoonTerrain.height(d)))

func _shapes() -> Array:
	var body := _moon.get_node_or_null("Rocks/RockBody")
	return [] if body == null else body.find_children("*", "CollisionShape3D", false, false)

func _wait_for_shapes() -> void:
	for i in range(600):
		await physics_frame
		if not _shapes().is_empty():
			return

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame

var _walker: CharacterBody3D

func _test_boulder_shapes_near_the_walker_only() -> int:
	_walker = MoonWalkerScript.new()
	_walker.name = "MoonWalker"
	_world.add_child(_walker)
	_rebase.tracked_node = NodePath("../MoonWalker")
	_walker.controls = {"move": Vector2.ZERO, "jog": false, "jump": false}
	var spot := _beside(12.0)
	_walker.place(spot[0], spot[1])
	await _wait_for_shapes()
	var shapes := _shapes()
	if shapes.is_empty():
		print("FAIL _test_boulder_shapes_near_the_walker_only: no boulder shapes")
		return 1
	for shape: CollisionShape3D in shapes:
		if shape.global_position.distance_to(_walker.global_position) > MoonRocks.COLLIDE_REACH + 5.0:
			print("FAIL _test_boulder_shapes_near_the_walker_only: a shape %.0f m away" % shape.global_position.distance_to(_walker.global_position))
			return 1
	return 0

# Where the physics server has the boulder: the sphere answers a point
# query at the drawn boulder's middle, tick after tick as the moon moves.
func _test_boulder_shapes_follow_the_moon() -> int:
	for i in range(120):
		await physics_frame
		var query := PhysicsPointQueryParameters3D.new()
		query.position = _centre() + _moon.up_at(_centre()) * (_boulder.size * 0.2)
		var hits := _walker.get_world_3d().direct_space_state.intersect_point(query, 4)
		if hits.is_empty():
			print("FAIL _test_boulder_shapes_follow_the_moon: tick %d, no boulder at its drawn place" % i)
			return 1
	return 0

func _test_walker_stops_at_a_boulder() -> int:
	var spot := _beside(8.0)
	_walker.place(spot[0], spot[1])
	await _ticks(2)
	_walker.controls = {"move": Vector2(0.0, 1.0), "jog": true, "jump": false}
	await _ticks(240)
	_walker.controls = {"move": Vector2.ZERO, "jog": false, "jump": false}
	var gap: float = _walker.global_position.distance_to(_centre())
	if gap < _boulder.size * 0.45:
		print("FAIL _test_walker_stops_at_a_boulder: %.2f m from the middle of a %.1f m boulder" % [gap, _boulder.size])
		return 1
	return 0

func _test_rover_stops_at_a_boulder() -> int:
	_world.remove_child(_walker)
	_walker.free()
	var rover: CharacterBody3D = MoonRoverScript.new()
	rover.name = "MoonRover"
	_world.add_child(rover)
	_rebase.tracked_node = NodePath("../MoonRover")
	var spot := _beside(20.0)
	rover.place(spot[0], spot[1])
	rover.controls = {"throttle": 1.0, "steer": 0.0, "handbrake": false}
	await _ticks(360)
	rover.controls = {"throttle": 0.0, "steer": 0.0, "handbrake": true}
	var gap: float = rover.global_position.distance_to(_centre())
	var result := 0
	if gap < _boulder.size * 0.45:
		print("FAIL _test_rover_stops_at_a_boulder: %.2f m from the middle of a %.1f m boulder" % [gap, _boulder.size])
		result = 1
	return result
