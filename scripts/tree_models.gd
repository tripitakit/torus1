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
const DETAIL := 250.0
# The last FADE metres before DETAIL the detailed tree dissolves into its
# impostor, pixel by pixel (the two take complementary pixels).
const FADE := 50.0
# The impostor atlases: a GRID x GRID of CELL-pixel cells, one per variant.
const IMPOSTOR_CELL := 256
const IMPOSTOR_GRID := 5
const IMPOSTOR_SIDE_PATH := "res://assets/trees/impostors_side.png"
const IMPOSTOR_TOP_PATH := "res://assets/trees/impostors_top.png"
# Each variant's average leaf colour (the bake's), for the far shapes.
const IMPOSTOR_COLOURS_PATH := "res://assets/trees/impostors.json"
# Beyond IMPOSTOR_FAR a tree is a few pixels: the impostor gives way to a
# simple opaque shape in its variant's colour, over the last FAR_FADE metres.
const IMPOSTOR_FAR := 3000.0
const FAR_FADE := 300.0
# The impostor's top card, this share of the tree's height up.
const IMPOSTOR_TOP_AT := 0.6

const BARK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool leaves = false;
uniform float detail_to = 500.0;
uniform float fade = 50.0;
varying flat float fade_t;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(origin, INV_VIEW_MATRIX[3].xyz);
	fade_t = clamp((d - (detail_to - fade)) / max(fade, 0.001), 0.0, 1.0);
	if (d > detail_to) {
		VERTEX = vec3(0.0);
	}
}
void fragment() {
	// Dissolving into the impostor: these pixels are its.
	if (fade_t > fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))))) {
		discard;
	}
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
uniform float fade = 50.0;
varying flat float fade_t;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(origin, INV_VIEW_MATRIX[3].xyz);
	fade_t = clamp((d - (detail_to - fade)) / max(fade, 0.001), 0.0, 1.0);
	if (d > detail_to) {
		VERTEX = vec3(0.0);
	}
}
void fragment() {
	// Dissolving into the impostor: these pixels are its.
	if (fade_t > fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))))) {
		discard;
	}
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

# The impostor: two upright crossed cards with the side view, one level card
# with the top view at IMPOSTOR_TOP_AT, sized and pictured per variant (the
# variant in the instance colour's red, its shade in the green); it takes
# over the pixels the detailed tree gives up within FADE of DETAIL, and is
# whole beyond.
const IMPOSTOR_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D side_atlas : source_color, filter_linear_mipmap;
uniform sampler2D top_atlas : source_color, filter_linear_mipmap;
uniform float side_sizes[25];
uniform float top_sizes[25];
uniform float detail_from = 350.0;
uniform float fade = 50.0;
uniform float far_from = 3000.0;
uniform float far_fade = 300.0;
varying flat float fade_t;
varying flat float far_t;
varying flat float is_top;
varying flat float shade;
varying vec3 tree_up;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(origin, INV_VIEW_MATRIX[3].xyz);
	fade_t = clamp((d - (detail_from - fade)) / max(fade, 0.001), 0.0, 1.0);
	far_t = clamp((d - (far_from - far_fade)) / max(far_fade, 0.001), 0.0, 1.0);
	int v = clamp(int(COLOR.r * 32.0 + 0.5), 0, 24);
	shade = COLOR.g;
	is_top = UV2.x;
	if (UV2.x > 0.5) {
		VERTEX.xz *= top_sizes[v];
	} else {
		VERTEX *= side_sizes[v];
	}
	UV = (vec2(float(v % 5), float(v / 5)) + UV) / 5.0;
	tree_up = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	if (d < detail_from - fade || d > far_from) {
		VERTEX = vec3(0.0);
	}
}
void fragment() {
	// The detailed tree's pixels while it dissolves near; the far shape's far.
	float h = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (fade_t <= h || far_t > h) {
		discard;
	}
	vec4 c = is_top > 0.5 ? texture(top_atlas, UV) : texture(side_atlas, UV);
	// Lit as a crown from above on either face (a card seen from behind
	// would otherwise turn its normal down, into the dark).
	NORMAL = tree_up;
	ALBEDO = c.rgb * shade;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
"""

# The far shapes (TreeShapes' far cone and crown): the variant's average leaf
# colour, lit; taking the pixels the impostor gives up past IMPOSTOR_FAR.
const FAR_SHADER := """
shader_type spatial;
uniform vec3 colours[25];
uniform vec3 trunk_color : source_color = vec3(0.36, 0.25, 0.16);
uniform float far_from = 3000.0;
uniform float far_fade = 300.0;
varying flat float far_t;
varying flat vec3 crown;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(origin, INV_VIEW_MATRIX[3].xyz);
	far_t = clamp((d - (far_from - far_fade)) / max(far_fade, 0.001), 0.0, 1.0);
	// The crown's vertices are white: COLOR is the instance's (variant in red,
	// shade in green). The trunk's take trunk_color in the fragment.
	int v = clamp(int(COLOR.r * 32.0 + 0.5), 0, 24);
	crown = colours[v] * COLOR.g;
	if (d < far_from - far_fade) {
		VERTEX = vec3(0.0);
	}
}
void fragment() {
	if (far_t <= fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))))) {
		discard;
	}
	ALBEDO = mix(trunk_color, crown, COLOR.a);
	ROUGHNESS = 0.9;
}
"""

static var _variants: Array = []
static var _far_material: ShaderMaterial
static var _impostor_mesh: ArrayMesh
static var _impostor_material: ShaderMaterial

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
	return variant_from(hash(Vector3i(roundi(origin.x * 10.0), roundi(origin.y * 10.0), roundi(origin.z * 10.0))), conifer, height)

# The same from a random `seed` (TerrainDressing's tree hash).
static func variant_from(seed: int, conifer: bool, height: float) -> int:
	var roll := float(seed & 0xFFFF) / 65536.0
	var pick := (seed >> 16) & 0xFFFF
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
	material.set_shader_parameter("fade", FADE)
	return material

# How much of a variant one impostor cell shows: Vector2(width of the square
# (both ways), height of its middle), the trunk's foot at the bottom middle
# of the side view and in the middle of the top view.
static func impostor_frame(mesh: ArrayMesh, top: bool) -> Vector2:
	var box := mesh.get_aabb()
	var half := maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
	if top:
		return Vector2(half * 2.0 * 1.06, 0.0)
	var span := maxf(1.0, half * 2.0) * 1.06
	return Vector2(span, span * 0.5)

# The share of a tree that is its impostor at distance `d` from the camera
# (0 within DETAIL - FADE, 1 from DETAIL on).
static func fade_share(d: float) -> float:
	return clampf((d - (DETAIL - FADE)) / FADE, 0.0, 1.0)

# The impostor's cards: unit tall, the foot at the origin (the shader sizes
# them per variant); UV2.x 1 on the top card.
static func impostor_mesh() -> ArrayMesh:
	if _impostor_mesh != null:
		return _impostor_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cards := [
		[Vector3(-0.5, 1.0, 0.0), Vector3(0.5, 1.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(-0.5, 0.0, 0.0), 0.0],
		[Vector3(0.0, 1.0, 0.5), Vector3(0.0, 1.0, -0.5), Vector3(0.0, 0.0, -0.5), Vector3(0.0, 0.0, 0.5), 0.0],
		[Vector3(-0.5, IMPOSTOR_TOP_AT, -0.5), Vector3(0.5, IMPOSTOR_TOP_AT, -0.5), Vector3(0.5, IMPOSTOR_TOP_AT, 0.5), Vector3(-0.5, IMPOSTOR_TOP_AT, 0.5), 1.0],
	]
	var uvs := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for card in cards:
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color.WHITE)
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(card[4], 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(card[k])
	_impostor_mesh = st.commit()
	return _impostor_mesh

static func impostor_material() -> ShaderMaterial:
	if _impostor_material != null:
		return _impostor_material
	var shader := Shader.new()
	shader.code = IMPOSTOR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("side_atlas", _atlas(IMPOSTOR_SIDE_PATH))
	material.set_shader_parameter("top_atlas", _atlas(IMPOSTOR_TOP_PATH))
	var side := PackedFloat32Array()
	var top := PackedFloat32Array()
	for v in variants():
		side.append(impostor_frame(v.mesh, false).x)
		top.append(impostor_frame(v.mesh, true).x)
	material.set_shader_parameter("side_sizes", side)
	material.set_shader_parameter("top_sizes", top)
	material.set_shader_parameter("detail_from", DETAIL)
	material.set_shader_parameter("fade", FADE)
	material.set_shader_parameter("far_from", IMPOSTOR_FAR)
	material.set_shader_parameter("far_fade", FAR_FADE)
	_impostor_material = material
	return _impostor_material

# An atlas from its raw PNG (as the models, no editor import), mipmapped (the
# bake has given the transparent pixels their nearest leaf's colour: far off
# the leaves keep their colour instead of darkening toward the black).
static func _atlas(path: String) -> ImageTexture:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		push_error("TreeModels: cannot read %s" % path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

# Transparent pixels coloured like their opaque neighbours, `passes` pixels
# out (the bake's).
static func bleed(image: Image, passes: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var data := image.get_data()
	for pass_index in range(passes):
		var next := data.duplicate()
		for y in range(h):
			for x in range(w):
				var i := (y * w + x) * 4
				if data[i + 3] > 0:
					continue
				for n: Vector2i in [Vector2i(x + 1, y), Vector2i(x - 1, y), Vector2i(x, y + 1), Vector2i(x, y - 1)]:
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
						continue
					var j := (n.y * w + n.x) * 4
					if data[j + 3] > 0 or (data[j] + data[j + 1] + data[j + 2]) > 0:
						next[i] = data[j]
						next[i + 1] = data[j + 1]
						next[i + 2] = data[j + 2]
						break
		data = next
	image.set_data(w, h, false, Image.FORMAT_RGBA8, data)

# The far shapes' material: each variant's colour from the bake.
static func far_material() -> ShaderMaterial:
	if _far_material != null:
		return _far_material
	var shader := Shader.new()
	shader.code = FAR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	var colours := PackedVector3Array()
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(IMPOSTOR_COLOURS_PATH))
	var parsed = JSON.parse_string(text)
	for k in range(25):
		var c: Array = parsed[k] if parsed is Array and k < parsed.size() else [0.2, 0.4, 0.15]
		colours.append(Vector3(c[0], c[1], c[2]))
	material.set_shader_parameter("colours", colours)
	material.set_shader_parameter("far_from", IMPOSTOR_FAR)
	material.set_shader_parameter("far_fade", FAR_FADE)
	_far_material = material
	return _far_material
