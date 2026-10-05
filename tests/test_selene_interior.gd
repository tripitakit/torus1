extends SceneTree

const SeleneInteriorScript = preload("res://scripts/selene_interior.gd")
const SeleneLayout = preload("res://scripts/selene_layout.gd")
const InteriorWalkerScript = preload("res://scripts/interior_walker.gd")

var _base: Node3D
var _walker: CharacterBody3D

func _initialize():
	_base = SeleneInteriorScript.new()
	_base.crew_count = 0
	_base.build()
	root.add_child(_base)
	_walker = InteriorWalkerScript.new()
	_walker.flat = true
	_walker.add_to_group(SeleneInteriorScript.PEOPLE_GROUP)
	_base.add_child(_walker)
	await physics_frame
	var failures := 0
	failures += await _test_spawn_on_the_dock_floor()
	failures += await _test_walker_stops_at_a_wall()
	failures += await _test_door_opens_and_closes()
	failures += await _test_walks_through_a_door()
	failures += await _test_door_stays_open_while_someone_is_in_it()
	failures += await _test_office_wall_opens()
	failures += await _test_walks_up_into_the_office()
	failures += _test_tube_goes_to_the_other_stop()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame

func _stand(at: Vector3, facing: Vector3) -> void:
	_walker.place(at + Vector3(0.0, 0.1, 0.0), facing)
	_walker.controls = {"move": Vector2.ZERO, "jog": false, "jump": false}
	await _ticks(20)

func _walk(seconds: float) -> void:
	_walker.controls = {"move": Vector2(0.0, 1.0), "jog": false, "jump": false}
	await _ticks(roundi(seconds * 60.0))
	_walker.controls = {"move": Vector2.ZERO, "jog": false, "jump": false}

# The door between `a` and `b`.
func _door(a: String, b: String) -> Node3D:
	var doors := SeleneLayout.doors()
	for k in range(doors.size()):
		if (doors[k].a == a and doors[k].b == b) or (doors[k].a == b and doors[k].b == a):
			return _base.get_node("Doors/Door_%d" % k) as Node3D
	return null

func _test_spawn_on_the_dock_floor() -> int:
	var spawn: Transform3D = _base.spawn_transform()
	await _stand(spawn.origin, -spawn.basis.z)
	var at := _walker.position
	if SeleneLayout.room_at(at) != "dock" or absf(at.y) > 0.05 or not _base.near_lift(at) or _base.room_name(at) != "PAD 1 DOCK":
		print("FAIL _test_spawn_on_the_dock_floor: at %s in '%s', near the lift %s" % [at, _base.room_name(at), _base.near_lift(at)])
		return 1
	return 0

func _test_walker_stops_at_a_wall() -> int:
	await _stand(Vector3(0.0, 0.0, 2.4), Vector3(1.0, 0.0, 0.0))
	await _walk(3.0)
	if _walker.position.x > 2.4 - 0.25 or _walker.position.x < 1.5:
		print("FAIL _test_walker_stops_at_a_wall: at %s" % _walker.position)
		return 1
	return 0

func _test_door_opens_and_closes() -> int:
	var door := _door("reception", "tube_centre")
	await _stand(Vector3(0.0, 0.0, 3.3), Vector3(0.0, 0.0, 1.0))
	await _ticks(60)
	var opened: float = door.open_amount()
	await _stand(Vector3(0.0, 0.0, -4.0), Vector3(0.0, 0.0, 1.0))
	await _ticks(60)
	var closed: float = door.open_amount()
	if opened < 0.99 or closed > 0.01:
		print("FAIL _test_door_opens_and_closes: open %.2f near, %.2f far" % [opened, closed])
		return 1
	return 0

func _test_walks_through_a_door() -> int:
	await _stand(Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, 1.0))
	await _walk(2.5)
	if _walker.position.z < 5.6:
		print("FAIL _test_walks_through_a_door: stopped at %s" % _walker.position)
		return 1
	return 0

# Standing in the doorway the door never closes on the walker.
func _test_door_stays_open_while_someone_is_in_it() -> int:
	var door := _door("side_left", "medical")
	await _stand(Vector3(-10.8, 0.0, -9.0), Vector3(-1.0, 0.0, 0.0))
	var least := 1.0
	for i in range(240):
		await physics_frame
		if i > 40:
			least = minf(least, door.open_amount())
	if least < 0.99:
		print("FAIL _test_door_stays_open_while_someone_is_in_it: down to %.2f" % least)
		return 1
	return 0

func _test_office_wall_opens() -> int:
	var wall := _door("main_mission", "office")
	await _stand(Vector3(8.1, 0.0, -24.0), Vector3(1.0, 0.0, 0.0))
	await _ticks(60)
	if wall == null or wall.open_amount() < 0.99:
		print("FAIL _test_office_wall_opens: %s" % wall)
		return 1
	return 0

func _test_tube_goes_to_the_other_stop() -> int:
	var stops := SeleneLayout.tube_stops()
	if not _base.tube_ride("centre").is_equal_approx(stops.dock) or not _base.tube_ride("dock").is_equal_approx(stops.centre) or _base.tube_stop_at((stops.dock as Transform3D).origin) != "dock" or _base.tube_stop_at(Vector3(0.0, 0.0, -10.0)) != "":
		print("FAIL _test_tube_goes_to_the_other_stop")
		return 1
	return 0

# Up the steps (a ramp underneath) and through the sliding wall.
func _test_walks_up_into_the_office() -> int:
	await _stand(Vector3(7.0, 0.0, -24.0), Vector3(1.0, 0.0, 0.0))
	await _walk(4.0)
	await _ticks(20)
	if _walker.position.x < 11.5 or absf(_walker.position.y - SeleneLayout.OFFICE_FLOOR) > 0.05:
		print("FAIL _test_walks_up_into_the_office: at %s" % _walker.position)
		return 1
	return 0
