extends Node3D

# The moon, a child of PlanetSystem beside the planet (so the world origin
# shift moves it with everything else). Tidally locked: seen from the ring's
# turning frame it is a rigid body turning about the planet's axis at
# relative_rate(), so its transform is a function of one angle.

const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const OrbitalFrame = preload("res://scripts/orbital_frame.gd")
const MoonBase = preload("res://scripts/moon_base.gd")
const MoonTerrain = preload("res://scripts/moon_terrain.gd")
const MoonPatch = preload("res://scripts/moon_patch.gd")
const MoonRocks = preload("res://scripts/moon_rocks.gd")
const MoonTracks = preload("res://scripts/moon_tracks.gd")
const MoonMesh = preload("res://scripts/moon_mesh.gd")
const PortalScript = preload("res://scripts/portal.gd")
const PortalRules = preload("res://scripts/portal_rules.gd")

const COLOR_PATH := "res://assets/textures/moon/color.jpg"
const NORMAL_PATH := "res://assets/textures/moon/normal.png"
# Past this distance from the moon's centre a light sphere (FAR_SEGMENTS
# round) stands in for the full mesh, with the same material.
const FAR_SWITCH := 1500000.0
const FAR_SEGMENTS := 96
# The moon portal's amber (the earth portal is blue).
const PORTAL_COLOR := Color(1.0, 0.7, 0.3)
const MOON_SHADER := """
shader_type spatial;

uniform sampler2D surface_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// The patch's rings sit at `offset` (moon axes) and carry their own relief:
// no normal map there (normal_depth 0).
uniform vec3 offset = vec3(0.0);
uniform float normal_depth = 1.0;
// The whole moon leaves a hole where the patch is: the square of points
// whose direction falls on the plane touching the sphere (radius
// `hole_radius`) at hole_up within `hole_half` metres each way of
// hole_centre along hole_x and hole_z, as the patch lays its points out
// (the cube face's plane; 0: no hole).
uniform vec3 hole_up = vec3(0.0, 1.0, 0.0);
uniform float hole_radius = 250000.0;
uniform vec3 hole_x = vec3(1.0, 0.0, 0.0);
uniform vec3 hole_z = vec3(0.0, 0.0, 1.0);
uniform vec2 hole_centre = vec2(0.0);
uniform float hole_half = 0.0;
// The patch's rings (moon_patch.gd): each vertex moves toward the next
// surface (CUSTOM0.xyz; CUSTOM1 its normal) with its distance from the
// camera, between MORPH_START and MORPH_END of the ring's half width
// (CUSTOM0.w).
uniform bool morph = false;
uniform float morph_start = 0.55;
uniform float morph_end = 0.85;

varying vec3 local_dir;
varying vec3 local_pos;

void vertex() {
	if (morph) {
		vec3 camera = transpose(mat3(MODEL_MATRIX)) * (CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz);
		float t = smoothstep(CUSTOM0.w * morph_start, CUSTOM0.w * morph_end, length(VERTEX - camera));
		VERTEX += CUSTOM0.xyz * t;
		NORMAL = normalize(mix(NORMAL, CUSTOM1.xyz, t));
	}
	local_pos = VERTEX + offset;
	local_dir = normalize(local_pos);
	// East (+Z at longitude 0) and north, for the normal map (x east, y
	// north).
	TANGENT = normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
	BINORMAL = cross(NORMAL, TANGENT);
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	// NASA's maps, equirectangular: longitude atan2(z, -x) (0 toward the
	// planet, east +Z) in the middle, north up. The longitude jumps where it
	// wraps (the far side): take the gradients of whichever of u and u + 0.5
	// is continuous here, so no seam line shows.
	float u = atan(local_dir.z, -local_dir.x) / TAU + 0.5;
	float v = acos(clamp(local_dir.y, -1.0, 1.0)) / PI;
	float shifted = fract(u + 0.5);
	vec2 dx = vec2(dFdx(u), dFdx(v));
	vec2 dy = vec2(dFdy(u), dFdy(v));
	vec2 dx2 = vec2(dFdx(shifted), dx.y);
	vec2 dy2 = vec2(dFdy(shifted), dy.y);
	if (abs(dx2.x) + abs(dy2.x) < abs(dx.x) + abs(dy.x)) {
		dx = dx2;
		dy = dy2;
	}
	if (hole_half > 0.0) {
		float facing = dot(local_dir, hole_up);
		// Anywhere on the face (its corners are 55 degrees off its axis),
		// never the far side.
		if (facing > 0.5) {
			vec2 on_plane = vec2(dot(local_dir, hole_x), dot(local_dir, hole_z)) * hole_radius / facing - hole_centre;
			if (abs(on_plane.x) < hole_half && abs(on_plane.y) < hole_half) {
				discard;
			}
		}
	}
	vec2 uv = vec2(u, v);
	// Fine grain for close-up flying: the colour map is ~190 m a pixel.
	float grain = value_noise(local_pos / 40.0) * 0.6 + value_noise(local_pos / 9.0) * 0.4;
	ALBEDO = textureGrad(surface_color, uv, dx, dy).rgb * (0.9 + 0.2 * grain);
	NORMAL_MAP = textureGrad(surface_normal, uv, dx, dy).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = 0.95;
}
"""

@export var planet_path: NodePath = NodePath("../Planet")
@export var planet_gm: float = OrbitalFrame.MOON_GM
@export var ring_radius: float = 6949600.0

var angle := MoonOrbit.START_ANGLE
# The angle the last advance() turned: a ship in the moon's frame is turned
# by the same (void_cruiser.gd), the moon moving first each tick.
var last_step := 0.0

func _ready() -> void:
	MoonTerrain.load_heights()
	build()
	_place()

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	last_step = relative_rate() * delta
	angle += last_step
	_place()

func _place() -> void:
	var planet := get_node_or_null(planet_path) as Node3D
	var planet_transform := Transform3D() if planet == null else planet.transform
	transform = planet_transform * Transform3D(MoonOrbit.moon_basis(angle), MoonOrbit.centre_offset(angle))
	# The base's physics body would learn its parent's move only when the
	# tree flushes transform notifications, and an animatable (kinematic)
	# body only moves at the next physics step: either way a tick late, ~32 m
	# off under a ship on a pad. A static body, told now, moves at once.
	for body_path in ["Base", "Rocks/RockBody"]:
		var body := get_node_or_null(body_path) as CollisionObject3D
		if body != null and body.is_inside_tree():
			PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	var portal := get_node_or_null("Portal")
	if portal != null:
		portal.sync_body()

func relative_rate() -> float:
	return MoonOrbit.relative_rate(planet_gm, ring_radius)

func planet_centre() -> Vector3:
	return (get_node(planet_path) as Node3D).global_position

# The planet's axis, which the moon turns about (world).
func axis() -> Vector3:
	return (get_node(planet_path) as Node3D).global_transform.basis.y.normalized()

# The moon's own frame turns at the moon's orbital rate (inertial terms).
func frame_omega() -> Vector3:
	return axis() * MoonOrbit.moon_rate(planet_gm)

func rel_omega() -> Vector3:
	return axis() * relative_rate()

func centre() -> Vector3:
	return global_position

func up_at(point: Vector3) -> Vector3:
	return (point - global_position).normalized()

# Height of `point` (world) over the ground under it (MoonTerrain).
func altitude(point: Vector3) -> float:
	var local: Vector3 = global_transform.affine_inverse() * point
	return local.length() - MoonOrbit.RADIUS - MoonTerrain.height(local.normalized())

# The ground's height under `point`, as a ground vehicle asks for it
# (GroundVehicle).
func ground_altitude(point: Vector3) -> float:
	return altitude(point)

# The base's flat ground: its distance from the moon's centre.
static func ground_radius() -> float:
	return MoonOrbit.RADIUS + MoonTerrain.base_height()

# Base Selene, in Plato (MoonOrbit.BASE_LATITUDE, BASE_LONGITUDE).
static func base_direction() -> Vector3:
	return MoonOrbit.base_direction()

static func direction_of(latitude: float, longitude: float) -> Vector3:
	return MoonOrbit.direction_of(latitude, longitude)

# East at the base, along the surface.
static func base_east() -> Vector3:
	return MoonMesh.base_east()

# The base site in the moon's frame: origin on the surface, y the local up,
# x east.
static func base_local_transform() -> Transform3D:
	var up := base_direction()
	var east := base_east()
	return Transform3D(Basis(east, up, east.cross(up)), up * ground_radius())

func base_transform() -> Transform3D:
	return global_transform * base_local_transform()

# Arc distances of the surface mesh's rings (MoonMesh).
static func ring_arcs() -> PackedFloat64Array:
	return MoonMesh.ring_arcs()

func build() -> void:
	var existing := get_node_or_null("Surface")
	if existing != null:
		remove_child(existing)
		existing.queue_free()
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = build_surface_mesh()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = MOON_SHADER
	material.shader = shader
	material.set_shader_parameter("surface_color", load(COLOR_PATH))
	material.set_shader_parameter("surface_normal", load(NORMAL_PATH))
	surface.material_override = material
	surface.visibility_range_end = FAR_SWITCH
	add_child(surface)
	var old_far := get_node_or_null("FarSurface")
	if old_far != null:
		remove_child(old_far)
		old_far.queue_free()
	var far := MeshInstance3D.new()
	far.name = "FarSurface"
	var sphere := SphereMesh.new()
	sphere.radius = MoonOrbit.RADIUS
	sphere.height = MoonOrbit.RADIUS * 2.0
	sphere.radial_segments = FAR_SEGMENTS
	sphere.rings = FAR_SEGMENTS / 2
	far.mesh = sphere
	far.material_override = material
	far.visibility_range_begin = FAR_SWITCH
	add_child(far)
	# The fine ground under the ship (see follow_patch), its own copy of the
	# material: offset to its rings, no normal map.
	var old_patch := get_node_or_null("Patch")
	if old_patch != null:
		remove_child(old_patch)
		old_patch.queue_free()
	var patch: Node3D = MoonPatch.new()
	patch.name = "Patch"
	var patch_material := material.duplicate() as ShaderMaterial
	patch_material.set_shader_parameter("normal_depth", 0.0)
	patch_material.set_shader_parameter("morph", true)
	patch_material.set_shader_parameter("morph_start", MoonPatch.MORPH_START)
	patch_material.set_shader_parameter("morph_end", MoonPatch.MORPH_END)
	patch.set_material(patch_material)
	patch.visible = false
	patch.rebuilt.connect(_on_patch_rebuilt.bind(patch, material, patch_material))
	add_child(patch)
	# Stones and boulders round the player (MoonRocks).
	var old_rocks := get_node_or_null("Rocks")
	if old_rocks != null:
		remove_child(old_rocks)
		old_rocks.queue_free()
	var rocks: Node3D = MoonRocks.new()
	rocks.name = "Rocks"
	add_child(rocks)
	# The rover's tracks, kept for the session (MoonTracks).
	if get_node_or_null("Tracks") == null:
		var tracks: Node3D = MoonTracks.new()
		tracks.name = "Tracks"
		add_child(tracks)
	var old_base := get_node_or_null("Base")
	if old_base != null:
		remove_child(old_base)
		old_base.queue_free()
	# Base Selene: a static body moved with the moon (see _place), as a ship
	# landed on it is (carried by the same turn).
	var base := StaticBody3D.new()
	base.name = "Base"
	base.transform = base_local_transform()
	MoonBase.build(base, ground_radius())
	add_child(base)
	var old_portal := get_node_or_null("Portal")
	if old_portal != null:
		remove_child(old_portal)
		old_portal.queue_free()
	# The moon portal, MOON_HEIGHT over the base, back to the ring.
	var portal: Node3D = PortalScript.new()
	portal.name = "Portal"
	portal.destination = "TERRA"
	portal.light_color = PORTAL_COLOR
	portal.transform = PortalRules.moon_local_transform(base_local_transform())
	add_child(portal)

# The ship at `point` (world): the fine ground under it while `active` (in
# the moon's frame), none otherwise.
func follow_patch(point: Vector3, active: bool, velocity := Vector3.ZERO) -> void:
	var patch := get_node_or_null("Patch")
	if patch == null:
		return
	if active:
		patch.follow(global_transform.affine_inverse() * point, global_transform.basis.inverse() * velocity)
	elif patch.visible or patch.built:
		patch.stop()
		((get_node("Surface") as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("hole_half", 0.0)

# The shader's hole test (MOON_SHADER, fragment), in GDScript for the
# tests: whether the whole moon leaves out moon-axes direction `direction`.
static func in_hole(direction: Vector3, up: Vector3, x: Vector3, z: Vector3, centre: Vector2, half: float, radius: float) -> bool:
	if half <= 0.0:
		return false
	var facing := direction.dot(up)
	if facing <= 0.5:
		return false
	var on_plane := Vector2(direction.dot(x), direction.dot(z)) * radius / facing - centre
	return absf(on_plane.x) < half and absf(on_plane.y) < half

# The stones round `point` (world); with `collide` (rover, walker) the near
# boulders' spheres too.
func follow_rocks(point: Vector3, collide: bool) -> void:
	var rocks := get_node_or_null("Rocks")
	if rocks != null:
		rocks.follow(global_transform.affine_inverse() * point, collide)

# New rings in place: the whole moon's hole and the patch's offset follow.
func _on_patch_rebuilt(patch: Node3D, material: ShaderMaterial, patch_material: ShaderMaterial) -> void:
	var axes: Dictionary = MoonPatch.face_axes(patch.face)
	patch_material.set_shader_parameter("offset", patch.origin())
	material.set_shader_parameter("hole_up", axes.axis)
	material.set_shader_parameter("hole_radius", MoonOrbit.RADIUS)
	material.set_shader_parameter("hole_x", axes.e1)
	material.set_shader_parameter("hole_z", axes.e2)
	material.set_shader_parameter("hole_centre", patch.hole_centre)
	# A metre short of the patch's edge: the two overlap rather than gap.
	material.set_shader_parameter("hole_half", patch.hole_half - 1.0)

# Base Selene's beacon, over the tower (world).
func beacon_position() -> Vector3:
	return (get_node("Base/Beacon") as Node3D).global_position

# The top centre of pad `number` (1-6), y the local up (world).
func pad_transform(number: int) -> Transform3D:
	var centre: Vector2 = MoonBase.pad_centres()[number - 1]
	var ground: Transform3D = MoonBase.ground(centre.x, centre.y, ground_radius())
	return base_transform() * Transform3D(ground.basis, ground.origin + ground.basis.y * MoonBase.PAD_HEIGHT)

# The whole moon's surface mesh (MoonMesh).
static func build_surface_mesh() -> ArrayMesh:
	return MoonMesh.build()
