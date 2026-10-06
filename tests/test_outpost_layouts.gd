extends SceneTree

# The far-side outposts' plans (UltraTelescope, Area 2's monitoring depot):
# an airlock with the hatch to the surface and one room beyond, Alpha-style.

const TelescopeLayout = preload("res://scripts/telescope_layout.gd")
const DepotLayout = preload("res://scripts/depot_layout.gd")
const AlphaPlan = preload("res://scripts/alpha_plan.gd")

func _init():
	var failures := 0
	for layout in [TelescopeLayout, DepotLayout]:
		failures += _test_rooms(layout)
		failures += _test_room_reached_from_the_airlock(layout)
		failures += _test_corners_closed(layout)
		failures += _test_hatch_and_spawn(layout)
		failures += _test_furniture_inside(layout)
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _size_of(layout, name: String) -> Vector3:
	for room in layout.rooms():
		if room.name == name:
			return Vector3((room.rect as Rect2).size.x, room.height, (room.rect as Rect2).size.y)
	return Vector3.ZERO

func _test_rooms(layout) -> int:
	var expected := {"airlock": Vector3(4.8, 3.0, 4.8), "control": Vector3(12.0, 4.2, 9.6)} if layout == TelescopeLayout else {"airlock": Vector3(4.8, 3.0, 4.8), "monitor": Vector3(12.0, 4.2, 12.0)}
	if layout.rooms().size() != 2:
		print("FAIL _test_rooms: %d rooms" % layout.rooms().size())
		return 1
	for name: String in expected:
		if not _size_of(layout, name).is_equal_approx(expected[name]):
			print("FAIL _test_rooms: %s is %s" % [name, _size_of(layout, name)])
			return 1
	if (layout.window_view() as Dictionary).is_empty() or _size_of(layout, layout.window_view().room) == Vector3.ZERO:
		print("FAIL _test_rooms: no window")
		return 1
	return 0

func _test_room_reached_from_the_airlock(layout) -> int:
	for door in layout.doors():
		if door.kind != "hatch" and ((door.a == "airlock" and door.b != "airlock") or door.b == "airlock"):
			return 0
	print("FAIL _test_room_reached_from_the_airlock")
	return 1

func _covered(layout, p: Vector2) -> bool:
	for wall in layout.walls():
		var a: Vector2 = wall.from
		var b: Vector2 = wall.to
		var along := (b - a).normalized()
		var t := (p - a).dot(along)
		var off := absf((p - a).cross(along))
		if off <= AlphaPlan.WALL_THICK * 0.5 + 1e-4 and t >= -1e-4 and t <= a.distance_to(b) + 1e-4:
			return true
	return false

func _test_corners_closed(layout) -> int:
	var half := AlphaPlan.WALL_THICK * 0.5
	for room in layout.rooms():
		var r: Rect2 = room.rect
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			for dx in [-half, 0.0, half]:
				for dz in [-half, 0.0, half]:
					if not _covered(layout, corner + Vector2(dx, dz)):
						print("FAIL _test_corners_closed: %s corner %s" % [room.name, corner])
						return 1
	return 0

# The hatch to the surface in the airlock's outer wall, the pilot arriving
# just inside it.
func _test_hatch_and_spawn(layout) -> int:
	var hatch: Transform3D = layout.hatch()
	var spawn: Transform3D = layout.spawn()
	var hatches := 0
	for door in layout.doors():
		if door.kind == "hatch":
			hatches += 1
			if door.b != "outside" or door.a != "airlock" or not (door.centre as Vector3).is_equal_approx(hatch.origin):
				print("FAIL _test_hatch_and_spawn: %s" % door)
				return 1
	var inward := -hatch.basis.z
	if hatches != 1 or layout.room_at(spawn.origin) != "airlock" or spawn.origin.distance_to(hatch.origin) > 2.4 or (spawn.origin - hatch.origin).dot(inward) <= 0.5 or layout.room_at(hatch.origin + inward * 0.5) != "airlock":
		print("FAIL _test_hatch_and_spawn: hatch %s, spawn %s" % [hatch.origin, spawn.origin])
		return 1
	return 0

func _test_furniture_inside(layout) -> int:
	for item in layout.furniture():
		var where: Transform3D = item.transform
		if layout.room_at(where.origin) == "":
			print("FAIL _test_furniture_inside: %s at %s" % [item.kind, where.origin])
			return 1
	return 0
