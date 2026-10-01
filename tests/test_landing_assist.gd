extends SceneTree

# Below 300 m over the moon: thrust and turn rate ease off, and an idle ship
# levels itself without turning its nose.

const LandingAssist = preload("res://scripts/landing_assist.gd")

func _init():
	var failures := 0
	failures += _test_thrust_factor()
	failures += _test_torque_factor()
	failures += _test_level_rate_rights_the_ship_keeping_the_heading()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_thrust_factor() -> int:
	# 1x from 300 m up; about 2 m/s2 of the base 150 below 20 m; between,
	# straight in the altitude.
	var low := LandingAssist.thrust_factor(10.0) * 150.0
	if LandingAssist.thrust_factor(300.0) != 1.0 or LandingAssist.thrust_factor(5000.0) != 1.0 or absf(low - 2.0) > 0.05 or LandingAssist.thrust_factor(20.0) != LandingAssist.thrust_factor(0.0):
		print("FAIL _test_thrust_factor: %f at 300 m, %f m/s2 at 10 m" % [LandingAssist.thrust_factor(300.0), low])
		return 1
	var mid := LandingAssist.thrust_factor(160.0)
	if absf(mid - lerpf(LandingAssist.THRUST_MIN, 1.0, 0.5)) > 1e-6:
		print("FAIL _test_thrust_factor: %f halfway" % mid)
		return 1
	return 0

func _test_torque_factor() -> int:
	if LandingAssist.torque_factor(400.0) != 1.0 or absf(LandingAssist.torque_factor(0.0) - 0.25) > 1e-6 or LandingAssist.torque_factor(150.0) >= 1.0:
		print("FAIL _test_torque_factor")
		return 1
	return 0

func _test_level_rate_rights_the_ship_keeping_the_heading() -> int:
	# Integrated the way flying_craft.gd turns the ship (pitch about local X,
	# yaw about local Y, roll about local FORWARD), the rate levels the ship
	# and leaves the nose's horizontal heading where it was.
	var up := Vector3(0.2, 1.0, -0.1).normalized()
	var ship := Node3D.new()
	# Start: level, nose some way, then pitched 20 and rolled 15 degrees.
	var east := up.cross(Vector3(0.0, 0.0, 1.0)).normalized()
	var start := Basis(east, up, east.cross(up)).rotated(east, deg_to_rad(20.0))
	start = start.rotated(start.z.normalized(), deg_to_rad(15.0))
	ship.transform.basis = start
	var heading_before := _heading(ship.transform.basis, up)
	var heading := LandingAssist.heading_of(ship.transform.basis, up)
	for tick in range(240):
		var rate: Vector3 = LandingAssist.level_rate(ship.transform.basis, up, heading)
		ship.rotate_object_local(Vector3.RIGHT, rate.x / 60.0)
		ship.rotate_object_local(Vector3.UP, rate.y / 60.0)
		ship.rotate_object_local(Vector3.FORWARD, rate.z / 60.0)
	var tilt: float = rad_to_deg(acos(clampf(ship.transform.basis.y.normalized().dot(up), -1.0, 1.0)))
	var turned: float = rad_to_deg(heading_before.angle_to(_heading(ship.transform.basis, up)))
	ship.free()
	if tilt > 1.0 or turned > 1.0:
		print("FAIL _test_level_rate_rights_the_ship_keeping_the_heading: %.2f degrees off level, nose turned %.2f degrees after 4 s" % [tilt, turned])
		return 1
	return 0

# The nose's direction in the horizontal plane.
func _heading(basis: Basis, up: Vector3) -> Vector3:
	var nose := -basis.z.normalized()
	return (nose - up * nose.dot(up)).normalized()
