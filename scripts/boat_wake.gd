extends RefCounted

# The boats' wakes, drawn by the shader alone like the boats (LoopTraffic):
# each wake vertex carries a lag (UV.x, seconds) and sits where the boat
# was that long ago, `lateral` to its left (VERTEX.x) and `along` ahead of
# its middle (VERTEX.z), so the wake follows the loop's curves. Two foam
# arms opening in a V behind the stern (ARM_TIME), a fainter band between
# them (CENTRE_TIME), two short whiskers off the bow (BOW_TIME). It fades
# with the lag and with the boat's speed then: a boat waiting at its pier
# leaves none. See-through, writing no depth, lifted off the water more
# the farther the camera (the 24-bit depth made a flat wake flicker), and
# gone past FAR_END. wake_point, speed_share, wake_alpha and wake_lift are
# the GDScript copies (tests).

const LoopTraffic = preload("res://scripts/loop_traffic.gd")

const STERN := -5.0
const BOW := 5.6
const ARM_TIME := 6.0
const CENTRE_TIME := 4.0
const BOW_TIME := 1.0
const ROWS := 12
# The boat's speed is read over this long; full wake from FULL_SPEED.
const SPEED_SAMPLE := 0.5
const FULL_SPEED := 6.0
const LIFT_NEAR := 0.15
const LIFT_PER_METRE := 0.0006
const FAR_START := 1200.0
const FAR_END := 1500.0
# [along, lateral at lag 0, lateral growth (m/s), width at lag 0, width at
# the end, duration, strength, mirrored each side]
const PIECES := [
	[STERN, 1.2, 1.5, 0.8, 3.0, ARM_TIME, 1.0, true],
	[STERN, 0.0, 0.0, 2.5, 6.0, CENTRE_TIME, 0.5, false],
	[BOW, 0.6, 3.0, 0.5, 1.2, BOW_TIME, 0.8, true],
]

const SHADER := """
shader_type spatial;
render_mode unshaded, skip_vertex_transform, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
%s
uniform float speed_sample = 0.5;
uniform float full_speed = 6.0;
uniform float lift_near = 0.15;
uniform float lift_per_metre = 0.0006;
uniform float far_start = 1200.0;
uniform float far_end = 1500.0;

varying float fade;
varying float edge;
varying float night;

void vertex() {
	float lag = UV.x;
	vec3 pos; vec3 left; vec3 up; vec3 forward;
	loop_pose(MODEL_MATRIX, TIME - lag, pos, left, up, forward);
	vec3 before; vec3 l2; vec3 u2; vec3 f2;
	loop_pose(MODEL_MATRIX, TIME - lag - speed_sample, before, l2, u2, f2);
	float share = clamp(length(pos - before) / speed_sample / full_speed, 0.0, 1.0);
	vec3 world = pos + left * VERTEX.x + forward * VERTEX.z;
	float distance = length(world - CAMERA_POSITION_WORLD);
	world += up * max(lift_near, lift_per_metre * distance);
	fade = max(0.0, 1.0 - lag / UV2.x) * share * UV2.y * (1.0 - smoothstep(far_start, far_end, distance));
	edge = UV.y;
	night = interior_night(interior_hour(world.z));
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	ALBEDO = vec3(0.85, 0.94, 1.0) * mix(1.0, 0.4, night);
	ALPHA = fade * edge * 0.85;
}
"""

# Strips of three vertices across (edge, middle, edge), ROWS + 1 rows down
# the lag. UV: (lag, 1 in the middle else 0); UV2: (duration, strength).
static func wake_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece in PIECES:
		var sides: Array = [-1.0, 1.0] if piece[7] else [0.0]
		for side: float in sides:
			var rows := []
			for r in range(ROWS + 1):
				var share := float(r) / ROWS
				var lag: float = piece[5] * share
				var centre: float = side * (piece[1] + piece[2] * lag)
				var width: float = lerpf(piece[3], piece[4], share)
				var row := []
				for k in range(3):
					row.append([Vector3(centre + (k - 1) * width * 0.5, 0.0, piece[0]), Vector2(lag, 1.0 if k == 1 else 0.0)])
				rows.append(row)
			for r in range(ROWS):
				for k in range(2):
					var quad := [rows[r][k], rows[r][k + 1], rows[r + 1][k + 1], rows[r + 1][k]]
					for i in [0, 1, 2, 0, 2, 3]:
						st.set_uv(quad[i][1])
						st.set_uv2(Vector2(piece[5], piece[6]))
						st.add_vertex(quad[i][0])
	return st.commit()

static func material(corner: float) -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = SHADER % LoopTraffic.LOOP_GLSL
	shader_material.set_shader_parameter("corner", corner)
	shader_material.set_shader_parameter("speed_sample", SPEED_SAMPLE)
	shader_material.set_shader_parameter("full_speed", FULL_SPEED)
	shader_material.set_shader_parameter("lift_near", LIFT_NEAR)
	shader_material.set_shader_parameter("lift_per_metre", LIFT_PER_METRE)
	shader_material.set_shader_parameter("far_start", FAR_START)
	shader_material.set_shader_parameter("far_end", FAR_END)
	return shader_material

static func wake_point(loop: Dictionary, t: float, lag: float, lateral: float, along: float, lift: float) -> Vector3:
	var frame := LoopTraffic.pose_at(loop, t - lag)
	return frame.origin + frame.basis.x * lateral + frame.basis.z * along + frame.basis.y * lift

static func speed_share(loop: Dictionary, t: float, lag: float) -> float:
	var now := LoopTraffic.pose_at(loop, t - lag).origin
	var before := LoopTraffic.pose_at(loop, t - lag - SPEED_SAMPLE).origin
	return clampf(now.distance_to(before) / SPEED_SAMPLE / FULL_SPEED, 0.0, 1.0)

static func wake_alpha(loop: Dictionary, t: float, lag: float, duration: float, strength: float) -> float:
	return maxf(0.0, 1.0 - lag / duration) * speed_share(loop, t, lag) * strength

static func wake_lift(distance: float) -> float:
	return maxf(LIFT_NEAR, LIFT_PER_METRE * distance)
