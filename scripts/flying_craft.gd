extends CharacterBody3D

# Flight model shared by the player's craft: 6-DOF thrust and torque with
# damping, a forward-thrust ramp, mouse-look, and a bounce on collision.

const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")

@export var thrust_power: float = 150.0
@export_range(0.0, 0.999, 0.001) var linear_damping: float = 0.5
@export var torque_power: float = 2.0
@export_range(0.0, 0.999, 0.001) var angular_damping: float = 0.5
@export var mouse_sensitivity: float = 0.01 / 6.0
@export_range(0.0, 1.0, 0.01) var collision_restitution: float = 0.4
# Holding forward or back ramps the thrust through these multipliers, one
# every forward_thrust_step_duration seconds (see
# VoidCruiserPhysics.compute_forward_thrust_multiplier).
@export var forward_thrust_steps: PackedFloat64Array = PackedFloat64Array([10.0])
@export var forward_thrust_step_duration: float = 5.0

var angular_velocity: Vector3 = Vector3.ZERO

var _mouse_delta: Vector2 = Vector2.ZERO
var _forward_hold_time: float = 0.0
var _forward_hold_sign: float = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative

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

# One physics tick of player flight: input, ramped forward thrust, motion.
func _fly(delta: float) -> void:
	var thrust_input := _read_thrust_input()
	_update_forward_hold_time(thrust_input.z, delta)
	thrust_input.z *= forward_thrust_multiplier()
	_apply_physics_step(delta, thrust_input, _read_torque_input(delta))

func forward_thrust_multiplier() -> float:
	return VoidCruiserPhysics.compute_forward_thrust_multiplier(_forward_hold_time, forward_thrust_step_duration, forward_thrust_steps)

func _update_forward_hold_time(forward_input: float, delta: float) -> void:
	# Releasing the key, or reversing direction, starts the ramp over from 1x
	# on the very next press.
	var current_sign: float = sign(forward_input)
	if current_sign == 0.0 or current_sign != _forward_hold_sign:
		_forward_hold_time = 0.0
	else:
		_forward_hold_time += delta
	_forward_hold_sign = current_sign

# What this tick of flight uses; a craft can change them (see void_cruiser.gd).
func _linear_damping_now() -> float:
	return linear_damping

func _angular_damping_now() -> float:
	return angular_damping

# Pulls from outside the craft (gravity and the like), in world space.
func _external_acceleration() -> Vector3:
	return Vector3.ZERO

func _apply_physics_step(delta: float, local_thrust_input: Vector3, local_torque_input: Vector3) -> void:
	var outside := _external_acceleration()
	velocity = VoidCruiserPhysics.compute_new_velocity(velocity, local_thrust_input, transform.basis, thrust_power, _linear_damping_now(), delta) + outside * delta
	angular_velocity = VoidCruiserPhysics.compute_new_angular_velocity(angular_velocity, local_torque_input, torque_power, _angular_damping_now(), delta)

	_move(delta)

	rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * delta)
	rotate_object_local(Vector3.FORWARD, angular_velocity.z * delta)

func _move(delta: float) -> void:
	# move_and_collide needs a live physics space, which only exists once
	# this node is genuinely inside a processed scene tree frame. Off-tree
	# (every headless unit test in this project, which never adds the
	# cruiser to a tree) falls back to plain integration — see
	# docs/superpowers/specs/2026-09-23-station-collisions-design.md for the
	# empirical verification behind this.
	if not is_inside_tree():
		position += velocity * delta
		return
	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = VoidCruiserPhysics.compute_bounce_velocity(velocity, collision.get_normal(), collision_restitution)
