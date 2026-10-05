extends SceneTree

# Stones and boulders on the moon: the same stones in the same cells, more
# on crater rims, none at Base Selene, sizes in their class's range.

const MoonRocks = preload("res://scripts/moon_rocks.gd")
const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonPatch = preload("res://scripts/moon_patch.gd")

func _initialize():
	MoonTerrain.load_heights()
	var failures := 0
	failures += _test_same_cell_same_stones()
	failures += _test_denser_on_crater_rims()
	failures += _test_none_at_selene()
	failures += _test_sizes_in_range()
	failures += _test_drawn_radius_on_the_lattice()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# A square `half` metres each way round `direction` on its face's plane.
func _area(direction: Vector3, half: float) -> Array:
	var face := MoonPatch.face_of(direction, -1)
	var plane := MoonPatch.plane_coords(direction, face)
	return [face, plane - Vector2.ONE * half, plane + Vector2.ONE * half]

func _far_place() -> Vector3:
	return MoonOrbit.direction_of(-20.0, 40.0)

func _test_same_cell_same_stones() -> int:
	var area := _area(_far_place(), 100.0)
	var first: Array = MoonRocks.stones_in(area[0], MoonRocks.ROCK, area[1], area[2])
	var again: Array = MoonRocks.stones_in(area[0], MoonRocks.ROCK, area[1], area[2])
	if first.is_empty() or first.size() != again.size():
		print("FAIL _test_same_cell_same_stones: %d then %d stones" % [first.size(), again.size()])
		return 1
	for i in range(first.size()):
		if (first[i].direction as Vector3).distance_to(again[i].direction) > 1e-12 or first[i].size != again[i].size:
			print("FAIL _test_same_cell_same_stones: stone %d moved" % i)
			return 1
	return 0

func _test_denser_on_crater_rims() -> int:
	var crater: Dictionary = MoonTerrain.find_crater(true, _far_place())
	var centre: Vector3 = crater.centre
	var side := centre.cross(Vector3.UP).normalized()
	var rim := centre.rotated(side, crater.radius / MoonOrbit.RADIUS).normalized()
	var flat := Vector3.ZERO
	for k in range(200):
		var probe := _far_place().rotated(Vector3.UP, k * 0.0004).normalized()
		if absf(MoonTerrain.crater_height(probe)) < 0.01:
			flat = probe
			break
	var on_rim: float = MoonRocks.density(rim)
	var on_flat: float = MoonRocks.density(flat)
	if flat == Vector3.ZERO or on_rim < 2.0 * on_flat:
		print("FAIL _test_denser_on_crater_rims: rim %.2f, flat %.2f" % [on_rim, on_flat])
		return 1
	return 0

func _test_none_at_selene() -> int:
	var base := MoonOrbit.base_direction()
	var reach := 700.0
	for kind in [MoonRocks.PEBBLE, MoonRocks.ROCK, MoonRocks.BOULDER]:
		var half := 300.0 if kind == MoonRocks.PEBBLE else 650.0
		var area := _area(base, half)
		for stone: Dictionary in MoonRocks.stones_in(area[0], kind, area[1], area[2]):
			var along := MoonOrbit.RADIUS * acos(clampf((stone.direction as Vector3).dot(base), -1.0, 1.0))
			if along < reach:
				print("FAIL _test_none_at_selene: a stone %.0f m from the base" % along)
				return 1
	return 0

func _test_sizes_in_range() -> int:
	var area := _area(_far_place(), 400.0)
	for kind in [MoonRocks.ROCK, MoonRocks.BOULDER]:
		var cls: Dictionary = MoonRocks.CLASSES[kind]
		for stone: Dictionary in MoonRocks.stones_in(area[0], kind, area[1], area[2]):
			if stone.size < cls.low - 1e-9 or stone.size > cls.high + 1e-9:
				print("FAIL _test_sizes_in_range: class %d size %.2f" % [kind, stone.size])
				return 1
	return 0

# The ground as the patch's finest ring draws it: at a lattice point the
# point's own height, halfway along a lattice edge the mean of its ends.
func _test_drawn_radius_on_the_lattice() -> int:
	var face := MoonPatch.face_of(_far_place(), -1)
	var plane := MoonPatch.plane_coords(_far_place(), face)
	var i := floori(plane.x / 8.0)
	var j := floori(plane.y / 8.0)
	var a := MoonPatch.plane_direction(face, Vector2(i, j) * 8.0)
	var b := MoonPatch.plane_direction(face, Vector2(i + 1, j) * 8.0)
	var mid := MoonPatch.plane_direction(face, Vector2(i + 0.5, j) * 8.0)
	var ra := MoonOrbit.RADIUS + MoonTerrain.height(a)
	var rb := MoonOrbit.RADIUS + MoonTerrain.height(b)
	var at_a: float = MoonPatch.drawn_radius(face, a)
	var at_mid: float = MoonPatch.drawn_radius(face, mid)
	if absf(at_a - ra) > 1e-6 or absf(at_mid - (ra + rb) * 0.5) > 1e-4:
		print("FAIL _test_drawn_radius_on_the_lattice: %.4f vs %.4f, %.4f vs %.4f" % [at_a, ra, at_mid, (ra + rb) * 0.5])
		return 1
	return 0
