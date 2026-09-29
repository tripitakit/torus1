extends RefCounted

# Station identification stencilled on each section's outer hull (see
# torus_station.gd): "T1-0001" up to "T1-<num_sections>", at 4 points round
# the circumference (every 90 degrees), reading along the section's length
# with each character upright (its own "up" the circumferential tangent)
# and facing outward. Drawn as MultiMesh instances sampling a shared glyph
# atlas (tools/labels/build_label_atlas.py): one quad per character, its
# atlas cell picked per instance through the MultiMesh's custom data.

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

# One entry per character of `text`: {"transform": Transform3D, "uv": Rect2}.
# The string is centred along the cylinder's axis (local Y) at `angle` round
# it (local Y is the axis, XZ the circle — see torus_station.gd's pad-normal
# convention). Each character's local X reads along the axis, Y is its own
# "up" (the circumferential tangent at that angle), Z faces outward (the
# surface normal there); X and Y carry the character's size, so the mesh
# itself only needs to be a unit quad.
static func label_instances(text: String, angle: float, surface_radius: float, char_width: float, char_height: float, spacing: float) -> Array:
	var outward := Vector3(sin(angle), 0.0, cos(angle))
	var tangent := Vector3(cos(angle), 0.0, -sin(angle))
	var axial := Vector3(0.0, 1.0, 0.0)
	var basis := Basis(axial * char_width, tangent * char_height, outward)
	var origin := outward * surface_radius
	var step := char_width + spacing
	var total := text.length() * char_width + (text.length() - 1) * spacing
	var start := -total * 0.5 + char_width * 0.5
	var instances := []
	for i in range(text.length()):
		var y: float = start + i * step
		instances.append({
			"transform": Transform3D(basis, origin + axial * y),
			"uv": glyph_uv(text[i]),
		})
	return instances
