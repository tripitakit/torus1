extends Control

# The ship's accelerations along its own axes, like the velocity cross: its
# own share (engines, brake, flight computer, speed limit), the outside
# pulls (gravity, the turning frame) and the net, each an arrow in the
# across / up-down cross and a bar forward / aft. One log scale, MIN to TOP,
# so the moon's 0.1 g and the brake's 150 g both read. The values sit in a
# column on the right, in m/s2 and g.

const MIN := 0.01
const TOP := 20000.0
const G := 9.80665
const PANEL_SIZE := Vector2(380.0, 230.0)
const ARM := 75.0
const CROSS_CENTRE := Vector2(105.0, 105.0)
const FORWARD_CENTRE := Vector2(215.0, 105.0)
# The three forward bars side by side.
const FORWARD_SPREAD := 7.0
const BAR_WIDTH := 3.0
const HEAD := 7.0
const FONT_SIZE := 14
const READOUT_LEFT := 240.0
const READOUT_TOP := 70.0
const READOUT_STEP := 26.0
const AXIS_COLOR := Color(0.4, 0.95, 1.0, 0.3)
# Thrust, outside, net.
const COLORS := [Color(0.4, 0.95, 1.0), Color(1.0, 0.6, 0.2), Color(1.0, 1.0, 1.0)]
const NAMES := ["THR", "EXT", "NET"]

# (starboard, dorsal, forward) components, m/s2: thrust, outside, net.
var vectors: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]

func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Signed reaches, 0..1 each way: the magnitude's log length shared out by
# each axis's part (as the velocity cross does).
static func reach(values: Vector3) -> Vector3:
	var magnitude := values.length()
	if magnitude < MIN:
		return Vector3.ZERO
	var fraction := clampf(log(magnitude / MIN) / log(TOP / MIN), 0.0, 1.0)
	return values / magnitude * fraction

static func format_accel(value: float) -> String:
	var metres: String
	if value < 10.0:
		metres = "%.2f" % value
	elif value < 100.0:
		metres = "%.1f" % value
	else:
		metres = "%d" % roundi(value)
	var g := value / G
	return "%s m/s² %s g" % [metres, ("%.2f" % g) if g < 10.0 else ("%d" % roundi(g))]

static func readout(thrust: Vector3, outside: Vector3, net: Vector3) -> Array:
	var rows := []
	var values := [thrust, outside, net]
	for k in range(3):
		rows.append("%s %s" % [NAMES[k], format_accel((values[k] as Vector3).length())])
	return rows

# Components along the ship's axes (see VelocityCross.ship_components).
func set_accelerations(thrust: Vector3, outside: Vector3, net: Vector3) -> void:
	vectors = [thrust, outside, net]
	queue_redraw()

func _draw() -> void:
	draw_line(CROSS_CENTRE + Vector2(-ARM, 0.0), CROSS_CENTRE + Vector2(ARM, 0.0), AXIS_COLOR, 1.0)
	draw_line(CROSS_CENTRE + Vector2(0.0, -ARM), CROSS_CENTRE + Vector2(0.0, ARM), AXIS_COLOR, 1.0)
	draw_line(FORWARD_CENTRE + Vector2(0.0, -ARM), FORWARD_CENTRE + Vector2(0.0, ARM), AXIS_COLOR, 1.0)
	_label(CROSS_CENTRE + Vector2(-26.0, -ARM - 6.0), "ACCEL", AXIS_COLOR)
	_label(FORWARD_CENTRE + Vector2(-14.0, -ARM - 6.0), "FWD", AXIS_COLOR)
	_label(FORWARD_CENTRE + Vector2(-14.0, ARM + 16.0), "AFT", AXIS_COLOR)
	var rows := readout(vectors[0], vectors[1], vectors[2])
	for k in range(3):
		var r := reach(vectors[k])
		_arrow(CROSS_CENTRE, Vector2(r.x, -r.y) * ARM, COLORS[k])
		var column := FORWARD_CENTRE + Vector2((k - 1) * FORWARD_SPREAD, 0.0)
		if not is_zero_approx(r.z):
			draw_line(column, column + Vector2(0.0, -r.z * ARM), COLORS[k], BAR_WIDTH)
		_label(Vector2(READOUT_LEFT, READOUT_TOP + k * READOUT_STEP), rows[k], COLORS[k])

func _arrow(origin: Vector2, reach_px: Vector2, color: Color) -> void:
	if reach_px.length() < 1.0:
		return
	var tip := origin + reach_px
	var back := reach_px.normalized() * HEAD
	draw_line(origin, tip, color, BAR_WIDTH)
	draw_line(tip, tip - back + back.orthogonal() * 0.6, color, BAR_WIDTH)
	draw_line(tip, tip - back - back.orthogonal() * 0.6, color, BAR_WIDTH)

func _label(at: Vector2, text: String, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
