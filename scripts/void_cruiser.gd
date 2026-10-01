extends "res://scripts/flying_craft.gd"

const CockpitScript = preload("res://scripts/cockpit.gd")
const OrbitalFrame = preload("res://scripts/orbital_frame.gd")
const ApproachGuide = preload("res://scripts/approach_guide.gd")
const VelocityCross = preload("res://scripts/velocity_cross.gd")
const Attitude = preload("res://scripts/attitude.gd")
const DockingAssist = preload("res://scripts/docking_assist.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const LandingReadout = preload("res://scripts/landing_readout.gd")
const LandingGuide = preload("res://scripts/landing_guide.gd")
const LandingAssist = preload("res://scripts/landing_assist.gd")
const PortalRules = preload("res://scripts/portal_rules.gd")
const SubspaceTunnel = preload("res://scripts/subspace_tunnel.gd")

# The planet the ship orbits, and the ring's circular orbit around it. The
# ship flies in the frame turning with the ring (see orbital_frame.gd); the
# ring's axis is the planet node's Y axis.
@export var planet_path: NodePath = NodePath("../PlanetSystem/Planet")
@export var planet_gm: float = OrbitalFrame.MOON_GM
@export var ring_radius: float = 6949600.0
# The station whose nearest dock the approach guide points at.
@export var station_path: NodePath = NodePath("../PlanetSystem/TorusStation")
# The moon: its pull everywhere, and its frame near it (see moon_orbit.gd).
@export var moon_path: NodePath = NodePath("../PlanetSystem/Moon")
const APPROACH_COLOR := Color(0.3, 1.0, 0.4, 0.7)

# Out in the void the ramp goes on: 10x after 5 s, 100x after 10 s.
const VOID_THRUST_STEPS := [10.0, 100.0]
# C holds the current velocity: the thrusters cancel the orbital pulls. A
# new press of W/A/S/D, or C again, lets go; roll, mouse and up/down do not
# (up/down change the held velocity).
const CRUISE_RELEASE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right"]
# B brakes the ship to rest (relative to the station) and holds it there,
# cancelling the orbital pulls too.
# B again, or any thrust key, lets go. C and B turn each other off.
const BRAKE_RELEASE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right", "move_up", "move_down"]

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
# Landing on the moon (ground, pads, flat roofs): slower than these, and
# level (the ship's up within LANDING_TILT of the local vertical, the nose
# any way). Otherwise a crash.
const LANDING_VERTICAL_SPEED := LandingReadout.DESCENT_LIMIT
const LANDING_HORIZONTAL_SPEED := LandingReadout.DRIFT_LIMIT
const LANDING_TILT := LandingReadout.LEVEL_LIMIT * PI / 180.0
const HALF_HEIGHT := 3.75  # HULL_SIZE.y / 2
# Under this height (centre over the ground) the hull's corners are checked
# against the ground: more than the hull's half diagonal plus a fast tick.
const GROUND_CHECK_HEIGHT := 60.0
# Base Selene's HUD marker hides this close to the beacon.
const BEACON_HIDE_DISTANCE := 1000.0
# The wreck comes to rest this far above the planet's surface.
const PLANET_CLEARANCE := 10.0

var _strobe_time: float = 0.0
# The approach path's shape last frame, over a section's rim or not, and
# the bridge it led to (see ApproachGuide.over_rim).
var _guide_over_rim := false
var _guide_bridge := -1
var cruise_locked := false
var brake_engaged := false
# Crashed on the planet: the wreck stays put until GameMode restarts it.
signal crashed
var is_crashed := false
# The precision factor this tick (1 away from docks; see DockingAssist).
var thrust_scale := 1.0
# The planet as last read from the scene (see _sync_planet); without one,
# no orbital forces.
var has_planet := false
var planet_center := Vector3.ZERO
var planet_axis := Vector3.UP
var planet_radius := 1737400.0
# In the moon's frame (below MoonOrbit.ATTACH_ALTITUDE): carried with the
# moon every tick, `velocity` relative to it.
var in_moon_frame := false
var is_landed := false
var crashed_on_moon := false
# While levelling itself near the moon: the nose's heading to keep, in the
# moon's own axes (so it turns with the moon). Zero when not levelling.
var _level_heading := Vector3.ZERO
# Between the portals (PortalRules.TRANSIT_TIME): the ship holds still where
# it went in, out of reach, until it comes out of the other one.
signal transit_started
signal transit_finished
var in_transit := false
var _transit_left := 0.0
var _transit_to: Node3D
# The ship (at the crossing point) and its velocity, and the entry portal,
# as they were when it went in.
var _transit_ship := Transform3D()
var _transit_velocity := Vector3.ZERO
var _transit_entry := Transform3D()

func _init() -> void:
	forward_thrust_steps = PackedFloat64Array(VOID_THRUST_STEPS)

func _ready() -> void:
	build_collision_shape()
	build_proximity_sensors()
	build_navigation_lights()
	build_headlights()
	build_cockpit()
	build_approach_guide()
	build_subspace_tunnel()
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
		cockpit.set_brake(brake_engaged)
		cockpit.set_thrust_scale(thrust_scale)
		cockpit.update_velocity(VelocityCross.ship_components(_world_basis(), velocity), cruise_locked)
		cockpit.update_attitude(attitude_matrix())
		if is_inside_tree():
			cockpit.update_motion(velocity)
	var readout := _update_approach_guide()
	if cockpit:
		cockpit.update_approach(readout)
		cockpit.update_moon(moon_readout())
		cockpit.update_gate(gate_readout())
		var gate := nearest_portal()
		var gate_shown: bool = not gate.is_empty() and not in_transit and gate.distance > PortalRules.MARKER_HIDE and gate.distance < PortalRules.MARKER_RANGE
		cockpit.update_gate_marker(gate.get("centre", Vector3.ZERO), gate.get("distance", 0.0), gate_shown)
		var moon := moon_node()
		if moon != null and is_inside_tree():
			var beacon: Vector3 = moon.beacon_position()
			var distance := global_position.distance_to(beacon)
			var shown := distance > BEACON_HIDE_DISTANCE and not is_landed and not in_transit and MoonOrbit.marker_in_range(global_position - moon.centre())
			cockpit.update_beacon(beacon, distance, shown)
		else:
			cockpit.update_beacon(Vector3.ZERO, 0.0, false)

# The pad the landing guide points at: {number, pad (top-centre
# transform)}, within LandingGuide.GUIDE_RANGE of the base in the moon's
# frame; else empty.
func landing_target() -> Dictionary:
	var moon := moon_node()
	if not in_moon_frame or moon == null or global_position.distance_to(moon.base_transform().origin) > LandingGuide.GUIDE_RANGE:
		return {}
	var pads := []
	for number in range(1, 7):
		pads.append(moon.pad_transform(number))
	var index := LandingGuide.target_pad(global_position, pads)
	return {"number": index + 1, "pad": pads[index]}

# The height of the hull's bottom (as when level) over the ground, or over
# the target pad near the base, in the moon's frame; INF elsewhere.
func landing_altitude() -> float:
	var moon := moon_node()
	if not in_moon_frame or moon == null:
		return INF
	var height: float = moon.altitude(global_position)
	var target := landing_target()
	if not target.is_empty():
		# Over the pad its top counts; away from it the ground curves off
		# under the pad's plane (199 m at 10 km), so the lower of the two.
		height = minf(height, (global_position - (target.pad as Transform3D).origin).dot(moon.up_at(global_position)))
	return height - HALF_HEIGHT

# The moon panel's readout while in the moon's frame, else empty.
func moon_readout() -> Dictionary:
	var moon := moon_node()
	if not in_moon_frame or moon == null:
		return {}
	var up: Vector3 = moon.up_at(global_position)
	var vertical: float = velocity.dot(up)
	var drift: float = (velocity - up * vertical).length()
	var tilt: float = rad_to_deg(acos(clampf(_world_basis().y.normalized().dot(up), -1.0, 1.0)))
	var target := landing_target()
	var number: int = 0 if target.is_empty() else target.number
	return LandingReadout.readout(landing_altitude(), vertical, drift, tilt, number, is_landed)

func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event.is_echo():
		return
	if event.is_action_pressed("cruise"):
		cruise_locked = not cruise_locked
		brake_engaged = false
	elif event.is_action_pressed("brake"):
		brake_engaged = not brake_engaged
		cruise_locked = false
	else:
		for action in BRAKE_RELEASE_ACTIONS:
			if event.is_action_pressed(action):
				brake_engaged = false
				if action in CRUISE_RELEASE_ACTIONS:
					cruise_locked = false

# Pure inertia on motion (no drag); rotation keeps its drag so the mouse
# does not leave the ship spinning.
func _linear_damping_now() -> float:
	return 0.0

func _external_acceleration() -> Vector3:
	# Holding velocity or braking: the thrusters cancel the orbital pulls.
	if not has_planet or cruise_locked or brake_engaged or is_landed:
		return Vector3.ZERO
	var omega := ring_omega()
	var pull := Vector3.ZERO
	var moon := moon_node()
	if moon != null:
		pull = MoonOrbit.gravity(_world_position() - moon.centre())
		if in_moon_frame:
			omega = moon.frame_omega()
	return OrbitalFrame.frame_acceleration(_world_position() - planet_center, velocity, planet_gm, omega, planet_radius) + pull

# Near a dock the precision factor scales every thruster and stops the
# ramp. The brake stops the ship at up to BRAKE_MULTIPLIER times the base
# thrust, scaled too.
func _fly(delta: float) -> void:
	if is_crashed:
		# Nothing the pilot does meanwhile carries over to the restart.
		_mouse_delta = Vector2.ZERO
		_forward_hold_time = 0.0
		return
	var thrust_input := _read_thrust_input()
	if is_landed:
		# Only lifting off counts: the ship rests, carried with the moon.
		_level_heading = Vector3.ZERO
		if thrust_input.y <= 0.0:
			_mouse_delta = Vector2.ZERO
			_forward_hold_time = 0.0
			velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			return
		is_landed = false
	_update_forward_hold_time(thrust_input.z, delta)
	var dock := _nearest_dock()
	# Near a dock and low over the moon the thrust eases off; the lower
	# factor wins.
	var altitude := landing_altitude()
	thrust_scale = 1.0 if dock.is_empty() else DockingAssist.precision_factor(dock.distance)
	thrust_scale = minf(thrust_scale, LandingAssist.thrust_factor(altitude))
	thrust_input = DockingAssist.scaled_thrust(thrust_input, forward_thrust_multiplier(), thrust_scale)
	if brake_engaged:
		velocity = DockingAssist.brake_velocity(velocity, Vector3.ZERO, thrust_power * DockingAssist.BRAKE_MULTIPLIER * thrust_scale, delta)
	var torque := _read_torque_input(delta) * LandingAssist.torque_factor(altitude)
	_level_near_the_moon(altitude, torque)
	_apply_physics_step(delta, thrust_input, torque)

# Low over the moon with hands off the mouse and the roll keys, the ship
# turns itself level, keeping the heading its nose had when levelling began.
func _level_near_the_moon(altitude: float, torque: Vector3) -> void:
	var moon := moon_node()
	if moon == null or altitude >= LandingAssist.RANGE or not torque.is_zero_approx():
		_level_heading = Vector3.ZERO
		return
	var up: Vector3 = moon.up_at(global_position)
	var moon_axes: Basis = moon.global_transform.basis.orthonormalized()
	# A heading kept from somewhere else (no longer horizontal here) is stale.
	if _level_heading != Vector3.ZERO and absf((moon_axes * _level_heading).dot(up)) > 0.05:
		_level_heading = Vector3.ZERO
	if _level_heading == Vector3.ZERO:
		_level_heading = moon_axes.inverse() * LandingAssist.heading_of(_world_basis(), up)
	var heading: Vector3 = moon_axes * _level_heading
	heading = (heading - up * heading.dot(up)).normalized()
	angular_velocity = LandingAssist.level_rate(_world_basis(), up, heading)

# Any touch of the planet is a crash, no bounce: the move is swept against
# the planet's sphere (PLANET_CLEARANCE up) before it is made.
func _move(delta: float) -> void:
	if _enter_portal(delta):
		return
	var moon := moon_node()
	if in_moon_frame and moon != null:
		# The moon's ground (MoonTerrain): the hull's lowest corner against it.
		# Moving down or sinking deeper counts (lifting off starts on it; the
		# ship turning level can keep its lowest corner just where it was).
		var start := _world_position()
		var motion := velocity * delta
		if moon.altitude(start) < GROUND_CHECK_HEIGHT:
			var before := lowest_clearance(Transform3D(_world_basis(), start))
			var after := lowest_clearance(Transform3D(_world_basis(), start + motion))
			if after < 0.0 and (velocity.dot(moon.up_at(start)) < 0.0 or after < before - 0.001):
				var share := clampf(before / (before - after), 0.0, 1.0)
				var point: Vector3 = start + motion * share
				touch_down(point, moon.up_at(point), point)
				return
		# Base Selene: a level surface (a pad, a roof) is a touch-down, a wall
		# a bounce.
		var collision := move_and_collide(velocity * delta)
		if collision:
			if _hit_portal_frame(collision):
				return
			var normal := collision.get_normal()
			if normal.dot(moon.up_at(global_position)) >= cos(LANDING_TILT):
				touch_down(global_position, moon.up_at(global_position), global_position)
			else:
				velocity = VoidCruiserPhysics.compute_bounce_velocity(velocity, normal, collision_restitution)
		return
	if has_planet:
		var from := _world_position()
		var entry := VoidCruiserPhysics.sphere_entry(from, from + velocity * delta, planet_center, planet_radius + PLANET_CLEARANCE)
		if entry >= 0.0:
			_crash_at(from + velocity * delta * entry)
			return
	if not is_inside_tree():
		super(delta)
		return
	var hit := move_and_collide(velocity * delta)
	if hit and not _hit_portal_frame(hit):
		velocity = VoidCruiserPhysics.compute_bounce_velocity(velocity, hit.get_normal(), collision_restitution)

# The lowest of the hull's eight corners over the moon's ground, with the
# ship at `at` (world).
func lowest_clearance(at: Transform3D) -> float:
	var moon := moon_node()
	var lowest := INF
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				lowest = minf(lowest, moon.altitude(at * (Vector3(x, y, z) * HULL_SIZE)))
	return lowest

# How far below the ship's centre its hull reaches along `up` (half the
# box's extent along that direction).
func hull_reach(up: Vector3) -> float:
	var hull := _world_basis().orthonormalized()
	return absf(up.dot(hull.x)) * HULL_SIZE.x * 0.5 + absf(up.dot(hull.y)) * HULL_SIZE.y * 0.5 + absf(up.dot(hull.z)) * HULL_SIZE.z * 0.5

static func landing_ok(motion: Vector3, up: Vector3, ship_up: Vector3) -> bool:
	var along: float = motion.dot(up)
	var across: float = (motion - up * along).length()
	return -along < LANDING_VERTICAL_SPEED and across < LANDING_HORIZONTAL_SPEED and ship_up.normalized().dot(up) >= cos(LANDING_TILT)

# Touching level ground at `point` (local up `up`): landed if slow and level,
# otherwise a crash. On the moon's ground `rest` is where the ship's centre
# comes to rest.
func touch_down(point: Vector3, up: Vector3, rest: Vector3) -> void:
	if not landing_ok(velocity, up, _world_basis().y):
		crashed_on_moon = true
		_crash_at(point)
		return
	if is_inside_tree():
		global_position = rest
	else:
		position = rest
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	brake_engaged = false
	cruise_locked = false
	is_landed = true

# Put down, landed, at `where` (GameMode's restart on a pad).
func land_at(where: Transform3D) -> void:
	global_transform = where
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	brake_engaged = false
	cruise_locked = false
	is_landed = true
	in_moon_frame = true
	_level_heading = Vector3.ZERO

func _crash_at(where: Vector3) -> void:
	if is_inside_tree():
		global_position = where
	else:
		position = where
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	brake_engaged = false
	cruise_locked = false
	is_crashed = true
	crashed.emit()

# Flying again after a crash (GameMode has placed the ship).
func restart_after_crash() -> void:
	is_crashed = false
	in_transit = false
	_set_hull_solid(true)
	crashed_on_moon = false
	is_landed = false
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_mouse_delta = Vector2.ZERO
	_forward_hold_time = 0.0

# The nearest dock within the guide's MAX_RANGE: station, bridge index,
# port and straight distance to the pad. Empty off the tree, with no
# station, or past that range.
func _nearest_dock() -> Dictionary:
	if not is_inside_tree():
		return {}
	var station := get_node_or_null(station_path) as Node3D
	if station == null or not station.is_inside_tree():
		return {}
	var index: int = station.nearest_bridge_index(global_position)
	var port: Node3D = station.get_docking_port(index)
	var distance := global_position.distance_to(port.global_position)
	if distance > ApproachGuide.MAX_RANGE:
		return {}
	return {"station": station, "index": index, "port": port, "distance": distance}

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

# Square gates on the path to the nearest dock (see approach_guide.gd). Not
# moved by the ship (top_level): _update_approach_guide places and redraws
# them every frame.
# The tunnel round the ship during a transit, around the pilot's eye.
func build_subspace_tunnel() -> void:
	var tunnel: Node3D = SubspaceTunnel.new()
	tunnel.name = "SubspaceTunnel"
	tunnel.position = COCKPIT_POSITION
	add_child(tunnel)
	transit_started.connect(tunnel.start)
	transit_finished.connect(tunnel.stop)

func build_approach_guide() -> void:
	add_child(_line_mesh("ApproachGuide", APPROACH_COLOR))

func _line_mesh(node_name: String, color: Color) -> MeshInstance3D:
	var lines := MeshInstance3D.new()
	lines.name = node_name
	lines.top_level = true
	lines.mesh = ArrayMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	lines.material_override = material
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lines.visible = false
	return lines

# Shown between MIN_RANGE and MAX_RANGE (straight line) from the nearest
# dock. Returns the approach panel's readout (empty past MAX_RANGE).
func _update_approach_guide() -> Dictionary:
	var guide := get_node_or_null("ApproachGuide") as MeshInstance3D
	if guide == null:
		return {}
	# Near Base Selene the same lines guide down onto the nearest pad.
	var target := landing_target()
	if not target.is_empty():
		_show_lines(guide, LandingGuide.gate_segments(target.pad, global_position))
		return {}
	var gate_lines := PackedVector3Array()
	var readout := {}
	var dock := _nearest_dock()
	if dock.is_empty():
		_guide_bridge = -1
	else:
		if dock.index != _guide_bridge:
			_guide_over_rim = false
			_guide_bridge = dock.index
		var port: Node3D = dock.port
		var distance: float = dock.distance
		# The pad is still: motion relative to it is the ship's own.
		var motion: Vector3 = velocity
		var closing := motion.dot((port.global_position - global_position).normalized())
		var length := distance
		if distance >= ApproachGuide.MIN_RANGE:
			var up := global_transform.basis.y
			var path := _approach_path(dock.station, port)
			length = 0.0
			for i in range(1, path.size()):
				length += path[i - 1].distance_to(path[i])
			gate_lines = ApproachGuide.gates_along(path, up)
			var gates := ApproachGuide.gate_centres(path)
			if not gates.is_empty():
				var first: Vector3 = gates[0][0]
				closing = motion.dot(first.normalized())
		readout = DockingAssist.readout(length, motion.length(), closing, distance)
	if gate_lines.is_empty():
		_guide_over_rim = false
	_show_lines(guide, gate_lines)
	return readout

# Draws `segments` (relative to the ship) on `lines`, or hides it.
func _show_lines(lines: MeshInstance3D, segments: PackedVector3Array) -> void:
	lines.visible = not segments.is_empty()
	if segments.is_empty():
		return
	lines.global_transform = Transform3D(Basis(), global_position)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = segments
	var mesh := lines.mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

# The approach path to `port`, relative to the ship: worked out in the frame
# of the port's bridge (see approach_guide.gd), where the station near the
# dock is round about the axis. It leaves along the nose (-Z) and ends on the
# pad. Updates the shape carried to the next frame.
func _approach_path(station: Node3D, port: Node3D) -> PackedVector3Array:
	var bridge_frame: Transform3D = (port.get_parent() as Node3D).global_transform
	var to_bridge := bridge_frame.affine_inverse()
	var ship: Vector3 = to_bridge * global_position
	var nose: Vector3 = (to_bridge.basis * -global_transform.basis.z).normalized()
	var half_gap: float = station.get_bridge_length() * 0.5
	var pad: Vector3 = port.transform.origin
	_guide_over_rim = ApproachGuide.over_rim(ship, nose, pad, station.section_radius, half_gap, _guide_over_rim)
	var local_path := ApproachGuide.approach_path(ship, nose, pad, station.section_radius, half_gap, station.get_bridge_radius(), _guide_over_rim)
	var path := PackedVector3Array()
	for point in local_path:
		path.append(bridge_frame * point - global_position)
	return path

func _world_basis() -> Basis:
	return global_transform.basis if is_inside_tree() else transform.basis

# The navball's matrix: the ship's attitude in the ring's frame (identity
# frame without a planet).
func attitude_matrix() -> Basis:
	var reference := Basis()
	if has_planet:
		reference = Attitude.ring_reference(_world_position(), planet_center, planet_axis)
	return Attitude.navball_matrix(_world_basis(), reference)

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
	if in_transit:
		_transit_tick(delta)
		return
	_follow_moon()
	_fly(delta)

# The nearest portal: {portal, centre (world), distance}; empty without one.
func nearest_portal() -> Dictionary:
	var best := {}
	for portal in portals():
		var centre: Vector3 = (portal.active_transform() as Transform3D).origin
		var distance := _world_position().distance_to(centre)
		if best.is_empty() or distance < best.distance:
			best = {"portal": portal, "centre": centre, "distance": distance}
	return best

# The gate panel's readout within PANEL_RANGE of a portal, else empty.
func gate_readout() -> Dictionary:
	var gate := nearest_portal()
	if in_transit or gate.is_empty() or gate.distance > PortalRules.PANEL_RANGE:
		return {}
	var front := PortalRules.in_front(_world_position(), gate.portal.active_transform())
	return PortalRules.readout(gate.portal.destination, gate.distance, velocity.length(), front)

# The portals the ship can enter (the "portals" group).
func portals() -> Array:
	if not is_inside_tree():
		return []
	return get_tree().get_nodes_in_group("portals")

# Through a portal's opening from its active side this move: slow enough,
# the transit starts; too fast, a crash where it crossed. True if either.
func _enter_portal(delta: float) -> bool:
	var from := _world_position()
	var to := from + velocity * delta
	for portal in portals():
		var entry: Transform3D = portal.active_transform()
		var t := PortalRules.crossing(from, to, entry)
		if t < 0.0:
			continue
		var point := from + (to - from) * t
		if not PortalRules.speed_ok(velocity.length()):
			crashed_on_moon = in_moon_frame
			_crash_at(point)
			return true
		var exit: Node3D = portal.other_portal()
		if exit == null:
			continue
		_transit_ship = Transform3D(_world_basis(), point)
		_transit_velocity = velocity
		_transit_entry = entry
		_transit_to = exit
		_transit_left = PortalRules.TRANSIT_TIME
		in_transit = true
		velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		cruise_locked = false
		brake_engaged = false
		_set_hull_solid(false)
		transit_started.emit()
		return true
	return false

func _transit_tick(delta: float) -> void:
	# Nothing the pilot does meanwhile carries over.
	_mouse_delta = Vector2.ZERO
	_forward_hold_time = 0.0
	_transit_left -= delta
	if _transit_left <= 0.0:
		_leave_transit()

# Out of the other portal: the same offset, attitude and velocity against
# it as against the entry, turned half round, EXIT_CLEARANCE out. Its own
# frame: the moon's for the moon portal (under ATTACH_ALTITUDE), else the
# ring's.
func _leave_transit() -> void:
	var exit: Transform3D = _transit_to.active_transform()
	var out := PortalRules.exit_transform(_transit_ship, _transit_entry, exit)
	out.origin += exit.basis.z.normalized() * PortalRules.EXIT_CLEARANCE
	global_transform = out
	velocity = PortalRules.exit_velocity(_transit_velocity, _transit_entry, exit)
	angular_velocity = Vector3.ZERO
	var moon := moon_node()
	in_moon_frame = moon != null and moon.altitude(out.origin) < MoonOrbit.ATTACH_ALTITUDE
	is_landed = false
	_level_heading = Vector3.ZERO
	in_transit = false
	_transit_to = null
	_set_hull_solid(true)
	transit_finished.emit()

func _set_hull_solid(solid: bool) -> void:
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", not solid)

# The portal frames are solid: touching one is a crash, wherever.
func _hit_portal_frame(collision: KinematicCollision3D) -> bool:
	var body := collision.get_collider() as Node
	if body == null or not body.is_in_group("portal_frames"):
		return false
	crashed_on_moon = in_moon_frame
	_crash_at(global_position)
	return true

func moon_node() -> Node3D:
	if not is_inside_tree():
		return null
	var moon := get_node_or_null(moon_path) as Node3D
	return moon if moon != null and moon.is_inside_tree() else null

# The ship joins the moon's frame below ATTACH_ALTITUDE and leaves it above
# DETACH_ALTITUDE, its velocity converted so the true motion does not jump;
# then, in the frame, it turns with the moon about the planet's axis by the
# moon's own last step. Frame first, turn second: the moon has already moved
# this tick, so a ship joining now is carried this tick, and one leaving now
# is not (its ring-frame velocity moves it instead). The moon's step, not an
# angle the ship remembers: ticks the ship missed never pile up into a jump.
func _follow_moon() -> void:
	var moon := moon_node()
	if moon == null:
		in_moon_frame = false
		return
	var distance: float = global_position.distance_to(moon.centre())
	var offset: Vector3 = global_position - moon.planet_centre()
	if not in_moon_frame and distance < MoonOrbit.RADIUS + MoonOrbit.ATTACH_ALTITUDE:
		velocity = MoonOrbit.to_moon_velocity(velocity, offset, moon.axis(), moon.relative_rate())
		in_moon_frame = true
	elif in_moon_frame and distance > MoonOrbit.RADIUS + MoonOrbit.DETACH_ALTITUDE:
		velocity = MoonOrbit.to_ring_velocity(velocity, offset, moon.axis(), moon.relative_rate())
		in_moon_frame = false
	if in_moon_frame:
		var turn: Transform3D = MoonOrbit.spin(moon.axis(), moon.last_step, moon.planet_centre())
		global_transform = turn * global_transform
		velocity = turn.basis * velocity

# The ship's velocity in the ring's frame, whichever frame it flies in.
func ring_velocity() -> Vector3:
	var moon := moon_node()
	if not in_moon_frame or moon == null:
		return velocity
	return MoonOrbit.to_ring_velocity(velocity, global_position - moon.planet_centre(), moon.axis(), moon.relative_rate())
