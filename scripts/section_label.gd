extends RefCounted

# Station identification stencilled on each section's outer hull (see
# torus_station.gd): "T1-0001" up to "T1-<num_sections>", at 4 points round
# the circumference (every 90 degrees), reading along the section's length
# with each character upright (its own "up" the circumferential tangent)
# and facing outward. Drawn as MultiMesh instances sampling a shared glyph
# atlas (tools/labels/build_label_atlas.py): one curved strip per character,
# its atlas cell picked per instance through the MultiMesh's custom data.

const GLYPHS := "0123456789T-"
const ATLAS_COLS := 4
const ATLAS_ROWS := 3
# Angles round the circumference the label repeats at.
const ANGLES: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]

# "T1-0001" for section index 0, up to "T1-<num_sections>" for the last.
static func format_id(section_index: int) -> String:
	return "T1-%04d" % (section_index + 1)

# The glyph's cell in the shared atlas, normalized (u, v, width, height).
static func glyph_uv(glyph: String) -> Rect2:
	var index := GLYPHS.find(glyph)
	var col := index % ATLAS_COLS
	var row := index / ATLAS_COLS
	var w := 1.0 / ATLAS_COLS
	var h := 1.0 / ATLAS_ROWS
	return Rect2(col * w, row * h, w, h)

# A unit-width glyph surface bent round a cylinder. Y stays normalized so
# the instance transform can scale it to `char_height`; Z is the physical
# radial offset from the tangent point. The bottom-to-top rows keep every
# vertex at exactly `surface_radius` from the cylinder's axis.
static func build_curved_glyph_mesh(surface_radius: float, char_height: float, segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in range(segments + 1):
		var fraction := float(row) / segments
		var centred := fraction - 0.5
		var angle := centred * char_height / surface_radius
		var tangent_offset := sin(angle) * surface_radius / char_height
		var radial_offset := cos(angle) * surface_radius - surface_radius
		vertices.append(Vector3(-0.5, tangent_offset, radial_offset))
		vertices.append(Vector3(0.5, tangent_offset, radial_offset))
		uvs.append(Vector2(0.0, 1.0 - fraction))
		uvs.append(Vector2(1.0, 1.0 - fraction))
	for row in range(segments):
		var bottom_left := row * 2
		var bottom_right := bottom_left + 1
		var top_left := bottom_left + 2
		var top_right := bottom_left + 3
		indices.append_array(PackedInt32Array([
			bottom_left, bottom_right, top_right,
			bottom_left, top_right, top_left,
		]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# One entry per character of `text`: {"transform": Transform3D, "uv": Rect2}.
# The string is centred along the cylinder's axis (local Y) at `angle` round
# it (local Y is the axis, XZ the circle — see torus_station.gd's pad-normal
# convention). Each character's local X reads towards local -Y (screen-right
# for an outside observer), its Y is "up" along the circumferential tangent,
# and Z faces outward. X and Y carry the character's size; the shared mesh
# supplies the cylindrical depth.
static func label_instances(text: String, angle: float, surface_radius: float, char_width: float, char_height: float, spacing: float) -> Array:
	var outward := Vector3(sin(angle), 0.0, cos(angle))
	var tangent := Vector3(cos(angle), 0.0, -sin(angle))
	var right := Vector3(0.0, -1.0, 0.0)
	var basis := Basis(right * char_width, tangent * char_height, outward)
	var origin := outward * surface_radius
	var step := char_width + spacing
	var total := text.length() * char_width + (text.length() - 1) * spacing
	var start := -total * 0.5 + char_width * 0.5
	var instances := []
	for i in range(text.length()):
		var y: float = start + i * step
		instances.append({
			"transform": Transform3D(basis, origin + right * y),
			"uv": glyph_uv(text[i]),
		})
	return instances
