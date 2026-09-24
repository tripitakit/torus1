extends Node3D

# The inside of the station around one bridge, built on docking: the bridge
# tube centred on the origin (axis along Z) and the two sections it joins.
# It does not rotate: this is the frame of the people living inside, so the
# ground stays still.

const InteriorLayout = preload("res://scripts/interior_layout.gd")
const SectionGeneratorScript = preload("res://scripts/section_generator.gd")
const TerrainDressingScript = preload("res://scripts/terrain_dressing.gd")

# Set before build(); defaults are the full-scale station's.
var section_radius := 2000.0
var section_length := 20000.0
var bridge_radius := 600.0
var bridge_length := 1834.0

# Which station sections this interior shows: bridge i joins section i
# (behind, +Z) and section i + 1 (ahead, -Z). Each is generated from its index.
var behind_section_index := 0
var ahead_section_index := 1

# Terrain split in chunks: the renderer lights each object with at most 8
# lights (see InteriorLayout.count_lights_reaching_band).
const CHUNKS_AROUND := 16
const CHUNK_LENGTH := 1000.0
const CHUNK_ARC_SEGMENTS := 8
const CHUNK_LENGTH_SEGMENTS := 4
const CAP_SEGMENTS := 128
const TUBE_SEGMENTS := 4
const TUBE_ARC_SEGMENTS := 64

const SUN_SPACING := 1000.0
const SUN_RANGE := 2600.0
const SUN_ENERGY := 1.5
# No distance falloff inside the range (only the range's soft edge): with
# the default 1/d falloff a sun 2000 m above the ground lights it at ~6e-4
# of its energy and the interior reads black.
const AXIS_LIGHT_ATTENUATION := 0.0
const SUN_COLOR := Color(1.0, 0.93, 0.8)
const SUN_GLOBE_RADIUS := 30.0
const BRIDGE_LIGHT_RANGE := 900.0
const BRIDGE_LIGHT_ENERGY := 1.0

const STRUCTURE_COLOR := Color(0.45, 0.47, 0.5)

const DOCK_PLATFORM_SIZE := Vector3(60.0, 4.0, 60.0)
const DOCK_LIGHT_RANGE := 150.0
const SPAWN_HEIGHT := 24.0
const SIGN_TEXT := "UNDOCK  [F]"
const SIGN_READY_COLOR := Color(0.3, 1.0, 0.4)
const SIGN_IDLE_COLOR := Color(0.5, 0.5, 0.5)

var _structure_material: StandardMaterial3D
var _sun_mesh: SphereMesh
var _sun_material: StandardMaterial3D
var _plans := {}

func build() -> void:
	_structure_material = _make_material(STRUCTURE_COLOR, 0.6)
	_sun_mesh = SphereMesh.new()
	_sun_mesh.radius = SUN_GLOBE_RADIUS
	_sun_mesh.height = SUN_GLOBE_RADIUS * 2.0
	_sun_material = StandardMaterial3D.new()
	_sun_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sun_material.albedo_color = SUN_COLOR

	# Every chunk's floor collides as the same piece of wall, turned and
	# shifted: one collision shape for all of them. What is drawn on it comes
	# from the section's plan.
	var chunk_shape := _build_band_mesh(section_radius, TAU / CHUNKS_AROUND, CHUNK_LENGTH, CHUNK_ARC_SEGMENTS, CHUNK_LENGTH_SEGMENTS).create_trimesh_shape()
	var dressing = TerrainDressingScript.new()
	for side in [-1.0, 1.0]:
		_build_section(side, chunk_shape, dressing)
	_build_bridge_tube()
	_build_bridge_lights()
	_build_dock()

# Above the dock platform, bow toward the section ahead (-Z), "up" toward the
# tube's axis (the platform sits at the bottom of the tube).
func get_spawn_transform() -> Transform3D:
	return Transform3D(Basis(), _platform_position() + Vector3(0.0, SPAWN_HEIGHT, 0.0))

# The interior world always sits at the origin of the main scene.
func get_dock_position() -> Vector3:
	return transform * _platform_position()

func set_undock_ready(ready: bool) -> void:
	(get_node("Dock/Sign") as Label3D).modulate = SIGN_READY_COLOR if ready else SIGN_IDLE_COLOR

# The plan of the section ahead (side -1) or behind (side +1).
func get_section_plan(side: float):
	return _plans[side]

func _platform_position() -> Vector3:
	return Vector3(0.0, -bridge_radius + DOCK_PLATFORM_SIZE.y * 0.5, 0.0)

func _build_section(side: float, chunk_shape: Shape3D, dressing) -> void:
	var section := Node3D.new()
	section.name = "SectionAhead" if side < 0.0 else "SectionBehind"
	add_child(section)
	var plan = SectionGeneratorScript.generate(ahead_section_index if side < 0.0 else behind_section_index, section_radius, section_length)
	_plans[side] = plan
	var buildings_by_chunk: Dictionary = plan.group_buildings_by_chunk()
	var center_z: float = InteriorLayout.section_center_z(bridge_length, section_length, side)
	var start_z: float = center_z - section_length * 0.5
	var chunks_along: int = roundi(section_length / CHUNK_LENGTH)
	var angle_step: float = TAU / CHUNKS_AROUND
	for around in range(CHUNKS_AROUND):
		for along in range(chunks_along):
			var chunk := StaticBody3D.new()
			chunk.name = "Chunk_%02d_%02d" % [around, along]
			chunk.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), around * angle_step), Vector3(0.0, 0.0, start_z + along * CHUNK_LENGTH))
			var collision := CollisionShape3D.new()
			collision.name = "Collision"
			collision.shape = chunk_shape
			chunk.add_child(collision)
			dressing.dress_chunk(chunk, plan, around, along, buildings_by_chunk.get(Vector2i(around, along), []))
			section.add_child(chunk)
	# Both caps face into the section. The one by the bridge has the tube's
	# hole; the far one is closed (its door to the next bridge opens in piece C).
	section.add_child(_build_cap("NearCap", bridge_radius, center_z - side * section_length * 0.5, side))
	section.add_child(_build_cap("FarCap", 0.0, center_z + side * section_length * 0.5, -side))
	var suns: PackedVector3Array = InteriorLayout.sun_positions(center_z, section_length, SUN_SPACING)
	for k in range(suns.size()):
		section.add_child(_build_sun("Sun_%02d" % k, suns[k]))

func _build_cap(cap_name: String, inner_radius: float, z: float, facing: float) -> StaticBody3D:
	var cap := StaticBody3D.new()
	cap.name = cap_name
	var mesh := _build_annulus_mesh(inner_radius, section_radius, CAP_SEGMENTS)
	# The annulus faces -Z; half a turn around Y makes it face +Z.
	var cap_basis := Basis() if facing < 0.0 else Basis(Vector3.UP, PI)
	cap.transform = Transform3D(cap_basis, Vector3(0.0, 0.0, z))
	_add_mesh_and_collision(cap, mesh, mesh.create_trimesh_shape(), _structure_material)
	return cap

func _build_sun(sun_name: String, sun_position: Vector3) -> Node3D:
	var sun := Node3D.new()
	sun.name = sun_name
	sun.position = sun_position
	var globe := MeshInstance3D.new()
	globe.name = "Globe"
	globe.mesh = _sun_mesh
	globe.material_override = _sun_material
	sun.add_child(globe)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = SUN_COLOR
	light.light_energy = SUN_ENERGY
	light.omni_range = SUN_RANGE
	light.omni_attenuation = AXIS_LIGHT_ATTENUATION
	# No shadows: at kilometre scale shadow maps band and flicker (as the
	# headlights did), and 40 shadowed lights would cost too much.
	light.shadow_enabled = false
	sun.add_child(light)
	return sun

func _build_bridge_tube() -> void:
	var tube := Node3D.new()
	tube.name = "BridgeTube"
	add_child(tube)
	var segment_length: float = bridge_length / TUBE_SEGMENTS
	var mesh := _build_band_mesh(bridge_radius, TAU, segment_length, TUBE_ARC_SEGMENTS, 1)
	var shape := mesh.create_trimesh_shape()
	for k in range(TUBE_SEGMENTS):
		var segment := StaticBody3D.new()
		segment.name = "Segment_%d" % k
		segment.position = Vector3(0.0, 0.0, -bridge_length * 0.5 + k * segment_length)
		_add_mesh_and_collision(segment, mesh, shape, _structure_material)
		tube.add_child(segment)

func _build_bridge_lights() -> void:
	for k in range(3):
		var light := OmniLight3D.new()
		light.name = "BridgeLight_%d" % k
		light.position = Vector3(0.0, 0.0, bridge_length * (k - 1) / 3.0)
		light.light_color = SUN_COLOR
		light.light_energy = BRIDGE_LIGHT_ENERGY
		light.omni_range = BRIDGE_LIGHT_RANGE
		light.omni_attenuation = AXIS_LIGHT_ATTENUATION
		light.shadow_enabled = false
		add_child(light)

func _build_dock() -> void:
	var dock := Node3D.new()
	dock.name = "Dock"
	add_child(dock)

	var platform := StaticBody3D.new()
	platform.name = "Platform"
	platform.position = _platform_position()
	var box := BoxMesh.new()
	box.size = DOCK_PLATFORM_SIZE
	var box_shape := BoxShape3D.new()
	box_shape.size = DOCK_PLATFORM_SIZE
	var platform_material := _make_material(SIGN_READY_COLOR, 0.5)
	platform_material.emission_enabled = true
	platform_material.emission = SIGN_READY_COLOR
	platform_material.emission_energy_multiplier = 1.5
	_add_mesh_and_collision(platform, box, box_shape, platform_material)
	dock.add_child(platform)

	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = _platform_position() + Vector3(0.0, 30.0, 0.0)
	light.light_color = SIGN_READY_COLOR
	light.light_energy = 2.0
	light.omni_range = DOCK_LIGHT_RANGE
	light.shadow_enabled = false
	dock.add_child(light)

	# The only undock cue: there is no HUD inside.
	var undock_sign := Label3D.new()
	undock_sign.name = "Sign"
	undock_sign.text = SIGN_TEXT
	undock_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	undock_sign.font_size = 96
	undock_sign.pixel_size = 0.1
	undock_sign.position = _platform_position() + Vector3(0.0, 45.0, 0.0)
	undock_sign.modulate = SIGN_IDLE_COLOR
	dock.add_child(undock_sign)

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _add_mesh_and_collision(body: Node3D, mesh: Mesh, shape: Shape3D, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)

# Inner wall of a cylinder: angle 0..angle_span, z 0..length, facing the axis.
func _build_band_mesh(radius: float, angle_span: float, length: float, arc_segments: int, length_segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(arc_segments):
		var a0: float = angle_span * i / arc_segments
		var a1: float = angle_span * (i + 1) / arc_segments
		for j in range(length_segments):
			var z0: float = length * j / length_segments
			var z1: float = length * (j + 1) / length_segments
			_add_quad(st,
				InteriorLayout.cylinder_point(radius, a0, z0),
				InteriorLayout.cylinder_point(radius, a1, z0),
				InteriorLayout.cylinder_point(radius, a0, z1),
				InteriorLayout.cylinder_point(radius, a1, z1))
	st.generate_normals()
	return st.commit()

# Flat ring in the z = 0 plane from inner_radius to outer_radius, facing -Z.
# inner_radius 0 gives a full disc.
func _build_annulus_mesh(inner_radius: float, outer_radius: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0: float = TAU * i / segments
		var a1: float = TAU * (i + 1) / segments
		var inner0 := InteriorLayout.cylinder_point(inner_radius, a0, 0.0)
		var inner1 := InteriorLayout.cylinder_point(inner_radius, a1, 0.0)
		var outer0 := InteriorLayout.cylinder_point(outer_radius, a0, 0.0)
		var outer1 := InteriorLayout.cylinder_point(outer_radius, a1, 0.0)
		if inner_radius > 0.0:
			_add_quad(st, inner0, outer0, inner1, outer1)
		else:
			_add_triangle(st, inner0, outer0, outer1)
	st.generate_normals()
	return st.commit()

# p00-p10 and p01-p11 are opposite edges. This winding is the one
# SurfaceTool.generate_normals turns into the facing direction documented on
# the two builders above (verified empirically).
func _add_quad(st: SurfaceTool, p00: Vector3, p10: Vector3, p01: Vector3, p11: Vector3) -> void:
	_add_triangle(st, p00, p10, p01)
	_add_triangle(st, p10, p11, p01)

func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
