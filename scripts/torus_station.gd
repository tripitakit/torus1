@tool
extends Node3D

const TorusGeometry = preload("res://scripts/torus_geometry.gd")

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
	# Bridges spin rigidly together with the sections they connect: the
	# whole ring rotates as one piece.
	var target_gravity := TorusGeometry.GRAVITY_1G * target_gravity_g
	var omega := TorusGeometry.compute_section_angular_velocity(section_radius, target_gravity)
	for child in get_children():
		if child.name.begins_with("Section") or child.name.begins_with("Bridge"):
			child.rotate_object_local(Vector3.UP, omega * delta)

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
	return get_node("DockingCollar%d/Port" % bridge_index)

const HULL_ALBEDO_PATH := "res://assets/textures/station/albedo.png"
const HULL_ROUGHNESS_PATH := "res://assets/textures/station/roughness.png"
const HULL_NORMAL_PATH := "res://assets/textures/station/normal.png"
const HULL_EMISSION_PATH := "res://assets/textures/station/emission.png"
const HULL_AO_PATH := "res://assets/textures/station/ao.png"
const HULL_TILE_SIZE := 500.0
const HULL_LIGHTS_ENERGY := 3.0
const BRIDGE_RADIUS_RATIO := 0.3
# A docking collar around the middle of every bridge. It does not spin, so its
# port stays still for docking. Sizes are fractions of the bridge radius.
const COLLAR_INNER_RATIO := 1.05
const COLLAR_OUTER_RATIO := 1.25
const PORT_OFFSET_RATIO := 0.01
const PORT_SIZE_RATIO := Vector3(0.007, 0.1, 0.1)
const PORT_COLOR := Color(0.2, 1.0, 0.35)
const COLLAR_COLOR := Color(0.35, 0.37, 0.4)

func _build_hull_material(circumference: float, length: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(HULL_ALBEDO_PATH)
	mat.roughness_texture = load(HULL_ROUGHNESS_PATH)
	mat.normal_enabled = true
	mat.normal_texture = load(HULL_NORMAL_PATH)
	mat.emission_enabled = true
	mat.emission = Color(0, 0, 0)
	mat.emission_texture = load(HULL_EMISSION_PATH)
	mat.emission_energy_multiplier = HULL_LIGHTS_ENERGY
	mat.ao_enabled = true
	mat.ao_texture = load(HULL_AO_PATH)
	mat.uv1_scale = Vector3(circumference / HULL_TILE_SIZE, length / HULL_TILE_SIZE, 1.0)
	return mat

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
		if child.name.begins_with("Section") or child.name.begins_with("Bridge") or child.name.begins_with("DockingCollar"):
			remove_child(child)
			child.queue_free()

	var effective_planet_radius := _effective_planet_radius()
	var hull_material := _build_hull_material(TAU * section_radius, section_length)

	var section_mesh := CylinderMesh.new()
	section_mesh.top_radius = section_radius
	section_mesh.bottom_radius = section_radius
	section_mesh.height = section_length

	var section_shape := _build_prism_shape(section_mesh)

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
		section_mesh_instance.material_override = hull_material
		section.add_child(section_mesh_instance)

		var section_collision := CollisionShape3D.new()
		section_collision.name = "Collision"
		section_collision.shape = section_shape
		section.add_child(section_collision)

		section.transform = section_transforms[i]
		add_child(section)

	var bridge_length := TorusGeometry.compute_bridge_length(effective_planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_transforms := TorusGeometry.compute_bridge_transforms(effective_planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_mesh := CylinderMesh.new()
	bridge_mesh.top_radius = get_bridge_radius()
	bridge_mesh.bottom_radius = get_bridge_radius()
	bridge_mesh.height = max(bridge_length, 0.01)

	var bridge_shape := _build_prism_shape(bridge_mesh)

	for i in range(bridge_transforms.size()):
		var bridge := AnimatableBody3D.new()
		bridge.name = "Bridge%d" % i
		# Bridges now rotate every frame together with sections — same
		# reasoning as sections: a body under continuous external transform
		# control should not be a StaticBody3D (see the sync_to_physics
		# comment on the section body above for why sync_to_physics must
		# also be off).
		bridge.sync_to_physics = false

		var bridge_mesh_instance := MeshInstance3D.new()
		bridge_mesh_instance.name = "Mesh"
		bridge_mesh_instance.mesh = bridge_mesh
		bridge_mesh_instance.material_override = hull_material
		bridge.add_child(bridge_mesh_instance)

		var bridge_collision := CollisionShape3D.new()
		bridge_collision.name = "Collision"
		bridge_collision.shape = bridge_shape
		bridge.add_child(bridge_collision)

		bridge.transform = bridge_transforms[i]
		add_child(bridge)

	_build_docking_collars(bridge_transforms)

func _build_docking_collars(bridge_transforms: Array[Transform3D]) -> void:
	var bridge_radius := get_bridge_radius()
	var collar_mesh := TorusMesh.new()
	collar_mesh.inner_radius = bridge_radius * COLLAR_INNER_RATIO
	collar_mesh.outer_radius = bridge_radius * COLLAR_OUTER_RATIO
	# Triangle shape from the visible mesh: no analytic shape (see the
	# CylinderShape3D teleport note on _build_prism_shape).
	var collar_shape := collar_mesh.create_trimesh_shape()
	var collar_material := StandardMaterial3D.new()
	collar_material.albedo_color = COLLAR_COLOR
	collar_material.metallic = 0.6
	collar_material.roughness = 0.4

	var port_mesh := BoxMesh.new()
	port_mesh.size = PORT_SIZE_RATIO * bridge_radius
	# Glowing, not a real light: 2000 extra lights would cost too much.
	var port_material := StandardMaterial3D.new()
	port_material.albedo_color = PORT_COLOR
	port_material.emission_enabled = true
	port_material.emission = PORT_COLOR
	port_material.emission_energy_multiplier = 3.0

	for i in range(bridge_transforms.size()):
		# Named neither Section nor Bridge: _rotate_sections leaves it still.
		var collar := StaticBody3D.new()
		collar.name = "DockingCollar%d" % i
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		mesh_instance.mesh = collar_mesh
		mesh_instance.material_override = collar_material
		collar.add_child(mesh_instance)
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		collision.shape = collar_shape
		collar.add_child(collision)
		var port := Node3D.new()
		port.name = "Port"
		port.position = Vector3(collar_mesh.outer_radius + bridge_radius * PORT_OFFSET_RATIO, 0.0, 0.0)
		var platform := MeshInstance3D.new()
		platform.name = "Platform"
		platform.mesh = port_mesh
		platform.material_override = port_material
		port.add_child(platform)
		collar.add_child(port)
		collar.transform = bridge_transforms[i]
		add_child(collar)
