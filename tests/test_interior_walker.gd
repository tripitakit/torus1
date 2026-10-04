extends SceneTree

# The pilot on foot inside a section: gravity toward the cylinder's wall,
# real collisions with the ground, the buildings and the landing pads; the
# interior streams and rebases round the walker, the parked cruiser along.

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const InteriorWalkerScript = preload("res://scripts/interior_walker.gd")
const LandingPads = preload("res://scripts/landing_pads.gd")
const SpineTrain = preload("res://scripts/spine_train.gd")

var _world: Node3D
var _walker: CharacterBody3D

func _initialize():
	await process_frame
	_world = InteriorWorldScript.new()
	_world.build()
	root.add_child(_world)
	_walker = InteriorWalkerScript.new()
	_walker.name = "InteriorWalker"
	_world.add_child(_walker)
	await physics_frame
	await physics_frame
	var failures := 0
	failures += await _test_walker_stands_on_the_ground()
	failures += await _test_walks_on_the_ground()
	failures += await _test_walker_steps_onto_the_pad()
	failures += await _test_stops_at_a_building()
	failures += await _test_interior_follows_the_walker()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	_world.free()
	quit()

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame

func _still() -> Dictionary:
	return {"move": Vector2.ZERO, "jog": false, "jump": false}

func _pad() -> Transform3D:
	return _world.nearest_pad(Vector3.ZERO).transform

# Up from the pad's top (toward the axis), metres.
func _over(pad: Transform3D, point: Vector3) -> float:
	return (point - pad.origin).dot(pad.basis.y.normalized())

func _test_walker_stands_on_the_ground() -> int:
	var pad := _pad()
	_walker.controls = _still()
	_walker.place(pad.origin + pad.basis.y * 0.3, pad.basis.z)
	await _ticks(120)
	var over := _over(pad, _walker.position)
	if not _walker.is_on_floor() or absf(over) > 0.1:
		print("FAIL _test_walker_stands_on_the_ground: on the floor %s, %.3f m over the pad" % [_walker.is_on_floor(), over])
		return 1
	return 0

func _test_walks_on_the_ground() -> int:
	var pad := _pad()
	_walker.place(pad.origin + pad.basis.y * 0.3, pad.basis.z)
	await _ticks(30)
	var start: Vector3 = _walker.position
	_walker.controls = {"move": Vector2(0.0, 1.0), "jog": false, "jump": false}
	await _ticks(300)
	_walker.controls = _still()
	var walked := start.distance_to(_walker.position)
	if absf(walked - 7.5) > 0.6 or not _walker.is_on_floor():
		print("FAIL _test_walks_on_the_ground: %.2f m in 5 s, on the floor %s" % [walked, _walker.is_on_floor()])
		return 1
	return 0

func _test_walker_steps_onto_the_pad() -> int:
	var pad := _pad()
	var side: Vector3 = pad.basis.x.normalized()
	var beside: Vector3 = pad.origin + side * (LandingPads.SIZE * 0.5 + 3.0) + pad.basis.y * 0.3
	_walker.place(beside, -side)
	await _ticks(30)
	_walker.controls = {"move": Vector2(0.0, 1.0), "jog": false, "jump": false}
	await _ticks(300)
	_walker.controls = _still()
	await _ticks(10)
	var across: float = absf((_walker.position - pad.origin).dot(side))
	var over := _over(pad, _walker.position)
	if across > LandingPads.SIZE * 0.5 - 1.0 or absf(over) > 0.1:
		print("FAIL _test_walker_steps_onto_the_pad: %.2f m from the middle across, %.3f m over the top" % [across, over])
		return 1
	return 0

# The built building nearest the pad: walk at it from 6 m off.
func _test_stops_at_a_building() -> int:
	var pad := _pad()
	var nearest := {}
	for state in _world._sections.values():
		if state.node == null:
			continue
		var plan = state.plan
		var section: Transform3D = _world._chain.transform * state.node.transform
		# Only buildings actually built (the pads' lots are cleared).
		var built := []
		for key in state.groups:
			built.append_array(state.groups[key])
		for b: int in built:
			var ground: float = _world.section_radius - plan.height_at(plan.building_x[b], plan.building_z[b])
			var frame: Transform3D = section * SpineTrain.spine_frame(plan.building_x[b] / _world.section_radius, ground, plan.building_z[b] - _world.section_length * 0.5)
			var gap: float = frame.origin.distance_to(pad.origin)
			if (nearest.is_empty() or gap < nearest.gap) and plan.building_size[b].x > 8.0 and plan.building_size[b].z > 8.0:
				nearest = {"frame": frame, "size": plan.building_size[b], "gap": gap}
	if nearest.is_empty():
		print("FAIL _test_stops_at_a_building: no building found")
		return 1
	var frame: Transform3D = nearest.frame
	var along: Vector3 = frame.basis.z.normalized()
	var half: float = nearest.size.z * 0.5
	_walker.place(frame.origin - along * (half + 6.0) + frame.basis.y * 0.5, along)
	await _ticks(30)
	_walker.controls = {"move": Vector2(0.0, 1.0), "jog": true, "jump": false}
	await _ticks(240)
	_walker.controls = _still()
	var into: float = (_walker.position - frame.origin).dot(along)
	if into > -half + 0.1:
		print("FAIL _test_stops_at_a_building: %.2f m from the middle along, the wall at %.2f" % [into, -half])
		return 1
	return 0

func _test_interior_follows_the_walker() -> int:
	var cruiser := Node3D.new()
	cruiser.name = "InternalCruiser"
	_world.add_child(cruiser)
	var pad := _pad()
	_walker.place(pad.origin + pad.basis.y * 0.3, pad.basis.z)
	cruiser.position = _walker.position + Vector3(4.0, 0.0, 0.0)
	await _ticks(2)
	var focus: Node3D = _world.focus()
	var gap: Vector3 = cruiser.position - _walker.position
	_walker.position.z += _world.REBASE_DISTANCE + 50.0
	cruiser.position.z += _world.REBASE_DISTANCE + 50.0
	await _ticks(2)
	var result := 0
	if focus != _walker or absf(_walker.position.z) > _world.REBASE_DISTANCE or (cruiser.position - _walker.position).distance_to(gap) > 0.5:
		print("FAIL _test_interior_follows_the_walker: focus %s, walker z %.1f, cruiser off by %.2f" % [focus.name if focus else null, _walker.position.z, (cruiser.position - _walker.position).distance_to(gap)])
		result = 1
	cruiser.free()
	return result
