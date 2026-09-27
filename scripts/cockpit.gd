extends Node3D

const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")
const VelocityCrossScript = preload("res://scripts/velocity_cross.gd")
const NavballScript = preload("res://scripts/navball.gd")

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
const BRAKE_TEXT := "BRAKE"
const BRAKE_COLOR := Color(1.0, 0.45, 0.3)
const THRUST_TEXT := "THRUST  %.1fx"

# distance key -> [label node name, HUD prefix], in display order.
const DISTANCE_LABELS := {
	"bow": ["BowLabel", "BOW"],
	"stern": ["SternLabel", "STERN"],
	"port": ["PortLabel", "PORT"],
	"starboard": ["StarboardLabel", "STARBOARD"],
	"dorsal": ["DorsalLabel", "DORSAL"],
	"ventral": ["VentralLabel", "VENTRAL"],
}

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

func set_brake(active: bool) -> void:
	(get_node("Hud/Panel/Lines/BrakeLabel") as Label).visible = active

# Shown only while the thrust is scaled down near a dock.
func set_thrust_scale(scale: float) -> void:
	var label := get_node("Hud/Panel/Lines/ThrustLabel") as Label
	label.visible = scale < 1.0
	label.text = THRUST_TEXT % scale

# Velocity along the ship's axes (starboard, dorsal, forward), in m/s.
func update_velocity(components: Vector3, cruise: bool) -> void:
	(get_node("Hud/VelocityCross") as Control).set_velocity(components, cruise)

# The ship's attitude in the ring's frame (see Attitude.navball_matrix).
func update_attitude(matrix: Basis) -> void:
	(get_node("Hud/Navball") as Control).set_attitude(matrix)

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
	_add_hud_label(lines, "SpeedLabel", label_settings)
	var cruise_settings := LabelSettings.new()
	cruise_settings.font_size = HUD_FONT_SIZE
	cruise_settings.font_color = CRUISE_COLOR
	_add_hud_label(lines, "CruiseLabel", cruise_settings)
	var cruise_label: Label = lines.get_node("CruiseLabel")
	cruise_label.text = CRUISE_TEXT
	cruise_label.visible = false
	var brake_settings := LabelSettings.new()
	brake_settings.font_size = HUD_FONT_SIZE
	brake_settings.font_color = BRAKE_COLOR
	_add_hud_label(lines, "BrakeLabel", brake_settings)
	var brake_label: Label = lines.get_node("BrakeLabel")
	brake_label.text = BRAKE_TEXT
	brake_label.visible = false
	_add_hud_label(lines, "ThrustLabel", label_settings)
	(lines.get_node("ThrustLabel") as Label).visible = false
	for key in DISTANCE_LABELS:
		_add_hud_label(lines, DISTANCE_LABELS[key][0], label_settings)

	var dock_settings := LabelSettings.new()
	dock_settings.font_size = HUD_FONT_SIZE
	dock_settings.font_color = DOCK_PROMPT_COLOR
	_add_hud_label(lines, "DockLabel", dock_settings)
	var dock_label: Label = lines.get_node("DockLabel")
	dock_label.text = DOCK_PROMPT_TEXT
	dock_label.visible = false

	# Bottom-left corner, clear of the text panel at the top.
	var cross: Control = VelocityCrossScript.new()
	cross.name = "VelocityCross"
	cross.anchor_left = 0.0
	cross.anchor_right = 0.0
	cross.anchor_top = 1.0
	cross.anchor_bottom = 1.0
	cross.offset_left = HUD_MARGIN
	cross.offset_right = HUD_MARGIN + VelocityCrossScript.PANEL_SIZE.x
	cross.offset_top = -HUD_MARGIN - VelocityCrossScript.PANEL_SIZE.y
	cross.offset_bottom = -HUD_MARGIN
	hud.add_child(cross)
	# Top centre.
	var navball: Control = NavballScript.new()
	navball.name = "Navball"
	navball.anchor_left = 0.5
	navball.anchor_right = 0.5
	navball.anchor_top = 0.0
	navball.anchor_bottom = 0.0
	navball.offset_left = -NavballScript.PANEL_SIZE.x * 0.5
	navball.offset_right = NavballScript.PANEL_SIZE.x * 0.5
	navball.offset_top = HUD_MARGIN
	navball.offset_bottom = HUD_MARGIN + NavballScript.PANEL_SIZE.y
	hud.add_child(navball)

	update_hud(0.0, {})

func _add_hud_label(parent: Node, label_name: String, label_settings: LabelSettings) -> void:
	var label := Label.new()
	label.name = label_name
	label.label_settings = label_settings
	parent.add_child(label)
