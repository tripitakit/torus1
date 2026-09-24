extends "res://scripts/flying_craft.gd"

# The small craft flown inside the station: same controls as the
# void-cruiser, a shorter thrust ramp (it stops at 10x, about 1 km/s), no HUD
# and no gravity.

const HULL_SIZE := Vector3(4.0, 2.0, 8.0)
const CAMERA_POSITION := Vector3(0.0, 0.3, -2.0)
const CAMERA_HFOV := 90.0
const CAMERA_NEAR := 0.2
const CAMERA_FAR := 60000.0
# With linear_damping 0.5 the top speed is thrust / ln 2: about 101 m/s at
# 1x, about 1 km/s at the end of the ramp (10x).
const INTERNAL_THRUST := 70.0

func _init() -> void:
	thrust_power = INTERNAL_THRUST

func _ready() -> void:
	build_collision_shape()
	build_camera()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func build_collision_shape() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = HULL_SIZE
	shape_node.shape = box
	add_child(shape_node)

func build_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = CAMERA_POSITION
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAMERA_HFOV
	camera.near = CAMERA_NEAR
	camera.far = CAMERA_FAR
	camera.current = true
	add_child(camera)

func _physics_process(delta: float) -> void:
	_fly(delta)
