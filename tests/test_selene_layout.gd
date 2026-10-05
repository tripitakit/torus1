extends SceneTree

const SeleneLayout = preload("res://scripts/selene_layout.gd")

func _init():
	var failures := 0
	failures += _test_rooms_sizes()
	failures += _test_rooms_do_not_overlap()
	failures += _test_every_centre_room_reached_from_reception()
	failures += _test_routes_cross_walls_only_at_doors()
	failures += _test_routes_clear_of_walls_and_furniture()
	failures += _test_one_seat_per_desk()
	failures += _test_room_at()
	failures += _test_wall_pieces_short()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _room(name: String) -> Dictionary:
	for room in SeleneLayout.rooms():
		if room.name == name:
			return room
	return {}

# The spec's table (width x depth, either way round, and height).
func _test_rooms_sizes() -> int:
	var expected := {"dock": [12.0, 9.6, 4.8], "tube_dock": [2.4, 3.6, 2.4], "tube_centre": [2.4, 3.6, 2.4],
		"reception": [4.8, 4.8, 2.4], "corridor": [2.4, 18.0, 2.4], "side_left": [9.6, 1.8, 2.4], "side_right": [9.6, 1.8, 2.4],
		"main_mission": [20.0, 12.0, 4.8], "office": [6.0, 7.2, 4.2], "medical": [9.6, 7.2, 2.4],
		"quarters_a": [4.8, 4.8, 2.4], "quarters_b": [4.8, 4.8, 2.4], "lounge": [9.6, 9.6, 2.4]}
	var result := 0
	if SeleneLayout.rooms().size() != expected.size():
		print("FAIL _test_rooms_sizes: %d rooms" % SeleneLayout.rooms().size())
		result = 1
	for name: String in expected:
		var room := _room(name)
		var want: Array = expected[name]
		if room.is_empty():
			print("FAIL _test_rooms_sizes: no %s" % name)
			result = 1
			continue
		var size: Vector2 = (room.rect as Rect2).size
		var fits := (is_equal_approx(size.x, want[0]) and is_equal_approx(size.y, want[1])) or (is_equal_approx(size.x, want[1]) and is_equal_approx(size.y, want[0]))
		if not fits or not is_equal_approx(room.height, want[2]):
			print("FAIL _test_rooms_sizes: %s %s h %.1f" % [name, size, room.height])
			result = 1
	return result

func _test_rooms_do_not_overlap() -> int:
	var rooms := SeleneLayout.rooms()
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			if (rooms[i].rect as Rect2).grow(-0.01).intersects((rooms[j].rect as Rect2).grow(-0.01)):
				print("FAIL _test_rooms_do_not_overlap: %s and %s" % [rooms[i].name, rooms[j].name])
				return 1
	return 0

func _test_every_centre_room_reached_from_reception() -> int:
	var reached := {"reception": true}
	var changed := true
	while changed:
		changed = false
		for door in SeleneLayout.doors():
			if reached.has(door.a) != reached.has(door.b):
				reached[door.a] = true
				reached[door.b] = true
				changed = true
	var result := 0
	for room in SeleneLayout.rooms():
		if room.zone == "centre" and not reached.has(room.name):
			print("FAIL _test_every_centre_room_reached_from_reception: %s" % room.name)
			result = 1
		if room.zone == "dock" and reached.has(room.name):
			print("FAIL _test_every_centre_room_reached_from_reception: %s reached on foot" % room.name)
			result = 1
	return result

# Where segment p0-p1 crosses segment q0-q1 (Vector2), or null.
func _crossing(p0: Vector2, p1: Vector2, q0: Vector2, q1: Vector2):
	var r := p1 - p0
	var s := q1 - q0
	var den := r.cross(s)
	if absf(den) < 1e-9:
		return null
	var t := (q0 - p0).cross(s) / den
	var u := (q0 - p0).cross(r) / den
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return null
	return p0 + r * t

func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

func _test_routes_cross_walls_only_at_doors() -> int:
	if SeleneLayout.routes().size() != 10:
		print("FAIL _test_routes_cross_walls_only_at_doors: %d routes" % SeleneLayout.routes().size())
		return 1
	for route in SeleneLayout.routes():
		var points: PackedVector3Array = route.points
		for k in range(points.size() - 1):
			for wall in SeleneLayout.walls():
				var hit = _crossing(_flat(points[k]), _flat(points[k + 1]), wall.from, wall.to)
				if hit != null:
					print("FAIL _test_routes_cross_walls_only_at_doors: %s leg %d through a wall at %s" % [route.department, k, hit])
					return 1
	return 0

func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)

# Distance from point p to an axis-aligned footprint (centre, size on the floor).
func _distance_to_box(p: Vector2, centre: Vector2, half: Vector2) -> float:
	var d := (p - centre).abs() - half
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()

# Walls 0.3 m off the walking line at least (a shoulder), furniture 0.5 m.
func _test_routes_clear_of_walls_and_furniture() -> int:
	for route in SeleneLayout.routes():
		var points: PackedVector3Array = route.points
		for k in range(points.size() - 1):
			var a := _flat(points[k])
			var b := _flat(points[k + 1])
			var steps := ceili(a.distance_to(b) / 0.1)
			for i in range(steps + 1):
				var p := a.lerp(b, float(i) / steps)
				for wall in SeleneLayout.walls():
					if _distance_to_segment(p, wall.from, wall.to) < 0.3:
						print("FAIL _test_routes_clear_of_walls_and_furniture: %s at %s by a wall" % [route.department, p])
						return 1
				for item in SeleneLayout.furniture():
					var where: Transform3D = item.transform
					var size: Vector3 = item.size
					# Turned a quarter: the footprint swaps.
					var across := absf(where.basis.x.z) > 0.5
					var half := Vector2(size.z, size.x) * 0.5 if across else Vector2(size.x, size.z) * 0.5
					if _distance_to_box(p, Vector2(where.origin.x, where.origin.z), half) < 0.5:
						print("FAIL _test_routes_clear_of_walls_and_furniture: %s at %s by a %s" % [route.department, p, item.kind])
						return 1
	return 0

func _test_one_seat_per_desk() -> int:
	var desks := []
	for item in SeleneLayout.furniture():
		if item.kind == "desk":
			desks.append(item)
	var seats := SeleneLayout.seats()
	if desks.size() != 8 or seats.size() != 8:
		print("FAIL _test_one_seat_per_desk: %d desks, %d seats" % [desks.size(), seats.size()])
		return 1
	for k in range(8):
		var seat: Transform3D = seats[k]
		var desk: Transform3D = desks[k].transform
		# Close behind the desk, facing it.
		var to_desk := desk.origin - seat.origin
		if to_desk.length() > 1.2 or to_desk.normalized().dot(-seat.basis.z) < 0.9 or SeleneLayout.room_at(seat.origin) != "main_mission":
			print("FAIL _test_one_seat_per_desk: seat %d at %s, desk %s" % [k, seat.origin, desk.origin])
			return 1
	return 0

func _test_room_at() -> int:
	var cases := {Vector3(0.0, 0.0, 2.0): "reception", Vector3(0.0, 0.0, -10.0): "corridor", Vector3(0.0, 0.0, -25.0): "main_mission",
		SeleneLayout.lift_centre(): "dock", Vector3(500.0, 0.0, 0.0): ""}
	for point: Vector3 in cases:
		if SeleneLayout.room_at(point) != cases[point]:
			print("FAIL _test_room_at: %s in '%s', expected '%s'" % [point, SeleneLayout.room_at(point), cases[point]])
			return 1
	var stops := SeleneLayout.tube_stops()
	if SeleneLayout.room_at((stops.dock as Transform3D).origin) != "tube_dock" or SeleneLayout.room_at((stops.centre as Transform3D).origin) != "tube_centre":
		print("FAIL _test_room_at: tube stops %s" % stops)
		return 1
	return 0

# Long walls in pieces: each lit by its own nearest lights (8 at most).
func _test_wall_pieces_short() -> int:
	for wall in SeleneLayout.walls():
		if (wall.from as Vector2).distance_to(wall.to) > 12.0 + 1e-6:
			print("FAIL _test_wall_pieces_short: %s to %s" % [wall.from, wall.to])
			return 1
	return 0
