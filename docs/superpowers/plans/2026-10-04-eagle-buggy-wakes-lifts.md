# Eagle, Moon Buggy, Boat Wakes, Lift Cabins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un modello Eagle per il void-cruiser visto da fuori, un rover Moon Buggy, scie e onde di prua per le barche, cabine degli ascensori di vetro con persone dentro.

**Architecture:** Quattro task indipendenti, ognuno con mesh fatte a codice (`RoadTraffic._box/_loft/_face`, come gli altri modelli) e funzioni pure testabili. La scia è calcolata nello shader con lo stesso `loop_pose` che muove le barche, chiamato a `TIME - ritardo`; una copia in GDScript serve ai test.

**Tech Stack:** Godot 4.6.1 doppia precisione, renderer `gl_compatibility`, GDScript, test `extends SceneTree`.

**Spec:** `docs/superpowers/specs/2026-10-04-eagle-buggy-wakes-lifts-design.md`

## Global Constraints

- Godot: `~/Godot_v4.6.1-stable-double_linux.x86_64`; un test: `--headless --path . -s tests/<file>.gd`; fallito se
  `FAIL`, `SCRIPT ERROR` o `Parse Error`, passato con `ALL TESTS PASSED`.
- Solo i test nuovi o toccati. TDD: ogni test visto fallire prima del codice.
- Faccia davanti in senso orario (`gl_compatibility`); `RoadTraffic._box/_face` lo fanno già.
- Livello del modello esterno della nave: `CockpitScript.SHIP_EXTERIOR_LAYER` (4), già escluso dalla camera del
  pilota.
- Rover: restano `WheelFL/FR/RL/RR` (con figlio `Spin`), `HeadlightL/R`, `RoverModel.WHEEL_RADIUS` 0,4, occhio
  (0, 1,3, −0,2).
- Scia: bracci 6 s, fascia centrale 4 s, baffi di prua 1 s; alzata max(0,15, 0,0006 × distanza); niente oltre
  1,5 km.
- Cabine: `LIFT_SIZE` 6 × 8 × 6 m e `lift_height` invariati.
- Commit con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Scia con barca ferma al molo:** opacità 0 durante la sosta — `_test_stopped_boat_leaves_no_wake` (Task 3).
2. **Scia lontana sfarfallante:** alzata che cresce con la distanza — `_test_lift_grows_with_distance` (Task 3).
3. **Vista dalla cabina del rover coperta dal nuovo modello:** raggio davanti libero — `_test_view_ahead_is_clear`
   (Task 2).
4. **Nave posata che "galleggia" o affonda:** piedi a −3,75 — `_test_feet_touch_the_bottom` (Task 1).
5. **Persone fuori dalla cabina o una sull'altra:** `_test_lift_riders` (Task 4).

---

### Task 1: Il void-cruiser in stile Eagle

**Files:**
- Create: `scripts/ship_model.gd`, `tests/test_ship_model.gd`
- Modify: `scripts/void_cruiser.gd` (`_ready`, `_process`)

**Interfaces:**
- Produces: `ShipModel.mesh() -> ArrayMesh`, `ShipModel.material() -> ShaderMaterial`,
  `ShipModel.build(parent: Node3D) -> MeshInstance3D` (nome `Model`, livello 4),
  `ShipModel.engines_on(thrust: Vector3, landed: bool) -> bool`,
  `ShipModel.set_engines(model: MeshInstance3D, on: bool)`, costante `FOOT_Y := -3.75`.

- [ ] **Step 1: test** — `tests/test_ship_model.gd`:

```gdscript
extends SceneTree

# The void-cruiser's outside model (an Eagle): inside the collision box,
# feet on its bottom, nose -Z, on the exterior layer the pilot never sees,
# engines glowing with thrust.

const ShipModel = preload("res://scripts/ship_model.gd")
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")
const CockpitScript = preload("res://scripts/cockpit.gd")

func _initialize():
	var failures := 0
	failures += _test_inside_the_collision_box()
	failures += _test_feet_touch_the_bottom()
	failures += _test_nose_ahead()
	failures += _test_engines_on_with_thrust()
	failures += await _test_on_the_exterior_layer()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_inside_the_collision_box() -> int:
	var box := ShipModel.mesh().get_aabb()
	var half := VoidCruiserScript.HULL_SIZE * 0.5 + Vector3.ONE * 0.05
	if box.position.x < -half.x or box.position.y < -half.y or box.position.z < -half.z or box.end.x > half.x or box.end.y > half.y or box.end.z > half.z:
		print("FAIL _test_inside_the_collision_box: %s" % box)
		return 1
	return 0

func _test_feet_touch_the_bottom() -> int:
	var low := ShipModel.mesh().get_aabb().position.y
	if absf(low - ShipModel.FOOT_Y) > 0.05:
		print("FAIL _test_feet_touch_the_bottom: lowest point %.2f m" % low)
		return 1
	return 0

func _test_nose_ahead() -> int:
	var box := ShipModel.mesh().get_aabb()
	if box.position.z > -13.0:
		print("FAIL _test_nose_ahead: foremost point z %.2f" % box.position.z)
		return 1
	return 0

func _test_engines_on_with_thrust() -> int:
	var pushing: bool = ShipModel.engines_on(Vector3(0.0, 0.0, -5.0), false)
	var idle: bool = ShipModel.engines_on(Vector3.ZERO, false)
	var landed: bool = ShipModel.engines_on(Vector3(0.0, 0.0, -5.0), true)
	var model: MeshInstance3D = ShipModel.build(Node3D.new())
	ShipModel.set_engines(model, true)
	var lit: float = (model.material_override as ShaderMaterial).get_shader_parameter("engines")
	if not pushing or idle or landed or lit != 1.0:
		print("FAIL _test_engines_on_with_thrust: pushing %s, idle %s, landed %s, parameter %s" % [pushing, idle, landed, lit])
		return 1
	return 0

func _test_on_the_exterior_layer() -> int:
	var ship: Node3D = VoidCruiserScript.new()
	root.add_child(ship)
	await process_frame
	var model := ship.get_node_or_null("Model") as MeshInstance3D
	var pilot := ship.get_node("Cockpit/PilotCamera") as Camera3D
	var result := 0
	if model == null or model.layers != CockpitScript.SHIP_EXTERIOR_LAYER or (pilot.cull_mask & model.layers) != 0:
		print("FAIL _test_on_the_exterior_layer: model %s" % model)
		result = 1
	ship.free()
	return result
```

- [ ] **Step 2:** lanciare; atteso errore di caricamento (`ship_model.gd` non c'è).

- [ ] **Step 3: codice** — `scripts/ship_model.gd`:

```gdscript
extends RefCounted

# The void-cruiser seen from outside: an Eagle transporter (Space: 1999), low
# poly, inside the collision box (VoidCruiser.HULL_SIZE, 15 x 7.5 x 30 m),
# nose -Z, its four feet on the box's bottom. On the ship-exterior layer:
# the pilot's camera never sees it. UV.x parts: 0 white hull, 1 dark
# (windows, doors, shock sleeves), 2 grey frame, 3 red-orange stripes,
# 4 engine glow (bright with thrust).

const RoadTraffic = preload("res://scripts/road_traffic.gd")
const CockpitScript = preload("res://scripts/cockpit.gd")

const FOOT_Y := -3.75
const SIDES := 8
# Thrust (m/s²) above which the engines glow.
const GLOW_THRUST := 0.05

const SHADER := """
shader_type spatial;
uniform float engines = 0.0;
varying float part;
void vertex() {
	part = UV.x;
}
void fragment() {
	vec3 colour = vec3(0.88, 0.88, 0.86);
	vec3 glow = vec3(0.0);
	float rough = 0.6;
	if (part > 0.5 && part < 1.5) {
		colour = vec3(0.06, 0.07, 0.08);
		rough = 0.2;
	} else if (part > 1.5 && part < 2.5) {
		colour = vec3(0.5, 0.52, 0.55);
	} else if (part > 2.5 && part < 3.5) {
		colour = vec3(0.85, 0.25, 0.08);
	} else if (part > 3.5) {
		colour = vec3(0.1);
		glow = vec3(1.0, 0.55, 0.2) * (0.15 + 3.0 * engines);
	}
	ALBEDO = colour;
	ROUGHNESS = rough;
	EMISSION = glow;
}
"""

static func mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Command module: an eight-sided nose cone on a short drum, a dark band
	# of windows round it.
	_cone_z(st, Vector2(0.0, 0.9), [[-14.9, 0.5], [-12.6, 1.9], [-10.0, 2.2], [-8.8, 2.0]], 0.0, true)
	_cone_z(st, Vector2(0.0, 0.9), [[-12.95, 1.78], [-12.25, 1.98]], 1.0, true)
	# Spine: two rails low and high each side, braces every 2.2 m.
	for side: float in [-1.0, 1.0]:
		_b(st, Vector3(side * 1.1, 0.5, -9.0), Vector3(side * 1.5, 0.9, 9.6), 2.0)
		_b(st, Vector3(side * 1.15, 1.9, -9.0), Vector3(side * 1.45, 2.2, 9.6), 2.0)
	for k in range(9):
		var z := -8.5 + k * 2.2
		_b(st, Vector3(-1.3, 0.5, z - 0.12), Vector3(1.3, 0.8, z + 0.12), 2.0)
		for side: float in [-1.0, 1.0]:
			_b(st, Vector3(side * 1.2, 0.9, z - 0.1), Vector3(side * 1.4, 1.9, z + 0.1), 2.0)
	# Passenger module under the spine: a red stripe and a door each side.
	_b(st, Vector3(-2.6, -1.9, -6.2), Vector3(2.6, 0.5, 6.2), 0.0)
	for side: float in [-1.0, 1.0]:
		_b(st, Vector3(side * 2.6, -0.55, -6.0), Vector3(side * 2.66, -0.25, 6.0), 3.0)
		_b(st, Vector3(side * 2.6, -1.5, -1.0), Vector3(side * 2.64, 0.1, 1.0), 1.0)
	# Side frames carrying the legs, arms out to them from the spine; each
	# leg a strut, a dark shock sleeve and a disc foot on the box's bottom.
	for side: float in [-1.0, 1.0]:
		_b(st, Vector3(side * 4.6, 0.4, -8.2), Vector3(side * 5.9, 1.1, 8.2), 0.0)
		_b(st, Vector3(side * 5.9, 0.6, -8.0), Vector3(side * 5.96, 0.9, 8.0), 3.0)
		for z: float in [-7.0, 7.0]:
			_b(st, Vector3(side * 1.5, 0.55, z - 0.25), Vector3(side * 4.6, 0.85, z + 0.25), 2.0)
			_b(st, Vector3(side * 5.25 - 0.22, -3.45, z - 0.22), Vector3(side * 5.25 + 0.22, 0.4, z + 0.22), 2.0)
			_b(st, Vector3(side * 5.25 - 0.32, -2.3, z - 0.32), Vector3(side * 5.25 + 0.32, -1.2, z + 0.32), 1.0)
			_cone_y(st, Vector3(side * 5.25, FOOT_Y, z), 0.9, 0.6, 0.3, 2.0)
	# Engines: a block behind the spine with a stripe, two tanks on top, four
	# nozzles, each with a glowing disc deep inside.
	_b(st, Vector3(-2.8, -0.9, 9.6), Vector3(2.8, 2.2, 12.6), 0.0)
	_b(st, Vector3(-2.84, 0.3, 9.6), Vector3(2.84, 0.6, 12.6), 3.0)
	for x: float in [-1.6, 1.6]:
		_cone_z(st, Vector2(x, 2.95), [[9.8, 0.3], [10.3, 0.75], [11.9, 0.75], [12.4, 0.3]], 0.0, true)
	for x: float in [-1.3, 1.3]:
		for y: float in [-0.1, 1.5]:
			_cone_z(st, Vector2(x, y), [[12.6, 0.45], [14.95, 0.85]], 2.0, false)
			_cone_z(st, Vector2(x, y), [[14.5, 0.0], [14.55, 0.78]], 4.0, true)
	st.index()
	return st.commit()

static func material() -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = SHADER
	return shader_material

# The model as `parent`'s child "Model", on the ship-exterior layer.
static func build(parent: Node3D) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = mesh()
	model.material_override = material()
	model.layers = CockpitScript.SHIP_EXTERIOR_LAYER
	parent.add_child(model)
	return model

static func engines_on(thrust: Vector3, landed: bool) -> bool:
	return not landed and thrust.length() > GLOW_THRUST

static func set_engines(model: MeshInstance3D, on: bool) -> void:
	(model.material_override as ShaderMaterial).set_shader_parameter("engines", 1.0 if on else 0.0)

# A box between any two opposite corners.
static func _b(st: SurfaceTool, a: Vector3, b: Vector3, part: float) -> void:
	RoadTraffic._box(st, a.min(b), a.max(b), part)

# Rings [z, radius] of SIDES corners round (centre.x, centre.y), joined by
# flat quads; `caps` closes both ends.
static func _cone_z(st: SurfaceTool, centre: Vector2, rings: Array, part: float, caps: bool) -> void:
	var points := []
	var middle := Vector3(centre.x, centre.y, 0.5 * (rings[0][0] + rings[-1][0]))
	for r in rings:
		var ring := []
		for i in range(SIDES):
			var angle := TAU * (i + 0.5) / SIDES
			ring.append(Vector3(centre.x + cos(angle) * r[1], centre.y + sin(angle) * r[1], r[0]))
		points.append(ring)
	for k in range(points.size() - 1):
		for i in range(SIDES):
			var j := (i + 1) % SIDES
			RoadTraffic._face(st, [points[k][i], points[k][j], points[k + 1][j], points[k + 1][i]], middle, part)
	if caps:
		RoadTraffic._face(st, points[0], middle, part)
		RoadTraffic._face(st, points[-1], middle, part)

# A short upright drum: radius r0 at `base`, r1 `height` above.
static func _cone_y(st: SurfaceTool, base: Vector3, r0: float, r1: float, height: float, part: float) -> void:
	var low := []
	var high := []
	for i in range(SIDES):
		var angle := TAU * (i + 0.5) / SIDES
		low.append(base + Vector3(cos(angle) * r0, 0.0, sin(angle) * r0))
		high.append(base + Vector3(cos(angle) * r1, height, sin(angle) * r1))
	var middle := base + Vector3(0.0, height * 0.5, 0.0)
	for i in range(SIDES):
		var j := (i + 1) % SIDES
		RoadTraffic._face(st, [low[i], low[j], high[j], high[i]], middle, part)
	RoadTraffic._face(st, low, middle, part)
	RoadTraffic._face(st, high, middle, part)
```

In `scripts/void_cruiser.gd`: `const ShipModel = preload("res://scripts/ship_model.gd")`; in `_ready()` dopo
`build_collision_shape()`: `ShipModel.build(self)`; in `_process()` dopo il blocco della luce di coda:

```gdscript
	var model := get_node_or_null("Model") as MeshInstance3D
	if model != null:
		ShipModel.set_engines(model, ShipModel.engines_on(accel_thrust, is_landed))
```

- [ ] **Step 4:** `test_ship_model.gd` → `ALL TESTS PASSED`; poi `test_cockpit_in_tree.gd` e `test_game_mode.gd`
  (la nave ha un figlio in più).
- [ ] **Step 5:** commit "Void-cruiser: an Eagle-style outside model, seen from the rover, never from the cockpit".

---

### Task 2: Il rover Moon Buggy

**Files:**
- Modify: `scripts/rover_model.gd` (tutto `build`)
- Create: `tests/test_rover_model.gd`

**Interfaces:**
- Consumes/Produces: `RoverModel.build(rover: Node3D)`, `RoverModel.WHEEL_RADIUS`; nodi `WheelFL/FR/RL/RR` con `Spin`,
  `Dome`, `DomeRing` (vetro, esclusi dal test della vista).

- [ ] **Step 1: test** — `tests/test_rover_model.gd`:

```gdscript
extends SceneTree

# The Moon Buggy's looks: the nodes the driving moves, its size, and a
# clear view ahead from the driver's eye.

const RoverModel = preload("res://scripts/rover_model.gd")
const EYE := Vector3(0.0, 1.3, -0.2)
# Glass the driver looks through.
const SEE_THROUGH := ["Dome", "DomeRing"]

func _initialize():
	var rover := Node3D.new()
	root.add_child(rover)
	RoverModel.build(rover)
	var failures := 0
	failures += _test_driving_nodes(rover)
	failures += _test_size(rover)
	failures += _test_view_ahead_is_clear(rover)
	failures += _test_buggy_parts(rover)
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _meshes(rover: Node3D) -> Array:
	return rover.find_children("*", "MeshInstance3D", true, false)

func _box(mesh: MeshInstance3D) -> AABB:
	return mesh.global_transform * mesh.get_aabb()

func _test_driving_nodes(rover: Node3D) -> int:
	for wheel in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		if rover.get_node_or_null(wheel + "/Spin") == null:
			print("FAIL _test_driving_nodes: no %s/Spin" % wheel)
			return 1
	return 0

func _test_size(rover: Node3D) -> int:
	var all := AABB()
	var first := true
	for mesh in _meshes(rover):
		all = _box(mesh) if first else all.merge(_box(mesh))
		first = false
	if all.position.x < -1.1 or all.end.x > 1.1 or all.position.y < -0.01 or all.end.y > 2.4 or all.position.z < -1.7 or all.end.z > 1.7:
		print("FAIL _test_size: %s" % all)
		return 1
	return 0

func _test_view_ahead_is_clear(rover: Node3D) -> int:
	for mesh in _meshes(rover):
		if String(mesh.name) in SEE_THROUGH:
			continue
		if _box(mesh).intersects_segment(EYE, EYE + Vector3(0.0, 0.0, -3.0)):
			print("FAIL _test_view_ahead_is_clear: %s in the way" % mesh.name)
			return 1
	return 0

func _test_buggy_parts(rover: Node3D) -> int:
	for part in ["Dome", "DomeRing", "Console", "SeatL", "SeatR", "FenderFL", "LampL", "LampR", "Cargo", "Antenna"]:
		if rover.get_node_or_null(part) == null:
			print("FAIL _test_buggy_parts: no %s" % part)
			return 1
	return 0
```

- [ ] **Step 2:** lanciare; atteso `FAIL _test_buggy_parts` (il modello di oggi non ha cupola né sedili).

- [ ] **Step 3: codice** — `scripts/rover_model.gd` riscritto:

```gdscript
extends RefCounted

# The rover's looks: a Moon Buggy (Space: 1999), low poly. A low white
# platform with a red-orange stripe each side and a raised nose, four big
# ribbed wheels under white fenders, two seats and a low console with
# status lights under a glass dome, two round lamps in the nose, a cargo
# box and a whip antenna behind. The origin is where the wheels touch the
# ground, -Z the nose; from the driver's eye (moon_rover.gd EYE) the front
# wheels and fenders show at the view's lower corners.

const WHEEL_RADIUS := 0.4
const WHEEL_WIDTH := 0.3
const WHITE := Color(0.9, 0.9, 0.88)
const STRIPE := Color(0.88, 0.3, 0.08)
const GREY := Color(0.45, 0.47, 0.5)
const TYRE := Color(0.07, 0.07, 0.07)
const SEAT := Color(0.2, 0.22, 0.25)

static func build(rover: Node3D) -> void:
	var white := _material(WHITE, 0.55, 0.1)
	var stripe := _material(STRIPE, 0.5, 0.1)
	var grey := _material(GREY, 0.5, 0.5)
	var tyre := _material(TYRE, 0.9, 0.0)
	var seat := _material(SEAT, 0.8, 0.0)
	# Platform, raised nose, stripes.
	_box(rover, "Platform", Vector3(1.5, 0.22, 2.9), Vector3(0.0, 0.66, 0.05), white)
	_box(rover, "Nose", Vector3(1.4, 0.3, 0.35), Vector3(0.0, 0.82, -1.5), white)
	_box(rover, "StripeL", Vector3(0.03, 0.08, 2.9), Vector3(-0.765, 0.68, 0.05), stripe)
	_box(rover, "StripeR", Vector3(0.03, 0.08, 2.9), Vector3(0.765, 0.68, 0.05), stripe)
	# Round lamps in the nose (the HeadlightL/R lights sit just ahead).
	for lamp in [["LampL", -0.5], ["LampR", 0.5]]:
		var disc := MeshInstance3D.new()
		disc.name = lamp[0]
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.13
		cylinder.bottom_radius = 0.13
		cylinder.height = 0.06
		disc.mesh = cylinder
		disc.material_override = _glow(Color(1.0, 0.95, 0.8))
		disc.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		disc.position = Vector3(lamp[1], 0.84, -1.69)
		rover.add_child(disc)
	# Seats and the console with its status lights.
	_box(rover, "SeatL", Vector3(0.5, 0.12, 0.5), Vector3(-0.35, 0.83, 0.1), seat)
	_box(rover, "SeatR", Vector3(0.5, 0.12, 0.5), Vector3(0.35, 0.83, 0.1), seat)
	_box(rover, "BackL", Vector3(0.5, 0.55, 0.1), Vector3(-0.35, 1.1, 0.38), seat)
	_box(rover, "BackR", Vector3(0.5, 0.55, 0.1), Vector3(0.35, 1.1, 0.38), seat)
	_box(rover, "Console", Vector3(0.7, 0.22, 0.25), Vector3(0.0, 0.88, -0.75), grey)
	for k in range(4):
		var colour := Color(0.3, 1.0, 0.4) if k % 2 == 0 else Color(1.0, 0.7, 0.2)
		_box(rover, "Status%d" % k, Vector3(0.06, 0.04, 0.02), Vector3(-0.21 + k * 0.14, 0.95, -0.62), _glow(colour))
	# The glass dome over the seats and its thin ring.
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	var sphere := SphereMesh.new()
	sphere.radius = 1.05
	sphere.height = 1.05
	sphere.is_hemisphere = true
	sphere.radial_segments = 24
	sphere.rings = 8
	dome.mesh = sphere
	dome.material_override = _glass()
	dome.position = Vector3(0.0, 0.95, -0.2)
	rover.add_child(dome)
	var ring := MeshInstance3D.new()
	ring.name = "DomeRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.02
	torus.outer_radius = 1.08
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = white
	ring.position = Vector3(0.0, 0.95, -0.2)
	rover.add_child(ring)
	# Cargo box and whip antenna behind.
	_box(rover, "Cargo", Vector3(1.1, 0.45, 0.45), Vector3(0.0, 1.0, 1.25), white)
	_box(rover, "CargoStripe", Vector3(1.12, 0.06, 0.47), Vector3(0.0, 1.05, 1.25), stripe)
	_box(rover, "Antenna", Vector3(0.03, 1.1, 0.03), Vector3(0.45, 1.75, 1.35), grey)
	# Wheels: a pivot (steers) holding a Spin node (rolls) holding the tyre,
	# its ribs and a hub; a fender over each.
	for wheel in [["FL", -1.0, -1.0], ["FR", 1.0, -1.0], ["RL", -1.0, 1.0], ["RR", 1.0, 1.0]]:
		var pivot := Node3D.new()
		pivot.name = "Wheel" + wheel[0]
		pivot.position = Vector3(wheel[1] * 0.9, WHEEL_RADIUS, wheel[2] * 1.25)
		rover.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		var tyre_mesh := MeshInstance3D.new()
		tyre_mesh.name = "Tyre"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = WHEEL_RADIUS - 0.04
		cylinder.bottom_radius = WHEEL_RADIUS - 0.04
		cylinder.height = WHEEL_WIDTH
		cylinder.radial_segments = 16
		tyre_mesh.mesh = cylinder
		tyre_mesh.material_override = tyre
		tyre_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
		spin.add_child(tyre_mesh)
		for k in range(8):
			var rib := MeshInstance3D.new()
			rib.name = "Rib%d" % k
			var rib_box := BoxMesh.new()
			rib_box.size = Vector3(WHEEL_WIDTH, 0.06, 0.12)
			rib.mesh = rib_box
			rib.material_override = tyre
			var angle := TAU * k / 8.0
			rib.rotation = Vector3(angle, 0.0, 0.0)
			rib.position = Vector3(0.0, cos(angle), -sin(angle)) * (WHEEL_RADIUS - 0.03)
			spin.add_child(rib)
		_box(spin, "Hub", Vector3(WHEEL_WIDTH + 0.02, 0.22, 0.22), Vector3.ZERO, grey)
		_box(rover, "Fender" + wheel[0], Vector3(0.38, 0.06, 0.95), Vector3(wheel[1] * 0.9, 0.9, wheel[2] * 1.25), white)

static func _box(parent: Node3D, part: String, size: Vector3, at: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = part
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)

static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

static func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

# Faint blue glass, seen from inside too.
static func _glass() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.6, 0.85, 1.0, 0.1)
	material.roughness = 0.05
	material.metallic_specular = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material
```

- [ ] **Step 4:** `test_rover_model.gd` e `test_moon_rover.gd` → `ALL TESTS PASSED`.
- [ ] **Step 5:** commit "Rover: a Moon Buggy (Space: 1999)".

---

### Task 3: Scie e onde di prua delle barche

**Files:**
- Create: `scripts/boat_wake.gd`, `tests/test_boat_wake.gd`
- Modify: `scripts/interior_world.gd` (membri, `build()`, dove nasce il MultiMesh `Boats`),
  `scripts/lake_boats.gd` (commento di `boat_mesh`)

**Interfaces:**
- Consumes: `LoopTraffic.pose_at(loop, t) -> Transform3D` (x sinistra, y alto, z avanti), `LoopTraffic.LOOP_GLSL`
  (`loop_pose(model, time, ...)`), `LoopTraffic.multimesh_instance`, `LoopTraffic.make_loop`, `with_stop`,
  `stop_progress`.
- Produces: `BoatWake.wake_mesh() -> ArrayMesh`, `BoatWake.material(corner: float) -> ShaderMaterial`,
  `wake_point(loop, t, lag, lateral, along, lift) -> Vector3`, `speed_share(loop, t, lag) -> float`,
  `wake_alpha(loop, t, lag, duration, strength) -> float`, `wake_lift(distance) -> float`.

- [ ] **Step 1: test** — `tests/test_boat_wake.gd`:

```gdscript
extends SceneTree

# The boats' wakes: points where the boat was `lag` seconds ago, fading with
# the lag and with the boat's speed then, lifted off the water more the
# farther the camera.

const BoatWake = preload("res://scripts/boat_wake.gd")
const LoopTraffic = preload("res://scripts/loop_traffic.gd")

func _initialize():
	var failures := 0
	failures += _test_point_where_the_boat_was()
	failures += _test_fades_with_the_lag()
	failures += _test_stopped_boat_leaves_no_wake()
	failures += _test_lift_grows_with_distance()
	failures += _test_mesh_lags_in_range()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _cruising() -> Dictionary:
	return LoopTraffic.make_loop(LoopTraffic.FLAT, 0.0, 0.0, 400.0, 200.0, 30.0, 10.0, 0.0, 0.0, 0)

func _test_point_where_the_boat_was() -> int:
	var loop := _cruising()
	var then := LoopTraffic.pose_at(loop, 98.0)
	var expected := then.origin + then.basis.x * 2.0 + then.basis.z * -5.0 + then.basis.y * 0.15
	var got: Vector3 = BoatWake.wake_point(loop, 100.0, 2.0, 2.0, -5.0, 0.15)
	if got.distance_to(expected) > 1e-6:
		print("FAIL _test_point_where_the_boat_was: %s, expected %s" % [got, expected])
		return 1
	return 0

func _test_fades_with_the_lag() -> int:
	var loop := _cruising()
	var early: float = BoatWake.wake_alpha(loop, 100.0, 1.0, 6.0, 1.0)
	var late: float = BoatWake.wake_alpha(loop, 100.0, 5.0, 6.0, 1.0)
	var gone: float = BoatWake.wake_alpha(loop, 100.0, 6.0, 6.0, 1.0)
	if not (early > late and late > 0.0 and gone == 0.0):
		print("FAIL _test_fades_with_the_lag: %.3f, %.3f, %.3f" % [early, late, gone])
		return 1
	return 0

# A loop with a stop: halfway through the dwell the boat has been still
# for 10 s, so even its freshest wake is gone.
func _test_stopped_boat_leaves_no_wake() -> int:
	var loop := LoopTraffic.with_stop(_cruising(), 100.0, 10.0, 0.0)
	var lap := LoopTraffic.lap_time(loop)
	var t := lap - LoopTraffic.STOP_DWELL * 0.5
	var alpha: float = BoatWake.wake_alpha(loop, t, 0.5, 6.0, 1.0)
	var moving: float = BoatWake.wake_alpha(loop, lap * 0.4, 0.5, 6.0, 1.0)
	if alpha != 0.0 or moving <= 0.5:
		print("FAIL _test_stopped_boat_leaves_no_wake: at the stop %.3f, cruising %.3f" % [alpha, moving])
		return 1
	return 0

func _test_lift_grows_with_distance() -> int:
	var near: float = BoatWake.wake_lift(10.0)
	var far: float = BoatWake.wake_lift(1000.0)
	if absf(near - 0.15) > 1e-6 or absf(far - 0.6) > 1e-6:
		print("FAIL _test_lift_grows_with_distance: %.3f, %.3f" % [near, far])
		return 1
	return 0

func _test_mesh_lags_in_range() -> int:
	var arrays := BoatWake.wake_mesh().surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var longest := 0.0
	for uv in uvs:
		if uv.x < 0.0 or uv.x > BoatWake.ARM_TIME + 1e-6:
			print("FAIL _test_mesh_lags_in_range: lag %.2f" % uv.x)
			return 1
		longest = maxf(longest, uv.x)
	if uvs.is_empty() or absf(longest - BoatWake.ARM_TIME) > 1e-6:
		print("FAIL _test_mesh_lags_in_range: %d vertices, longest lag %.2f" % [uvs.size(), longest])
		return 1
	return 0
```

Nota: la sosta è all'inizio di ogni giro (`stop_progress` parte dalla ripartenza), quindi a `lap − dwell/2` la
barca è ferma; se `stop_progress` mette la sosta altrove, leggere il codice e scegliere un `t` dentro la sosta
(ruling a ledger).

- [ ] **Step 2:** lanciare; atteso errore di caricamento (`boat_wake.gd` non c'è).

- [ ] **Step 3: codice** — `scripts/boat_wake.gd`:

```gdscript
extends RefCounted

# The boats' wakes, drawn by the shader alone like the boats (LoopTraffic):
# each wake vertex carries a lag (UV.x, seconds) and sits where the boat
# was that long ago, `lateral` to its left (VERTEX.x) and `along` ahead of
# its middle (VERTEX.z), so the wake follows the loop's curves. Two foam
# arms opening in a V behind the stern (ARM_TIME), a fainter band between
# them (CENTRE_TIME), two short whiskers off the bow (BOW_TIME). It fades
# with the lag and with the boat's speed then: a boat waiting at its pier
# leaves none. See-through, writing no depth, lifted off the water more
# the farther the camera (the 24-bit depth made a flat wake flicker), and
# gone past FAR_END. wake_point, speed_share, wake_alpha and wake_lift are
# the GDScript copies (tests).

const LoopTraffic = preload("res://scripts/loop_traffic.gd")

const STERN := -5.0
const BOW := 5.6
const ARM_TIME := 6.0
const CENTRE_TIME := 4.0
const BOW_TIME := 1.0
const ROWS := 12
# The boat's speed is read over this long; full wake from FULL_SPEED.
const SPEED_SAMPLE := 0.5
const FULL_SPEED := 6.0
const LIFT_NEAR := 0.15
const LIFT_PER_METRE := 0.0006
const FAR_START := 1200.0
const FAR_END := 1500.0
# [along, lateral at lag 0, lateral growth (m/s), width at lag 0, width at
# the end, duration, strength, mirrored each side]
const PIECES := [
	[STERN, 1.2, 1.5, 0.8, 3.0, ARM_TIME, 1.0, true],
	[STERN, 0.0, 0.0, 2.5, 6.0, CENTRE_TIME, 0.5, false],
	[BOW, 0.6, 3.0, 0.5, 1.2, BOW_TIME, 0.8, true],
]

const SHADER := """
shader_type spatial;
render_mode unshaded, skip_vertex_transform, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
%s
uniform float speed_sample = 0.5;
uniform float full_speed = 6.0;
uniform float lift_near = 0.15;
uniform float lift_per_metre = 0.0006;
uniform float far_start = 1200.0;
uniform float far_end = 1500.0;

varying float fade;
varying float edge;
varying float night;

void vertex() {
	float lag = UV.x;
	vec3 pos; vec3 left; vec3 up; vec3 forward;
	loop_pose(MODEL_MATRIX, TIME - lag, pos, left, up, forward);
	vec3 before; vec3 l2; vec3 u2; vec3 f2;
	loop_pose(MODEL_MATRIX, TIME - lag - speed_sample, before, l2, u2, f2);
	float share = clamp(length(pos - before) / speed_sample / full_speed, 0.0, 1.0);
	vec3 world = pos + left * VERTEX.x + forward * VERTEX.z;
	float distance = length(world - CAMERA_POSITION_WORLD);
	world += up * max(lift_near, lift_per_metre * distance);
	fade = max(0.0, 1.0 - lag / UV2.x) * share * UV2.y * (1.0 - smoothstep(far_start, far_end, distance));
	edge = UV.y;
	night = interior_night(interior_hour(world.z));
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	ALBEDO = vec3(0.85, 0.94, 1.0) * mix(1.0, 0.4, night);
	ALPHA = fade * edge * 0.85;
}
"""

# Strips of three vertices across (edge, middle, edge), ROWS + 1 rows down
# the lag. UV: (lag, 1 in the middle else 0); UV2: (duration, strength).
static func wake_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece in PIECES:
		var sides: Array = [-1.0, 1.0] if piece[7] else [0.0]
		for side: float in sides:
			var rows := []
			for r in range(ROWS + 1):
				var share := float(r) / ROWS
				var lag: float = piece[5] * share
				var centre: float = side * (piece[1] + piece[2] * lag)
				var width: float = lerpf(piece[3], piece[4], share)
				var row := []
				for k in range(3):
					row.append([Vector3(centre + (k - 1) * width * 0.5, 0.0, piece[0]), Vector2(lag, 1.0 if k == 1 else 0.0)])
				rows.append(row)
			for r in range(ROWS):
				for k in range(2):
					var quad := [rows[r][k], rows[r][k + 1], rows[r + 1][k + 1], rows[r + 1][k]]
					for i in [0, 1, 2, 0, 2, 3]:
						st.set_uv(quad[i][1])
						st.set_uv2(Vector2(piece[5], piece[6]))
						st.add_vertex(quad[i][0])
	return st.commit()

static func material(corner: float) -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = SHADER % LoopTraffic.LOOP_GLSL
	shader_material.set_shader_parameter("corner", corner)
	shader_material.set_shader_parameter("speed_sample", SPEED_SAMPLE)
	shader_material.set_shader_parameter("full_speed", FULL_SPEED)
	shader_material.set_shader_parameter("lift_near", LIFT_NEAR)
	shader_material.set_shader_parameter("lift_per_metre", LIFT_PER_METRE)
	shader_material.set_shader_parameter("far_start", FAR_START)
	shader_material.set_shader_parameter("far_end", FAR_END)
	return shader_material

static func wake_point(loop: Dictionary, t: float, lag: float, lateral: float, along: float, lift: float) -> Vector3:
	var frame := LoopTraffic.pose_at(loop, t - lag)
	return frame.origin + frame.basis.x * lateral + frame.basis.z * along + frame.basis.y * lift

static func speed_share(loop: Dictionary, t: float, lag: float) -> float:
	var now := LoopTraffic.pose_at(loop, t - lag).origin
	var before := LoopTraffic.pose_at(loop, t - lag - SPEED_SAMPLE).origin
	return clampf(now.distance_to(before) / SPEED_SAMPLE / FULL_SPEED, 0.0, 1.0)

static func wake_alpha(loop: Dictionary, t: float, lag: float, duration: float, strength: float) -> float:
	return maxf(0.0, 1.0 - lag / duration) * speed_share(loop, t, lag) * strength

static func wake_lift(distance: float) -> float:
	return maxf(LIFT_NEAR, LIFT_PER_METRE * distance)
```

In `scripts/interior_world.gd`: `const BoatWake = preload("res://scripts/boat_wake.gd")`; membri
`var _wake_mesh: ArrayMesh` e `var _wake_material: ShaderMaterial` accanto a `_boat_mesh`; in `build()` dopo
`_boat_material = ...`: `_wake_mesh = BoatWake.wake_mesh()` e `_wake_material = BoatWake.material(LakeBoats.CORNER)`;
dopo la riga che aggiunge `Boats`:

```gdscript
		state.node.add_child(LoopTraffic.multimesh_instance("BoatWakes", state.boats, _wake_mesh, _wake_material, lake_bounds))
```

In `scripts/lake_boats.gd`, commento di `boat_mesh`: "(The wake is boat_wake.gd's.)" al posto della frase sulla
scia piatta.

- [ ] **Step 4:** `test_boat_wake.gd`, `test_lake_boats.gd`, `test_loop_traffic.gd`, `test_interior_world.gd` →
  `ALL TESTS PASSED`.
- [ ] **Step 5:** commit "Boats: a V wake behind the stern and whiskers off the bow, fading in seconds, none at the
  pier".

---

### Task 4: Cabine degli ascensori di vetro, con persone

**Files:**
- Modify: `scripts/spine_train.gd` (`lift_mesh`, nuove `lift_glass_mesh`, `lift_glass_material`, `lift_riders`,
  costanti), `scripts/interior_world.gd` (membri, `build()`, ciclo delle cabine), `tests/test_spine_train.gd`

**Interfaces:**
- Produces: `SpineTrain.LIFT_SLAB := 0.4`, `LIFT_POST := 0.3`, `lift_mesh()`, `lift_glass_mesh() -> ArrayMesh`,
  `lift_glass_material() -> ShaderMaterial`, `lift_riders(seed: int) -> Array` di `{transform: Transform3D, suit: int}`.
- Consumes: `DockCrowd.person_mesh()`, `DockCrowd.SUITS`, `SpineTrain.structure_material(hull, accent)`.

- [ ] **Step 1: test** — in `tests/test_spine_train.gd` aggiungere a `_initialize`:

```gdscript
	_failures += _test_lift_frame_keeps_its_size()
	_failures += _test_lift_glass_on_four_sides()
	_failures += _test_lift_riders()
```

e le funzioni:

```gdscript
func _test_lift_frame_keeps_its_size() -> int:
	var box := SpineTrain.lift_mesh().get_aabb()
	var half := SpineTrain.LIFT_SIZE * 0.5
	if box.position.x < -half.x - 0.06 or box.end.x > half.x + 0.06 or box.position.y < -half.y - 0.01 or box.end.y > half.y + 0.3 or box.position.z < -half.z - 0.06 or box.end.z > half.z + 0.06:
		print("FAIL _test_lift_frame_keeps_its_size: %s" % box)
		return 1
	return 0

func _test_lift_glass_on_four_sides() -> int:
	var box := SpineTrain.lift_glass_mesh().get_aabb()
	if box.size.x < 5.6 or box.size.z < 5.6 or box.size.y < 6.8:
		print("FAIL _test_lift_glass_on_four_sides: %s" % box)
		return 1
	return 0

func _test_lift_riders() -> int:
	var half := SpineTrain.LIFT_SIZE * 0.5
	var floor_y := -half.y + SpineTrain.LIFT_SLAB
	for seed in range(60):
		var riders: Array = SpineTrain.lift_riders(seed)
		var again: Array = SpineTrain.lift_riders(seed)
		if riders.size() < 1 or riders.size() > 4 or riders.size() != again.size():
			print("FAIL _test_lift_riders: seed %d gives %d riders" % [seed, riders.size()])
			return 1
		for i in range(riders.size()):
			var at: Vector3 = riders[i].transform.origin
			if at != (again[i].transform.origin as Vector3) or absf(at.x) > half.x - 0.6 or absf(at.z) > half.z - 0.6 or absf(at.y - floor_y) > 1e-6:
				print("FAIL _test_lift_riders: seed %d rider at %s" % [seed, at])
				return 1
			for j in range(i):
				if at.distance_to(riders[j].transform.origin) < 0.8:
					print("FAIL _test_lift_riders: seed %d riders too close" % seed)
					return 1
	return 0
```

- [ ] **Step 2:** lanciare `test_spine_train.gd`; atteso `SCRIPT ERROR`/`Parse Error` (`LIFT_SLAB`, `lift_glass_mesh`,
  `lift_riders` mancano).

- [ ] **Step 3: codice** — in `scripts/spine_train.gd`, accanto a `LIFT_SIZE`:

```gdscript
# A cabin's floor and roof thickness, its corner posts' width.
const LIFT_SLAB := 0.4
const LIFT_POST := 0.3
# Riders keep this far from the walls and 0.8 m from each other.
const LIFT_RIDER_MARGIN := 0.6
const LIFT_RIDER_GAP := 0.8
```

`lift_mesh` al posto di quello di oggi, e le nuove funzioni dopo:

```gdscript
# A lift cabin's frame, centred: floor and roof LIFT_SLAB thick, four corner
# posts, a glowing band round the roof and a cap on it, the sliding door's
# rail on +z. The walls are glass (lift_glass_mesh).
static func lift_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := LIFT_SIZE * 0.5
	RoadTraffic._box(st, Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y + LIFT_SLAB, half.z), 0.0)
	RoadTraffic._box(st, Vector3(-half.x, half.y - LIFT_SLAB, -half.z), Vector3(half.x, half.y, half.z), 0.0)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			var a := Vector3(x * half.x, -half.y, z * half.z)
			var b := Vector3(x * (half.x - LIFT_POST), half.y, z * (half.z - LIFT_POST))
			RoadTraffic._box(st, a.min(b), a.max(b), 0.0)
	RoadTraffic._box(st, Vector3(-half.x - 0.05, half.y - 0.35, -half.z - 0.05), Vector3(half.x + 0.05, half.y - 0.2, half.z + 0.05), 2.0)
	RoadTraffic._box(st, Vector3(-half.x * 0.8, half.y, -half.z * 0.8), Vector3(half.x * 0.8, half.y + 0.25, half.z * 0.8), 2.0)
	RoadTraffic._box(st, Vector3(-1.6, half.y - LIFT_SLAB - 0.15, half.z - 0.15), Vector3(1.6, half.y - LIFT_SLAB, half.z), 1.0)
	st.index()
	return st.commit()

# The cabin's four glass walls between floor and roof.
static func lift_glass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := LIFT_SIZE * 0.5 - Vector3(0.05, LIFT_SLAB, 0.05)
	for side: float in [-1.0, 1.0]:
		RoadTraffic._box(st, Vector3(side * inner.x - 0.03, -inner.y, -inner.z), Vector3(side * inner.x + 0.03, inner.y, inner.z), 0.0)
		RoadTraffic._box(st, Vector3(-inner.x, -inner.y, side * inner.z - 0.03), Vector3(inner.x, inner.y, side * inner.z + 0.03), 0.0)
	st.index()
	return st.commit()

# Faint blue glass, warmer and a little brighter by night (lit inside).
const GLASS_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/interior_hour.gdshaderinc"

varying float night;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	night = interior_night(interior_hour(world.z));
}

void fragment() {
	ALBEDO = mix(vec3(0.55, 0.8, 0.95), vec3(1.0, 0.88, 0.65), night);
	ALPHA = mix(0.22, 0.38, night);
}
"""

static func lift_glass_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = GLASS_SHADER
	return material

# One to four people standing on the cabin's floor, the same for the same
# `seed`: {transform (cabin frame), suit (0-3)}.
static func lift_riders(seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var count := rng.randi_range(1, 4)
	var floor_y := -LIFT_SIZE.y * 0.5 + LIFT_SLAB
	var reach := LIFT_SIZE.x * 0.5 - LIFT_POST - LIFT_RIDER_MARGIN
	var riders := []
	for attempt in range(100):
		if riders.size() >= count:
			break
		var at := Vector3(rng.randf_range(-reach, reach), floor_y, rng.randf_range(-reach, reach))
		var clear := true
		for rider in riders:
			if (rider.transform.origin as Vector3).distance_to(at) < LIFT_RIDER_GAP:
				clear = false
		if clear:
			riders.append({"transform": Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at), "suit": rng.randi_range(0, 3)})
	return riders
```

In `scripts/interior_world.gd`: preload `DockCrowd` se non c'è già; membri `var _lift_glass_mesh: ArrayMesh`,
`var _lift_glass_material: ShaderMaterial`, `var _person_mesh: ArrayMesh`, `var _rider_materials: Array = []`; in
`build()` dopo `_lift_mesh = SpineTrain.lift_mesh()`:

```gdscript
	_lift_glass_mesh = SpineTrain.lift_glass_mesh()
	_lift_glass_material = SpineTrain.lift_glass_material()
	_person_mesh = DockCrowd.person_mesh()
	_rider_materials.clear()
	for suit in DockCrowd.SUITS:
		_rider_materials.append(SpineTrain.structure_material(suit, ACCENT_COLOR))
```

nel ciclo delle cabine, dopo `cabin.position = foot`:

```gdscript
			cabin.add_child(_structure_mesh("Glass", _lift_glass_mesh, _lift_glass_material))
			var riders := SpineTrain.lift_riders(hash([state.ring_index, k, side]))
			for i in range(riders.size()):
				var rider := _structure_mesh("Rider_%d" % i, _person_mesh, _rider_materials[riders[i].suit])
				rider.transform = riders[i].transform
				cabin.add_child(rider)
```

- [ ] **Step 4:** `test_spine_train.gd`, `test_interior_world.gd`, `test_interior_train.gd` (se esiste) → verdi.
- [ ] **Step 5:** commit "Lift cabins: glass walls on a frame, one to four people riding".

---

### Task 5: Prova GPU e note

- [ ] **Step 1:** `tests/zz_probe.gd` (finestra visibile, poi cancellato): (a) nave su pad 1, `leave_ship`, rover
  girato verso la nave → `eagle.png`; (b) dalla cabina del rover → `buggy.png`; (c) interno: internal cruiser a
  ~150 m sopra un lago con una barca in moto, guardando giù → `wake.png`; (d) davanti a una cabina d'ascensore,
  di giorno e di notte (ora del `InteriorClock`) → `lift_day.png`, `lift_night.png`. Guardare i PNG; correggere
  e rilanciare il test del pezzo toccato.
- [ ] **Step 2:** sezione "Cambiato durante l'esecuzione" in fondo alla spec; commit.
