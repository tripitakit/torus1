extends "res://scripts/flying_craft.gd"

const CockpitScript = preload("res://scripts/cockpit.gd")
const OrbitalFrame = preload("res://scripts/orbital_frame.gd")

# The planet the ship orbits, and the ring's circular orbit around it. The
# ship flies in the frame turning with the ring (see orbital_frame.gd); the
# ring's axis is the planet node's Y axis.
@export var planet_path: NodePath = NodePath("../PlanetSystem/Planet")
@export var planet_gm: float = OrbitalFrame.MOON_GM
@export var ring_radius: float = 6949600.0

# Out in the void the ramp goes on: 10x after 5 s, 100x after 10 s.
const VOID_THRUST_STEPS := [10.0, 100.0]
# C holds the current velocity: the thrusters cancel the orbital pulls. A
# new press of W/A/S/D, or C again, lets go; roll, mouse and up/down do not
# (up/down change the held velocity).
const CRUISE_RELEASE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right"]

const STROBE_PERIOD := 1.2
const STROBE_ON_DURATION := 0.1
const NAV_LIGHT_ENERGY := 3.0
const TAIL_LIGHT_ENERGY := 5.0
const HEADLIGHT_ENERGY := 18.0
const HEADLIGHT_RANGE := 8000.0
const HEADLIGHT_ANGLE := 45.0
const HEADLIGHT_ATTENUATION := 0.8
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
# The pilot's eye, inside the hull box, 7 m behind the bow face.
const COCKPIT_POSITION := Vector3(0.0, 0.5, -8.0)

var _strobe_time: float = 0.0
var cruise_locked := false
# The planet as last read from the scene (see _sync_planet); without one,
# no orbital forces.
var has_planet := false
var planet_center := Vector3.ZERO
var planet_axis := Vector3.UP
var planet_radius := 1737400.0

func _init() -> void:
	forward_thrust_steps = PackedFloat64Array(VOID_THRUST_STEPS)

func _ready() -> void:
	build_collision_shape()
	build_proximity_sensors()
	build_navigation_lights()
	build_headlights()
	build_cockpit()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta: float) -> void:
	_sync_planet()
	_strobe_time += delta
	var tail_light: OmniLight3D = get_node_or_null("TailLight")
	if tail_light:
		tail_light.light_energy = VoidCruiserPhysics.compute_strobe_energy(_strobe_time, STROBE_PERIOD, STROBE_ON_DURATION, TAIL_LIGHT_ENERGY)
	var cockpit := get_node_or_null("Cockpit")
	if cockpit:
		cockpit.update_hud(velocity.length(), read_proximity_distances())
		cockpit.set_cruise(cruise_locked)

func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_echo():
		return
	if event.is_action_pressed("cruise"):
		cruise_locked = not cruise_locked
	elif cruise_locked:
		for action in CRUISE_RELEASE_ACTIONS:
			if event.is_action_pressed(action):
				cruise_locked = false

# Pure inertia on motion (no drag); rotation keeps its drag so the mouse
# does not leave the ship spinning.
func _linear_damping_now() -> float:
	return 0.0

func _external_acceleration() -> Vector3:
	# Holding velocity: the thrusters cancel the orbital pulls.
	if not has_planet or cruise_locked:
		return Vector3.ZERO
	return OrbitalFrame.frame_acceleration(_world_position() - planet_center, velocity, planet_gm, ring_omega(), planet_radius)

func ring_omega() -> Vector3:
	return planet_axis * OrbitalFrame.orbit_angular_velocity(planet_gm, ring_radius)

# The origin shift moves the planet: read it again every tick and frame.
func _sync_planet() -> void:
	if not is_inside_tree():
		return
	var planet := get_node_or_null(planet_path) as Node3D
	if planet == null or not planet.is_inside_tree():
		return
	has_planet = true
	planet_center = planet.global_position
	planet_axis = planet.global_transform.basis.y.normalized()
	if "planet_radius" in planet:
		planet_radius = planet.planet_radius

func _world_position() -> Vector3:
	return global_position if is_inside_tree() else position

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

func build_cockpit() -> void:
	var cockpit: Node3D = CockpitScript.new()
	cockpit.name = "Cockpit"
	cockpit.position = COCKPIT_POSITION
	add_child(cockpit)
	cockpit.build()

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
	# The markers are for outside observers; keep them out of the on-board cameras.
	marker.layers = CockpitScript.SHIP_EXTERIOR_LAYER
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
	light.spot_attenuation = HEADLIGHT_ATTENUATION
	# Shadows off by design: at the station's kilometer scale, the spotlight
	# shadow map self-shadows the curved hull with flickering acne bands at
	# range, resolving cleanly only at very close distance.
	light.shadow_enabled = false
	add_child(light)

func _physics_process(delta: float) -> void:
	_sync_planet()
	_fly(delta)
