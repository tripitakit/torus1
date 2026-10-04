extends CanvasLayer

# The rover's HUD, in the ship's HUD style (cockpit.gd): top left the ROVER
# panel (speed, heading, slope, altitude, lights), top centre "V BOARD"
# when the pilot can board, and markers on the parked ship and on Base
# Selene's beacon (beacon_marker.gd).

const CockpitScript = preload("res://scripts/cockpit.gd")
const BeaconMarkerScript = preload("res://scripts/beacon_marker.gd")

const LINES := {
	"spd": "SpdLabel",
	"hdg": "HdgLabel",
	"slope": "SlopeLabel",
	"alt": "AltLabel",
	"lights": "LightsLabel",
}
const SHIP_MARKER_COLOR := Color(0.4, 0.95, 1.0, 0.95)

static func readout(speed: float, heading_deg: float, slope_deg: float, altitude: float, lights: bool) -> Dictionary:
	return {
		"spd": "SPD  %d km/h  %.1f m/s" % [roundi(absf(speed) * 3.6), absf(speed)],
		"hdg": "HDG  %03d°" % posmod(roundi(heading_deg), 360),
		"slope": "SLOPE  %d°" % roundi(slope_deg),
		"alt": "ALT  %d m" % roundi(altitude),
		"lights": "LIGHTS ON" if lights else "LIGHTS OFF",
	}

# The heading of `nose` (degrees, 0 north, 90 east) where the local up is
# `up`, north toward `pole`.
static func heading(nose: Vector3, up: Vector3, pole: Vector3) -> float:
	var north := (pole - up * pole.dot(up)).normalized()
	var east := north.cross(up)
	return fposmod(rad_to_deg(atan2(nose.dot(east), nose.dot(north))), 360.0)

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(CockpitScript.HUD_MARGIN, CockpitScript.HUD_MARGIN)
	panel.add_theme_stylebox_override("panel", _background())
	add_child(panel)
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	panel.add_child(lines)
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "ROVER"
	title.label_settings = _settings()
	lines.add_child(title)
	for key in LINES:
		var label := Label.new()
		label.name = LINES[key]
		label.label_settings = _settings()
		lines.add_child(label)
	var board := PanelContainer.new()
	board.name = "BoardLabel"
	board.anchor_left = 0.5
	board.anchor_right = 0.5
	board.offset_top = CockpitScript.HUD_MARGIN
	board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	board.add_theme_stylebox_override("panel", _background())
	var text := Label.new()
	text.text = "V BOARD"
	text.label_settings = _settings()
	board.add_child(text)
	board.visible = false
	add_child(board)
	var ship_marker: Control = BeaconMarkerScript.new()
	ship_marker.name = "ShipMarker"
	ship_marker.prefix = "SHIP"
	ship_marker.color = SHIP_MARKER_COLOR
	ship_marker.label_offset = BeaconMarkerScript.LABEL_UP_LEFT
	add_child(ship_marker)
	var selene: Control = BeaconMarkerScript.new()
	selene.name = "SeleneMarker"
	add_child(selene)

func show_readout(lines: Dictionary) -> void:
	for key in LINES:
		(get_node("Panel/Lines/" + LINES[key]) as Label).text = lines[key]

func set_board_prompt(shown: bool) -> void:
	(get_node("BoardLabel") as Control).visible = shown

# The ship's marker at `ship_at` (a Vector3, or null without a ship) and
# Selene's at `beacon_at`, seen by `camera`.
func update_markers(camera: Camera3D, ship_at: Variant, beacon_at: Vector3) -> void:
	var ship_marker := get_node("ShipMarker")
	if ship_at == null:
		ship_marker.update_target(camera, Vector3.ZERO, 0.0, false)
	else:
		ship_marker.update_target(camera, ship_at, camera.global_position.distance_to(ship_at), true)
	get_node("SeleneMarker").update_target(camera, beacon_at, camera.global_position.distance_to(beacon_at), true)

func _settings() -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = CockpitScript.HUD_FONT_SIZE
	settings.font_color = CockpitScript.HUD_TEXT_COLOR
	return settings

func _background() -> StyleBoxFlat:
	var background := StyleBoxFlat.new()
	background.bg_color = CockpitScript.HUD_BACKGROUND_COLOR
	background.set_corner_radius_all(6)
	background.set_content_margin_all(CockpitScript.HUD_PADDING)
	return background
