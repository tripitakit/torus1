extends SceneTree

# Photographs the real outside for the windows (run once, with a GPU):
#   ~/Godot_v4.6.1-stable-double_linux.x86_64 --path . -s tools/bake_window_views.gd
# From where each window would look out on the moon: Selene's Main Mission
# (from the base toward the planet's side), the UltraTelescope's control
# room (from its building toward the dish), Area 2's monitor room (from the
# depot toward the silo field). AlphaInterior.WINDOW_VIEW_* sets the camera.

const AlphaInterior = preload("res://scripts/alpha_interior.gd")
const MoonSites = preload("res://scripts/moon_sites.gd")

var _view: SubViewport
var _camera: Camera3D

func _initialize():
	var scene: Node3D = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(scene)
	for i in range(30):
		await process_frame
	var ship: Node3D = scene.get_node("VoidCruiser")
	var moon: Node3D = scene.get_node("PlanetSystem/Moon")
	_view = SubViewport.new()
	_view.size = AlphaInterior.WINDOW_VIEW_SIZE
	_view.world_3d = root.find_world_3d()
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = AlphaInterior.WINDOW_VIEW_FOV
	_camera.near = 0.3
	_camera.far = 2.0e6
	_view.add_child(_camera)
	_camera.current = true
	var shots := [
		["field", 8, func() -> Transform3D: return moon.site_transform("area2") * MoonSites.building_transform("area2") * Transform3D(Basis(Vector3.RIGHT, AlphaInterior.WINDOW_PITCH.field), Vector3(0.0, 3.2, -11.6))],
		["dish", 7, func() -> Transform3D: return moon.site_transform("telescope") * MoonSites.building_transform("telescope") * Transform3D(Basis(Vector3.RIGHT, AlphaInterior.WINDOW_PITCH.dish), Vector3(0.0, 3.2, -6.4))],
		["moon", 1, func() -> Transform3D: return _selene_spot(moon)],
	]
	for shot in shots:
		moon.set_physics_process(true)
		ship.set_physics_process(true)
		var pad: Transform3D = moon.pad_transform(shot[1])
		ship.land_at(Transform3D(pad.basis, pad.origin + pad.basis.y.normalized() * ship.HALF_HEIGHT))
		ship.visible = false
		# Until the fine ground round the site is built (a worker's job).
		var patch: Node3D = moon.get_node("Patch")
		for i in range(1800):
			_camera.global_transform = (shot[2] as Callable).call()
			await process_frame
			if i > 120 and patch.built and not patch.building:
				break
		# Everything still for the photograph (the moon turns tens of metres a
		# frame, and the origin shift with it).
		moon.set_physics_process(false)
		ship.set_physics_process(false)
		for i in range(60):
			_camera.global_transform = (shot[2] as Callable).call()
			await process_frame
		print("%s: patch built %s, camera %.1f m over the ground" % [shot[0], patch.built, moon.altitude(_camera.global_position)])
		await RenderingServer.frame_post_draw
		var path: String = AlphaInterior.WINDOW_VIEWS[shot[0]]
		_view.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(path), 0.9)
		print("saved " + path)
	quit()

# Out of the base toward the planet, 15 m up, 160 m from the tower.
func _selene_spot(moon: Node3D) -> Transform3D:
	var base: Transform3D = moon.base_transform()
	var toward: Vector3 = base.basis.inverse() * (moon.planet_centre() - base.origin)
	var level := Vector3(toward.x, 0.0, toward.z).normalized()
	var look := Basis.looking_at(level, Vector3.UP) * Basis(Vector3.RIGHT, AlphaInterior.WINDOW_PITCH.moon)
	return base * Transform3D(look, level * 160.0 + Vector3(0.0, 15.0, 0.0))
