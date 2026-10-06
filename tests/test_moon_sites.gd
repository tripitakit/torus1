extends SceneTree

# The far-side outposts on the moon: the UltraTelescope in Mare Moscoviense
# and Nuclear Waste Disposal Area 2 in Tsiolkovskiy: where, the flat ground,
# no stones, Area 2's silos and laser fence; on the real moon (small scene)
# their bodies, pads, hatches, and the fence stopping the walker.

const MoonScript = preload("res://scripts/moon.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonRocks = preload("res://scripts/moon_rocks.gd")
const MoonSites = preload("res://scripts/moon_sites.gd")
const MoonWalkerScript = preload("res://scripts/moon_walker.gd")
const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

var _world: Node3D
var _moon: Node3D
var _rebase: Node

func _initialize():
	var failures := 0
	failures += _test_far_side_and_apart()
	failures += _test_flat_ground()
	failures += _test_no_stones()
	failures += _test_silos()
	failures += _test_cross_area()
	failures += _test_fence_posts()
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
	failures += _test_bodies_pads_and_hatches()
	failures += await _test_bodies_follow_the_moon()
	failures += await _test_walker_stopped_by_the_fence()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _dir(name: String) -> Vector3:
	return MoonSites.direction(name)

# Away from the planet (the moon's -X faces it) and far from each other.
func _test_far_side_and_apart() -> int:
	var apart := MoonOrbit.RADIUS * acos(_dir("telescope").dot(_dir("area2")))
	if _dir("telescope").x < 0.3 or _dir("area2").x < 0.3 or apart < 100000.0:
		print("FAIL _test_far_side_and_apart: %s %s, %.0f km apart" % [_dir("telescope"), _dir("area2"), apart / 1000.0])
		return 1
	return 0

# A point `metres` from a site along the surface.
func _off(name: String, metres: float, bearing: float) -> Vector3:
	var d := _dir(name)
	var side := d.cross(Vector3.UP).normalized().rotated(d, bearing)
	return d.rotated(side, metres / MoonOrbit.RADIUS).normalized()

func _test_flat_ground() -> int:
	for name in ["telescope", "area2"]:
		var flat: float = MoonSites.SITES[name].flat
		var h := MoonTerrain.height(_dir(name))
		for bearing in [0.0, 1.0, 2.5, 4.0]:
			var there := MoonTerrain.height(_off(name, flat * 0.95, bearing))
			if not is_equal_approx(there, h) or not is_equal_approx(h, MoonSites.ground_height(name)):
				print("FAIL _test_flat_ground: %s %.2f vs %.2f" % [name, there, h])
				return 1
	return 0

func _test_no_stones() -> int:
	for name in ["telescope", "area2"]:
		for metres in [0.0, 150.0, 300.0]:
			if MoonRocks.density(_off(name, metres, 0.7)) != 0.0:
				print("FAIL _test_no_stones: %s at %.0f m" % [name, metres])
				return 1
	return 0

# 35 silo caps: 12 in the west arm, 12 south, 7 north, 4 east (x east, z
# south in the site's frame).
func _test_silos() -> int:
	var arms := {"W": 0, "S": 0, "N": 0, "E": 0}
	for p: Vector2 in MoonSites.silos():
		if p.x < -20.0:
			arms.W += 1
		elif p.x > 20.0:
			arms.E += 1
		elif p.y > 20.0:
			arms.S += 1
		elif p.y < -20.0:
			arms.N += 1
	if MoonSites.silos().size() != 35 or arms.W != 12 or arms.S != 12 or arms.N != 7 or arms.E != 4:
		print("FAIL _test_silos: %d caps, %s" % [MoonSites.silos().size(), arms])
		return 1
	return 0

# About two football fields.
func _test_cross_area() -> int:
	var area := MoonSites.cross_area()
	if area < 14000.0 or area > 16000.0:
		print("FAIL _test_cross_area: %.0f m2" % area)
		return 1
	return 0

# Posts all round the cross, no more than 10 m apart but at the gate.
func _test_fence_posts() -> int:
	var posts := MoonSites.fence_posts()
	var gaps := 0
	for k in range(posts.size()):
		var gap := (posts[k] as Vector2).distance_to(posts[(k + 1) % posts.size()])
		if gap > 10.01:
			gaps += 1
			if gap > MoonSites.GATE + 0.01:
				print("FAIL _test_fence_posts: %.1f m between posts %d and %d" % [gap, k, k + 1])
				return 1
	if posts.size() < 80 or gaps != 1:
		print("FAIL _test_fence_posts: %d posts, %d gates" % [posts.size(), gaps])
		return 1
	return 0

func _test_bodies_pads_and_hatches() -> int:
	var result := 0
	for name in ["telescope", "area2"]:
		var body := _moon.get_node_or_null("Sites/" + MoonSites.node_name(name)) as StaticBody3D
		var site: Transform3D = _moon.site_transform(name)
		var hatch: Transform3D = _moon.hatch_transform(name)
		if body == null or body.get_child_count() < 5 or hatch.origin.distance_to(site.origin) > 150.0:
			print("FAIL _test_bodies_pads_and_hatches: %s body %s, hatch %.0f m off" % [name, body, hatch.origin.distance_to(site.origin)])
			result = 1
	for pad in [[7, "telescope"], [8, "area2"]]:
		var at: Transform3D = _moon.pad_transform(pad[0])
		var site: Transform3D = _moon.site_transform(pad[1])
		var up: Vector3 = _moon.up_at(at.origin)
		var height: float = _moon.altitude(at.origin)
		if at.origin.distance_to(site.origin) > 200.0 or at.basis.y.normalized().dot(up) < 0.999 or absf(height - 2.0) > 0.2:
			print("FAIL _test_bodies_pads_and_hatches: pad %d %.0f m from its site, %.2f m up" % [pad[0], at.origin.distance_to(site.origin), height])
			result = 1
	return result

# The physics bodies move with the moon on the same tick (as the base's).
func _test_bodies_follow_the_moon() -> int:
	for i in range(5):
		_moon.advance(1.0 / 60.0)
	var body := _moon.get_node("Sites/" + MoonSites.node_name("area2")) as StaticBody3D
	var state: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	if state.origin.distance_to(body.global_transform.origin) > 0.01:
		print("FAIL _test_bodies_follow_the_moon: body %.3f m behind" % state.origin.distance_to(body.global_transform.origin))
		return 1
	return 0

# From outside the fence, walking at it (away from the gate): stopped.
func _test_walker_stopped_by_the_fence() -> int:
	var walker: CharacterBody3D = MoonWalkerScript.new()
	walker.name = "MoonWalker"
	_world.add_child(walker)
	_rebase.tracked_node = NodePath("../MoonWalker")
	var site: Transform3D = _moon.site_transform("area2")
	# The south arm's west edge (fence at x = -23), from 8 m outside.
	var start: Vector3 = site * MoonSites.ground_point(Vector2(-31.0, 60.0), MoonSites.ground_height("area2"))
	var inside: Vector3 = site * MoonSites.ground_point(Vector2(-10.0, 60.0), MoonSites.ground_height("area2"))
	walker.controls = {"move": Vector2.ZERO, "jog": false, "jump": false}
	walker.place(start, inside - start)
	await physics_frame
	await physics_frame
	walker.controls = {"move": Vector2(0.0, 1.0), "jog": true, "jump": false}
	for i in range(240):
		await physics_frame
	var local: Vector3 = _moon.site_transform("area2").affine_inverse() * walker.global_position
	walker.free()
	if local.x > -23.0:
		print("FAIL _test_walker_stopped_by_the_fence: through to x %.1f" % local.x)
		return 1
	return 0
