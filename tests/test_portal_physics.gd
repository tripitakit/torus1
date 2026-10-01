extends SceneTree

# The jump between the portals, with real physics on a small scene: the
# planet, the moon (with its portal), the earth portal, the ship and the
# world origin shift.

const MoonScript = preload("res://scripts/moon.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const PortalScript = preload("res://scripts/portal.gd")
const PortalRules = preload("res://scripts/portal_rules.gd")
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")
const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

var _failures := 0
var _moon: Node3D
var _earth: Node3D
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
	_moon = MoonScript.new()
	_moon.name = "Moon"
	system.add_child(_moon)
	_earth = PortalScript.new()
	_earth.name = "EarthPortal"
	_earth.place_on_ring = true
	system.add_child(_earth)
	_ship = VoidCruiserScript.new()
	_ship.name = "VoidCruiser"
	world.add_child(_ship)
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.name = "WorldOriginRebase"
	rebase.tracked_node = NodePath("../VoidCruiser")
	world.add_child(rebase)
	await physics_frame
	await physics_frame

	_failures += _test_portals_in_place()
	_failures += _test_gate_readout()
	_failures += await _test_earth_to_moon()
	_failures += await _test_moon_to_earth()
	_failures += await _test_too_fast_crashes()
	_failures += await _test_hitting_the_frame_crashes()
	_failures += await _test_from_behind_no_jump()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _lunar() -> Node3D:
	return _moon.get_node("Portal")

# The ship `ahead` metres out of `portal`'s active side, `side` metres
# along its Y, nose into it, moving in at `speed` (relative to the portal).
func _aim(portal: Node3D, ahead: float, side: float, speed: float, moon_frame: bool) -> void:
	var at: Transform3D = portal.active_transform()
	var inward := -at.basis.z.normalized()
	var up := at.basis.y.normalized()
	_ship.restart_after_crash()
	_ship.brake_engaged = false
	_ship.cruise_locked = false
	_ship.in_moon_frame = moon_frame
	_ship.global_transform = Transform3D(Basis.looking_at(inward, up), at.origin - inward * ahead + up * side)
	_ship.velocity = inward * speed

# Ticks until the ship starts its transit (or `limit` ticks pass).
func _until_transit(limit: int) -> bool:
	for tick in range(limit):
		await physics_frame
		if _ship.in_transit:
			return true
	return false

# Ticks until the transit ends; the ship's position while in it must hold.
func _through_transit() -> bool:
	var held := _ship.global_position
	var tunnel := _ship.get_node("SubspaceTunnel") as Node3D
	if not tunnel.visible:
		print("  no tunnel at the start of the transit")
		return false
	for tick in range(roundi(PortalRules.TRANSIT_TIME * 60.0) + 30):
		await physics_frame
		if not _ship.in_transit:
			if tunnel.visible:
				print("  the tunnel stayed after the transit")
				return false
			return true
		if _ship.global_position.distance_to(held) > 1.0:
			print("  moved %.1f m during the transit" % _ship.global_position.distance_to(held))
			return false
	return false

func _test_portals_in_place() -> int:
	var site: Transform3D = _moon.base_transform()
	var up := site.basis.y.normalized()
	var at: Transform3D = _lunar().active_transform()
	var height := (at.origin - site.origin).length()
	if absf(height - PortalRules.MOON_HEIGHT) > 1.0 or at.basis.z.normalized().dot(-up) < 0.9999:
		print("FAIL _test_portals_in_place: moon portal %.0f m over the base" % height)
		return 1
	if _earth.other_portal() != _lunar() or _lunar().other_portal() != _earth:
		print("FAIL _test_portals_in_place: the portals do not lead to each other")
		return 1
	return 0

func _test_earth_to_moon() -> int:
	_aim(_earth, 150.0, 40.0, 100.0, false)
	if not await _until_transit(200):
		print("FAIL _test_earth_to_moon: no transit")
		return 1
	if not await _through_transit():
		print("FAIL _test_earth_to_moon: the transit did not end, or the ship moved")
		return 1
	var at: Transform3D = _lunar().active_transform()
	var down := at.basis.z.normalized()
	var offset := _ship.global_position - at.origin
	var along := offset.dot(down)
	var across := (offset - down * along).length()
	var speed_down: float = _ship.velocity.dot(down)
	var nose: Vector3 = -_ship.global_transform.basis.z.normalized()
	if not _ship.in_moon_frame or along < 0.0 or along > 60.0 or absf(across - 40.0) > 2.0 or absf(speed_down - 100.0) > 3.0 or nose.dot(down) < 0.99:
		print("FAIL _test_earth_to_moon: in moon frame %s, %.1f m out, %.1f m across, %.1f m/s down, nose %.3f" % [_ship.in_moon_frame, along, across, speed_down, nose.dot(down)])
		return 1
	return 0

func _test_moon_to_earth() -> int:
	_aim(_lunar(), 150.0, 0.0, 80.0, true)
	if not await _until_transit(200):
		print("FAIL _test_moon_to_earth: no transit")
		return 1
	if not await _through_transit():
		print("FAIL _test_moon_to_earth: the transit did not end, or the ship moved")
		return 1
	var at: Transform3D = _earth.active_transform()
	var out := at.basis.z.normalized()
	var along := (_ship.global_position - at.origin).dot(out)
	var speed_out: float = _ship.velocity.dot(out)
	if _ship.in_moon_frame or along < 0.0 or along > 60.0 or absf(speed_out - 80.0) > 3.0:
		print("FAIL _test_moon_to_earth: in moon frame %s, %.1f m out, %.1f m/s out" % [_ship.in_moon_frame, along, speed_out])
		return 1
	return 0

func _test_too_fast_crashes() -> int:
	_aim(_earth, 150.0, 0.0, 400.0, false)
	for tick in range(60):
		await physics_frame
		if _ship.is_crashed or _ship.in_transit:
			break
	var result := 0
	if not _ship.is_crashed or _ship.in_transit:
		print("FAIL _test_too_fast_crashes: crashed %s, in transit %s" % [_ship.is_crashed, _ship.in_transit])
		result = 1
	_ship.restart_after_crash()
	return result

func _test_hitting_the_frame_crashes() -> int:
	# Straight at the ring's middle, slowly.
	_aim(_earth, 100.0, PortalRules.APERTURE_RADIUS + PortalRules.FRAME_WIDTH * 0.5, 50.0, false)
	for tick in range(240):
		await physics_frame
		if _ship.is_crashed or _ship.in_transit:
			break
	var result := 0
	if not _ship.is_crashed:
		print("FAIL _test_hitting_the_frame_crashes: no crash (in transit %s)" % _ship.in_transit)
		result = 1
	_ship.restart_after_crash()
	return result

func _test_from_behind_no_jump() -> int:
	# From the back side through the middle: the ship just flies on.
	var at: Transform3D = _earth.active_transform()
	var out := at.basis.z.normalized()
	_ship.restart_after_crash()
	_ship.in_moon_frame = false
	_ship.global_transform = Transform3D(Basis.looking_at(out, at.basis.y), at.origin - out * 150.0)
	_ship.velocity = out * 100.0
	var jumped := await _until_transit(240)
	var along: float = (_ship.global_position - (_earth.active_transform() as Transform3D).origin).dot(out)
	if jumped or along < 50.0:
		print("FAIL _test_from_behind_no_jump: jumped %s, %.1f m past the opening" % [jumped, along])
		return 1
	return 0

func _test_gate_readout() -> int:
	# Near the earth portal: the panel names the moon; far off: nothing.
	_aim(_earth, 2000.0, 0.0, 120.0, false)
	var near: Dictionary = _ship.gate_readout()
	var nearest: Dictionary = _ship.nearest_portal()
	_aim(_earth, 9000.0, 0.0, 120.0, false)
	var far: Dictionary = _ship.gate_readout()
	_ship.velocity = Vector3.ZERO
	if near.is_empty() or near.gate != "GATE > LUNA  2.0 km" or near.approach != "APPROACH 120 m/s  OK" or near.side != "" or not far.is_empty() or nearest.portal != _earth:
		print("FAIL _test_gate_readout: near %s, far %s" % [near, far])
		return 1
	return 0
