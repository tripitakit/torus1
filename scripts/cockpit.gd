extends Node3D

const CockpitLayout = preload("res://scripts/cockpit_layout.gd")
const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

# Visual layers (bit values). The pilot camera sees only the cockpit; the
# exterior cameras see the world but neither the cockpit nor the ship's own
# exterior markers.
const COCKPIT_LAYER := 2
const SHIP_EXTERIOR_LAYER := 4
const ALL_LAYERS := 0xFFFFF
const EXTERIOR_CAMERA_CULL_MASK := ALL_LAYERS & ~(COCKPIT_LAYER | SHIP_EXTERIOR_LAYER)

const SCREEN_DISTANCE := 1.6
const CENTER_SCREEN_SIZE := Vector2(1.6, 0.9)
const SIDE_SCREEN_SIZE := Vector2(0.9, 0.50625)
const SIDE_SCREEN_TILT := 30.0
const CENTER_VIEWPORT_SIZE := Vector2i(1280, 720)
const SIDE_VIEWPORT_SIZE := Vector2i(960, 540)
const BEZEL_MARGIN := 0.03
const BEZEL_DEPTH := 0.04

const HUD_SCREEN_SIZE := Vector2(0.8, 0.5)
const HUD_SCREEN_POSITION := Vector3(0.0, -0.72, -1.3)
const HUD_SCREEN_PITCH := -30.0
const HUD_VIEWPORT_SIZE := Vector2i(512, 320)
const HUD_FONT_SIZE := 28
const HUD_TEXT_COLOR := Color(0.4, 0.95, 1.0)
const HUD_BACKGROUND_COLOR := Color(0.02, 0.05, 0.08)

const DASHBOARD_SIZE := Vector3(2.4, 0.06, 0.8)
const DASHBOARD_POSITION := Vector3(0.0, -1.02, -1.3)
const FRAME_COLOR := Color(0.08, 0.09, 0.1)

const PILOT_FOV := 80.0
const PILOT_NEAR := 0.05
const PILOT_FAR := 10.0
# Horizontal FOV (keep_aspect = KEEP_WIDTH): the side cameras turn by exactly
# this much, so the three images join into one panorama.
const EXTERIOR_CAMERA_HFOV := 60.0
# The eye sits 7 m behind the bow face: a larger near plane would clip a
# surface touching the bow.
const EXTERIOR_CAMERA_NEAR := 2.0
const EXTERIOR_CAMERA_FAR := 69496000.0

# distance key -> [label node name, HUD prefix], in display order.
const DISTANCE_LABELS := {
	"bow": ["BowLabel", "PRUA"],
	"stern": ["SternLabel", "POPPA"],
	"port": ["PortLabel", "SX"],
	"starboard": ["StarboardLabel", "DX"],
	"dorsal": ["DorsalLabel", "DORSO"],
	"ventral": ["VentralLabel", "VENTRE"],
}

var _frame_material: StandardMaterial3D

func build() -> void:
	_frame_material = StandardMaterial3D.new()
	_frame_material.albedo_color = FRAME_COLOR
	_frame_material.roughness = 0.6
	_frame_material.metallic = 0.3

	_build_pilot_camera()
	_build_cockpit_light()
	_build_exterior_screen("Front", CENTER_SCREEN_SIZE, CENTER_VIEWPORT_SIZE,
		Transform3D(Basis(), Vector3(0.0, 0.0, -SCREEN_DISTANCE)), 0.0)
	for side in [-1.0, 1.0]:
		_build_exterior_screen("Left" if side < 0.0 else "Right", SIDE_SCREEN_SIZE, SIDE_VIEWPORT_SIZE,
			CockpitLayout.compute_side_screen_transform(CENTER_SCREEN_SIZE.x, SIDE_SCREEN_SIZE.x, SCREEN_DISTANCE, SIDE_SCREEN_TILT, side),
			CockpitLayout.compute_side_camera_yaw_degrees(EXTERIOR_CAMERA_HFOV, side))
	_build_dashboard()
	_build_hud()

func update_hud(speed: float, distances: Dictionary) -> void:
	var lines := get_node("HudViewport/Lines")
	(lines.get_node("SpeedLabel") as Label).text = "VEL  " + CockpitHudFormat.format_speed(speed)
	for key in DISTANCE_LABELS:
		var entry: Array = DISTANCE_LABELS[key]
		var distance: float = distances.get(key, -1.0)
		(lines.get_node(entry[0]) as Label).text = "%s  %s" % [entry[1], CockpitHudFormat.format_distance(distance)]

func _build_pilot_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "PilotCamera"
	camera.fov = PILOT_FOV
	camera.near = PILOT_NEAR
	camera.far = PILOT_FAR
	camera.cull_mask = COCKPIT_LAYER
	camera.current = true
	add_child(camera)

func _build_cockpit_light() -> void:
	var light := OmniLight3D.new()
	light.name = "CockpitLight"
	light.light_cull_mask = COCKPIT_LAYER
	light.light_color = Color(1.0, 0.85, 0.7)
	light.light_energy = 0.6
	light.omni_range = 4.0
	light.position = Vector3(0.0, 0.6, -0.8)
	add_child(light)

func _build_exterior_screen(prefix: String, screen_size: Vector2, viewport_size: Vector2i, screen_transform: Transform3D, camera_yaw_degrees: float) -> void:
	var viewport := SubViewport.new()
	viewport.name = prefix + "Viewport"
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = EXTERIOR_CAMERA_HFOV
	camera.near = EXTERIOR_CAMERA_NEAR
	camera.far = EXTERIOR_CAMERA_FAR
	camera.cull_mask = EXTERIOR_CAMERA_CULL_MASK
	camera.current = true
	viewport.add_child(camera)

	# A camera under a SubViewport does not inherit the ship's transform;
	# the mount (a child of the cockpit, so of the ship) pushes it.
	var mount := RemoteTransform3D.new()
	mount.name = prefix + "CameraMount"
	mount.rotation_degrees = Vector3(0.0, camera_yaw_degrees, 0.0)
	add_child(mount)
	mount.remote_path = mount.get_path_to(camera)

	var screen := _make_screen(prefix + "Screen", screen_size, viewport)
	screen.transform = screen_transform
	add_child(screen)

	var bezel := MeshInstance3D.new()
	bezel.name = "Bezel"
	var bezel_mesh := BoxMesh.new()
	bezel_mesh.size = Vector3(screen_size.x + BEZEL_MARGIN * 2.0, screen_size.y + BEZEL_MARGIN * 2.0, BEZEL_DEPTH)
	bezel.mesh = bezel_mesh
	bezel.material_override = _frame_material
	bezel.position = Vector3(0.0, 0.0, -BEZEL_DEPTH * 0.5 - 0.005)
	_put_on_cockpit_layer(bezel)
	screen.add_child(bezel)

func _build_dashboard() -> void:
	var dashboard := MeshInstance3D.new()
	dashboard.name = "Dashboard"
	var box := BoxMesh.new()
	box.size = DASHBOARD_SIZE
	dashboard.mesh = box
	dashboard.material_override = _frame_material
	dashboard.position = DASHBOARD_POSITION
	_put_on_cockpit_layer(dashboard)
	add_child(dashboard)

func _build_hud() -> void:
	var viewport := SubViewport.new()
	viewport.name = "HudViewport"
	viewport.size = HUD_VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = HUD_BACKGROUND_COLOR
	background.size = Vector2(HUD_VIEWPORT_SIZE)
	viewport.add_child(background)

	var lines := VBoxContainer.new()
	lines.name = "Lines"
	lines.position = Vector2(24.0, 12.0)
	viewport.add_child(lines)

	var label_settings := LabelSettings.new()
	label_settings.font_size = HUD_FONT_SIZE
	label_settings.font_color = HUD_TEXT_COLOR
	_add_hud_label(lines, "SpeedLabel", label_settings)
	for key in DISTANCE_LABELS:
		_add_hud_label(lines, DISTANCE_LABELS[key][0], label_settings)

	var screen := _make_screen("HudScreen", HUD_SCREEN_SIZE, viewport)
	screen.position = HUD_SCREEN_POSITION
	screen.rotation_degrees = Vector3(HUD_SCREEN_PITCH, 0.0, 0.0)
	add_child(screen)

	update_hud(0.0, {})

func _add_hud_label(parent: Node, label_name: String, label_settings: LabelSettings) -> void:
	var label := Label.new()
	label.name = label_name
	label.label_settings = label_settings
	parent.add_child(label)

func _make_screen(screen_name: String, screen_size: Vector2, viewport: SubViewport) -> MeshInstance3D:
	var screen := MeshInstance3D.new()
	screen.name = screen_name
	var quad := QuadMesh.new()
	quad.size = screen_size
	screen.mesh = quad
	# Unshaded: the screen shows the camera image as-is, unaffected by lights.
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	screen.material_override = material
	_put_on_cockpit_layer(screen)
	return screen

func _put_on_cockpit_layer(mesh: GeometryInstance3D) -> void:
	mesh.layers = COCKPIT_LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
