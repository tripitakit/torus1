extends RefCounted

# The little people and service machines of the interior (town walkers, the
# lakes' piers): low-poly shapes and their paints. UV.x parts as
# LoopTraffic's shader reads them.

const RoadTraffic = preload("res://scripts/road_traffic.gd")
const SpineTrain = preload("res://scripts/spine_train.gd")

# Overalls and clothes: white, orange, cyan, grey.
const SUITS := [Color(0.92, 0.93, 0.95), Color(1.0, 0.5, 0.12), Color(0.3, 0.85, 0.95), Color(0.55, 0.57, 0.6)]
const CART_PAINTS := [Color(1.0, 0.75, 0.15), Color(0.92, 0.93, 0.95)]
const DRONE_PAINTS := [Color(0.3, 0.32, 0.35), Color(0.92, 0.93, 0.95)]

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
