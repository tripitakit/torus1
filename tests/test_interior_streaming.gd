extends SceneTree

# The interior chain loading around the craft over real frames.

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")

const LENGTH := 20000.0
const BRIDGE_LENGTH := 1834.0
const PERIOD := LENGTH + BRIDGE_LENGTH

var _failures := 0

func _initialize():
	await process_frame
	_failures += _test_rebase_moves_chain_and_craft_together()
	_failures += _test_freeing_while_a_plan_is_generating_waits_for_it()
	_failures += await _test_a_step_dresses_at_most_16_chunks_nearest_first()
	_failures += await _test_hovering_at_the_load_edge_keeps_the_same_section()
	_failures += await _test_flying_along_the_chain_finds_each_section_ready()
	_failures += await _test_internal_cruiser_flies_through_a_bridge_into_the_next_section()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _make_world() -> Node3D:
	var world: Node3D = InteriorWorldScript.new()
	world.build()
	return world

func _test_rebase_moves_chain_and_craft_together() -> int:
	var world := _make_world()
	var craft := Node3D.new()
	craft.name = "InternalCruiser"
	world.add_child(craft)
	var result := 0
	craft.position = Vector3(5.0, 7.0, -9000.0)
	world.rebase_around(craft)
	if not is_zero_approx(world.get_chain_offset()) or not is_equal_approx(craft.position.z, -9000.0):
		print("FAIL _test_rebase_moves_chain_and_craft_together: shifted at 9 km (offset %f)" % world.get_chain_offset())
		result = 1
	craft.position = Vector3(5.0, 7.0, -15000.0)
	var dock_from_craft: Vector3 = world.get_dock_position(0) - craft.position
	world.rebase_around(craft)
	if not craft.position.is_equal_approx(Vector3(5.0, 7.0, 0.0)) or not is_equal_approx(world.get_chain_offset(), 15000.0) or not is_equal_approx(world.chain_z(craft.position), -15000.0):
		print("FAIL _test_rebase_moves_chain_and_craft_together: craft %s offset %f" % [craft.position, world.get_chain_offset()])
		result = 1
	if not (world.get_dock_position(0) - craft.position).is_equal_approx(dock_from_craft):
		print("FAIL _test_rebase_moves_chain_and_craft_together: the dock moved relative to the craft")
		result = 1
	world.free()
	return result

func _test_freeing_while_a_plan_is_generating_waits_for_it() -> int:
	var world := _make_world()
	world.stream_step(-0.5 * PERIOD, 16, 32)  # starts section 1's plan on a worker
	var state = world._sections.get(1)
	if state == null or state.task_id < 0:
		print("FAIL _test_freeing_while_a_plan_is_generating_waits_for_it: no plan in progress for section 1")
		world.free()
		return 1
	world.free()
	if state.task_id != -1 or state.plan == null:
		print("FAIL _test_freeing_while_a_plan_is_generating_waits_for_it: the world was freed without waiting for its worker")
		return 1
	return 0

func _test_a_step_dresses_at_most_16_chunks_nearest_first() -> int:
	var world := _make_world()
	root.add_child(world)
	var focus := -0.5 * PERIOD
	var dressed := 0
	for i in range(3000):
		dressed = world.stream_step(focus, 16, 32)
		if dressed > 0:
			break
		await process_frame
	var result := 0
	var section := world.get_node_or_null("Chain/Section_1")
	var chunks: Array = [] if section == null else section.find_children("Chunk_*", "StaticBody3D", false, false)
	if dressed != 16 or chunks.size() != 16:
		print("FAIL _test_a_step_dresses_at_most_16_chunks_nearest_first: one step dressed %d, section 1 has %d chunks" % [dressed, chunks.size()])
		result = 1
	else:
		# Section 1's row 19 is its +Z end, the one facing the craft.
		for chunk in chunks:
			if not String(chunk.name).ends_with("_19"):
				print("FAIL _test_a_step_dresses_at_most_16_chunks_nearest_first: %s dressed before the nearest row" % chunk.name)
				result = 1
				break
	world.free()
	return result

func _test_hovering_at_the_load_edge_keeps_the_same_section() -> int:
	var world := _make_world()
	root.add_child(world)
	# Section 1's centre is 1.25 periods from here: it loads just inside,
	# and must not unload just outside.
	var edge := -0.25 * PERIOD
	var seen := {}
	for i in range(200):
		world.stream_step(edge + (300.0 if i % 2 == 0 else -300.0), 16, 32)
		var section := world.get_node_or_null("Chain/Section_1")
		if section != null:
			seen[section.get_instance_id()] = true
		await process_frame
	var result := 0
	if seen.size() != 1:
		print("FAIL _test_hovering_at_the_load_edge_keeps_the_same_section: section 1 was built %d times" % seen.size())
		result = 1
	world.free()
	return result

func _test_flying_along_the_chain_finds_each_section_ready() -> int:
	# 50 m per frame along -Z for two sections; the world streams in _process
	# and rebases in _physics_process around its "InternalCruiser" child.
	var world := _make_world()
	var craft := Node3D.new()
	craft.name = "InternalCruiser"
	world.add_child(craft)
	root.add_child(world)
	var along := 0.0
	var worst_usec := 0
	var not_ready := []
	var frames := 0
	var last := Time.get_ticks_usec()
	while along > -2.2 * PERIOD:
		along -= 50.0
		craft.position.z = along + world.get_chain_offset()
		await process_frame
		var now := Time.get_ticks_usec()
		if frames > 2:
			worst_usec = maxi(worst_usec, now - last)
		last = now
		frames += 1
		var slot: int = floori(-along / PERIOD)
		if not world.is_section_ready(slot) and not not_ready.has(slot):
			not_ready.append(slot)
	for i in range(40):
		await process_frame
	print("  worst frame while streaming: %.1f ms" % (worst_usec / 1000.0))
	var result := 0
	if not not_ready.is_empty():
		print("FAIL _test_flying_along_the_chain_finds_each_section_ready: reached sections %s before they were ready" % [not_ready])
		result = 1
	if worst_usec > 50000:
		print("FAIL _test_flying_along_the_chain_finds_each_section_ready: a frame took %.1f ms" % (worst_usec / 1000.0))
		result = 1
	if world.get_loaded_section_slots() != [1, 2] or world.get_node_or_null("Chain/Section_-1") != null or world.get_node_or_null("Chain/Section_0") != null:
		print("FAIL _test_flying_along_the_chain_finds_each_section_ready: loaded %s, expected [1, 2] with -1 and 0 freed" % [world.get_loaded_section_slots()])
		result = 1
	if is_zero_approx(world.get_chain_offset()) or absf(craft.position.z) > 10050.0:
		print("FAIL _test_flying_along_the_chain_finds_each_section_ready: no origin shift (offset %f, craft z %f)" % [world.get_chain_offset(), craft.position.z])
		result = 1
	world.free()
	return result

func _test_internal_cruiser_flies_through_a_bridge_into_the_next_section() -> int:
	# On the axis, 2 km before section 0's -Z cap, heading -Z at 1 km/s:
	# through the cap's hole, bridge 1 and into section 1, touching nothing.
	var world := _make_world()
	var cruiser: CharacterBody3D = InternalCruiserScript.new()
	cruiser.name = "InternalCruiser"
	cruiser.linear_damping = 0.0
	cruiser.position = Vector3(0.0, 0.0, -PERIOD + BRIDGE_LENGTH * 0.5 + 2000.0)
	world.add_child(cruiser)
	root.add_child(world)
	for i in range(3000):
		if world.is_section_ready(1):
			break
		await process_frame
	if not world.is_section_ready(1):
		print("FAIL _test_internal_cruiser_flies_through_a_bridge_into_the_next_section: section 1 never loaded")
		world.free()
		return 1
	cruiser.velocity = Vector3(0.0, 0.0, -1000.0)
	for tick in range(360):
		await physics_frame
	var result := 0
	var end_z: float = world.chain_z(cruiser.position)
	if not cruiser.velocity.is_equal_approx(Vector3(0.0, 0.0, -1000.0)) or end_z > -(PERIOD + BRIDGE_LENGTH * 0.5):
		print("FAIL _test_internal_cruiser_flies_through_a_bridge_into_the_next_section: at chain z %.1f with velocity %s (section 1 starts at %.1f)" % [end_z, cruiser.velocity, -(PERIOD + BRIDGE_LENGTH * 0.5)])
		result = 1
	world.free()
	return result
