extends RefCounted

# The whole moon's surface mesh: rings round Base Selene (its pole), on
# NASA's heights (MoonTerrain, small craters left to the patch under the
# ship), and the point of that mesh in any direction (the patch's outer edge
# meets it there).

const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonTerrain = preload("res://scripts/moon_terrain.gd")

# The surface mesh is laid out in rings round the base: DENSE_STEP apart up
# to DENSE_REACH from it, then each GROWTH times farther than the last, up
# to STEP_CAP; SEGMENTS round each ring. Near the base the chord sag is well
# under a centimetre; far away it stays within a few metres.
const SEGMENTS := 512
const DENSE_STEP := 20.0
const DENSE_REACH := 2000.0
const GROWTH := 1.08
const STEP_CAP := 3000.0

static var _arcs := PackedFloat64Array()

# East at the base, along the surface.
static func base_east() -> Vector3:
	var lon := deg_to_rad(MoonOrbit.BASE_LONGITUDE)
	return Vector3(sin(lon), 0.0, cos(lon))

# Arc distances from the base of the surface mesh's rings: 0 (the base
# itself) first, the antipode (pi * RADIUS) last.
static func ring_arcs() -> PackedFloat64Array:
	var arcs := PackedFloat64Array()
	var far := PI * MoonOrbit.RADIUS
	var s := 0.0
	var step := DENSE_STEP
	while s < far - step * 0.5:
		arcs.append(s)
		s += step
		if s >= DENSE_REACH:
			step = minf(step * GROWTH, STEP_CAP)
	arcs.append(far)
	return arcs

# The whole moon's ground: NASA's heights only (the patch under the ship
# adds the small craters).
static func _surface_radius(direction: Vector3) -> float:
	return MoonOrbit.RADIUS + MoonTerrain.height(direction, 0.0)

# The sphere in rings round the base (its pole): dense near it, sparse far.
# Vertex 0 is the base point, then SEGMENTS per ring, then the antipode.
static func build() -> ArrayMesh:
	var arcs := ring_arcs()
	var pole := MoonOrbit.base_direction()
	var a := base_east()
	var b := pole.cross(a)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.append(pole * _surface_radius(pole))
	normals.append(pole)
	var cosines := PackedFloat64Array()
	var sines := PackedFloat64Array()
	for i in range(SEGMENTS):
		cosines.append(cos(TAU * i / SEGMENTS))
		sines.append(sin(TAU * i / SEGMENTS))
	for k in range(1, arcs.size() - 1):
		var theta: float = arcs[k] / MoonOrbit.RADIUS
		var up_part: Vector3 = pole * cos(theta)
		var side: float = sin(theta)
		for i in range(SEGMENTS):
			var direction: Vector3 = up_part + (a * cosines[i] + b * sines[i]) * side
			vertices.append(direction * _surface_radius(direction))
			normals.append(direction)
	vertices.append(-pole * _surface_radius(-pole))
	normals.append(-pole)
	var rings: int = arcs.size() - 2
	var last: int = vertices.size() - 1
	var indices := PackedInt32Array()
	# Winding (front faces out): with P(k, i) ring k's i-th vertex, the base
	# point as ring 0 and the antipode as ring `rings` + 1, a quad is
	# [P(k,i), P(k,i+1), P(k+1,i)] and [P(k,i+1), P(k+1,i+1), P(k+1,i)].
	for i in range(SEGMENTS):
		var next: int = (i + 1) % SEGMENTS
		indices.append_array(PackedInt32Array([0, 1 + next, 1 + i]))
	for k in range(rings - 1):
		var row: int = 1 + k * SEGMENTS
		var below: int = row + SEGMENTS
		for i in range(SEGMENTS):
			var next: int = (i + 1) % SEGMENTS
			indices.append_array(PackedInt32Array([row + i, row + next, below + i, row + next, below + next, below + i]))
	var outer: int = 1 + (rings - 1) * SEGMENTS
	for i in range(SEGMENTS):
		var next: int = (i + 1) % SEGMENTS
		indices.append_array(PackedInt32Array([outer + i, outer + next, last]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# The distance from the moon's centre to the mesh along `direction` (unit,
# moon axes): through the very triangle drawn there.
static func mesh_radius(direction: Vector3) -> float:
	if _arcs.is_empty():
		_arcs = ring_arcs()
	var pole := MoonOrbit.base_direction()
	var a := base_east()
	var b := pole.cross(a)
	var arc := acos(clampf(direction.dot(pole), -1.0, 1.0)) * MoonOrbit.RADIUS
	var last := _arcs.size() - 1
	var k := clampi(_arcs.bsearch(arc, false) - 1, 0, last - 1)
	var phi := fposmod(atan2(direction.dot(b), direction.dot(a)), TAU)
	var i := floori(phi / TAU * SEGMENTS) % SEGMENTS
	var j := (i + 1) % SEGMENTS
	var triangles := []
	if k == 0:
		triangles.append([_vertex(0, 0, pole, a, b), _vertex(1, j, pole, a, b), _vertex(1, i, pole, a, b)])
	elif k + 1 == last:
		triangles.append([_vertex(k, i, pole, a, b), _vertex(k, j, pole, a, b), _vertex(last, 0, pole, a, b)])
	else:
		var p00 := _vertex(k, i, pole, a, b)
		var p01 := _vertex(k, j, pole, a, b)
		var p10 := _vertex(k + 1, i, pole, a, b)
		var p11 := _vertex(k + 1, j, pole, a, b)
		triangles.append([p00, p01, p10])
		triangles.append([p01, p11, p10])
	var best := -1.0
	for triangle in triangles:
		var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3.ZERO, direction, triangle[0], triangle[1], triangle[2])
		if hit != null:
			return (hit as Vector3).length()
		if best < 0.0:
			# Just off an edge (rounding): its plane.
			var normal: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
			best = normal.dot(triangle[0]) / normal.dot(direction)
	return best

# Mesh vertex `i` of ring `k` (ring 0 the base point, the last the antipode).
static func _vertex(k: int, i: int, pole: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var theta: float = _arcs[k] / MoonOrbit.RADIUS
	var angle := TAU * i / SEGMENTS
	var direction := pole * cos(theta) + (a * cos(angle) + b * sin(angle)) * sin(theta)
	if k == 0:
		direction = pole
	elif k == _arcs.size() - 1:
		direction = -pole
	return direction * _surface_radius(direction)
