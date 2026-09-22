extends Node3D

const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")

@export var thrust_power: float = 50.0
@export_range(0.0, 0.999, 0.001) var linear_damping: float = 0.5
@export var torque_power: float = 2.0
@export_range(0.0, 0.999, 0.001) var angular_damping: float = 0.5
@export var mouse_sensitivity: float = 0.01

var velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO

var _mouse_delta: Vector2 = Vector2.ZERO

func _ready() -> void:
	build_ship_mesh()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func build_ship_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ShipMesh"
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.0, 4.0)
	mesh_instance.mesh = box
	add_child(mesh_instance)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative

func _physics_process(delta: float) -> void:
	_apply_physics_step(delta, _read_thrust_input(), _read_torque_input(delta))

func _read_thrust_input() -> Vector3:
	var strafe := Input.get_axis("move_left", "move_right")
	var vertical := Input.get_axis("move_down", "move_up")
	var forward := Input.get_axis("move_forward", "move_backward")
	return Vector3(strafe, vertical, forward)

func _read_torque_input(delta: float) -> Vector3:
	# Mouse motion is a one-off displacement, not a continuous rate, but it
	# feeds into compute_new_angular_velocity's `torque_input * delta`
	# integration alongside continuous keyboard input. Pre-dividing by delta
	# here cancels that later multiplication, so mouse-look sensitivity stays
	# constant regardless of the physics tick rate.
	var pitch := 0.0
	var yaw := 0.0
	if delta > 0.0:
		pitch = -_mouse_delta.y * mouse_sensitivity / delta
		yaw = -_mouse_delta.x * mouse_sensitivity / delta
	var roll := Input.get_axis("roll_left", "roll_right")
	_mouse_delta = Vector2.ZERO
	return Vector3(pitch, yaw, roll)

func _apply_physics_step(delta: float, local_thrust_input: Vector3, local_torque_input: Vector3) -> void:
	velocity = VoidCruiserPhysics.compute_new_velocity(velocity, local_thrust_input, transform.basis, thrust_power, linear_damping, delta)
	angular_velocity = VoidCruiserPhysics.compute_new_angular_velocity(angular_velocity, local_torque_input, torque_power, angular_damping, delta)

	position += velocity * delta
	rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * delta)
	rotate_object_local(Vector3.FORWARD, angular_velocity.z * delta)
