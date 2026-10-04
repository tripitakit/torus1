extends CharacterBody3D

# The pilot on foot on the moon (OnFoot does the walking). Lives in the
# moon's frame like the rover (moon_rover.gd): every tick it turns with the
# moon by the moon's last step, then walks, bumps into Base Selene and the
# vehicles, and keeps its feet on the moon's ground (MoonTerrain, as the
# patch draws it). Seen from the eyes only. A jump is a long lunar bound;
# the ground ahead rising steeper than OnFoot.MAX_CLIMB stops the walk.

const OnFoot = preload("res://scripts/on_foot.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const GroundVehicle = preload("res://scripts/ground_vehicle.gd")
const CockpitScript = preload("res://scripts/cockpit.gd")
const WalkerHud = preload("res://scripts/walker_hud.gd")

const MOON_GRAVITY := 1.62
# Further than this over the ground with no jump (an edge): falling.
const DROP_GAP := 0.5
# How far ahead the climb is read.
const CLIMB_PROBE := 0.5

@export var moon_path: NodePath = NodePath("../PlanetSystem/Moon")

# When not empty, used instead of the keyboard (tests): {move, jog, jump}.
var controls := {}
var airborne := false
# Along the local up while in the air; the walk kept from the take-off.
var vertical := 0.0
var _carry := Vector3.ZERO
var _turn := 0.0
var _pitch := 0.0

func _ready() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = OnFoot.RADIUS
	capsule.height = OnFoot.HEIGHT
	shape_node.shape = capsule
	shape_node.position = Vector3(0.0, OnFoot.HEIGHT * 0.5, 0.0)
	add_child(shape_node)
	var eye := Camera3D.new()
	eye.name = "Camera"
	eye.position = Vector3(0.0, OnFoot.EYE_HEIGHT, 0.0)
	eye.keep_aspect = Camera3D.KEEP_WIDTH
	eye.fov = 90.0
	eye.near = 0.05
	eye.far = CockpitScript.PILOT_FAR
	eye.current = true
	add_child(eye)
	var hud: CanvasLayer = WalkerHud.new()
	hud.name = "Hud"
	add_child(hud)

func _moon() -> Node3D:
	if not is_inside_tree():
		return null
	var moon := get_node_or_null(moon_path) as Node3D
	return moon if moon != null and moon.is_inside_tree() else null

func camera() -> Camera3D:
	return get_node("Camera") as Camera3D

func speed() -> float:
	return velocity.length()

# Standing on the ground under `point` (world), facing `facing`.
func place(point: Vector3, facing: Vector3) -> void:
	var moon := _moon()
	var up: Vector3 = moon.up_at(point)
	global_transform = Transform3D(GroundVehicle.heading_basis(facing, up), point - up * moon.ground_altitude(point))
	velocity = Vector3.ZERO
	airborne = false
	vertical = 0.0

func set_board_prompt(shown: bool) -> void:
	(get_node("Hud") as CanvasLayer).set_board_prompt(shown)

# Markers on the vehicles: [[name, Node3D], ...].
func set_targets(targets: Array) -> void:
	(get_node("Hud") as CanvasLayer).update_markers(camera(), targets)

func read_controls() -> Dictionary:
	if not controls.is_empty():
		return controls
	return {
		"move": Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_backward", "move_forward")),
		"jog": Input.is_action_pressed("jog"),
		"jump": Input.is_action_pressed("jump"),
	}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var look := OnFoot.look(Vector2(0.0, _pitch), event.relative)
		_turn += look.x
		_pitch = look.y

func _process(_delta: float) -> void:
	camera().rotation = Vector3(_pitch, 0.0, 0.0)
	(get_node("Hud") as CanvasLayer).show_speed(speed())

func _physics_process(delta: float) -> void:
	var moon := _moon()
	if moon == null:
		return
	global_transform = MoonOrbit.spin(moon.axis(), moon.last_step, moon.planet_centre()) * global_transform
	var start := global_position
	var up: Vector3 = moon.up_at(start)
	var basis := GroundVehicle.heading_basis(-global_transform.basis.z, up).rotated(up, _turn)
	_turn = 0.0
	global_transform = Transform3D(basis, start)
	var c := read_controls()
	var walk := Vector3.ZERO
	if airborne:
		walk = _carry
		vertical -= MOON_GRAVITY * delta
	else:
		walk = OnFoot.walk_velocity(c.move, c.jog, basis)
		if walk.length() > 0.0:
			var ahead: Vector3 = start + walk.normalized() * CLIMB_PROBE
			var rise: float = moon.ground_altitude(start) - moon.ground_altitude(ahead)
			if atan2(rise, CLIMB_PROBE) > OnFoot.MAX_CLIMB:
				walk = Vector3.ZERO
		if c.jump:
			airborne = true
			vertical = OnFoot.JUMP_MOON
			_carry = walk
	var hit := move_and_collide((walk + up * vertical) * delta)
	if hit != null:
		move_and_collide(hit.get_remainder().slide(hit.get_normal()))
		_carry = _carry.slide(hit.get_normal())
	var here := global_position
	var height: float = moon.ground_altitude(here)
	var here_up: Vector3 = moon.up_at(here)
	if airborne:
		if height <= 0.0 and vertical <= 0.0:
			airborne = false
			vertical = 0.0
	elif height > DROP_GAP:
		airborne = true
		vertical = 0.0
		_carry = walk
	if not airborne:
		here -= here_up * height
	global_transform = Transform3D(GroundVehicle.heading_basis(-basis.z, here_up), here)
	velocity = (global_position - start) / delta
	moon.follow_patch(global_position, true, velocity)
