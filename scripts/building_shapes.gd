extends RefCounted

# The sci-fi building shapes, built in code once each: low-poly meshes in
# the unit box centred on the origin (x and z from -0.5 to 0.5, y from -0.5
# to 0.5, base at y = -0.5), so terrain_dressing's building_transform
# stretches them to each building's size. Most are "lathed": a footprint
# outline repeated in rings of (height 0..1, scale); a ring at the same
# height as the one before but narrower makes a ledge, which is roof.
# Normals are flat per face (low-poly look).

const SectionPlanScript = preload("res://scripts/section_plan.gd")

# Node names, by SectionPlan.Style.
const NAMES := ["Dome", "Vault", "Block", "RingHouse", "Stepped", "Tapered", "RingTower", "FinSlab", "Spire"]
const MAX_TRIANGLES := 256
const ROUND_SIDES := 12
const HULL_MARGIN := 1.002

static var _meshes := {}
static var _hulls := {}

static func mesh(style: int) -> ArrayMesh:
	if not _meshes.has(style):
		_meshes[style] = _build(style)
	return _meshes[style]

# The shape's convex hull in the unit box. Buildings of this style collide
# as it, stretched to their size: recesses (steps, gaps between fins) are
# solid.
static func hull_points(style: int) -> PackedVector3Array:
	if not _hulls.has(style):
		var shape := mesh(style).create_convex_shape(true, false) as ConvexPolygonShape3D
		# The cleaned hull (a few dozen points) sits up to ~1e-4 inside the
		# mesh: push it out a hair so it always holds the drawn shape.
		var points := PackedVector3Array()
		for p in shape.points:
			points.append(p * HULL_MARGIN)
		_hulls[style] = points
	return _hulls[style]

static func _build(style: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var square := _polygon(4, sqrt(0.5), PI / 4.0)
	var octagon := _polygon(8, 0.5 / cos(PI / 8.0), PI / 8.0)
	var circle := _polygon(ROUND_SIDES, 0.5, 0.0)
	if style == SectionPlanScript.Style.DOME:
		var rings := [Vector2(0.0, 1.0), Vector2(0.3, 1.0)]
		for k in range(1, 5):
			var a: float = k * PI / 8.0
			rings.append(Vector2(0.3 + 0.7 * sin(a), cos(a)))
		_lathe(st, circle, rings)
	elif style == SectionPlanScript.Style.VAULT:
		_vault(st)
	elif style == SectionPlanScript.Style.BLOCK:
		_lathe(st, octagon, [Vector2(0.0, 1.0), Vector2(0.88, 1.0), Vector2(0.88, 0.82), Vector2(1.0, 0.82)])
	elif style == SectionPlanScript.Style.RING_HOUSE:
		# A full-width plinth, a narrower body, a ring round the middle.
		_lathe(st, circle, [Vector2(0.0, 1.0), Vector2(0.1, 1.0), Vector2(0.1, 0.85), Vector2(0.45, 0.85), Vector2(0.45, 1.0), Vector2(0.55, 1.0), Vector2(0.55, 0.85), Vector2(1.0, 0.85)])
	elif style == SectionPlanScript.Style.STEPPED:
		_lathe(st, square, [Vector2(0.0, 1.0), Vector2(0.5, 1.0), Vector2(0.5, 0.8), Vector2(0.75, 0.8), Vector2(0.75, 0.6), Vector2(1.0, 0.6)])
	elif style == SectionPlanScript.Style.TAPERED:
		_lathe(st, octagon, [Vector2(0.0, 1.0), Vector2(0.88, 0.72), Vector2(0.88, 0.62), Vector2(1.0, 0.62)])
	elif style == SectionPlanScript.Style.RING_TOWER:
		# A full-width plinth ring at the base and one ring higher up: two
		# rings stay under 256 triangles (a third would not).
		_lathe(st, circle, [Vector2(0.0, 1.0), Vector2(0.06, 1.0), Vector2(0.06, 0.8), Vector2(0.55, 0.8), Vector2(0.55, 1.0), Vector2(0.6, 1.0), Vector2(0.6, 0.8), Vector2(1.0, 0.8)])
	elif style == SectionPlanScript.Style.FIN_SLAB:
		_lathe(st, _rect(-0.3, 0.3, -0.5, 0.5), [Vector2(0.0, 1.0), Vector2(1.0, 1.0)])
		for side in [-1.0, 1.0]:
			for z0 in [-0.42, 0.34]:
				var x0: float = 0.28 if side > 0.0 else -0.5
				_lathe(st, _rect(x0, x0 + 0.22, z0, z0 + 0.08), [Vector2(0.0, 1.0), Vector2(0.94, 1.0)])
	else:  # SPIRE
		_lathe(st, octagon, [Vector2(0.0, 1.0), Vector2(0.45, 0.78), Vector2(0.7, 0.55), Vector2(0.82, 0.35), Vector2(0.82, 0.06), Vector2(1.0, 0.04)])
	return st.commit()

# Regular polygon in the (x, z) plane, anticlockwise seen from above.
static func _polygon(sides: int, radius: float, turn: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in range(sides):
		var a: float = turn + TAU * k / sides
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points

# Rectangle in (x, z), same turning sense as _polygon.
static func _rect(x0: float, x1: float, z0: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x1, z1), Vector2(x0, z1), Vector2(x0, z0), Vector2(x1, z0)])

# Outline point p (x, z) at ring (height 0..1, scale), in the centred box.
static func _at(p: Vector2, ring: Vector2) -> Vector3:
	return Vector3(p.x * ring.y, ring.x - 0.5, p.y * ring.y)

static func _lathe(st: SurfaceTool, outline: PackedVector2Array, rings: Array) -> void:
	for r in range(rings.size() - 1):
		var low: Vector2 = rings[r]
		var high: Vector2 = rings[r + 1]
		for i in range(outline.size()):
			var p := outline[i]
			var q := outline[(i + 1) % outline.size()]
			var edge := q - p
			var out := Vector3(edge.y, 0.0, -edge.x).normalized()
			# Out as the profile climbs, up as it steps in, down as it steps out.
			var hint: Vector3 = out * (high.x - low.x) + Vector3.UP * (low.y - high.y) * ((p + q) * 0.5).length()
			_quad(st, _at(p, low), _at(q, low), _at(q, high), _at(p, high), hint)
	var top: Vector2 = rings[rings.size() - 1]
	if top.y > 1e-6:
		var centre := Vector2.ZERO
		for p in outline:
			centre += p
		centre /= outline.size()
		for i in range(outline.size()):
			_face(st, _at(centre, top), _at(outline[i], top), _at(outline[(i + 1) % outline.size()], top), Vector3.UP)

# A module lying along z: walls to half height, a half-round roof, flat ends.
static func _vault(st: SurfaceTool) -> void:
	var profile := PackedVector2Array([Vector2(-0.5, 0.0), Vector2(-0.5, 0.5)])
	for k in range(1, 7):
		var a: float = PI - k * PI / 6.0
		profile.append(Vector2(0.5 * cos(a), 0.5 + 0.5 * sin(a)))
	profile.append(Vector2(0.5, 0.0))
	for i in range(profile.size() - 1):
		var p := profile[i]
		var q := profile[i + 1]
		var hint := Vector3(-(q.y - p.y), q.x - p.x, 0.0)
		_quad(st, Vector3(p.x, p.y - 0.5, -0.5), Vector3(q.x, q.y - 0.5, -0.5), Vector3(q.x, q.y - 0.5, 0.5), Vector3(p.x, p.y - 0.5, 0.5), hint)
	for z in [-0.5, 0.5]:
		var centre := Vector3(0.0, -0.1, z)
		for i in range(profile.size()):
			var p := profile[i]
			var q := profile[(i + 1) % profile.size()]
			_face(st, centre, Vector3(p.x, p.y - 0.5, z), Vector3(q.x, q.y - 0.5, z), Vector3(0.0, 0.0, z))

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
	_face(st, a, b, c, hint)
	_face(st, a, c, d, hint)

# One flat triangle facing the `hint` side, wound as Godot expects (its
# normal opposite to (b - a) x (c - a)). Degenerate ones are skipped.
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length() < 1e-9:
		return
	var n := cross.normalized()
	if n.dot(hint) < 0.0:
		n = -n
	if cross.dot(n) > 0.0:
		var swap := b
		b = c
		c = swap
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)
