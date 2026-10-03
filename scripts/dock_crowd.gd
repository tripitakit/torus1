extends RefCounted

# Life on a dock platform (60 x 60 m, its top at `top` in the dock's frame):
# people walking round square loops between PEOPLE_BAND, clear of the
# landing square (LANDING_HALF either way of the middle) where the craft
# sets down; service carts round the edge; cargo drones circling above the
# corners. LoopTraffic loops, FLAT; nothing collides (nothing may get in the
# way of a docking).

const LoopTraffic = preload("res://scripts/loop_traffic.gd")
const RoadTraffic = preload("res://scripts/road_traffic.gd")
const SpineTrain = preload("res://scripts/spine_train.gd")

const LANDING_HALF := 12.0
const PEOPLE := 24
const PEOPLE_BAND := Vector2(14.0, 25.0)
const PEOPLE_CORNER := 2.0
const WALK_SPEEDS := Vector2(1.2, 1.6)
const CARTS := 3
const CART_HALF := 28.5
const CART_CORNER := 5.0
const CART_SPEED := 5.0
const DRONES := 4
const DRONE_RADIUS := 8.0
const DRONE_CENTRE := 21.0
const DRONE_HEIGHTS := Vector2(12.0, 25.0)
const DRONE_SPEED := 3.0
# Overalls: white, orange, cyan, grey.
const SUITS := [Color(0.92, 0.93, 0.95), Color(1.0, 0.5, 0.12), Color(0.3, 0.85, 0.95), Color(0.55, 0.57, 0.6)]
const CART_PAINTS := [Color(1.0, 0.75, 0.15), Color(0.92, 0.93, 0.95)]
const DRONE_PAINTS := [Color(0.3, 0.32, 0.35), Color(0.92, 0.93, 0.95)]
# The crowd shows up to this far (it is small).
const VISIBLE_TO := 600.0

static func people(top: float, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "people"])
	var found := []
	for k in range(PEOPLE):
		var half := rng.randf_range(PEOPLE_BAND.x, PEOPLE_BAND.y)
		var loop := LoopTraffic.make_loop(LoopTraffic.FLAT, -half, -half, 2.0 * half, 2.0 * half, PEOPLE_CORNER, rng.randf_range(WALK_SPEEDS.x, WALK_SPEEDS.y), rng.randf(), top, seed * 100 + k)
		if rng.randf() < 0.5:
			loop.laps = -loop.laps
		found.append(loop)
	return found

static func carts(top: float) -> Array:
	var found := []
	for k in range(CARTS):
		found.append(LoopTraffic.make_loop(LoopTraffic.FLAT, -CART_HALF, -CART_HALF, 2.0 * CART_HALF, 2.0 * CART_HALF, CART_CORNER, CART_SPEED, float(k) / CARTS, top, k))
	return found

static func drones(top: float, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "drones"])
	var found := []
	for k in range(DRONES):
		var centre := Vector2(DRONE_CENTRE if k % 2 == 0 else -DRONE_CENTRE, DRONE_CENTRE if k < 2 else -DRONE_CENTRE)
		var height := rng.randf_range(DRONE_HEIGHTS.x, DRONE_HEIGHTS.y)
		var loop := LoopTraffic.make_loop(LoopTraffic.FLAT, centre.x - DRONE_RADIUS, centre.y - DRONE_RADIUS, 2.0 * DRONE_RADIUS, 2.0 * DRONE_RADIUS, DRONE_RADIUS, DRONE_SPEED, rng.randf(), top + height, seed * 10 + k)
		found.append(loop)
	return found

# A low-poly worker 1.8 m tall standing on y = 0, facing +Z: dark legs,
# overall-coloured body and helmet, a glowing visor.
static func person_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	SpineTrain._frustum(st, 0.17, 0.2, 0.0, 0.85, 1.0)
	SpineTrain._frustum(st, 0.24, 0.2, 0.85, 1.48, 0.0)
	RoadTraffic._box(st, Vector3(-0.12, 1.5, -0.13), Vector3(0.12, 1.78, 0.13), 0.0)
	RoadTraffic._box(st, Vector3(-0.1, 1.58, 0.13), Vector3(0.1, 1.68, 0.16), 2.0)
	st.index()
	return st.commit()

# A flat service cart about 3 m long: low body, glass cab at the front, an
# amber beacon on top, accent strip, white lights in front.
static func cart_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadTraffic._box(st, Vector3(-0.8, 0.2, -1.5), Vector3(0.8, 0.8, 1.5), 0.0)
	RoadTraffic._box(st, Vector3(-0.7, 0.8, 0.3), Vector3(0.7, 1.5, 1.3), 1.0)
	RoadTraffic._box(st, Vector3(-0.15, 1.5, 0.6), Vector3(0.15, 1.7, 0.9), 4.0)
	for side: float in [-1.0, 1.0]:
		RoadTraffic._box(st, Vector3(side * 0.82 - 0.03, 0.4, -1.4), Vector3(side * 0.82 + 0.03, 0.5, 1.4), 2.0)
		RoadTraffic._box(st, Vector3(side * 0.5 - 0.12, 0.45, 1.5), Vector3(side * 0.5 + 0.12, 0.6, 1.55), 3.0)
	st.index()
	return st.commit()

# A cargo drone about 3 m across: a body with a crate under it, four arms
# with a glowing rotor plate at each tip, an amber beacon on top.
static func drone_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadTraffic._box(st, Vector3(-0.5, -0.2, -0.6), Vector3(0.5, 0.25, 0.6), 0.0)
	RoadTraffic._box(st, Vector3(-0.4, -0.75, -0.45), Vector3(0.4, -0.2, 0.45), 1.0)
	RoadTraffic._box(st, Vector3(-0.1, 0.25, -0.1), Vector3(0.1, 0.4, 0.1), 4.0)
	for k in range(4):
		var a := TAU * (k + 0.5) / 4.0
		var tip := Vector3(cos(a), 0.0, sin(a)) * 1.3
		RoadTraffic._box(st, Vector3(minf(0.0, tip.x) - 0.06, 0.0, minf(0.0, tip.z) - 0.06), Vector3(maxf(0.0, tip.x) + 0.06, 0.1, maxf(0.0, tip.z) + 0.06), 0.0)
		RoadTraffic._box(st, tip + Vector3(-0.5, 0.1, -0.5), tip + Vector3(0.5, 0.16, 0.5), 2.0)
	st.index()
	return st.commit()
