extends "res://scripts/alpha_interior.gd"

# Selene's interior, after Moonbase Alpha (Space: 1999, year one), on the
# Alpha-style builder (AlphaInterior) from SeleneLayout: the comm post at
# the crossing with its video screen, button console and direction signs;
# Main Mission with its window on the moon; the Commander's office up its
# steps; the hangar under the pad with its lift and beacons; the Travel
# Tube's tunnel and car; the crew. The outside world is detached while the
# pilot is in here.

const Alpha = preload("res://scripts/alpha_interior.gd")
# Selene's interior, after Moonbase Alpha (Space: 1999, year one), built in
# code from SeleneLayout: solid walls of beige panels on the 1.2 m grid, the
# corridors' curved light panels, dark skirting with a glowing strip,
# coffered ceilings with recessed lights, wall computer banks with their
# tape reels, plants; the comm post at the crossing with its video screen,
# button console and direction signs; sliding doors in dark chamfered
# frames that open for anyone near; Main Mission with its window on the
# moon, the Big Screen between computer banks, the window consoles, the
# curved desks with monitors and globe lamps, the Commander's office up its
# steps behind a sliding glass wall; the hangar under the pad and the Travel
# Tube. Its own light and environment: the outside world is detached while
# the pilot is in here.

const SeleneLayout = preload("res://scripts/selene_layout.gd")
const SeleneCrew = preload("res://scripts/selene_crew.gd")

const LIFT_SIZE := 6.0
const LIFT_REACH := 3.0
# Zero for tests that need no crew; SeleneCrew fills the base otherwise.
var crew_count := 12

var _beacons: Array[Node3D] = []

func _init() -> void:
	layout = SeleneLayout

func build() -> void:
	build_shell()
	var rooms := get_node("Rooms") as Node3D
	var furniture := get_node("Furniture") as Node3D
	_build_ramp(rooms)
	_build_post(furniture)
	_build_lift(rooms)
	_build_hangar(rooms)
	_build_tube()
	_build_crew()

func _process(delta: float) -> void:
	for beacon in _beacons:
		beacon.rotate_y(delta * 4.0)

# Where the pilot arrives: in the hangar beside the lift's platform, facing it.
func spawn_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), SeleneLayout.lift_centre() + Vector3(-4.4, 0.0, -2.4))

func near_lift(point: Vector3) -> bool:
	var half := LIFT_SIZE * 0.5
	var c := SeleneLayout.lift_centre()
	var d := Vector2(maxf(absf(point.x - c.x) - half, 0.0), maxf(absf(point.z - c.z) - half, 0.0))
	return SeleneLayout.room_at(point) == "dock" and d.length() <= LIFT_REACH

# The steps up to the office: a ramp to walk on, three steps drawn.
func _build_ramp(parent: Node3D) -> void:
	var r := SeleneLayout.office_ramp()
	var rise := SeleneLayout.OFFICE_FLOOR
	var run := r.size.x
	var slope := atan2(rise, run)
	var length := sqrt(run * run + rise * rise)
	var centre := r.get_center()
	_collide(Vector3(length, 0.1, r.size.y), Transform3D(Basis(Vector3.BACK, slope), Vector3(centre.x, rise * 0.5 - 0.05 / cos(slope), centre.y)))
	for i in range(3):
		var height := rise * (i + 1) / 3.0
		_box(parent, Vector3(run / 3.0, height, r.size.y), _mat(WHITE.darkened(0.1)), _at(r.position.x + run / 3.0 * (i + 0.5), height * 0.5, centre.y))
		_box(parent, Vector3(0.04, 0.02, r.size.y), _mat(STRIP, 1.5), _at(r.position.x + run / 3.0 * i + 0.03, height + 0.01, centre.y))

# The comm post: a white column; on two faces a video screen and below it a
# sloping console of lit buttons; on all four a sign with the way to each
# place (an arrow drawn before each name).
func _build_post(parent: Node3D) -> void:
	var post := Node3D.new()
	post.name = "CommPost"
	post.position = SeleneLayout.POST
	parent.add_child(post)
	var height := 2.8
	_cylinder(post, 0.32, height, _mat(WHITE), _at(0.0, height * 0.5, 0.0))
	_cylinder(post, 0.36, 0.12, _mat(ORANGE), _at(0.0, height - 0.3, 0.0))
	_cylinder(post, 0.4, 0.1, _mat(DARK), _at(0.0, 0.05, 0.0))
	_collide(Vector3(SeleneLayout.POST_SIZE * 0.7, height, SeleneLayout.POST_SIZE * 0.7), _at(SeleneLayout.POST.x, height * 0.5, SeleneLayout.POST.z))
	for face in [1.0, -1.0]:
		var turn := 0.0 if face > 0.0 else PI
		var out := Transform3D(Basis(Vector3.UP, turn), Vector3.ZERO)
		_box(post, Vector3(0.8, 0.62, 0.3), _mat(WHITE), out * _at(0.0, 1.62, 0.25))
		_monitor(post, out * _at(0.0, 1.62, 0.41), Vector2(0.62, 0.46), 2)
		_box(post, Vector3(0.72, 0.1, 0.36), _mat(WHITE), out * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 1.12, 0.36)))
		_quad(post, Vector2(0.64, 0.3), _blink, out * Transform3D(Basis(Vector3.RIGHT, -0.5 - PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 1.18, 0.38)))
	for sign_data in SeleneLayout.post_signs():
		var normal: Vector3 = sign_data.normal
		var basis := Basis.looking_at(-normal, Vector3.UP)
		var face := Transform3D(basis, normal * 0.44 + Vector3(0.0, 2.25, 0.0))
		_box(post, Vector3(0.66, 0.66, 0.03), _mat(WHITE), face)
		_box(post, Vector3(0.66, 0.05, 0.035), _mat(ORANGE), face * Transform3D(Basis(), Vector3(0.0, 0.33, 0.0)))
		var lines: Array = sign_data.lines
		for k in range(lines.size()):
			var y := 0.23 - k * 0.115
			var text := _label(lines[k][0], 0.052, Color(0.12, 0.12, 0.14))
			text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			text.transform = face * Transform3D(Basis(), Vector3(-0.2, y, 0.02))
			post.add_child(text)
			_arrow(post, face * Transform3D(Basis(), Vector3(-0.26, y, 0.02)), lines[k][1])

func _build_lift(parent: Node3D) -> void:
	var c := SeleneLayout.lift_centre()
	_box(parent, Vector3(LIFT_SIZE, 0.04, LIFT_SIZE), _mat(DARK), _at(c.x, 0.02, c.z))
	for side in range(4):
		var turn := side * PI * 0.5
		var edge := Basis(Vector3.UP, turn) * Vector3(0.0, 0.0, LIFT_SIZE * 0.5 - 0.15)
		_box(parent, Vector3(LIFT_SIZE, 0.05, 0.3), _mat(HAZARD, 0.4), _at(c.x + edge.x, 0.025, c.z + edge.z, turn))
		var corner := Basis(Vector3.UP, turn) * Vector3(LIFT_SIZE * 0.5 + 0.4, 0.0, LIFT_SIZE * 0.5 + 0.4)
		_cylinder(parent, 0.14, 0.3, _mat(DARK), _at(c.x + corner.x, 0.15, c.z + corner.z))
		var beacon := Node3D.new()
		beacon.position = Vector3(c.x + corner.x, 0.42, c.z + corner.z)
		parent.add_child(beacon)
		_sphere(beacon, 0.12, _mat(Color(1.0, 0.55, 0.1), 2.5), _at(0.0, 0.0, 0.0))
		_box(beacon, Vector3(0.3, 0.06, 0.04), _mat(Color(1.0, 0.7, 0.2), 3.0), _at(0.0, 0.0, 0.0))
		_beacons.append(beacon)
	# The shaft up to the pad: a dark square in the ceiling with a rim.
	_box(parent, Vector3(LIFT_SIZE, 0.06, LIFT_SIZE), _mat(Color(0.05, 0.05, 0.06)), _at(c.x, 7.96, c.z))
	for side in range(4):
		var turn := side * PI * 0.5
		var edge := Basis(Vector3.UP, turn) * Vector3(0.0, 0.0, LIFT_SIZE * 0.5)
		_box(parent, Vector3(LIFT_SIZE + 0.4, 0.4, 0.2), _mat(HAZARD), _at(c.x + edge.x, 7.8, c.z + edge.z, turn))

# The hangar: beams across the roof, pipes along the walls.
func _build_hangar(parent: Node3D) -> void:
	var r := SeleneLayout.room_rect("dock")
	for z in [-5.0, 5.0]:
		_box(parent, Vector3(r.size.x, 0.6, 0.5), _mat(STEEL), _at(r.get_center().x, 7.5, z))
	for x in [r.position.x + 1.0, r.end.x - 1.0]:
		_box(parent, Vector3(0.5, 0.6, r.size.y), _mat(STEEL), _at(x, 7.5, r.get_center().y))
	for k in range(3):
		var y := 5.5 + k * 0.35
		for x in [r.position.x + 0.25, r.end.x - 0.25]:
			_cylinder(parent, 0.1, r.size.y - 0.6, _mat(ORANGE if k == 1 else STEEL), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, r.get_center().y)))

# --- the Travel Tube ----------------------------------------------------

var _car: TubeCar

func tube_car() -> Node3D:
	return _car

# The stop the car stands at ("dock", "centre"), "" while it runs.
func car_stop() -> String:
	return _car.stop

func in_car(point: Vector3) -> bool:
	return _car.holds(point)

# Off to the other stop with whoever is aboard; false while it runs.
func start_ride() -> bool:
	if _car.stop == "":
		return false
	_car.run_to("centre" if _car.stop == "dock" else "dock")
	return true

# The car, empty, to `stop` (from in front of its door).
func call_car(stop: String) -> bool:
	if _car.stop == "" or _car.stop == stop:
		return false
	_car.run_to(stop)
	return true

# The stop whose Travel Tube door a point stands before, or "".
func near_tube_door(point: Vector3) -> String:
	for stop in ["dock", "centre"]:
		var door := (SeleneLayout.tube_stops()[stop] as Transform3D).origin + Vector3(0.0, 0.0, -1.8)
		var room := "dock" if stop == "dock" else "reception"
		if SeleneLayout.room_at(point) == room and Vector2(point.x - door.x, point.z - door.z).length() <= 2.5:
			return stop
	return ""

# The tunnel between the stations: floor, walls, roof, a rail, light rings
# every 6 m; and the car, at the hangar's stop.
func _build_tube() -> void:
	var r := SeleneLayout.room_rect("tunnel")
	var tube := Node3D.new()
	tube.name = "Tube"
	add_child(tube)
	var centre := r.get_center()
	var height := 3.6
	_box(tube, Vector3(r.size.x, 0.2, r.size.y + 0.4), _mat(FLOOR_GREY.darkened(0.3)), _at(centre.x, -0.1, centre.y))
	_collide(Vector3(r.size.x, 0.2, r.size.y), _at(centre.x, -0.1, centre.y))
	_box(tube, Vector3(r.size.x, 0.2, r.size.y + 0.4), _mat(STEEL.darkened(0.4)), _at(centre.x, height + 0.1, centre.y))
	for z in [r.position.y - 0.1, r.end.y + 0.1]:
		_box(tube, Vector3(r.size.x, height, 0.2), _mat(STEEL.darkened(0.3)), _at(centre.x, height * 0.5, z))
	for z in [centre.y - 0.8, centre.y + 0.8]:
		_box(tube, Vector3(r.size.x, 0.08, 0.1), _mat(STEEL), _at(centre.x, 0.04, z))
	var x := r.position.x + 3.0
	while x < r.end.x:
		for z in [r.position.y + 0.05, r.end.y - 0.05]:
			_box(tube, Vector3(0.25, height, 0.1), _mat(STRIP, 2.0), _at(x, height * 0.5, z))
		_box(tube, Vector3(0.25, 0.1, r.size.y), _mat(STRIP, 2.0), _at(x, height - 0.05, centre.y))
		x += 6.0
	_car = TubeCar.new()
	_car.name = "Car"
	add_child(_car)
	_car.setup(self)

# Main Mission's operators at their desks, the crew at work on their feet,
# the walkers on their rounds; all open the doors.
func _build_crew() -> void:
	if crew_count == 0:
		return
	var crew := Node3D.new()
	crew.name = "Crew"
	add_child(crew)
	var members := []
	for seat: Transform3D in SeleneLayout.crew_seats():
		var member := SeleneCrew.new_member("main_mission")
		member.transform = seat
		members.append(member)
		crew.add_child(member)
		member.sit()
	for worker in SeleneLayout.workers():
		var member := SeleneCrew.new_member(worker.department)
		member.transform = worker.transform
		crew.add_child(member)
		members.append(member)
		member.idle()
	var routes := SeleneLayout.routes()
	for k in range(routes.size()):
		var member := SeleneCrew.new_member(routes[k].department)
		crew.add_child(member)
		member.walk_route(routes[k].points, k)
		members.append(member)
	for k in range(members.size()):
		members[k].name = "Member_%02d" % k
		members[k].add_to_group(PEOPLE_GROUP)

# The Travel Tube's car: a kinematic box with benches, windows, a control
# panel with the line's map, a door on its -Z side that is shut while it
# runs. It runs along X from stop to stop (2 s up to speed, 2 s braking,
# ~10 s in all), carrying whoever is aboard.
class TubeCar extends AnimatableBody3D:
	const SIZE := Vector3(4.4, 2.8, 3.2)
	const DOOR_WIDTH := 1.8
	const RAMP := 2.0
	const TOP_SPEED := 25.0
	var stop := "dock"
	var _from := 0.0
	var _to := 0.0
	var _time := 0.0
	var _target := ""
	var _door := 0.0
	var _door_panel: Node3D
	var _door_shape: CollisionShape3D
	var _map: ShaderMaterial

	const MAP_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float progress = 0.0;
void fragment() {
	vec3 colour = vec3(0.04, 0.06, 0.1);
	float line = step(abs(UV.y - 0.5), 0.03) * step(0.08, UV.x) * step(UV.x, 0.92);
	colour = mix(colour, vec3(0.3, 0.6, 1.0), line);
	for (int i = 0; i < 2; i++) {
		float end = i == 0 ? 0.08 : 0.92;
		colour = mix(colour, vec3(1.0), step(length(vec2((UV.x - end) * 2.0, UV.y - 0.5)), 0.06));
	}
	float x = mix(0.08, 0.92, progress);
	float dot_on = step(length(vec2((UV.x - x) * 2.0, UV.y - 0.5)), 0.09) * step(0.5, fract(TIME * 2.0));
	ALBEDO = mix(colour, vec3(1.0, 0.6, 0.1), dot_on);
}
"""

	func setup(base) -> void:
		sync_to_physics = false
		transform = SeleneLayout.tube_stops().dock
		var white: Material = base._mat(Alpha.WHITE)
		var dark: Material = base._mat(Alpha.DARK)
		var half := SIZE * 0.5
		# Floor and roof.
		base._box(self, Vector3(SIZE.x, 0.1, SIZE.z), base._mat(Alpha.FLOOR_GREY), Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)))
		base._collide(Vector3(SIZE.x, 0.1, SIZE.z), Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), self)
		base._box(self, Vector3(SIZE.x, 0.1, SIZE.z), white, Transform3D(Basis(), Vector3(0.0, SIZE.y, 0.0)))
		base._box(self, Vector3(SIZE.x - 0.6, 0.02, 0.5), base._mat(Alpha.GLOW, 0.9), Transform3D(Basis(), Vector3(0.0, SIZE.y - 0.06, 0.0)))
		# The back (+Z) and the ends: low walls, windows, a band above.
		for wall in [[Vector3(0.0, 0.0, half.z), Vector3(SIZE.x, 0.0, 0.1)], [Vector3(half.x, 0.0, 0.0), Vector3(0.1, 0.0, SIZE.z)], [Vector3(-half.x, 0.0, 0.0), Vector3(0.1, 0.0, SIZE.z)]]:
			var at: Vector3 = wall[0]
			var size: Vector3 = wall[1]
			base._box(self, Vector3(maxf(size.x, 0.1), 1.0, maxf(size.z, 0.1)), white, Transform3D(Basis(), at + Vector3(0.0, 0.5, 0.0)))
			base._box(self, Vector3(maxf(size.x, 0.1), 1.0, maxf(size.z, 0.1)), base._glass(), Transform3D(Basis(), at + Vector3(0.0, 1.5, 0.0)))
			base._box(self, Vector3(maxf(size.x, 0.1), 0.8, maxf(size.z, 0.1)), white, Transform3D(Basis(), at + Vector3(0.0, 2.4, 0.0)))
			base._box(self, Vector3(maxf(size.x, 0.1) + 0.02, 0.06, maxf(size.z, 0.1) + 0.02), base._mat(Alpha.ORANGE), Transform3D(Basis(), at + Vector3(0.0, 1.0, 0.0)))
			base._collide(Vector3(maxf(size.x, 0.1), SIZE.y, maxf(size.z, 0.1)), Transform3D(Basis(), at + Vector3(0.0, SIZE.y * 0.5, 0.0)), self)
		# The front (-Z): wall either side of the door, the door.
		var side := (SIZE.x - DOOR_WIDTH) * 0.5
		for sx in [-1.0, 1.0]:
			var at := Vector3(sx * (DOOR_WIDTH * 0.5 + side * 0.5), SIZE.y * 0.5, -half.z)
			base._box(self, Vector3(side, SIZE.y, 0.1), white, Transform3D(Basis(), at))
			base._collide(Vector3(side, SIZE.y, 0.1), Transform3D(Basis(), at), self)
		_door_panel = Node3D.new()
		add_child(_door_panel)
		base._box(_door_panel, Vector3(DOOR_WIDTH, SIZE.y - 0.3, 0.06), white, Transform3D(Basis(), Vector3(0.0, (SIZE.y - 0.3) * 0.5, -half.z)))
		base._box(_door_panel, Vector3(DOOR_WIDTH, 0.1, 0.08), base._mat(Alpha.ORANGE), Transform3D(Basis(), Vector3(0.0, 1.0, -half.z)))
		_door_shape = base._collide(Vector3(DOOR_WIDTH, SIZE.y, 0.1), Transform3D(Basis(), Vector3(0.0, SIZE.y * 0.5, -half.z)), self)
		base._box(self, Vector3(DOOR_WIDTH, 0.3, 0.1), white, Transform3D(Basis(), Vector3(0.0, SIZE.y - 0.15, -half.z)))
		# Benches along the ends, the panel with the map by the door.
		for sx in [-1.0, 1.0]:
			base._box(self, Vector3(0.5, 0.45, SIZE.z - 0.6), base._mat(Alpha.ORANGE), Transform3D(Basis(), Vector3(sx * (half.x - 0.35), 0.25, 0.1)))
			base._box(self, Vector3(0.1, 0.5, SIZE.z - 0.6), white, Transform3D(Basis(), Vector3(sx * (half.x - 0.12), 0.7, 0.1)))
		var panel_at := Transform3D(Basis(), Vector3(-half.x + 1.0, 1.4, -half.z + 0.06))
		base._box(self, Vector3(0.9, 0.7, 0.06), dark, panel_at)
		_map = ShaderMaterial.new()
		_map.shader = Shader.new()
		_map.shader.code = MAP_SHADER
		base._quad(self, Vector2(0.8, 0.3), _map, panel_at * Transform3D(Basis(), Vector3(0.0, 0.15, 0.035)))
		base._quad(self, Vector2(0.8, 0.25), base._blink, panel_at * Transform3D(Basis(), Vector3(0.0, -0.17, 0.035)))
		var sign: Label3D = base._label("TRAVEL TUBE", 0.12, Color(0.12, 0.12, 0.14))
		sign.transform = Transform3D(Basis(), Vector3(0.0, SIZE.y - 0.15, -half.z - 0.06)) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		add_child(sign)

	func holds(point: Vector3) -> bool:
		var local := to_local(point)
		return absf(local.x) < SIZE.x * 0.5 and absf(local.z) < SIZE.z * 0.5 and local.y > -0.5 and local.y < SIZE.y

	func door_closed() -> bool:
		return not _door_shape.disabled

	func run_to(target: String) -> void:
		_target = target
		_from = position.x
		_to = (SeleneLayout.tube_stops()[target] as Transform3D).origin.x
		_time = 0.0
		stop = ""

	# Distance covered `t` seconds into a run of `length`.
	static func covered(t: float, length: float) -> float:
		var accel := TOP_SPEED / RAMP
		var ramp_distance := 0.5 * TOP_SPEED * RAMP
		var cruise := (length - 2.0 * ramp_distance) / TOP_SPEED
		if t < RAMP:
			return 0.5 * accel * t * t
		if t < RAMP + cruise:
			return ramp_distance + TOP_SPEED * (t - RAMP)
		var left := maxf(2.0 * RAMP + cruise - t, 0.0)
		return length - 0.5 * accel * left * left

	func _physics_process(delta: float) -> void:
		var wanted := 0.0
		if stop != "":
			for person in get_tree().get_nodes_in_group(Alpha.PEOPLE_GROUP):
				var p := to_local((person as Node3D).global_position)
				if absf(p.x) < DOOR_WIDTH and absf(p.z + SIZE.z * 0.5) < Alpha.DOOR_REACH:
					wanted = 1.0
		_door = move_toward(_door, wanted, delta / Alpha.DOOR_TIME)
		_door_panel.position.x = DOOR_WIDTH * _door
		_door_shape.disabled = stop != "" and _door > 0.3
		if stop != "":
			return
		# Shut first, then away.
		if _door > 0.0:
			return
		_time += delta
		var length := absf(_to - _from)
		var x := _from + signf(_to - _from) * covered(_time, length)
		var dx := x - position.x
		for person in get_tree().get_nodes_in_group(Alpha.PEOPLE_GROUP):
			if holds((person as Node3D).global_position):
				(person as Node3D).global_position.x += dx
		position.x = x
		_map.set_shader_parameter("progress", clampf(x / SeleneLayout.DOCK_X, 0.0, 1.0))
		if _time >= 2.0 * RAMP + (length - TOP_SPEED * RAMP) / TOP_SPEED:
			position.x = _to
			stop = _target

