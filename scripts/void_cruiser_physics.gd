extends RefCounted

static func compute_new_velocity(velocity: Vector3, local_thrust_input: Vector3, orientation: Basis, thrust_power: float, linear_damping: float, delta: float) -> Vector3:
	var damping_factor := pow(1.0 - clamp(linear_damping, 0.0, 0.999), delta)
	var thrust_accel := orientation * (local_thrust_input * thrust_power)
	return velocity * damping_factor + thrust_accel * delta

static func compute_new_angular_velocity(angular_velocity: Vector3, local_torque_input: Vector3, torque_power: float, angular_damping: float, delta: float) -> Vector3:
	var damping_factor := pow(1.0 - clamp(angular_damping, 0.0, 0.999), delta)
	var torque_accel := local_torque_input * torque_power
	return angular_velocity * damping_factor + torque_accel * delta

# Forward-thrust multiplier after holding the key `hold_time` seconds. Each
# entry of `steps` is reached `step_duration` seconds after the previous one,
# rising in a straight line from it (from 1x for the first); past the last
# step the multiplier stays there.
static func compute_forward_thrust_multiplier(hold_time: float, step_duration: float, steps: PackedFloat64Array) -> float:
	if steps.is_empty():
		return 1.0
	if step_duration <= 0.0:
		return steps[steps.size() - 1]
	var t: float = maxf(hold_time, 0.0) / step_duration
	var step: int = floori(t)
	if step >= steps.size():
		return steps[steps.size() - 1]
	var from: float = 1.0 if step == 0 else steps[step - 1]
	return lerpf(from, steps[step], t - step)

static func compute_bounce_velocity(velocity: Vector3, normal: Vector3, restitution: float) -> Vector3:
	return velocity.bounce(normal) * restitution

static func compute_strobe_energy(time: float, period: float, on_duration: float, energy: float) -> float:
	var phase: float = fmod(time, period)
	return energy if phase < on_duration else 0.0
