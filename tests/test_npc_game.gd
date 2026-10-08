extends SceneTree

# The people one can talk to in the game: Ferrand and Okafor in Selene with
# their sheets, the rest of the crew with the generic one; the person right
# ahead of the pilot is the one spoken to; a listener stops and turns; the
# pilot stands still while talking.

const SeleneInteriorScript = preload("res://scripts/selene_interior.gd")
const InteriorWalkerScript = preload("res://scripts/interior_walker.gd")
const TownFolk = preload("res://scripts/town_folk.gd")
const NpcBrain = preload("res://scripts/npc_brain.gd")

func _initialize():
	var failures := 0
	failures += await _test_selene_people()
	failures += await _test_frozen_walker()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_selene_people() -> int:
	var base: Node3D = SeleneInteriorScript.new()
	base.build()
	root.add_child(base)
	await process_frame
	var by_npc := {}
	var people: Array = base.get_node("Crew").get_children()
	for member in people:
		var id: String = member.get_meta("npc", "")
		by_npc[id] = by_npc.get(id, []) + [member]
	if by_npc.get("ferrand", []).size() != 1 or by_npc.get("okafor", []).size() != 1 or by_npc.get("selene_crew", []).size() != people.size() - 2:
		print("FAIL _test_selene_people: %s" % [by_npc.keys()])
		return 1
	var ferrand: Node3D = by_npc.ferrand[0]
	var sheet := TownFolk.sheet_for(ferrand)
	var crew_sheet := TownFolk.sheet_for(by_npc.selene_crew[0])
	if sheet.name != "Tomas Ferrand" or crew_sheet.name.contains("{") or crew_sheet.name == "" or crew_sheet.label.contains("{"):
		print("FAIL _test_selene_people: sheets %s / %s" % [sheet.name, crew_sheet.label])
		return 1
	# 1.5 m in front of Ferrand, looking at him: him; 4 m away: nobody.
	var at := ferrand.global_position + (-ferrand.global_transform.basis.z) * 1.5
	var looking := Transform3D(Basis.looking_at(ferrand.global_position - at, Vector3.UP), at)
	var far := Transform3D(looking.basis, ferrand.global_position + (-ferrand.global_transform.basis.z) * 4.0)
	if TownFolk.person_ahead(people, looking) != ferrand or TownFolk.person_ahead(people, far) != null:
		print("FAIL _test_selene_people: person ahead")
		return 1
	# A walker on their round stops and turns to the pilot while listening.
	var walker: Node3D = by_npc.selene_crew[-1]
	for i in range(30):
		await physics_frame
	walker.listen_to(walker.global_position + Vector3(2.0, 0.0, 0.0))
	var still := walker.global_position
	for i in range(30):
		await physics_frame
	var facing: Vector3 = -walker.global_transform.basis.z
	if walker.global_position.distance_to(still) > 0.01 or facing.dot(Vector3(1.0, 0.0, 0.0)) < 0.99:
		print("FAIL _test_selene_people: listener moved %.2f, facing %s" % [walker.global_position.distance_to(still), facing])
		return 1
	walker.stop_listening()
	for i in range(60):
		await physics_frame
	base.free()
	return 0

func _test_frozen_walker() -> int:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	root.add_child(floor_body)
	var walker: CharacterBody3D = InteriorWalkerScript.new()
	walker.flat = true
	root.add_child(walker)
	walker.place(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0))
	walker.controls = {"move": Vector2(0.0, 1.0), "jog": false, "jump": false}
	walker.frozen = true
	for i in range(60):
		await physics_frame
	var moved := Vector2(walker.position.x, walker.position.z).length()
	walker.frozen = false
	for i in range(30):
		await physics_frame
	var after := Vector2(walker.position.x, walker.position.z).length()
	walker.free()
	floor_body.free()
	if moved > 0.01 or after < 0.3:
		print("FAIL _test_frozen_walker: frozen moved %.2f, free %.2f" % [moved, after])
		return 1
	return 0
