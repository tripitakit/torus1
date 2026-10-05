extends CharacterBody3D

# The pilot on foot inside a section (OnFoot does the walking): gravity
# toward the cylinder's wall (up is toward the axis, the interior's Z), real
# collisions with the ground, trees, buildings and landing pads
# (move_and_slide, a capsule riding up steps of a few centimetres). Lives
# in the interior world's coordinates, which only ever shift along Z.

const OnFoot = preload("res://scripts/on_foot.gd")
const GroundVehicle = preload("res://scripts/ground_vehicle.gd")
const WalkerHud = preload("res://scripts/walker_hud.gd")

const GRAVITY := 9.81
const CAMERA_FAR := 60000.0
const FLOOR_SNAP := 0.3

# When not empty, used instead of the keyboard (tests): {move, jog, jump}.
var controls := {}
# On a flat floor (Selene's interior): up is +Y everywhere.
var flat := false
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
	eye.far = CAMERA_FAR
	eye.current = true
	add_child(eye)
	var hud: CanvasLayer = WalkerHud.new()
	hud.name = "Hud"
	add_child(hud)
	floor_snap_length = FLOOR_SNAP
	floor_max_angle = deg_to_rad(45.0)

# Toward the axis from `point` (interior coordinates).
static func up_at(point: Vector3) -> Vector3:
	return -Vector3(point.x, point.y, 0.0).normalized()

func _up(point: Vector3) -> Vector3:
	return Vector3.UP if flat else up_at(point)

func camera() -> Camera3D:
	return get_node("Camera") as Camera3D

func speed() -> float:
	var up := _up(position)
	return (velocity - up * velocity.dot(up)).length()

# Feet at `point` (interior coordinates), facing `facing`; gravity settles
# them onto what is below.
func place(point: Vector3, facing: Vector3) -> void:
	transform = Transform3D(GroundVehicle.heading_basis(facing, _up(point)), point)
	velocity = Vector3.ZERO
	_carry = Vector3.ZERO

# Nothing in the way of the walker's capsule where it stands.
func is_clear() -> bool:
	var shape_node := get_node("CollisionShape3D") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func set_board_prompt(shown: bool) -> void:
	(get_node("Hud") as CanvasLayer).set_board_prompt(shown)

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
	# On the axis (not placed yet) there is no up.
	if not flat and Vector2(position.x, position.y).length() < 1.0:
		return
	var up := _up(position)
	var basis := GroundVehicle.heading_basis(-transform.basis.z, up).rotated(up, _turn)
	_turn = 0.0
	transform = Transform3D(basis, position)
	up_direction = up
	var c := read_controls()
	var rise := velocity.dot(up)
	var walk := _carry
	if is_on_floor():
		walk = OnFoot.walk_velocity(c.move, c.jog, basis)
		rise = 0.0
		if c.jump:
			rise = OnFoot.JUMP_INTERIOR
			_carry = walk
	else:
		rise -= GRAVITY * delta
	velocity = walk + up * rise
	move_and_slide()
