extends CharacterBody3D

# The rover driven on the moon out of the landed void-cruiser
# (GroundVehicle does the driving, the moon is its ground). It lives in the
# moon's frame: every tick it turns with the moon by the moon's last step,
# as the ship does (void_cruiser.gd _follow_moon), then drives, bumps into
# Base Selene and the ship, and sits on the moon's ground (MoonTerrain, the
# same the patch draws round it). Seen from the driver's seat only.

const GroundVehicle = preload("res://scripts/ground_vehicle.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const RoverModel = preload("res://scripts/rover_model.gd")
const CockpitScript = preload("res://scripts/cockpit.gd")
const RoverHud = preload("res://scripts/rover_hud.gd")

const MOON_GRAVITY := 1.62
# A bump keeps half of what is left along the wall; head-on, nothing.
const BUMP_KEEP := 0.5
# The collision box, above the wheels so the ground's pebbles never stop it.
const BOX_SIZE := Vector3(1.8, 1.4, 3.1)
const BOX_CENTRE := Vector3(0.0, 1.1, 0.0)
const EYE := Vector3(0.0, 1.3, -0.95)
const CAMERA_HFOV := 90.0
const CAMERA_NEAR := 0.05
const HEADLIGHT_RANGE := 80.0
const HEADLIGHT_ENERGY := 4.0
const HEADLIGHT_ANGLE := 35.0
# Looking round with the mouse: so far each way, back ahead after a pause.
const LOOK_SENSITIVITY := 0.003
const LOOK_YAW := 2.0943951  # 120 degrees
const LOOK_PITCH := 1.0471976  # 60 degrees
const LOOK_IDLE := 1.5
const LOOK_RETURN_SPEED := 4.1887902  # 240 degrees/s: 120 degrees in 0.5 s

@export var moon_path: NodePath = NodePath("../PlanetSystem/Moon")

# Set by GameMode: the parked ship (null in tests).
var ship: Node3D
var body := {}
var lights_on := true
# When not empty, used instead of the keyboard (tests).
var controls := {}
var _look := Vector2.ZERO
var _look_idle := 0.0
var _wheel_roll := 0.0

func _ready() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = BOX_SIZE
	shape_node.shape = box
	shape_node.position = BOX_CENTRE
	add_child(shape_node)
	RoverModel.build(self)
	for side in [["HeadlightL", -0.6], ["HeadlightR", 0.6]]:
		var light := SpotLight3D.new()
		light.name = side[0]
		light.position = Vector3(side[1], 0.9, -1.6)
		light.spot_range = HEADLIGHT_RANGE
		light.spot_angle = HEADLIGHT_ANGLE
		light.light_energy = HEADLIGHT_ENERGY
		light.shadow_enabled = false
		add_child(light)
	var eye := Camera3D.new()
	eye.name = "Camera"
	eye.position = EYE
	eye.keep_aspect = Camera3D.KEEP_WIDTH
	eye.fov = CAMERA_HFOV
	eye.near = CAMERA_NEAR
	eye.far = CockpitScript.PILOT_FAR
	eye.current = true
	add_child(eye)
	if body.is_empty():
		body = GroundVehicle.new_body(global_transform)
	var hud: CanvasLayer = RoverHud.new()
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

# On the ground under `point` (world), the nose toward `nose`, leaned onto
# the ground at once, standing still.
func place(point: Vector3, nose: Vector3) -> void:
	var moon := _moon()
	var up: Vector3 = moon.up_at(point)
	var on_ground: Vector3 = point - up * moon.ground_altitude(point)
	body = GroundVehicle.new_body(Transform3D(GroundVehicle.heading_basis(nose, up), on_ground))
	body = GroundVehicle.settle(body, moon, 1.0)
	global_transform = body.transform
	velocity = Vector3.ZERO

# Nothing in the way of the rover's box where it stands.
func is_clear() -> bool:
	var shape_node := get_node("CollisionShape3D") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

# "V BOARD" at the top centre (GameMode decides when).
func set_board_prompt(shown: bool) -> void:
	(get_node("Hud") as CanvasLayer).set_board_prompt(shown)

func read_controls() -> Dictionary:
	if not controls.is_empty():
		return controls
	return {
		"throttle": Input.get_axis("move_backward", "move_forward"),
		"steer": Input.get_axis("move_left", "move_right"),
		"handbrake": Input.is_action_pressed("brake"),
	}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_look.x = clampf(_look.x - event.relative.x * LOOK_SENSITIVITY, -LOOK_YAW, LOOK_YAW)
		_look.y = clampf(_look.y - event.relative.y * LOOK_SENSITIVITY, -LOOK_PITCH, LOOK_PITCH)
		_look_idle = 0.0
	elif event.is_action_pressed("lights") and not event.is_echo():
		lights_on = not lights_on
		for light_name in ["HeadlightL", "HeadlightR"]:
			(get_node(light_name) as Light3D).visible = lights_on

# The look (yaw, pitch) after `idle` seconds without the mouse: held for
# LOOK_IDLE, then back ahead at LOOK_RETURN_SPEED.
static func look_after(look: Vector2, idle: float, delta: float) -> Vector2:
	if idle < LOOK_IDLE:
		return look
	return look.move_toward(Vector2.ZERO, LOOK_RETURN_SPEED * delta)

func _process(delta: float) -> void:
	_look_idle += delta
	_look = look_after(_look, _look_idle, delta)
	camera().rotation = Vector3(_look.y, _look.x, 0.0)
	if body.is_empty():
		return
	var speed_now: float = body.speed
	_wheel_roll -= speed_now * delta / RoverModel.WHEEL_RADIUS
	var angle := GroundVehicle.wheel_angle(speed_now, body.steer)
	for wheel in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var pivot := get_node(wheel) as Node3D
		if wheel.begins_with("WheelF"):
			pivot.rotation.y = angle
		(pivot.get_node("Spin") as Node3D).rotation.x = _wheel_roll
	var moon := _moon()
	if moon == null:
		return
	var up: Vector3 = moon.up_at(global_position)
	var basis := global_transform.basis.orthonormalized()
	var pole: Vector3 = moon.global_transform.basis.y.normalized()
	var slope := rad_to_deg(acos(clampf(basis.y.dot(up), -1.0, 1.0)))
	var altitude: float = moon.to_local(global_position).length() - MoonOrbit.RADIUS
	var hud := get_node("Hud") as CanvasLayer
	hud.show_readout(RoverHud.readout(body.speed, RoverHud.heading(-basis.z, up, pole), slope, altitude, lights_on))
	hud.update_markers(camera(), ship.global_position if is_instance_valid(ship) else null, moon.beacon_position())

func _physics_process(delta: float) -> void:
	var moon := _moon()
	if moon == null or body.is_empty():
		return
	# With the moon first, by its own last step (see void_cruiser.gd).
	global_transform = MoonOrbit.spin(moon.axis(), moon.last_step, moon.planet_centre()) * global_transform
	body.transform = global_transform
	body = GroundVehicle.drive(body, read_controls(), moon, MOON_GRAVITY, delta)
	global_transform = body.transform
	var start := global_position
	var hit := move_and_collide(body.motion)
	if hit != null:
		var normal := hit.get_normal()
		var nose := -global_transform.basis.z.normalized()
		body.speed *= BUMP_KEEP * (1.0 - absf(nose.dot(normal)))
		move_and_collide(hit.get_remainder().slide(normal) * BUMP_KEEP)
	body.transform = global_transform
	body = GroundVehicle.settle(body, moon, delta)
	global_transform = body.transform
	velocity = (global_position - start) / delta
	moon.follow_patch(global_position, true, velocity)
