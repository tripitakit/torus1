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

const HULL_ALBEDO_PATH := "res://assets/textures/station/albedo.png"
const HULL_ROUGHNESS_PATH := "res://assets/textures/station/roughness.png"
const HULL_NORMAL_PATH := "res://assets/textures/station/normal.png"
const HULL_EMISSION_PATH := "res://assets/textures/station/emission.png"
const HULL_AO_PATH := "res://assets/textures/station/ao.png"
const HULL_TILE_SIZE := 500.0
const HULL_LIGHTS_ENERGY := 3.0
const STRIPE_COLOR := Color(0.95, 0.65, 0.05)

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

func _build_stripe_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STRIPE_COLOR
	mat.emission_enabled = true
	mat.emission = STRIPE_COLOR
	mat.emission_energy_multiplier = 0.3
	return mat

func build_station() -> void:
	for child in get_children():
		if child.name.begins_with("Section") or child.name.begins_with("Bridge"):
			remove_child(child)
			child.queue_free()

	var effective_planet_radius := _effective_planet_radius()
	var hull_material := _build_hull_material(TAU * section_radius, section_length)
	var stripe_material := _build_stripe_material()

	var section_mesh := CylinderMesh.new()
	section_mesh.top_radius = section_radius
	section_mesh.bottom_radius = section_radius
	section_mesh.height = section_length

	var section_shape := CylinderShape3D.new()
	section_shape.radius = section_radius
	section_shape.height = section_length

	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(2.0, section_length, 2.0)

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

		var stripe := MeshInstance3D.new()
		stripe.name = "Stripe"
		stripe.mesh = stripe_mesh
		stripe.material_override = stripe_material
		stripe.transform.origin = Vector3(0.0, 0.0, section_radius)
		section.add_child(stripe)

		section.transform = section_transforms[i]
		add_child(section)

	var bridge_length := TorusGeometry.compute_bridge_length(effective_planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_transforms := TorusGeometry.compute_bridge_transforms(effective_planet_radius, orbit_altitude, num_sections, section_length)
	var bridge_mesh := CylinderMesh.new()
	bridge_mesh.top_radius = section_radius * 0.3
	bridge_mesh.bottom_radius = section_radius * 0.3
	bridge_mesh.height = max(bridge_length, 0.01)

	var bridge_shape := CylinderShape3D.new()
	bridge_shape.radius = section_radius * 0.3
	bridge_shape.height = max(bridge_length, 0.01)

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
