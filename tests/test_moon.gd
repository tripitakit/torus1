extends SceneTree

# The moon node: its orbit seen from the ring, its tidal lock, its surface
# mesh and its base site.

const MoonScript = preload("res://scripts/moon.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonTerrain = preload("res://scripts/moon_terrain.gd")

var _failures := 0
var _system: Node3D
var _planet: Node3D
var _moon: Node3D

func _initialize():
	_system = Node3D.new()
	_system.name = "PlanetSystem"
	_system.position = Vector3(0.0, -4000.0, -6959600.0)
	root.add_child(_system)
	_planet = Node3D.new()
	_planet.name = "Planet"
	_system.add_child(_planet)
	_moon = MoonScript.new()
	_moon.name = "Moon"
	var start := Time.get_ticks_msec()
	_system.add_child(_moon)
	print("  moon built in %d ms" % (Time.get_ticks_msec() - start))
	_moon.set_physics_process(false)
	await process_frame

	_failures += _test_advances_at_the_relative_rate()
	_failures += _test_base_faces_the_planet()
	_failures += _test_base_transform_on_the_surface()
	_failures += _test_surface_mesh()
	_failures += _test_mesh_radius_meets_the_triangles()
	_failures += _test_altitude()
	_failures += _test_far_version()
	_failures += _test_maps_have_mipmaps()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_advances_at_the_relative_rate() -> int:
	var before: float = _moon.angle
	_moon.advance(10.0)
	var offset: Vector3 = _moon.global_position - _planet.global_position
	var result := 0
	if not is_equal_approx(_moon.angle - before, 10.0 * _moon.relative_rate()) or absf(offset.length() - MoonOrbit.ORBIT_RADIUS) > 0.01 or absf(offset.y) > 0.01:
		print("FAIL _test_advances_at_the_relative_rate: angle moved %e, offset %s" % [_moon.angle - before, offset])
		result = 1
	return result

func _test_base_faces_the_planet() -> int:
	# In Plato (51.6 N, 9.4 W; longitude 0 toward the planet, east +Z), at
	# any orbit angle; the base's x points east.
	var direction: Vector3 = MoonScript.base_direction()
	var latitude := rad_to_deg(asin(direction.y))
	var longitude := rad_to_deg(atan2(direction.z, -direction.x))
	var east: Vector3 = MoonScript.base_local_transform().basis.x.normalized()
	if absf(latitude - 51.6) > 0.01 or absf(longitude + 9.4) > 0.01 or not east.is_equal_approx(Vector3(sin(deg_to_rad(-9.4)), 0.0, cos(deg_to_rad(-9.4)))):
		print("FAIL _test_base_faces_the_planet: base at %.2f, %.2f, east %s" % [latitude, longitude, east])
		return 1
	var expected := rad_to_deg(acos(cos(deg_to_rad(51.6)) * cos(deg_to_rad(9.4))))
	for angle in [0.0, 1.3, -2.0]:
		_moon.angle = angle
		_moon.advance(0.0)
		var site: Vector3 = _moon.base_transform().origin
		var to_planet: Vector3 = (_planet.global_position - _moon.global_position).normalized()
		var off: float = rad_to_deg(acos(clampf((site - _moon.global_position).normalized().dot(to_planet), -1.0, 1.0)))
		if absf(off - expected) > 0.01:
			print("FAIL _test_base_faces_the_planet: base %.3f degrees off the planet's direction" % off)
			return 1
	return 0

func _test_base_transform_on_the_surface() -> int:
	var site: Transform3D = _moon.base_transform()
	var up: Vector3 = (site.origin - _moon.global_position).normalized()
	if absf(site.origin.distance_to(_moon.global_position) - MoonScript.ground_radius()) > 0.01 or site.basis.y.normalized().dot(up) < 0.999999 or absf(site.basis.determinant() - 1.0) > 1e-6:
		print("FAIL _test_base_transform_on_the_surface: %s" % site)
		return 1
	return 0

func _test_surface_mesh() -> int:
	var mesh: Mesh = (_moon.get_node("Surface") as MeshInstance3D).mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() < 150000 or vertices.size() > 300000:
		print("FAIL _test_surface_mesh: %d vertices" % vertices.size())
		return 1
	for v in vertices:
		# On NASA's heights (no small craters). Mesh positions are 32-bit
		# floats: ~2 cm at 250 km.
		if absf(v.length() - MoonOrbit.RADIUS - MoonTerrain.height(v.normalized(), 0.0)) > 0.05:
			print("FAIL _test_surface_mesh: vertex %s off the ground" % v)
			return 1
	# Front faces out (the winding of the rest of the project).
	for t in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[t]]
		var b: Vector3 = vertices[indices[t + 1]]
		var c: Vector3 = vertices[indices[t + 2]]
		if (c - a).cross(b - a).dot(a + b + c) <= 0.0:
			print("FAIL _test_surface_mesh: triangle %d faces in" % (t / 3))
			return 1
	# Dense rings round the base: the first 20 rings at most 20.5 m apart.
	var arcs: PackedFloat64Array = MoonScript.ring_arcs()
	for k in range(20):
		if arcs[k + 1] - arcs[k] > 20.5:
			print("FAIL _test_surface_mesh: ring %d is %f m from the next" % [k, arcs[k + 1] - arcs[k]])
			return 1
	print("  moon mesh: %d vertices, %d rings" % [vertices.size(), arcs.size()])
	return 0

func _test_altitude() -> int:
	# Over the ground (MoonTerrain), in the moon's own axes.
	var up := Vector3(0.3, 0.8, -0.2).normalized()
	var point: Vector3 = _moon.to_global(up * (MoonOrbit.RADIUS + MoonTerrain.height(up) + 100.0))
	if absf(_moon.altitude(point) - 100.0) > 0.01 or _moon.up_at(point).dot(_moon.global_transform.basis * up) < 0.999999:
		print("FAIL _test_altitude: %f" % _moon.altitude(point))
		return 1
	return 0

func _test_far_version() -> int:
	# From afar a light sphere with the same material takes over: the full
	# mesh is 420k triangles.
	var near := _moon.get_node("Surface") as MeshInstance3D
	var far := _moon.get_node_or_null("FarSurface") as MeshInstance3D
	if far == null or near.visibility_range_end != MoonScript.FAR_SWITCH or far.visibility_range_begin != MoonScript.FAR_SWITCH or far.visibility_range_end != 0.0 or far.material_override != near.material_override or far.mesh.get_faces().size() / 3 > 20000:
		print("FAIL _test_far_version: far surface missing or not set up")
		return 1
	return 0

func _test_maps_have_mipmaps() -> int:
	# The shader samples with gradients: without mip levels a 2048 px map on
	# a 12 px moon shimmers.
	for path in [MoonScript.COLOR_PATH, MoonScript.NORMAL_PATH]:
		if not (load(path) as Texture2D).get_image().has_mipmaps():
			print("FAIL _test_maps_have_mipmaps: %s has none" % path)
			return 1
	return 0

func _test_mesh_radius_meets_the_triangles() -> int:
	# Along a vertex's or a triangle's centre's direction, MoonMesh finds
	# that very point (32-bit mesh positions: a few cm).
	const MoonMesh = preload("res://scripts/moon_mesh.gd")
	var arrays: Array = (_moon.get_node("Surface") as MeshInstance3D).mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t in range(0, indices.size(), 3 * 997):
		var a: Vector3 = vertices[indices[t]]
		var centre: Vector3 = (a + vertices[indices[t + 1]] + vertices[indices[t + 2]]) / 3.0
		for p in [a, centre]:
			var found := MoonMesh.mesh_radius((p as Vector3).normalized())
			if absf(found - (p as Vector3).length()) > 0.1:
				print("FAIL _test_mesh_radius_meets_the_triangles: %.2f m off at %s" % [found - (p as Vector3).length(), p])
				return 1
	return 0
