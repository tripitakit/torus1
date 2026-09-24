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

var mode: Mode = Mode.VOID
var docked_bridge := -1

var _station: Node3D
var _void_cruiser: CharacterBody3D
var _interior: Node3D
var _detached: Array = []
var _transitioning := false
var _curtain: ColorRect

func _ready() -> void:
	_station = get_node(station_path)
	_void_cruiser = get_node(void_cruiser_path)
	_build_fade()

func is_inside() -> bool:
	return mode == Mode.INTERIOR

func is_transitioning() -> bool:
	return _transitioning

func _process(_delta: float) -> void:
	if mode == Mode.VOID:
		var cockpit := _void_cruiser.get_node_or_null("Cockpit")
		if cockpit:
			cockpit.set_dock_prompt(_can_dock_now())
	elif _interior:
		_interior.set_undock_ready(0, _can_undock_now())

func _unhandled_input(event: InputEvent) -> void:
	if _transitioning or not event.is_action_pressed("dock"):
		return
	if mode == Mode.VOID and _can_dock_now():
		_transition(enter_interior.bind(_station.nearest_bridge_index(_void_cruiser.global_position)))
	elif mode == Mode.INTERIOR and _can_undock_now():
		_transition(exit_interior)

func _can_dock_now() -> bool:
	var port: Node3D = _station.get_docking_port(_station.nearest_bridge_index(_void_cruiser.global_position))
	return DockingRules.can_dock(port.global_position.distance_to(_void_cruiser.global_position), _void_cruiser.velocity.length())

func _can_undock_now() -> bool:
	var cruiser: CharacterBody3D = _interior.get_node("InternalCruiser")
	return DockingRules.can_dock(_interior.get_dock_position(0).distance_to(cruiser.position), cruiser.velocity.length())

func enter_interior(bridge_index: int) -> void:
	var parent := get_parent()
	_detached.clear()
	for child in parent.get_children():
		if child == self or String(child.name) in KEPT_WHILE_INSIDE:
			continue
		_detached.append([child, child.get_index()])
	for entry in _detached:
		parent.remove_child(entry[0])

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
	var parent := get_parent()
	parent.remove_child(_interior)
	_interior.free()
	_interior = null
	# Back in their original order (indices were taken before any removal).
	for entry in _detached:
		parent.add_child(entry[0])
		parent.move_child(entry[0], entry[1])
	_detached.clear()

	var port: Node3D = _station.get_docking_port(docked_bridge)
	var outward: Vector3 = port.global_transform.basis.x.normalized()
	var along: Vector3 = port.global_transform.basis.y.normalized()
	_void_cruiser.global_transform = Transform3D(Basis.looking_at(outward, along), port.global_position + outward * UNDOCK_CLEARANCE)
	_void_cruiser.velocity = Vector3.ZERO
	_void_cruiser.angular_velocity = Vector3.ZERO
	var pilot_camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	if pilot_camera:
		pilot_camera.make_current()
	docked_bridge = -1
	mode = Mode.VOID

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
