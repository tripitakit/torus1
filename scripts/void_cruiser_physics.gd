extends RefCounted

static func compute_new_velocity(velocity: Vector3, local_thrust_input: Vector3, orientation: Basis, thrust_power: float, linear_damping: float, delta: float) -> Vector3:
	var damping_factor := pow(1.0 - linear_damping, delta)
	var thrust_accel := orientation * (local_thrust_input * thrust_power)
	return velocity * damping_factor + thrust_accel * delta

static func compute_new_angular_velocity(angular_velocity: Vector3, local_torque_input: Vector3, torque_power: float, angular_damping: float, delta: float) -> Vector3:
	var damping_factor := pow(1.0 - angular_damping, delta)
	var torque_accel := local_torque_input * torque_power
	return angular_velocity * damping_factor + torque_accel * delta
