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
