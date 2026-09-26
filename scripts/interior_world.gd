extends Node3D

# The inside of the station: a straight chain of sections and bridges along
# the Z axis (see InteriorLayout for slots), built around the craft as it
# flies. At docking the docked bridge is slot 0, centred on the origin. It
# does not rotate: this is the frame of the people living inside, so the
# ground stays still.

const InteriorLayout = preload("res://scripts/interior_layout.gd")
const SectionGeneratorScript = preload("res://scripts/section_generator.gd")
const TerrainDressingScript = preload("res://scripts/terrain_dressing.gd")
const DockPadTexture = preload("res://scripts/dock_pad_texture.gd")

# Set before build(); defaults are the full-scale station's.
var section_radius := 2000.0
var section_length := 20000.0
var bridge_radius := 600.0
var bridge_length := 1834.0
# The station bridge docked at (slot 0) and how many sections the ring has:
# past the last one the chain goes on from section 0.
var docked_bridge_index := 0
var ring_sections := 2000

# Terrain split in chunks: the renderer lights each object with at most 8
# lights (see InteriorLayout.count_lights_reaching_band).
const CHUNKS_AROUND := 16
const CHUNK_LENGTH := 1000.0
const CHUNK_ARC_SEGMENTS := 8
const CHUNK_LENGTH_SEGMENTS := 4
const CAP_SEGMENTS := 128
const TUBE_SEGMENTS := 4
const TUBE_ARC_SEGMENTS := 64

# Sections load within LOAD_REACH chain periods of the craft (centre to
# craft, along the axis) and unload past UNLOAD_REACH: the gap keeps a
# section from being built and thrown away while hovering at the edge.
const LOAD_REACH := 1.25
const UNLOAD_REACH := 1.5
# Per-frame work while flying (about 13 ms and 7 ms measured).
const CHUNKS_DRESSED_PER_FRAME := 16
const CHUNKS_FREED_PER_FRAME := 32
const ALL_AT_ONCE := 1 << 30

# Past this distance from the origin along Z, the chain and the craft move
# back together (Z only: the axis stays at x = y = 0).
const REBASE_DISTANCE := 10000.0

const SUN_SPACING := 1000.0
const SUN_RANGE := 2600.0
const SUN_ENERGY := 1.5
# No distance falloff inside the range (only the range's soft edge): with
# the default 1/d falloff a sun 2000 m above the ground lights it at ~6e-4
# of its energy and the interior reads black.
const AXIS_LIGHT_ATTENUATION := 0.0
const SUN_COLOR := Color(1.0, 0.93, 0.8)
const SUN_GLOBE_RADIUS := 30.0
# Bridges have no suns of their own: the nearest suns of the sections on
# either side (500 m inside them) reach the whole tube. With 3 sections and
# 4 bridges loaded that is 64 lights (60 suns, 4 dock lights), the most the
# renderer draws; past 25 km from the camera a light is gone anyway.
const LIGHT_FADE_BEGIN := 24000.0
const LIGHT_FADE_LENGTH := 1000.0

const STRUCTURE_COLOR := Color(0.45, 0.47, 0.5)

const DOCK_PLATFORM_SIZE := Vector3(60.0, 4.0, 60.0)
const DOCK_LIGHT_RANGE := 150.0
const SPAWN_HEIGHT := 24.0
const SIGN_TEXT := "UNDOCK  [F]"
const SIGN_READY_COLOR := Color(0.3, 1.0, 0.4)
const SIGN_IDLE_COLOR := Color(0.5, 0.5, 0.5)

# One section of the chain, from the moment it is wanted until it is freed.
class SectionLoad:
	extends RefCounted
	var slot := 0
	var ring_index := 0
	var radius := 0.0
	var length := 0.0
	var node: Node3D
	var plan = null
	var groups := {}
	var task_id := -1
	var pending_chunks := []
	var unloading := false

	# Runs on a worker thread: touches nothing but this object.
	func generate() -> void:
		plan = SectionGeneratorScript.generate(ring_index, radius, length)
		groups = plan.group_buildings_by_chunk()

	func is_ready() -> bool:
		return task_id < 0 and plan != null and pending_chunks.is_empty() and not unloading

var _chain: Node3D
var _structure_material: StandardMaterial3D
var _sun_mesh: SphereMesh
var _sun_material: StandardMaterial3D
var _chunk_shape: Shape3D
var _cap_mesh: ArrayMesh
var _cap_shape: Shape3D
var _tube_mesh: ArrayMesh
var _tube_shape: Shape3D
var _dressing
var _sections := {}
var _bridges := {}

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
	_chunk_shape = _build_band_mesh(section_radius, TAU / CHUNKS_AROUND, CHUNK_LENGTH, CHUNK_ARC_SEGMENTS, CHUNK_LENGTH_SEGMENTS).create_trimesh_shape()
	_cap_mesh = _build_annulus_mesh(bridge_radius, section_radius, CAP_SEGMENTS)
	_cap_shape = _cap_mesh.create_trimesh_shape()
	_tube_mesh = _build_band_mesh(bridge_radius, TAU, bridge_length / TUBE_SEGMENTS, TUBE_ARC_SEGMENTS, 1)
	_tube_shape = _tube_mesh.create_trimesh_shape()
	_dressing = TerrainDressingScript.new()
	_chain = Node3D.new()
	_chain.name = "Chain"
	add_child(_chain)
	# At docking the two sections beside the bridge are built whole, behind
	# the fade.
	load_now(0.0)

# Loads everything wanted around chain position `focus_z` at once, waiting
# for every plan, and frees what is too far.
func load_now(focus_z: float) -> void:
	_plan_window(focus_z)
	for state: SectionLoad in _sections.values():
		if state.task_id >= 0:
			_finish_plan(state, focus_z)
	_dress_chunks(focus_z, ALL_AT_ONCE)
	_free_unloading(ALL_AT_ONCE)

# One step of loading around chain position `focus_z` that never waits:
# unfinished plans are picked up on a later step. Returns chunks dressed.
func stream_step(focus_z: float, chunk_budget: int, free_budget: int) -> int:
	_plan_window(focus_z)
	for state: SectionLoad in _sections.values():
		if state.task_id >= 0 and WorkerThreadPool.is_task_completed(state.task_id):
			_finish_plan(state, focus_z)
	var dressed := _dress_chunks(focus_z, chunk_budget)
	_free_unloading(free_budget)
	return dressed

func rebase_around(craft: Node3D) -> void:
	if absf(craft.position.z) <= REBASE_DISTANCE:
		return
	var shift: float = craft.position.z
	_chain.position.z -= shift
	craft.position.z -= shift

func _process(_delta: float) -> void:
	var craft := get_node_or_null("InternalCruiser") as Node3D
	if craft != null and _chain != null:
		stream_step(chain_z(craft.position), CHUNKS_DRESSED_PER_FRAME, CHUNKS_FREED_PER_FRAME)

# Before the craft moves this tick (a parent runs before its children); the
# static bodies follow their moved parent.
func _physics_process(_delta: float) -> void:
	var craft := get_node_or_null("InternalCruiser") as Node3D
	if craft != null and _chain != null:
		rebase_around(craft)

func period() -> float:
	return InteriorLayout.chain_period(section_length, bridge_length)

# How far the chain has been moved along Z to keep the craft near the origin.
func get_chain_offset() -> float:
	return _chain.position.z

# Position along the chain of a point given in this node's coordinates.
func chain_z(point: Vector3) -> float:
	return point.z - _chain.position.z

# Above the docked bridge's platform, bow toward -Z, "up" toward the tube's
# axis (the platform sits at the bottom of the tube).
func get_spawn_transform() -> Transform3D:
	return Transform3D(Basis(), get_dock_position(0) + Vector3(0.0, SPAWN_HEIGHT, 0.0))

# The dock platform of bridge `slot`, in this node's coordinates.
func get_dock_position(slot: int) -> Vector3:
	return _platform_position() + Vector3(0.0, 0.0, InteriorLayout.bridge_slot_z(slot, period()) + _chain.position.z)

func nearest_dock_slot(point: Vector3) -> int:
	return InteriorLayout.nearest_bridge_slot(chain_z(point), period())

func get_bridge_ring_index(slot: int) -> int:
	return InteriorLayout.bridge_ring_index(docked_bridge_index, slot, ring_sections)

# Lights the sign of bridge `slot` when undocking is possible there; every
# other sign stays idle.
func set_undock_ready(slot: int, undock_ready: bool) -> void:
	for bridge_slot in _bridges:
		var lit: bool = undock_ready and bridge_slot == slot
		(_bridges[bridge_slot].get_node("Dock/Sign") as Label3D).modulate = SIGN_READY_COLOR if lit else SIGN_IDLE_COLOR

# The plan of section `slot`, or null while it is not generated.
func get_section_plan(slot: int):
	var state: SectionLoad = _sections.get(slot)
	return state.plan if state != null and state.task_id < 0 else null

func is_section_ready(slot: int) -> bool:
	return _sections.has(slot) and (_sections[slot] as SectionLoad).is_ready()

func get_loaded_section_slots() -> Array:
	var slots := []
	for slot in _sections:
		if not (_sections[slot] as SectionLoad).unloading:
			slots.append(slot)
	slots.sort()
	return slots

func get_bridge_slots() -> Array:
	var slots := _bridges.keys()
	slots.sort()
	return slots

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# A worker may still be generating a plan: never let it outlive us.
		for state: SectionLoad in _sections.values():
			if state.task_id >= 0:
				WorkerThreadPool.wait_for_task_completion(state.task_id)
				state.task_id = -1

# Starts every wanted section, marks far ones for unloading, and keeps the
# bridges at both ends of the loaded sections.
func _plan_window(focus_z: float) -> void:
	var p := period()
	for slot in InteriorLayout.sections_within(focus_z, p, LOAD_REACH * p):
		if not _sections.has(slot):
			_start_section(slot)
	for slot in _sections:
		var state: SectionLoad = _sections[slot]
		if state.task_id < 0 and absf(InteriorLayout.section_slot_z(slot, p) - focus_z) > UNLOAD_REACH * p:
			state.unloading = true
	_update_bridges()

func _start_section(slot: int) -> void:
	var state := SectionLoad.new()
	state.slot = slot
	state.ring_index = InteriorLayout.section_ring_index(docked_bridge_index, slot, ring_sections)
	state.radius = section_radius
	state.length = section_length
	state.node = _build_section_shell(slot)
	_chain.add_child(state.node)
	state.task_id = WorkerThreadPool.add_task(state.generate)
	_sections[slot] = state

# Takes the finished plan and queues the section's chunks, nearest first.
func _finish_plan(state: SectionLoad, focus_z: float) -> void:
	WorkerThreadPool.wait_for_task_completion(state.task_id)
	state.task_id = -1
	var start_z: float = InteriorLayout.section_slot_z(state.slot, period()) - section_length * 0.5
	var chunks := []
	for along in range(roundi(section_length / CHUNK_LENGTH)):
		for around in range(CHUNKS_AROUND):
			chunks.append(Vector2i(around, along))
	chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return absf(start_z + (a.y + 0.5) * CHUNK_LENGTH - focus_z) < absf(start_z + (b.y + 0.5) * CHUNK_LENGTH - focus_z))
	state.pending_chunks = chunks

# Dresses up to `budget` chunks, nearest section first. Returns how many.
func _dress_chunks(focus_z: float, budget: int) -> int:
	var p := period()
	var order: Array = _sections.values().filter(func(s: SectionLoad) -> bool:
		return s.task_id < 0 and not s.unloading and not s.pending_chunks.is_empty())
	order.sort_custom(func(a: SectionLoad, b: SectionLoad) -> bool:
		return absf(InteriorLayout.section_slot_z(a.slot, p) - focus_z) < absf(InteriorLayout.section_slot_z(b.slot, p) - focus_z))
	var dressed := 0
	for state: SectionLoad in order:
		while dressed < budget and not state.pending_chunks.is_empty():
			var key: Vector2i = state.pending_chunks.pop_front()
			_build_chunk(state, key.x, key.y)
			dressed += 1
	return dressed

# Frees up to `budget` chunks of unloading sections; a section with no chunks
# left goes with its caps and suns.
func _free_unloading(budget: int) -> void:
	var freed := 0
	for slot in _sections.keys():
		var state: SectionLoad = _sections[slot]
		if not state.unloading:
			continue
		for chunk in state.node.find_children("Chunk_*", "StaticBody3D", false, false):
			if freed >= budget:
				return
			chunk.free()
			freed += 1
		state.node.free()
		_sections.erase(slot)

func _update_bridges() -> void:
	var wanted := InteriorLayout.bridges_of_sections(get_loaded_section_slots())
	for slot in _bridges.keys():
		if not wanted.has(slot):
			(_bridges[slot] as Node3D).free()
			_bridges.erase(slot)
	for slot in wanted:
		if not _bridges.has(slot):
			var bridge := _build_bridge(slot)
			_chain.add_child(bridge)
			_bridges[slot] = bridge

func _platform_position() -> Vector3:
	return Vector3(0.0, -bridge_radius + DOCK_PLATFORM_SIZE.y * 0.5, 0.0)

# The section node at its centre, with its caps and suns; chunks come later.
func _build_section_shell(slot: int) -> Node3D:
	var section := Node3D.new()
	section.name = "Section_%d" % slot
	section.position = Vector3(0.0, 0.0, InteriorLayout.section_slot_z(slot, period()))
	# Both caps face into the section and have the bridge's hole: the way on
	# is always open.
	section.add_child(_build_cap("CapBehind", section_length * 0.5, -1.0))
	section.add_child(_build_cap("CapAhead", -section_length * 0.5, 1.0))
	var suns: PackedVector3Array = InteriorLayout.sun_positions(0.0, section_length, SUN_SPACING)
	for k in range(suns.size()):
		section.add_child(_build_sun("Sun_%02d" % k, suns[k]))
	return section

func _build_chunk(state: SectionLoad, around: int, along: int) -> void:
	var chunk := StaticBody3D.new()
	chunk.name = "Chunk_%02d_%02d" % [around, along]
	chunk.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), around * TAU / CHUNKS_AROUND), Vector3(0.0, 0.0, -section_length * 0.5 + along * CHUNK_LENGTH))
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = _chunk_shape
	chunk.add_child(collision)
	_dressing.dress_chunk(chunk, state.plan, around, along, state.groups.get(Vector2i(around, along), []))
	state.node.add_child(chunk)

func _build_cap(cap_name: String, z: float, facing: float) -> StaticBody3D:
	var cap := StaticBody3D.new()
	cap.name = cap_name
	# The annulus faces -Z; half a turn around Y makes it face +Z.
	var cap_basis := Basis() if facing < 0.0 else Basis(Vector3.UP, PI)
	cap.transform = Transform3D(cap_basis, Vector3(0.0, 0.0, z))
	_add_mesh_and_collision(cap, _cap_mesh, _cap_shape, _structure_material)
	return cap

func _fade_with_distance(light: Light3D) -> void:
	light.distance_fade_enabled = true
	light.distance_fade_begin = LIGHT_FADE_BEGIN
	light.distance_fade_length = LIGHT_FADE_LENGTH

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
	# headlights did), and 60 shadowed lights would cost too much.
	light.shadow_enabled = false
	_fade_with_distance(light)
	sun.add_child(light)
	return sun

func _build_bridge(slot: int) -> Node3D:
	var bridge := Node3D.new()
	bridge.name = "Bridge_%d" % slot
	bridge.position = Vector3(0.0, 0.0, InteriorLayout.bridge_slot_z(slot, period()))
	var segment_length: float = bridge_length / TUBE_SEGMENTS
	for k in range(TUBE_SEGMENTS):
		var segment := StaticBody3D.new()
		segment.name = "Segment_%d" % k
		segment.position = Vector3(0.0, 0.0, -bridge_length * 0.5 + k * segment_length)
		_add_mesh_and_collision(segment, _tube_mesh, _tube_shape, _structure_material)
		bridge.add_child(segment)
	bridge.add_child(_build_dock())
	return bridge

func _build_dock() -> Node3D:
	var dock := Node3D.new()
	dock.name = "Dock"

	var platform := StaticBody3D.new()
	platform.name = "Platform"
	platform.position = _platform_position()
	var box := BoxMesh.new()
	box.size = DOCK_PLATFORM_SIZE
	var box_shape := BoxShape3D.new()
	box_shape.size = DOCK_PLATFORM_SIZE
	# Same sci-fi pad as outside, on the box's top.
	_add_mesh_and_collision(platform, box, box_shape, DockPadTexture.platform_material(DOCK_PLATFORM_SIZE.x))
	dock.add_child(platform)

	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = _platform_position() + Vector3(0.0, 30.0, 0.0)
	light.light_color = SIGN_READY_COLOR
	light.light_energy = 2.0
	light.omni_range = DOCK_LIGHT_RANGE
	light.shadow_enabled = false
	_fade_with_distance(light)
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
	return dock

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
