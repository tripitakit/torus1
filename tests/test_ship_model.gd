extends SceneTree

# The void-cruiser's outside model (an Eagle): inside the collision box,
# feet on its bottom, nose -Z, on the exterior layer the pilot never sees,
# engines glowing with thrust.

const ShipModel = preload("res://scripts/ship_model.gd")
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")
const CockpitScript = preload("res://scripts/cockpit.gd")

func _initialize():
	var failures := 0
	failures += _test_inside_the_collision_box()
	failures += _test_feet_touch_the_bottom()
	failures += _test_nose_ahead()
	failures += _test_engines_on_with_thrust()
	failures += await _test_on_the_exterior_layer()
	failures += _test_no_thin_decals()
	failures += await _test_nav_lights_on_the_hull()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_inside_the_collision_box() -> int:
	var box: AABB = ShipModel.mesh().get_aabb()
	var half := VoidCruiserScript.HULL_SIZE * 0.5 + Vector3.ONE * 0.05
	if box.position.x < -half.x or box.position.y < -half.y or box.position.z < -half.z or box.end.x > half.x or box.end.y > half.y or box.end.z > half.z:
		print("FAIL _test_inside_the_collision_box: %s" % box)
		return 1
	return 0

func _test_feet_touch_the_bottom() -> int:
	var low: float = ShipModel.mesh().get_aabb().position.y
	if absf(low - ShipModel.FOOT_Y) > 0.05:
		print("FAIL _test_feet_touch_the_bottom: lowest point %.2f m" % low)
		return 1
	return 0

func _test_nose_ahead() -> int:
	var box: AABB = ShipModel.mesh().get_aabb()
	if box.position.z > -13.0:
		print("FAIL _test_nose_ahead: foremost point z %.2f" % box.position.z)
		return 1
	return 0

func _test_engines_on_with_thrust() -> int:
	var pushing: bool = ShipModel.engines_on(Vector3(0.0, 0.0, -5.0), false)
	var idle: bool = ShipModel.engines_on(Vector3.ZERO, false)
	var landed: bool = ShipModel.engines_on(Vector3(0.0, 0.0, -5.0), true)
	var holder := Node3D.new()
	var model: MeshInstance3D = ShipModel.build(holder)
	ShipModel.set_engines(model, true)
	var lit: float = (model.material_override as ShaderMaterial).get_shader_parameter("engines")
	holder.free()
	if not pushing or idle or landed or lit != 1.0:
		print("FAIL _test_engines_on_with_thrust: pushing %s, idle %s, landed %s, parameter %s" % [pushing, idle, landed, lit])
		return 1
	return 0

func _test_on_the_exterior_layer() -> int:
	var ship: Node3D = VoidCruiserScript.new()
	root.add_child(ship)
	await process_frame
	var model := ship.get_node_or_null("Model") as MeshInstance3D
	var pilot := ship.get_node("Cockpit/PilotCamera") as Camera3D
	var result := 0
	if model == null or model.layers != CockpitScript.SHIP_EXTERIOR_LAYER or (pilot.cull_mask & model.layers) != 0:
		print("FAIL _test_on_the_exterior_layer: model %s" % model)
		result = 1
	ship.free()
	return result

# Two parts' faces facing the same way less than DECAL_GAP apart, one over
# the other, flicker with the rover's 24-bit depth from ~150 m: colour the
# faces themselves instead.
const DECAL_GAP := 0.25

func _test_no_thin_decals() -> int:
	var arrays: Array = ShipModel.mesh().surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := []
	for t in range(0, indices.size(), 3):
		var a := points[indices[t]]
		var b := points[indices[t + 1]]
		var c := points[indices[t + 2]]
		var normal := (b - a).cross(c - a)
		if normal.length() < 1e-6:
			continue
		faces.append([a, b, c, normal.normalized(), uvs[indices[t]].x, (a + b + c) / 3.0])
	# Faces lying against an opposite face (boxes stacked in bands) are inside
	# the hull: never seen.
	var shown := []
	for g in faces:
		var hidden := false
		for h in faces:
			if (h[3] as Vector3).dot(g[3]) > -0.999:
				continue
			var touch = Geometry3D.ray_intersects_triangle((g[5] as Vector3) - (g[3] as Vector3) * 0.001, g[3], h[0], h[1], h[2])
			if touch != null and (touch as Vector3).distance_to(g[5]) < 0.002:
				hidden = true
				break
		if not hidden:
			shown.append(g)
	for f in shown:
		for g in shown:
			if f[4] == g[4] or (f[3] as Vector3).dot(g[3]) < 0.999:
				continue
			# g's middle, slid along f's normal: on f, a hair to DECAL_GAP away?
			for way: float in [1.0, -1.0]:
				var hit = Geometry3D.ray_intersects_triangle(g[5], (f[3] as Vector3) * way, f[0], f[1], f[2])
				if hit != null:
					var gap := (hit as Vector3).distance_to(g[5])
					if gap > 1e-3 and gap < DECAL_GAP:
						print("FAIL _test_no_thin_decals: parts %d over %d, %.2f m apart at %s" % [g[4], f[4], gap, g[5]])
						return 1
	return 0

# The red and green lights sit on the model's outermost frames, not in the
# air beside them.
func _test_nav_lights_on_the_hull() -> int:
	var ship: Node3D = VoidCruiserScript.new()
	root.add_child(ship)
	await process_frame
	var reach := ShipModel.mesh().get_aabb().end.x
	var result := 0
	for light_name in ["PortLight", "StarboardLight"]:
		var light := ship.get_node_or_null(light_name) as Node3D
		if light == null or absf(absf(light.position.x) - reach) > 0.3:
			print("FAIL _test_nav_lights_on_the_hull: %s at %s, hull reaches %.2f" % [light_name, light.position if light else null, reach])
			result = 1
		# Right on the hull they would paint it red and green: they light
		# everything but the ship itself.
		elif ((light as Light3D).light_cull_mask & CockpitScript.SHIP_EXTERIOR_LAYER) != 0:
			print("FAIL _test_nav_lights_on_the_hull: %s lights the ship's own hull" % light_name)
			result = 1
	ship.free()
	return result
