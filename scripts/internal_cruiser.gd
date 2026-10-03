extends "res://scripts/flying_craft.gd"

# The small craft flown inside the station: same controls as the
# void-cruiser, a shorter thrust ramp (it stops at 10x, about 1 km/s), no
# gravity, and a minimal HUD: the boresight and motion marker plus the
# current section's ID and time of day.

const FlightMarkersScript = preload("res://scripts/flight_markers.gd")
const SectionLabelScript = preload("res://scripts/section_label.gd")
const Clock = preload("res://scripts/interior_clock.gd")
const HULL_SIZE := Vector3(4.0, 2.0, 8.0)
const CAMERA_POSITION := Vector3(0.0, 0.3, -2.0)
const CAMERA_HFOV := 90.0
const CAMERA_NEAR := 0.2
const CAMERA_FAR := 60000.0
# With linear_damping 0.5 the top speed is thrust / ln 2: about 101 m/s at
# 1x, about 1 km/s at the end of the ramp (10x).
const INTERNAL_THRUST := 70.0
# The section-ID panel, top right (matches cockpit.gd's HUD style).
const HUD_MARGIN := 24.0
const HUD_PADDING := 12.0
const HUD_FONT_SIZE := 22
const HUD_TEXT_COLOR := Color(0.4, 0.95, 1.0)
const HUD_BACKGROUND_COLOR := Color(0.02, 0.05, 0.08, 0.6)
const SECTION_PANEL_WIDTH := 180.0

func _init() -> void:
	thrust_power = INTERNAL_THRUST

func _ready() -> void:
	build_collision_shape()
	build_camera()
	build_hud()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func build_collision_shape() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = HULL_SIZE
	shape_node.shape = box
	add_child(shape_node)

func build_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = CAMERA_POSITION
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAMERA_HFOV
	camera.near = CAMERA_NEAR
	camera.far = CAMERA_FAR
	camera.current = true
	add_child(camera)

# The boresight, the motion marker (see flight_markers.gd) and, top right,
# which section of the ring the craft is currently inside of and its hour.
func build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	add_child(hud)
	var markers: Control = FlightMarkersScript.new()
	markers.name = "FlightMarkers"
	hud.add_child(markers)

	var panel := PanelContainer.new()
	panel.name = "SectionPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -HUD_MARGIN - SECTION_PANEL_WIDTH
	panel.offset_right = -HUD_MARGIN
	panel.offset_top = HUD_MARGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var background := StyleBoxFlat.new()
	background.bg_color = HUD_BACKGROUND_COLOR
	background.set_corner_radius_all(6)
	background.set_content_margin_all(HUD_PADDING)
	panel.add_theme_stylebox_override("panel", background)
	hud.add_child(panel)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	panel.add_child(rows)
	var settings := LabelSettings.new()
	settings.font_size = HUD_FONT_SIZE
	settings.font_color = HUD_TEXT_COLOR
	for label_name in ["SectionLabel", "TimeLabel"]:
		var label := Label.new()
		label.name = label_name
		label.label_settings = settings
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows.add_child(label)

func _process(_delta: float) -> void:
	var markers := get_node_or_null("Hud/FlightMarkers") as Control
	var camera := get_node_or_null("Camera") as Camera3D
	if markers != null and camera != null and is_inside_tree():
		markers.update_motion(camera, velocity)
	_update_section_panel()

# Only needs this node's own `position` (local to the interior world, the
# chain's frame), so it works whether or not the craft is in the live tree.
func _update_section_panel() -> void:
	var label := get_node_or_null("Hud/SectionPanel/Rows/SectionLabel") as Label
	var interior := get_parent()
	if label == null or interior == null or not interior.has_method("nearest_section_slot"):
		return
	var slot: int = interior.nearest_section_slot(position)
	label.text = SectionLabelScript.format_id(interior.get_section_ring_index(slot))
	(get_node("Hud/SectionPanel/Rows/TimeLabel") as Label).text = Clock.format(interior.hour_at(position))

func _physics_process(delta: float) -> void:
	_fly(delta)
