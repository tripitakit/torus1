extends Node3D

# The fine ground under the ship (a child of the moon, in its axes): three
# square rings, points SPACINGS apart and CELLS across, each round a hole
# the finer one fills. The points sit on a lattice fixed on the moon: the
# plane of the cube face under the ship (as the craters' grid), so a point
# of the ground is always the same vertex with the same height, and a ring
# only slides by SNAP_CELLS whole cells as the ship moves: no swimming.
# Each vertex also carries where the next ring's surface is (the whole
# moon's for the outer ring) and the moon shader morphs to it with the
# distance from the camera, from MORPH_START to MORPH_END of the ring's half
# width: full detail near, smooth far, done before the ring's edge, so a
# ring's edge sliding on never shows. The edges lie on the next ring's
# surface (no cracks); a skirt hangs from the outer one. Heights are cached
# per lattice point: a rebuild computes only the new strip. Built on a
# worker thread when the inner ring has a cell step to slide.

const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonMesh = preload("res://scripts/moon_mesh.gd")

const SPACINGS := [8.0, 32.0, 128.0]
const CELLS := 64
# Spacings grow by this from ring to ring.
const RATIO := 4
const SNAP_CELLS := 8
# Each ring leaves out craters whose class tops out under this (m).
const SMALLEST := [0.0, 64.0, 256.0]
# The morph runs from MORPH_START to MORPH_END of a ring's half width: done
# with room to spare before its edge, even with the ring a step behind.
const MORPH_START := 0.45
const MORPH_END := 0.75
# The rings centre where the ship will be this far ahead (s): a rebuild
# takes a few frames, and a ring caught behind shows the coarser ring's
# ground ahead of the ship until it slides on.
const LEAD := 0.3
const SKIRT := 30.0
# The cube face is kept until another's axis is this much nearer the ship's
# direction (no flicker on an edge).
const FACE_STICK := 0.95
# Past this many cached heights the cache starts over.
const CACHE_LIMIT := 400000

signal rebuilt
var face := -1
# The inner ring's window (lattice indices of its centre) and the outer
# ring's centre and half width on the face's plane (for the whole moon's
# hole).
var window := Vector2i(-99999999, -99999999)
var hole_centre := Vector2.ZERO
var hole_half := 0.0
var building := false
var built := false
var _active := false
# Where it was last told to follow (moon axes).
var last_point := Vector3.ZERO
var _task := -1
var _material: Material

static var _cache := {}
static var _samples := 0

func set_material(material: Material) -> void:
	_material = material
	for ring in find_children("Ring*", "MeshInstance3D", false, false):
		(ring as MeshInstance3D).material_override = material

# The ship at `point` moving at `velocity` (moon axes): rebuild round the
# ground under where it will be (LEAD) when the inner ring has a step to
# slide.
func follow(point: Vector3, velocity := Vector3.ZERO) -> void:
	last_point = point
	_active = true
	visible = built
	if building:
		return
	var direction := (point + velocity * LEAD).normalized()
	var on_face := face_of(direction, face)
	var plane := plane_coords(direction, on_face)
	if built and on_face == face and window_of(plane, 0) == window:
		return
	building = true
	_task = WorkerThreadPool.add_task(_work.bind(on_face, plane), true, "moon patch")

func stop() -> void:
	_active = false
	built = false
	visible = false

func _work(on_face: int, plane: Vector2) -> void:
	var rings := build_rings(on_face, plane)
	_apply.call_deferred(on_face, plane, rings)

# A build still running when the patch leaves the tree finishes first.
func _exit_tree() -> void:
	_finish_task()

func _finish_task() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _apply(on_face: int, plane: Vector2, rings: Array) -> void:
	_finish_task()
	building = false
	if not _active:
		return
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	for k in range(rings.size()):
		var ring: Dictionary = rings[k]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = ring.vertices
		arrays[Mesh.ARRAY_NORMAL] = ring.normals
		arrays[Mesh.ARRAY_CUSTOM0] = ring.morph
		arrays[Mesh.ARRAY_CUSTOM1] = ring.morph_normals
		arrays[Mesh.ARRAY_INDEX] = ring.indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		var node := get_node_or_null("Ring%d" % k) as MeshInstance3D
		if node == null:
			node = MeshInstance3D.new()
			node.name = "Ring%d" % k
			add_child(node)
		node.mesh = mesh
		node.position = ring.origin
		node.material_override = _material
		# Morphed vertices move up to tens of metres: never cull by the box.
		node.extra_cull_margin = 200.0
	face = on_face
	window = window_of(plane, 0)
	var outer: Dictionary = rings[-1]
	hole_centre = outer.centre_uv
	hole_half = SPACINGS[-1] * CELLS * 0.5
	built = true
	visible = true
	rebuilt.emit()

# The common origin of the rings' vertices (moon axes): the inner ring's
# centre, where precision matters most.
func origin() -> Vector3:
	var ring := get_node_or_null("Ring0") as Node3D
	return Vector3.ZERO if ring == null else ring.position

# The cube face for `direction`: +X 0, -X 1, +Y 2, -Y 3, +Z 4, -Z 5; kept
# (`current`) until another axis is clearly nearer.
static func face_of(direction: Vector3, current: int) -> int:
	var best := 0
	for axis in range(1, 3):
		if absf(direction[axis]) > absf(direction[best]):
			best = axis
	if current >= 0:
		var current_axis := current / 2
		var same_side := (direction[current_axis] > 0.0) == (current % 2 == 0)
		if same_side and absf(direction[current_axis]) >= absf(direction[best]) * FACE_STICK:
			return current
	return best * 2 + (0 if direction[best] > 0.0 else 1)

# A face's axes: {axis (out of the face), e1, e2 (along it)}.
static func face_axes(on_face: int) -> Dictionary:
	var index := on_face / 2
	var axis := Vector3.ZERO
	axis[index] = 1.0 if on_face % 2 == 0 else -1.0
	var e1 := Vector3.ZERO
	e1[(index + 1) % 3] = 1.0
	var e2 := Vector3.ZERO
	e2[(index + 2) % 3] = 1.0
	return {"axis": axis, "e1": e1, "e2": e2}

# Metres on the face's plane (the plane touching the sphere of
# MoonOrbit.RADIUS at the face's centre) for `direction`.
static func plane_coords(direction: Vector3, on_face: int) -> Vector2:
	var axes := face_axes(on_face)
	var out: float = direction.dot(axes.axis)
	return Vector2(direction.dot(axes.e1), direction.dot(axes.e2)) * (MoonOrbit.RADIUS / out)

static func plane_direction(on_face: int, uv: Vector2) -> Vector3:
	var axes := face_axes(on_face)
	return (axes.axis * MoonOrbit.RADIUS + axes.e1 * uv.x + axes.e2 * uv.y).normalized()

# Ring `k`'s window: the lattice indices (in its own spacing) of its centre,
# snapped to SNAP_CELLS.
static func window_of(plane: Vector2, k: int) -> Vector2i:
	var step: float = SPACINGS[k] * SNAP_CELLS
	return Vector2i(roundi(plane.x / step), roundi(plane.y / step)) * SNAP_CELLS

static func samples_taken() -> int:
	return _samples

# The ground's distance from the moon's centre at lattice point (i, j) of
# `level` (a ring's spacing and craters; level SPACINGS.size(): the whole
# moon's mesh on the outer ring's lattice). Cached.
static func lattice_radius(on_face: int, level: int, i: int, j: int) -> float:
	var key := Vector4i(on_face, level, i, j)
	if _cache.has(key):
		return _cache[key]
	if _cache.size() > CACHE_LIMIT:
		_cache.clear()
	var spacing: float = SPACINGS[mini(level, SPACINGS.size() - 1)]
	var direction := plane_direction(on_face, Vector2(i, j) * spacing)
	var r: float
	if level >= SPACINGS.size():
		r = MoonMesh.mesh_radius(direction)
	else:
		r = MoonOrbit.RADIUS + MoonTerrain.height(direction, 1.0, SMALLEST[level])
	_samples += 1
	_cache[key] = r
	return r

# The next level's surface at point (i, j) of `level`: on its triangles (its
# quads split a-b-c, b-d-c as the rings lay them), as a distance from the
# moon's centre.
static func coarse_radius(on_face: int, level: int, i: int, j: int) -> float:
	if level == SPACINGS.size() - 1:
		return MoonMesh.mesh_radius(plane_direction(on_face, Vector2(i, j) * SPACINGS[level]))
	var ci := floori(float(i) / RATIO)
	var cj := floori(float(j) / RATIO)
	var fx := float(i - ci * RATIO) / RATIO
	var fy := float(j - cj * RATIO) / RATIO
	var r00 := lattice_radius(on_face, level + 1, ci, cj)
	if fx == 0.0 and fy == 0.0:
		return r00
	var r10 := lattice_radius(on_face, level + 1, ci + 1, cj)
	var r01 := lattice_radius(on_face, level + 1, ci, cj + 1)
	if fx + fy <= 1.0:
		return r00 + (r10 - r00) * fx + (r01 - r00) * fy
	var r11 := lattice_radius(on_face, level + 1, ci + 1, cj + 1)
	return r11 + (r01 - r11) * (1.0 - fx) + (r10 - r11) * (1.0 - fy)

# The rings round `plane` (the ship's point on `on_face`'s plane): per ring
# {origin (shared), vertices and normals (from the origin), morph (offset to
# the next surface, and the ring's half width), morph_normals, indices,
# edge (1 on the outer edge), centre_uv, face}.
static func build_rings(on_face: int, plane: Vector2) -> Array:
	var centre := window_of(plane, 0)
	var origin := plane_direction(on_face, Vector2(centre) * SPACINGS[0]) * MoonOrbit.RADIUS
	var rings := []
	for k in range(SPACINGS.size()):
		var hole := Vector2i(-1, -1)
		if k > 0:
			hole = window_of(plane, k - 1) / RATIO
		rings.append(_ring(on_face, k, window_of(plane, k), hole, origin))
	return rings

static func _ring(on_face: int, k: int, centre: Vector2i, hole_centre_index: Vector2i, origin: Vector3) -> Dictionary:
	var spacing: float = SPACINGS[k]
	var half := CELLS / 2
	var side := CELLS + 1
	var last := k == SPACINGS.size() - 1
	var count := side * side
	var points := PackedVector3Array()
	points.resize(count)
	var targets := PackedVector3Array()
	targets.resize(count)
	var edge := PackedByteArray()
	edge.resize(count)
	for j in range(side):
		for i in range(side):
			var gi := centre.x - half + i
			var gj := centre.y - half + j
			var direction := plane_direction(on_face, Vector2(gi, gj) * spacing)
			var target := direction * coarse_radius(on_face, k, gi, gj)
			var on_edge := i == 0 or j == 0 or i == CELLS or j == CELLS
			var n := j * side + i
			edge[n] = 1 if on_edge else 0
			# The edge lies on the next surface: no crack whatever the morph.
			points[n] = (target if on_edge else direction * lattice_radius(on_face, k, gi, gj)) - origin
			targets[n] = target - origin
	var normals := _normals(points)
	var target_normals := _normals(targets)
	var morph := PackedFloat32Array()
	morph.resize(count * 4)
	var morph_normals := PackedFloat32Array()
	morph_normals.resize(count * 4)
	var ring_half := spacing * CELLS * 0.5
	for n in range(count):
		var offset := targets[n] - points[n]
		morph[n * 4] = offset.x
		morph[n * 4 + 1] = offset.y
		morph[n * 4 + 2] = offset.z
		morph[n * 4 + 3] = ring_half
		morph_normals[n * 4] = target_normals[n].x
		morph_normals[n * 4 + 1] = target_normals[n].y
		morph_normals[n * 4 + 2] = target_normals[n].z
	var indices := PackedInt32Array()
	# The hole the finer ring fills: its window, in this ring's cells.
	var hole_cells := half / RATIO
	for j in range(CELLS):
		for i in range(CELLS):
			if k > 0:
				var gi := centre.x - half + i
				var gj := centre.y - half + j
				if gi >= hole_centre_index.x - hole_cells and gi < hole_centre_index.x + hole_cells and gj >= hole_centre_index.y - hole_cells and gj < hole_centre_index.y + hole_cells:
					continue
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var d := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	if last:
		_skirt(points, normals, morph, morph_normals, indices, origin)
	return {"origin": origin, "vertices": points, "normals": normals, "morph": morph, "morph_normals": morph_normals, "indices": indices, "edge": edge, "centre_uv": Vector2(centre) * spacing, "face": on_face}

static func _normals(points: PackedVector3Array) -> PackedVector3Array:
	var side := CELLS + 1
	var normals := PackedVector3Array()
	normals.resize(points.size())
	for j in range(side):
		for i in range(side):
			var east := points[j * side + mini(i + 1, CELLS)] - points[j * side + maxi(i - 1, 0)]
			var south := points[mini(j + 1, CELLS) * side + i] - points[maxi(j - 1, 0) * side + i]
			normals[j * side + i] = south.cross(east).normalized()
	return normals

# A strip hanging SKIRT metres down from the outer edge (hides any slit
# between the patch and the whole moon's mesh).
static func _skirt(points: PackedVector3Array, normals: PackedVector3Array, morph: PackedFloat32Array, morph_normals: PackedFloat32Array, indices: PackedInt32Array, origin: Vector3) -> void:
	var side := CELLS + 1
	var ring_order := []
	for i in range(CELLS):
		ring_order.append(i)
	for j in range(CELLS):
		ring_order.append(j * side + CELLS)
	for i in range(CELLS, 0, -1):
		ring_order.append(CELLS * side + i)
	for j in range(CELLS, 0, -1):
		ring_order.append(j * side)
	var start := points.size()
	for index in ring_order:
		var top: Vector3 = points[index]
		var down := (top + origin).normalized()
		points.append(top - down * SKIRT)
		normals.append(normals[index])
		for c in range(4):
			morph.append(morph[index * 4 + c])
			morph_normals.append(morph_normals[index * 4 + c])
	var count := ring_order.size()
	for n in range(count):
		var a: int = ring_order[n]
		var b: int = ring_order[(n + 1) % count]
		var c := start + n
		var d := start + (n + 1) % count
		indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
