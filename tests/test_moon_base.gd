extends SceneTree

# Base Selene's layout and its pads on the moon.

const MoonScript = preload("res://scripts/moon.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonBase = preload("res://scripts/moon_base.gd")

var _failures := 0
var _moon: Node3D

func _initialize():
	var system := Node3D.new()
	system.name = "PlanetSystem"
	system.position = Vector3(0.0, -4000.0, -6959600.0)
	root.add_child(system)
	var planet := Node3D.new()
	planet.name = "Planet"
	system.add_child(planet)
	_moon = MoonScript.new()
	_moon.name = "Moon"
	system.add_child(_moon)
	_moon.set_physics_process(false)
	await process_frame

	_failures += _test_six_numbered_pads()
	_failures += _test_pieces_do_not_overlap()
	_failures += _test_everything_within_1300_m()
	_failures += _test_pads_on_the_sphere_level()
	_failures += _test_base_body_and_colliders()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _pieces(kind: String) -> Array:
	return MoonBase.layout().filter(func(piece: Dictionary) -> bool: return piece.kind == kind)

func _test_six_numbered_pads() -> int:
	var pads := _pieces("pad")
	var numbers := []
	for pad in pads:
		numbers.append(pad.number)
	numbers.sort()
	var centres := MoonBase.pad_centres()
	if numbers != [1, 2, 3, 4, 5, 6] or centres.size() != 6 or _pieces("tower").size() != 1 or _pieces("module").size() != 20 or _pieces("hangar").size() != 6:
		print("FAIL _test_six_numbered_pads: pads %s, %d tower, %d modules, %d hangars" % [numbers, _pieces("tower").size(), _pieces("module").size(), _pieces("hangar").size()])
		return 1
	for i in range(6):
		for j in range(i + 1, 6):
			if (centres[i] as Vector2).distance_to(centres[j]) < 100.0 - 0.001:
				print("FAIL _test_six_numbered_pads: pads %d and %d %.1f m apart" % [i + 1, j + 1, (centres[i] as Vector2).distance_to(centres[j])])
				return 1
	return 0

# Footprint rectangle (x0, z0, x1, z1) of a piece, yaw 0 or 90 degrees.
func _footprint(piece: Dictionary) -> Rect2:
	var size := Vector2(piece.size.x, piece.size.z)
	return Rect2(piece.centre - size * 0.5, size)

func _test_pieces_do_not_overlap() -> int:
	# Tubes may touch the pieces they join, nothing may overlap.
	var pieces := MoonBase.layout()
	for i in range(pieces.size()):
		for j in range(i + 1, pieces.size()):
			var overlap := _footprint(pieces[i]).intersection(_footprint(pieces[j]))
			if overlap.get_area() > 0.01:
				print("FAIL _test_pieces_do_not_overlap: %s and %s overlap by %.1f m2" % [pieces[i].name, pieces[j].name, overlap.get_area()])
				return 1
	return 0

func _test_everything_within_1300_m() -> int:
	for piece in MoonBase.layout():
		var rect := _footprint(piece)
		for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			if (corner as Vector2).length() > 1300.0:
				print("FAIL _test_everything_within_1300_m: %s reaches %.0f m" % [piece.name, (corner as Vector2).length()])
				return 1
	return 0

func _test_pads_on_the_sphere_level() -> int:
	for number in range(1, 7):
		var top: Transform3D = _moon.pad_transform(number)
		var up: Vector3 = _moon.up_at(top.origin)
		if absf(top.origin.distance_to(_moon.centre()) - (MoonOrbit.RADIUS + MoonBase.PAD_HEIGHT)) > 0.01 or top.basis.y.normalized().dot(up) < 0.99999:
			print("FAIL _test_pads_on_the_sphere_level: pad %d top %.3f m from the centre, up off by %f" % [number, top.origin.distance_to(_moon.centre()), top.basis.y.normalized().dot(up)])
			return 1
	return 0

func _test_base_body_and_colliders() -> int:
	# Static: moved at once when the moon moves (a kinematic body lags a
	# physics step, ~32 m at the moon's speed).
	var base := _moon.get_node_or_null("Base") as StaticBody3D
	if base == null:
		print("FAIL _test_base_body_and_colliders: no static Base under the moon")
		return 1
	var shapes := base.find_children("*", "CollisionShape3D", true, false)
	if shapes.size() != MoonBase.layout().size():
		print("FAIL _test_base_body_and_colliders: %d colliders for %d pieces" % [shapes.size(), MoonBase.layout().size()])
		return 1
	return 0
