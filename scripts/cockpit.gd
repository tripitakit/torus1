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

# distance key -> [label node name, HUD prefix], in display order.
const DISTANCE_LABELS := {
	"bow": ["BowLabel", "PRUA"],
	"stern": ["SternLabel", "POPPA"],
	"port": ["PortLabel", "SX"],
	"starboard": ["StarboardLabel", "DX"],
	"dorsal": ["DorsalLabel", "DORSO"],
	"ventral": ["VentralLabel", "VENTRE"],
}

func build() -> void:
	_build_pilot_camera()
	_build_hud()

func update_hud(speed: float, distances: Dictionary) -> void:
	var lines := get_node("Hud/Panel/Lines")
	(lines.get_node("SpeedLabel") as Label).text = "VEL  " + CockpitHudFormat.format_speed(speed)
	for key in DISTANCE_LABELS:
		var entry: Array = DISTANCE_LABELS[key]
		var distance: float = distances.get(key, -1.0)
		(lines.get_node(entry[0]) as Label).text = "%s  %s" % [entry[1], CockpitHudFormat.format_distance(distance)]

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
	for key in DISTANCE_LABELS:
		_add_hud_label(lines, DISTANCE_LABELS[key][0], label_settings)

	update_hud(0.0, {})

func _add_hud_label(parent: Node, label_name: String, label_settings: LabelSettings) -> void:
	var label := Label.new()
	label.name = label_name
	label.label_settings = label_settings
	parent.add_child(label)
