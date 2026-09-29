extends SceneTree

const TorusStationScript = preload("res://scripts/torus_station.gd")
const DockPadTexture = preload("res://scripts/dock_pad_texture.gd")
const SectionLabelScript = preload("res://scripts/section_label.gd")
const PlanetScript = preload("res://scripts/planet.gd")
const TorusGeometry = preload("res://scripts/torus_geometry.gd")

func _init():
	var failures := 0
	failures += _test_build_station_child_count()
	failures += _test_section_and_bridge_mesh_shape()
	failures += _test_rebuild_does_not_leak()
	failures += _test_build_station_preserves_unrelated_children()
	failures += _test_bridge_positions_are_distinct_and_close_the_ring()
	failures += _test_uses_planet_node_radius_when_set()
	failures += _test_sections_have_no_stripe_marker()
	failures += _test_rotate_sections_applies_correct_local_y_angle()
	failures += _test_rotate_sections_leaves_bridges_still()
	failures += _test_sections_and_bridges_share_one_hull_material()
	failures += _test_sections_share_one_mesh_resource()
	failures += _test_bridges_share_one_mesh_resource()
	failures += _test_section_panel_material_has_emission()
	failures += _test_sections_are_animatable_bodies()
	failures += _test_bridges_are_animatable_bodies()
	failures += _test_sections_have_matching_collision_shape()
	failures += _test_bridges_have_matching_collision_shape()
	failures += _test_section_collision_shapes_are_shared()
	failures += _test_bridge_collision_shapes_are_shared()
	failures += _test_no_docking_collars_left()
	failures += _test_each_bridge_has_a_dock_pad_flat_on_one_face()
	failures += _test_dock_pads_share_mesh_and_textured_material()
	failures += _test_port_sits_on_its_still_bridge()
	failures += _test_bridge_radius_and_length_helpers()
	failures += _test_every_pad_has_four_corner_lamps()
	failures += _test_lamp_shader_keeps_a_minimum_size_and_blinks()
	failures += _test_sections_use_the_bridge_panel_texture()
	failures += _test_every_section_has_its_id_stencilled_on_the_hull()
	failures += _test_section_labels_use_the_curved_glyph_mesh()
	failures += _test_label_shader_does_not_back_face_cull()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_station(num_sections: int) -> Node3D:
	var station: Node3D = TorusStationScript.new()
	station.planet_radius = 500.0
	station.orbit_altitude = 1500.0
	station.num_sections = num_sections
	station.section_radius = 30.0
	station.section_length = 80.0
	station.target_gravity_g = 1.0
	return station

func _test_build_station_child_count() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if station.get_child_count() != 8:
		print("FAIL _test_build_station_child_count: expected 8 children (4 sections, 4 bridges), got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_section_and_bridge_mesh_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var section_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var bridge_mesh: MeshInstance3D = station.get_node("Bridge0").get_node("Mesh")
	var failed := false
	if not (section_mesh.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Section0/Mesh.mesh is not CylinderMesh")
		failed = true
	else:
		var cyl: CylinderMesh = section_mesh.mesh
		if not is_equal_approx(cyl.top_radius, 30.0) or not is_equal_approx(cyl.height, 80.0):
			print("FAIL _test_section_and_bridge_mesh_shape: Section0/Mesh top_radius=%f height=%f" % [cyl.top_radius, cyl.height])
			failed = true
	if not (bridge_mesh.mesh is CylinderMesh):
		print("FAIL _test_section_and_bridge_mesh_shape: Bridge0/Mesh.mesh is not CylinderMesh")
		failed = true
	station.free()
	return 1 if failed else 0

func _test_rebuild_does_not_leak() -> int:
	var station := _make_station(4)
	station.build_station()
	station.build_station()
	var result := 0
	if station.get_child_count() != 8:
		print("FAIL _test_rebuild_does_not_leak: expected 8 children after rebuild, got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_build_station_preserves_unrelated_children() -> int:
	var station := _make_station(4)
	var marker := Node3D.new()
	marker.name = "Marker"
	station.add_child(marker)
	station.build_station()
	var result := 0
	if station.get_node_or_null("Marker") == null:
		print("FAIL _test_build_station_preserves_unrelated_children: Marker was removed by build_station()")
		result = 1
	if station.get_child_count() != 9:
		print("FAIL _test_build_station_preserves_unrelated_children: expected 9 children (8 generated + Marker), got %d" % station.get_child_count())
		result = 1
	station.free()
	return result

func _test_bridge_positions_are_distinct_and_close_the_ring() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var torus_radius := 500.0 + 1500.0
	var step := TAU / 4.0
	for i in range(4):
		var bridge: AnimatableBody3D = station.get_node("Bridge%d" % i)
		var expected_theta := i * step + step * 0.5
		var expected_pos := Vector3(cos(expected_theta), 0.0, sin(expected_theta)) * torus_radius
		if not bridge.transform.origin.is_equal_approx(expected_pos):
			print("FAIL _test_bridge_positions_are_distinct_and_close_the_ring: Bridge%d origin=%s expected=%s" % [i, bridge.transform.origin, expected_pos])
			result = 1
	station.free()
	return result

func _test_uses_planet_node_radius_when_set() -> int:
	var station := _make_station(4)
	station.planet_radius = 500.0
	var planet: MeshInstance3D = PlanetScript.new()
	planet.name = "Planet"
	planet.planet_radius = 900.0
	station.add_child(planet)
	station.planet_node = NodePath("Planet")
	station.build_station()
	var result := 0
	var section0: AnimatableBody3D = station.get_node("Section0")
	var expected_torus_radius := 900.0 + 1500.0
	if not is_equal_approx(section0.transform.origin.length(), expected_torus_radius):
		print("FAIL _test_uses_planet_node_radius_when_set: Section0 distance=%f expected=%f" % [section0.transform.origin.length(), expected_torus_radius])
		result = 1
	station.free()
	return result

func _test_sections_have_no_stripe_marker() -> int:
	# The orange rotation-marker stripe was removed at the user's request:
	# a section is only its hull mesh and collision shape.
	var station := _make_station(4)
	station.build_station()
	var section: AnimatableBody3D = station.get_node("Section0")
	var result := 0
	if section.get_node_or_null("Stripe") != null:
		print("FAIL _test_sections_have_no_stripe_marker: Section0 still has a Stripe child")
		result = 1
	var mesh_count := section.find_children("*", "MeshInstance3D", true, false).size()
	if mesh_count != 1:
		print("FAIL _test_sections_have_no_stripe_marker: Section0 has %d meshes, expected 1 (hull only)" % mesh_count)
		result = 1
	station.free()
	return result

func _test_rotate_sections_applies_correct_local_y_angle() -> int:
	var station := _make_station(4)
	station.build_station()
	var section: AnimatableBody3D = station.get_node("Section0")
	var original_basis: Basis = section.transform.basis
	var delta := 0.1
	station._rotate_sections(delta)
	var new_basis: Basis = section.transform.basis
	var delta_basis: Basis = original_basis.inverse() * new_basis
	var expected_omega: float = TorusGeometry.compute_section_angular_velocity(30.0, TorusGeometry.GRAVITY_1G)
	var expected_delta_basis := Basis(Vector3.UP, expected_omega * delta)
	var result := 0
	if not delta_basis.x.is_equal_approx(expected_delta_basis.x) \
			or not delta_basis.y.is_equal_approx(expected_delta_basis.y) \
			or not delta_basis.z.is_equal_approx(expected_delta_basis.z):
		print("FAIL _test_rotate_sections_applies_correct_local_y_angle: delta_basis=%s expected=%s" % [delta_basis, expected_delta_basis])
		result = 1
	station.free()
	return result

func _test_rotate_sections_leaves_bridges_still() -> int:
	# Sections spin for gravity; bridges, with their pads, stay put so the
	# ships outside have a still dock to fly to.
	var station := _make_station(4)
	station.build_station()
	var bridge: AnimatableBody3D = station.get_node("Bridge0")
	var section: Node3D = station.get_node("Section0")
	var bridge_basis: Basis = bridge.transform.basis
	var section_basis: Basis = section.transform.basis
	station._rotate_sections(0.1)
	var result := 0
	if not bridge.transform.basis.is_equal_approx(bridge_basis) or section.transform.basis.is_equal_approx(section_basis):
		print("FAIL _test_rotate_sections_leaves_bridges_still: bridge turned %s, section turned %s" % [not bridge.transform.basis.is_equal_approx(bridge_basis), not section.transform.basis.is_equal_approx(section_basis)])
		result = 1
	station.free()
	return result

func _test_sections_and_bridges_share_one_hull_material() -> int:
	# Every section references the SAME hull material, and every bridge the
	# SAME bridge material — not a fresh StandardMaterial3D per mesh: with
	# num_sections in the thousands, per-object materials would duplicate a
	# GPU resource needlessly. (Bridges have their own panels since the
	# rectangular texture.)
	var station := _make_station(4)
	station.build_station()
	var section0_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var section1_mesh: MeshInstance3D = station.get_node("Section1").get_node("Mesh")
	var bridge0_mesh: MeshInstance3D = station.get_node("Bridge0").get_node("Mesh")
	var bridge1_mesh: MeshInstance3D = station.get_node("Bridge1").get_node("Mesh")
	var result := 0
	if section0_mesh.material_override == null:
		print("FAIL _test_sections_and_bridges_share_one_hull_material: Section0/Mesh has no material_override")
		result = 1
	elif section0_mesh.material_override != section1_mesh.material_override:
		print("FAIL _test_sections_and_bridges_share_one_hull_material: Section0 and Section1 use different material resources")
		result = 1
	elif bridge0_mesh.material_override == null or bridge0_mesh.material_override != bridge1_mesh.material_override:
		print("FAIL _test_sections_and_bridges_share_one_hull_material: Bridge0 and Bridge1 use different material resources")
		result = 1
	station.free()
	return result

func _test_sections_share_one_mesh_resource() -> int:
	# With num_sections in the thousands, a fresh CylinderMesh per section
	# would duplicate identical geometry in GPU memory thousands of times.
	var station := _make_station(4)
	station.build_station()
	var section0_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var section1_mesh: MeshInstance3D = station.get_node("Section1").get_node("Mesh")
	var result := 0
	if section0_mesh.mesh == null or section0_mesh.mesh != section1_mesh.mesh:
		print("FAIL _test_sections_share_one_mesh_resource: Section0 and Section1 use different mesh resources")
		result = 1
	station.free()
	return result

func _test_bridges_share_one_mesh_resource() -> int:
	var station := _make_station(4)
	station.build_station()
	var bridge0_mesh: MeshInstance3D = station.get_node("Bridge0").get_node("Mesh")
	var bridge1_mesh: MeshInstance3D = station.get_node("Bridge1").get_node("Mesh")
	var result := 0
	if bridge0_mesh.mesh == null or bridge0_mesh.mesh != bridge1_mesh.mesh:
		print("FAIL _test_bridges_share_one_mesh_resource: Bridge meshes differ between instances")
		result = 1
	station.free()
	return result

func _test_section_panel_material_has_emission() -> int:
	# Sections use the same panel look as bridges (see
	# _test_sections_use_the_bridge_panel_texture): small lights painted into
	# the texture, additive over black so only those spots glow.
	var station := _make_station(4)
	station.build_station()
	var section_mesh: MeshInstance3D = station.get_node("Section0").get_node("Mesh")
	var mat: StandardMaterial3D = section_mesh.material_override
	var result := 0
	if not mat.emission_enabled or mat.emission_texture == null:
		print("FAIL _test_section_panel_material_has_emission: emission not enabled or no emission_texture")
		result = 1
	if not mat.emission.is_equal_approx(Color(0, 0, 0)):
		print("FAIL _test_section_panel_material_has_emission: base emission color=%s expected black" % mat.emission)
		result = 1
	station.free()
	return result

func _test_sections_are_animatable_bodies() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if not (station.get_node("Section0") is AnimatableBody3D):
		print("FAIL _test_sections_are_animatable_bodies: Section0 is not an AnimatableBody3D")
		result = 1
	station.free()
	return result

func _test_bridges_are_animatable_bodies() -> int:
	# Bridges now rotate every frame together with sections — same reasoning
	# as sections: Godot recommends against moving a StaticBody3D every
	# frame, and a body under continuous external transform control should
	# be an AnimatableBody3D instead.
	var station := _make_station(4)
	station.build_station()
	var result := 0
	if not (station.get_node("Bridge0") is AnimatableBody3D):
		print("FAIL _test_bridges_are_animatable_bodies: Bridge0 is not an AnimatableBody3D")
		result = 1
	station.free()
	return result

# The collision shape must be a convex prism whose corners are exactly the
# side-wall corners of the visible CylinderMesh (not a CylinderShape3D: see
# test_torus_station_physics.gd). Returns an error message, or "" if it matches.
func _prism_mismatch(body: Node, expected_radius: float) -> String:
	var collision := body.get_node_or_null("Collision")
	if collision == null or not (collision is CollisionShape3D) or not ((collision as CollisionShape3D).shape is ConvexPolygonShape3D):
		return "%s has no CollisionShape3D with a ConvexPolygonShape3D" % body.name
	var points: PackedVector3Array = ((collision as CollisionShape3D).shape as ConvexPolygonShape3D).points
	var mesh: CylinderMesh = (body.get_node("Mesh") as MeshInstance3D).mesh
	if not is_equal_approx(mesh.top_radius, expected_radius):
		return "%s mesh radius=%f expected %f" % [body.name, mesh.top_radius, expected_radius]
	if points.size() != mesh.radial_segments * 2:
		return "%s prism has %d points, expected %d (2 per radial segment)" % [body.name, points.size(), mesh.radial_segments * 2]
	var mesh_vertices: PackedVector3Array = mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
	for point in points:
		var found := false
		for vertex in mesh_vertices:
			if point.is_equal_approx(vertex):
				found = true
				break
		if not found:
			return "%s prism point %s is not a vertex of the visible mesh" % [body.name, point]
		if not is_equal_approx(absf(point.y), mesh.height * 0.5) or not is_equal_approx(Vector2(point.x, point.z).length(), expected_radius):
			return "%s prism point %s is not on the side wall rim" % [body.name, point]
	return ""

func _test_sections_have_matching_collision_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var mismatch := _prism_mismatch(station.get_node("Section0"), 30.0)
	if mismatch != "":
		print("FAIL _test_sections_have_matching_collision_shape: " + mismatch)
		result = 1
	station.free()
	return result

func _test_bridges_have_matching_collision_shape() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var mismatch := _prism_mismatch(station.get_node("Bridge0"), 9.0)
	if mismatch != "":
		print("FAIL _test_bridges_have_matching_collision_shape: " + mismatch)
		result = 1
	station.free()
	return result

func _test_section_collision_shapes_are_shared() -> int:
	var station := _make_station(4)
	station.build_station()
	var shape0: Shape3D = (station.get_node("Section0").get_node("Collision") as CollisionShape3D).shape
	var shape1: Shape3D = (station.get_node("Section1").get_node("Collision") as CollisionShape3D).shape
	var result := 0
	if shape0 == null or shape0 != shape1:
		print("FAIL _test_section_collision_shapes_are_shared: Section0 and Section1 use different collision shape resources")
		result = 1
	station.free()
	return result

func _test_bridge_collision_shapes_are_shared() -> int:
	var station := _make_station(4)
	station.build_station()
	var shape0: Shape3D = (station.get_node("Bridge0").get_node("Collision") as CollisionShape3D).shape
	var shape1: Shape3D = (station.get_node("Bridge1").get_node("Collision") as CollisionShape3D).shape
	var result := 0
	if shape0 == null or shape0 != shape1:
		print("FAIL _test_bridge_collision_shapes_are_shared: Bridge0 and Bridge1 use different collision shape resources")
		result = 1
	station.free()
	return result

func _test_bridge_radius_and_length_helpers() -> int:
	var station := _make_station(4)
	var result := 0
	if not is_equal_approx(station.get_bridge_radius(), 9.0):
		print("FAIL _test_bridge_radius_and_length_helpers: bridge radius %f expected 9.0" % station.get_bridge_radius())
		result = 1
	var expected_length: float = TorusGeometry.compute_bridge_length(500.0, 1500.0, 4, 80.0)
	if not is_equal_approx(station.get_bridge_length(), expected_length):
		print("FAIL _test_bridge_radius_and_length_helpers: bridge length %f expected %f" % [station.get_bridge_length(), expected_length])
		result = 1
	station.free()
	return result

func _test_no_docking_collars_left() -> int:
	var station := _make_station(4)
	station.build_station()
	var result := 0
	for child in station.get_children():
		if String(child.name).begins_with("DockingCollar"):
			print("FAIL _test_no_docking_collars_left: %s still there" % child.name)
			result = 1
			break
	station.free()
	return result

# The two top-ring vertices of the bridge prism closest to `direction`
# (bridge-local, perpendicular to the axis).
func _face_vertices(bridge: Node3D, direction: Vector3) -> Array:
	var mesh: CylinderMesh = (bridge.get_node("Mesh") as MeshInstance3D).mesh
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top := mesh.height * 0.5
	var ring := []
	for v in vertices:
		if is_equal_approx(v.y, top) and Vector2(v.x, v.z).length() > mesh.top_radius * 0.99 and not ring.has(v):
			ring.append(v)
	ring.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.normalized().dot(direction) > b.normalized().dot(direction))
	return [ring[0], ring[1]]

func _test_each_bridge_has_a_dock_pad_flat_on_one_face() -> int:
	# Small station: bridge radius 9. The pad lies on one flat face of the
	# prism, lifted by PAD_LIFT_RATIO of the radius, inside the face's width.
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var lift: float = 9.0 * TorusStationScript.PAD_LIFT_RATIO
	for i in range(4):
		var bridge: Node3D = station.get_node("Bridge%d" % i)
		var pad := bridge.get_node_or_null("DockPad") as MeshInstance3D
		var port := bridge.get_node_or_null("Port") as Node3D
		if pad == null or port == null or not (pad.mesh is PlaneMesh):
			print("FAIL _test_each_bridge_has_a_dock_pad_flat_on_one_face: Bridge%d has no DockPad plane or no Port" % i)
			result = 1
			continue
		var normal: Vector3 = pad.transform.basis.y.normalized()
		var face: Array = _face_vertices(bridge, normal)
		var plane_distance: float = face[0].dot(normal)
		var face_width: float = (face[0] - face[1]).length()
		if absf(face[1].dot(normal) - plane_distance) > 1e-3 or absf(normal.y) > 1e-6:
			print("FAIL _test_each_bridge_has_a_dock_pad_flat_on_one_face: Bridge%d pad is not parallel to a prism face" % i)
			result = 1
		var plane: PlaneMesh = pad.mesh
		for corner in [Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, -0.5), Vector3(-0.5, 0.0, 0.5), Vector3(0.5, 0.0, 0.5)]:
			var p: Vector3 = pad.transform * Vector3(corner.x * plane.size.x, 0.0, corner.z * plane.size.y)
			var across: float = absf((p - normal * p.dot(normal)).dot((face[0] - face[1]).normalized()))
			if absf(p.dot(normal) - plane_distance - lift) > 1e-3 or across > face_width * 0.5:
				print("FAIL _test_each_bridge_has_a_dock_pad_flat_on_one_face: Bridge%d pad corner %s is %.4f above the face (expected %.4f) and %.3f across (face half-width %.3f)" % [i, p, p.dot(normal) - plane_distance, lift, across, face_width * 0.5])
				result = 1
				break
		if not port.position.is_equal_approx(pad.position) or not port.transform.basis.x.normalized().is_equal_approx(normal) or not port.transform.basis.y.normalized().is_equal_approx(Vector3.UP):
			print("FAIL _test_each_bridge_has_a_dock_pad_flat_on_one_face: Bridge%d port not at the pad centre facing out along the axis" % i)
			result = 1
	station.free()
	return result

func _test_dock_pads_share_mesh_and_textured_material() -> int:
	var station := _make_station(4)
	station.build_station()
	var pad0: MeshInstance3D = station.get_node("Bridge0/DockPad")
	var pad1: MeshInstance3D = station.get_node("Bridge1/DockPad")
	var result := 0
	if pad0.mesh != pad1.mesh or pad0.material_override != pad1.material_override or pad0.material_override != DockPadTexture.pad_material():
		print("FAIL _test_dock_pads_share_mesh_and_textured_material: pads do not share the mesh and the dock pad material")
		result = 1
	if not is_equal_approx(pad0.visibility_range_end, 9.0 * TorusStationScript.PAD_VISIBLE_RATIO):
		print("FAIL _test_dock_pads_share_mesh_and_textured_material: pad drawn up to %f m" % pad0.visibility_range_end)
		result = 1
	station.free()
	return result

func _test_port_sits_on_its_still_bridge() -> int:
	var station := _make_station(4)
	station.build_station()
	var bridge: Node3D = station.get_node("Bridge0")
	var port: Node3D = station.get_docking_port(0)
	var result := 0
	if port.get_parent() != bridge:
		print("FAIL _test_port_sits_on_its_still_bridge: the port is not on the bridge")
		result = 1
	var before: Vector3 = bridge.transform * port.position
	station._rotate_sections(1.0)
	if not (bridge.transform * port.position).is_equal_approx(before):
		print("FAIL _test_port_sits_on_its_still_bridge: the port moved as the sections turned")
		result = 1
	station.free()
	return result

func _test_every_pad_has_four_corner_lamps() -> int:
	# Small station: bridge radius 9, lamps 9/600 m above the pad, on the
	# texture's green corner spots.
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var first: MeshInstance3D = null
	for i in range(4):
		var bridge: Node3D = station.get_node("Bridge%d" % i)
		var pad: MeshInstance3D = bridge.get_node("DockPad")
		if bridge.get_node_or_null("Beacon") != null:
			print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d still has the old beacon" % i)
			result = 1
		var half: float = (pad.mesh as PlaneMesh).size.x * (0.5 - DockPadTexture.LAMP_INSET)
		var normal: Vector3 = pad.transform.basis.y.normalized()
		for k in range(4):
			var lamp := bridge.get_node_or_null("DockLamp_%d" % k) as MeshInstance3D
			if lamp == null:
				print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d has no DockLamp_%d" % [i, k])
				result = 1
				continue
			if first == null:
				first = lamp
			var offset: Vector3 = lamp.position - pad.position
			var height: float = offset.dot(normal)
			var flat: Vector3 = offset - normal * height
			var across: float = absf(flat.dot(pad.transform.basis.x.normalized()))
			var along: float = absf(flat.dot(pad.transform.basis.z.normalized()))
			if not is_equal_approx(height, 9.0 * TorusStationScript.LAMP_LIFT_RATIO) or not is_equal_approx(across, half) or not is_equal_approx(along, half):
				print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d DockLamp_%d at %.3f up, %.3f / %.3f across (expected %.3f, %.3f)" % [i, k, height, across, along, 9.0 * TorusStationScript.LAMP_LIFT_RATIO, half])
				result = 1
			if not lamp.transform.basis.y.normalized().is_equal_approx(normal):
				print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d DockLamp_%d does not carry its pad's normal as its up" % [i, k])
				result = 1
			if lamp.mesh != first.mesh or lamp.material_override != first.material_override or not (lamp.material_override is ShaderMaterial):
				print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d DockLamp_%d does not share the lamp mesh and shader material" % [i, k])
				result = 1
			if not is_equal_approx(lamp.visibility_range_end, TorusStationScript.LAMP_RANGE) or lamp.extra_cull_margin < TorusStationScript.LAMP_CULL_MARGIN:
				print("FAIL _test_every_pad_has_four_corner_lamps: Bridge%d DockLamp_%d drawn to %f m, cull margin %f" % [i, k, lamp.visibility_range_end, lamp.extra_cull_margin])
				result = 1
	station.free()
	return result

func _test_lamp_shader_keeps_a_minimum_size_and_blinks() -> int:
	# Headless has no renderer: check the code and parameters (Task 5 renders).
	var station := _make_station(4)
	station.build_station()
	var material := (station.get_node("Bridge0/DockLamp_0") as MeshInstance3D).material_override as ShaderMaterial
	var code: String = material.shader.code
	var result := 0
	# At the pixel floor the lamp is a full square: a 2 px quad cut to a
	# circle covers almost no pixel centres and vanishes (seen in renders at
	# 3 and 30 km). It rounds off only from 3 px up.
	# Depth-tested, so sections and bridges in front hide the lamps; pulled
	# toward the camera by max(own size, 1% of the distance) so the pad
	# face does not cut them; hidden too when their pad faces away.
	for needle in ["skip_vertex_transform", "PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x", "max(lamp_size, min_pixels * pixel * depth)", "pull", "max(world_size, 0.01 * depth)", "facing", "mod(TIME, period)", "discard", "round_shape", "3.0 * pixel * depth"]:
		if not code.contains(needle):
			print("FAIL _test_lamp_shader_keeps_a_minimum_size_and_blinks: shader lacks '%s'" % needle)
			result = 1
	# Without the depth test, lamps floated over the 2 km-wide section hulls
	# standing between the camera and the pad.
	if code.contains("depth_test_disabled"):
		print("FAIL _test_lamp_shader_keeps_a_minimum_size_and_blinks: lamps skip the depth test and show through sections")
		result = 1
	if not is_equal_approx(material.get_shader_parameter("lamp_size"), 8.0) or not is_equal_approx(material.get_shader_parameter("min_pixels"), 2.0):
		print("FAIL _test_lamp_shader_keeps_a_minimum_size_and_blinks: lamp_size %s min_pixels %s" % [material.get_shader_parameter("lamp_size"), material.get_shader_parameter("min_pixels")])
		result = 1
	station.free()
	return result

func _test_every_section_has_its_id_stencilled_on_the_hull() -> int:
	# 4 positions round the circumference x 7 characters in "T1-0003" (index
	# 2): one MultiMeshInstance3D per section, visible from well beyond
	# 80 km, using the shared glyph atlas. Headless runs cannot read
	# MultiMesh instances back (see test_terrain_dressing.gd), so the actual
	# placement and atlas cells are checked directly against SectionLabel's
	# own output in test_section_label.gd; here only the wiring is checked.
	var station := _make_station(4)
	station.build_station()
	var result := 0
	var labels := station.get_node_or_null("Section2/Labels") as MultiMeshInstance3D
	if labels == null or labels.multimesh == null:
		print("FAIL _test_every_section_has_its_id_stencilled_on_the_hull: no Labels multimesh on Section2")
		return 1
	var text := SectionLabelScript.format_id(2)
	var expected_count: int = SectionLabelScript.ANGLES.size() * text.length()
	if labels.multimesh.instance_count != expected_count:
		print("FAIL _test_every_section_has_its_id_stencilled_on_the_hull: %d instances, expected %d" % [labels.multimesh.instance_count, expected_count])
		result = 1
	if not labels.multimesh.use_custom_data:
		print("FAIL _test_every_section_has_its_id_stencilled_on_the_hull: no per-instance custom data (needed for the atlas cell)")
		result = 1
	if labels.visibility_range_end < 80000.0:
		print("FAIL _test_every_section_has_its_id_stencilled_on_the_hull: visibility range %f, must reach 80 km" % labels.visibility_range_end)
		result = 1
	var mat := labels.material_override as ShaderMaterial
	if mat == null or (mat.get_shader_parameter("atlas") as Texture2D) == null or not (mat.get_shader_parameter("atlas") as Texture2D).resource_path.ends_with("labels/atlas.png"):
		print("FAIL _test_every_section_has_its_id_stencilled_on_the_hull: label material lacks the shared atlas")
		result = 1
	station.free()
	return result

func _test_section_labels_use_the_curved_glyph_mesh() -> int:
	var station := _make_station(4)
	station.section_radius = 2000.0
	station.build_station()
	var labels := station.get_node("Section0/Labels") as MultiMeshInstance3D
	var mesh := labels.multimesh.mesh
	if not mesh is ArrayMesh:
		print("FAIL _test_section_labels_use_the_curved_glyph_mesh: labels still use a flat primitive mesh")
		station.free()
		return 1
	var vertices: PackedVector3Array = (mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var has_cylindrical_depth := false
	for vertex in vertices:
		if vertex.z < -1.0:
			has_cylindrical_depth = true
			break
	if vertices.size() <= 4 or not has_cylindrical_depth:
		print("FAIL _test_section_labels_use_the_curved_glyph_mesh: assigned mesh has no cylindrical depth")
		station.free()
		return 1
	station.free()
	return 0

func _test_label_shader_does_not_back_face_cull() -> int:
	# Verified live (real GPU, real scene, real gameplay loop): with
	# cull_back the label glyphs never render — swapping to cull_disabled in
	# an otherwise-identical material made "T1-0001" appear immediately, at
	# every distance and rotation angle tried. The glyph mesh's winding, as
	# actually built from label_instances()'s basis and carried through a
	# section's live (rotated) transform, ends up back-facing the camera in
	# the real scene even though isolated repros (fixed, unrotated
	# transforms) showed it front-facing — headless can't render to tell
	# the difference, so this pins the fix as a shader-source assertion.
	# A thin decorative hull marking has no reason to cull either face.
	var station := _make_station(4)
	station.build_station()
	var labels := station.get_node("Section0/Labels") as MultiMeshInstance3D
	var code: String = (labels.material_override as ShaderMaterial).shader.code
	var result := 0
	if code.contains("cull_back"):
		print("FAIL _test_label_shader_does_not_back_face_cull: shader still has cull_back")
		result = 1
	if not code.contains("cull_disabled"):
		print("FAIL _test_label_shader_does_not_back_face_cull: shader should declare cull_disabled")
		result = 1
	station.free()
	return result

func _test_sections_use_the_bridge_panel_texture() -> int:
	# Sections now use the same rectangular panel texture as bridges (much
	# nicer than the old hexagon hull), each with its own material resource
	# (their circumference and length give a different whole-repeat count),
	# a whole number of ~100 m repeats round and along the side (the side's
	# UV v spans 0..0.5, so the scale doubles that).
	var station := _make_station(4)
	station.build_station()
	var bridge_mat := (station.get_node("Bridge0/Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	var section_mat := (station.get_node("Section0/Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	var result := 0
	if bridge_mat == null or section_mat == null or bridge_mat == section_mat:
		print("FAIL _test_sections_use_the_bridge_panel_texture: bridge and section must be separate material resources")
		station.free()
		return 1
	for mat in [bridge_mat, section_mat]:
		if mat.albedo_texture == null or not mat.albedo_texture.resource_path.ends_with("bridge/color.png") or not mat.emission_enabled or mat.emission_texture == null or mat.normal_texture == null:
			print("FAIL _test_sections_use_the_bridge_panel_texture: material %s lacks the panel textures" % mat)
			result = 1
			continue
		var round_repeats: float = mat.uv1_scale.x
		var along_repeats: float = mat.uv1_scale.y * 0.5
		if round_repeats != roundf(round_repeats) or along_repeats != roundf(along_repeats) or round_repeats < 1.0 or along_repeats < 1.0:
			print("FAIL _test_sections_use_the_bridge_panel_texture: uv scale %s is not whole repeats" % mat.uv1_scale)
			result = 1
	station.free()
	return result
