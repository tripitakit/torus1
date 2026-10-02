extends SceneTree

# Where the base marker goes: on its point when on screen, on the screen's
# edge toward it when not (behind the camera too).

const BeaconMarker = preload("res://scripts/beacon_marker.gd")

const SCREEN := Vector2(1600.0, 900.0)

func _init():
	var failures := 0
	failures += _test_on_screen()
	failures += _test_off_to_the_right()
	failures += _test_behind_goes_to_the_opposite_edge()
	failures += _test_marker_node()
	failures += _test_tiny_screen()
	failures += _test_labels_kept_apart_on_leader_lines()
	failures += _test_edge_labels_kept_apart()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_on_screen() -> int:
	# In front (camera space -Z), projected inside the screen.
	var place := BeaconMarker.placement(Vector3(0.1, 0.05, -1.0), Vector2(900.0, 400.0), SCREEN)
	if not place.on_screen or place.point != Vector2(900.0, 400.0):
		print("FAIL _test_on_screen: %s" % place)
		return 1
	return 0

func _test_off_to_the_right() -> int:
	# Far right and a little up: on the right edge, arrow pointing right.
	var place := BeaconMarker.placement(Vector3(5.0, 0.5, -1.0), Vector2(5000.0, 300.0), SCREEN)
	if place.on_screen or absf(place.point.x - (SCREEN.x - BeaconMarker.EDGE_MARGIN)) > 0.01 or place.point.y >= SCREEN.y * 0.5 or absf(place.angle) > 0.2:
		print("FAIL _test_off_to_the_right: %s" % place)
		return 1
	return 0

func _test_behind_goes_to_the_opposite_edge() -> int:
	# Behind and to the left: the marker waits on the left edge (turn left).
	var place := BeaconMarker.placement(Vector3(-1.0, 0.0, 2.0), Vector2(1200.0, 450.0), SCREEN)
	if place.on_screen or absf(place.point.x - BeaconMarker.EDGE_MARGIN) > 0.01 or absf(absf(place.angle) - PI) > 0.2:
		print("FAIL _test_behind_goes_to_the_opposite_edge: %s" % place)
		return 1
	# Straight behind: still somewhere on an edge, never the centre.
	place = BeaconMarker.placement(Vector3(0.0, 0.0, 1.0), SCREEN * 0.5, SCREEN)
	if place.on_screen or place.point.distance_to(SCREEN * 0.5) < 100.0:
		print("FAIL _test_behind_goes_to_the_opposite_edge: dead astern at %s" % place.point)
		return 1
	return 0

func _test_marker_node() -> int:
	var marker: Control = BeaconMarker.new()
	var result := 0
	if marker.visible or marker.mouse_filter != Control.MOUSE_FILTER_IGNORE or marker.prefix != "SELENE" or marker.color != BeaconMarker.COLOR:
		print("FAIL _test_marker_node: shown from the start or catching the mouse")
		result = 1
	marker.free()
	return result

func _test_tiny_screen() -> int:
	# A view smaller than the margins (headless runs): no negative rectangle,
	# the point stays on the screen.
	var tiny := Vector2(50.0, 50.0)
	var place := BeaconMarker.placement(Vector3(5.0, 0.0, -1.0), Vector2(300.0, 25.0), tiny)
	if place.point.x < 0.0 or place.point.x > tiny.x or place.point.y < 0.0 or place.point.y > tiny.y:
		print("FAIL _test_tiny_screen: %s on a 50 px screen" % place.point)
		return 1
	return 0

func _test_labels_kept_apart_on_leader_lines() -> int:
	# Several markers on one spot (the gate and the flight computer's point
	# 500 m in front of it, seen from afar): each label sits out at its own
	# corner at the end of a diagonal line from the diamond, so they never
	# cover each other or the diamond.
	var point := Vector2(800.0, 450.0)
	var size := Vector2(170.0, 22.0)
	var rects := []
	for offset in [BeaconMarker.LABEL_UP_LEFT, BeaconMarker.LABEL_DOWN_RIGHT, BeaconMarker.LABEL_UP_RIGHT]:
		var rect := BeaconMarker.label_rect(point, offset, size)
		var line := BeaconMarker.leader_line(point, offset)
		if rect.has_point(point) or line[0].distance_to(point) > BeaconMarker.DIAMOND + 1.0 or absf(absf((line[1] - line[0]).angle()) - PI * 0.5) < 0.3 or absf((line[1] - line[0]).angle()) < 0.3 or absf(absf((line[1] - line[0]).angle()) - PI) < 0.3:
			print("FAIL _test_labels_kept_apart_on_leader_lines: %s: label %s, line %s" % [offset, rect, line])
			return 1
		for other in rects:
			if rect.intersects(other):
				print("FAIL _test_labels_kept_apart_on_leader_lines: %s overlaps %s" % [rect, other])
				return 1
		rects.append(rect)
	return 0

func _test_edge_labels_kept_apart() -> int:
	# Off the screen two markers can wait at one arrow (the gate and the
	# flight computer's point behind the ship): their labels go up or down
	# by their corner, far enough apart.
	var point := Vector2(SCREEN.x - BeaconMarker.EDGE_MARGIN, 450.0)
	var up := BeaconMarker.edge_label_at(point, 0.0, BeaconMarker.LABEL_UP_LEFT)
	var down := BeaconMarker.edge_label_at(point, 0.0, BeaconMarker.LABEL_DOWN_RIGHT)
	if absf(up.y - down.y) < BeaconMarker.FONT_SIZE * 2.0 or up.y >= down.y:
		print("FAIL _test_edge_labels_kept_apart: %s and %s" % [up, down])
		return 1
	return 0
