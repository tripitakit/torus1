extends Node3D

# Boot prints on the regolith, a child of the moon (its axes): one every
# WALK_STRIDE walking, JOG_STRIDE jogging (longer, deeper), left and right
# of the line SIDE_OFFSET out in turn; two side by side at a jump's
# take-off, two wide ones with a splash at landing. Kept for the session in
# MultiMesh blocks of BLOCK (each with its own origin), drawn within REACH;
# the shader draws the sole. See-through, writing no depth, lifted off the
# ground more the farther the camera (24-bit depth).

enum { WALK, JOG, TAKEOFF, LANDING }

const WALK_STRIDE := 0.7
const JOG_STRIDE := 1.4
const SIDE_OFFSET := 0.15
const PRINT_SIZE := Vector2(0.13, 0.32)
const JOG_LENGTH := 1.3
const LANDING_SCALE := 1.4
# The landing's splash reaches this far round the print (share of it).
const SPLASH := 1.6
const BLOCK := 512
const MAX_BLOCKS := 200
const REACH := 150.0

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying float kind;
varying float splash;
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float distance = length(world - CAMERA_POSITION_WORLD);
	VERTEX += vec3(0.0, 1.0, 0.0) * max(0.02, 0.0004 * distance);
	kind = INSTANCE_CUSTOM.x;
	splash = INSTANCE_CUSTOM.y;
}
void fragment() {
	// UV across 0..1, along 0..1 (toe at 1); the sole fills the middle of a
	// splash-sized square.
	vec2 p = (UV - 0.5) * splash + 0.5;
	vec2 q = abs(p - 0.5) - vec2(0.36, 0.42);
	float sole = 1.0 - smoothstep(0.0, 0.06, length(max(q, 0.0)) + min(max(q.x, q.y), 0.0));
	float ridges = 0.6 + 0.4 * step(0.45, fract(p.y * 9.0));
	float heel_gap = 1.0 - 0.5 * step(0.32, p.y) * step(p.y, 0.4);
	float depth = kind > 0.5 && kind < 1.5 ? 0.75 : 0.55;
	float halo = 0.0;
	if (kind > 2.5) {
		halo = 0.25 * (1.0 - smoothstep(0.2, 0.5, length(UV - 0.5)));
	}
	ALBEDO = vec3(0.16, 0.155, 0.15);
	ROUGHNESS = 1.0;
	ALPHA = max(sole * ridges * heel_gap * depth, halo);
}
"""

# When to leave prints: `step` gives [{side, kind}, ...] (often none).
class Gait:
	var _walked := 0.0
	var _side := 1.0
	# Between a take-off and its landing no prints.
	var _flying := false

	func step(moved: float, jogging: bool, took_off: bool, landed: bool) -> Array:
		if took_off:
			_walked = 0.0
			_flying = true
			return [{"side": -1.0, "kind": TAKEOFF}, {"side": 1.0, "kind": TAKEOFF}]
		if landed:
			_walked = 0.0
			_flying = false
			return [{"side": -1.0, "kind": LANDING}, {"side": 1.0, "kind": LANDING}]
		if _flying:
			return []
		var stride := JOG_STRIDE if jogging else WALK_STRIDE
		_walked += moved
		var prints := []
		while _walked >= stride - 1e-6:
			_walked -= stride
			_side = -_side
			prints.append({"side": _side, "kind": JOG if jogging else WALK})
		return prints

var _material: ShaderMaterial
var _mesh: PlaneMesh
var _blocks := []
var _count := 0

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = Shader.new()
	_material.shader.code = SHADER
	_mesh = PlaneMesh.new()
	_mesh.size = Vector2.ONE

func print_count() -> int:
	return _count

# A print by the feet at `feet` (moon axes), the walk going `nose`, `up` the
# local up, `side` -1 left, +1 right.
func add(feet: Vector3, nose: Vector3, up: Vector3, side: float, kind: int) -> void:
	var block: MultiMeshInstance3D = null if _blocks.is_empty() else _blocks[-1]
	if block == null or block.multimesh.visible_instance_count >= BLOCK:
		block = MultiMeshInstance3D.new()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = _mesh
		multimesh.instance_count = BLOCK
		multimesh.visible_instance_count = 0
		block.multimesh = multimesh
		block.material_override = _material
		block.position = feet
		block.visibility_range_end = REACH
		block.custom_aabb = AABB(-Vector3.ONE * REACH, Vector3.ONE * REACH * 2.0)
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(block)
		_blocks.append(block)
		if _blocks.size() > MAX_BLOCKS:
			(_blocks[0] as Node).queue_free()
			_blocks.remove_at(0)
	var y := up.normalized()
	var z := -(nose - y * nose.dot(y)).normalized()
	var x := y.cross(z)
	var size := PRINT_SIZE
	if kind == JOG:
		size.y *= JOG_LENGTH
	elif kind == LANDING:
		size *= LANDING_SCALE
	var splash := SPLASH if kind == LANDING else 1.0
	var at := feet + x * side * SIDE_OFFSET - block.position
	var n := block.multimesh.visible_instance_count
	block.multimesh.set_instance_transform(n, Transform3D(Basis(x * size.x * splash, y, -z * size.y * splash), at))
	block.multimesh.set_instance_custom_data(n, Color(float(kind), splash, side, 0.0))
	block.multimesh.visible_instance_count = n + 1
	_count += 1
