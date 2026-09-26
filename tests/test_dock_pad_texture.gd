extends SceneTree

const DockPadTexture = preload("res://scripts/dock_pad_texture.gd")

func _init():
	var failures := 0
	failures += _test_images_are_square_and_the_same_size()
	failures += _test_border_is_black_and_yellow_hazard_stripes()
	failures += _test_landing_ring_and_corner_lamps_glow()
	failures += _test_plates_are_dark_metal_that_does_not_glow()
	failures += _test_pad_and_platform_materials_share_the_look()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

func _px(fraction: float) -> int:
	return int(DockPadTexture.SIZE * fraction)

func _test_images_are_square_and_the_same_size() -> int:
	var albedo: Image = DockPadTexture.albedo_texture().get_image()
	var emission: Image = DockPadTexture.emission_texture().get_image()
	var size := DockPadTexture.SIZE
	if albedo.get_size() != Vector2i(size, size) or emission.get_size() != Vector2i(size, size):
		print("FAIL _test_images_are_square_and_the_same_size: %s / %s, expected %d square" % [albedo.get_size(), emission.get_size(), size])
		return 1
	return 0

func _test_border_is_black_and_yellow_hazard_stripes() -> int:
	var albedo: Image = DockPadTexture.albedo_texture().get_image()
	var yellow := 0
	var black := 0
	for x in range(DockPadTexture.SIZE):
		var c := albedo.get_pixel(x, 3)
		if _near(c, DockPadTexture.HAZARD_YELLOW):
			yellow += 1
		elif _near(c, DockPadTexture.HAZARD_BLACK):
			black += 1
	if yellow < _px(0.25) or black < _px(0.25) or yellow + black != DockPadTexture.SIZE:
		print("FAIL _test_border_is_black_and_yellow_hazard_stripes: top edge has %d yellow, %d black of %d" % [yellow, black, DockPadTexture.SIZE])
		return 1
	return 0

func _test_landing_ring_and_corner_lamps_glow() -> int:
	var emission: Image = DockPadTexture.emission_texture().get_image()
	var result := 0
	var centre := _px(0.5)
	var ring := emission.get_pixel(centre + _px(DockPadTexture.RING_RADIUS), centre)
	if not _near(ring, DockPadTexture.MARK_COLOR):
		print("FAIL _test_landing_ring_and_corner_lamps_glow: ring glows %s, expected %s" % [ring, DockPadTexture.MARK_COLOR])
		result = 1
	var lamp := emission.get_pixel(_px(DockPadTexture.LAMP_INSET), _px(DockPadTexture.LAMP_INSET))
	if not _near(lamp, DockPadTexture.LAMP_COLOR):
		print("FAIL _test_landing_ring_and_corner_lamps_glow: corner lamp glows %s, expected %s" % [lamp, DockPadTexture.LAMP_COLOR])
		result = 1
	return result

func _test_plates_are_dark_metal_that_does_not_glow() -> int:
	# Between the ring and the border, off the cross-hair and the chevrons.
	var albedo: Image = DockPadTexture.albedo_texture().get_image()
	var emission: Image = DockPadTexture.emission_texture().get_image()
	var x := _px(0.22)
	var y := _px(0.66)
	var c := albedo.get_pixel(x, y)
	var glow := emission.get_pixel(x, y)
	if c.get_luminance() > 0.3 or glow.get_luminance() > 0.01:
		print("FAIL _test_plates_are_dark_metal_that_does_not_glow: plate %s glowing %s" % [c, glow])
		return 1
	return 0

func _test_pad_and_platform_materials_share_the_look() -> int:
	var pad: StandardMaterial3D = DockPadTexture.pad_material()
	var platform: StandardMaterial3D = DockPadTexture.platform_material(60.0)
	var result := 0
	if pad != DockPadTexture.pad_material():
		print("FAIL _test_pad_and_platform_materials_share_the_look: pad material built twice")
		result = 1
	if pad.albedo_texture != platform.albedo_texture or pad.emission_texture != platform.emission_texture or pad.albedo_texture == null or not pad.emission_enabled:
		print("FAIL _test_pad_and_platform_materials_share_the_look: textures not shared or no glow")
		result = 1
	# The platform is a box: the pad image is projected on it from above,
	# once across its 60 m top.
	if pad.uv1_triplanar or not platform.uv1_triplanar or platform.uv1_world_triplanar or not platform.uv1_scale.is_equal_approx(Vector3.ONE / 60.0):
		print("FAIL _test_pad_and_platform_materials_share_the_look: projection wrong (pad triplanar %s, platform triplanar %s world %s scale %s)" % [pad.uv1_triplanar, platform.uv1_triplanar, platform.uv1_world_triplanar, platform.uv1_scale])
		result = 1
	return result
