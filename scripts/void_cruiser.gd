extends CharacterBody3D

const VoidCruiserPhysics = preload("res://scripts/void_cruiser_physics.gd")
const SHIP_MODEL_PATH := "res://assets/models/void_cruiser.glb"

@export var thrust_power: float = 150.0
@export_range(0.0, 0.999, 0.001) var linear_damping: float = 0.5
@export var torque_power: float = 2.0
@export_range(0.0, 0.999, 0.001) var angular_damping: float = 0.5
@export var mouse_sensitivity: float = 0.01
@export var forward_thrust_ramp_multiplier: float = 10.0
@export var forward_thrust_ramp_duration: float = 5.0
@export_range(0.0, 1.0, 0.01) var collision_restitution: float = 0.4

const STROBE_PERIOD := 1.2
const STROBE_ON_DURATION := 0.1
const NAV_LIGHT_ENERGY := 3.0
const TAIL_LIGHT_ENERGY := 5.0
const HEADLIGHT_ENERGY := 12.0
const HEADLIGHT_RANGE := 400.0
const HEADLIGHT_ANGLE := 25.0
const HULL_SIZE := Vector3(15.0, 7.5, 30.0)
const SENSOR_RANGE := 20000.0
const SENSOR_DIRECTIONS := {
	"bow": Vector3(0.0, 0.0, -1.0),
	"stern": Vector3(0.0, 0.0, 1.0),
	"port": Vector3(-1.0, 0.0, 0.0),
	"starboard": Vector3(1.0, 0.0, 0.0),
	"dorsal": Vector3(0.0, 1.0, 0.0),
	"ventral": Vector3(0.0, -1.0, 0.0),
}

var angular_velocity: Vector3 = Vector3.ZERO

var _mouse_delta: Vector2 = Vector2.ZERO
var _forward_hold_time: float = 0.0
var _forward_hold_sign: float = 0.0
var _strobe_time: float = 0.0

func _ready() -> void:
	build_ship_mesh()
	build_collision_shape()
	build_proximity_sensors()
	build_navigation_lights()
	build_headlights()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta: float) -> void:
	_strobe_time += delta
	var tail_light: OmniLight3D = get_node_or_null("TailLight")
	if tail_light:
		tail_light.light_energy = VoidCruiserPhysics.compute_strobe_energy(_strobe_time, STROBE_PERIOD, STROBE_ON_DURATION, TAIL_LIGHT_ENERGY)

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

func build_collision_shape() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = HULL_SIZE
	shape_node.shape = box
	add_child(shape_node)

func build_proximity_sensors() -> void:
	# One ray per hull face, starting on the face itself, so the reading is
	# the gap between the hull and the surface, not the ship's center.
	# exclude_parent (on by default) keeps the rays from hitting the ship.
	for key in SENSOR_DIRECTIONS:
		var direction: Vector3 = SENSOR_DIRECTIONS[key]
		var ray := RayCast3D.new()
		ray.name = "Sensor" + String(key).capitalize()
		ray.position = direction * HULL_SIZE * 0.5
		ray.target_position = direction * SENSOR_RANGE
		add_child(ray)

func read_proximity_distances() -> Dictionary:
	var distances := {}
	for key in SENSOR_DIRECTIONS:
		var ray: RayCast3D = get_node("Sensor" + String(key).capitalize())
		if ray.is_colliding():
			distances[key] = ray.global_position.distance_to(ray.get_collision_point())
		else:
			distances[key] = -1.0
	return distances

func build_navigation_lights() -> void:
	# Aircraft convention: red = port (left), green = starboard (right),
	# white = tail. The tail light strobes; position/color are steady.
	_add_nav_light("PortLight", Color.RED, Vector3(-7.5, 0.0, 0.0), NAV_LIGHT_ENERGY)
	_add_nav_light("StarboardLight", Color.GREEN, Vector3(7.5, 0.0, 0.0), NAV_LIGHT_ENERGY)
	_add_nav_light("TailLight", Color.WHITE, Vector3(0.0, 0.0, 15.0), TAIL_LIGHT_ENERGY)

func _add_nav_light(light_name: String, color: Color, local_position: Vector3, energy: float) -> void:
	var light := OmniLight3D.new()
	light.name = light_name
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 50.0
	light.position = local_position
	add_child(light)

	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	marker.mesh = sphere
	var marker_material := StandardMaterial3D.new()
	marker_material.emission_enabled = true
	marker_material.emission = color
	marker_material.emission_energy_multiplier = 4.0
	marker.material_override = marker_material
	light.add_child(marker)

func build_headlights() -> void:
	# Nose = -Z. Two powerful, deep-reaching spotlights, one per side.
	_add_headlight("HeadlightLeft", Vector3(-4.0, -1.0, -15.0))
	_add_headlight("HeadlightRight", Vector3(4.0, -1.0, -15.0))

func _add_headlight(light_name: String, local_position: Vector3) -> void:
	var light := SpotLight3D.new()
	light.name = light_name
	light.position = local_position
	# SpotLight3D shines toward its own local -Z, which already matches the
	# ship's forward (-Z) as a direct child — no corrective rotation needed.
	light.light_color = Color.WHITE
	light.light_energy = HEADLIGHT_ENERGY
	light.spot_range = HEADLIGHT_RANGE
	light.spot_angle = HEADLIGHT_ANGLE
	light.shadow_enabled = true
	add_child(light)

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
