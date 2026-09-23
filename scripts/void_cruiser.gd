extends Node3D

const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")
const SHIP_MODEL_PATH := "res://assets/models/void_cruiser.glb"

@export var thrust_power: float = 150.0
@export_range(0.0, 0.999, 0.001) var linear_damping: float = 0.5
@export var torque_power: float = 2.0
@export_range(0.0, 0.999, 0.001) var angular_damping: float = 0.5
@export var mouse_sensitivity: float = 0.01
@export var forward_thrust_ramp_multiplier: float = 10.0
@export var forward_thrust_ramp_duration: float = 5.0

var velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO

var _mouse_delta: Vector2 = Vector2.ZERO
var _forward_hold_time: float = 0.0
var _forward_hold_sign: float = 0.0

func _ready() -> void:
	build_ship_mesh()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func build_ship_mesh() -> void:
	var packed: PackedScene = load(SHIP_MODEL_PATH)
	var model := packed.instantiate()
	model.name = "ShipModel"
	# Blender's glTF exporter does not preserve "which way is forward": this
	# ship was modeled nose-toward -Y in Blender, and the export placed the
	# nose toward +Z in Godot instead of -Z (forward), so it faced the chase
	# camera instead of away from it. Corrective yaw, not a modeling error.
	model.rotation_degrees.y = 180.0
	add_child(model)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative

func _physics_process(delta: float) -> void:
	var thrust_input := _read_thrust_input()
	_update_forward_hold_time(thrust_input.z, delta)
	var multiplier := VoidCruiserPhysics.compute_forward_thrust_multiplier(_forward_hold_time, forward_thrust_ramp_duration, forward_thrust_ramp_multiplier)
	thrust_input.z *= multiplier
	_apply_physics_step(delta, thrust_input, _read_torque_input(delta))

func _read_thrust_input() -> Vector3:
	var strafe := Input.get_axis("move_left", "move_right")
	var vertical := Input.get_axis("move_down", "move_up")
	var forward := Input.get_axis("move_forward", "move_backward")
	return Vector3(strafe, vertical, forward)

func _update_forward_hold_time(forward_input: float, delta: float) -> void:
	# Holding W/S continuously ramps forward/backward thrust up to
	# forward_thrust_ramp_multiplier over forward_thrust_ramp_duration
	# seconds. Releasing the key, or reversing direction, starts the ramp
	# over from 1x on the very next press.
	var current_sign: float = sign(forward_input)
	if current_sign == 0.0 or current_sign != _forward_hold_sign:
		_forward_hold_time = 0.0
	else:
		_forward_hold_time += delta
	_forward_hold_sign = current_sign

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
