extends Control

# Two markers over a camera's view, shared by the void-cruiser's cockpit and
# the internal-cruiser:
# - the boresight, white, fixed at the centre: where the nose points;
# - the motion marker, magenta, where the craft is going: the classic
#   flight path marker (a ring with wings and a tail); when the motion is
#   behind the camera, a ring with an X at the opposite point (retrograde).
#   Off the screen it waits on the edge on its side. Hidden under MIN_SPEED.
# - the acceleration marker, orange, where the net acceleration points: a
#   triangle, upside down at the opposite point when it points behind the
#   camera. Hidden under MIN_ACCEL.

enum Motion { NONE, PROGRADE, RETROGRADE }

const BORESIGHT_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const MOTION_COLOR := Color(1.0, 0.2, 0.85, 0.95)
const BORESIGHT_RADIUS := 10.0
# The cross runs from inside the ring to this far out from the centre.
const CROSS_INNER := 4.0
const CROSS_OUTER := 16.0
const MARKER_RADIUS := 8.0
const WING := 10.0
const TAIL := 7.0
const LINE_WIDTH := 2.0
# A dark rim drawn under every line, so both markers read on white clouds and
# bright hulls as well as on black space.
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.75)
const OUTLINE_WIDTH := 4.0
const MIN_SPEED := 0.5
const ACCEL_COLOR := Color(1.0, 0.6, 0.2, 0.95)
const MIN_ACCEL := 0.05
const TRIANGLE := 9.0
# How far along the motion the projected point is taken (m).
const PROJECT_DISTANCE := 1000.0
# Off-screen motion waits this far inside the screen's edge (px).
const EDGE_MARGIN := 24.0

var motion: Motion = Motion.NONE
var motion_point := Vector2.ZERO
var accel: Motion = Motion.NONE
var accel_point := Vector2.ZERO

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Where the motion marker goes for `velocity` (world) seen by `camera`:
# {"kind": Motion, "point": screen position}. Worked out in the camera's own
# axes: motion toward the view is prograde, away from it retrograde (drawn
# at the opposite point). Motion off the screen, or square across the view
# (a strafe from rest), waits on the screen's edge on its side, EDGE_MARGIN
# in. In-tree camera only.
static func motion_marker(camera: Camera3D, velocity: Vector3) -> Dictionary:
	return direction_marker(camera, velocity, MIN_SPEED)

# The acceleration marker: placed like the motion marker (see there).
static func accel_marker(camera: Camera3D, acceleration: Vector3) -> Dictionary:
	return direction_marker(camera, acceleration, MIN_ACCEL)

# Where a marker for `vector`'s direction goes, hidden under `least`.
static func direction_marker(camera: Camera3D, vector: Vector3, least: float) -> Dictionary:
	if vector.length() < least:
		return {"kind": Motion.NONE, "point": Vector2.ZERO}
	var view: Basis = camera.global_transform.basis.orthonormalized()
	var d: Vector3 = view.inverse() * vector.normalized()
	var kind := Motion.PROGRADE
	if d.z > 1e-6:
		d = -d
		kind = Motion.RETROGRADE
	# The viewport's own size: the space unproject_position works in.
	var screen := Vector2(camera.get_viewport().size)
	var centre := screen * 0.5
	# Screen direction of the motion (y grows downward).
	var across := Vector2(d.x, -d.y)
	if -d.z > 1e-3:
		var point := camera.unproject_position(camera.global_position + view * d * PROJECT_DISTANCE)
		if Rect2(Vector2.ONE * EDGE_MARGIN, screen - Vector2.ONE * 2.0 * EDGE_MARGIN).has_point(point):
			return {"kind": kind, "point": point}
		across = point - centre
	if across.length() < 1e-9:
		return {"kind": kind, "point": centre}
	var room := centre - Vector2.ONE * EDGE_MARGIN
	var reach := minf(room.x / absf(across.x) if absf(across.x) > 1e-9 else INF, room.y / absf(across.y) if absf(across.y) > 1e-9 else INF)
	return {"kind": kind, "point": centre + across * reach}

func update_motion(camera: Camera3D, velocity: Vector3) -> void:
	var marker := motion_marker(camera, velocity)
	motion = marker.kind
	motion_point = marker.point
	queue_redraw()

func update_accel(camera: Camera3D, acceleration: Vector3) -> void:
	var marker := accel_marker(camera, acceleration)
	accel = marker.kind
	accel_point = marker.point
	queue_redraw()

func _draw() -> void:
	_draw_accel(OUTLINE_COLOR, OUTLINE_WIDTH)
	_draw_accel(ACCEL_COLOR, LINE_WIDTH)
	_draw_markers(OUTLINE_COLOR, OUTLINE_COLOR, OUTLINE_WIDTH)
	_draw_markers(BORESIGHT_COLOR, MOTION_COLOR, LINE_WIDTH)

func _draw_accel(color: Color, width: float) -> void:
	if accel == Motion.NONE:
		return
	var flip := 1.0 if accel == Motion.PROGRADE else -1.0
	var p := accel_point
	var points := PackedVector2Array([p + Vector2(0.0, -TRIANGLE) * flip, p + Vector2(TRIANGLE * 0.87, TRIANGLE * 0.5) * flip, p + Vector2(-TRIANGLE * 0.87, TRIANGLE * 0.5) * flip, p + Vector2(0.0, -TRIANGLE) * flip])
	draw_polyline(points, color, width, true)

func _draw_markers(boresight_color: Color, motion_color: Color, width: float) -> void:
	var centre := size * 0.5
	draw_arc(centre, BORESIGHT_RADIUS, 0.0, TAU, 32, boresight_color, width, true)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + d * CROSS_INNER, centre + d * CROSS_OUTER, boresight_color, width, true)
	if motion == Motion.NONE:
		return
	var p := motion_point
	draw_arc(p, MARKER_RADIUS, 0.0, TAU, 24, motion_color, width, true)
	if motion == Motion.PROGRADE:
		draw_line(p + Vector2(MARKER_RADIUS, 0.0), p + Vector2(MARKER_RADIUS + WING, 0.0), motion_color, width, true)
		draw_line(p - Vector2(MARKER_RADIUS, 0.0), p - Vector2(MARKER_RADIUS + WING, 0.0), motion_color, width, true)
		draw_line(p - Vector2(0.0, MARKER_RADIUS), p - Vector2(0.0, MARKER_RADIUS + TAIL), motion_color, width, true)
	else:
		var k := MARKER_RADIUS * 0.7
		draw_line(p + Vector2(-k, -k), p + Vector2(k, k), motion_color, width, true)
		draw_line(p + Vector2(-k, k), p + Vector2(k, -k), motion_color, width, true)
