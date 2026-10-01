extends Node3D

# A wormhole portal: a ring 300 m across with eight blocks on its frame, a
# shimmering horizon across the opening, sixteen lamps chasing round the
# active face and a beacon seen from any distance. +Z is the active side
# (see PortalRules). The frame is solid (touching it is a crash, see
# void_cruiser.gd); the opening is not. The ship finds both portals by the
# "portals" group and jumps to the other one.

const PortalRules = preload("res://scripts/portal_rules.gd")
const TorusStation = preload("res://scripts/torus_station.gd")

const FRAME_SEGMENTS := 32
const FRAME_COLOR := Color(0.55, 0.57, 0.6)
const BLOCK_COUNT := 8
# Along the radius, along the portal's axis, round the ring.
const BLOCK_SIZE := Vector3(30.0, 28.0, 36.0)
const BLOCK_COLOR := Color(0.35, 0.37, 0.4)
const STRIP_SIZE := Vector3(3.0, 30.0, 20.0)
const LAMP_COUNT := 16
const LAMP_SIZE := 6.0
const LAMP_PERIOD := 1.6
const LAMP_ON_TIME := 0.25
const BEACON_SIZE := 30.0
const BEACON_MIN_PIXELS := 4.0
const BEACON_PERIOD := 1.2
const BEACON_ON_TIME := 0.2
const HORIZON_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 glow : source_color = vec3(0.3, 0.6, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	// A slow swirl: the angle turns faster toward the middle.
	float a = atan(p.y, p.x) + TIME * 0.6 + (1.0 - r) * 3.0;
	vec2 q = vec2(cos(a), sin(a)) * r * 4.0;
	float n = noise(q + TIME * 0.3) * 0.6 + noise(q * 2.3 - TIME * 0.5) * 0.4;
	float rim = smoothstep(0.75, 1.0, r);
	float core = 1.0 - smoothstep(0.0, 0.35, r);
	ALBEDO = glow * (0.25 + 0.5 * n + 0.8 * rim + 0.6 * core);
}
"""

@export var destination := "LUNA"
@export var light_color := Color(0.35, 0.65, 1.0)
# The earth portal sets itself on the ring's frame from PortalRules; the
# moon portal is placed by the moon.
@export var place_on_ring := false
@export var ring_radius: float = 6949600.0

func _ready() -> void:
	if place_on_ring:
		transform = PortalRules.earth_transform(ring_radius)
	build()

func build() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	add_to_group("portals")
	var metal := StandardMaterial3D.new()
	metal.albedo_color = FRAME_COLOR
	metal.metallic = 0.6
	metal.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = BLOCK_COLOR
	dark.metallic = 0.5
	dark.roughness = 0.5
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = light_color
	var frame := StaticBody3D.new()
	frame.name = "Frame"
	frame.add_to_group("portal_frames")
	add_child(frame)
	# The ring itself: a torus round the Z axis.
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = PortalRules.APERTURE_RADIUS
	torus.outer_radius = PortalRules.APERTURE_RADIUS + PortalRules.FRAME_WIDTH
	torus.rings = 96
	torus.ring_segments = 16
	ring.mesh = torus
	ring.material_override = metal
	ring.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	frame.add_child(ring)
	var middle := PortalRules.APERTURE_RADIUS + PortalRules.FRAME_WIDTH * 0.5
	for i in range(FRAME_SEGMENTS):
		var angle := TAU * i / FRAME_SEGMENTS
		var chord := 2.0 * middle * tan(PI / FRAME_SEGMENTS)
		frame.add_child(_collider("Segment%d" % i, angle, middle, Vector3(PortalRules.FRAME_WIDTH, PortalRules.FRAME_WIDTH, chord)))
	var block_mesh := BoxMesh.new()
	block_mesh.size = BLOCK_SIZE
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = STRIP_SIZE
	var block_at := PortalRules.APERTURE_RADIUS + BLOCK_SIZE.x * 0.5
	for i in range(BLOCK_COUNT):
		var angle := TAU * (i + 0.5) / BLOCK_COUNT
		var where := _radial(angle, block_at)
		var block := MeshInstance3D.new()
		block.name = "Block%d" % i
		block.mesh = block_mesh
		block.material_override = dark
		block.transform = where
		frame.add_child(block)
		# A lit strip on the block's outer face.
		var strip := MeshInstance3D.new()
		strip.name = "Strip%d" % i
		strip.mesh = strip_mesh
		strip.material_override = glow
		strip.transform = _radial(angle, block_at + BLOCK_SIZE.x * 0.5 + STRIP_SIZE.x * 0.5 - 1.0)
		frame.add_child(strip)
		frame.add_child(_collider("BlockCollider%d" % i, angle, block_at, BLOCK_SIZE))
	add_child(_horizon())
	var lamp_mesh := QuadMesh.new()
	lamp_mesh.size = Vector2.ONE
	var lamps := Node3D.new()
	lamps.name = "Lamps"
	add_child(lamps)
	for i in range(LAMP_COUNT):
		# Between the blocks.
		var angle := TAU * (i + 0.5) / LAMP_COUNT
		var lamp := MeshInstance3D.new()
		lamp.name = "Lamp%d" % i
		lamp.mesh = lamp_mesh
		lamp.material_override = _lamp_material(LAMP_SIZE, TorusStation.LAMP_MIN_PIXELS, LAMP_PERIOD, LAMP_ON_TIME, LAMP_PERIOD * i / LAMP_COUNT, false)
		# On the active face, facing out of it (the lamps show which side
		# leads in): the lamp's +Y along the portal's +Z.
		var at := Vector2(cos(angle), sin(angle)) * middle
		lamp.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(at.x, at.y, PortalRules.FRAME_WIDTH * 0.5 + 1.0))
		lamp.visibility_range_end = TorusStation.LAMP_RANGE
		lamp.extra_cull_margin = TorusStation.LAMP_CULL_MARGIN
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamps.add_child(lamp)
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	beacon.mesh = lamp_mesh
	beacon.material_override = _lamp_material(BEACON_SIZE, BEACON_MIN_PIXELS, BEACON_PERIOD, BEACON_ON_TIME, 0.0, true)
	beacon.position = Vector3(0.0, PortalRules.APERTURE_RADIUS + BLOCK_SIZE.x + 10.0, 0.0)
	# The quad grows with distance in the shader: never cull it by its box.
	beacon.extra_cull_margin = 16384.0
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)

# Where the ship enters (and leaves): this node's transform, in the world.
func active_transform() -> Transform3D:
	return global_transform if is_inside_tree() else transform

func beacon_position() -> Vector3:
	return (get_node("Beacon") as Node3D).global_position

# The other portal in the "portals" group, or null.
func other_portal() -> Node3D:
	if not is_inside_tree():
		return null
	for portal in get_tree().get_nodes_in_group("portals"):
		if portal != self:
			return portal
	return null

# A static body only learns of its parent's move a tick late (see
# moon.gd): the moon calls this right after moving.
func sync_body() -> void:
	var frame := get_node_or_null("Frame") as CollisionObject3D
	if frame != null and frame.is_inside_tree():
		PhysicsServer3D.body_set_state(frame.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, frame.global_transform)

# Pointing out from the centre at `angle` (in the portal's XY plane), `out`
# metres from it: local x radial, y along the portal's axis, z round.
static func _radial(angle: float, out: float) -> Transform3D:
	var radial := Vector3(cos(angle), sin(angle), 0.0)
	var round_way := Vector3(-sin(angle), cos(angle), 0.0)
	return Transform3D(Basis(radial, Vector3(0, 0, 1), -round_way), radial * out)

static func _collider(collider_name: String, angle: float, out: float, size: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = collider_name
	collider.shape = shape
	collider.transform = _radial(angle, out)
	return collider

func _horizon() -> MeshInstance3D:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = HORIZON_SHADER
	material.shader = shader
	material.set_shader_parameter("glow", light_color)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * PortalRules.APERTURE_RADIUS * 2.0
	var horizon := MeshInstance3D.new()
	horizon.name = "Horizon"
	horizon.mesh = quad
	horizon.material_override = material
	horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return horizon

# The station's lamp shader, with a phase (for the chase round the ring)
# and the option to show from behind as well.
func _lamp_material(size: float, min_pixels: float, period: float, on_time: float, phase: float, both_sides: bool) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = lamp_shader_code()
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("lamp_size", size)
	material.set_shader_parameter("min_pixels", min_pixels)
	material.set_shader_parameter("lamp_color", light_color)
	material.set_shader_parameter("period", period)
	material.set_shader_parameter("on_time", on_time)
	material.set_shader_parameter("phase", phase)
	material.set_shader_parameter("both_sides", both_sides)
	return material

static func lamp_shader_code() -> String:
	var code := TorusStation.LAMP_SHADER
	code = code.replace("uniform float on_time = 0.5;", "uniform float on_time = 0.5;\nuniform float phase = 0.0;\nuniform bool both_sides = false;")
	code = code.replace("facing = step(0.0, dot(pad_normal, -centre));", "facing = both_sides ? 1.0 : step(0.0, dot(pad_normal, -centre));")
	code = code.replace("mod(TIME, period)", "mod(TIME + period - phase, period)")
	return code
