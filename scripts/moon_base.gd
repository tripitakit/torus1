extends RefCounted

# Base Selene, after Space 1999's Moonbase Alpha: a command tower in a low
# round hub, rings of low sectors round it (some with domes, two long
# wedges reaching out), spokes out to six round pads each with a hangar,
# and thin masts tipped with spheres. Laid out on the base's tangent plane
# (x east, z south, metres from the tower; angles from +x toward +z), every
# piece then set on the sphere with its own vertical. Built under the moon
# as one static body (moon.gd).

const SectionPlanScript = preload("res://scripts/section_plan.gd")
const BuildingShapesScript = preload("res://scripts/building_shapes.gd")
const TerrainDressingScript = preload("res://scripts/terrain_dressing.gd")
const TorusStation = preload("res://scripts/torus_station.gd")

const TOWER_RADIUS := 20.0
const TOWER_HEIGHT := 60.0
const TUBE_WIDTH := 6.0
const PAD_RADIUS := 30.0
const PAD_HEIGHT := 2.0
# The pads' ring, and their angles (degrees): out past the outer ring's
# sectors and the wedges, pad 1 east.
const PAD_RING := 600.0
const PAD_ANGLES := [-2.5, 47.5, 117.5, 175.0, 227.5, 300.0]
const HANGAR_SIZE := Vector3(24.0, 10.0, 30.0)  # out, up, round
# The hangar beside its pad, round the ring (centre this far from the pad's).
const HANGAR_OFFSET := 55.0
# Sectors: [inner, outer, start, end (degrees), height, dome].
const HUB := [TOWER_RADIUS, 48.0, 0.0, 360.0, 4.0, false]
const SECTORS := [
	# Inner ring.
	[62.0, 130.0, 5.0, 55.0, 8.0, true],
	[62.0, 130.0, 65.0, 115.0, 8.0, false],
	[62.0, 130.0, 125.0, 175.0, 8.0, true],
	[62.0, 130.0, 185.0, 235.0, 8.0, false],
	[62.0, 130.0, 245.0, 295.0, 8.0, true],
	[62.0, 130.0, 305.0, 355.0, 8.0, true],
	# Middle ring, open where the wedges run.
	[145.0, 215.0, 20.0, 80.0, 7.0, true],
	[145.0, 215.0, 90.0, 150.0, 7.0, false],
	[145.0, 215.0, 200.0, 255.0, 7.0, true],
	[145.0, 215.0, 265.0, 330.0, 7.0, false],
	# Outer ring.
	[230.0, 290.0, 25.0, 70.0, 6.0, false],
	[230.0, 290.0, 95.0, 140.0, 6.0, true],
	[230.0, 290.0, 205.0, 250.0, 6.0, false],
	[230.0, 290.0, 275.0, 325.0, 6.0, true],
	# The long wedges.
	[145.0, 380.0, 160.0, 190.0, 9.0, true],
	[145.0, 340.0, 340.0, 375.0, 8.0, true],
]
const DOME_RADIUS := 10.0
# Masts: [angle (degrees), length]; 1.6 m thick, a TIP_RADIUS sphere on top.
# In the gaps between the sectors, clear of the spokes and pads.
const MASTS := [[60.0, 200.0], [85.0, 320.0], [155.0, 300.0], [195.0, 320.0], [260.0, 330.0], [335.0, 300.0]]
const MAST_WIDTH := 1.6
const TIP_RADIUS := 3.0
# Sectors sink this far into the ground (the surface curves under them).
const SINK := 0.5
# Sector meshes and colliders: one slice per this many degrees at most.
const SLICE := 4.0
const WHITE := Color(0.92, 0.93, 0.95)
const LIGHT_GREY := Color(0.78, 0.8, 0.83)
const TUBE_COLOR := Color(0.7, 0.72, 0.75)
const NUMBER_COLOR := Color(1.0, 0.96, 0.88)
# The beacon over the tower: a short white flash every second, never under
# BEACON_MIN_PIXELS, drawn at any distance (the station lamps' shader).
const BEACON_LIFT := 6.0
const BEACON_SIZE := 25.0
const BEACON_MIN_PIXELS := 4.0
const BEACON_COLOR := Color(1.0, 0.97, 0.85)
const BEACON_PERIOD := 1.0
const BEACON_ON_TIME := 0.15
# The sectors' skin: panelled roofs, walls with a band of lit windows.
const SECTOR_SHADER := """
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.84, 0.85, 0.87);

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 colour = base_color;
	if (local_normal.y > 0.7) {
		// Roof panels, 6 m, each a slightly different grey.
		vec2 cell = floor(local_pos.xz / 6.0);
		vec2 seam = abs(fract(local_pos.xz / 6.0) - 0.5);
		float tone = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		colour *= (0.9 + 0.12 * tone) * (1.0 - 0.3 * step(0.46, max(seam.x, seam.y)));
		ROUGHNESS = 0.7;
	} else {
		// UV: metres along the wall, metres up it.
		float band = step(2.0, UV.y) * step(UV.y, 3.2);
		float window = band * step(0.55, fract(UV.x / 4.0));
		colour *= 0.7;
		EMISSION = vec3(1.0, 0.95, 0.82) * window * 1.6;
		ROUGHNESS = 0.8;
	}
	ALBEDO = colour;
}
"""
# A pad's top: grey, a darker rim, an orange cross.
const PAD_SHADER := """
shader_type spatial;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos.xz / 30.0;
	float r = length(p);
	vec3 colour = vec3(0.55, 0.56, 0.58);
	if (r > 0.9) {
		colour = vec3(0.3, 0.31, 0.33);
	} else if (min(abs(p.x), abs(p.y)) < 0.12 && r < 0.75) {
		colour = vec3(0.85, 0.42, 0.12);
	}
	ALBEDO = colour;
	ROUGHNESS = 0.8;
}
"""

# Every piece: {kind, name, centre (x, z), size (along, up, across), angle
# (radians: the length's direction), number (pads)}; a sector: {kind, name,
# inner, outer, start, end (degrees), height, dome}.
static func layout() -> Array:
	var pieces := []
	pieces.append({"kind": "tower", "name": "Tower", "centre": Vector2.ZERO, "size": Vector3(TOWER_RADIUS * 2.0, TOWER_HEIGHT, TOWER_RADIUS * 2.0), "angle": 0.0, "number": 0})
	pieces.append(_sector("Hub", HUB))
	for i in range(SECTORS.size()):
		pieces.append(_sector("Sector%d" % (i + 1), SECTORS[i]))
	for i in range(PAD_ANGLES.size()):
		var number := i + 1
		var angle := deg_to_rad(PAD_ANGLES[i])
		var out := Vector2.from_angle(angle)
		var centre := out * PAD_RING
		pieces.append({"kind": "pad", "name": "Pad%d" % number, "centre": centre, "size": Vector3(PAD_RADIUS * 2.0, PAD_HEIGHT, PAD_RADIUS * 2.0), "angle": angle, "number": number})
		pieces.append(_tube("Spoke%d" % number, angle, Vector2.ZERO, outer_reach(PAD_ANGLES[i]), PAD_RING - PAD_RADIUS))
		# The hangar beside the pad, round the ring (counter-clockwise), a
		# short tube between.
		var round_way := out.orthogonal()
		var hangar_centre := centre - round_way * HANGAR_OFFSET
		pieces.append({"kind": "hangar", "name": "Hangar%d" % number, "centre": hangar_centre, "size": HANGAR_SIZE, "angle": angle, "number": number})
		pieces.append(_tube("HangarTube%d" % number, (-round_way).angle(), centre, PAD_RADIUS, HANGAR_OFFSET - HANGAR_SIZE.z * 0.5))
	for i in range(MASTS.size()):
		var angle: float = MASTS[i][0]
		var from := outer_reach(angle)
		pieces.append({"kind": "mast", "name": "Mast%d" % (i + 1), "centre": Vector2.from_angle(deg_to_rad(angle)) * (from + MASTS[i][1] * 0.5), "size": Vector3(MASTS[i][1], MAST_WIDTH, MAST_WIDTH), "angle": deg_to_rad(angle), "number": 0})
	return pieces

static func _sector(sector_name: String, row: Array) -> Dictionary:
	return {"kind": "sector", "name": sector_name, "inner": row[0], "outer": row[1], "start": row[2], "end": row[3], "height": row[4], "dome": row[5]}

# A tube from `from` to `to` metres out of `origin` toward `angle`.
static func _tube(tube_name: String, angle: float, origin: Vector2, from: float, to: float) -> Dictionary:
	var centre := origin + Vector2.from_angle(angle) * (from + to) * 0.5
	return {"kind": "tube", "name": tube_name, "centre": centre, "size": Vector3(to - from, TUBE_WIDTH, TUBE_WIDTH), "angle": angle, "number": 0}

# How far out the farthest sector reaches toward `degrees`.
static func outer_reach(degrees: float) -> float:
	var reach := HUB[1] as float
	for row in SECTORS:
		var into := fposmod(degrees - row[2], 360.0)
		if into > 0.0 and into < row[3] - row[2]:
			reach = maxf(reach, row[1])
	return reach

# Pads 1-6 in order.
static func pad_centres() -> Array[Vector2]:
	var centres: Array[Vector2] = []
	centres.resize(6)
	for piece in layout():
		if piece.kind == "pad":
			centres[piece.number - 1] = piece.centre
	return centres

# The ground under tangent point (x, z) in the base's frame (origin on the
# surface at the tower, y the local up there), and the local vertical.
static func ground(x: float, z: float, radius: float) -> Transform3D:
	var height: float = sqrt(radius * radius - x * x - z * z)
	var up := Vector3(x, height, z) / radius
	return Transform3D(Basis(Quaternion(Vector3.UP, up)), Vector3(x, height - radius, z))

# A piece's transform in the base's frame: centred at half its height
# above the ground, with the local vertical, its x along its angle.
static func piece_transform(piece: Dictionary, radius: float) -> Transform3D:
	var at := ground(piece.centre.x, piece.centre.y, radius)
	var turned := at.basis * Basis(Vector3.UP, -piece.get("angle", 0.0))
	return Transform3D(turned, at.origin + at.basis.y * piece.size.y * 0.5)

# Builds meshes and colliders into `base` (the moon's Base body).
static func build(base: StaticBody3D, radius: float) -> void:
	var building_material := ShaderMaterial.new()
	var building_shader := Shader.new()
	building_shader.code = TerrainDressingScript.BUILDING_SHADER
	building_material.shader = building_shader
	building_material.set_shader_parameter("glow_energy", TerrainDressingScript.BUILDING_GLOW_ENERGY)
	var tube_material := StandardMaterial3D.new()
	tube_material.albedo_color = TUBE_COLOR
	tube_material.roughness = 0.6
	tube_material.metallic = 0.3
	var sector_material := ShaderMaterial.new()
	var sector_shader := Shader.new()
	sector_shader.code = SECTOR_SHADER
	sector_material.shader = sector_shader
	var dome_material := StandardMaterial3D.new()
	dome_material.albedo_color = WHITE
	dome_material.roughness = 0.35
	dome_material.metallic = 0.2
	var lamp_mesh := QuadMesh.new()
	lamp_mesh.size = Vector2.ONE
	var lamp_material := ShaderMaterial.new()
	var lamp_shader := Shader.new()
	lamp_shader.code = TorusStation.LAMP_SHADER
	lamp_material.shader = lamp_shader
	lamp_material.set_shader_parameter("lamp_size", TorusStation.LAMP_SIZE)
	lamp_material.set_shader_parameter("min_pixels", TorusStation.LAMP_MIN_PIXELS)
	lamp_material.set_shader_parameter("lamp_color", TorusStation.LAMP_COLOR)
	lamp_material.set_shader_parameter("period", TorusStation.LAMP_PERIOD)
	lamp_material.set_shader_parameter("on_time", TorusStation.LAMP_ON_TIME)
	var pad_material := ShaderMaterial.new()
	var pad_shader := Shader.new()
	pad_shader.code = PAD_SHADER
	pad_material.shader = pad_shader
	var buildings := {SectionPlanScript.Style.RING_TOWER: [], SectionPlanScript.Style.BLOCK: []}
	var sectors := SurfaceTool.new()
	sectors.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = DOME_RADIUS
	dome_mesh.height = DOME_RADIUS
	dome_mesh.is_hemisphere = true
	dome_mesh.radial_segments = 24
	dome_mesh.rings = 8
	for piece in layout():
		if piece.kind == "sector":
			_add_sector(piece, radius, sectors, base)
			if piece.dome:
				base.add_child(_dome(piece, radius, dome_mesh, dome_material))
			continue
		var where := piece_transform(piece, radius)
		var collision := CollisionShape3D.new()
		collision.name = piece.name + "Collider"
		collision.transform = where
		match piece.kind:
			"tower":
				collision.shape = _tower_shape()
				buildings[SectionPlanScript.Style.RING_TOWER].append([where, piece])
			"hangar":
				collision.shape = _box(piece.size)
				buildings[SectionPlanScript.Style.BLOCK].append([where, piece])
			"tube", "mast":
				collision.shape = _box(piece.size)
				base.add_child(_tube_mesh(piece, where, tube_material))
				if piece.kind == "mast":
					base.add_child(_mast_tip(piece, where, dome_material))
			"pad":
				var cylinder := CylinderShape3D.new()
				cylinder.radius = PAD_RADIUS
				cylinder.height = PAD_HEIGHT
				collision.shape = cylinder
				base.add_child(_pad(piece, where, lamp_mesh, lamp_material, pad_material))
		base.add_child(collision)
	var sector_node := MeshInstance3D.new()
	sector_node.name = "Sectors"
	sector_node.mesh = sectors.commit()
	sector_node.material_override = sector_material
	base.add_child(sector_node)
	for style in buildings:
		base.add_child(_buildings(style, buildings[style], building_material))
	base.add_child(_beacon(lamp_mesh, radius))

# The ground's height under (x, z) in the base's frame.
static func _ground_y(x: float, z: float, radius: float) -> float:
	return sqrt(radius * radius - x * x - z * z) - radius

# A sector's walls and roof into `mesh` (in the base's frame), and its
# colliders into `base`: one convex slice every SLICE degrees at most.
static func _add_sector(piece: Dictionary, radius: float, mesh: SurfaceTool, base: StaticBody3D) -> void:
	var span: float = piece.end - piece.start
	var slices := maxi(1, ceili(span / SLICE))
	var corners := []
	for k in range(slices + 1):
		var a := deg_to_rad(piece.start + span * k / slices)
		var out := Vector2.from_angle(a)
		var row := []
		for r in [piece.inner, piece.outer]:
			var p: Vector2 = out * r
			var y := _ground_y(p.x, p.y, radius)
			row.append([Vector3(p.x, y - SINK, p.y), Vector3(p.x, y + piece.height, p.y)])
		corners.append(row)
	for k in range(slices):
		var a0: Array = corners[k]
		var a1: Array = corners[k + 1]
		var mid := deg_to_rad(piece.start + span * (k + 0.5) / slices)
		var out := Vector3(cos(mid), 0.0, sin(mid))
		var inner_len: float = piece.inner * deg_to_rad(span) * k / slices
		var outer_len: float = piece.outer * deg_to_rad(span) * k / slices
		var inner_step: float = piece.inner * deg_to_rad(span) / slices
		var outer_step: float = piece.outer * deg_to_rad(span) / slices
		# Roof.
		_quad(mesh, a0[0][1], a1[0][1], a1[1][1], a0[1][1], Vector3.UP, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		# Outer wall, inner wall (UV: along, up).
		_quad(mesh, a0[1][0], a0[1][1], a1[1][1], a1[1][0], out, [Vector2(outer_len, 0.0), Vector2(outer_len, piece.height + SINK), Vector2(outer_len + outer_step, piece.height + SINK), Vector2(outer_len + outer_step, 0.0)])
		_quad(mesh, a1[0][0], a1[0][1], a0[0][1], a0[0][0], -out, [Vector2(inner_len + inner_step, 0.0), Vector2(inner_len + inner_step, piece.height + SINK), Vector2(inner_len, piece.height + SINK), Vector2(inner_len, 0.0)])
		var collision := CollisionShape3D.new()
		collision.name = "%sCollider%d" % [piece.name, k]
		var hull := ConvexPolygonShape3D.new()
		hull.points = PackedVector3Array([a0[0][0], a0[0][1], a0[1][0], a0[1][1], a1[0][0], a1[0][1], a1[1][0], a1[1][1]])
		collision.shape = hull
		base.add_child(collision)
	# The two ends, unless the sector closes round.
	if span < 360.0:
		var depth: float = piece.outer - piece.inner
		var first: Array = corners[0]
		var last: Array = corners[slices]
		var start_dir := Vector3(-sin(deg_to_rad(piece.start)), 0.0, cos(deg_to_rad(piece.start)))
		var end_dir := Vector3(-sin(deg_to_rad(piece.end)), 0.0, cos(deg_to_rad(piece.end)))
		_quad(mesh, first[1][0], first[1][1], first[0][1], first[0][0], -start_dir, [Vector2(depth, 0.0), Vector2(depth, piece.height + SINK), Vector2(0.0, piece.height + SINK), Vector2.ZERO])
		_quad(mesh, last[0][0], last[0][1], last[1][1], last[1][0], end_dir, [Vector2.ZERO, Vector2(0.0, piece.height + SINK), Vector2(depth, piece.height + SINK), Vector2(depth, 0.0)])

# Two triangles a-b-c, a-c-d facing `normal`.
static func _quad(mesh: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uvs: Array) -> void:
	var points := [a, b, c, d]
	# Wind them so the front faces `normal` (Godot: clockwise from the front).
	var order := [0, 1, 2, 0, 2, 3]
	if (b - a).cross(c - a).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		mesh.set_normal(normal)
		mesh.set_uv(uvs[i])
		mesh.add_vertex(points[i])

# A dome on the middle of a sector's roof, solid.
static func _dome(piece: Dictionary, radius: float, mesh: SphereMesh, material: Material) -> Node3D:
	var mid := deg_to_rad((piece.start + piece.end) * 0.5)
	var p: Vector2 = Vector2.from_angle(mid) * (piece.inner + piece.outer) * 0.5
	var at := ground(p.x, p.y, radius)
	var dome := MeshInstance3D.new()
	dome.name = piece.name + "Dome"
	dome.mesh = mesh
	dome.material_override = material
	dome.transform = Transform3D(at.basis, at.origin + at.basis.y * (piece.height + DOME_RADIUS * 0.5 - 0.5))
	var collision := CollisionShape3D.new()
	collision.name = piece.name + "ColliderDome"
	var sphere := SphereShape3D.new()
	sphere.radius = DOME_RADIUS
	collision.shape = sphere
	collision.transform = Transform3D(at.basis, at.origin + at.basis.y * (piece.height - 0.5))
	var holder := Node3D.new()
	holder.name = piece.name + "DomeParts"
	holder.add_child(dome)
	holder.add_child(collision)
	return holder

# The sphere on a mast's outer end.
static func _mast_tip(piece: Dictionary, where: Transform3D, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = TIP_RADIUS
	sphere.height = TIP_RADIUS * 2.0
	var tip := MeshInstance3D.new()
	tip.name = piece.name + "Tip"
	tip.mesh = sphere
	tip.material_override = material
	tip.transform = Transform3D(where.basis, where.origin + where.basis.x.normalized() * piece.size.x * 0.5)
	return tip

static func _beacon(lamp_mesh: QuadMesh, radius: float) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = TorusStation.LAMP_SHADER
	material.shader = shader
	material.set_shader_parameter("lamp_size", BEACON_SIZE)
	material.set_shader_parameter("min_pixels", BEACON_MIN_PIXELS)
	material.set_shader_parameter("lamp_color", BEACON_COLOR)
	material.set_shader_parameter("period", BEACON_PERIOD)
	material.set_shader_parameter("on_time", BEACON_ON_TIME)
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	beacon.mesh = lamp_mesh
	beacon.material_override = material
	var top := ground(0.0, 0.0, radius)
	beacon.position = top.origin + top.basis.y * (TOWER_HEIGHT + BEACON_LIFT)
	# The quad grows with distance in the shader: never cull it by its 1 m box.
	beacon.extra_cull_margin = 16384.0
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return beacon

static func _box(size: Vector3) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = size
	return box

# The tower's hexagonal prism (its unit mesh scaled to the tower's size).
static func _tower_shape() -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for p in BuildingShapesScript.hull_points(SectionPlanScript.Style.RING_TOWER):
		points.append(p * Vector3(TOWER_RADIUS * 2.0, TOWER_HEIGHT, TOWER_RADIUS * 2.0))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape

# One MultiMesh of `style` for the tower or the modules and hangars, with
# the interior's facade shader: window bands, cool white light.
static func _buildings(style: int, entries: Array, material: ShaderMaterial) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = BuildingShapesScript.mesh(style)
	multimesh.instance_count = entries.size()
	for i in range(entries.size()):
		var where: Transform3D = entries[i][0]
		var piece: Dictionary = entries[i][1]
		multimesh.set_instance_transform(i, Transform3D(where.basis.scaled_local(piece.size), where.origin))
		multimesh.set_instance_color(i, WHITE if piece.kind != "hangar" else LIGHT_GREY)
		# Facade 0 (bands), accent 1 (cool white), 60% lit, a seed.
		multimesh.set_instance_custom_data(i, Color(0.0, 1.0, 0.6, fposmod(i * 0.618034, 1.0)))
	var node := MultiMeshInstance3D.new()
	node.name = BuildingShapesScript.NAMES[style]
	node.multimesh = multimesh
	node.material_override = material
	node.custom_aabb = AABB(Vector3(-900.0, -60.0, -900.0), Vector3(1800.0, 140.0, 1800.0))
	return node

# A tube (or a mast) as a cylinder along its local x.
static func _tube_mesh(piece: Dictionary, where: Transform3D, material: Material) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.height = piece.size.x
	cylinder.top_radius = piece.size.y * 0.5
	cylinder.bottom_radius = piece.size.y * 0.5
	cylinder.radial_segments = 12
	var node := MeshInstance3D.new()
	node.name = piece.name
	node.mesh = cylinder
	node.material_override = material
	# The cylinder stands along y: lay it along x.
	node.transform = Transform3D(where.basis * Basis(Vector3.BACK, PI * 0.5), where.origin)
	return node

# A round pad: a 2 m disc with an orange cross, four blinking lamps round
# its rim and its number lying on it.
static func _pad(piece: Dictionary, where: Transform3D, lamp_mesh: QuadMesh, lamp_material: ShaderMaterial, pad_material: ShaderMaterial) -> Node3D:
	var pad := Node3D.new()
	pad.name = piece.name
	pad.transform = where
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = PAD_RADIUS
	cylinder.bottom_radius = PAD_RADIUS
	cylinder.height = PAD_HEIGHT
	cylinder.radial_segments = 48
	disc.mesh = cylinder
	disc.material_override = pad_material
	pad.add_child(disc)
	var top: float = PAD_HEIGHT * 0.5
	for k in range(4):
		var a := PI * 0.25 + PI * 0.5 * k
		var lamp := MeshInstance3D.new()
		lamp.name = "Lamp_%d" % k
		lamp.mesh = lamp_mesh
		lamp.material_override = lamp_material
		lamp.position = Vector3(cos(a), 0.0, sin(a)) * PAD_RADIUS * 0.82 + Vector3(0.0, top + 0.5, 0.0)
		lamp.visibility_range_end = TorusStation.LAMP_RANGE
		lamp.extra_cull_margin = TorusStation.LAMP_CULL_MARGIN
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pad.add_child(lamp)
	var number := Label3D.new()
	number.name = "Number"
	number.text = str(piece.number)
	number.font_size = 256
	number.pixel_size = 0.04
	number.modulate = NUMBER_COLOR
	number.shaded = false
	# Lying on the pad in a quarter of the cross, readable from above.
	number.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(PAD_RADIUS * 0.4, top + 0.3, PAD_RADIUS * 0.4))
	pad.add_child(number)
	return pad
