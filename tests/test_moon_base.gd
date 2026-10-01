extends SceneTree

# Base Selene's layout (Space 1999's Alpha: rings of low sectors round a
# tower, spokes out to round pads) and its pads on the moon.

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
	_failures += _test_beacon_on_the_tower()
	_failures += _test_rings_of_low_sectors()
	_failures += _test_every_pad_on_a_spoke()
	_failures += _test_pad_zone_clear()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _pieces(kind: String) -> Array:
	return MoonBase.layout().filter(func(piece: Dictionary) -> bool: return piece.kind == kind)

func _named(piece_name: String) -> Dictionary:
	for piece in MoonBase.layout():
		if piece.name == piece_name:
			return piece
	return {}

# Whether `piece`'s footprint covers `point` (base plane, x east, z south),
# `margin` metres inside its edge.
func _covers(piece: Dictionary, point: Vector2, margin: float) -> bool:
	match piece.kind:
		"tower":
			return point.length() < MoonBase.TOWER_RADIUS - margin
		"pad":
			return point.distance_to(piece.centre) < MoonBase.PAD_RADIUS - margin
		"sector":
			var r := point.length()
			if r <= piece.inner + margin or r >= piece.outer - margin:
				return false
			var angle := fposmod(rad_to_deg(atan2(point.y, point.x)) - piece.start, 360.0)
			var slack := rad_to_deg(margin / r)
			return angle > slack and angle < piece.end - piece.start - slack
		_:
			# A box turned to `angle` (its length along that direction).
			var local: Vector2 = (point - piece.centre).rotated(-piece.angle)
			return absf(local.x) < piece.size.x * 0.5 - margin and absf(local.y) < piece.size.z * 0.5 - margin

# A circle round the piece: {centre, radius}.
func _reach(piece: Dictionary) -> Dictionary:
	match piece.kind:
		"tower":
			return {"centre": Vector2.ZERO, "radius": MoonBase.TOWER_RADIUS}
		"pad":
			return {"centre": piece.centre, "radius": MoonBase.PAD_RADIUS}
		"sector":
			return {"centre": Vector2.ZERO, "radius": piece.outer}
		_:
			return {"centre": piece.centre, "radius": Vector2(piece.size.x, piece.size.z).length() * 0.5}

# A piece's points every `step` metres, `margin` inside its edge.
func _samples(piece: Dictionary, step: float, margin: float) -> PackedVector2Array:
	var reach := _reach(piece)
	var points := PackedVector2Array()
	if piece.kind == "sector":
		# Round and out, not over the whole square round the base.
		var r: float = piece.inner + step * 0.5
		while r < piece.outer:
			var a: float = deg_to_rad(piece.start) + step * 0.5 / r
			while a < deg_to_rad(piece.end):
				var point := Vector2.from_angle(a) * r
				if _covers(piece, point, margin):
					points.append(point)
				a += step / r
			r += step
		return points
	var x: float = reach.centre.x - reach.radius
	while x <= reach.centre.x + reach.radius:
		var z: float = reach.centre.y - reach.radius
		while z <= reach.centre.y + reach.radius:
			var point := Vector2(x, z)
			if _covers(piece, point, margin):
				points.append(point)
			z += step
		x += step
	return points

func _test_six_numbered_pads() -> int:
	var pads := _pieces("pad")
	var numbers := []
	for pad in pads:
		numbers.append(pad.number)
	numbers.sort()
	var centres := MoonBase.pad_centres()
	if numbers != [1, 2, 3, 4, 5, 6] or centres.size() != 6 or _pieces("tower").size() != 1 or _pieces("hangar").size() != 6:
		print("FAIL _test_six_numbered_pads: pads %s, %d tower, %d hangars" % [numbers, _pieces("tower").size(), _pieces("hangar").size()])
		return 1
	for i in range(6):
		for j in range(i + 1, 6):
			if (centres[i] as Vector2).distance_to(centres[j]) < 100.0 - 0.001:
				print("FAIL _test_six_numbered_pads: pads %d and %d %.1f m apart" % [i + 1, j + 1, (centres[i] as Vector2).distance_to(centres[j])])
				return 1
	return 0

func _test_pieces_do_not_overlap() -> int:
	# Pieces may touch the ones they join, never overlap.
	var pieces := MoonBase.layout()
	for i in range(pieces.size()):
		for point in _samples(pieces[i], 3.0, 0.5):
			for j in range(pieces.size()):
				if j == i:
					continue
				var reach := _reach(pieces[j])
				if point.distance_to(reach.centre) > reach.radius + 1.0:
					continue
				if _covers(pieces[j], point, 0.5):
					print("FAIL _test_pieces_do_not_overlap: %s and %s overlap at %s" % [pieces[i].name, pieces[j].name, point])
					return 1
	return 0

func _test_everything_within_1300_m() -> int:
	for piece in MoonBase.layout():
		var reach := _reach(piece)
		if (reach.centre as Vector2).length() + reach.radius > 1300.0:
			print("FAIL _test_everything_within_1300_m: %s reaches past 1300 m" % piece.name)
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
	# physics step, ~32 m at the moon's speed). Every piece solid.
	var base := _moon.get_node_or_null("Base") as StaticBody3D
	if base == null:
		print("FAIL _test_base_body_and_colliders: no static Base under the moon")
		return 1
	var names := []
	for shape in base.find_children("*", "CollisionShape3D", true, false):
		names.append(String(shape.name))
	for piece in MoonBase.layout():
		var found := false
		for shape_name in names:
			if (shape_name as String).begins_with(piece.name + "Collider"):
				found = true
				break
		if not found:
			print("FAIL _test_base_body_and_colliders: %s has no collider" % piece.name)
			return 1
	return 0

func _test_beacon_on_the_tower() -> int:
	# A blinking light over the tower, drawn at any distance, never under a
	# few pixels.
	var beacon := _moon.get_node_or_null("Base/Beacon") as MeshInstance3D
	if beacon == null or beacon.visibility_range_end != 0.0 or beacon.position.y < MoonBase.TOWER_HEIGHT:
		print("FAIL _test_beacon_on_the_tower: missing, range-limited or below the tower top")
		return 1
	return 0

func _test_rings_of_low_sectors() -> int:
	# Many low sectors in rings round the tower, some with domes.
	var sectors := _pieces("sector")
	var rings := {}
	var domes := 0
	for sector in sectors:
		if sector.height > 10.0:
			print("FAIL _test_rings_of_low_sectors: %s is %.0f m tall" % [sector.name, sector.height])
			return 1
		rings[sector.inner] = true
		domes += 1 if sector.dome else 0
	if sectors.size() < 15 or rings.size() < 4 or domes < 8:
		print("FAIL _test_rings_of_low_sectors: %d sectors, %d rings, %d domes" % [sectors.size(), rings.size(), domes])
		return 1
	return 0

func _test_every_pad_on_a_spoke() -> int:
	# A tube from each pad's edge back to a sector.
	for pad in _pieces("pad"):
		var spoke := _named("Spoke%d" % pad.number)
		if spoke.is_empty():
			print("FAIL _test_every_pad_on_a_spoke: pad %d has no spoke" % pad.number)
			return 1
		var along := Vector2.from_angle(spoke.angle)
		var outer: Vector2 = spoke.centre + along * spoke.size.x * 0.5
		var inner: Vector2 = spoke.centre - along * spoke.size.x * 0.5
		var on_sector := false
		for sector in _pieces("sector"):
			if _covers(sector, inner - along * 1.0, 0.0):
				on_sector = true
		if absf(outer.distance_to(pad.centre) - MoonBase.PAD_RADIUS) > 0.5 or not on_sector:
			print("FAIL _test_every_pad_on_a_spoke: pad %d's spoke ends %.1f m from its centre, on a sector %s" % [pad.number, outer.distance_to(pad.centre), on_sector])
			return 1
	return 0

func _test_pad_zone_clear() -> int:
	# Round each pad, room to land: nothing within 40 m but its own spoke,
	# hangar and hangar tube.
	for pad in _pieces("pad"):
		var own := ["Pad%d" % pad.number, "Spoke%d" % pad.number, "Hangar%d" % pad.number, "HangarTube%d" % pad.number]
		for piece in MoonBase.layout():
			if piece.name in own:
				continue
			for point in _samples(piece, 3.0, 0.0):
				if point.distance_to(pad.centre) < MoonBase.PAD_RADIUS + 40.0:
					print("FAIL _test_pad_zone_clear: %s next to pad %d" % [piece.name, pad.number])
					return 1
	return 0
