extends Node3D

const MoonPatch = preload("res://scripts/moon_patch.gd")

# The Moon Buggy's tracks on the regolith, a child of the moon (its axes):
# two strips WIDTH wide under the wheels of each side, a sample every
# SPACING of road on the ground; in the air the tracks break and start
# again on landing. Kept for the whole session (the moon outlives trips
# inside the station), in blocks of BLOCK samples, each with its own
# origin (precision), drawn within REACH. See-through, writing no depth,
# lifted off the ground more the farther the camera (24-bit depth).

const SPACING := 0.5
const MIN_SPEED := 0.3
# Samples further apart than this start a new strip.
const BREAK_GAP := 2.0
const WIDTH := 0.3
const HALF_TRACK := 0.9
# Each sample rebuilds its block's mesh: 25 m blocks keep that cheap; the
# last 100 km are kept.
const BLOCK := 50
const MAX_BLOCKS := 4000
const REACH := 600.0

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying vec2 track;
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float distance = length(world - CAMERA_POSITION_WORLD);
	VERTEX += NORMAL * max(0.02, 0.0004 * distance);
	track = UV;
}
void fragment() {
	// Chevrons of the tread across the strip, deeper in its middle.
	float across = abs(track.x - 0.5);
	float tread = step(0.5, fract(track.y * 3.0 + across * 1.6));
	ALBEDO = vec3(0.17, 0.165, 0.16);
	ROUGHNESS = 1.0;
	ALPHA = mix(0.32, 0.6, tread) * (1.0 - smoothstep(0.32, 0.5, across));
}
"""

# The ground under the left and right wheels of a rover at `at`.
static func wheel_points(at: Transform3D) -> Array:
	return [at * Vector3(-HALF_TRACK, 0.0, 0.0), at * Vector3(HALF_TRACK, 0.0, 0.0)]

# When to lay samples: `step` gives [[left, right, up, new_strip], ...]
# (often none), every SPACING along the way.
class Recorder:
	var _last := Vector3.INF
	var _broken := true

	func step(at: Transform3D, airborne: bool, speed: float) -> Array:
		if airborne:
			_broken = true
			return []
		if speed < MIN_SPEED:
			return []
		var gap := INF if _last == Vector3.INF else at.origin.distance_to(_last)
		if _broken or gap > BREAK_GAP:
			_broken = false
			_last = at.origin
			return [_sample(at, at.origin, true)]
		# Exactly every SPACING along the way covered this tick (a tick can
		# cover more than one).
		var samples := []
		var way := (at.origin - _last).normalized()
		while gap >= SPACING - 1e-6:
			_last += way * SPACING
			gap -= SPACING
			samples.append(_sample(at, _last, false))
		return samples

	func _sample(at: Transform3D, point: Vector3, fresh: bool) -> Array:
		var across := at.basis.x.normalized() * HALF_TRACK
		return [point - across, point + across, at.basis.y.normalized(), fresh]

var _material: ShaderMaterial
var _blocks := []
var _count := 0

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = Shader.new()
	_material.shader.code = SHADER

func sample_count() -> int:
	return _count

# The newest block's left-hand points (moon axes), for the tests.
func last_points() -> Array:
	return [] if _blocks.is_empty() else _blocks[-1].left

# `point` (moon axes) put on the ground as the patch draws it (unchanged
# off the moon: tests).
func _on_drawn_ground(point: Vector3) -> Vector3:
	var patch := get_parent().get_node_or_null("Patch") if get_parent() != null else null
	if patch == null:
		return point
	var direction := point.normalized()
	var face: int = patch.face if patch.face >= 0 else MoonPatch.face_of(direction, -1)
	return direction * MoonPatch.drawn_radius(face, direction)

# A sample (moon axes); `new_strip` starts the tracks afresh (after a jump).
func add(left: Vector3, right: Vector3, up: Vector3, new_strip: bool) -> void:
	_count += 1
	left = _on_drawn_ground(left)
	right = _on_drawn_ground(right)
	var block: Dictionary = {} if _blocks.is_empty() else _blocks[-1]
	if new_strip or block.is_empty() or block.left.size() >= BLOCK:
		var carry := not new_strip and not block.is_empty()
		block = {"left": [], "right": [], "up": [], "node": MeshInstance3D.new()}
		if carry:
			var last: Dictionary = _blocks[-1]
			block.left.append(last.left[-1])
			block.right.append(last.right[-1])
			block.up.append(last.up[-1])
		var node: MeshInstance3D = block.node
		node.position = left
		node.material_override = _material
		node.visibility_range_end = REACH
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_blocks.append(block)
		if _blocks.size() > MAX_BLOCKS:
			(_blocks[0].node as Node).queue_free()
			_blocks.remove_at(0)
	block.left.append(left)
	block.right.append(right)
	block.up.append(up)
	_rebuild(block)

func _rebuild(block: Dictionary) -> void:
	var node: MeshInstance3D = block.node
	if block.left.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for line in [block.left, block.right]:
		var along := 0.0
		for k in range(line.size() - 1):
			var a: Vector3 = line[k]
			var b: Vector3 = line[k + 1]
			var up: Vector3 = block.up[k + 1]
			var side := up.cross(b - a).normalized() * WIDTH * 0.5
			var length := a.distance_to(b)
			var corners := [[a - side, Vector2(0.0, along)], [a + side, Vector2(1.0, along)], [b + side, Vector2(1.0, along + length)], [b - side, Vector2(0.0, along + length)]]
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_normal(up)
				st.set_uv(corners[i][1])
				st.add_vertex((corners[i][0] as Vector3) - node.position)
			along += length
	node.mesh = st.commit()
