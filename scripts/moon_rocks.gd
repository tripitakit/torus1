extends Node3D

# Stones and boulders on the moon, a child of the moon (its axes). Three
# sizes, each on a grid on the plane of the cube face under the player (as
# MoonTerrain's craters): at most one stone a cell, picked by the cell's
# hash, so the same stones lie in the same place every time. More on crater
# rims and their ejecta (where the small craters lift the ground), none on
# Base Selene and its pads, few on its flat ground.

const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonPatch = preload("res://scripts/moon_patch.gd")

enum { PEBBLE, ROCK, BOULDER }
# cell (m), chance a cell has one, size range (m), drawn within `reach`,
# rebuilt every `step` the player moves.
const CLASSES := [
	{"cell": 2.0, "chance": 0.6, "low": 0.1, "high": 0.3, "reach": 60.0, "step": 20.0},
	{"cell": 8.0, "chance": 0.35, "low": 0.3, "high": 0.8, "reach": 200.0, "step": 50.0},
	{"cell": 40.0, "chance": 0.6, "low": 0.8, "high": 4.0, "reach": 600.0, "step": 150.0},
]
# Round Base Selene (metres along the surface from its tower).
const NONE_WITHIN := 700.0
const SPARSE_WITHIN := 1200.0
const FULL_FROM := 2500.0
const SPARSE := 0.05
# Crater rims raise the chance by up to this many times over.
const RIM_BOOST := 3.0
# The hash's octave numbers for the stones (the craters use 0..3).
const HASH_OCTAVE := 10

# How much likelier a stone is at `direction` (moon axes, unit) than on
# plain ground: 0 at the base and on the outposts' flat ground, up to
# 1 + RIM_BOOST on crater rims.
static func density(direction: Vector3) -> float:
	var from_base := MoonOrbit.RADIUS * acos(clampf(direction.dot(MoonOrbit.base_direction()), -1.0, 1.0))
	if from_base < NONE_WITHIN:
		return 0.0
	var share := SPARSE
	if from_base >= SPARSE_WITHIN:
		share = lerpf(SPARSE, 1.0, smoothstep(SPARSE_WITHIN, FULL_FROM, from_base))
	# None on the outposts' flat ground, fewer on its blend.
	for name: String in MoonOrbit.OUTPOSTS:
		var site: Dictionary = MoonOrbit.OUTPOSTS[name]
		var along := direction.dot(MoonOrbit.direction_of(site.latitude, site.longitude))
		if along < cos(site.blend / MoonOrbit.RADIUS):
			continue
		var from := MoonOrbit.RADIUS * acos(clampf(along, -1.0, 1.0))
		if from < site.flat:
			return 0.0
		share = minf(share, lerpf(SPARSE, 1.0, smoothstep(site.flat, site.blend, from)))
	return share * (1.0 + clampf(MoonTerrain.crater_height(direction), 0.0, RIM_BOOST))

# The stones of size `kind` in the cells over the face plane's rectangle
# `low`..`high` (metres): {direction, size, spin, squash, shape}.
static func stones_in(face: int, kind: int, low: Vector2, high: Vector2) -> Array:
	var cls: Dictionary = CLASSES[kind]
	var cell: float = cls.cell
	var most: float = cls.chance * (1.0 + RIM_BOOST)
	var found := []
	for i in range(floori(low.x / cell), floori(high.x / cell) + 1):
		for j in range(floori(low.y / cell), floori(high.y / cell) + 1):
			var bits := MoonTerrain._hash(face, HASH_OCTAVE + kind, i, j)
			var roll := MoonTerrain._part(bits, 0)
			if roll >= most:
				continue
			var uv := (Vector2(i, j) + Vector2(MoonTerrain._part(bits, 1), MoonTerrain._part(bits, 2))) * cell
			var direction := MoonPatch.plane_direction(face, uv)
			if roll >= cls.chance * density(direction):
				continue
			var more := MoonTerrain._mix(bits)
			var small := MoonTerrain._part(more, 0)
			found.append({
				"direction": direction,
				"size": lerpf(cls.low, cls.high, small * small),
				"spin": MoonTerrain._part(more, 1) * TAU,
				"squash": lerpf(0.55, 0.9, MoonTerrain._part(more, 2)),
				"shape": mini(2, int(MoonTerrain._part(more, 3) * 3.0)),
			})
	return found

# Boulders within this of the one walking or driving get a sphere each
# (RockBody), rebuilt every COLLIDE_STEP they move.
const COLLIDE_REACH := 60.0
const COLLIDE_STEP := 10.0
# A stone sits a quarter of its height in the ground.
const SINK := 0.25
const COLOUR := Color(0.46, 0.45, 0.43)

var _face := -1
var _windows := [Vector2i(-999999, -999999), Vector2i(-999999, -999999), Vector2i(-999999, -999999)]
var _tasks := [-1, -1, -1]
# The boulders last built: [position (moon axes), size] each.
var _boulders := []
var _collide_at := Vector3.INF
var _meshes := []
var _material: StandardMaterial3D

func _ready() -> void:
	var body := StaticBody3D.new()
	body.name = "RockBody"
	add_child(body)
	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOUR
	_material.roughness = 1.0
	for kind in range(3):
		_meshes.append(rock_mesh(kind))
		var node := MultiMeshInstance3D.new()
		node.name = "Stones%d" % kind
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _meshes[kind]
		node.multimesh = multimesh
		node.material_override = _material
		node.visibility_range_end = CLASSES[kind].reach * 1.2
		add_child(node)

func _exit_tree() -> void:
	for kind in range(3):
		if _tasks[kind] >= 0:
			WorkerThreadPool.wait_for_task_completion(_tasks[kind])
			_tasks[kind] = -1

# The player at `point` (moon axes): the stones round them, rebuilt on a
# worker as they move; with `collide`, spheres on the near boulders.
func follow(point: Vector3, collide: bool) -> void:
	var direction := point.normalized()
	var face := MoonPatch.face_of(direction, _face)
	if face != _face:
		_face = face
		for kind in range(3):
			_windows[kind] = Vector2i(-999999, -999999)
	var plane := MoonPatch.plane_coords(direction, face)
	# Higher up than a size is seen from (the ship flying): not built, hidden.
	var altitude := point.length() - MoonOrbit.RADIUS - MoonTerrain.height(direction)
	for kind in range(3):
		var seen: bool = altitude < CLASSES[kind].reach * 1.2
		(get_node("Stones%d" % kind) as Node3D).visible = seen
		if not seen:
			continue
		var step: float = CLASSES[kind].step
		var window := Vector2i(roundi(plane.x / step), roundi(plane.y / step))
		if window != _windows[kind] and _tasks[kind] < 0:
			_windows[kind] = window
			_tasks[kind] = WorkerThreadPool.add_task(_build.bind(kind, face, window), true, "moon stones")
	if collide and point.distance_to(_collide_at) > COLLIDE_STEP:
		_collide_round(point)

func _build(kind: int, face: int, window: Vector2i) -> void:
	var cls: Dictionary = CLASSES[kind]
	var centre := Vector2(window) * float(cls.step)
	var origin := MoonPatch.plane_direction(face, centre) * MoonOrbit.RADIUS
	var stones := stones_in(face, kind, centre - Vector2.ONE * cls.reach, centre + Vector2.ONE * cls.reach)
	var buffer := PackedFloat32Array()
	buffer.resize(stones.size() * 12)
	var boulders := []
	for n in range(stones.size()):
		var stone: Dictionary = stones[n]
		var up: Vector3 = stone.direction
		var ground: Vector3 = up * MoonPatch.drawn_radius(face, up)
		var size: float = stone.size
		var high: float = size * stone.squash
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up)) * Basis(Vector3.UP, stone.spin)
		basis = basis * Basis.from_scale(Vector3(size, high, size * 0.85))
		var at := ground + up * high * (0.5 - SINK) - origin
		var t := Transform3D(basis, at)
		for r in range(3):
			buffer[n * 12 + r * 4] = t.basis[0][r]
			buffer[n * 12 + r * 4 + 1] = t.basis[1][r]
			buffer[n * 12 + r * 4 + 2] = t.basis[2][r]
			buffer[n * 12 + r * 4 + 3] = t.origin[r]
		if kind == BOULDER:
			boulders.append([ground, size])
	_apply.call_deferred(kind, origin, buffer, stones.size(), boulders)

func _apply(kind: int, origin: Vector3, buffer: PackedFloat32Array, count: int, boulders: Array) -> void:
	if _tasks[kind] >= 0:
		WorkerThreadPool.wait_for_task_completion(_tasks[kind])
	_tasks[kind] = -1
	var node := get_node("Stones%d" % kind) as MultiMeshInstance3D
	node.position = origin
	node.multimesh.instance_count = count
	if count > 0:
		node.multimesh.buffer = buffer
	node.custom_aabb = AABB(-Vector3.ONE * CLASSES[kind].reach * 1.5, Vector3.ONE * CLASSES[kind].reach * 3.0)
	if kind == BOULDER:
		_boulders = boulders
		_collide_at = Vector3.INF

# A sphere for each boulder within COLLIDE_REACH of `point` (moon axes).
func _collide_round(point: Vector3) -> void:
	if _boulders.is_empty():
		return
	_collide_at = point
	var body := get_node("RockBody") as StaticBody3D
	for child in body.get_children():
		body.remove_child(child)
		child.free()
	for boulder: Array in _boulders:
		var ground: Vector3 = boulder[0]
		if ground.distance_to(point) > COLLIDE_REACH:
			continue
		var size: float = boulder[1]
		var sphere := SphereShape3D.new()
		sphere.radius = size * 0.45
		var shape := CollisionShape3D.new()
		shape.shape = sphere
		shape.position = ground + ground.normalized() * size * 0.2
		body.add_child(shape)

# A low-poly stone about 1 m across: a coarse sphere with its corners pulled
# in and out (a different pull for each size), flat-shaded.
static func rock_mesh(kind: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 7
	sphere.rings = 4
	var arrays := sphere.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(indices.size()):
		var p := points[indices[k]]
		var key := Vector3i((p * 100.0).round())
		var pull := 0.75 + 0.5 * MoonTerrain._part(MoonTerrain._hash(kind, 0, key.x * 131 + key.y, key.z), 0)
		st.add_vertex(p * pull)
	st.generate_normals()
	return st.commit()
