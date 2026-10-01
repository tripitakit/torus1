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
	if marker.visible or marker.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		print("FAIL _test_marker_node: shown from the start or catching the mouse")
		result = 1
	marker.free()
	return result
