extends Node3D

const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")
const VelocityCrossScript = preload("res://scripts/velocity_cross.gd")
const NavballScript = preload("res://scripts/navball.gd")
const FlightMarkersScript = preload("res://scripts/flight_markers.gd")
const BeaconMarkerScript = preload("res://scripts/beacon_marker.gd")

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
const LIMIT_COLOR_BRAKING := Color(1.0, 0.65, 0.2)
# The approach panel, top right: readout key -> label, in display order.
const APPROACH_LINES := {
	"dist": "DistLabel",
	"speed": "RelSpeedLabel",
	"advised": "AdvisedLabel",
	"eta": "EtaLabel",
	"status": "StatusLabel",
}
const APPROACH_PANEL_WIDTH := 300.0
# The gate panel, top centre, near a portal: readout key -> label.
const GATE_LINES := {
	"gate": "GateLabel",
	"approach": "ApproachLabel",
	"side": "SideLabel",
}
const GATE_PANEL_WIDTH := 340.0
const GATE_MARKER_COLOR := Color(0.45, 0.75, 1.0, 0.95)
# The flight computer's panel, right, under the approach and moon panels:
# readout key -> label (FlightComputer.lines).
const NAV_LINES := {
	"nav": "NavLabel",
	"dist": "DistLabel",
	"closing": "ClosingLabel",
	"eta": "EtaLabel",
	"stop": "StopLabel",
	"brake": "BrakeLabel",
	"auto": "AutoLabel",
}
const NAV_PANEL_TOP := 300.0
const NAV_MARKER_COLOR := Color(0.35, 1.0, 0.45, 0.95)
# The moon panel (same place as the approach panel): readout key -> label.
const MOON_LINES := {
	"pad": "PadLabel",
	"alt": "AltLabel",
	"vs": "VsLabel",
	"drift": "DriftLabel",
	"level": "LevelLabel",
	"status": "StatusLabel",
}
# By DockingAssist.Rating: OK, CAUTION, OVER.
const APPROACH_COLORS := [Color(0.3, 1.0, 0.4), Color(1.0, 0.8, 0.3), Color(1.0, 0.3, 0.25)]

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

# The zone's speed limit; orange while the flight computer brakes down to it.
func set_speed_limit(limit: float, braking: bool) -> void:
	var label := get_node("Hud/Panel/Lines/LimitLabel") as Label
	label.text = "LIMIT  " + CockpitHudFormat.format_speed(limit)
	label.label_settings.font_color = LIMIT_COLOR_BRAKING if braking else HUD_TEXT_COLOR

func set_dock_prompt(available: bool) -> void:
	(get_node("Hud/Panel/Lines/DockLabel") as Label).visible = available

func set_cruise(active: bool) -> void:
	(get_node("Hud/Panel/Lines/CruiseLabel") as Label).visible = active

func set_brake(active: bool) -> void:
	(get_node("Hud/Panel/Lines/BrakeLabel") as Label).visible = active

# The approach panel from a DockingAssist.readout; hidden when empty. The
# relative speed is coloured by its rating, the status green when ready.
func update_approach(readout: Dictionary) -> void:
	var panel := get_node("Hud/ApproachPanel") as Control
	panel.visible = not readout.is_empty()
	if readout.is_empty():
		return
	var lines := panel.get_node("Lines")
	for key in APPROACH_LINES:
		(lines.get_node(APPROACH_LINES[key]) as Label).text = readout[key]
	(lines.get_node("RelSpeedLabel") as Label).label_settings.font_color = APPROACH_COLORS[readout.rating]
	var status := lines.get_node("StatusLabel") as Label
	status.visible = readout.status != ""
	status.label_settings.font_color = APPROACH_COLORS[0] if readout.ready else APPROACH_COLORS[2]

# Landing on the moon (LandingReadout.readout); empty hides the panel. Empty
# pad and status lines are hidden.
func update_moon(readout: Dictionary) -> void:
	var panel := get_node("Hud/MoonPanel") as Control
	panel.visible = not readout.is_empty()
	if readout.is_empty():
		return
	var lines := panel.get_node("Lines")
	for key in MOON_LINES:
		var label := lines.get_node(MOON_LINES[key]) as Label
		label.text = readout[key]
		label.visible = readout[key] != ""
		if readout.colors.has(key):
			label.label_settings.font_color = readout.colors[key]
	var status := lines.get_node("StatusLabel") as Label
	status.label_settings.font_color = APPROACH_COLORS[0] if readout.status == "LANDED" else APPROACH_COLORS[2]

# The gate panel: PortalRules.readout(), or empty to hide it.
func update_gate(readout: Dictionary) -> void:
	var panel := get_node("Hud/GatePanel") as Control
	panel.visible = not readout.is_empty()
	if readout.is_empty():
		return
	var lines := panel.get_node("Lines")
	for key in GATE_LINES:
		var label := lines.get_node(GATE_LINES[key]) as Label
		label.text = readout[key]
		label.visible = readout[key] != ""
		if readout.colors.has(key):
			label.label_settings.font_color = readout.colors[key]

# The flight computer's panel: FlightComputer.lines(), or empty to hide it.
func update_nav(lines: Dictionary) -> void:
	var panel := get_node("Hud/NavPanel") as Control
	panel.visible = not lines.is_empty()
	if lines.is_empty():
		return
	var labels := panel.get_node("Lines")
	for key in NAV_LINES:
		var label := labels.get_node(NAV_LINES[key]) as Label
		label.text = lines[key]
		label.visible = lines[key] != ""
		label.label_settings.font_color = lines.colors.get(key, HUD_TEXT_COLOR)

# The flight computer's leg marker: `name` at `target` (world), `distance`
# away.
func update_nav_marker(marker_name: String, target: Vector3, distance: float, shown: bool) -> void:
	var marker := get_node("Hud/NavMarker")
	marker.prefix = marker_name
	if shown and has_node("PilotCamera") and is_inside_tree():
		marker.update_target(get_node("PilotCamera") as Camera3D, target, distance, true)
	else:
		marker.update_target(null, target, distance, false)

# The nearest portal's marker, at `target` (world), `distance` away.
func update_gate_marker(target: Vector3, distance: float, shown: bool) -> void:
	var marker := get_node("Hud/GateMarker")
	if shown and has_node("PilotCamera") and is_inside_tree():
		marker.update_target(get_node("PilotCamera") as Camera3D, target, distance, true)
	else:
		marker.update_target(null, target, distance, false)

# Base Selene's marker: the beacon at `target` (world), `distance` away.
func update_beacon(target: Vector3, distance: float, shown: bool) -> void:
	var marker := get_node("Hud/BeaconMarker")
	if shown and has_node("PilotCamera") and is_inside_tree():
		marker.update_target(get_node("PilotCamera") as Camera3D, target, distance, true)
	else:
		marker.update_target(null, target, distance, false)

# Shown only while the thrust is scaled down near a dock.
func set_thrust_scale(scale: float) -> void:
	var label := get_node("Hud/Panel/Lines/ThrustLabel") as Label
	label.visible = scale < 1.0
	# Two decimals under 0.1 (low over the moon it goes down to ~0.013).
	label.text = (THRUST_TEXT % scale) if scale >= 0.1 else "THRUST  %.2fx" % scale

# Velocity along the ship's axes (starboard, dorsal, forward), in m/s.
func update_velocity(components: Vector3, cruise: bool) -> void:
	(get_node("Hud/VelocityCross") as Control).set_velocity(components, cruise)

# The boresight and the motion marker for `velocity` (world, m/s) seen by
# the pilot camera. In-tree only.
func update_motion(velocity: Vector3) -> void:
	(get_node("Hud/FlightMarkers") as Control).update_motion(get_node("PilotCamera") as Camera3D, velocity)

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
	# Its own settings: it turns orange.
	var limit_settings := LabelSettings.new()
	limit_settings.font_size = HUD_FONT_SIZE
	limit_settings.font_color = HUD_TEXT_COLOR
	_add_hud_label(lines, "LimitLabel", limit_settings)
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
	# Top right, growing leftward: the approach to the nearest dock.
	var approach := PanelContainer.new()
	approach.name = "ApproachPanel"
	approach.anchor_left = 1.0
	approach.anchor_right = 1.0
	approach.offset_left = -HUD_MARGIN - APPROACH_PANEL_WIDTH
	approach.offset_right = -HUD_MARGIN
	approach.offset_top = HUD_MARGIN
	approach.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	approach.add_theme_stylebox_override("panel", background)
	approach.visible = false
	hud.add_child(approach)
	var approach_lines := VBoxContainer.new()
	approach_lines.name = "Lines"
	approach.add_child(approach_lines)
	for key in APPROACH_LINES:
		# Each its own settings: the speed and status lines change colour.
		var settings := LabelSettings.new()
		settings.font_size = HUD_FONT_SIZE
		settings.font_color = HUD_TEXT_COLOR
		_add_hud_label(approach_lines, APPROACH_LINES[key], settings)
	# Top right too, instead of the approach panel near the moon.
	var moon := PanelContainer.new()
	moon.name = "MoonPanel"
	moon.anchor_left = 1.0
	moon.anchor_right = 1.0
	moon.offset_left = -HUD_MARGIN - APPROACH_PANEL_WIDTH
	moon.offset_right = -HUD_MARGIN
	moon.offset_top = HUD_MARGIN
	moon.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	moon.add_theme_stylebox_override("panel", background)
	moon.visible = false
	hud.add_child(moon)
	var moon_lines := VBoxContainer.new()
	moon_lines.name = "Lines"
	moon.add_child(moon_lines)
	for key in MOON_LINES:
		var settings := LabelSettings.new()
		settings.font_size = HUD_FONT_SIZE
		settings.font_color = HUD_TEXT_COLOR
		_add_hud_label(moon_lines, MOON_LINES[key], settings)
	# Right, under the approach and moon panels: the flight computer.
	var nav := PanelContainer.new()
	nav.name = "NavPanel"
	nav.anchor_left = 1.0
	nav.anchor_right = 1.0
	nav.offset_left = -HUD_MARGIN - APPROACH_PANEL_WIDTH
	nav.offset_right = -HUD_MARGIN
	nav.offset_top = NAV_PANEL_TOP
	nav.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	nav.add_theme_stylebox_override("panel", background)
	nav.visible = false
	hud.add_child(nav)
	var nav_lines := VBoxContainer.new()
	nav_lines.name = "Lines"
	nav.add_child(nav_lines)
	for key in NAV_LINES:
		var settings := LabelSettings.new()
		settings.font_size = HUD_FONT_SIZE
		settings.font_color = HUD_TEXT_COLOR
		_add_hud_label(nav_lines, NAV_LINES[key], settings)
	# Top centre: the approach to a portal.
	var gate := PanelContainer.new()
	gate.name = "GatePanel"
	gate.anchor_left = 0.5
	gate.anchor_right = 0.5
	gate.offset_left = -GATE_PANEL_WIDTH * 0.5
	gate.offset_right = GATE_PANEL_WIDTH * 0.5
	gate.offset_top = HUD_MARGIN
	gate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	gate.add_theme_stylebox_override("panel", background)
	gate.visible = false
	hud.add_child(gate)
	var gate_lines := VBoxContainer.new()
	gate_lines.name = "Lines"
	gate.add_child(gate_lines)
	for key in GATE_LINES:
		var settings := LabelSettings.new()
		settings.font_size = HUD_FONT_SIZE
		settings.font_color = HUD_TEXT_COLOR
		_add_hud_label(gate_lines, GATE_LINES[key], settings)
	# Bottom right.
	var navball: Control = NavballScript.new()
	navball.name = "Navball"
	navball.anchor_left = 1.0
	navball.anchor_right = 1.0
	navball.anchor_top = 1.0
	navball.anchor_bottom = 1.0
	navball.offset_left = -HUD_MARGIN - NavballScript.PANEL_SIZE.x
	navball.offset_right = -HUD_MARGIN
	navball.offset_top = -HUD_MARGIN - NavballScript.PANEL_SIZE.y
	navball.offset_bottom = -HUD_MARGIN
	hud.add_child(navball)
	# Boresight and motion marker over the whole view.
	var markers: Control = FlightMarkersScript.new()
	markers.name = "FlightMarkers"
	hud.add_child(markers)
	# Base Selene's marker, over the whole view too.
	var beacon: Control = BeaconMarkerScript.new()
	beacon.name = "BeaconMarker"
	hud.add_child(beacon)
	# The flight computer's leg.
	var nav_marker: Control = BeaconMarkerScript.new()
	nav_marker.name = "NavMarker"
	nav_marker.color = NAV_MARKER_COLOR
	nav_marker.prefix = "NAV"
	nav_marker.label_offset = BeaconMarkerScript.LABEL_DOWN_RIGHT
	hud.add_child(nav_marker)
	# And the nearest portal's.
	var gate_marker: Control = BeaconMarkerScript.new()
	gate_marker.name = "GateMarker"
	gate_marker.color = GATE_MARKER_COLOR
	gate_marker.prefix = "GATE"
	gate_marker.label_offset = BeaconMarkerScript.LABEL_UP_LEFT
	hud.add_child(gate_marker)

	update_hud(0.0, {})

func _add_hud_label(parent: Node, label_name: String, label_settings: LabelSettings) -> void:
	var label := Label.new()
	label.name = label_name
	label.label_settings = label_settings
	parent.add_child(label)
