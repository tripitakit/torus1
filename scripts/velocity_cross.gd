extends Control

# The ship's velocity (relative to the ring, like SPEED) split along its own
# axes: a cross for port / starboard across and dorsal / ventral up and
# down, and a separate bar for forward / aft. The speed sets a logarithmic
# length, from 1 m/s to 100 km/s, so docking speeds and full-ramp speeds both
# read; each bar shows its axis's share of it (see bar_reaches).
# The values sit in a fixed row under the bars: written at the bar tips they
# ran over each other at tens of km/s.

const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

const TOP_SPEED := 100000.0
const MIN_SPEED := 0.5
const PANEL_SIZE := Vector2(380.0, 230.0)
# Pixels from a bar's centre to its full length.
const ARM := 80.0
const CROSS_CENTRE := Vector2(130.0, 105.0)
const FORWARD_CENTRE := Vector2(300.0, 105.0)
const BAR_WIDTH := 4.0
const FONT_SIZE := 14
# The value row: one column per axis (lateral, vertical, forward).
const READOUT_COLUMNS := [0.0, 130.0, 260.0]
const READOUT_WIDTH := 120.0
const READOUT_BASELINE := 225.0
const BAR_COLOR := Color(0.4, 0.95, 1.0)
const AXIS_COLOR := Color(0.4, 0.95, 1.0, 0.3)
const CRUISE_COLOR := Color(1.0, 0.8, 0.3)

# (starboard, dorsal, forward) in m/s.
var components := Vector3.ZERO
var cruise := false

func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Velocity along the ship's own axes: +x starboard, +y dorsal, -z forward.
static func ship_components(ship_basis: Basis, velocity: Vector3) -> Vector3:
	var local := ship_basis.inverse() * velocity
	return Vector3(local.x, local.y, -local.z)

# How far a bar reaches, 0..1: nothing under MIN_SPEED, full at TOP_SPEED.
static func bar_fraction(speed: float) -> float:
	var magnitude := absf(speed)
	if magnitude < MIN_SPEED:
		return 0.0
	return clampf(log(1.0 + magnitude) / log(1.0 + TOP_SPEED), 0.0, 1.0)

# Signed bar lengths, 0..1 each way: the total speed's log length, shared
# out by each axis's part of the velocity. Bars scaled one by one made a few
# m/s look like a third of a bar, so turning the nose through broadside
# flipped the forward bar in one frame.
static func bar_reaches(values: Vector3) -> Vector3:
	var speed := values.length()
	if bar_fraction(speed) <= 0.0:
		return Vector3.ZERO
	return values / speed * bar_fraction(speed)

# The value row: each axis named by the way the ship moves along it.
static func readout(values: Vector3) -> Array:
	return [
		"%s %s" % ["STBD" if values.x >= 0.0 else "PORT", CockpitHudFormat.format_speed(absf(values.x))],
		"%s %s" % ["DOR" if values.y >= 0.0 else "VEN", CockpitHudFormat.format_speed(absf(values.y))],
		"%s %s" % ["FWD" if values.z >= 0.0 else "AFT", CockpitHudFormat.format_speed(absf(values.z))],
	]

func set_velocity(new_components: Vector3, cruise_locked: bool) -> void:
	components = new_components
	cruise = cruise_locked
	queue_redraw()

func _draw() -> void:
	draw_line(CROSS_CENTRE + Vector2(-ARM, 0.0), CROSS_CENTRE + Vector2(ARM, 0.0), AXIS_COLOR, 1.0)
	draw_line(CROSS_CENTRE + Vector2(0.0, -ARM), CROSS_CENTRE + Vector2(0.0, ARM), AXIS_COLOR, 1.0)
	draw_line(FORWARD_CENTRE + Vector2(0.0, -ARM), FORWARD_CENTRE + Vector2(0.0, ARM), AXIS_COLOR, 1.0)
	_label(CROSS_CENTRE + Vector2(-ARM - 40.0, 5.0), "PORT", AXIS_COLOR)
	_label(CROSS_CENTRE + Vector2(ARM + 4.0, 5.0), "STBD", AXIS_COLOR)
	_label(CROSS_CENTRE + Vector2(-14.0, -ARM - 6.0), "DOR", AXIS_COLOR)
	_label(CROSS_CENTRE + Vector2(-14.0, ARM + 16.0), "VEN", AXIS_COLOR)
	_label(FORWARD_CENTRE + Vector2(-14.0, -ARM - 6.0), "FWD", AXIS_COLOR)
	_label(FORWARD_CENTRE + Vector2(-14.0, ARM + 16.0), "AFT", AXIS_COLOR)
	var forward_color := CRUISE_COLOR if cruise else BAR_COLOR
	var reaches := bar_reaches(components)
	_bar(CROSS_CENTRE, Vector2(reaches.x, 0.0), BAR_COLOR)
	_bar(CROSS_CENTRE, Vector2(0.0, -reaches.y), BAR_COLOR)
	_bar(FORWARD_CENTRE, Vector2(0.0, -reaches.z), forward_color)
	var values := readout(components)
	for k in range(3):
		_label(Vector2(READOUT_COLUMNS[k], READOUT_BASELINE), values[k], forward_color if k == 2 else BAR_COLOR)

func _bar(origin: Vector2, reach: Vector2, color: Color) -> void:
	if reach.is_zero_approx():
		return
	draw_line(origin, origin + reach * ARM, color, BAR_WIDTH)

func _label(at: Vector2, text: String, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
