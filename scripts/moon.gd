extends Node3D

# The moon, a child of PlanetSystem beside the planet (so the world origin
# shift moves it with everything else). Tidally locked: seen from the ring's
# turning frame it is a rigid body turning about the planet's axis at
# relative_rate(), so its transform is a function of one angle.

const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const OrbitalFrame = preload("res://scripts/orbital_frame.gd")
const MoonBase = preload("res://scripts/moon_base.gd")

const COLOR_PATH := "res://assets/textures/moon/color.png"
const NORMAL_PATH := "res://assets/textures/moon/normal.png"
# The surface mesh is laid out in rings round the base: DENSE_STEP apart up
# to DENSE_REACH from it, then each GROWTH times farther than the last, up
# to STEP_CAP; SEGMENTS round each ring. Near the base the chord sag is well
# under a centimetre; far away it stays within a few metres.
const SEGMENTS := 512
const DENSE_STEP := 20.0
const DENSE_REACH := 2000.0
const GROWTH := 1.08
const STEP_CAP := 3000.0
# Base Selene: 30 degrees from the point right under the planet (the moon's
# local -X), toward its local +Y.
const BASE_ANGLE := PI / 6.0
const MOON_SHADER := """
shader_type spatial;

uniform sampler2D surface_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 local_dir;
varying vec3 local_pos;

void vertex() {
	local_dir = normalize(VERTEX);
	local_pos = VERTEX;
	// East and north, for the crater normal map (x east, y north).
	TANGENT = normalize(cross(NORMAL, vec3(0.0, 1.0, 0.0)));
	BINORMAL = cross(TANGENT, NORMAL);
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
	// Equirectangular by direction. The longitude jumps where it wraps: take
	// the gradients of whichever of u and u + 0.5 is continuous here, so no
	// seam line shows.
	float u = atan(local_dir.z, local_dir.x) / TAU + 0.5;
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
	vec2 uv = vec2(u, v);
	// Fine grain for close-up flying: the maps are ~770 m a pixel.
	float grain = value_noise(local_pos / 40.0) * 0.6 + value_noise(local_pos / 9.0) * 0.4;
	ALBEDO = textureGrad(surface_color, uv, dx, dy).rgb * (0.9 + 0.2 * grain);
	NORMAL_MAP = textureGrad(surface_normal, uv, dx, dy).rgb;
	ROUGHNESS = 0.95;
}
"""

@export var planet_path: NodePath = NodePath("../Planet")
@export var planet_gm: float = OrbitalFrame.MOON_GM
@export var ring_radius: float = 6949600.0

var angle := MoonOrbit.START_ANGLE

func _ready() -> void:
	build()
	_place()

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	angle += relative_rate() * delta
	_place()

func _place() -> void:
	var planet := get_node_or_null(planet_path) as Node3D
	var planet_transform := Transform3D() if planet == null else planet.transform
	transform = planet_transform * Transform3D(MoonOrbit.moon_basis(angle), MoonOrbit.centre_offset(angle))
	# The base's physics body would learn its parent's move only when the
	# tree flushes transform notifications, and an animatable (kinematic)
	# body only moves at the next physics step: either way a tick late, ~32 m
	# off under a ship on a pad. A static body, told now, moves at once.
	var base := get_node_or_null("Base") as CollisionObject3D
	if base != null and base.is_inside_tree():
		PhysicsServer3D.body_set_state(base.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, base.global_transform)

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

func altitude(point: Vector3) -> float:
	return point.distance_to(global_position) - MoonOrbit.RADIUS

static func base_direction() -> Vector3:
	return Vector3(-cos(BASE_ANGLE), sin(BASE_ANGLE), 0.0)

# The base site in the moon's frame: origin on the surface, y the local up,
# x the moon's local +Z (east).
static func base_local_transform() -> Transform3D:
	var up := base_direction()
	var east := Vector3(0.0, 0.0, 1.0)
	return Transform3D(Basis(east, up, east.cross(up)), up * MoonOrbit.RADIUS)

func base_transform() -> Transform3D:
	return global_transform * base_local_transform()

# Arc distances from the base of the surface mesh's rings: 0 (the base
# itself) first, the antipode (pi * RADIUS) last.
static func ring_arcs() -> PackedFloat64Array:
	var arcs := PackedFloat64Array()
	var far := PI * MoonOrbit.RADIUS
	var s := 0.0
	var step := DENSE_STEP
	while s < far - step * 0.5:
		arcs.append(s)
		s += step
		if s >= DENSE_REACH:
			step = minf(step * GROWTH, STEP_CAP)
	arcs.append(far)
	return arcs

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
	add_child(surface)
	var old_base := get_node_or_null("Base")
	if old_base != null:
		remove_child(old_base)
		old_base.queue_free()
	# Base Selene: a static body moved with the moon (see _place), as a ship
	# landed on it is (carried by the same turn).
	var base := StaticBody3D.new()
	base.name = "Base"
	base.transform = base_local_transform()
	MoonBase.build(base, MoonOrbit.RADIUS)
	add_child(base)

# The top centre of pad `number` (1-6), y the local up (world).
func pad_transform(number: int) -> Transform3D:
	var centre: Vector2 = MoonBase.pad_centres()[number - 1]
	var ground: Transform3D = MoonBase.ground(centre.x, centre.y, MoonOrbit.RADIUS)
	return base_transform() * Transform3D(ground.basis, ground.origin + ground.basis.y * MoonBase.PAD_HEIGHT)

# The sphere in rings round the base (its pole): dense near it, sparse far.
# Vertex 0 is the base point, then SEGMENTS per ring, then the antipode.
static func build_surface_mesh() -> ArrayMesh:
	var arcs := ring_arcs()
	var pole := base_direction()
	var a := Vector3(0.0, 0.0, 1.0)
	var b := pole.cross(a)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.append(pole * MoonOrbit.RADIUS)
	normals.append(pole)
	var cosines := PackedFloat64Array()
	var sines := PackedFloat64Array()
	for i in range(SEGMENTS):
		cosines.append(cos(TAU * i / SEGMENTS))
		sines.append(sin(TAU * i / SEGMENTS))
	for k in range(1, arcs.size() - 1):
		var theta: float = arcs[k] / MoonOrbit.RADIUS
		var up_part: Vector3 = pole * cos(theta)
		var side: float = sin(theta)
		for i in range(SEGMENTS):
			var direction: Vector3 = up_part + (a * cosines[i] + b * sines[i]) * side
			vertices.append(direction * MoonOrbit.RADIUS)
			normals.append(direction)
	vertices.append(-pole * MoonOrbit.RADIUS)
	normals.append(-pole)
	var rings: int = arcs.size() - 2
	var last: int = vertices.size() - 1
	var indices := PackedInt32Array()
	# Winding (front faces out): with P(k, i) ring k's i-th vertex, the base
	# point as ring 0 and the antipode as ring `rings` + 1, a quad is
	# [P(k,i), P(k,i+1), P(k+1,i)] and [P(k,i+1), P(k+1,i+1), P(k+1,i)].
	for i in range(SEGMENTS):
		var next: int = (i + 1) % SEGMENTS
		indices.append_array(PackedInt32Array([0, 1 + next, 1 + i]))
	for k in range(rings - 1):
		var row: int = 1 + k * SEGMENTS
		var below: int = row + SEGMENTS
		for i in range(SEGMENTS):
			var next: int = (i + 1) % SEGMENTS
			indices.append_array(PackedInt32Array([row + i, row + next, below + i, row + next, below + next, below + i]))
	var outer: int = 1 + (rings - 1) * SEGMENTS
	for i in range(SEGMENTS):
		var next: int = (i + 1) % SEGMENTS
		indices.append_array(PackedInt32Array([outer + i, outer + next, last]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
