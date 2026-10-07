extends SceneTree

# The windows of Selene's Main Mission, the UltraTelescope's control room and
# Area 2's monitor room show photographs of the real outside (baked by
# tools/bake_window_views.gd), projected by the direction one looks in.

const AlphaInterior = preload("res://scripts/alpha_interior.gd")
const SeleneInteriorScript = preload("res://scripts/selene_interior.gd")
const OutpostInteriorScript = preload("res://scripts/outpost_interior.gd")
const TelescopeLayout = preload("res://scripts/telescope_layout.gd")
const DepotLayout = preload("res://scripts/depot_layout.gd")

func _init():
	var failures := 0
	failures += _test_photographs()
	failures += _test_projection()
	failures += _test_windows_show_them()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_photographs() -> int:
	for kind in ["moon", "dish", "field"]:
		var image := Image.load_from_file(ProjectSettings.globalize_path(AlphaInterior.WINDOW_VIEWS[kind]))
		if image == null or image.get_width() < 3840 or image.get_height() < 1920:
			print("FAIL _test_photographs: %s %s" % [kind, image.get_size() if image != null else "missing"])
			return 1
	return 0

# Looking straight out: the photograph's middle; along the edge of its field
# of view: its edge; behind the window: nothing.
func _test_projection() -> int:
	var half := deg_to_rad(AlphaInterior.WINDOW_VIEW_FOV * 0.5)
	var ahead: Vector2 = AlphaInterior.window_uv(Vector3(0.0, 0.0, -1.0), 0.0)
	var right: Vector2 = AlphaInterior.window_uv(Vector3(sin(half), 0.0, -cos(half)), 0.0)
	var up: Vector2 = AlphaInterior.window_uv(Vector3(0.0, 0.3, -1.0).normalized(), 0.0)
	var pitched: Vector2 = AlphaInterior.window_uv(Vector3(0.0, sin(0.2), -cos(0.2)), 0.2)
	var behind: Vector2 = AlphaInterior.window_uv(Vector3(0.0, 0.0, 1.0), 0.0)
	if not ahead.is_equal_approx(Vector2(0.5, 0.5)) or absf(right.x - 1.0) > 0.001 or absf(right.y - 0.5) > 0.001 or up.y >= 0.5 or not pitched.is_equal_approx(Vector2(0.5, 0.5)) or behind.x >= 0.0:
		print("FAIL _test_projection: ahead %s, right %s, up %s, pitched %s, behind %s" % [ahead, right, up, pitched, behind])
		return 1
	return 0

func _view_material(interior: Node3D) -> ShaderMaterial:
	for node in interior.find_children("*", "MeshInstance3D", true, false):
		var m := (node as MeshInstance3D).material_override as ShaderMaterial
		if m != null and m.get_shader_parameter("view") != null:
			return m
	return null

func _test_windows_show_them() -> int:
	var selene: Node3D = SeleneInteriorScript.new()
	selene.crew_count = 0
	selene.build()
	var telescope: Node3D = OutpostInteriorScript.new()
	telescope.layout = TelescopeLayout
	telescope.build()
	var depot: Node3D = OutpostInteriorScript.new()
	depot.layout = DepotLayout
	depot.build()
	var result := 0
	for pair in [[selene, "moon"], [telescope, "dish"], [depot, "field"]]:
		var m := _view_material(pair[0])
		var view: Texture2D = m.get_shader_parameter("view") if m != null else null
		if view == null or view.get_width() < 3840:
			print("FAIL _test_windows_show_them: %s window %s" % [pair[1], view])
			result = 1
	selene.free()
	telescope.free()
	depot.free()
	return result
