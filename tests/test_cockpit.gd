extends SceneTree

const CockpitScript = preload("res://scripts/cockpit.gd")

func _init():
	var failures := 0
	failures += _test_pilot_camera_sees_only_the_cockpit()
	failures += _test_exterior_cameras_form_a_continuous_panorama()
	failures += _test_camera_mounts_drive_their_cameras()
	failures += _test_screens_show_their_viewport_textures()
	failures += _test_cockpit_meshes_are_on_cockpit_layer_without_shadows()
	failures += _test_side_screens_touch_the_front_screen_edges()
	failures += _test_hud_screen_sits_below_and_faces_the_pilot()
	failures += _test_hud_lines_in_display_order()
	failures += _test_update_hud_writes_speed_and_distances()
	failures += _test_update_hud_missing_distances_show_no_reading()
	failures += _test_panorama_is_continuous_across_the_seams()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_cockpit() -> Node3D:
	var cockpit: Node3D = CockpitScript.new()
	cockpit.build()
	return cockpit

func _test_pilot_camera_sees_only_the_cockpit() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var camera := cockpit.get_node_or_null("PilotCamera")
	if camera == null or not (camera is Camera3D):
		print("FAIL _test_pilot_camera_sees_only_the_cockpit: no PilotCamera Camera3D")
		result = 1
	else:
		var pilot: Camera3D = camera
		if pilot.cull_mask != 2:
			print("FAIL _test_pilot_camera_sees_only_the_cockpit: cull_mask=%d expected 2 (COCKPIT_LAYER only)" % pilot.cull_mask)
			result = 1
		if not pilot.current:
			print("FAIL _test_pilot_camera_sees_only_the_cockpit: PilotCamera is not current")
			result = 1
	cockpit.free()
	return result

func _test_exterior_cameras_form_a_continuous_panorama() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	# Side cameras: hfov = 2*asin(sin 30° * 0.9 / 1.6) ≈ 32.67°, turned by
	# 30° + 16.33° so their image starts where the front one ends.
	var expected_yaw := {"Front": 0.0, "Left": 46.3348, "Right": -46.3348}
	var expected_fov := {"Front": 60.0, "Left": 32.6696, "Right": 32.6696}
	for prefix in expected_yaw:
		var camera := cockpit.get_node_or_null("%sViewport/Camera" % prefix)
		if camera == null or not (camera is Camera3D):
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: no %sViewport/Camera" % prefix)
			result = 1
			continue
		var cam: Camera3D = camera
		if cam.keep_aspect != Camera3D.KEEP_WIDTH or absf(cam.fov - expected_fov[prefix]) > 0.001:
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: %s keep_aspect=%d fov=%f expected KEEP_WIDTH and %f (horizontal FOV)" % [prefix, cam.keep_aspect, cam.fov, expected_fov[prefix]])
			result = 1
		if (cam.cull_mask & 1) == 0 or (cam.cull_mask & 2) != 0 or (cam.cull_mask & 4) != 0:
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: %s cull_mask=%d must include world (1) and exclude cockpit (2) and ship exterior (4)" % [prefix, cam.cull_mask])
			result = 1
		var mount := cockpit.get_node_or_null("%sCameraMount" % prefix)
		if mount == null or not (mount is RemoteTransform3D):
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: no %sCameraMount RemoteTransform3D" % prefix)
			result = 1
		elif absf((mount as Node3D).rotation_degrees.y - expected_yaw[prefix]) > 0.001:
			print("FAIL _test_exterior_cameras_form_a_continuous_panorama: %sCameraMount yaw=%f expected=%f" % [prefix, (mount as Node3D).rotation_degrees.y, expected_yaw[prefix]])
			result = 1
	cockpit.free()
	return result

func _test_camera_mounts_drive_their_cameras() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	for prefix in ["Front", "Left", "Right"]:
		var mount: RemoteTransform3D = cockpit.get_node("%sCameraMount" % prefix)
		var camera: Node = cockpit.get_node("%sViewport/Camera" % prefix)
		if mount.get_node_or_null(mount.remote_path) != camera:
			print("FAIL _test_camera_mounts_drive_their_cameras: %sCameraMount.remote_path=%s does not resolve to %sViewport/Camera" % [prefix, mount.remote_path, prefix])
			result = 1
	cockpit.free()
	return result

func _test_screens_show_their_viewport_textures() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var pairs := {"FrontScreen": "FrontViewport", "LeftScreen": "LeftViewport", "RightScreen": "RightViewport", "HudScreen": "HudViewport"}
	for screen_name in pairs:
		var screen := cockpit.get_node_or_null(screen_name)
		var viewport := cockpit.get_node_or_null(pairs[screen_name])
		if screen == null or viewport == null:
			print("FAIL _test_screens_show_their_viewport_textures: missing %s or %s" % [screen_name, pairs[screen_name]])
			result = 1
			continue
		var material := (screen as MeshInstance3D).material_override as StandardMaterial3D
		if material == null or material.albedo_texture != (viewport as SubViewport).get_texture():
			print("FAIL _test_screens_show_their_viewport_textures: %s does not show %s's texture" % [screen_name, pairs[screen_name]])
			result = 1
		elif material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			print("FAIL _test_screens_show_their_viewport_textures: %s material is not unshaded" % screen_name)
			result = 1
		if (viewport as SubViewport).render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			print("FAIL _test_screens_show_their_viewport_textures: %s does not update always" % pairs[screen_name])
			result = 1
	cockpit.free()
	return result

func _test_cockpit_meshes_are_on_cockpit_layer_without_shadows() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var meshes := cockpit.find_children("*", "MeshInstance3D", true, false)
	# 4 screens + 3 bezels + dashboard
	if meshes.size() < 8:
		print("FAIL _test_cockpit_meshes_are_on_cockpit_layer_without_shadows: only %d meshes, expected at least 8" % meshes.size())
		result = 1
	for mesh in meshes:
		var instance: MeshInstance3D = mesh
		if instance.layers != 2:
			print("FAIL _test_cockpit_meshes_are_on_cockpit_layer_without_shadows: %s layers=%d expected 2" % [instance.name, instance.layers])
			result = 1
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			print("FAIL _test_cockpit_meshes_are_on_cockpit_layer_without_shadows: %s casts shadows" % instance.name)
			result = 1
	cockpit.free()
	return result

func _test_side_screens_touch_the_front_screen_edges() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var front: MeshInstance3D = cockpit.get_node("FrontScreen")
	var front_half_width: float = (front.mesh as QuadMesh).size.x * 0.5
	for side in [-1.0, 1.0]:
		var screen: MeshInstance3D = cockpit.get_node("LeftScreen" if side < 0.0 else "RightScreen")
		var half_width: float = (screen.mesh as QuadMesh).size.x * 0.5
		var inner_edge: Vector3 = screen.transform * Vector3(-side * half_width, 0.0, 0.0)
		var front_edge: Vector3 = front.transform * Vector3(side * front_half_width, 0.0, 0.0)
		if not inner_edge.is_equal_approx(front_edge):
			print("FAIL _test_side_screens_touch_the_front_screen_edges: %s inner edge=%s front edge=%s" % [screen.name, inner_edge, front_edge])
			result = 1
	cockpit.free()
	return result

func _test_hud_screen_sits_below_and_faces_the_pilot() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var hud: MeshInstance3D = cockpit.get_node("HudScreen")
	var to_eye: Vector3 = Vector3.ZERO - hud.position
	if hud.position.y >= 0.0:
		print("FAIL _test_hud_screen_sits_below_and_faces_the_pilot: position=%s expected below eye level" % hud.position)
		result = 1
	if hud.transform.basis.z.dot(to_eye) <= 0.0 or hud.transform.basis.z.y <= 0.0:
		print("FAIL _test_hud_screen_sits_below_and_faces_the_pilot: normal=%s must face the eye and tilt up" % hud.transform.basis.z)
		result = 1
	cockpit.free()
	return result

func _test_hud_lines_in_display_order() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var lines := cockpit.get_node("HudViewport/Lines")
	var names: Array = []
	for child in lines.get_children():
		names.append(String(child.name))
	var expected := ["SpeedLabel", "BowLabel", "SternLabel", "PortLabel", "StarboardLabel", "DorsalLabel", "VentralLabel"]
	if names != expected:
		print("FAIL _test_hud_lines_in_display_order: %s expected %s" % [names, expected])
		result = 1
	cockpit.free()
	return result

func _test_update_hud_writes_speed_and_distances() -> int:
	var cockpit := _make_cockpit()
	cockpit.update_hud(1240.4, {"bow": 819.6, "stern": -1.0, "port": 3140.0, "starboard": -1.0, "dorsal": 410.0, "ventral": -1.0})
	var result := 0
	var expected := {
		"SpeedLabel": "VEL  1240 m/s",
		"BowLabel": "PRUA  820 m",
		"SternLabel": "POPPA  —",
		"PortLabel": "SX  3.1 km",
		"StarboardLabel": "DX  —",
		"DorsalLabel": "DORSO  410 m",
		"VentralLabel": "VENTRE  —",
	}
	for label_name in expected:
		var label: Label = cockpit.get_node("HudViewport/Lines/" + label_name)
		if label.text != expected[label_name]:
			print("FAIL _test_update_hud_writes_speed_and_distances: %s='%s' expected '%s'" % [label_name, label.text, expected[label_name]])
			result = 1
	cockpit.free()
	return result

func _test_update_hud_missing_distances_show_no_reading() -> int:
	var cockpit := _make_cockpit()
	cockpit.update_hud(0.0, {})
	var result := 0
	var label: Label = cockpit.get_node("HudViewport/Lines/BowLabel")
	if label.text != "PRUA  —":
		print("FAIL _test_update_hud_missing_distances_show_no_reading: BowLabel='%s' expected 'PRUA  —'" % label.text)
		result = 1
	cockpit.free()
	return result

# Height (metres, from the screen's centre line) at which a camera draws a
# direction on its physical screen. Exterior cameras use KEEP_WIDTH, so fov is
# horizontal and the image spans the screen width.
func _height_on_screen(direction: Vector3, camera_yaw_degrees: float, hfov_degrees: float, screen_width: float) -> float:
	var in_camera: Vector3 = Basis(Vector3.UP, deg_to_rad(camera_yaw_degrees)).inverse() * direction
	return screen_width * (in_camera.y / -in_camera.z) / (2.0 * tan(deg_to_rad(hfov_degrees) * 0.5))

func _test_panorama_is_continuous_across_the_seams() -> int:
	# A point on the seam line must be drawn at the same height on both
	# screens, at any elevation; otherwise the picture steps at the joint.
	var cockpit := _make_cockpit()
	var result := 0
	var front_camera: Camera3D = cockpit.get_node("FrontViewport/Camera")
	var front_width: float = (cockpit.get_node("FrontScreen").mesh as QuadMesh).size.x
	for side in [-1.0, 1.0]:
		var prefix := "Left" if side < 0.0 else "Right"
		var side_camera: Camera3D = cockpit.get_node("%sViewport/Camera" % prefix)
		var side_width: float = (cockpit.get_node("%sScreen" % prefix).mesh as QuadMesh).size.x
		var side_yaw: float = (cockpit.get_node("%sCameraMount" % prefix) as Node3D).rotation_degrees.y
		for elevation in [-12.0, 12.0, 25.0]:
			# The front image's outer edge, on this side, at this elevation.
			var seam_yaw: float = -side * front_camera.fov * 0.5
			var direction: Vector3 = Basis(Vector3.UP, deg_to_rad(seam_yaw)) * Vector3(0.0, sin(deg_to_rad(elevation)), -cos(deg_to_rad(elevation)))
			var front_height := _height_on_screen(direction, 0.0, front_camera.fov, front_width)
			var side_height := _height_on_screen(direction, side_yaw, side_camera.fov, side_width)
			if not is_equal_approx(front_height, side_height):
				print("FAIL _test_panorama_is_continuous_across_the_seams: %s seam at %s° elevation drawn at %f m on the front screen but %f m on the side screen" % [prefix, elevation, front_height, side_height])
				result = 1
			# The seam direction must also be exactly the side image's inner edge (no gap, no overlap).
			var in_side_camera: Vector3 = Basis(Vector3.UP, deg_to_rad(side_yaw)).inverse() * direction
			var edge_ratio: float = absf(in_side_camera.x / in_side_camera.z)
			if not is_equal_approx(edge_ratio, tan(deg_to_rad(side_camera.fov) * 0.5)):
				print("FAIL _test_panorama_is_continuous_across_the_seams: %s seam direction is not on the side image's edge (x/z=%f, edge=%f)" % [prefix, edge_ratio, tan(deg_to_rad(side_camera.fov) * 0.5)])
				result = 1
	cockpit.free()
	return result
