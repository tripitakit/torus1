extends RefCounted

static func compute_new_velocity(velocity: Vector3, local_thrust_input: Vector3, orientation: Basis, thrust_power: float, linear_damping: float, delta: float) -> Vector3:
	var damping_factor := pow(1.0 - clamp(linear_damping, 0.0, 0.999), delta)
	var thrust_accel := orientation * (local_thrust_input * thrust_power)
	return velocity * damping_factor + thrust_accel * delta

static func compute_new_angular_velocity(angular_velocity: Vector3, local_torque_input: Vector3, torque_power: float, angular_damping: float, delta: float) -> Vector3:
	var damping_factor := pow(1.0 - clamp(angular_damping, 0.0, 0.999), delta)
	var torque_accel := local_torque_input * torque_power
	return angular_velocity * damping_factor + torque_accel * delta

static func compute_forward_thrust_multiplier(hold_time: float, ramp_duration: float, max_multiplier: float) -> float:
	if ramp_duration <= 0.0:
		return max_multiplier
	var t: float = clamp(hold_time / ramp_duration, 0.0, 1.0)
	return lerp(1.0, max_multiplier, t)

static func compute_bounce_velocity(velocity: Vector3, normal: Vector3, restitution: float) -> Vector3:
	return velocity.bounce(normal) * restitution

static func compute_strobe_energy(time: float, period: float, on_duration: float, energy: float) -> float:
	var phase: float = fmod(time, period)
	return energy if phase < on_duration else 0.0
