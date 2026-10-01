extends SceneTree

# The subspace tunnel: hidden until started, a white flash at both ends.

const TunnelScript = preload("res://scripts/subspace_tunnel.gd")

func _init():
	var failures := 0
	failures += _test_hidden_until_started()
	failures += _test_flash_at_start_and_stop()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _tunnel() -> Node3D:
	var tunnel: Node3D = TunnelScript.new()
	tunnel.build()
	return tunnel

func _test_hidden_until_started() -> int:
	var tunnel := _tunnel()
	var result := 0
	var tube := tunnel.get_node_or_null("Tube") as MeshInstance3D
	var flash := tunnel.get_node_or_null("FlashLayer/Flash") as ColorRect
	if tube == null or flash == null or tunnel.get_node_or_null("Core") == null:
		print("FAIL _test_hidden_until_started: parts missing")
		result = 1
	elif tunnel.visible or flash.color.a > 0.0 or tunnel.running:
		print("FAIL _test_hidden_until_started: shown before the start")
		result = 1
	tunnel.free()
	return result

func _test_flash_at_start_and_stop() -> int:
	var tunnel := _tunnel()
	var flash := tunnel.get_node("FlashLayer/Flash") as ColorRect
	var result := 0
	tunnel.start()
	if not tunnel.visible or not tunnel.running or flash.color.a < 0.99:
		print("FAIL _test_flash_at_start_and_stop: no tunnel or flash at the start")
		result = 1
	tunnel.advance(TunnelScript.FLASH_TIME + 0.01)
	if flash.color.a > 0.0:
		print("FAIL _test_flash_at_start_and_stop: the flash did not fade")
		result = 1
	tunnel.stop()
	if tunnel.visible or tunnel.running or flash.color.a < 0.99:
		print("FAIL _test_flash_at_start_and_stop: tunnel still shown, or no flash at the end")
		result = 1
	tunnel.advance(TunnelScript.FLASH_TIME + 0.01)
	if flash.color.a > 0.0:
		print("FAIL _test_flash_at_start_and_stop: the end flash did not fade")
		result = 1
	tunnel.free()
	return result
