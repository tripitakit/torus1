extends Node3D

const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

# The ship's own exterior markers (nav-light spheres) sit on this visual
# layer; the pilot camera, inside the hull, skips them.
const SHIP_EXTERIOR_LAYER := 4
const ALL_LAYERS := 0xFFFFF

# Horizontal FOV (keep_aspect = KEEP_WIDTH): the same sideways view on any
# screen shape. Wider than 90° stretches objects near the edges too much
# with a flat perspective projection.
const PILOT_HFOV := 90.0
# The eye sits 7 m behind the bow face: a larger near plane would clip a
# surface touching the bow.
const PILOT_NEAR := 2.0
const PILOT_FAR := 69496000.0

const HUD_MARGIN := 24.0
const HUD_PADDING := 12.0
const HUD_FONT_SIZE := 22
const HUD_TEXT_COLOR := Color(0.4, 0.95, 1.0)
const HUD_BACKGROUND_COLOR := Color(0.02, 0.05, 0.08, 0.6)
const DOCK_PROMPT_TEXT := "DOCK  [F]"
const DOCK_PROMPT_COLOR := Color(0.3, 1.0, 0.4)
const CRUISE_TEXT := "CRUISE"
const CRUISE_COLOR := Color(1.0, 0.8, 0.3)
const WARNING_COLOR := Color(1.0, 0.3, 0.25)
# Orbit lines: [label node name, HUD prefix, readout key], in display order.
const ORBIT_LABELS := [
	["AltitudeLabel", "ALTITUDE", "altitude"],
	["PeriapsisLabel", "PERIAPSIS", "periapsis"],
	["ApoapsisLabel", "APOAPSIS", "apoapsis"],
]

# distance key -> [label node name, HUD prefix], in display order.
const DISTANCE_LABELS := {
	"bow": ["BowLabel", "BOW"],
	"stern": ["SternLabel", "STERN"],
	"port": ["PortLabel", "PORT"],
	"starboard": ["StarboardLabel", "STARBOARD"],
	"dorsal": ["DorsalLabel", "DORSAL"],
	"ventral": ["VentralLabel", "VENTRAL"],
}

var _text_settings: LabelSettings
var _cruise_settings: LabelSettings

func build() -> void:
	_build_pilot_camera()
	_build_hud()

func update_hud(speed: float, distances: Dictionary) -> void:
	var lines := get_node("Hud/Panel/Lines")
	(lines.get_node("SpeedLabel") as Label).text = "SPEED  " + CockpitHudFormat.format_speed(speed)
	for key in DISTANCE_LABELS:
		var entry: Array = DISTANCE_LABELS[key]
		var distance: float = distances.get(key, -1.0)
		(lines.get_node(entry[0]) as Label).text = "%s  %s" % [entry[1], CockpitHudFormat.format_distance(distance)]

func set_dock_prompt(available: bool) -> void:
	(get_node("Hud/Panel/Lines/DockLabel") as Label).visible = available

func set_cruise(active: bool) -> void:
	(get_node("Hud/Panel/Lines/CruiseLabel") as Label).visible = active

# `readout`: heights above the surface (see void_cruiser.gd orbit_readout);
# empty when there is no planet.
func update_orbit(assist_on: bool, readout: Dictionary) -> void:
	var lines := get_node("Hud/Panel/Lines")
	var assist: Label = lines.get_node("AssistLabel")
	assist.text = "ASSIST  ON" if assist_on else "ASSIST  OFF"
	assist.label_settings = _text_settings if assist_on else _cruise_settings
	for entry in ORBIT_LABELS:
		var value: float = readout.get(entry[2], INF)
		(lines.get_node(entry[0]) as Label).text = "%s  %s" % [entry[1], CockpitHudFormat.format_altitude(value)]
	(lines.get_node("ImpactLabel") as Label).visible = readout.has("periapsis") and readout.periapsis < 0.0
	(lines.get_node("EscapeLabel") as Label).visible = readout.has("apoapsis") and is_inf(readout.apoapsis)

func _build_pilot_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "PilotCamera"
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = PILOT_HFOV
	camera.near = PILOT_NEAR
	camera.far = PILOT_FAR
	camera.cull_mask = ALL_LAYERS & ~SHIP_EXTERIOR_LAYER
	camera.current = true
	add_child(camera)

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	add_child(hud)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(HUD_MARGIN, HUD_MARGIN)
	var background := StyleBoxFlat.new()
	background.bg_color = HUD_BACKGROUND_COLOR
	background.set_corner_radius_all(6)
	background.set_content_margin_all(HUD_PADDING)
	panel.add_theme_stylebox_override("panel", background)
	hud.add_child(panel)

	var lines := VBoxContainer.new()
	lines.name = "Lines"
	panel.add_child(lines)

	var label_settings := LabelSettings.new()
	label_settings.font_size = HUD_FONT_SIZE
	label_settings.font_color = HUD_TEXT_COLOR
	_text_settings = label_settings
	_add_hud_label(lines, "SpeedLabel", label_settings)
	var cruise_settings := LabelSettings.new()
	cruise_settings.font_size = HUD_FONT_SIZE
	cruise_settings.font_color = CRUISE_COLOR
	_cruise_settings = cruise_settings
	_add_hud_label(lines, "CruiseLabel", cruise_settings)
	var cruise_label: Label = lines.get_node("CruiseLabel")
	cruise_label.text = CRUISE_TEXT
	cruise_label.visible = false
	_add_hud_label(lines, "AssistLabel", label_settings)
	for entry in ORBIT_LABELS:
		_add_hud_label(lines, entry[0], label_settings)
	var warning_settings := LabelSettings.new()
	warning_settings.font_size = HUD_FONT_SIZE
	warning_settings.font_color = WARNING_COLOR
	for warning in [["ImpactLabel", "IMPACT"], ["EscapeLabel", "ESCAPE"]]:
		_add_hud_label(lines, warning[0], warning_settings)
		var warning_label: Label = lines.get_node(warning[0])
		warning_label.text = warning[1]
		warning_label.visible = false
	for key in DISTANCE_LABELS:
		_add_hud_label(lines, DISTANCE_LABELS[key][0], label_settings)

	var dock_settings := LabelSettings.new()
	dock_settings.font_size = HUD_FONT_SIZE
	dock_settings.font_color = DOCK_PROMPT_COLOR
	_add_hud_label(lines, "DockLabel", dock_settings)
	var dock_label: Label = lines.get_node("DockLabel")
	dock_label.text = DOCK_PROMPT_TEXT
	dock_label.visible = false

	update_hud(0.0, {})
	update_orbit(true, {})

func _add_hud_label(parent: Node, label_name: String, label_settings: LabelSettings) -> void:
	var label := Label.new()
	label.name = label_name
	label.label_settings = label_settings
	parent.add_child(label)
