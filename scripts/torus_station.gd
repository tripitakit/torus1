@tool
extends Node3D

const TorusGeometry = preload("res://scripts/torus_geometry.gd")
const DockPadTexture = preload("res://scripts/dock_pad_texture.gd")
const SectionLabelScript = preload("res://scripts/section_label.gd")

@export var planet_radius: float = 1737400.0
@export var orbit_altitude: float = 5212200.0
@export var num_sections: int = 2000
@export var section_radius: float = 2000.0
@export var section_length: float = 20000.0
@export var target_gravity_g: float = 0.7
@export var planet_node: NodePath = NodePath("")

@export_tool_button("Rebuild Station")
var rebuild_action: Callable = build_station

func _ready() -> void:
	build_station()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_rotate_sections(delta)

func _rotate_sections(delta: float) -> void:
	# Sections spin for artificial gravity; bridges stay still, so their
	# docks do not move.
	var omega := _spin_rate()
	for child in get_children():
		if child.name.begins_with("Section"):
			child.rotate_object_local(Vector3.UP, omega * delta)

# How fast sections spin (rad/s) for the target gravity.
func _spin_rate() -> float:
	return TorusGeometry.compute_section_angular_velocity(section_radius, TorusGeometry.GRAVITY_1G * target_gravity_g)

func _effective_planet_radius() -> float:
	if planet_node.is_empty():
		return planet_radius
	var planet := get_node_or_null(planet_node)
	if planet == null or not ("planet_radius" in planet):
		return planet_radius
	return planet.planet_radius

func get_bridge_radius() -> float:
	return section_radius * BRIDGE_RADIUS_RATIO

func get_bridge_length() -> float:
	return TorusGeometry.compute_bridge_length(_effective_planet_radius(), orbit_altitude, num_sections, section_length)

# In-tree only (uses the station's global transform).
func nearest_bridge_index(world_position: Vector3) -> int:
	return TorusGeometry.compute_nearest_bridge_index(to_local(world_position), num_sections)

func get_docking_port(bridge_index: int) -> Node3D:
	return get_node("Bridge%d/Port" % bridge_index)

const HULL_LIGHTS_ENERGY := 3.0
# Sections and bridges both carry the rectangular panel texture (much nicer
# than the old hexagon hull; tools/blender/panel_textures.py), about
# BRIDGE_TILE_SIZE metres a repeat. Each gets its own material resource
# (their circumference and length give different whole-repeat counts).
const BRIDGE_TEXTURE_DIR := "res://assets/textures/bridge/"
const BRIDGE_TILE_SIZE := 100.0
# Station identification stencilled on every section's outer hull (see
# section_label.gd): character size and gap (about 1 degree tall seen from
# LABEL_VISIBILITY_RANGE, so it reads from well outside a bridge's approach),
# lifted just off the surface so it does not z-fight the panel texture.
const LABEL_CHAR_HEIGHT := 1400.0
const LABEL_CHAR_WIDTH := 840.0
const LABEL_SPACING := 130.0
const LABEL_LIFT_RATIO := 0.0005
const LABEL_CURVE_SEGMENTS := 16
const LABEL_VISIBILITY_RANGE := 90000.0
const LABEL_ATLAS_PATH := "res://assets/textures/labels/atlas.png"
const LABEL_COLOR := Color(1.0, 0.96, 0.88)
const LABEL_ENERGY := 4.0
const LABEL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec3 label_color : source_color = vec3(1.0, 0.96, 0.88);
uniform float label_energy = 4.0;

varying vec2 atlas_uv;

void vertex() {
	// INSTANCE_CUSTOM carries this instance's atlas cell: xy = origin, zw = size.
	atlas_uv = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}

void fragment() {
	float glyph = texture(atlas, atlas_uv).a;
	if (glyph < 0.5) {
		discard;
	}
	ALBEDO = label_color;
	EMISSION = label_color * label_energy;
}
"""
const BRIDGE_RADIUS_RATIO := 0.3
# A docking pad on one flat face of every bridge prism, halfway along it,
# spinning with the bridge. BRIDGE_SEGMENTS faces; PAD_FACE is the one just
# past local +X. The pad sits PAD_LIFT_RATIO of the radius above the face
# (0.3 m on a 600 m bridge): it reads as painted on, and the depth buffer
# still separates it from the face up to PAD_VISIBLE_RATIO radii (3 km),
# past which it is not drawn (a couple of pixels anyway).
const BRIDGE_SEGMENTS := 64
const PAD_FACE := 15
const PAD_FACE_FILL := 0.985
const PAD_LIFT_RATIO := 0.0005
const PAD_VISIBLE_RATIO := 5.0
# Four green lamps on each pad's corners (the texture's green spots), 8 m
# across: they shrink with distance like real objects but never below
# LAMP_MIN_PIXELS, so a dock still shows up to LAMP_RANGE. See LAMP_SHADER.
const LAMP_COLOR := Color(0.3, 1.0, 0.4)
const LAMP_SIZE := 8.0
const LAMP_MIN_PIXELS := 2.0
const LAMP_RANGE := 50000.0
const LAMP_LIFT_RATIO := 1.0 / 600.0
# The quad is 1 m; drawn, it reaches ~160 m across at 50 km.
const LAMP_CULL_MARGIN := 500.0
const LAMP_PERIOD := 1.5
const LAMP_ON_TIME := 0.5
# Billboard sized in camera space (writing MODELVIEW_MATRIX has no effect in
# this double-precision build; skip_vertex_transform does). Depth-tested:
# the sections at both ends of a bridge (2 km radius, ~1.4 km above the pad)
# hide its lamps from shallow views along the ring, as they should. Pulled
# toward the camera by max(own size, 1% of the distance) so the pad face
# does not cut the quad, far short of the ~900 m to a section's rim. A lamp
# also hides itself when its pad (its node's +Y) faces away.
const LAMP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

uniform float lamp_size = 8.0;
uniform float min_pixels = 2.0;
uniform vec3 lamp_color : source_color = vec3(0.3, 1.0, 0.4);
uniform float period = 1.5;
uniform float on_time = 0.5;

// 1 while the lamp is at least 3 px across: rounded then, a full square
// below (a 2 px quad cut to a circle covers almost no pixel centres).
varying float round_shape;
// 1 while the lamp's pad faces the camera.
varying float facing;

void vertex() {
	// The lamp's centre in the camera's frame, and how far away it is.
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float depth = max(-centre.z, 0.001);
	// Width of one screen pixel per metre of depth.
	float pixel = 2.0 / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);
	float world_size = max(lamp_size, min_pixels * pixel * depth);
	round_shape = step(3.0 * pixel * depth, world_size);
	// Centre and size scaled together: same place and size on screen.
	float pull = clamp((depth - max(world_size, 0.01 * depth)) / depth, 0.1, 1.0);
	VERTEX = (centre + VERTEX * world_size) * pull;
	vec3 pad_normal = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	facing = step(0.0, dot(pad_normal, -centre));
}

void fragment() {
	if (facing < 0.5 || (round_shape > 0.5 && length(UV - vec2(0.5)) > 0.5) || mod(TIME, period) >= on_time) {
		discard;
	}
	ALBEDO = lamp_color;
}
"""

# One mesh and one material for every lamp.
var _lamp_mesh: QuadMesh
var _lamp_material: ShaderMaterial
var _label_glyph_mesh: ArrayMesh
var _label_material: ShaderMaterial

# A whole number of repeats round and along, so no seam shows where the
# texture wraps. A CylinderMesh side spans UV v 0..0.5 only: twice the scale.
# Used for both sections and bridges (each its own resource, different
# repeat counts).
func _build_panel_material(circumference: float, length: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(BRIDGE_TEXTURE_DIR + "color.png")
	mat.roughness_texture = load(BRIDGE_TEXTURE_DIR + "roughness.png")
	mat.normal_enabled = true
	mat.normal_texture = load(BRIDGE_TEXTURE_DIR + "normal.png")
	mat.emission_enabled = true
	mat.emission = Color(0, 0, 0)
	mat.emission_texture = load(BRIDGE_TEXTURE_DIR + "emission.png")
	mat.emission_energy_multiplier = HULL_LIGHTS_ENERGY
	var round_repeats := maxf(1.0, roundf(circumference / BRIDGE_TILE_SIZE))
	var along_repeats := maxf(1.0, roundf(length / BRIDGE_TILE_SIZE))
	mat.uv1_scale = Vector3(round_repeats, along_repeats * 2.0, 1.0)
	return mat

# The section's ID (see section_label.gd), stencilled at 4 points round the
# circumference. One MultiMeshInstance3D per section: a shared curved glyph
# mesh, each character an instance whose transform (position, size,
# orientation) and atlas cell (custom data) are computed once at build time.
func _build_section_labels(section_index: int) -> MultiMeshInstance3D:
	var text := SectionLabelScript.format_id(section_index)
	var surface_radius := section_radius * (1.0 + LABEL_LIFT_RATIO)
	var instances := []
	for angle in SectionLabelScript.ANGLES:
		instances += SectionLabelScript.label_instances(text, angle, surface_radius, LABEL_CHAR_WIDTH, LABEL_CHAR_HEIGHT, LABEL_SPACING)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _label_glyph_mesh
	multimesh.instance_count = instances.size()
	for i in range(instances.size()):
		multimesh.set_instance_transform(i, instances[i].transform)
		var uv: Rect2 = instances[i].uv
		multimesh.set_instance_custom_data(i, Color(uv.position.x, uv.position.y, uv.size.x, uv.size.y))
	var node := MultiMeshInstance3D.new()
	node.name = "Labels"
	node.multimesh = multimesh
	node.material_override = _label_material
	node.visibility_range_end = LABEL_VISIBILITY_RANGE
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

# Not CylinderShape3D: at this scale Godot's cylinder collision gives bad
# contacts against the ship's turning box, shoving a still ship up to ~100 m
# per tick (see tests/test_torus_station_physics.gd). A convex prism with the
# visible mesh's own side-wall corners collides reliably and matches what the
# player sees.
func _build_prism_shape(mesh: CylinderMesh) -> ConvexPolygonShape3D:
	var half_height: float = mesh.height * 0.5
	var corners := {}
	for vertex: Vector3 in mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX]:
		var on_rim: bool = is_equal_approx(absf(vertex.y), half_height) \
				and is_equal_approx(Vector2(vertex.x, vertex.z).length(), mesh.top_radius)
		if on_rim:
			# The mesh repeats the seam vertex; the key collapses duplicates.
			corners[vertex.snappedf(0.001)] = vertex
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(corners.values())
	return shape

func build_station() -> void:
	for child in get_children():
		if child.name.begins_with("Section") or child.name.begins_with("Bridge"):
			remove_child(child)
			child.queue_free()

	var effective_planet_radius := _effective_planet_radius()
	var section_material := _build_panel_material(TAU * section_radius, section_length)

	var section_mesh := CylinderMesh.new()
	section_mesh.top_radius = section_radius
	section_mesh.bottom_radius = section_radius
	section_mesh.height = section_length

	var section_shape := _build_prism_shape(section_mesh)

	var label_surface_radius := section_radius * (1.0 + LABEL_LIFT_RATIO)
	_label_glyph_mesh = SectionLabelScript.build_curved_glyph_mesh(label_surface_radius, LABEL_CHAR_HEIGHT, LABEL_CURVE_SEGMENTS)
	var label_shader := Shader.new()
	label_shader.code = LABEL_SHADER
	_label_material = ShaderMaterial.new()
	_label_material.shader = label_shader
	_label_material.set_shader_parameter("atlas", load(LABEL_ATLAS_PATH))
	_label_material.set_shader_parameter("label_color", LABEL_COLOR)
	_label_material.set_shader_parameter("label_energy", LABEL_ENERGY)

	var section_transforms := TorusGeometry.compute_section_transforms(effective_planet_radius, orbit_altitude, num_sections)
	for i in range(section_transforms.size()):
		var section := AnimatableBody3D.new()
		section.name = "Section%d" % i
		# Sections rotate every frame for artificial gravity. With the
		# default sync_to_physics=true, the physics server treats itself as
		# the source of truth for the body's transform between physics
		# steps: transform changes applied outside a physics step (this
		# rotation runs in _process, not _physics_process) are silently
		# dropped except for roughly the last one before each physics tick,
		# and a parent's transform change (as WorldOriginRebase applies) is
		# not picked up correctly either. Verified empirically — see
		# tests/test_torus_station_physics.gd.
		section.sync_to_physics = false

		var section_mesh_instance := MeshInstance3D.new()
		section_mesh_instance.name = "Mesh"
		section_mesh_instance.mesh = section_mesh
		section_mesh_instance.material_override = section_material
		section.add_child(section_mesh_instance)

		var section_collision := CollisionShape3D.new()
		section_collision.name = "Collision"
		section_collision.shape = section_shape
		section.add_child(section_collision)

		section.add_child(_build_section_labels(i))

		section.transform = section_transforms[i]
		add_child(section)

	var bridge_length := TorusGeometry.compute_bridge_length(effective_planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_transforms := TorusGeometry.compute_bridge_transforms(effective_planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_material := _build_panel_material(TAU * get_bridge_radius(), bridge_length)
	var bridge_mesh := CylinderMesh.new()
	bridge_mesh.top_radius = get_bridge_radius()
	bridge_mesh.bottom_radius = get_bridge_radius()
	bridge_mesh.height = max(bridge_length, 0.01)
	bridge_mesh.radial_segments = BRIDGE_SEGMENTS

	var bridge_shape := _build_prism_shape(bridge_mesh)
	var pad_face := _pad_face()
	var pad_mesh := PlaneMesh.new()
	pad_mesh.size = Vector2.ONE * pad_face.width * PAD_FACE_FILL
	_lamp_mesh = QuadMesh.new()
	_lamp_mesh.size = Vector2.ONE
	var lamp_shader := Shader.new()
	lamp_shader.code = LAMP_SHADER
	_lamp_material = ShaderMaterial.new()
	_lamp_material.shader = lamp_shader
	_lamp_material.set_shader_parameter("lamp_size", LAMP_SIZE)
	_lamp_material.set_shader_parameter("min_pixels", LAMP_MIN_PIXELS)
	_lamp_material.set_shader_parameter("lamp_color", LAMP_COLOR)
	_lamp_material.set_shader_parameter("period", LAMP_PERIOD)
	_lamp_material.set_shader_parameter("on_time", LAMP_ON_TIME)

	for i in range(bridge_transforms.size()):
		var bridge := AnimatableBody3D.new()
		bridge.name = "Bridge%d" % i
		# Bridges stay still (only sections spin). They keep the section's
		# body setup: AnimatableBody3D with sync_to_physics off, so a
		# parent's transform change (as WorldOriginRebase applies) is picked
		# up (see the sync_to_physics comment on the section body above).
		bridge.sync_to_physics = false

		var bridge_mesh_instance := MeshInstance3D.new()
		bridge_mesh_instance.name = "Mesh"
		bridge_mesh_instance.mesh = bridge_mesh
		bridge_mesh_instance.material_override = bridge_material
		bridge.add_child(bridge_mesh_instance)

		var bridge_collision := CollisionShape3D.new()
		bridge_collision.name = "Collision"
		bridge_collision.shape = bridge_shape
		bridge.add_child(bridge_collision)

		_add_dock(bridge, pad_mesh, pad_face)

		bridge.transform = bridge_transforms[i]
		add_child(bridge)

# The pad's face of the bridge prism: outward normal, distance of its plane
# from the axis, and its width (CylinderMesh puts vertex i at the sin/cos of
# i * TAU / segments; the face runs from vertex PAD_FACE to the next).
func _pad_face() -> Dictionary:
	var step := TAU / BRIDGE_SEGMENTS
	var angle := (PAD_FACE + 0.5) * step
	var radius := get_bridge_radius()
	return {
		"normal": Vector3(sin(angle), 0.0, cos(angle)),
		"distance": radius * cos(step * 0.5),
		"width": 2.0 * radius * sin(step * 0.5),
	}

func _add_dock(bridge: Node3D, pad_mesh: PlaneMesh, face: Dictionary) -> void:
	var normal: Vector3 = face.normal
	var across := Vector3(normal.z, 0.0, -normal.x)
	var centre: Vector3 = normal * (face.distance + get_bridge_radius() * PAD_LIFT_RATIO)
	var pad := MeshInstance3D.new()
	pad.name = "DockPad"
	pad.mesh = pad_mesh
	pad.material_override = DockPadTexture.pad_material()
	# The plane faces its +Y: turn that to the face's normal.
	pad.transform = Transform3D(Basis(across, normal, across.cross(normal)), centre)
	pad.visibility_range_end = get_bridge_radius() * PAD_VISIBLE_RATIO
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bridge.add_child(pad)
	# Docking and undocking read the port: x out of the face, y along the axis.
	var port := Node3D.new()
	port.name = "Port"
	port.transform = Transform3D(Basis(normal, Vector3.UP, normal.cross(Vector3.UP)), centre)
	bridge.add_child(port)
	# Lamps on the pad's corners, just above it.
	var half: float = pad_mesh.size.x * (0.5 - DockPadTexture.LAMP_INSET)
	var along := across.cross(normal)
	var lift: Vector3 = normal * get_bridge_radius() * LAMP_LIFT_RATIO
	var k := 0
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			var lamp := MeshInstance3D.new()
			lamp.name = "DockLamp_%d" % k
			lamp.mesh = _lamp_mesh
			lamp.material_override = _lamp_material
			# Up = the pad normal: the shader hides the lamp when it faces away.
			lamp.transform = Transform3D(Basis(across, normal, along), centre + across * a * half + along * b * half + lift)
			lamp.visibility_range_end = LAMP_RANGE
			lamp.extra_cull_margin = LAMP_CULL_MARGIN
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bridge.add_child(lamp)
			k += 1
