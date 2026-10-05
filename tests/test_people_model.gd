extends SceneTree

const PeopleModel = preload("res://scripts/people_model.gd")

func _init():
	var failures := 0
	failures += _test_loads()
	failures += _test_height()
	failures += _test_faces_plus_z()
	failures += _test_feet_swap_at_half_cycle()
	failures += _test_hips_stay_in_place()
	failures += _test_parts()
	failures += _test_texture_frame_zero_matches()
	failures += _test_idle_mesh()
	failures += _test_stride_matches_speed()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# Mean of the frame's points whose heaviest bone is `bone`.
func _mean(points: PackedVector3Array, bone: String) -> Vector3:
	var bones: PackedStringArray = PeopleModel.bake().bones
	var sum := Vector3.ZERO
	var n := 0
	for i in range(points.size()):
		if bones[i] == bone:
			sum += points[i]
			n += 1
	return sum / maxf(n, 1)

func _test_loads() -> int:
	var baked: Dictionary = PeopleModel.bake()
	if baked.is_empty() or baked.vertices != 4733 or baked.frames != PeopleModel.FRAMES or not (baked.mesh is ArrayMesh) or not (baked.positions is ImageTexture) or not (baked.normals is ImageTexture):
		print("FAIL _test_loads: %s" % [baked.keys()])
		return 1
	return 0

func _test_height() -> int:
	var result := 0
	for frame in [0, PeopleModel.FRAMES / 2]:
		var low := INF
		var high := -INF
		for p in PeopleModel.frame_points(frame):
			low = minf(low, p.y)
			high = maxf(high, p.y)
		# Walking, the feet lift a little and the head bobs.
		if absf(low) > 0.06 or absf(high - PeopleModel.HEIGHT) > 0.08:
			print("FAIL _test_height: frame %d from %.3f to %.3f" % [frame, low, high])
			result = 1
	return result

# Toes ahead of the ankles, the face ahead of the back of the head.
func _test_faces_plus_z() -> int:
	var points := PeopleModel.frame_points(0)
	var toes := _mean(points, "LeftToeBase") + _mean(points, "RightToeBase")
	var ankles := _mean(points, "LeftFoot") + _mean(points, "RightFoot")
	if toes.z - ankles.z < 0.1:
		print("FAIL _test_faces_plus_z: toes %s ankles %s" % [toes * 0.5, ankles * 0.5])
		return 1
	# Walking: the foot on the ground slides straight back, toward -Z.
	var back := Vector3.ZERO
	for bone in ["LeftFoot", "RightFoot"]:
		for frame in range(PeopleModel.FRAMES):
			var here := _mean(PeopleModel.frame_points(frame), bone)
			var next := _mean(PeopleModel.frame_points((frame + 1) % PeopleModel.FRAMES), bone)
			if here.y < 0.07 and next.y < 0.07:
				back += next - here
	if back.z > -0.3 or absf(back.x) > 0.2 * absf(back.z):
		print("FAIL _test_faces_plus_z: the planted feet slide by %s" % back)
		return 1
	return 0

func _test_feet_swap_at_half_cycle() -> int:
	# From the widest stride, half a cycle on: the other foot ahead.
	var widest := 0
	var gaps := []
	for frame in range(PeopleModel.FRAMES):
		var points := PeopleModel.frame_points(frame)
		gaps.append(_mean(points, "LeftFoot").z - _mean(points, "RightFoot").z)
		if absf(gaps[frame]) > absf(gaps[widest]):
			widest = frame
	var lead := [gaps[widest], gaps[(widest + PeopleModel.FRAMES / 2) % PeopleModel.FRAMES]]
	if absf(lead[0]) < 0.3 or absf(lead[1]) < 0.3 or signf(lead[0]) == signf(lead[1]):
		print("FAIL _test_feet_swap_at_half_cycle: left ahead by %.2f then %.2f m" % lead)
		return 1
	return 0

# The shader moves them along: the clip walks on the spot.
func _test_hips_stay_in_place() -> int:
	var start := _mean(PeopleModel.frame_points(0), "Hips")
	for frame in range(PeopleModel.FRAMES):
		var hips := _mean(PeopleModel.frame_points(frame), "Hips")
		if Vector2(hips.x - start.x, hips.z - start.z).length() > 0.1:
			print("FAIL _test_hips_stay_in_place: frame %d hips %s from %s" % [frame, hips, start])
			return 1
	return 0

# UV.x parts as LoopTraffic's shader reads them: legs dark (1), a glowing
# visor (2) on the face, the rest the suit (0).
func _test_parts() -> int:
	var baked: Dictionary = PeopleModel.bake()
	var arrays: Array = (baked.mesh as ArrayMesh).surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedStringArray = baked.bones
	var visor := 0
	var result := 0
	for i in range(uv.size()):
		var index := roundi(uv[i].y)
		var bone: String = bones[index]
		var part := roundi(uv[i].x)
		if bone in ["LeftLeg", "RightLeg", "LeftUpLeg", "RightUpLeg", "LeftFoot", "RightFoot"] and part != 1:
			result = 1
		if bone in ["Spine1", "Spine2", "LeftArm", "RightArm"] and part != 0:
			result = 1
		if part == 2:
			visor += 1
			if bone != "Head":
				result = 1
	if result != 0 or visor < 6:
		print("FAIL _test_parts: wrong part for a bone, or %d visor vertices" % visor)
		return 1
	return 0

# The mesh's UV.y is the vertex's texel; the texture's frame 0 row holds the
# skinned points of frame 0.
func _test_texture_frame_zero_matches() -> int:
	var baked: Dictionary = PeopleModel.bake()
	var image: Image = (baked.positions as ImageTexture).get_image()
	var points := PeopleModel.frame_points(0)
	var middle := PeopleModel.frame_points(PeopleModel.FRAMES / 2)
	for index in [0, 1000, 4732]:
		var at := Vector2i(index % PeopleModel.ROW, index / PeopleModel.ROW)
		var c := image.get_pixelv(at)
		var later: int = index + PeopleModel.FRAMES / 2 * baked.vertices
		var c2 := image.get_pixelv(Vector2i(later % PeopleModel.ROW, later / PeopleModel.ROW))
		if Vector3(c.r, c.g, c.b).distance_to(points[index]) > 0.001 or Vector3(c2.r, c2.g, c2.b).distance_to(middle[index]) > 0.001:
			print("FAIL _test_texture_frame_zero_matches: texel %d %s, point %s" % [index, c, points[index]])
			return 1
	if image.get_width() != PeopleModel.ROW or image.get_format() != Image.FORMAT_RGBAF:
		print("FAIL _test_texture_frame_zero_matches: image %d wide, format %d" % [image.get_width(), image.get_format()])
		return 1
	return 0

func _test_idle_mesh() -> int:
	var idle: ArrayMesh = PeopleModel.bake().idle
	var box := idle.get_aabb()
	if absf(box.position.y) > 0.03 or absf(box.end.y - PeopleModel.HEIGHT) > 0.03 or box.size.x > 1.0:
		print("FAIL _test_idle_mesh: %s" % box)
		return 1
	return 0

# One walk cycle every STRIDE metres, so the feet keep to the ground.
func _test_stride_matches_speed() -> int:
	var a := PeopleModel.cycle_phase(PeopleModel.STRIDE * 0.5)
	var b := PeopleModel.cycle_phase(PeopleModel.STRIDE * 3.25)
	if not is_equal_approx(PeopleModel.STRIDE, 1.4) or absf(a - 0.5) > 1e-6 or absf(b - 0.25) > 1e-6:
		print("FAIL _test_stride_matches_speed: %f %f" % [a, b])
		return 1
	return 0
