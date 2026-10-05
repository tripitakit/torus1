extends CanvasLayer

# The HUD on foot, in the ship's HUD style (cockpit.gd): top left ON FOOT
# and the speed, top centre "K BOARD" when a vehicle is near enough, a
# marker on each vehicle (beacon_marker.gd) with its distance.

const CockpitScript = preload("res://scripts/cockpit.gd")
const BeaconMarkerScript = preload("res://scripts/beacon_marker.gd")

const MARKER_COLOR := Color(0.4, 0.95, 1.0, 0.95)

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(CockpitScript.HUD_MARGIN, CockpitScript.HUD_MARGIN)
	panel.add_theme_stylebox_override("panel", _background())
	add_child(panel)
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	panel.add_child(lines)
	for line in [["TitleLabel", "ON FOOT"], ["SpeedLabel", ""]]:
		var label := Label.new()
		label.name = line[0]
		label.text = line[1]
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
	text.text = "K BOARD"
	text.label_settings = _settings()
	board.add_child(text)
	board.visible = false
	add_child(board)

func show_speed(speed: float) -> void:
	(get_node("Panel/Lines/SpeedLabel") as Label).text = "SPD  %.1f m/s" % speed

func set_board_prompt(shown: bool) -> void:
	(get_node("BoardLabel") as Control).visible = shown

# A marker on each of `targets` ([name, Node3D]), seen by `camera`; markers
# of vehicles no longer listed hide.
func update_markers(camera: Camera3D, targets: Array) -> void:
	var wanted := {}
	for target: Array in targets:
		var node := target[1] as Node3D
		if not is_instance_valid(node):
			continue
		var marker_name := "Marker" + String(target[0])
		wanted[marker_name] = true
		var marker := get_node_or_null(marker_name)
		if marker == null:
			marker = BeaconMarkerScript.new()
			marker.name = marker_name
			marker.prefix = target[0]
			marker.color = MARKER_COLOR
			marker.label_offset = BeaconMarkerScript.LABEL_UP_LEFT
			add_child(marker)
		marker.update_target(camera, node.global_position, camera.global_position.distance_to(node.global_position), true)
	for child in get_children():
		if String(child.name).begins_with("Marker") and not wanted.has(String(child.name)):
			child.visible = false

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
