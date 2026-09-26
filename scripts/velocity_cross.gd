extends Control

# The ship's velocity (relative to the ring, like SPEED) split along its own
# axes: a cross for port / starboard across and dorsal / ventral up and
# down, and a separate bar for forward / aft. Bar lengths are logarithmic
# from 1 m/s to 100 km/s, so docking speeds and full-ramp speeds both read.

const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

const TOP_SPEED := 100000.0
const MIN_SPEED := 0.5
const PANEL_SIZE := Vector2(260.0, 200.0)
# Pixels from a bar's centre to its full length.
const ARM := 80.0
const CROSS_CENTRE := Vector2(100.0, 100.0)
const FORWARD_CENTRE := Vector2(225.0, 100.0)
const BAR_WIDTH := 4.0
const FONT_SIZE := 14
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

func set_velocity(new_components: Vector3, cruise_locked: bool) -> void:
	components = new_components
	cruise = cruise_locked
	queue_redraw()

func _draw() -> void:
	draw_line(CROSS_CENTRE + Vector2(-ARM, 0.0), CROSS_CENTRE + Vector2(ARM, 0.0), AXIS_COLOR, 1.0)
	draw_line(CROSS_CENTRE + Vector2(0.0, -ARM), CROSS_CENTRE + Vector2(0.0, ARM), AXIS_COLOR, 1.0)
	draw_line(FORWARD_CENTRE + Vector2(0.0, -ARM), FORWARD_CENTRE + Vector2(0.0, ARM), AXIS_COLOR, 1.0)
	_label(CROSS_CENTRE + Vector2(-ARM - 36.0, 5.0), "PORT", AXIS_COLOR)
	_label(CROSS_CENTRE + Vector2(ARM + 4.0, 5.0), "STBD", AXIS_COLOR)
	_label(CROSS_CENTRE + Vector2(-14.0, -ARM - 6.0), "DOR", AXIS_COLOR)
	_label(CROSS_CENTRE + Vector2(-14.0, ARM + 16.0), "VEN", AXIS_COLOR)
	_label(FORWARD_CENTRE + Vector2(-14.0, -ARM - 6.0), "FWD", AXIS_COLOR)
	_label(FORWARD_CENTRE + Vector2(-14.0, ARM + 16.0), "AFT", AXIS_COLOR)
	_bar(CROSS_CENTRE, Vector2(signf(components.x), 0.0), components.x, BAR_COLOR)
	_bar(CROSS_CENTRE, Vector2(0.0, -signf(components.y)), components.y, BAR_COLOR)
	_bar(FORWARD_CENTRE, Vector2(0.0, -signf(components.z)), components.z, CRUISE_COLOR if cruise else BAR_COLOR)

func _bar(origin: Vector2, direction: Vector2, speed: float, color: Color) -> void:
	var reach := bar_fraction(speed)
	if reach <= 0.0:
		return
	var tip := origin + direction * ARM * reach
	draw_line(origin, tip, color, BAR_WIDTH)
	_label(tip + direction * 6.0 + Vector2(4.0, 4.0), CockpitHudFormat.format_speed(absf(speed)), color)

func _label(at: Vector2, text: String, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
