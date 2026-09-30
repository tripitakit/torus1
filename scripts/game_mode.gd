extends Node

# Switches between flying outside the station (void-cruiser) and inside it
# (internal-cruiser in a separate interior world). The outside world is taken
# out of the tree while inside, kept in memory, and put back unchanged.

const DockingRules = preload("res://scripts/docking_rules.gd")
const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")

enum Mode { VOID, INTERIOR }

@export var station_path: NodePath = NodePath("../PlanetSystem/TorusStation")
@export var void_cruiser_path: NodePath = NodePath("../VoidCruiser")

const FADE_TIME := 0.4
# The void-cruiser reappears this far out from the port it docked at.
const UNDOCK_CLEARANCE := 60.0
const KEPT_WHILE_INSIDE := ["WorldEnvironment"]
# A crash on the planet: a flash, the pilot camera shaking, a fade to the
# crash screen that waits for R, then the ship back at rest by a dock.
const CRASH_FLASH_TIME := 0.15
const CRASH_SHAKE_TIME := 0.6
const CRASH_SHAKE := 0.4
const CRASH_FADE_TIME := 1.0
const CRASH_FLASH_COLOR := Color(1.0, 0.75, 0.45, 1.0)
const CRASH_SCREEN_COLOR := Color(0.22, 0.02, 0.02, 0.92)
const CRASH_TEXT := "CRASH\nPRESS R TO RESTART"

var mode: Mode = Mode.VOID
var docked_bridge := -1

var _station: Node3D
var _void_cruiser: CharacterBody3D
var _interior: Node3D
var _detached: Array = []
var _transitioning := false
var _curtain: ColorRect
var _crash_label: Label
# Crashed, and whether the crash screen is up (waiting for R).
var _crashed := false
var _crash_screen_up := false

func _ready() -> void:
	_station = get_node(station_path)
	_void_cruiser = get_node(void_cruiser_path)
	_build_fade()
	if _void_cruiser.has_signal("crashed"):
		_void_cruiser.crashed.connect(_on_crashed)

func _notification(what: int) -> void:
	# Freed while inside (the game quits): the outside world is out of the
	# tree and nothing else would ever free it.
	if what == NOTIFICATION_PREDELETE:
		for entry in _detached:
			var node: Node = entry[0]
			if is_instance_valid(node) and not node.is_inside_tree():
				node.free()
		_detached.clear()

func is_inside() -> bool:
	return mode == Mode.INTERIOR

func is_transitioning() -> bool:
	return _transitioning

func is_crashed() -> bool:
	return _crashed

func _process(_delta: float) -> void:
	if mode == Mode.VOID:
		var cockpit := _void_cruiser.get_node_or_null("Cockpit")
		if cockpit:
			cockpit.set_dock_prompt(_can_dock_now())
	elif _interior:
		var cruiser := _interior.get_node("InternalCruiser") as Node3D
		_interior.set_undock_ready(_interior.nearest_dock_slot(cruiser.position), _can_undock_now())

func _unhandled_input(event: InputEvent) -> void:
	if _crashed:
		if _crash_screen_up and event.is_action_pressed("restart"):
			restart_after_crash()
		return
	if _transitioning or not event.is_action_pressed("dock"):
		return
	if mode == Mode.VOID and _can_dock_now():
		_transition(enter_interior.bind(_station.nearest_bridge_index(_void_cruiser.global_position)))
	elif mode == Mode.INTERIOR and _can_undock_now():
		_transition(exit_interior)

func _can_dock_now() -> bool:
	var index: int = _station.nearest_bridge_index(_void_cruiser.global_position)
	var port: Node3D = _station.get_docking_port(index)
	# The pad stands still on its bridge: the ship's own speed counts.
	return DockingRules.can_dock(port.global_position.distance_to(_void_cruiser.global_position), _void_cruiser.velocity.length())

# Every bridge inside has a dock; the one nearest the craft counts.
func _can_undock_now() -> bool:
	var cruiser: CharacterBody3D = _interior.get_node("InternalCruiser")
	var dock: Vector3 = _interior.get_dock_position(_interior.nearest_dock_slot(cruiser.position))
	return DockingRules.can_dock(dock.distance_to(cruiser.position), cruiser.velocity.length())

func enter_interior(bridge_index: int) -> void:
	var parent := get_parent()
	_detached.clear()
	for child in parent.get_children():
		if child == self or String(child.name) in KEPT_WHILE_INSIDE:
			continue
		_detached.append([child, child.get_index()])
	for entry in _detached:
		parent.remove_child(entry[0])
	_show_dome(false)

	_interior = InteriorWorldScript.new()
	_interior.name = "InteriorWorld"
	_interior.section_radius = _station.section_radius
	_interior.section_length = _station.section_length
	_interior.bridge_radius = _station.get_bridge_radius()
	_interior.bridge_length = _station.get_bridge_length()
	# The chain starts at the docked bridge and wraps round the ring.
	_interior.docked_bridge_index = bridge_index
	_interior.ring_sections = _station.num_sections
	_interior.build()
	var cruiser: CharacterBody3D = InternalCruiserScript.new()
	cruiser.name = "InternalCruiser"
	cruiser.transform = _interior.get_spawn_transform()
	_interior.add_child(cruiser)
	parent.add_child(_interior)
	docked_bridge = bridge_index
	mode = Mode.INTERIOR

func exit_interior() -> void:
	# Out through the collar of the bridge whose dock is nearest.
	var cruiser := _interior.get_node_or_null("InternalCruiser") as Node3D
	if cruiser != null:
		docked_bridge = _interior.get_bridge_ring_index(_interior.nearest_dock_slot(cruiser.position))
	var parent := get_parent()
	parent.remove_child(_interior)
	_interior.free()
	_interior = null
	# Back in their original order (indices were taken before any removal).
	for entry in _detached:
		parent.add_child(entry[0])
		parent.move_child(entry[0], entry[1])
	_detached.clear()

	_place_by_port(docked_bridge)
	var pilot_camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	if pilot_camera:
		pilot_camera.make_current()
	_show_dome(true)
	docked_bridge = -1
	mode = Mode.VOID

# The void-cruiser at rest UNDOCK_CLEARANCE out from `bridge`'s port, bow
# outward, under the pilot's own hand (brake and cruise off).
func _place_by_port(bridge: int) -> void:
	var port: Node3D = _station.get_docking_port(bridge)
	var outward: Vector3 = port.global_transform.basis.x.normalized()
	var along: Vector3 = port.global_transform.basis.y.normalized()
	_void_cruiser.global_transform = Transform3D(Basis.looking_at(outward, along), port.global_position + outward * UNDOCK_CLEARANCE)
	_void_cruiser.velocity = Vector3.ZERO
	_void_cruiser.angular_velocity = Vector3.ZERO
	_void_cruiser.brake_engaged = false
	_void_cruiser.cruise_locked = false

func _on_crashed() -> void:
	if _crashed:
		return
	_crashed = true
	_crash_screen_up = false
	var camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	var tween := create_tween()
	tween.tween_property(_curtain, "color", CRASH_FLASH_COLOR, CRASH_FLASH_TIME * 0.5)
	tween.tween_property(_curtain, "color", Color(CRASH_FLASH_COLOR, 0.0), CRASH_FLASH_TIME * 0.5)
	if camera != null:
		tween.tween_method(_shake.bind(camera), 1.0, 0.0, CRASH_SHAKE_TIME)
	tween.tween_property(_curtain, "color", CRASH_SCREEN_COLOR, CRASH_FADE_TIME)
	tween.tween_callback(_show_crash_screen)

# Shakes `camera` by up to CRASH_SHAKE metres times `strength`.
func _shake(strength: float, camera: Camera3D) -> void:
	camera.h_offset = randf_range(-1.0, 1.0) * CRASH_SHAKE * strength
	camera.v_offset = randf_range(-1.0, 1.0) * CRASH_SHAKE * strength

func _show_crash_screen() -> void:
	_crash_label.visible = true
	_crash_screen_up = true

# R on the crash screen: back at rest by the nearest dock (or, after a crash
# on the moon, landed on Base Selene's pad 1), the screen fading away.
func restart_after_crash() -> void:
	var moon: Node3D = _void_cruiser.moon_node() if _void_cruiser.has_method("moon_node") else null
	if _void_cruiser.get("crashed_on_moon") and moon != null:
		var pad: Transform3D = moon.pad_transform(1)
		_void_cruiser.restart_after_crash()
		_void_cruiser.land_at(Transform3D(pad.basis, pad.origin + pad.basis.y.normalized() * _void_cruiser.HALF_HEIGHT))
	else:
		_place_by_port(_station.nearest_bridge_index(_void_cruiser.global_position))
		_void_cruiser.restart_after_crash()
	var camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	if camera != null:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	_crash_label.visible = false
	_crash_screen_up = false
	_crashed = false
	var tween := create_tween()
	tween.tween_property(_curtain, "color", Color(0.0, 0.0, 0.0, 0.0), FADE_TIME)

func _transition(action: Callable) -> void:
	_transitioning = true
	var tween := create_tween()
	tween.tween_property(_curtain, "color:a", 1.0, FADE_TIME)
	await tween.finished
	action.call()
	tween = create_tween()
	tween.tween_property(_curtain, "color:a", 0.0, FADE_TIME)
	await tween.finished
	_transitioning = false

func _build_fade() -> void:
	var fade := CanvasLayer.new()
	fade.name = "Fade"
	fade.layer = 100
	add_child(fade)
	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.add_child(_curtain)
	_crash_label = Label.new()
	_crash_label.name = "CrashLabel"
	_crash_label.text = CRASH_TEXT
	_crash_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crash_label.add_theme_font_size_override("font_size", 48)
	_crash_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.8))
	_crash_label.visible = false
	fade.add_child(_crash_label)

# The space backdrop (space_sky.gd on the kept WorldEnvironment), off inside.
func _show_dome(shown: bool) -> void:
	var world := get_parent().get_node_or_null("WorldEnvironment")
	if world != null and world.has_method("show_dome"):
		world.show_dome(shown)
