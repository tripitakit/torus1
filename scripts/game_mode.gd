extends Node

# Switches between flying outside the station (void-cruiser) and inside it
# (internal-cruiser in a separate interior world). The outside world is taken
# out of the tree while inside, kept in memory, and put back unchanged.

const DockingRules = preload("res://scripts/docking_rules.gd")
const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")
const MoonRoverScript = preload("res://scripts/moon_rover.gd")
const RoverRules = preload("res://scripts/rover_rules.gd")
const MoonBase = preload("res://scripts/moon_base.gd")
const MoonWalkerScript = preload("res://scripts/moon_walker.gd")
const OnFoot = preload("res://scripts/on_foot.gd")
const InteriorWalkerScript = preload("res://scripts/interior_walker.gd")
const SeleneInteriorScript = preload("res://scripts/selene_interior.gd")
const SeleneCrew = preload("res://scripts/selene_crew.gd")
const SeleneLayout = preload("res://scripts/selene_layout.gd")

enum Mode { VOID, INTERIOR, ROVER, ON_FOOT, ON_FOOT_INSIDE, IN_BASE }

@export var station_path: NodePath = NodePath("../PlanetSystem/TorusStation")
@export var void_cruiser_path: NodePath = NodePath("../VoidCruiser")
@export var rebase_path: NodePath = NodePath("../WorldOriginRebase")

const FADE_TIME := 0.4
# Down into Selene (the pad's lift) and the Travel Tube ride: each way.
const BASE_FADE_TIME := 1.0
const TUBE_FADE_TIME := 0.75
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
var _rover: CharacterBody3D
var _walker: CharacterBody3D
var _base: Node3D
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
			cockpit.set_base_prompt(_can_enter_base())
	elif mode == Mode.ROVER:
		if _rover != null:
			_rover.set_board_prompt(_can_board_now())
	elif mode == Mode.ON_FOOT:
		if _walker != null:
			_walker.set_board_prompt(_board_target() != "")
			var targets := [["SHIP", _void_cruiser]]
			if _rover != null:
				targets.append(["ROVER", _rover])
			_walker.set_targets(targets)
	elif mode == Mode.INTERIOR and _interior:
		var cruiser := _interior.get_node("InternalCruiser") as Node3D
		_interior.set_undock_ready(_interior.nearest_dock_slot(cruiser.position), _can_undock_now())
		cruiser.set_land_prompt(_can_land_now())
		var pad: Dictionary = _interior.nearest_pad(cruiser.position)
		var shown: bool = not pad.is_empty() and pad.distance < PAD_MARKER_RANGE
		cruiser.update_pad_marker((pad.transform as Transform3D).origin if shown else Vector3.ZERO, pad.get("distance", 0.0), shown)
	elif mode == Mode.IN_BASE and _base != null:
		var walker := _base.get_node("BaseWalker") as CharacterBody3D
		var hud := walker.get_node("Hud")
		var stop: String = _base.tube_stop_at(walker.position)
		if _base.near_lift(walker.position):
			hud.set_prompt("K EAGLE")
		elif stop == "dock":
			hud.set_prompt("K CENTRO")
		elif stop == "centre":
			hud.set_prompt("K SBARCO")
		else:
			hud.set_prompt("")
		hud.set_place(_base.room_name(walker.position))
	elif mode == Mode.ON_FOOT_INSIDE and _interior:
		var walker := _interior.get_node_or_null("InteriorWalker")
		if walker != null:
			walker.set_board_prompt(_can_board_cruiser())
			walker.set_targets([["CRUISER", _interior.get_node("InternalCruiser")]])

func _unhandled_input(event: InputEvent) -> void:
	if _crashed:
		if _crash_screen_up and event.is_action_pressed("restart"):
			restart_after_crash()
		return
	if _transitioning:
		return
	if event.is_action_pressed("board"):
		if mode == Mode.VOID and _can_leave_ship_now():
			_transition(walk_from_ship)
		elif mode == Mode.ROVER and _rover != null and _rover.speed() < RoverRules.BOARD_SPEED:
			_transition(walk_from_rover)
		elif mode == Mode.INTERIOR and _can_land_now():
			_land_and_walk()
		elif mode == Mode.ON_FOOT_INSIDE and _can_board_cruiser():
			_transition(board_cruiser)
		elif mode == Mode.IN_BASE:
			var walker := _base.get_node("BaseWalker") as Node3D
			if _base.near_lift(walker.position):
				_transition(exit_base, BASE_FADE_TIME)
			elif _base.tube_stop_at(walker.position) != "":
				_transition(ride_tube, TUBE_FADE_TIME)
		elif mode == Mode.ON_FOOT:
			var target := _board_target()
			if target == "ship":
				_transition(board_ship_on_foot)
			elif target == "rover":
				_transition(board_rover_on_foot)
		return
	if event.is_action_pressed("base"):
		if mode == Mode.VOID and _can_enter_base():
			_transition(enter_base, BASE_FADE_TIME)
		return
	if event.is_action_pressed("vehicle"):
		if mode == Mode.VOID and _can_leave_ship_now():
			_transition(leave_ship)
		elif mode == Mode.ROVER and _can_board_now():
			_transition(board_ship)
		return
	if not event.is_action_pressed("dock"):
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

func rover() -> CharacterBody3D:
	return _rover

# Landed on the moon, the rover can come out.
func _can_leave_ship_now() -> bool:
	return _void_cruiser.is_landed and _void_cruiser.in_moon_frame and not _void_cruiser.is_crashed and _void_cruiser.moon_node() != null

func _can_board_now() -> bool:
	if _rover == null:
		return false
	var pad := _ship_pad()
	return RoverRules.can_board(_rover.global_position, _rover.speed(), _void_cruiser.global_position, not pad.is_empty(), pad.get("centre", Vector3.ZERO))

# The pad the landed ship sits on: {centre (its top's centre, world)}, or
# empty when it sits on the bare ground.
func _ship_pad() -> Dictionary:
	var target: Dictionary = _void_cruiser.landing_target()
	if target.is_empty():
		return {}
	var pad: Transform3D = target.pad
	var up: Vector3 = pad.basis.y.normalized()
	var offset: Vector3 = _void_cruiser.global_position - pad.origin
	var across: Vector3 = offset - up * offset.dot(up)
	return {"centre": pad.origin} if across.length() < MoonBase.PAD_RADIUS * sqrt(2.0) else {}

# The pad shown in the internal cruiser's HUD within this range.
const PAD_MARKER_RANGE := 3000.0
# Over a pad, the cruiser may land: this far off its middle on its plane,
# this high at most, this slow.
const PAD_LAND_REACH := 20.0
const PAD_LAND_HEIGHT := 30.0
const PAD_LAND_SPEED := 2.0
# Out of the landed cruiser: this far to its left.
const CRUISER_EXIT := 4.0

# Out of the ship into the rover: beside the ship (or clear of its pad), in
# the first spot with nothing in the way; the ship parked; the rover's eyes
# and the world origin with the rover. With no room anywhere the pilot stays
# aboard.
func leave_ship() -> void:
	var moon: Node3D = _void_cruiser.moon_node()
	var ship := _void_cruiser.global_transform.orthonormalized()
	var up: Vector3 = moon.up_at(ship.origin)
	var pad := _ship_pad()
	var spots := RoverRules.spawn_spots(ship, up, not pad.is_empty(), pad.get("centre", Vector3.ZERO))
	_rover = MoonRoverScript.new()
	_rover.name = "MoonRover"
	_rover.ship = _void_cruiser
	get_parent().add_child(_rover)
	_rover.moon_path = _rover.get_path_to(moon)
	var room := false
	for spot in spots:
		_rover.place(spot, -ship.basis.z)
		if _rover.is_clear():
			room = true
			break
	if not room:
		get_parent().remove_child(_rover)
		_rover.free()
		_rover = null
		return
	_void_cruiser.park(true)
	_rover.camera().make_current()
	_track(_rover)
	mode = Mode.ROVER

# Back into the ship: the rover gone, the ship's controls and eyes back.
func board_ship() -> void:
	get_parent().remove_child(_rover)
	_rover.free()
	_rover = null
	_void_cruiser.park(false)
	var pilot_camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	if pilot_camera:
		pilot_camera.make_current()
	_track(_void_cruiser)
	mode = Mode.VOID

func walker() -> CharacterBody3D:
	return _walker

# Over a pad, slow, the cruiser not already landing or parked.
func _can_land_now() -> bool:
	var cruiser := _interior.get_node("InternalCruiser")
	if cruiser.parked or cruiser.is_landing():
		return false
	var pad: Dictionary = _interior.nearest_pad(cruiser.position)
	if pad.is_empty():
		return false
	var local: Vector3 = (pad.transform as Transform3D).affine_inverse() * cruiser.position
	return Vector2(local.x, local.z).length() <= PAD_LAND_REACH and local.y > 0.0 and local.y <= PAD_LAND_HEIGHT and cruiser.velocity.length() < PAD_LAND_SPEED

# The cruiser down on the pad by itself, then the pilot out on foot.
func _land_and_walk() -> void:
	var cruiser := _interior.get_node("InternalCruiser")
	_transitioning = true
	cruiser.land_on(_interior.nearest_pad(cruiser.position).transform)
	await cruiser.landed
	_transitioning = false
	_transition(walk_from_cruiser)

func walk_from_cruiser() -> void:
	var cruiser := _interior.get_node("InternalCruiser") as Node3D
	var up: Vector3 = cruiser.transform.basis.y.normalized()
	var left := -cruiser.transform.basis.x.normalized()
	var walker: CharacterBody3D = InteriorWalkerScript.new()
	walker.name = "InteriorWalker"
	_interior.add_child(walker)
	walker.place(cruiser.position - up * (cruiser.HULL_SIZE.y * 0.5 - 0.1) + left * CRUISER_EXIT, left)
	cruiser.park(true)
	walker.camera().make_current()
	mode = Mode.ON_FOOT_INSIDE

func _can_board_cruiser() -> bool:
	var walker := _interior.get_node_or_null("InteriorWalker") as Node3D
	var cruiser := _interior.get_node("InternalCruiser")
	return walker != null and OnFoot.distance_to_box(walker.position, cruiser.transform, cruiser.HULL_SIZE) <= OnFoot.BOARD_DISTANCE

func board_cruiser() -> void:
	var walker := _interior.get_node_or_null("InteriorWalker")
	if walker != null:
		_interior.remove_child(walker)
		walker.free()
	var cruiser := _interior.get_node("InternalCruiser")
	cruiser.park(false)
	(cruiser.get_node("Camera") as Camera3D).make_current()
	mode = Mode.INTERIOR

# The vehicle the walker on the moon can board: "ship", "rover" (the nearer
# when both are in reach) or "".
func _board_target() -> String:
	if _walker == null:
		return ""
	var at := _walker.global_position
	var best := ""
	var best_distance := INF
	var ship_distance := OnFoot.distance_to_box(at, _void_cruiser.global_transform, _void_cruiser.HULL_SIZE)
	var pad := _ship_pad()
	if ship_distance <= OnFoot.BOARD_DISTANCE or (not pad.is_empty() and at.distance_to(pad.centre) <= OnFoot.PAD_BOARD):
		best = "ship"
		best_distance = ship_distance
	if _rover != null:
		var box := Transform3D(_rover.global_transform.basis, _rover.to_global(_rover.BOX_CENTRE))
		var rover_distance := OnFoot.distance_to_box(at, box, _rover.BOX_SIZE)
		if rover_distance <= OnFoot.BOARD_DISTANCE and rover_distance < best_distance:
			best = "rover"
	return best

# A walker on the moon at the first clear spot, facing `facing`; null (and
# none made) with no room anywhere.
func _new_walker(spots: Array, facing: Vector3) -> CharacterBody3D:
	var moon: Node3D = _void_cruiser.moon_node()
	var walker: CharacterBody3D = MoonWalkerScript.new()
	walker.name = "MoonWalker"
	get_parent().add_child(walker)
	walker.moon_path = walker.get_path_to(moon)
	for spot in spots:
		walker.place(spot, facing)
		if walker.is_clear():
			return walker
	get_parent().remove_child(walker)
	walker.free()
	return null

# Out of the landed ship on foot, beside it (or clear of its pad).
func walk_from_ship() -> void:
	var moon: Node3D = _void_cruiser.moon_node()
	var ship := _void_cruiser.global_transform.orthonormalized()
	var up: Vector3 = moon.up_at(ship.origin)
	var pad := _ship_pad()
	var spots := OnFoot.ship_exit_spots(ship, up, not pad.is_empty(), pad.get("centre", Vector3.ZERO))
	var outward: Vector3 = (spots[0] as Vector3) - ship.origin
	_walker = _new_walker(spots, outward - up * outward.dot(up))
	if _walker == null:
		return
	_void_cruiser.park(true)
	_walker.camera().make_current()
	_track(_walker)
	mode = Mode.ON_FOOT

# Out of the rover on foot, on its left; the rover left parked.
func walk_from_rover() -> void:
	var left := -_rover.global_transform.basis.x.normalized()
	_walker = _new_walker([_rover.global_position + left * 2.5], left)
	if _walker == null:
		return
	_rover.park(true)
	_walker.camera().make_current()
	_track(_walker)
	mode = Mode.ON_FOOT

func _drop_walker() -> void:
	if _walker != null:
		get_parent().remove_child(_walker)
		_walker.free()
		_walker = null

# On foot into the ship: the rover (if any) back in the hold.
func board_ship_on_foot() -> void:
	_drop_walker()
	if _rover != null:
		get_parent().remove_child(_rover)
		_rover.free()
		_rover = null
	_void_cruiser.park(false)
	var pilot_camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	if pilot_camera:
		pilot_camera.make_current()
	_track(_void_cruiser)
	mode = Mode.VOID

func board_rover_on_foot() -> void:
	_drop_walker()
	_rover.park(false)
	_rover.camera().make_current()
	_track(_rover)
	mode = Mode.ROVER

# Landed on one of Selene's pads, the pilot may go down into the base.
func _can_enter_base() -> bool:
	return _can_leave_ship_now() and not _ship_pad().is_empty()

# Down the pad's lift into Selene: the whole outside world (its sky too)
# off the tree, the ship parked on its pad; on foot in the dock.
func enter_base() -> void:
	var parent := get_parent()
	_detached.clear()
	for child in parent.get_children():
		if child != self:
			_detached.append([child, child.get_index()])
	for entry in _detached:
		parent.remove_child(entry[0])
	_void_cruiser.park(true)
	_base = SeleneInteriorScript.new()
	_base.name = "SeleneInterior"
	_base.build()
	var walker: CharacterBody3D = InteriorWalkerScript.new()
	walker.name = "BaseWalker"
	walker.flat = true
	walker.add_to_group(SeleneInteriorScript.PEOPLE_GROUP)
	walker.add_to_group(SeleneCrew.PILOT_GROUP)
	_base.add_child(walker)
	parent.add_child(_base)
	var spawn: Transform3D = _base.spawn_transform()
	walker.place(spawn.origin, -spawn.basis.z)
	walker.camera().make_current()
	(walker.get_node("Hud") as CanvasLayer).set_title("IN BASE")
	mode = Mode.IN_BASE

# Up the lift: the outside back as it was, aboard the Eagle on its pad.
func exit_base() -> void:
	var parent := get_parent()
	parent.remove_child(_base)
	_base.free()
	_base = null
	for entry in _detached:
		parent.add_child(entry[0])
		parent.move_child(entry[0], entry[1])
	_detached.clear()
	_void_cruiser.park(false)
	var pilot_camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	if pilot_camera:
		pilot_camera.make_current()
	_track(_void_cruiser)
	mode = Mode.VOID

# The Travel Tube to its other stop, the walker where it stood in the cabin.
func ride_tube() -> void:
	var walker := _base.get_node("BaseWalker") as CharacterBody3D
	var stop: String = _base.tube_stop_at(walker.position)
	var here: Transform3D = SeleneLayout.tube_stops()[stop]
	walker.transform = _base.tube_ride(stop) * (here.affine_inverse() * walker.transform)
	walker.velocity = Vector3.ZERO

# The world origin shift follows `node`.
func _track(node: Node3D) -> void:
	var rebase := get_node_or_null(rebase_path)
	if rebase != null:
		rebase.tracked_node = rebase.get_path_to(node)

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

func _transition(action: Callable, fade: float = FADE_TIME) -> void:
	_transitioning = true
	var tween := create_tween()
	tween.tween_property(_curtain, "color:a", 1.0, fade)
	await tween.finished
	action.call()
	tween = create_tween()
	tween.tween_property(_curtain, "color:a", 0.0, fade)
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
