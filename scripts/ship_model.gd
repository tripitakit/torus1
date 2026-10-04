extends RefCounted

# The void-cruiser seen from outside: an Eagle transporter (Space: 1999), low
# poly, inside the collision box (VoidCruiser.HULL_SIZE, 15 x 7.5 x 30 m),
# nose -Z, its four feet on the box's bottom. On the ship-exterior layer:
# the pilot's camera never sees it. UV.x parts: 0 white hull, 1 dark
# (windows, doors, shock sleeves), 2 grey frame, 3 red-orange stripes,
# 4 engine glow (bright with thrust).

const RoadTraffic = preload("res://scripts/road_traffic.gd")
const CockpitScript = preload("res://scripts/cockpit.gd")

const FOOT_Y := -3.75
const SIDES := 8
# Thrust (m/s²) above which the engines glow.
const GLOW_THRUST := 0.05

const SHADER := """
shader_type spatial;
uniform float engines = 0.0;
varying float part;
void vertex() {
	part = UV.x;
}
void fragment() {
	vec3 colour = vec3(0.88, 0.88, 0.86);
	vec3 glow = vec3(0.0);
	float rough = 0.6;
	if (part > 0.5 && part < 1.5) {
		colour = vec3(0.06, 0.07, 0.08);
		rough = 0.2;
	} else if (part > 1.5 && part < 2.5) {
		colour = vec3(0.5, 0.52, 0.55);
	} else if (part > 2.5 && part < 3.5) {
		colour = vec3(0.85, 0.25, 0.08);
	} else if (part > 3.5) {
		colour = vec3(0.1);
		glow = vec3(1.0, 0.55, 0.2) * (0.15 + 3.0 * engines);
	}
	ALBEDO = colour;
	ROUGHNESS = rough;
	EMISSION = glow;
}
"""

static func mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Command module: an eight-sided nose cone on a short drum, a dark band
	# of windows round it.
	_cone_z(st, Vector2(0.0, 0.9), [[-14.9, 0.5], [-12.6, 1.9], [-10.0, 2.2], [-8.8, 2.0]], 0.0, true)
	_cone_z(st, Vector2(0.0, 0.9), [[-12.95, 1.78], [-12.25, 1.98]], 1.0, true)
	# Spine: two rails low and high each side, braces every 2.2 m.
	for side: float in [-1.0, 1.0]:
		_b(st, Vector3(side * 1.1, 0.5, -9.0), Vector3(side * 1.5, 0.9, 9.6), 2.0)
		_b(st, Vector3(side * 1.15, 1.9, -9.0), Vector3(side * 1.45, 2.2, 9.6), 2.0)
	for k in range(9):
		var z := -8.5 + k * 2.2
		_b(st, Vector3(-1.3, 0.5, z - 0.12), Vector3(1.3, 0.8, z + 0.12), 2.0)
		for side: float in [-1.0, 1.0]:
			_b(st, Vector3(side * 1.2, 0.9, z - 0.1), Vector3(side * 1.4, 1.9, z + 0.1), 2.0)
	# Passenger module under the spine: a red stripe and a door each side.
	_b(st, Vector3(-2.6, -1.9, -6.2), Vector3(2.6, 0.5, 6.2), 0.0)
	for side: float in [-1.0, 1.0]:
		_b(st, Vector3(side * 2.6, -0.55, -6.0), Vector3(side * 2.66, -0.25, 6.0), 3.0)
		_b(st, Vector3(side * 2.6, -1.5, -1.0), Vector3(side * 2.64, 0.1, 1.0), 1.0)
	# Side frames carrying the legs, arms out to them from the spine; each
	# leg a strut, a dark shock sleeve and a disc foot on the box's bottom.
	for side: float in [-1.0, 1.0]:
		_b(st, Vector3(side * 4.6, 0.4, -8.2), Vector3(side * 5.9, 1.1, 8.2), 0.0)
		_b(st, Vector3(side * 5.9, 0.6, -8.0), Vector3(side * 5.96, 0.9, 8.0), 3.0)
		for z: float in [-7.0, 7.0]:
			_b(st, Vector3(side * 1.5, 0.55, z - 0.25), Vector3(side * 4.6, 0.85, z + 0.25), 2.0)
			_b(st, Vector3(side * 5.25 - 0.22, -3.45, z - 0.22), Vector3(side * 5.25 + 0.22, 0.4, z + 0.22), 2.0)
			_b(st, Vector3(side * 5.25 - 0.32, -2.3, z - 0.32), Vector3(side * 5.25 + 0.32, -1.2, z + 0.32), 1.0)
			_cone_y(st, Vector3(side * 5.25, FOOT_Y, z), 0.9, 0.6, 0.3, 2.0)
	# Engines: a block behind the spine with a stripe, two tanks on top, four
	# nozzles, each with a glowing disc deep inside.
	_b(st, Vector3(-2.8, -0.9, 9.6), Vector3(2.8, 2.2, 12.6), 0.0)
	_b(st, Vector3(-2.84, 0.3, 9.6), Vector3(2.84, 0.6, 12.6), 3.0)
	for x: float in [-1.6, 1.6]:
		_cone_z(st, Vector2(x, 2.95), [[9.8, 0.3], [10.3, 0.75], [11.9, 0.75], [12.4, 0.3]], 0.0, true)
	for x: float in [-1.3, 1.3]:
		for y: float in [-0.1, 1.5]:
			_cone_z(st, Vector2(x, y), [[12.6, 0.45], [14.95, 0.85]], 2.0, false)
			_cone_z(st, Vector2(x, y), [[14.5, 0.0], [14.55, 0.78]], 4.0, true)
	st.index()
	return st.commit()

static func material() -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = SHADER
	return shader_material

# The model as `parent`'s child "Model", on the ship-exterior layer.
static func build(parent: Node3D) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = mesh()
	model.material_override = material()
	model.layers = CockpitScript.SHIP_EXTERIOR_LAYER
	parent.add_child(model)
	return model

static func engines_on(thrust: Vector3, landed: bool) -> bool:
	return not landed and thrust.length() > GLOW_THRUST

static func set_engines(model: MeshInstance3D, on: bool) -> void:
	(model.material_override as ShaderMaterial).set_shader_parameter("engines", 1.0 if on else 0.0)

# A box between any two opposite corners.
static func _b(st: SurfaceTool, a: Vector3, b: Vector3, part: float) -> void:
	RoadTraffic._box(st, a.min(b), a.max(b), part)

# Rings [z, radius] of SIDES corners round (centre.x, centre.y), joined by
# flat quads; `caps` closes both ends.
static func _cone_z(st: SurfaceTool, centre: Vector2, rings: Array, part: float, caps: bool) -> void:
	var points := []
	var middle := Vector3(centre.x, centre.y, 0.5 * (rings[0][0] + rings[-1][0]))
	for r in rings:
		var ring := []
		for i in range(SIDES):
			var angle := TAU * (i + 0.5) / SIDES
			ring.append(Vector3(centre.x + cos(angle) * r[1], centre.y + sin(angle) * r[1], r[0]))
		points.append(ring)
	for k in range(points.size() - 1):
		for i in range(SIDES):
			var j := (i + 1) % SIDES
			RoadTraffic._face(st, [points[k][i], points[k][j], points[k + 1][j], points[k + 1][i]], middle, part)
	if caps:
		RoadTraffic._face(st, points[0], middle, part)
		RoadTraffic._face(st, points[-1], middle, part)

# A short upright drum: radius r0 at `base`, r1 `height` above.
static func _cone_y(st: SurfaceTool, base: Vector3, r0: float, r1: float, height: float, part: float) -> void:
	var low := []
	var high := []
	for i in range(SIDES):
		var angle := TAU * (i + 0.5) / SIDES
		low.append(base + Vector3(cos(angle) * r0, 0.0, sin(angle) * r0))
		high.append(base + Vector3(cos(angle) * r1, height, sin(angle) * r1))
	var middle := base + Vector3(0.0, height * 0.5, 0.0)
	for i in range(SIDES):
		var j := (i + 1) % SIDES
		RoadTraffic._face(st, [low[i], low[j], high[j], high[i]], middle, part)
	RoadTraffic._face(st, low, middle, part)
	RoadTraffic._face(st, high, middle, part)
