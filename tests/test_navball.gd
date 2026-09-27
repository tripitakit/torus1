extends SceneTree

const Navball = preload("res://scripts/navball.gd")

func _init():
	var failures := 0
	failures += _test_a_ball_in_its_own_little_world()
	failures += _test_wings_drawn_over_the_ball()
	failures += _test_attitude_reaches_the_shader()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_a_ball_in_its_own_little_world() -> int:
	var navball: Control = Navball.new()
	var result := 0
	var viewport := navball.get_node_or_null("Viewport") as SubViewport
	var ball := navball.get_node_or_null("Viewport/Ball") as MeshInstance3D
	var camera := navball.get_node_or_null("Viewport/Camera") as Camera3D
	if viewport == null or ball == null or camera == null:
		print("FAIL _test_a_ball_in_its_own_little_world: missing Viewport, Ball or Camera")
		navball.free()
		return 1
	if not viewport.own_world_3d or not viewport.transparent_bg or viewport.size != Vector2i(Navball.BALL_PIXELS, Navball.BALL_PIXELS):
		print("FAIL _test_a_ball_in_its_own_little_world: viewport own world %s, transparent %s, size %s" % [viewport.own_world_3d, viewport.transparent_bg, viewport.size])
		result = 1
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not (ball.mesh is SphereMesh) or not (ball.material_override is ShaderMaterial):
		print("FAIL _test_a_ball_in_its_own_little_world: camera not orthogonal, or ball not a shaded sphere")
		result = 1
	var code: String = (ball.material_override as ShaderMaterial).shader.code
	for needle in ["uniform mat3 attitude", "asin", "atan(d.x, -d.z)", "render_mode unshaded"]:
		if not code.contains(needle):
			print("FAIL _test_a_ball_in_its_own_little_world: shader lacks '%s'" % needle)
			result = 1
	if navball.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		print("FAIL _test_a_ball_in_its_own_little_world: the navball catches the mouse")
		result = 1
	navball.free()
	return result

func _test_wings_drawn_over_the_ball() -> int:
	var navball: Control = Navball.new()
	var result := 0
	var picture := navball.get_node_or_null("Picture") as TextureRect
	var wings := navball.get_node_or_null("Wings") as Line2D
	if picture == null or wings == null or wings.get_index() < picture.get_index() or wings.get_point_count() < 3:
		print("FAIL _test_wings_drawn_over_the_ball: Picture and Wings missing, or Wings drawn under the ball")
		result = 1
	navball.free()
	return result

func _test_attitude_reaches_the_shader() -> int:
	var navball: Control = Navball.new()
	var rolled := Basis(Vector3.BACK, PI)
	navball.set_attitude(rolled)
	var result := 0
	if not navball.attitude().is_equal_approx(rolled):
		print("FAIL _test_attitude_reaches_the_shader: attitude %s, expected %s" % [navball.attitude(), rolled])
		result = 1
	navball.free()
	return result
