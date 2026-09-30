extends RefCounted

# Two low-poly trees as unit meshes: base at y = 0, top at y = 1, about 0.7
# wide, flat-shaded, faces outward. Vertex colour: the trunk brown with
# alpha 0, the crown white with alpha 1; the tree shader paints the crown in
# each instance's own green (terrain_dressing.gd).

const TRUNK_COLOR := Color(0.36, 0.25, 0.16, 0.0)
const CROWN_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SIDES := 7

# Two stacked cones on a short trunk.
static func conifer() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(st, [Vector2(0.0, 0.04), Vector2(0.22, 0.04)], TRUNK_COLOR)
	_lathe(st, [Vector2(0.15, 0.0), Vector2(0.15, 0.3), Vector2(0.75, 0.0)], CROWN_COLOR)
	_lathe(st, [Vector2(0.45, 0.0), Vector2(0.45, 0.21), Vector2(1.0, 0.0)], CROWN_COLOR)
	return st.commit()

# A faceted round crown on a taller trunk.
static func broadleaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(st, [Vector2(0.0, 0.05), Vector2(0.42, 0.05)], TRUNK_COLOR)
	_lathe(st, [Vector2(0.3, 0.0), Vector2(0.48, 0.3), Vector2(0.75, 0.36), Vector2(0.92, 0.22), Vector2(1.0, 0.0)], CROWN_COLOR)
	return st.commit()

# Turns a profile of Vector2(height, radius) points, bottom to top, round
# the y axis in SIDES flat faces. A radius of 0 closes the shape at that
# height: an apex, or the centre of a bottom disc.
static func _lathe(st: SurfaceTool, profile: Array, color: Color) -> void:
	for k in range(profile.size() - 1):
		var a: Vector2 = profile[k]
		var b: Vector2 = profile[k + 1]
		# Outward normal of the profile segment, as (radial, vertical).
		var out := Vector2(b.x - a.x, -(b.y - a.y))
		for i in range(SIDES):
			var t0: float = TAU * i / SIDES
			var t1: float = TAU * (i + 1) / SIDES
			var p00 := Vector3(cos(t0) * a.y, a.x, sin(t0) * a.y)
			var p10 := Vector3(cos(t1) * a.y, a.x, sin(t1) * a.y)
			var p01 := Vector3(cos(t0) * b.y, b.x, sin(t0) * b.y)
			var p11 := Vector3(cos(t1) * b.y, b.x, sin(t1) * b.y)
			var mid: float = (t0 + t1) * 0.5
			var outward := Vector3(cos(mid) * out.x, out.y, sin(mid) * out.x)
			if a.y > 0.0:
				_triangle(st, p00, p10, p01, outward, color)
			if b.y > 0.0:
				_triangle(st, p10, p11, p01, outward, color)

# One flat triangle, wound so its front (Godot's winding) faces `outward`.
static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a)
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	for p in [a, b, c]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(p)
