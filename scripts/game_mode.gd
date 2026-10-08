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
const OutpostInteriorScript = preload("res://scripts/outpost_interior.gd")
const TelescopeLayout = preload("res://scripts/telescope_layout.gd")
const DepotLayout = preload("res://scripts/depot_layout.gd")
const MoonSites = preload("res://scripts/moon_sites.gd")
const OllamaClient = preload("res://scripts/ollama_client.gd")
const NpcTerminal = preload("res://scripts/npc_terminal.gd")
const NpcTalk = preload("res://scripts/npc_talk.gd")
const TownFolk = preload("res://scripts/town_folk.gd")
const TownWalkers = preload("res://scripts/town_walkers.gd")
const LoopTraffic = preload("res://scripts/loop_traffic.gd")
const InteriorClock = preload("res://scripts/interior_clock.gd")
const LandingPads = preload("res://scripts/landing_pads.gd")

enum Mode { VOID, INTERIOR, ROVER, ON_FOOT, ON_FOOT_INSIDE, IN_BASE, IN_OUTPOST }

@export var station_path: NodePath = NodePath("../PlanetSystem/TorusStation")
@export var void_cruiser_path: NodePath = NodePath("../VoidCruiser")
@export var rebase_path: NodePath = NodePath("../WorldOriginRebase")

const FADE_TIME := 0.4
# Down into Selene (the pad's lift): each way.
const BASE_FADE_TIME := 1.0
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
# Talking: the prompt; a passer-by stood in for goes back to its round once
# the pilot is this far; the town walkers drawn near are looked for within
# this of the pilot (their group's bounds); Bastiani's coat; the share of
# walkers home at night (the town walkers' material).
const TALK_PROMPT := "P PARLA"
const STAND_IN_KEPT := 30.0
const WALKER_SEARCH := 10.0
const BASTIANI_COAT := Color(0.32, 0.24, 0.17)
const WALKERS_NIGHT_HIDE := 0.5

var mode: Mode = Mode.VOID
var docked_bridge := -1

var _station: Node3D
var _void_cruiser: CharacterBody3D
var _interior: Node3D
var _rover: CharacterBody3D
var _walker: CharacterBody3D
var _base: Node3D
# Inside a far-side outpost: its building, and which site it is.
var _outpost: Node3D
var _outpost_site := ""
var _detached: Array = []
var _transitioning := false
var _curtain: ColorRect
var _crash_label: Label
# Crashed, and whether the crash screen is up (waiting for R).
var _crashed := false
var _crash_screen_up := false
# The talk (NpcTalk on its terminal, Ollama behind), who is listening, and
# the passers-by stood in for: [{person, node, index}].
var _ollama: Node
var _terminal: CanvasLayer
var _talk: Node
var _listener: Node3D
var _stand_ins: Array = []
# Bastiani at the pad by the docked bridge 0 (where teleport 3 lands): the
# spawn point in the chain's frame until he is placed.
var _bastiani: Node3D
var _bastiani_spot := Vector3.INF

func _ready() -> void:
	_station = get_node(station_path)
	_void_cruiser = get_node(void_cruiser_path)
	_build_fade()
	_build_debug_legend()
	_build_talk()
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
	_tend_talk()
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
			# Before a hatch, in first: Area 2's depot is within PAD_BOARD
			# of its pad.
			var prompt := ""
			if _near_hatch() != "":
				prompt = "K AIRLOCK"
			elif _board_target() != "":
				prompt = "K BOARD"
			(_walker.get_node("Hud") as CanvasLayer).set_prompt(prompt)
			var targets := [["SHIP", _void_cruiser]]
			if _rover != null:
				targets.append(["ROVER", _rover])
			_walker.set_targets(targets)
	elif mode == Mode.IN_OUTPOST and _outpost != null:
		var inside := _outpost.get_node("BaseWalker") as CharacterBody3D
		var hud := inside.get_node("Hud")
		hud.set_prompt("K USCITA" if _outpost.near_hatch(inside.position) else "")
		hud.set_place(_outpost.room_name(inside.position))
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
		var prompt := _base_prompt(walker.position)
		if talking():
			prompt = ""
		elif prompt == "" and _talk_target() != null:
			prompt = TALK_PROMPT
		hud.set_prompt(prompt)
		hud.set_place(_base.room_name(walker.position))
	elif mode == Mode.ON_FOOT_INSIDE and _interior:
		var walker := _interior.get_node_or_null("InteriorWalker")
		if walker != null:
			var prompt := ""
			if talking():
				pass
			elif _can_board_cruiser():
				prompt = "K BOARD"
			elif _talk_target() != null:
				prompt = TALK_PROMPT
			(walker.get_node("Hud") as CanvasLayer).set_prompt(prompt)
			walker.set_targets([["CRUISER", _interior.get_node("InternalCruiser")]])

func _unhandled_input(event: InputEvent) -> void:
	if _crashed:
		if _crash_screen_up and event.is_action_pressed("restart"):
			restart_after_crash()
		return
	if _transitioning or (_talk != null and _talk.talking()):
		return
	if event.is_action_pressed("talk") and mode in [Mode.IN_BASE, Mode.ON_FOOT_INSIDE]:
		var target = _talk_target()
		if target != null:
			start_talk(target)
		return
	for number in range(1, 10):
		if event.is_action_pressed("teleport_%d" % number):
			teleport(number)
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
			var stop: String = _base.car_stop()
			var door: String = _base.near_tube_door(walker.position)
			if _base.near_lift(walker.position):
				_transition(exit_base, BASE_FADE_TIME)
			elif _base.in_car(walker.position) and stop != "":
				_base.start_ride()
			elif door != "" and stop != "" and stop != door:
				_base.call_car(door)
		elif mode == Mode.ON_FOOT:
			var target := _board_target()
			if _near_hatch() != "":
				_transition(enter_outpost.bind(_near_hatch()))
			elif target == "ship":
				_transition(board_ship_on_foot)
			elif target == "rover":
				_transition(board_rover_on_foot)
		elif mode == Mode.IN_OUTPOST:
			if _outpost.near_hatch((_outpost.get_node("BaseWalker") as Node3D).position):
				_transition(exit_outpost)
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

# The pad the landed ship sits on: {centre (its top's centre, world),
# number}, or
# empty when it sits on the bare ground.
func _ship_pad() -> Dictionary:
	var target: Dictionary = _void_cruiser.landing_target()
	if target.is_empty():
		return {}
	var pad: Transform3D = target.pad
	var up: Vector3 = pad.basis.y.normalized()
	var offset: Vector3 = _void_cruiser.global_position - pad.origin
	var across: Vector3 = offset - up * offset.dot(up)
	return {"centre": pad.origin, "number": target.number} if across.length() < MoonBase.PAD_RADIUS * sqrt(2.0) else {}

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

# Landed on one of Selene's pads, the pilot may go down into the base (H).
func _can_enter_base() -> bool:
	var pad := _ship_pad()
	return _can_leave_ship_now() and not pad.is_empty() and pad.number <= 6

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

# The outpost whose hatch the pilot on foot stands by, or "".
const HATCH_REACH := 3.0

func _near_hatch() -> String:
	var moon: Node3D = _void_cruiser.moon_node()
	if _walker == null or moon == null:
		return ""
	for site: String in MoonSites.SITES:
		if _walker.global_position.distance_to((moon.hatch_transform(site) as Transform3D).origin) <= HATCH_REACH:
			return site
	return ""

# In through the hatch: the outside world off the tree (the pilot on foot
# kept where they stood), inside the airlock.
func enter_outpost(site: String) -> void:
	var parent := get_parent()
	_detached.clear()
	for child in parent.get_children():
		if child != self:
			_detached.append([child, child.get_index()])
	for entry in _detached:
		parent.remove_child(entry[0])
	_outpost_site = site
	_outpost = OutpostInteriorScript.new()
	_outpost.name = "OutpostInterior"
	_outpost.layout = TelescopeLayout if site == "telescope" else DepotLayout
	_outpost.build()
	var walker: CharacterBody3D = InteriorWalkerScript.new()
	walker.name = "BaseWalker"
	walker.flat = true
	walker.add_to_group(OutpostInteriorScript.PEOPLE_GROUP)
	_outpost.add_child(walker)
	parent.add_child(_outpost)
	var spawn: Transform3D = _outpost.spawn_transform()
	walker.place(spawn.origin, -spawn.basis.z)
	walker.camera().make_current()
	(walker.get_node("Hud") as CanvasLayer).set_title("OUTPOST")
	mode = Mode.IN_OUTPOST

# Out through the hatch: the outside back, on foot before the hatch.
func exit_outpost() -> void:
	var parent := get_parent()
	parent.remove_child(_outpost)
	_outpost.free()
	_outpost = null
	for entry in _detached:
		parent.add_child(entry[0])
		parent.move_child(entry[0], entry[1])
	_detached.clear()
	var hatch: Transform3D = _void_cruiser.moon_node().hatch_transform(_outpost_site)
	var out := hatch.basis.z.normalized()
	_walker.place(hatch.origin + out * 2.5, out)
	_walker.camera().make_current()
	_track(_walker)
	mode = Mode.ON_FOOT

# What K does in Selene where the pilot stands: up the lift, ride the
# Travel Tube (aboard, stopped), call it (before its door, the car away).
func _base_prompt(point: Vector3) -> String:
	var stop: String = _base.car_stop()
	var door: String = _base.near_tube_door(point)
	if _base.near_lift(point):
		return "K EAGLE"
	if _base.in_car(point) and stop != "":
		return "K CENTRO" if stop == "dock" else "K SBARCO"
	if door != "" and stop != "" and stop != door:
		return "K CHIAMA"
	return ""

# --- debug teleport (keys 1-9) ------------------------------------------

const TELEPORT_LEGEND := "1 DOCK  2 SEZIONE  3 PIAZZOLA  4 SELENE  5 HANGAR\n6 TELESCOPIO  7 AREA 2  8 AIRLOCK  9 ORBITA"
# Number 9: this high over Selene.
const TELEPORT_ORBIT := 5000.0

# A small legend of the teleport keys, top right under the target panel.
func _build_debug_legend() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugLegend"
	layer.layer = 90
	add_child(layer)
	var label := Label.new()
	label.name = "Label"
	label.text = TELEPORT_LEGEND
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 0.7))
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.offset_right = -26.0
	label.offset_top = 92.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)

# Debug: to place `number` (TELEPORT_LEGEND) from wherever the pilot is,
# behind the fade. Ignored in a crash or a fade.
func teleport(number: int) -> void:
	if _crashed or _transitioning:
		return
	_teleport_flow(number)

func _teleport_flow(number: int) -> void:
	_transitioning = true
	var tween := create_tween()
	tween.tween_property(_curtain, "color:a", 1.0, FADE_TIME)
	await tween.finished
	back_aboard()
	match number:
		1:
			_place_by_port(0)
			_void_cruiser.in_moon_frame = false
			_void_cruiser.is_landed = false
			_track(_void_cruiser)
		2:
			enter_interior(0)
		3:
			enter_interior(0)
			var cruiser := _interior.get_node("InternalCruiser") as Node3D
			var pad: Dictionary = {}
			for i in range(600):
				pad = _interior.nearest_pad(cruiser.position)
				if not pad.is_empty():
					break
				await get_tree().physics_frame
			if not pad.is_empty():
				var top: Transform3D = pad.transform
				cruiser.transform = Transform3D(top.basis, top.origin + top.basis.y.normalized() * (cruiser.HULL_SIZE.y * 0.5))
				cruiser.velocity = Vector3.ZERO
				await get_tree().physics_frame
				walk_from_cruiser()
		4, 6, 7:
			_land_teleport({4: 1, 6: 7, 7: 8}[number])
		5:
			_land_teleport(1)
			enter_base()
		8:
			_land_teleport(8)
			walk_from_ship()
			if _walker != null:
				var hatch: Transform3D = _void_cruiser.moon_node().hatch_transform("area2")
				var out := hatch.basis.z.normalized()
				_walker.place(hatch.origin + out * 2.0, -out)
		9:
			var moon: Node3D = _void_cruiser.moon_node()
			var base: Transform3D = moon.base_transform()
			var up := base.basis.y.normalized()
			_void_cruiser.global_transform = Transform3D(Basis.looking_at(base.basis.x.normalized(), up), base.origin + up * TELEPORT_ORBIT)
			_void_cruiser.velocity = Vector3.ZERO
			_void_cruiser.angular_velocity = Vector3.ZERO
			_void_cruiser.is_landed = false
			_void_cruiser.in_moon_frame = true
			_track(_void_cruiser)
	tween = create_tween()
	tween.tween_property(_curtain, "color:a", 0.0, FADE_TIME)
	await tween.finished
	_transitioning = false

# The ship landed on the moon's pad `number`, the pilot aboard.
func _land_teleport(number: int) -> void:
	var pad: Transform3D = _void_cruiser.moon_node().pad_transform(number)
	_void_cruiser.land_at(Transform3D(pad.basis, pad.origin + pad.basis.y.normalized() * _void_cruiser.HALF_HEIGHT))
	_track(_void_cruiser)

# Back aboard the void-cruiser from wherever the pilot is, by the ways out
# the game has (out of an outpost, Selene, a section; off foot or the rover).
func back_aboard() -> void:
	match mode:
		Mode.IN_OUTPOST:
			exit_outpost()
			board_ship_on_foot()
		Mode.IN_BASE:
			exit_base()
		Mode.ON_FOOT:
			board_ship_on_foot()
		Mode.ROVER:
			board_ship()
		Mode.ON_FOOT_INSIDE:
			board_cruiser()
			exit_interior()
		Mode.INTERIOR:
			exit_interior()
	_void_cruiser.park(false)
	var pilot_camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	if pilot_camera:
		pilot_camera.make_current()

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
	_bastiani = null
	_stand_ins.clear()
	_bastiani_spot = _interior.chain_node().to_local(cruiser.position) if bridge_index == 0 else Vector3.INF

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

# The talk's parts, always there: Ollama is only started at the first
# question.
func _build_talk() -> void:
	_ollama = OllamaClient.new()
	_ollama.name = "Ollama"
	add_child(_ollama)
	_terminal = NpcTerminal.new()
	_terminal.name = "NpcTerminal"
	add_child(_terminal)
	_talk = NpcTalk.new()
	_talk.name = "NpcTalk"
	_talk.client = _ollama
	_talk.terminal = _terminal
	_talk.ended.connect(_on_talk_ended)
	add_child(_talk)

func talking() -> bool:
	return _talk != null and _talk.talking()

# Who P would speak to: in Selene the crew member right ahead; in a
# section Bastiani or someone stood in for, else the passer-by ahead
# ({node, index, pose} of the walkers drawn by the shader). null if nobody.
func _talk_target():
	if mode == Mode.IN_BASE and _base != null:
		var walker := _base.get_node("BaseWalker") as Node3D
		return TownFolk.person_ahead(_base.get_node("Crew").get_children() if _base.has_node("Crew") else [], walker.global_transform)
	if mode == Mode.ON_FOOT_INSIDE and _interior != null:
		var walker := _interior.get_node_or_null("InteriorWalker") as Node3D
		if walker == null:
			return null
		var people := []
		if _bastiani != null:
			people.append(_bastiani)
		for entry in _stand_ins:
			people.append(entry.person)
		var person := TownFolk.person_ahead(people, walker.global_transform)
		if person != null:
			return person
		var found := TownFolk.nearest(_near_walker_nodes(walker.global_position), walker.global_transform, LoopTraffic.clock(), TownWalkers.CORNER, _home_at_night)
		return null if found.is_empty() else found
	return null

# The groups of animated town walkers whose bounds come within
# WALKER_SEARCH of `point`.
func _near_walker_nodes(point: Vector3) -> Array:
	var out := []
	var chain: Node3D = _interior.chain_node()
	if chain == null:
		return out
	for section in chain.get_children():
		for node in section.get_children():
			if node is MultiMeshInstance3D and String(node.name).begins_with(TownFolk.NEAR_PREFIX):
				var box: AABB = (node as MultiMeshInstance3D).global_transform * (node as MultiMeshInstance3D).custom_aabb
				if box.grow(WALKER_SEARCH).has_point(point):
					out.append(node)
	return out

# A walker the shader has sent home for the night (as LoopTraffic's shader).
func _home_at_night(pose: Transform3D, alpha: float) -> bool:
	var night := InteriorClock.night(_interior.hour_at(_interior.to_local(pose.origin)))
	return fposmod(alpha * 13.7, 1.0) < night * WALKERS_NIGHT_HIDE

# P: the pilot stops, the person stops and turns, the terminal opens.
func start_talk(target) -> void:
	var walker := (_base.get_node("BaseWalker") if mode == Mode.IN_BASE else _interior.get_node("InteriorWalker")) as Node3D
	var person: Node3D = target if target is Node3D else _stand_in(target, walker)
	walker.frozen = true
	person.listen_to(walker.global_position)
	_listener = person
	_talk.start(TownFolk.sheet_for(person))

# The passer-by `found` hidden, a real person in its place facing the pilot.
func _stand_in(found: Dictionary, walker: Node3D) -> Node3D:
	var node: MultiMeshInstance3D = found.node
	var pose: Transform3D = found.pose
	var person := TownFolk.stand_in(TownFolk.paint(node, found.index))
	var section: Node3D = node.get_parent()
	var who := TownFolk.identity(TownFolk.walker_id(node, found.index))
	var slot := String(section.name).get_slice("_", 1).to_int()
	who.place = "sezione %d" % posmod(docked_bridge + slot, maxi(1, _station.num_sections))
	person.set_meta("npc", "townsfolk")
	person.set_meta("npc_identity", who)
	section.add_child(person)
	var up := pose.basis.y.normalized()
	var toward := walker.global_position - pose.origin
	toward -= up * toward.dot(up)
	person.global_transform = Transform3D(Basis.looking_at(toward.normalized() if toward.length() > 1e-3 else pose.basis.z, up), pose.origin)
	TownFolk.hide(node, found.index, true)
	_stand_ins.append({"person": person, "node": node, "index": found.index})
	return person

func _on_talk_ended() -> void:
	var walker: Node = null
	if mode == Mode.IN_BASE and _base != null:
		walker = _base.get_node_or_null("BaseWalker")
	elif _interior != null:
		walker = _interior.get_node_or_null("InteriorWalker")
	if walker != null:
		walker.frozen = false
	# The crew go back to work; one stood in for stays put until left behind.
	if is_instance_valid(_listener) and not _stand_ins.any(func(e): return e.person == _listener):
		_listener.stop_listening()
	_listener = null

# Every frame: a talk ends if its place is gone; Bastiani placed once his
# pad is loaded; the passers-by left behind (or whose section went) back on
# their rounds.
func _tend_talk() -> void:
	if talking() and not (mode == Mode.IN_BASE or mode == Mode.ON_FOOT_INSIDE):
		_talk.end()
	if _interior == null:
		_stand_ins.clear()
		_bastiani = null
		return
	if _bastiani == null and _bastiani_spot != Vector3.INF:
		_place_bastiani()
	var walker := _interior.get_node_or_null("InteriorWalker") as Node3D
	var kept := []
	for entry in _stand_ins:
		var person: Node3D = entry.person
		var node: MultiMeshInstance3D = entry.node
		var gone := not is_instance_valid(node) or not is_instance_valid(person)
		var left := walker == null or (not gone and person.global_position.distance_to(walker.global_position) > STAND_IN_KEPT)
		if (gone or left) and person != _listener:
			if is_instance_valid(node):
				TownFolk.hide(node, entry.index, false)
			if is_instance_valid(person):
				person.queue_free()
		else:
			kept.append(entry)
	_stand_ins = kept

# Bastiani standing on the pad nearest bridge 0's dock, a few metres in
# from its edge, facing its middle.
func _place_bastiani() -> void:
	var chain: Node3D = _interior.chain_node()
	var pad: Dictionary = _interior.nearest_pad(_interior.to_local(chain.to_global(_bastiani_spot)))
	# Not yet the dock's own pad (its section still loading): wait.
	if pad.is_empty() or pad.distance > PAD_MARKER_RANGE:
		return
	var top: Transform3D = pad.transform
	var up := top.basis.y.normalized()
	var spot := top.origin + top.basis.x.normalized() * (LandingPads.SIZE * 0.5 - 3.0)
	var person := SeleneCrew.new_member("", BASTIANI_COAT)
	person.name = "Bastiani"
	person.set_meta("npc", "bastiani")
	chain.add_child(person)
	person.global_transform = Transform3D(Basis.looking_at((top.origin - spot).normalized(), up), _interior.to_global(spot))
	person.idle()
	_bastiani = person
