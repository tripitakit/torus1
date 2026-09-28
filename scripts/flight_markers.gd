extends Control

# Two markers over a camera's view, shared by the void-cruiser's cockpit and
# the internal-cruiser:
# - the boresight, white, fixed at the centre: where the nose points;
# - the motion marker, magenta, where the craft is going: the classic
#   flight path marker (a ring with wings and a tail); when the motion is
#   behind the camera, a ring with an X at the opposite point (retrograde).
#   Hidden under MIN_SPEED.

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
# How far along the motion the projected point is taken (m).
const PROJECT_DISTANCE := 1000.0

var motion: Motion = Motion.NONE
var motion_point := Vector2.ZERO

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Where the motion marker goes for `velocity` (world) seen by `camera`:
# {"kind": Motion, "point": screen position}. In-tree camera only.
static func motion_marker(camera: Camera3D, velocity: Vector3) -> Dictionary:
	if velocity.length() < MIN_SPEED:
		return {"kind": Motion.NONE, "point": Vector2.ZERO}
	var eye := camera.global_position
	var along := velocity.normalized()
	var kind := Motion.PROGRADE
	if camera.is_position_behind(eye + along * PROJECT_DISTANCE):
		along = -along
		kind = Motion.RETROGRADE
	return {"kind": kind, "point": camera.unproject_position(eye + along * PROJECT_DISTANCE)}

func update_motion(camera: Camera3D, velocity: Vector3) -> void:
	var marker := motion_marker(camera, velocity)
	motion = marker.kind
	motion_point = marker.point
	queue_redraw()

func _draw() -> void:
	_draw_markers(OUTLINE_COLOR, OUTLINE_COLOR, OUTLINE_WIDTH)
	_draw_markers(BORESIGHT_COLOR, MOTION_COLOR, LINE_WIDTH)

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
