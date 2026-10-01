extends Node3D

# The fine ground under the ship (a child of the moon, in its axes): three
# square rings on the tangent plane under the ship, points SPACINGS apart,
# CELLS across, each round a hole the finer one fills. Heights from
# MoonTerrain (the coarser rings skip craters too small for their grid; the
# outer ring fades out toward its edge onto the whole moon's mesh itself,
# MoonMesh.mesh_radius, which takes over there). A fine ring's outer edge lies on the next ring's
# surface, so no cracks open between them; a skirt hangs from the outer
# edge. Built on a worker thread when the ship has moved REBUILD metres from
# the patch's centre; the new rings replace the old ones at once.

const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonMesh = preload("res://scripts/moon_mesh.gd")

const SPACINGS := [8.0, 32.0, 128.0]
const CELLS := 64
# Each ring leaves out craters whose class tops out under this (m).
const SMALLEST := [0.0, 64.0, 256.0]
const REBUILD := 64.0
const SKIRT := 30.0

signal rebuilt
var centre := Vector3.ZERO  # unit direction, moon axes
var building := false
var built := false
var _active := false
var _task := -1
var _material: Material

func set_material(material: Material) -> void:
	_material = material
	for ring in find_children("Ring*", "MeshInstance3D", false, false):
		(ring as MeshInstance3D).material_override = material

# The ship at `point` (moon axes): rebuild round the ground under it when it
# has moved far enough.
func follow(point: Vector3) -> void:
	_active = true
	visible = built
	if building:
		return
	var direction := point.normalized()
	if built and centre.distance_to(direction) * MoonOrbit.RADIUS < REBUILD:
		return
	building = true
	_task = WorkerThreadPool.add_task(_work.bind(direction), true, "moon patch")

func stop() -> void:
	_active = false
	built = false
	visible = false

func _work(direction: Vector3) -> void:
	var rings := build_rings(direction)
	_apply.call_deferred(direction, rings)

# A build still running when the patch leaves the tree finishes first.
func _exit_tree() -> void:
	_finish_task()

func _finish_task() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _apply(direction: Vector3, rings: Array) -> void:
	_finish_task()
	building = false
	if not _active:
		return
	for k in range(rings.size()):
		var ring: Dictionary = rings[k]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = ring.vertices
		arrays[Mesh.ARRAY_NORMAL] = ring.normals
		arrays[Mesh.ARRAY_INDEX] = ring.indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var node := get_node_or_null("Ring%d" % k) as MeshInstance3D
		if node == null:
			node = MeshInstance3D.new()
			node.name = "Ring%d" % k
			add_child(node)
		node.mesh = mesh
		node.position = ring.origin
		node.material_override = _material
	centre = direction
	built = true
	visible = true
	rebuilt.emit()

# The tangent plane at `direction`: basis x and z along it, y up; origin on
# the sphere of MoonOrbit.RADIUS.
static func tangent_frame(direction: Vector3) -> Transform3D:
	var up := direction.normalized()
	var helper := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var x := helper.cross(up).normalized()
	var z := x.cross(up)
	return Transform3D(Basis(x, up, z), up * MoonOrbit.RADIUS)

# The rings round `direction`: per ring {origin, vertices (from origin),
# normals, indices, edge (1 for the outer edge's vertices), spacing}.
static func build_rings(direction: Vector3) -> Array:
	var frame := tangent_frame(direction)
	var rings := []
	for k in range(SPACINGS.size()):
		rings.append(_ring(frame, k))
	return rings

# A point of ring `k` at (u, v) metres on the tangent plane, moon axes.
static func ring_point(frame: Transform3D, k: int, u: float, v: float) -> Vector3:
	var direction := (frame.origin + frame.basis.x * u + frame.basis.z * v).normalized()
	var half: float = SPACINGS[k] * CELLS * 0.5
	var fade := smoothstep(half * 0.5, half, maxf(absf(u), absf(v)))
	if k < SPACINGS.size() - 1:
		# The craters the next ring leaves out fade toward this one's edge.
		return direction * (MoonOrbit.RADIUS + MoonTerrain.height(direction, 1.0, SMALLEST[k], SMALLEST[k + 1], 1.0 - fade))
	var ground := MoonOrbit.RADIUS + MoonTerrain.height(direction, 1.0 - fade, SMALLEST[k])
	if fade > 0.0:
		ground = lerpf(ground, MoonMesh.mesh_radius(direction), fade)
	return direction * ground

static func _ring(frame: Transform3D, k: int) -> Dictionary:
	var spacing: float = SPACINGS[k]
	var half := CELLS / 2
	var side := CELLS + 1
	var last := k == SPACINGS.size() - 1
	var points := PackedVector3Array()
	points.resize(side * side)
	var edge := PackedByteArray()
	edge.resize(side * side)
	for j in range(side):
		for i in range(side):
			var u := (i - half) * spacing
			var v := (j - half) * spacing
			var on_edge := i == 0 or j == 0 or i == CELLS or j == CELLS
			var p: Vector3
			if on_edge and not last:
				# On the next ring's grid line: on its straight edge between
				# its two points round here.
				var step := 4
				var along_i := j == 0 or j == CELLS
				var n := i if along_i else j
				var a := n - posmod(n - half, step)
				var b := mini(a + step, CELLS)
				var t := float(n - a) / step
				var pa: Vector3
				var pb: Vector3
				if along_i:
					pa = ring_point(frame, k + 1, (a - half) * spacing, v)
					pb = ring_point(frame, k + 1, (b - half) * spacing, v)
				else:
					pa = ring_point(frame, k + 1, u, (a - half) * spacing)
					pb = ring_point(frame, k + 1, u, (b - half) * spacing)
				p = pa.lerp(pb, t) if t > 0.0 else pa
				edge[j * side + i] = 1
			else:
				p = ring_point(frame, k, u, v)
				edge[j * side + i] = 1 if on_edge else 0
			points[j * side + i] = p - frame.origin
	var normals := PackedVector3Array()
	normals.resize(side * side)
	for j in range(side):
		for i in range(side):
			var east := points[j * side + mini(i + 1, CELLS)] - points[j * side + maxi(i - 1, 0)]
			var south := points[mini(j + 1, CELLS) * side + i] - points[maxi(j - 1, 0) * side + i]
			normals[j * side + i] = south.cross(east).normalized()
	var indices := PackedInt32Array()
	# The hole the finer ring fills: cells within its half width.
	var hole := 0 if k == 0 else int(SPACINGS[k - 1] * CELLS * 0.5 / spacing)
	for j in range(CELLS):
		for i in range(CELLS):
			if k > 0 and i >= half - hole and i < half + hole and j >= half - hole and j < half + hole:
				continue
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var d := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	if last:
		_skirt(points, normals, indices, frame)
	return {"origin": frame.origin, "vertices": points, "normals": normals, "indices": indices, "edge": edge, "spacing": spacing}

# A strip hanging SKIRT metres down from the outer edge (hides any slit
# between the patch and the whole moon's mesh).
static func _skirt(points: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, frame: Transform3D) -> void:
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
		var down := (top + frame.origin).normalized()
		points.append(top - down * SKIRT)
		normals.append(normals[index])
	var count := ring_order.size()
	for n in range(count):
		var a: int = ring_order[n]
		var b: int = ring_order[(n + 1) % count]
		var c := start + n
		var d := start + (n + 1) % count
		indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

# The largest distance from a fine ring's outer edge vertices to the next
# ring's edge segments there (for tests: should be ~0).
static func edge_gap(fine: Dictionary, coarse: Dictionary) -> float:
	var side := CELLS + 1
	var fine_points: PackedVector3Array = fine.vertices
	var coarse_points: PackedVector3Array = coarse.vertices
	var half := CELLS / 2
	var worst := 0.0
	for j in range(side):
		for i in range(side):
			if not (i == 0 or j == 0 or i == CELLS or j == CELLS):
				continue
			var p := fine_points[j * side + i]
			# The coarse grid index of this point, and its two neighbours on
			# the hole's edge.
			var ci := half + (i - half) / 4.0
			var cj := half + (j - half) / 4.0
			var a := Vector2i(floori(ci), floori(cj))
			var b := Vector2i(ceili(ci), ceili(cj))
			var pa := coarse_points[a.y * side + a.x]
			var pb := coarse_points[b.y * side + b.x]
			var segment := pb - pa
			var t := 0.0 if segment.length_squared() == 0.0 else clampf((p - pa).dot(segment) / segment.length_squared(), 0.0, 1.0)
			worst = maxf(worst, p.distance_to(pa + segment * t))
	return worst
