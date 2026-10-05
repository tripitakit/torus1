extends SceneTree

# The rover's tracks on the regolith: a sample every half metre on the
# ground, none in the air or standing still, a new strip after a jump; on
# the real moon five seconds of driving leave about 75 a side.

const MoonTracks = preload("res://scripts/moon_tracks.gd")
const MoonScript = preload("res://scripts/moon.gd")
const MoonRoverScript = preload("res://scripts/moon_rover.gd")
const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

func _initialize():
	var failures := 0
	failures += _test_wheel_points()
	failures += _test_one_sample_every_half_metre()
	failures += _test_no_samples_in_the_air_or_standing()
	failures += _test_new_strip_after_a_jump()
	failures += await _test_rover_leaves_tracks()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _at(z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, 0.0, -z))

func _test_wheel_points() -> int:
	var points: Array = MoonTracks.wheel_points(_at(0.0))
	if (points[0] as Vector3).distance_to(Vector3(-0.9, 0.0, 0.0)) > 1e-6 or (points[1] as Vector3).distance_to(Vector3(0.9, 0.0, 0.0)) > 1e-6:
		print("FAIL _test_wheel_points: %s" % [points])
		return 1
	return 0

func _test_one_sample_every_half_metre() -> int:
	var recorder := MoonTracks.Recorder.new()
	var samples := 0
	for i in range(601):
		samples += recorder.step(_at(i * 0.01), false, 5.0).size()
	# 6 m: the first point, then one every 0.5 m.
	if samples != 13:
		print("FAIL _test_one_sample_every_half_metre: %d samples over 6 m" % samples)
		return 1
	return 0

func _test_no_samples_in_the_air_or_standing() -> int:
	var recorder := MoonTracks.Recorder.new()
	recorder.step(_at(0.0), false, 5.0)
	var in_air := 0
	for i in range(1, 301):
		in_air += recorder.step(_at(i * 0.01), true, 5.0).size()
	var standing := 0
	for i in range(100):
		standing += recorder.step(_at(3.0), false, 0.1).size()
	if in_air != 0 or standing != 0:
		print("FAIL _test_no_samples_in_the_air_or_standing: %d in the air, %d standing" % [in_air, standing])
		return 1
	return 0

func _test_new_strip_after_a_jump() -> int:
	var recorder := MoonTracks.Recorder.new()
	var first: Array = recorder.step(_at(0.0), false, 5.0)
	recorder.step(_at(1.0), true, 5.0)
	var after: Array = recorder.step(_at(4.0), false, 5.0)
	var next: Array = recorder.step(_at(4.6), false, 5.0)
	if first.is_empty() or not first[0][3] or after.is_empty() or not after[0][3] or next.is_empty() or next[0][3]:
		print("FAIL _test_new_strip_after_a_jump: %s / %s / %s" % [first, after, next])
		return 1
	return 0

func _test_rover_leaves_tracks() -> int:
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
	var moon: Node3D = MoonScript.new()
	moon.name = "Moon"
	system.add_child(moon)
	var rover: CharacterBody3D = MoonRoverScript.new()
	rover.name = "MoonRover"
	world.add_child(rover)
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.name = "WorldOriginRebase"
	rebase.tracked_node = NodePath("../MoonRover")
	world.add_child(rebase)
	await physics_frame
	var r: float = MoonScript.ground_radius()
	var base: Transform3D = moon.base_transform()
	var point: Vector3 = base * Vector3(400.0, sqrt(r * r - 400.0 * 400.0 - 150.0 * 150.0) - r, 150.0)
	rover.place(point, base * Vector3(400.0, 0.0, 0.0) - point)
	await physics_frame
	rover.controls = {"throttle": 1.0, "steer": 0.0, "handbrake": false}
	for i in range(300):
		await physics_frame
	var count: int = moon.get_node("Tracks").sample_count()
	if count < 70 or count > 80:
		print("FAIL _test_rover_leaves_tracks: %d samples a side after 5 s (37.5 m)" % count)
		return 1
	return 0
