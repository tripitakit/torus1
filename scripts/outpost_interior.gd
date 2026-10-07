extends "res://scripts/alpha_interior.gd"

# A far-side outpost's building inside (TelescopeLayout, DepotLayout), on the
# Alpha-style builder: the airlock with its suit lockers and turning warning
# lights, the hatch to the surface (shut: K takes the pilot out), the room
# beyond with its window on the dish or the silo field. Nobody about.

const HATCH_REACH := 2.5

var _beacons: Array[Node3D] = []

func build() -> void:
	build_shell()
	_build_hatch(get_node("Rooms") as Node3D)

func _process(delta: float) -> void:
	for beacon in _beacons:
		beacon.rotate_y(delta * 4.0)

func spawn_transform() -> Transform3D:
	return layout.spawn()

func near_hatch(point: Vector3) -> bool:
	var hatch: Transform3D = layout.hatch()
	return layout.room_at(point) == "airlock" and Vector2(point.x - hatch.origin.x, point.z - hatch.origin.z).length() <= HATCH_REACH

# The hatch: a heavy panel with hazard bands, a red light and the way out
# written above; two turning amber lights either side.
func _build_hatch(parent: Node3D) -> void:
	var hatch: Transform3D = layout.hatch()
	var height := DOOR_HEIGHT
	var panel := Transform3D(hatch.basis, hatch.origin + Vector3(0.0, height * 0.5, 0.0))
	_box(parent, Vector3(1.8, height, 0.16), _mat(STEEL), panel)
	_collide(Vector3(1.8, height, 0.2), panel)
	for k in range(5):
		_box(parent, Vector3(1.8, 0.12, 0.18), _mat(HAZARD if k % 2 == 0 else DARK), Transform3D(hatch.basis, hatch.origin + Vector3(0.0, 0.3 + k * 0.12, 0.0)))
	_cylinder(parent, 0.25, 0.08, _mat(DARK), Transform3D(hatch.basis * Basis(Vector3.RIGHT, PI * 0.5), hatch.origin + Vector3(0.0, 1.3, -0.1)))
	_box(parent, Vector3(0.14, 0.14, 0.04), _mat(Color(1.0, 0.2, 0.15), 2.5), Transform3D(hatch.basis, hatch.origin + Vector3(0.6, 2.0, -0.1)))
	for side in [-1.0, 1.0]:
		var beacon := Node3D.new()
		beacon.position = hatch.origin + hatch.basis * Vector3(side * 1.4, 2.7, -0.2)
		parent.add_child(beacon)
		_sphere(beacon, 0.1, _mat(Color(1.0, 0.55, 0.1), 2.5), _at(0.0, 0.0, 0.0))
		_box(beacon, Vector3(0.26, 0.05, 0.04), _mat(Color(1.0, 0.7, 0.2), 3.0), _at(0.0, 0.0, 0.0))
		_beacons.append(beacon)
