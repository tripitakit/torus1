extends "res://scripts/flying_craft.gd"

# The small craft flown inside the station: same controls as the
# void-cruiser, a shorter thrust ramp (it stops at 10x, about 1 km/s), no
# gravity, and a minimal HUD: the boresight and motion marker plus the
# current section's ID and time of day.

const FlightMarkersScript = preload("res://scripts/flight_markers.gd")
const SectionLabelScript = preload("res://scripts/section_label.gd")
const Clock = preload("res://scripts/interior_clock.gd")
const BeaconMarkerScript = preload("res://scripts/beacon_marker.gd")
const AirTraffic = preload("res://scripts/air_traffic.gd")
const CockpitScript = preload("res://scripts/cockpit.gd")
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
# Seen from outside it is one of the interior's sci-fi cruisers
# (AirTraffic.cruiser_mesh, ~9.6 m, +Z ahead) turned to -Z, scaled into the
# hull and lifted to its middle.
const MODEL_SCALE := 0.83
const MODEL_LIFT := -0.37
const MODEL_SHADER := """
shader_type spatial;
varying float part;
void vertex() {
	part = UV.x;
}
void fragment() {
	vec3 colour = vec3(0.9, 0.92, 0.95);
	vec3 glow = vec3(0.0);
	if (part > 0.5 && part < 1.5) {
		colour = vec3(0.06, 0.08, 0.1);
	} else if (part > 1.5 && part < 2.5) {
		colour = vec3(0.1);
		glow = vec3(0.3, 0.9, 1.0) * 2.0;
	} else if (part > 2.5 && part < 3.5) {
		colour = vec3(0.1);
		glow = vec3(1.0, 0.1, 0.05) * 2.0;
	} else if (part > 3.5) {
		colour = vec3(0.1);
		glow = vec3(0.1, 1.0, 0.3) * 2.0;
	}
	ALBEDO = colour;
	ROUGHNESS = 0.5;
	EMISSION = glow;
}
"""
# The assisted landing on a pad (GameMode) takes this long.
const LAND_TIME := 2.0

signal landed

# Parked on a pad while the pilot walks (GameMode): see park().
var parked := false
var _landing_from := Transform3D()
var _landing_to := Transform3D()
var _landing_t := -1.0

func _init() -> void:
	thrust_power = INTERNAL_THRUST

func _ready() -> void:
	build_collision_shape()
	build_camera()
	build_model()
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
	# The craft's own model is for the pilot on foot only.
	camera.cull_mask = CockpitScript.ALL_LAYERS & ~CockpitScript.SHIP_EXTERIOR_LAYER
	add_child(camera)

# The craft seen from outside, on the exterior layer.
func build_model() -> void:
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = AirTraffic.cruiser_mesh()
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = MODEL_SHADER
	model.material_override = material
	model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * MODEL_SCALE), Vector3(0.0, MODEL_LIFT, 0.0))
	model.layers = CockpitScript.SHIP_EXTERIOR_LAYER
	add_child(model)

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
	# Top centre, over a landing pad: "K LAND".
	var land := PanelContainer.new()
	land.name = "LandPanel"
	land.anchor_left = 0.5
	land.anchor_right = 0.5
	land.offset_top = HUD_MARGIN
	land.grow_horizontal = Control.GROW_DIRECTION_BOTH
	land.add_theme_stylebox_override("panel", background)
	var land_label := Label.new()
	land_label.text = "K LAND"
	land_label.label_settings = settings
	land.add_child(land_label)
	land.visible = false
	hud.add_child(land)
	# The nearest landing pad.
	var pad_marker: Control = BeaconMarkerScript.new()
	pad_marker.name = "PadMarker"
	pad_marker.prefix = "PAD"
	pad_marker.color = HUD_TEXT_COLOR
	hud.add_child(pad_marker)

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

func set_land_prompt(shown: bool) -> void:
	(get_node("Hud/LandPanel") as Control).visible = shown

func update_pad_marker(target: Vector3, distance: float, shown: bool) -> void:
	var camera := get_node_or_null("Camera") as Camera3D
	if camera != null and is_inside_tree():
		get_node("Hud/PadMarker").update_target(camera, target, distance, shown)

func is_landing() -> bool:
	return _landing_t >= 0.0

# Down onto `pad` (its top's centre, y up) by itself in LAND_TIME: square to
# the pad, the bow where it pointed; `landed` when there.
func land_on(pad: Transform3D) -> void:
	var up := pad.basis.y.normalized()
	var nose := -transform.basis.z
	var flat := nose - up * nose.dot(up)
	if flat.length() < 0.01:
		flat = -pad.basis.z
	var rest := Transform3D(Basis.looking_at(flat.normalized(), up), pad.origin + up * HULL_SIZE.y * 0.5)
	_landing_from = transform
	_landing_to = rest
	_landing_t = 0.0
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	set_process_unhandled_input(false)

# The interior world moved everything `dz` along Z (rebase) mid-landing.
func shift_landing(dz: float) -> void:
	_landing_from.origin.z += dz
	_landing_to.origin.z += dz

# Parked while the pilot walks: no keys, no HUD; off again when boarding.
func park(on: bool) -> void:
	parked = on
	set_process_unhandled_input(not on)
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_mouse_delta = Vector2.ZERO
	var hud := get_node_or_null("Hud") as CanvasLayer
	if hud != null:
		hud.visible = not on

func _physics_process(delta: float) -> void:
	if is_landing():
		_landing_t = minf(_landing_t + delta / LAND_TIME, 1.0)
		var share := smoothstep(0.0, 1.0, _landing_t)
		transform = _landing_from.interpolate_with(_landing_to, share)
		if _landing_t >= 1.0:
			_landing_t = -1.0
			transform = _landing_to
			# Down: no keys any more (the pilot gets out behind the fade).
			park(true)
			landed.emit()
		return
	if parked:
		return
	_fly(delta)
