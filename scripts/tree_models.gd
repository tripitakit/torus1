extends RefCounted

# Quaternius' low poly trees (CC0, poly.pizza): pines, birches, maples,
# "normal" trees and dead trees, five variants each, read from the raw glTF
# at run time. Each variant one unit tall with its trunk's foot on the origin
# (an instance scales it to the tree's height), bark and leaves in our own
# shader: leaves cut out by their texture, and the whole tree hidden beyond
# `detail_to` from the camera (the simple far shapes take over there).

const KINDS := ["pine", "birch", "maple", "normal", "dead"]
const PATH := "res://assets/trees/%s.glb"
# Broadleaves near the treeline: this share of them dead, from this height.
const DEAD_SHARE := 0.05
const DEAD_FROM := 450.0
const DETAIL := 350.0

const BARK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool leaves = false;
uniform float detail_to = 500.0;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (distance(origin, INV_VIEW_MATRIX[3].xyz) > detail_to) {
		VERTEX = vec3(0.0);
	}
}
void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = texture(albedo_tex, UV).rgb;
	ROUGHNESS = 0.9;
}
"""

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool leaves = true;
uniform float detail_to = 500.0;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (distance(origin, INV_VIEW_MATRIX[3].xyz) > detail_to) {
		VERTEX = vec3(0.0);
	}
}
void fragment() {
	// Seen from behind, a leaf is lit as from in front.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
"""

static var _variants: Array = []

# [{kind, index, mesh}], pines first, then birches, maples, normals, dead.
static func variants() -> Array:
	if not _variants.is_empty():
		return _variants
	var out := []
	var shaders := {}
	for kind: String in KINDS:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(PATH % kind, state) != OK:
			push_error("TreeModels: cannot read %s" % (PATH % kind))
			continue
		var root := document.generate_scene(state)
		var found := root.find_children("*", "MeshInstance3D", true, false)
		found.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
		for k in range(found.size()):
			out.append({"kind": kind, "index": k, "mesh": _normalised(found[k] as MeshInstance3D, root, shaders)})
		root.free()
	_variants = out
	return _variants

# The variant (index into variants()) of a tree standing at `origin` (any
# frame: only its digits matter), a conifer or not, `height` above the floor.
static func variant_for(origin: Vector3, conifer: bool, height: float) -> int:
	var h := hash(Vector3i(roundi(origin.x * 10.0), roundi(origin.y * 10.0), roundi(origin.z * 10.0)))
	var roll := float(h & 0xFFFF) / 65536.0
	var pick := (h >> 16) & 0xFFFF
	if conifer:
		return pick % 5
	if height > DEAD_FROM and roll < DEAD_SHARE * 2.0 * (height - DEAD_FROM) / (height - DEAD_FROM + 50.0):
		return 20 + pick % 5
	return 5 + pick % 15

static func _normalised(node: MeshInstance3D, root: Node, shaders: Dictionary) -> ArrayMesh:
	var place := Transform3D()
	var n: Node = node
	while n != root:
		place = (n as Node3D).transform * place
		n = n.get_parent()
	# Height and the trunk's foot (the lowest points' middle) of the placed mesh.
	var low := INF
	var high := -INF
	for s in range(node.mesh.get_surface_count()):
		for p: Vector3 in node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var at := place * p
			low = minf(low, at.y)
			high = maxf(high, at.y)
	var height := high - low
	var foot := Vector2.ZERO
	var count := 0
	for s in range(node.mesh.get_surface_count()):
		for p: Vector3 in node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var at := place * p
			if at.y < low + height * 0.02:
				foot += Vector2(at.x, at.z)
				count += 1
	foot /= maxf(count, 1)
	var unit := Transform3D(Basis().scaled(Vector3.ONE / height), Vector3.ZERO) * Transform3D(Basis(), Vector3(-foot.x, -low, -foot.y)) * place
	var mesh := ArrayMesh.new()
	for s in range(node.mesh.get_surface_count()):
		var arrays: Array = node.mesh.surface_get_arrays(s)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(points.size()):
			points[i] = unit * points[i]
			if i < normals.size():
				normals[i] = (place.basis * normals[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(s, _material(node.mesh.surface_get_material(s), shaders))
	return mesh

# Our shader on the glTF material's texture; leaves (cut out) when the
# glTF material had any transparency.
static func _material(source: Material, shaders: Dictionary) -> ShaderMaterial:
	var base := source as BaseMaterial3D
	var leafy := base != null and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	var key := "leaves" if leafy else "bark"
	if not shaders.has(key):
		var shader := Shader.new()
		shader.code = LEAF_SHADER if leafy else BARK_SHADER
		shaders[key] = shader
	var material := ShaderMaterial.new()
	material.shader = shaders[key]
	material.set_shader_parameter("albedo_tex", base.albedo_texture if base != null else null)
	material.set_shader_parameter("leaves", leafy)
	material.set_shader_parameter("detail_to", DETAIL)
	return material
