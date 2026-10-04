# MoonRover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un rover da guidare sulla luna: esce dalla nave atterrata con V, si guida dalla cabina, si risale con V vicino alla nave.

**Architecture:** Un nucleo di guida arcade di sole funzioni statiche (`ground_vehicle.gd`) che chiede il suolo a un "fornitore" (`ground_altitude(point)`, `up_at(point)`); sulla luna il fornitore è il nodo della luna. Il nodo `moon_rover.gd` gira con la luna, chiama il nucleo, urta la base con `move_and_collide`, porta la toppa della luna. `game_mode.gd` aggiunge `Mode.ROVER` e lo scambio nave ↔ rover.

**Tech Stack:** Godot 4.6.1 doppia precisione, GDScript, test come script `extends SceneTree`.

**Spec:** `docs/superpowers/specs/2026-10-04-moon-rover-design.md`

## Global Constraints

- Godot: sempre `~/Godot_v4.6.1-stable-double_linux.x86_64` (il `godot` nel PATH rende nero). Un test:
  `~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/<file>.gd`; fallito se l'output ha
  `FAIL`, `SCRIPT ERROR` o `Parse Error`, passato se stampa `ALL TESTS PASSED`.
- Solo i test nuovi o toccati, non la suite intera.
- TDD: ogni test va visto fallire prima del codice.
- Tasti: **V** = azione `vehicle` (physical keycode 86), **L** = azione `lights` (76). W/S/A/D/B già esistono
  (`move_forward`, `move_backward`, `move_left`, `move_right`, `brake`).
- Valori del rover: 20 m/s max, retromarcia 5 m/s, gas 3 m/s², freno 6, freno a mano 8, attrito 0,6;
  raggio di sterzata 6 m da fermo → 40 m a 20 m/s; gravità lunare 1,62 m/s²; pendenza: motore pieno fino a
  25°, zero a 35°, oltre 35° scivola; in aria se più di 0,15 m sopra il suolo.
- Scambio: rover a 15 m dalla nave (52 m dal centro del pad se la nave è su un pad); risalita entro 30 m dalla
  nave (60 m dal centro del pad se la nave è su un pad) e sotto 1 m/s.
- Commenti in inglese, nello stile dei file vicini (frasi brevi sopra le funzioni).
- Ogni commit termina con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Nave su un pad**: il rover non deve nascere dentro il pad o dentro un tubo (spoke) — test in Task 5
   (`_test_rover_comes_out_clear_of_the_pad`) e in Task 4 (`spawn_spots`).
2. **Doppia corsa alla toppa della luna**: con il rover fuori la nave non deve chiamare `follow_patch` — test
   in Task 5 (`_test_parked_ship_leaves_the_patch_to_the_rover`).
3. **Tasti della nave durante il rover** (B accendeva il freno della nave, C il cruise): la nave parcheggiata
   non deve ricevere input — test in Task 5 (`_test_parked_ship_ignores_its_keys`).
4. **Spostamento dell'origine del mondo** quando il rover va lontano dalla nave: il rebase deve seguire il
   rover — test in Task 5 (`_test_rebase_follows_the_rover`).
5. **Retromarcia e sterzo**: in retromarcia con D il rover deve girare come un'auto vera (il muso va a
   sinistra) — test in Task 1 (`_test_reverse_turns_like_a_car`).

---

## File Structure

- Create `scripts/ground_vehicle.gd` — nucleo di guida, solo statiche.
- Create `scripts/rover_rules.gd` — dove nasce il rover, quando si può risalire (statiche).
- Create `scripts/rover_model.gd` — il modello del rover a codice (statiche).
- Create `scripts/rover_hud.gd` — HUD del rover (CanvasLayer) + `readout()` e `heading()` statiche.
- Create `scripts/moon_rover.gd` — il nodo del rover.
- Modify `scripts/moon.gd` — `ground_altitude()` (alias di `altitude`).
- Modify `scripts/void_cruiser.gd` — `parked`, `park()`.
- Modify `scripts/landing_readout.gd`, `scripts/cockpit.gd` — riga `V ROVER` quando atterrati.
- Modify `scripts/game_mode.gd` — `Mode.ROVER`, scambio con V.
- Modify `project.godot` — azioni `vehicle` e `lights`.
- Tests: `tests/test_ground_vehicle.gd`, `tests/test_rover_rules.gd`, `tests/test_rover_hud.gd`,
  `tests/test_moon_rover.gd` (nuovi); `tests/test_landing_readout.gd`, `tests/test_game_mode.gd` (toccati).

---

### Task 1: Nucleo di guida — velocità, sterzo, pendenza

**Files:**
- Create: `scripts/ground_vehicle.gd`
- Test: `tests/test_ground_vehicle.gd`

**Interfaces:**
- Produces (statiche di `ground_vehicle.gd`):
  - costanti `MAX_SPEED`, `MAX_REVERSE`, `ACCELERATION`, `BRAKING`, `HANDBRAKE`, `ROLLING_DRAG`,
    `RADIUS_STANDING`, `RADIUS_AT_TOP`, `WHEELBASE`, `STEER_IN_TIME`, `STEER_OUT_TIME`, `SLOPE_SOFT`,
    `SLOPE_STOP`, `AIR_GAP`, `SETTLE_TIME`, `HALF_TRACK`, `HALF_BASE`
  - `turn_radius(speed: float) -> float`
  - `yaw_rate(speed: float, steer: float) -> float` (rad/s, + verso sinistra attorno all'alto del veicolo;
    `steer` −1 sinistra … +1 destra)
  - `wheel_angle(speed: float, steer: float) -> float` (rad, per il modello)
  - `next_steer(steer: float, wanted: float, delta: float) -> float`
  - `climb_factor(slope: float) -> float`
  - `next_speed(speed: float, throttle: float, handbrake: bool, slope: float, gravity: float, delta: float) -> float`

- [ ] **Step 1: Write the failing test**

`tests/test_ground_vehicle.gd`:

```gdscript
extends SceneTree

# The ground vehicle's driving (GroundVehicle): speed, steering, slopes, and
# (with a made-up ground) the ground, the air and the tilt.

const GroundVehicle = preload("res://scripts/ground_vehicle.gd")
const DT := 1.0 / 60.0
const MOON_G := 1.62

func _init():
	var failures := 0
	failures += _test_throttle_reaches_top_speed_and_no_more()
	failures += _test_coasting_slows_down()
	failures += _test_back_brakes_then_reverses()
	failures += _test_turn_radius_grows_with_speed()
	failures += _test_reverse_turns_like_a_car()
	failures += _test_steering_eases_in_and_out()
	failures += _test_engine_weakens_uphill()
	failures += _test_steep_slope_slides_back()
	failures += _test_handbrake_stops()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

# `seconds` of the same controls on a slope, from `speed`.
func _speed_after(speed: float, throttle: float, handbrake: bool, slope: float, seconds: float) -> float:
	for i in range(roundi(seconds / DT)):
		speed = GroundVehicle.next_speed(speed, throttle, handbrake, slope, MOON_G, DT)
	return speed

func _test_throttle_reaches_top_speed_and_no_more() -> int:
	var after_2 := _speed_after(0.0, 1.0, false, 0.0, 2.0)
	var after_20 := _speed_after(0.0, 1.0, false, 0.0, 20.0)
	if absf(after_2 - 6.0) > 0.05 or absf(after_20 - 20.0) > 1e-6:
		print("FAIL _test_throttle_reaches_top_speed_and_no_more: %.3f after 2 s, %.3f after 20 s" % [after_2, after_20])
		return 1
	return 0

func _test_coasting_slows_down() -> int:
	var after := _speed_after(10.0, 0.0, false, 0.0, 5.0)
	if absf(after - 7.0) > 0.05:
		print("FAIL _test_coasting_slows_down: %.3f m/s, expected 7" % after)
		return 1
	return 0

func _test_back_brakes_then_reverses() -> int:
	var braked := _speed_after(12.0, -1.0, false, 0.0, 1.0)
	var stopped := _speed_after(12.0, -1.0, false, 0.0, 2.0)
	var reversing := _speed_after(12.0, -1.0, false, 0.0, 10.0)
	# After 2 s of S from 12 m/s (6 m/s²) it has just stopped: at most a tick of reverse.
	if absf(braked - 6.0) > 0.05 or stopped > 0.01 or stopped < -0.1 or absf(reversing + 5.0) > 1e-6:
		print("FAIL _test_back_brakes_then_reverses: %.3f after 1 s, %.3f after 2 s, %.3f after 10 s" % [braked, stopped, reversing])
		return 1
	return 0

func _test_turn_radius_grows_with_speed() -> int:
	var standing := GroundVehicle.turn_radius(0.0)
	var top := GroundVehicle.turn_radius(20.0)
	var rate := GroundVehicle.yaw_rate(20.0, 1.0)
	if absf(standing - 6.0) > 1e-6 or absf(top - 40.0) > 1e-6 or absf(rate + 0.5) > 1e-6:
		print("FAIL _test_turn_radius_grows_with_speed: %.2f m, %.2f m, %.3f rad/s" % [standing, top, rate])
		return 1
	return 0

# D (steer +1) going forward turns right (negative about up); going back the
# nose swings the other way, as in a car.
func _test_reverse_turns_like_a_car() -> int:
	var forward := GroundVehicle.yaw_rate(5.0, 1.0)
	var back := GroundVehicle.yaw_rate(-5.0, 1.0)
	if forward >= 0.0 or back <= 0.0:
		print("FAIL _test_reverse_turns_like_a_car: forward %.3f, back %.3f" % [forward, back])
		return 1
	return 0

func _test_steering_eases_in_and_out() -> int:
	var steer := 0.0
	for i in range(9):  # 0.15 s
		steer = GroundVehicle.next_steer(steer, 1.0, DT)
	var half := steer
	for i in range(9):
		steer = GroundVehicle.next_steer(steer, 1.0, DT)
	var full := steer
	for i in range(12):  # 0.2 s
		steer = GroundVehicle.next_steer(steer, 0.0, DT)
	if absf(half - 0.5) > 0.01 or absf(full - 1.0) > 1e-6 or absf(steer) > 1e-6:
		print("FAIL _test_steering_eases_in_and_out: %.3f, %.3f, %.3f" % [half, full, steer])
		return 1
	return 0

func _test_engine_weakens_uphill() -> int:
	var flat := _speed_after(0.0, 1.0, false, 0.0, 2.0)
	var at_30 := _speed_after(0.0, 1.0, false, deg_to_rad(30.0), 2.0)
	var at_36 := _speed_after(0.0, 1.0, false, deg_to_rad(36.0), 2.0)
	# Backing down the same 30-degree hill: full engine.
	var down := _speed_after(0.0, -1.0, false, deg_to_rad(30.0), 1.0)
	if absf(at_30 - flat * 0.5) > 0.05 or at_36 > 0.0 or absf(down + 3.0) > 0.05:
		print("FAIL _test_engine_weakens_uphill: flat %.2f, 30° %.2f, 36° %.2f, back down %.2f" % [flat, at_30, at_36, down])
		return 1
	return 0

func _test_steep_slope_slides_back() -> int:
	var slid := _speed_after(0.0, 0.0, false, deg_to_rad(40.0), 3.0)
	var held := _speed_after(0.0, 0.0, false, deg_to_rad(30.0), 3.0)
	if slid > -0.5 or held != 0.0:
		print("FAIL _test_steep_slope_slides_back: 40° %.3f, 30° %.3f" % [slid, held])
		return 1
	return 0

func _test_handbrake_stops() -> int:
	var stopped := _speed_after(16.0, 1.0, true, 0.0, 2.1)
	if stopped != 0.0:
		print("FAIL _test_handbrake_stops: %.3f m/s" % stopped)
		return 1
	return 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_ground_vehicle.gd`
Expected: `Parse Error` / errore di caricamento di `res://scripts/ground_vehicle.gd` (il file non esiste).

- [ ] **Step 3: Write minimal implementation**

`scripts/ground_vehicle.gd`:

```gdscript
extends RefCounted

# Arcade driving for a vehicle on the ground (the moon rover; later the car
# inside the station). Pure functions, no nodes: the vehicle's state goes in,
# the new state comes out. The ground is asked through any object with
#   ground_altitude(point: Vector3) -> float  (how far `point` is over it)
#   up_at(point: Vector3) -> Vector3          (the local up there)
# The vehicle's origin is where its wheels touch the ground; -Z is its nose.

const MAX_SPEED := 20.0
const MAX_REVERSE := 5.0
const ACCELERATION := 3.0
const BRAKING := 6.0
const HANDBRAKE := 8.0
# Off the throttle the vehicle slows down by itself.
const ROLLING_DRAG := 0.6
# The tightest turn: 6 m standing, 40 m at top speed, straight in between.
const RADIUS_STANDING := 6.0
const RADIUS_AT_TOP := 40.0
const WHEELBASE := 2.5
# The wheel turns full over in 0.3 s and comes back straight in 0.2 s.
const STEER_IN_TIME := 0.3
const STEER_OUT_TIME := 0.2
# Uphill the engine weakens from 25 degrees and has nothing left at 35;
# steeper than 35 degrees the vehicle slides down.
const SLOPE_SOFT := 0.4363323  # 25 degrees
const SLOPE_STOP := 0.6108652  # 35 degrees
# Further than this over the ground the vehicle is in the air.
const AIR_GAP := 0.15
# How fast the body leans onto the ground under its wheels.
const SETTLE_TIME := 0.1
# The wheels: half the track, half the wheelbase.
const HALF_TRACK := 0.9
const HALF_BASE := 1.25

static func turn_radius(speed: float) -> float:
	return lerpf(RADIUS_STANDING, RADIUS_AT_TOP, clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))

# Turning rate (rad/s, + to the left about the vehicle's up) at `speed` with
# the wheel at `steer` (-1 full left .. +1 full right). Backing up, the nose
# swings the other way, as in a car.
static func yaw_rate(speed: float, steer: float) -> float:
	return -speed / turn_radius(speed) * steer

# The front wheels' angle (rad, + to the left) for the model.
static func wheel_angle(speed: float, steer: float) -> float:
	return -atan(WHEELBASE / turn_radius(speed)) * steer

static func next_steer(steer: float, wanted: float, delta: float) -> float:
	var time := STEER_IN_TIME if wanted != 0.0 else STEER_OUT_TIME
	return move_toward(steer, wanted, delta / time)

# How much of the engine is left climbing `slope` (rad, + uphill).
static func climb_factor(slope: float) -> float:
	return clampf((SLOPE_STOP - slope) / (SLOPE_STOP - SLOPE_SOFT), 0.0, 1.0)

# The speed along the nose after a tick on the ground. `throttle` -1..1 (W
# +1, S -1): the way the vehicle goes (or off from standstill) it drives,
# against it it brakes. `slope` (rad) is + with the nose uphill.
static func next_speed(speed: float, throttle: float, handbrake: bool, slope: float, gravity: float, delta: float) -> float:
	var new_speed := speed
	if handbrake:
		new_speed = move_toward(speed, 0.0, HANDBRAKE * delta)
	elif throttle != 0.0 and (speed == 0.0 or signf(throttle) == signf(speed)):
		new_speed = speed + ACCELERATION * throttle * climb_factor(slope * signf(throttle)) * delta
	elif throttle != 0.0:
		new_speed = move_toward(speed, 0.0, BRAKING * absf(throttle) * delta)
	else:
		new_speed = move_toward(speed, 0.0, ROLLING_DRAG * delta)
	if absf(slope) > SLOPE_STOP:
		new_speed -= gravity * sin(slope) * delta
	return clampf(new_speed, -MAX_REVERSE, MAX_SPEED)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_ground_vehicle.gd`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ground_vehicle.gd tests/test_ground_vehicle.gd
git commit -m "Ground vehicle: arcade speed, steering and slopes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Nucleo di guida — suolo, aria, inclinazione

**Files:**
- Modify: `scripts/ground_vehicle.gd` (in fondo)
- Test: `tests/test_ground_vehicle.gd`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `new_body(at: Transform3D) -> Dictionary` → `{transform, speed: 0.0, vertical: 0.0, steer: 0.0, airborne: false, motion: Vector3.ZERO}`
  - `drive(body: Dictionary, controls: Dictionary, ground: Object, gravity: float, delta: float) -> Dictionary`
    — `controls` = `{throttle: float, steer: float, handbrake: bool}`; restituisce il corpo nuovo con
    `motion` (spostamento nel mondo di questo tick, da applicare prima di `settle`).
  - `settle(body: Dictionary, ground: Object, delta: float) -> Dictionary` — dopo lo spostamento: a terra
    (appoggiato e inclinato sulle 4 ruote) o in aria.
  - `heading_basis(nose: Vector3, up: Vector3) -> Basis` (y = up, −z = nose sul piano)
  - `contacts(at: Transform3D, ground: Object) -> Array` (4 punti del suolo: FL, FR, RL, RR)
  - `contact_normal(at: Transform3D, ground: Object) -> Vector3`

- [ ] **Step 1: Write the failing test**

Aggiungi in `tests/test_ground_vehicle.gd`, dopo le costanti:

```gdscript
# A made-up ground: a plane rising `angle` toward -Z (nose ahead), dropping
# `step` metres for z < step_at; up is always +Y.
class FakeGround:
	var angle := 0.0
	var step := 0.0
	var step_at := -INF

	func surface(p: Vector3) -> float:
		var y := -p.z * tan(angle)
		if p.z < step_at:
			y -= step
		return y

	func ground_altitude(p: Vector3) -> float:
		return p.y - surface(p)

	func up_at(_p: Vector3) -> Vector3:
		return Vector3.UP
```

Aggiungi in `_init`, prima del riepilogo:

```gdscript
	failures += _test_drives_straight_on_flat_ground()
	failures += _test_d_turns_right()
	failures += _test_climbs_a_ramp_on_its_surface()
	failures += _test_leans_onto_the_ramp()
	failures += _test_drop_flies_then_lands()
	failures += _test_handbrake_holds_on_a_20_degree_ramp()
```

e le funzioni:

```gdscript
# One tick: drive, move (no walls here), settle.
func _tick(body: Dictionary, controls: Dictionary, ground: FakeGround) -> Dictionary:
	body = GroundVehicle.drive(body, controls, ground, MOON_G, DT)
	body.transform = Transform3D(body.transform.basis, body.transform.origin + body.motion)
	return GroundVehicle.settle(body, ground, DT)

func _controls(throttle: float, steer := 0.0, handbrake := false) -> Dictionary:
	return {"throttle": throttle, "steer": steer, "handbrake": handbrake}

# On `ground` at `z`, nose to -Z, leaned onto the ground at once.
func _start(ground: FakeGround, z: float) -> Dictionary:
	var point := Vector3(0.0, ground.surface(Vector3(0.0, 0.0, z)), z)
	var body := GroundVehicle.new_body(Transform3D(GroundVehicle.heading_basis(Vector3.FORWARD, Vector3.UP), point))
	return GroundVehicle.settle(body, ground, 1.0)

func _test_drives_straight_on_flat_ground() -> int:
	var ground := FakeGround.new()
	var body := _start(ground, 0.0)
	for i in range(120):
		body = _tick(body, _controls(1.0), ground)
	var at: Vector3 = body.transform.origin
	# 2 s at 3 m/s²: about 6 m ahead, on the ground.
	if absf(at.z + 6.0) > 0.2 or absf(at.x) > 1e-6 or absf(at.y) > 1e-6 or body.airborne:
		print("FAIL _test_drives_straight_on_flat_ground: at %s, airborne %s" % [at, body.airborne])
		return 1
	return 0

func _test_d_turns_right() -> int:
	var ground := FakeGround.new()
	var body := _start(ground, 0.0)
	body.speed = 10.0
	for i in range(60):
		body = _tick(body, _controls(1.0, 1.0), ground)
	var nose: Vector3 = -body.transform.basis.z
	if nose.x <= 0.2 or body.transform.origin.x <= 0.0:
		print("FAIL _test_d_turns_right: nose %s, at %s" % [nose, body.transform.origin])
		return 1
	return 0

func _test_climbs_a_ramp_on_its_surface() -> int:
	var ground := FakeGround.new()
	ground.angle = deg_to_rad(20.0)
	var body := _start(ground, 0.0)
	var worst := 0.0
	for i in range(180):
		body = _tick(body, _controls(1.0), ground)
		worst = maxf(worst, absf(ground.ground_altitude(body.transform.origin)))
	if worst > 0.01 or body.transform.origin.y < 2.0 or body.airborne:
		print("FAIL _test_climbs_a_ramp_on_its_surface: %.3f m off the ground at worst, %.2f m up, airborne %s" % [worst, body.transform.origin.y, body.airborne])
		return 1
	return 0

func _test_leans_onto_the_ramp() -> int:
	var ground := FakeGround.new()
	ground.angle = deg_to_rad(20.0)
	var body := _start(ground, -10.0)
	var up: Vector3 = body.transform.basis.y.normalized()
	var expected := Vector3(0.0, cos(ground.angle), sin(ground.angle))
	if up.distance_to(expected) > 0.01:
		print("FAIL _test_leans_onto_the_ramp: up %s, expected %s" % [up, expected])
		return 1
	return 0

func _test_drop_flies_then_lands() -> int:
	var ground := FakeGround.new()
	ground.step = 1.0
	ground.step_at = -5.0
	var body := _start(ground, 0.0)
	body.speed = 20.0
	var flew := false
	var landed_again := false
	for i in range(240):
		body = _tick(body, _controls(1.0), ground)
		if body.airborne:
			flew = true
		elif flew:
			landed_again = true
			break
	var height := ground.ground_altitude(body.transform.origin)
	# Leaning over the edge first, it loses a little speed into the drop.
	if not flew or not landed_again or absf(height) > 1e-6 or body.speed < 17.0:
		print("FAIL _test_drop_flies_then_lands: flew %s, landed again %s, %.3f m over the ground, %.2f m/s" % [flew, landed_again, height, body.speed])
		return 1
	return 0

func _test_handbrake_holds_on_a_20_degree_ramp() -> int:
	var ground := FakeGround.new()
	ground.angle = deg_to_rad(20.0)
	var body := _start(ground, -10.0)
	var start: Vector3 = body.transform.origin
	for i in range(180):
		body = _tick(body, _controls(0.0, 0.0, true), ground)
	if body.transform.origin.distance_to(start) > 0.01:
		print("FAIL _test_handbrake_holds_on_a_20_degree_ramp: moved %.3f m" % body.transform.origin.distance_to(start))
		return 1
	return 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_ground_vehicle.gd`
Expected: `SCRIPT ERROR` (`new_body` / `heading_basis` non esistono).

- [ ] **Step 3: Write minimal implementation**

In fondo a `scripts/ground_vehicle.gd`:

```gdscript
# Standing still at `at`, on the ground.
static func new_body(at: Transform3D) -> Dictionary:
	return {"transform": at, "speed": 0.0, "vertical": 0.0, "steer": 0.0, "airborne": false, "motion": Vector3.ZERO}

# One tick of driving. `controls`: {throttle, steer, handbrake}. On the
# ground the vehicle speeds up or brakes along its nose and turns about its
# own up; in the air it only falls, keeping its speed. The new body's
# `motion` (world) is this tick's move: make it (with walls or not), then
# settle().
static func drive(body: Dictionary, controls: Dictionary, ground: Object, gravity: float, delta: float) -> Dictionary:
	var out := body.duplicate()
	var basis: Basis = body.transform.basis.orthonormalized()
	var origin: Vector3 = body.transform.origin
	var up: Vector3 = ground.up_at(origin)
	if body.airborne:
		out.vertical = body.vertical - gravity * delta
		out.motion = (_flat_nose(basis, up) * body.speed + up * out.vertical) * delta
		return out
	out.steer = next_steer(body.steer, controls.steer, delta)
	var nose := -basis.z
	var slope := asin(clampf(nose.dot(up), -1.0, 1.0))
	out.speed = next_speed(body.speed, controls.throttle, controls.handbrake, slope, gravity, delta)
	var turned := basis.rotated(basis.y, yaw_rate(out.speed, out.steer) * delta)
	out.transform = Transform3D(turned, origin)
	out.vertical = 0.0
	out.motion = -turned.z * out.speed * delta
	return out

# After the move. On the ground: put on it and leaned toward the plane under
# its four wheels; if the ground fell away more than AIR_GAP, off into the
# air with the speed it had (its climb becomes the vertical speed). In the
# air: levels out slowly, back on the ground once it reaches it.
static func settle(body: Dictionary, ground: Object, delta: float) -> Dictionary:
	var out := body.duplicate()
	var basis: Basis = body.transform.basis.orthonormalized()
	var origin: Vector3 = body.transform.origin
	var up: Vector3 = ground.up_at(origin)
	var height: float = ground.ground_altitude(origin)
	if not body.airborne and height > AIR_GAP:
		var rise: float = -basis.z.dot(up)
		out.airborne = true
		out.vertical = body.speed * rise
		out.speed = body.speed * sqrt(maxf(0.0, 1.0 - rise * rise))
	elif body.airborne and height <= 0.0:
		out.airborne = false
		out.vertical = 0.0
	if out.airborne:
		out.transform = Transform3D(_ease(basis, heading_basis(-basis.z, up), delta), origin)
		return out
	var on_ground := origin - up * height
	var lean := heading_basis(-basis.z, contact_normal(Transform3D(basis, on_ground), ground))
	out.transform = Transform3D(_ease(basis, lean, delta), on_ground)
	return out

# A basis with `up` as its y and `nose` (laid on the plane across `up`) as
# its -z.
static func heading_basis(nose: Vector3, up: Vector3) -> Basis:
	var y := up.normalized()
	var z := -(nose - y * nose.dot(y)).normalized()
	return Basis(y.cross(z), y, z)

# The ground's points under the four wheels of a vehicle at `at`: front
# left, front right, rear left, rear right.
static func contacts(at: Transform3D, ground: Object) -> Array:
	var points := []
	for corner in [Vector3(-HALF_TRACK, 0.0, -HALF_BASE), Vector3(HALF_TRACK, 0.0, -HALF_BASE), Vector3(-HALF_TRACK, 0.0, HALF_BASE), Vector3(HALF_TRACK, 0.0, HALF_BASE)]:
		var point: Vector3 = at * corner
		points.append(point - ground.up_at(point) * ground.ground_altitude(point))
	return points

# The ground's plane under the four wheels: the cross of its diagonals,
# turned up.
static func contact_normal(at: Transform3D, ground: Object) -> Vector3:
	var p := contacts(at, ground)
	var normal: Vector3 = ((p[1] as Vector3) - p[2]).cross((p[0] as Vector3) - p[3]).normalized()
	return normal if normal.dot(ground.up_at(at.origin)) >= 0.0 else -normal

static func _flat_nose(basis: Basis, up: Vector3) -> Vector3:
	var nose := -basis.z
	var flat := nose - up * nose.dot(up)
	return flat.normalized() if flat.length() > 1e-6 else nose

# Part of the way from `from` to `to`: all of it in SETTLE_TIME.
static func _ease(from: Basis, to: Basis, delta: float) -> Basis:
	return from.slerp(to.orthonormalized(), clampf(delta / SETTLE_TIME, 0.0, 1.0))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_ground_vehicle.gd`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ground_vehicle.gd tests/test_ground_vehicle.gd
git commit -m "Ground vehicle: on the ground, in the air, leaning on four wheels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Il rover sulla luna (nodo, modello, urti, toppa)

**Files:**
- Create: `scripts/rover_model.gd`, `scripts/moon_rover.gd`
- Modify: `scripts/moon.gd` (dopo `altitude()`), `project.godot` (sezione `[input]`)
- Test: `tests/test_moon_rover.gd`

**Interfaces:**
- Consumes: Task 1–2 (`GroundVehicle.new_body`, `drive`, `settle`, `heading_basis`, `wheel_angle`).
- Produces:
  - `moon.gd`: `ground_altitude(point: Vector3) -> float` (uguale ad `altitude`).
  - `moon_rover.gd` (`extends CharacterBody3D`):
    - `@export var moon_path: NodePath = NodePath("../PlanetSystem/Moon")`
    - `var ship: Node3D` (impostata da GameMode; null nei test)
    - `var body: Dictionary` (stato del nucleo), `var lights_on := true`
    - `var controls: Dictionary` — se non vuoto sostituisce la tastiera (per i test)
    - `const MOON_GRAVITY := 1.62`, `const BUMP_KEEP := 0.5`
    - `place(point: Vector3, nose: Vector3) -> void` — posa il rover sul suolo sotto `point`
    - `is_clear() -> bool` — il box del rover non tocca nulla
    - `speed() -> float` — `velocity.length()` (velocità rispetto alla luna)
    - `camera() -> Camera3D`
    - `set_board_prompt(shown: bool) -> void` (riempita in Task 4; qui vuota)
    - statica `look_after(look: Vector2, idle: float, delta: float) -> Vector2`
  - `rover_model.gd`: `static func build(rover: Node3D) -> void` crea `WheelFL`, `WheelFR`, `WheelRL`,
    `WheelRR` (ognuno con figlio `Spin`), `HeadlightL`, `HeadlightR`, e i pezzi del modello.

- [ ] **Step 1: Write the failing test**

`tests/test_moon_rover.gd`:

```gdscript
extends SceneTree

# The moon rover on the real moon, on a small scene: the planet, the moon,
# the rover and the world origin shift (no station, no ship).

const MoonScript = preload("res://scripts/moon.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const MoonRoverScript = preload("res://scripts/moon_rover.gd")
const WorldOriginRebaseScript = preload("res://scripts/world_origin_rebase.gd")

var _failures := 0
var _world: Node3D
var _moon: Node3D
var _rover: CharacterBody3D

func _initialize():
	_world = Node3D.new()
	_world.name = "World"
	root.add_child(_world)
	var system := Node3D.new()
	system.name = "PlanetSystem"
	system.position = Vector3(0.0, -4000.0, -6959600.0)
	_world.add_child(system)
	var planet := Node3D.new()
	planet.name = "Planet"
	system.add_child(planet)
	_moon = MoonScript.new()
	_moon.name = "Moon"
	system.add_child(_moon)
	_rover = MoonRoverScript.new()
	_rover.name = "MoonRover"
	_world.add_child(_rover)
	var rebase: Node = WorldOriginRebaseScript.new()
	rebase.name = "WorldOriginRebase"
	rebase.tracked_node = NodePath("../MoonRover")
	_world.add_child(rebase)
	await physics_frame
	await physics_frame

	_failures += await _test_rover_rests_on_the_ground_as_the_moon_moves()
	_failures += await _test_rover_drives_along_the_ground()
	_failures += await _test_rover_stops_at_a_base_wall()
	_failures += await _test_patch_follows_the_rover()
	_failures += _test_look_comes_back_after_a_pause()
	_failures += _test_lights_toggle()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# A point on the base's flat ground at (x, z) in its frame, `height` up.
func _at_base(x: float, z: float, height: float) -> Vector3:
	var r: float = MoonScript.ground_radius()
	return _moon.base_transform() * Vector3(x, sqrt(r * r - x * x - z * z) - r + height, z)

func _in_base(point: Vector3) -> Vector3:
	return _moon.base_transform().affine_inverse() * point

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame

func _test_rover_rests_on_the_ground_as_the_moon_moves() -> int:
	var point := _at_base(400.0, 150.0, 0.0)
	_rover.controls = {"throttle": 0.0, "steer": 0.0, "handbrake": false}
	_rover.place(point, _at_base(400.0, 0.0, 0.0) - point)
	await _ticks(2)
	var start := _in_base(_rover.global_position)
	await _ticks(600)
	var moved := _in_base(_rover.global_position).distance_to(start)
	var height: float = _moon.ground_altitude(_rover.global_position)
	if moved > 0.1 or absf(height) > 0.05:
		print("FAIL _test_rover_rests_on_the_ground_as_the_moon_moves: moved %.3f m in the base's frame, %.3f m over the ground" % [moved, height])
		return 1
	return 0

func _test_rover_drives_along_the_ground() -> int:
	var point := _at_base(400.0, 150.0, 0.0)
	_rover.place(point, _at_base(400.0, 0.0, 0.0) - point)
	await _ticks(2)
	var start := _in_base(_rover.global_position)
	_rover.controls = {"throttle": 1.0, "steer": 0.0, "handbrake": false}
	await _ticks(300)
	var gone := _in_base(_rover.global_position).distance_to(start)
	var height: float = _moon.ground_altitude(_rover.global_position)
	_rover.controls = {"throttle": 0.0, "steer": 0.0, "handbrake": true}
	await _ticks(200)
	# 5 s at 3 m/s²: 37.5 m.
	if absf(gone - 37.5) > 1.5 or absf(height) > 0.05 or _rover.speed() > 0.01:
		print("FAIL _test_rover_drives_along_the_ground: %.2f m in 5 s, %.3f m over the ground, %.2f m/s after the handbrake" % [gone, height, _rover.speed()])
		return 1
	return 0

# An outer ring sector spans 230..290 m from the tower, 25..70 degrees, 6 m
# high: drive at its outer wall at 35 degrees from 320 m.
func _test_rover_stops_at_a_base_wall() -> int:
	var out := Vector2.from_angle(deg_to_rad(35.0))
	var point := _at_base(out.x * 320.0, out.y * 320.0, 0.0)
	_rover.place(point, _at_base(out.x * 250.0, out.y * 250.0, 0.0) - point)
	await _ticks(2)
	_rover.controls = {"throttle": 1.0, "steer": 0.0, "handbrake": false}
	await _ticks(600)
	var at := _in_base(_rover.global_position)
	var reach := Vector2(at.x, at.z).length()
	_rover.controls = {"throttle": 0.0, "steer": 0.0, "handbrake": true}
	await _ticks(60)
	if reach < 290.0 or reach > 294.0:
		print("FAIL _test_rover_stops_at_a_base_wall: %.2f m from the tower (wall at 290)" % reach)
		return 1
	return 0

func _test_patch_follows_the_rover() -> int:
	var patch := _moon.get_node("Patch")
	if not patch.get("_active"):
		print("FAIL _test_patch_follows_the_rover: the moon's patch is not following anything")
		return 1
	return 0

func _test_look_comes_back_after_a_pause() -> int:
	var look := Vector2(deg_to_rad(90.0), deg_to_rad(30.0))
	var held := MoonRoverScript.look_after(look, 1.0, 0.1)
	var back := look
	for i in range(30):
		back = MoonRoverScript.look_after(back, 2.0, 1.0 / 60.0)
	if held != look or back.length() > 1e-6:
		print("FAIL _test_look_comes_back_after_a_pause: held %s, back %s" % [held, back])
		return 1
	return 0

func _test_lights_toggle() -> int:
	var light := _rover.get_node("HeadlightL") as Light3D
	var on_at_start := light.visible
	var event := InputEventAction.new()
	event.action = "lights"
	event.pressed = true
	_rover._unhandled_input(event)
	var off := not light.visible and not _rover.lights_on
	_rover._unhandled_input(event)
	if not on_at_start or not off or not light.visible:
		print("FAIL _test_lights_toggle: on %s, off after L %s, on again %s" % [on_at_start, off, light.visible])
		return 1
	return 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_moon_rover.gd`
Expected: errore di caricamento di `res://scripts/moon_rover.gd`.

- [ ] **Step 3: Write minimal implementation**

3a. `scripts/moon.gd`, subito dopo `altitude()`:

```gdscript
# The ground's height under `point`, as a ground vehicle asks for it
# (GroundVehicle).
func ground_altitude(point: Vector3) -> float:
	return altitude(point)
```

3b. `project.godot`, nella sezione `[input]` dopo il blocco `restart={...}`, due blocchi nello stesso formato
degli altri:

```
vehicle={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":86,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
lights={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":76,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

3c. `scripts/rover_model.gd`:

```gdscript
extends RefCounted

# The moon rover's looks, made of simple shapes in the Apollo rover's
# colours: a light grey frame, gold panels, black mesh wheels, a roll bar,
# an umbrella antenna. The origin is where the wheels touch the ground, -Z
# the nose. Seen only from the driver's seat: the dashboard, the bonnet,
# the front wheels and the roll bar's posts are what the camera shows.

const WHEEL_RADIUS := 0.4
const WHEEL_WIDTH := 0.25
const FRAME := Color(0.78, 0.78, 0.76)
const GOLD := Color(0.85, 0.65, 0.2)
const TYRE := Color(0.06, 0.06, 0.06)
const SCREEN := Color(0.03, 0.05, 0.06)

static func build(rover: Node3D) -> void:
	var frame := _material(FRAME, 0.6, 0.3)
	var gold := _material(GOLD, 0.35, 0.8)
	var tyre := _material(TYRE, 0.9, 0.0)
	var screen := _material(SCREEN, 0.2, 0.0)
	# Chassis, bonnet, rear deck.
	_box(rover, "Chassis", Vector3(1.6, 0.25, 3.1), Vector3(0.0, 0.65, 0.0), frame)
	_box(rover, "Bonnet", Vector3(1.5, 0.12, 0.5), Vector3(0.0, 0.84, -1.3), gold)
	_box(rover, "Deck", Vector3(1.5, 0.3, 0.7), Vector3(0.0, 0.92, 1.15), gold)
	# Dashboard with two dark screens, in front of the driver.
	_box(rover, "Dashboard", Vector3(1.1, 0.3, 0.12), Vector3(0.0, 1.0, -1.32), frame)
	_box(rover, "ScreenL", Vector3(0.35, 0.2, 0.02), Vector3(-0.25, 1.02, -1.255), screen)
	_box(rover, "ScreenR", Vector3(0.35, 0.2, 0.02), Vector3(0.25, 1.02, -1.255), screen)
	# Roll bar: two posts and a top bar over the seats.
	_box(rover, "PostL", Vector3(0.06, 0.95, 0.06), Vector3(-0.75, 1.25, -0.45), frame)
	_box(rover, "PostR", Vector3(0.06, 0.95, 0.06), Vector3(0.75, 1.25, -0.45), frame)
	_box(rover, "RollBar", Vector3(1.56, 0.06, 0.06), Vector3(0.0, 1.72, -0.45), frame)
	# Umbrella antenna behind.
	_box(rover, "Mast", Vector3(0.04, 0.9, 0.04), Vector3(0.5, 1.5, 1.3), frame)
	var dish := MeshInstance3D.new()
	dish.name = "Dish"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.45
	cone.height = 0.15
	dish.mesh = cone
	dish.material_override = gold
	dish.position = Vector3(0.5, 2.0, 1.3)
	rover.add_child(dish)
	# Wheels: a pivot (steers) holding a Spin node (rolls) holding the tyre.
	for wheel in [["WheelFL", -1.0, -1.0], ["WheelFR", 1.0, -1.0], ["WheelRL", -1.0, 1.0], ["WheelRR", 1.0, 1.0]]:
		var pivot := Node3D.new()
		pivot.name = wheel[0]
		pivot.position = Vector3(wheel[1] * 0.9, WHEEL_RADIUS, wheel[2] * 1.25)
		rover.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		var tyre_mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = WHEEL_RADIUS
		cylinder.bottom_radius = WHEEL_RADIUS
		cylinder.height = WHEEL_WIDTH
		cylinder.radial_segments = 16
		tyre_mesh.mesh = cylinder
		tyre_mesh.material_override = tyre
		tyre_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
		spin.add_child(tyre_mesh)
		# A gold hub, so the turning shows.
		_box(spin, "Hub", Vector3(WHEEL_WIDTH + 0.02, 0.5, 0.08), Vector3.ZERO, gold)

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
```

3d. `scripts/moon_rover.gd`:

```gdscript
extends CharacterBody3D

# The rover driven on the moon out of the landed void-cruiser
# (GroundVehicle does the driving, the moon is its ground). It lives in the
# moon's frame: every tick it turns with the moon by the moon's last step,
# as the ship does (void_cruiser.gd _follow_moon), then drives, bumps into
# Base Selene and the ship, and sits on the moon's ground (MoonTerrain, the
# same the patch draws round it). Seen from the driver's seat only.

const GroundVehicle = preload("res://scripts/ground_vehicle.gd")
const MoonOrbit = preload("res://scripts/moon_orbit.gd")
const RoverModel = preload("res://scripts/rover_model.gd")
const CockpitScript = preload("res://scripts/cockpit.gd")

const MOON_GRAVITY := 1.62
# A bump keeps half of what is left along the wall; head-on, nothing.
const BUMP_KEEP := 0.5
# The collision box, above the wheels so the ground's pebbles never stop it.
const BOX_SIZE := Vector3(1.8, 1.4, 3.1)
const BOX_CENTRE := Vector3(0.0, 1.1, 0.0)
const EYE := Vector3(0.0, 1.3, -0.95)
const CAMERA_HFOV := 90.0
const CAMERA_NEAR := 0.05
const HEADLIGHT_RANGE := 80.0
const HEADLIGHT_ENERGY := 4.0
const HEADLIGHT_ANGLE := 35.0
# Looking round with the mouse: so far each way, back ahead after a pause.
const LOOK_SENSITIVITY := 0.003
const LOOK_YAW := 2.0943951  # 120 degrees
const LOOK_PITCH := 1.0471976  # 60 degrees
const LOOK_IDLE := 1.5
const LOOK_RETURN_SPEED := 4.1887902  # 240 degrees/s: 120 degrees in 0.5 s

@export var moon_path: NodePath = NodePath("../PlanetSystem/Moon")

# Set by GameMode: the parked ship (null in tests).
var ship: Node3D
var body := {}
var lights_on := true
# When not empty, used instead of the keyboard (tests).
var controls := {}
var _look := Vector2.ZERO
var _look_idle := 0.0
var _wheel_roll := 0.0

func _ready() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = BOX_SIZE
	shape_node.shape = box
	shape_node.position = BOX_CENTRE
	add_child(shape_node)
	RoverModel.build(self)
	for side in [["HeadlightL", -0.6], ["HeadlightR", 0.6]]:
		var light := SpotLight3D.new()
		light.name = side[0]
		light.position = Vector3(side[1], 0.9, -1.6)
		light.spot_range = HEADLIGHT_RANGE
		light.spot_angle = HEADLIGHT_ANGLE
		light.light_energy = HEADLIGHT_ENERGY
		light.shadow_enabled = false
		add_child(light)
	var eye := Camera3D.new()
	eye.name = "Camera"
	eye.position = EYE
	eye.keep_aspect = Camera3D.KEEP_WIDTH
	eye.fov = CAMERA_HFOV
	eye.near = CAMERA_NEAR
	eye.far = CockpitScript.PILOT_FAR
	eye.current = true
	add_child(eye)
	if body.is_empty():
		body = GroundVehicle.new_body(global_transform if is_inside_tree() else transform)

func _moon() -> Node3D:
	if not is_inside_tree():
		return null
	var moon := get_node_or_null(moon_path) as Node3D
	return moon if moon != null and moon.is_inside_tree() else null

func camera() -> Camera3D:
	return get_node("Camera") as Camera3D

func speed() -> float:
	return velocity.length()

# On the ground under `point` (world), the nose toward `nose`, leaned onto
# the ground at once, standing still.
func place(point: Vector3, nose: Vector3) -> void:
	var moon := _moon()
	var up: Vector3 = moon.up_at(point)
	var on_ground: Vector3 = point - up * moon.ground_altitude(point)
	body = GroundVehicle.new_body(Transform3D(GroundVehicle.heading_basis(nose, up), on_ground))
	body = GroundVehicle.settle(body, moon, 1.0)
	global_transform = body.transform
	velocity = Vector3.ZERO

# Nothing in the way of the rover's box where it stands.
func is_clear() -> bool:
	var shape_node := get_node("CollisionShape3D") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

# The "V BOARD" line (rover_hud.gd, Task 4).
func set_board_prompt(_shown: bool) -> void:
	pass

func read_controls() -> Dictionary:
	if not controls.is_empty():
		return controls
	return {
		"throttle": Input.get_axis("move_backward", "move_forward"),
		"steer": Input.get_axis("move_left", "move_right"),
		"handbrake": Input.is_action_pressed("brake"),
	}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_look.x = clampf(_look.x - event.relative.x * LOOK_SENSITIVITY, -LOOK_YAW, LOOK_YAW)
		_look.y = clampf(_look.y - event.relative.y * LOOK_SENSITIVITY, -LOOK_PITCH, LOOK_PITCH)
		_look_idle = 0.0
	elif event.is_action_pressed("lights") and not event.is_echo():
		lights_on = not lights_on
		for light_name in ["HeadlightL", "HeadlightR"]:
			(get_node(light_name) as Light3D).visible = lights_on

# The look (yaw, pitch) after `idle` seconds without the mouse: held for
# LOOK_IDLE, then back ahead at LOOK_RETURN_SPEED.
static func look_after(look: Vector2, idle: float, delta: float) -> Vector2:
	if idle < LOOK_IDLE:
		return look
	return look.move_toward(Vector2.ZERO, LOOK_RETURN_SPEED * delta)

func _process(delta: float) -> void:
	_look_idle += delta
	_look = look_after(_look, _look_idle, delta)
	camera().rotation = Vector3(_look.y, _look.x, 0.0)
	if body.is_empty():
		return
	var speed_now: float = body.speed
	_wheel_roll -= speed_now * delta / RoverModel.WHEEL_RADIUS
	var angle := GroundVehicle.wheel_angle(speed_now, body.steer)
	for wheel in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var pivot := get_node(wheel) as Node3D
		if wheel.begins_with("WheelF"):
			pivot.rotation.y = angle
		(pivot.get_node("Spin") as Node3D).rotation.x = _wheel_roll

func _physics_process(delta: float) -> void:
	var moon := _moon()
	if moon == null or body.is_empty():
		return
	# With the moon first, by its own last step (see void_cruiser.gd).
	global_transform = MoonOrbit.spin(moon.axis(), moon.last_step, moon.planet_centre()) * global_transform
	body.transform = global_transform
	body = GroundVehicle.drive(body, read_controls(), moon, MOON_GRAVITY, delta)
	global_transform = body.transform
	var start := global_position
	var hit := move_and_collide(body.motion)
	if hit != null:
		var normal := hit.get_normal()
		var nose := -global_transform.basis.z.normalized()
		body.speed *= BUMP_KEEP * (1.0 - absf(nose.dot(normal)))
		move_and_collide(hit.get_remainder().slide(normal) * BUMP_KEEP)
	body.transform = global_transform
	body = GroundVehicle.settle(body, moon, delta)
	global_transform = body.transform
	velocity = (global_position - start) / delta
	moon.follow_patch(global_position, true, velocity)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_moon_rover.gd`
Expected: `ALL TESTS PASSED`. Se `_test_rover_stops_at_a_base_wall` legge meno di 290 m, il box passa dentro
il muro: controllare che `move_and_collide` riceva lo spostamento intero e che `settle` non lo sposti dentro
(il suolo della base è piano, quindi `settle` cambia solo la quota).

- [ ] **Step 5: Commit**

```bash
git add scripts/moon.gd scripts/rover_model.gd scripts/moon_rover.gd project.godot tests/test_moon_rover.gd
git commit -m "Moon rover: drives on the moon's ground, turns with the moon, bumps into the base

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: HUD del rover e regole di uscita/risalita

**Files:**
- Create: `scripts/rover_hud.gd`, `scripts/rover_rules.gd`
- Modify: `scripts/moon_rover.gd` (`_ready`, `_process`, `set_board_prompt`)
- Test: `tests/test_rover_hud.gd`, `tests/test_rover_rules.gd`

**Interfaces:**
- Consumes: Task 3 (`moon_rover.gd`: `ship`, `body`, `lights_on`, `camera()`, `_moon()`).
- Produces:
  - `rover_hud.gd` (`extends CanvasLayer`):
    - `static func readout(speed: float, heading_deg: float, slope_deg: float, altitude: float, lights: bool) -> Dictionary` → chiavi `spd`, `hdg`, `slope`, `alt`, `lights`
    - `static func heading(nose: Vector3, up: Vector3, pole: Vector3) -> float` (gradi 0..360, 0 = nord, 90 = est)
    - `func show_readout(lines: Dictionary) -> void`, `func set_board_prompt(shown: bool) -> void`,
      `func update_markers(camera: Camera3D, ship_at: Variant, beacon_at: Vector3) -> void`
      (`ship_at` = `Vector3` o `null`)
    - nodi `Panel/Lines/{SpdLabel,HdgLabel,SlopeLabel,AltLabel,LightsLabel}`, `BoardLabel`, `ShipMarker`,
      `SeleneMarker`
  - `rover_rules.gd`:
    - costanti `SIDE_OFFSET := 15.0`, `PAD_OFFSET := 52.0`, `BOARD_DISTANCE := 30.0`,
      `PAD_BOARD_DISTANCE := 60.0`, `BOARD_SPEED := 1.0`
    - `static func spawn_spots(ship: Transform3D, up: Vector3, on_pad: bool, pad_centre: Vector3) -> Array`
      (4 punti: destra, sinistra, dietro, davanti)
    - `static func can_board(rover: Vector3, speed: float, ship: Vector3, on_pad: bool, pad_centre: Vector3) -> bool`

- [ ] **Step 1: Write the failing tests**

`tests/test_rover_rules.gd`:

```gdscript
extends SceneTree

# Where the rover comes out of the ship and when the pilot can board again.

const RoverRules = preload("res://scripts/rover_rules.gd")

func _init():
	var failures := 0
	failures += _test_spots_beside_the_ship()
	failures += _test_spots_clear_of_the_pad()
	failures += _test_board_near_and_slow()
	failures += _test_board_by_the_pad()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_spots_beside_the_ship() -> int:
	# Ship nose -Z, right +X, tilted a little: the spots lie on the level.
	var ship := Transform3D(Basis(Vector3.FORWARD, 0.1), Vector3(100.0, 5.0, 0.0))
	var spots := RoverRules.spawn_spots(ship, Vector3.UP, false, Vector3.ZERO)
	var expected := [Vector3(115.0, 5.0, 0.0), Vector3(85.0, 5.0, 0.0), Vector3(100.0, 5.0, 15.0), Vector3(100.0, 5.0, -15.0)]
	for i in range(4):
		if (spots[i] as Vector3).distance_to(expected[i]) > 1e-3:
			print("FAIL _test_spots_beside_the_ship: %s" % [spots])
			return 1
	return 0

func _test_spots_clear_of_the_pad() -> int:
	# Ship 10 m off the pad's centre toward a corner: every spot past the
	# square's corners (30 * sqrt 2 = 42.4 m from the centre).
	var ship := Transform3D(Basis(), Vector3(7.0, 2.0, 7.0))
	var spots := RoverRules.spawn_spots(ship, Vector3.UP, true, Vector3(0.0, 2.0, 0.0))
	for spot in spots:
		var flat := Vector2(spot.x, spot.z)
		if absf(flat.x) <= 30.0 and absf(flat.y) <= 30.0 or flat.length() < 52.0 - 1e-3:
			print("FAIL _test_spots_clear_of_the_pad: %s" % spot)
			return 1
	return 0

func _test_board_near_and_slow() -> int:
	var ship := Vector3.ZERO
	var near_slow := RoverRules.can_board(Vector3(29.0, 0.0, 0.0), 0.5, ship, false, Vector3.ZERO)
	var far := RoverRules.can_board(Vector3(31.0, 0.0, 0.0), 0.5, ship, false, Vector3.ZERO)
	var fast := RoverRules.can_board(Vector3(10.0, 0.0, 0.0), 1.0, ship, false, Vector3.ZERO)
	if not near_slow or far or fast:
		print("FAIL _test_board_near_and_slow: near and slow %s, far %s, fast %s" % [near_slow, far, fast])
		return 1
	return 0

func _test_board_by_the_pad() -> int:
	var pad := Vector3(0.0, 2.0, 0.0)
	var by_pad := RoverRules.can_board(Vector3(55.0, 0.0, 0.0), 0.0, pad, true, pad)
	var away := RoverRules.can_board(Vector3(65.0, 0.0, 0.0), 0.0, pad, true, pad)
	if not by_pad or away:
		print("FAIL _test_board_by_the_pad: by the pad %s, away %s" % [by_pad, away])
		return 1
	return 0
```

`tests/test_rover_hud.gd`:

```gdscript
extends SceneTree

# The rover's HUD: its lines, the heading, the board prompt.

const RoverHud = preload("res://scripts/rover_hud.gd")

func _initialize():
	var failures := 0
	failures += _test_lines()
	failures += _test_heading()
	failures += await _test_board_prompt_and_panel()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_lines() -> int:
	var r := RoverHud.readout(15.0, 273.4, 12.2, -1240.4, true)
	var back := RoverHud.readout(-3.0, 0.0, 0.0, 15.0, false)
	if r.spd != "SPD  54 km/h  15.0 m/s" or r.hdg != "HDG  273°" or r.slope != "SLOPE  12°" or r.alt != "ALT  -1240 m" or r.lights != "LIGHTS ON" or back.spd != "SPD  11 km/h  3.0 m/s" or back.hdg != "HDG  000°" or back.lights != "LIGHTS OFF":
		print("FAIL _test_lines: %s / %s" % [r, back])
		return 1
	return 0

func _test_heading() -> int:
	# Pole +Y, standing on the +Z side (up +Z): north is +Y, east is +X.
	var pole := Vector3.UP
	var up := Vector3.BACK
	var north := RoverHud.heading(Vector3.UP, up, pole)
	var east := RoverHud.heading(Vector3.RIGHT, up, pole)
	var west := RoverHud.heading(Vector3.LEFT, up, pole)
	if absf(north) > 1e-3 or absf(east - 90.0) > 1e-3 or absf(west - 270.0) > 1e-3:
		print("FAIL _test_heading: north %.2f, east %.2f, west %.2f" % [north, east, west])
		return 1
	return 0

func _test_board_prompt_and_panel() -> int:
	var hud: CanvasLayer = RoverHud.new()
	root.add_child(hud)
	await process_frame
	hud.show_readout(RoverHud.readout(5.0, 90.0, 3.0, 10.0, true))
	hud.set_board_prompt(true)
	var board := hud.get_node("BoardLabel") as Control
	var spd := hud.get_node("Panel/Lines/SpdLabel") as Label
	var shown := board.visible
	hud.set_board_prompt(false)
	var result := 0
	if not shown or board.visible or spd.text != "SPD  18 km/h  5.0 m/s":
		print("FAIL _test_board_prompt_and_panel: prompt %s then %s, speed line '%s'" % [shown, board.visible, spd.text])
		result = 1
	hud.free()
	return result
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_rover_rules.gd` e
`~/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_rover_hud.gd`
Expected: errori di caricamento (`rover_rules.gd`, `rover_hud.gd` non esistono).

- [ ] **Step 3: Write minimal implementation**

`scripts/rover_rules.gd`:

```gdscript
extends RefCounted

# Where the rover comes out of the landed ship, and when the pilot can
# board again. On a pad (a 60 m square, 2 m high, which the rover cannot
# climb) both count from the pad's centre instead of the ship.

const SIDE_OFFSET := 15.0
# Past the pad's corners (30 * sqrt 2 = 42.4 m) with room to spare.
const PAD_OFFSET := 52.0
const BOARD_DISTANCE := 30.0
const PAD_BOARD_DISTANCE := 60.0
const BOARD_SPEED := 1.0

# Where the rover may come out, first choice first: right of the ship,
# left, behind, ahead, on the level across `up`.
static func spawn_spots(ship: Transform3D, up: Vector3, on_pad: bool, pad_centre: Vector3) -> Array:
	var right := _flat(ship.basis.x, up)
	var nose := _flat(-ship.basis.z, up)
	var from := pad_centre if on_pad else ship.origin
	var reach := PAD_OFFSET if on_pad else SIDE_OFFSET
	var spots := []
	for direction in [right, -right, -nose, nose]:
		spots.append(from + direction * reach)
	return spots

static func can_board(rover: Vector3, speed: float, ship: Vector3, on_pad: bool, pad_centre: Vector3) -> bool:
	if speed >= BOARD_SPEED:
		return false
	if on_pad:
		return rover.distance_to(pad_centre) <= PAD_BOARD_DISTANCE
	return rover.distance_to(ship) <= BOARD_DISTANCE

static func _flat(direction: Vector3, up: Vector3) -> Vector3:
	return (direction - up * direction.dot(up)).normalized()
```

`scripts/rover_hud.gd`:

```gdscript
extends CanvasLayer

# The rover's HUD, in the ship's HUD style (cockpit.gd): top left the ROVER
# panel (speed, heading, slope, altitude, lights), top centre "V BOARD"
# when the pilot can board, and markers on the parked ship and on Base
# Selene's beacon (beacon_marker.gd).

const CockpitScript = preload("res://scripts/cockpit.gd")
const BeaconMarkerScript = preload("res://scripts/beacon_marker.gd")

const LINES := {
	"spd": "SpdLabel",
	"hdg": "HdgLabel",
	"slope": "SlopeLabel",
	"alt": "AltLabel",
	"lights": "LightsLabel",
}
const SHIP_MARKER_COLOR := Color(0.4, 0.95, 1.0, 0.95)

static func readout(speed: float, heading_deg: float, slope_deg: float, altitude: float, lights: bool) -> Dictionary:
	return {
		"spd": "SPD  %d km/h  %.1f m/s" % [roundi(absf(speed) * 3.6), absf(speed)],
		"hdg": "HDG  %03d°" % posmod(roundi(heading_deg), 360),
		"slope": "SLOPE  %d°" % roundi(slope_deg),
		"alt": "ALT  %d m" % roundi(altitude),
		"lights": "LIGHTS ON" if lights else "LIGHTS OFF",
	}

# The heading of `nose` (degrees, 0 north, 90 east) where the local up is
# `up`, north toward `pole`.
static func heading(nose: Vector3, up: Vector3, pole: Vector3) -> float:
	var north := (pole - up * pole.dot(up)).normalized()
	var east := north.cross(up)
	return fposmod(rad_to_deg(atan2(nose.dot(east), nose.dot(north))), 360.0)

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(CockpitScript.HUD_MARGIN, CockpitScript.HUD_MARGIN)
	panel.add_theme_stylebox_override("panel", _background())
	add_child(panel)
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	panel.add_child(lines)
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "ROVER"
	title.label_settings = _settings()
	lines.add_child(title)
	for key in LINES:
		var label := Label.new()
		label.name = LINES[key]
		label.label_settings = _settings()
		lines.add_child(label)
	var board := PanelContainer.new()
	board.name = "BoardLabel"
	board.anchor_left = 0.5
	board.anchor_right = 0.5
	board.offset_top = CockpitScript.HUD_MARGIN
	board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	board.add_theme_stylebox_override("panel", _background())
	var text := Label.new()
	text.text = "V BOARD"
	text.label_settings = _settings()
	board.add_child(text)
	board.visible = false
	add_child(board)
	var ship_marker: Control = BeaconMarkerScript.new()
	ship_marker.name = "ShipMarker"
	ship_marker.prefix = "SHIP"
	ship_marker.color = SHIP_MARKER_COLOR
	ship_marker.label_offset = BeaconMarkerScript.LABEL_UP_LEFT
	add_child(ship_marker)
	var selene: Control = BeaconMarkerScript.new()
	selene.name = "SeleneMarker"
	add_child(selene)

func show_readout(lines: Dictionary) -> void:
	for key in LINES:
		(get_node("Panel/Lines/" + LINES[key]) as Label).text = lines[key]

func set_board_prompt(shown: bool) -> void:
	(get_node("BoardLabel") as Control).visible = shown

# The ship's marker at `ship_at` (a Vector3, or null without a ship) and
# Selene's at `beacon_at`, seen by `camera`.
func update_markers(camera: Camera3D, ship_at: Variant, beacon_at: Vector3) -> void:
	var ship_marker := get_node("ShipMarker")
	if ship_at == null:
		ship_marker.update_target(camera, Vector3.ZERO, 0.0, false)
	else:
		ship_marker.update_target(camera, ship_at, camera.global_position.distance_to(ship_at), true)
	get_node("SeleneMarker").update_target(camera, beacon_at, camera.global_position.distance_to(beacon_at), true)

func _settings() -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = CockpitScript.HUD_FONT_SIZE
	settings.font_color = CockpitScript.HUD_TEXT_COLOR
	return settings

func _background() -> StyleBoxFlat:
	var background := StyleBoxFlat.new()
	background.bg_color = CockpitScript.HUD_BACKGROUND_COLOR
	background.set_corner_radius_all(6)
	background.set_content_margin_all(CockpitScript.HUD_PADDING)
	return background
```

In `scripts/moon_rover.gd`:

- aggiungi `const RoverHud = preload("res://scripts/rover_hud.gd")` fra le costanti;
- in fondo a `_ready()`:

```gdscript
	var hud: CanvasLayer = RoverHud.new()
	hud.name = "Hud"
	add_child(hud)
```

- sostituisci `set_board_prompt`:

```gdscript
# "V BOARD" at the top centre (GameMode decides when).
func set_board_prompt(shown: bool) -> void:
	(get_node("Hud") as CanvasLayer).set_board_prompt(shown)
```

- in fondo a `_process(delta)` (dopo le ruote):

```gdscript
	var moon := _moon()
	if moon == null:
		return
	var up: Vector3 = moon.up_at(global_position)
	var basis := global_transform.basis.orthonormalized()
	var pole: Vector3 = moon.global_transform.basis.y.normalized()
	var slope := rad_to_deg(acos(clampf(basis.y.dot(up), -1.0, 1.0)))
	var altitude: float = moon.to_local(global_position).length() - MoonOrbit.RADIUS
	var hud := get_node("Hud") as CanvasLayer
	hud.show_readout(RoverHud.readout(body.speed, RoverHud.heading(-basis.z, up, pole), slope, altitude, lights_on))
	hud.update_markers(camera(), ship.global_position if is_instance_valid(ship) else null, moon.beacon_position())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `test_rover_rules.gd`, `test_rover_hud.gd`, e di nuovo `test_moon_rover.gd` (l'HUD ora c'è dentro il
rover). Expected: `ALL TESTS PASSED` per tutti e tre.

- [ ] **Step 5: Commit**

```bash
git add scripts/rover_hud.gd scripts/rover_rules.gd scripts/moon_rover.gd tests/test_rover_hud.gd tests/test_rover_rules.gd
git commit -m "Moon rover: HUD (speed, heading, slope, altitude, ship and Selene markers) and the rules to come out and board

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Scambio nave ↔ rover con V

**Files:**
- Modify: `scripts/void_cruiser.gd` (variabili, `_physics_process`, nuova `park()`)
- Modify: `scripts/landing_readout.gd`, `scripts/cockpit.gd` (`MOON_LINES`)
- Modify: `scripts/moon_patch.gd` (`last_point`)
- Modify: `scripts/game_mode.gd`
- Test: `tests/test_landing_readout.gd`, `tests/test_game_mode.gd`

**Interfaces:**
- Consumes: Task 3 (`MoonRover`: `moon_path`, `ship`, `place()`, `is_clear()`, `speed()`, `camera()`,
  `controls`, `set_board_prompt()`), Task 4 (`RoverRules.spawn_spots`, `RoverRules.can_board`).
- Produces:
  - `void_cruiser.gd`: `var parked := false`, `func park(on: bool) -> void`.
  - `landing_readout.gd`: chiave `hint` (`"V ROVER"` se atterrati, altrimenti `""`).
  - `game_mode.gd`: `Mode.ROVER`, `leave_ship()`, `board_ship()`, `rover() -> CharacterBody3D`,
    `@export var rebase_path: NodePath = NodePath("../WorldOriginRebase")`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_landing_readout.gd` aggiungi a `_init` `failures += _test_rover_hint()` e:

```gdscript
func _test_rover_hint() -> int:
	var landed := LandingReadout.readout(0.0, 0.0, 0.0, 0.0, 1, true)
	var flying := LandingReadout.readout(50.0, -1.0, 0.0, 0.0, 1, false)
	if landed.hint != "V ROVER" or flying.hint != "":
		print("FAIL _test_rover_hint: landed '%s', flying '%s'" % [landed.hint, flying.hint])
		return 1
	return 0
```

In `tests/test_game_mode.gd` aggiungi, in `_initialize` **prima** di
`_test_outside_world_is_freed_if_the_scene_goes_while_inside()`:

```gdscript
	_failures += await _test_vehicle_key_in_flight_does_nothing()
	_failures += await _test_rover_comes_out_clear_of_the_pad()
	_failures += await _test_parked_ship_ignores_its_keys()
	_failures += await _test_parked_ship_leaves_the_patch_to_the_rover()
	_failures += await _test_rebase_follows_the_rover()
	_failures += await _test_vehicle_key_far_from_the_ship_does_nothing()
	_failures += await _test_vehicle_key_by_the_ship_boards_it()
```

e le funzioni (con gli helper):

```gdscript
func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_game_mode._unhandled_input(event)

func _moon() -> Node3D:
	return _scene.get_node("PlanetSystem/Moon")

# The ship landed on pad 1, carried with the moon (its physics on).
func _land_on_pad_1() -> void:
	var pad: Transform3D = _moon().pad_transform(1)
	_void_cruiser.set_physics_process(true)
	_void_cruiser.land_at(Transform3D(pad.basis, pad.origin + pad.basis.y.normalized() * _void_cruiser.HALF_HEIGHT))
	await physics_frame
	await physics_frame

func _test_vehicle_key_in_flight_does_nothing() -> int:
	_void_cruiser.is_landed = false
	_press("vehicle")
	await _wait_for_transition()
	if _game_mode.mode != _game_mode.Mode.VOID or _game_mode.rover() != null:
		print("FAIL _test_vehicle_key_in_flight_does_nothing: mode %d" % _game_mode.mode)
		return 1
	return 0

func _test_rover_comes_out_clear_of_the_pad() -> int:
	await _land_on_pad_1()
	_press("vehicle")
	await _wait_for_transition()
	var rover: CharacterBody3D = _game_mode.rover()
	if _game_mode.mode != _game_mode.Mode.ROVER or rover == null:
		print("FAIL _test_rover_comes_out_clear_of_the_pad: mode %d, rover %s" % [_game_mode.mode, rover])
		return 1
	var pad: Transform3D = _moon().pad_transform(1)
	var from_pad: float = rover.global_position.distance_to(pad.origin)
	var height: float = _moon().ground_altitude(rover.global_position)
	if from_pad < 45.0 or from_pad > 60.0 or absf(height) > 0.05 or not rover.is_clear() or not rover.camera().current:
		print("FAIL _test_rover_comes_out_clear_of_the_pad: %.1f m from the pad, %.3f m over the ground, clear %s, camera %s" % [from_pad, height, rover.is_clear(), rover.camera().current])
		return 1
	return 0

func _test_parked_ship_ignores_its_keys() -> int:
	var hud := _void_cruiser.get_node("Cockpit/Hud") as CanvasLayer
	_void_cruiser._unhandled_input(_action_event("brake"))
	_void_cruiser._unhandled_input(_action_event("cruise"))
	if not _void_cruiser.parked or _void_cruiser.is_processing_unhandled_input() or hud.visible:
		print("FAIL _test_parked_ship_ignores_its_keys: parked %s, input on %s, HUD shown %s" % [_void_cruiser.parked, _void_cruiser.is_processing_unhandled_input(), hud.visible])
		return 1
	return 0

func _action_event(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event

func _test_parked_ship_leaves_the_patch_to_the_rover() -> int:
	# The rover 200 m off: the patch must follow it, not the ship.
	var rover: CharacterBody3D = _game_mode.rover()
	var away: Vector3 = rover.global_position + rover.global_transform.basis.x * 200.0
	rover.place(away, -rover.global_transform.basis.z)
	await physics_frame
	await physics_frame
	var patch := _moon().get_node("Patch")
	var target: Vector3 = _moon().global_transform.affine_inverse() * rover.global_position
	var followed: Vector3 = patch.last_point
	if followed.distance_to(target) > 50.0:
		print("FAIL _test_parked_ship_leaves_the_patch_to_the_rover: the patch follows %.0f m from the rover" % followed.distance_to(target))
		return 1
	return 0

func _test_rebase_follows_the_rover() -> int:
	var rebase := _scene.get_node("WorldOriginRebase")
	var tracked: Node = rebase.get_node(rebase.tracked_node)
	if tracked != _game_mode.rover():
		print("FAIL _test_rebase_follows_the_rover: the world origin follows %s" % tracked.name)
		return 1
	return 0

func _test_vehicle_key_far_from_the_ship_does_nothing() -> int:
	var rover: CharacterBody3D = _game_mode.rover()
	var pad: Transform3D = _moon().pad_transform(1)
	var out: Vector3 = (rover.global_position - pad.origin).normalized()
	rover.place(pad.origin + out * 100.0, -rover.global_transform.basis.z)
	await physics_frame
	await physics_frame
	_press("vehicle")
	await _wait_for_transition()
	if _game_mode.mode != _game_mode.Mode.ROVER:
		print("FAIL _test_vehicle_key_far_from_the_ship_does_nothing: mode %d" % _game_mode.mode)
		return 1
	return 0

func _test_vehicle_key_by_the_ship_boards_it() -> int:
	var rover: CharacterBody3D = _game_mode.rover()
	var pad: Transform3D = _moon().pad_transform(1)
	var out: Vector3 = (rover.global_position - pad.origin).normalized()
	rover.place(pad.origin + out * 50.0, -rover.global_transform.basis.z)
	await physics_frame
	await physics_frame
	_press("vehicle")
	await _wait_for_transition()
	var pilot := _void_cruiser.get_node("Cockpit/PilotCamera") as Camera3D
	var result := 0
	if _game_mode.mode != _game_mode.Mode.VOID or _game_mode.rover() != null or _void_cruiser.parked or not pilot.current or not _void_cruiser.is_landed:
		print("FAIL _test_vehicle_key_by_the_ship_boards_it: mode %d, parked %s, pilot camera %s, landed %s" % [_game_mode.mode, _void_cruiser.parked, pilot.current, _void_cruiser.is_landed])
		result = 1
	_void_cruiser.set_physics_process(false)
	_void_cruiser.is_landed = false
	_void_cruiser.in_moon_frame = false
	return result
```


- [ ] **Step 2: Run tests to verify they fail**

Run: `test_landing_readout.gd` → `FAIL _test_rover_hint` (o errore sulla chiave `hint`).
Run: `test_game_mode.gd` → `SCRIPT ERROR` (`rover()` non esiste in GameMode). Il test carica la scena intera:
ci vuole circa un minuto.

- [ ] **Step 3: Write minimal implementation**

5a. `scripts/landing_readout.gd`, nel dizionario restituito da `readout()` dopo `"status": status,`:

```gdscript
		# Landed, the rover can come out (GameMode, V).
		"hint": "V ROVER" if landed else "",
```

5b. `scripts/cockpit.gd`, in `MOON_LINES` dopo `"status": "StatusLabel",`:

```gdscript
	"hint": "HintLabel",
```

(`update_moon` nasconde già da sola le righe vuote.)

5b2. `scripts/moon_patch.gd`: fra le variabili, dopo `var _active := false`:

```gdscript
# Where it was last told to follow (moon axes).
var last_point := Vector3.ZERO
```

e come prima riga di `follow()`:

```gdscript
	last_point = point
```

5c. `scripts/void_cruiser.gd`:

- accanto a `var is_landed := false`:

```gdscript
# Parked while the pilot drives the moon rover (GameMode): see park().
var parked := false
```

- in `_physics_process`, subito dopo `_follow_moon()`:

```gdscript
	# Parked, the ship only turns with the moon: no flying, and the moon's
	# patch is the rover's.
	if parked:
		return
```

- nuova funzione dopo `land_at()`:

```gdscript
# Parked while the pilot is out in the rover: no keys, no mouse, no HUD;
# still carried with the moon. Off again when the pilot boards.
func park(on: bool) -> void:
	parked = on
	set_process_unhandled_input(not on)
	_mouse_delta = Vector2.ZERO
	_forward_hold_time = 0.0
	var hud := get_node_or_null("Cockpit/Hud") as CanvasLayer
	if hud != null:
		hud.visible = not on
```

5d. `scripts/game_mode.gd`:

- costanti e variabili:

```gdscript
const MoonRoverScript = preload("res://scripts/moon_rover.gd")
const RoverRules = preload("res://scripts/rover_rules.gd")
const MoonBase = preload("res://scripts/moon_base.gd")
```

```gdscript
enum Mode { VOID, INTERIOR, ROVER }
```

```gdscript
@export var rebase_path: NodePath = NodePath("../WorldOriginRebase")
```

```gdscript
var _rover: CharacterBody3D
```

- in `_process`, dopo il ramo `elif _interior:` aggiungi prima di esso il caso rover (l'ordine dei rami
  diventa VOID / ROVER / interno):

```gdscript
	elif mode == Mode.ROVER:
		if _rover != null:
			_rover.set_board_prompt(_can_board_now())
```

- in `_unhandled_input`, sostituisci la riga
  `if _transitioning or not event.is_action_pressed("dock"):` con:

```gdscript
	if _transitioning:
		return
	if event.is_action_pressed("vehicle"):
		if mode == Mode.VOID and _can_leave_ship_now():
			_transition(leave_ship)
		elif mode == Mode.ROVER and _can_board_now():
			_transition(board_ship)
		return
	if not event.is_action_pressed("dock"):
```

- nuove funzioni, dopo `_can_undock_now()`:

```gdscript
func rover() -> CharacterBody3D:
	return _rover

# Landed on the moon, the rover can come out.
func _can_leave_ship_now() -> bool:
	return _void_cruiser.is_landed and _void_cruiser.in_moon_frame and not _void_cruiser.is_crashed and _void_cruiser.moon_node() != null

func _can_board_now() -> bool:
	if _rover == null:
		return false
	var pad := _ship_pad()
	return RoverRules.can_board(_rover.global_position, _rover.speed(), _void_cruiser.global_position, not pad.is_empty(), pad.get("centre", Vector3.ZERO))

# The pad the landed ship sits on: {centre (its top's centre, world)}, or
# empty when it sits on the bare ground.
func _ship_pad() -> Dictionary:
	var target: Dictionary = _void_cruiser.landing_target()
	if target.is_empty():
		return {}
	var pad: Transform3D = target.pad
	var up: Vector3 = pad.basis.y.normalized()
	var offset: Vector3 = _void_cruiser.global_position - pad.origin
	var across: Vector3 = offset - up * offset.dot(up)
	return {"centre": pad.origin} if across.length() < MoonBase.PAD_RADIUS * sqrt(2.0) else {}

# Out of the ship into the rover: beside the ship (or clear of its pad), in
# the first spot with nothing in the way; the ship parked; the rover's eyes
# and the world origin with the rover.
func leave_ship() -> void:
	var moon: Node3D = _void_cruiser.moon_node()
	var ship := _void_cruiser.global_transform.orthonormalized()
	var up: Vector3 = moon.up_at(ship.origin)
	var pad := _ship_pad()
	var spots := RoverRules.spawn_spots(ship, up, not pad.is_empty(), pad.get("centre", Vector3.ZERO))
	_rover = MoonRoverScript.new()
	_rover.name = "MoonRover"
	_rover.ship = _void_cruiser
	get_parent().add_child(_rover)
	_rover.moon_path = _rover.get_path_to(moon)
	for spot in spots:
		_rover.place(spot, -ship.basis.z)
		if _rover.is_clear():
			break
	_void_cruiser.park(true)
	_rover.camera().make_current()
	_track(_rover)
	mode = Mode.ROVER

# Back into the ship: the rover gone, the ship's controls and eyes back.
func board_ship() -> void:
	get_parent().remove_child(_rover)
	_rover.free()
	_rover = null
	_void_cruiser.park(false)
	var pilot_camera := _void_cruiser.get_node_or_null("Cockpit/PilotCamera") as Camera3D
	if pilot_camera:
		pilot_camera.make_current()
	_track(_void_cruiser)
	mode = Mode.VOID

# The world origin shift follows `node`.
func _track(node: Node3D) -> void:
	var rebase := get_node_or_null(rebase_path)
	if rebase != null:
		rebase.tracked_node = rebase.get_path_to(node)
```

Nota: `is_clear()` interroga lo spazio fisico subito dopo `place()`. La base è già al suo posto (`moon.gd
_place()` la sposta con `PhysicsServer3D.body_set_state` a ogni tick). Se il test dice "non libero" dove non
c'è niente, stampare cosa tocca (`intersect_shape(query, 1)[0].collider.name`) prima di cambiare codice.

- [ ] **Step 4: Run tests to verify they pass**

Run: `test_landing_readout.gd`, `test_game_mode.gd`, `test_cockpit.gd`, `test_cockpit_in_tree.gd` (gli ultimi
due perché `MOON_LINES` è cambiato). Expected: `ALL TESTS PASSED` per tutti.

- [ ] **Step 5: Commit**

```bash
git add scripts/void_cruiser.gd scripts/landing_readout.gd scripts/cockpit.gd scripts/game_mode.gd scripts/moon_patch.gd tests/test_landing_readout.gd tests/test_game_mode.gd
git commit -m "V on the moon: out of the landed ship into the rover, and back in by the ship

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Prova sulla GPU e note

**Files:**
- Create (temporaneo, poi cancellato): `tests/zz_probe.gd`
- Modify: `docs/superpowers/specs/2026-10-04-moon-rover-design.md` (sezione finale "Cambiato durante
  l'esecuzione")

- [ ] **Step 1: Scrivere la prova**

`tests/zz_probe.gd` (finestra visibile, non headless): carica `res://scenes/torus1_system.tscn`, posa la
nave su pad 1 con `land_at` come in `_land_on_pad_1()` del Task 5, chiama `GameMode.leave_ship()`, aspetta
60 frame, salva `get_root().get_texture().get_image().save_png("<scratchpad>/rover_base.png")`; poi
`rover.place()` a 5 km dalla base (`moon.base_transform() * Vector3(5000, 0, 0)`), `controls =
{"throttle": 1.0, "steer": 0.3, "handbrake": false}`, 180 frame, salva `rover_crater.png`; poi spegne il sole
(`SunLight.visible = false`) e salva `rover_dark_lights.png`. `quit()`.

- [ ] **Step 2: Lanciarla e guardare i PNG**

Run: `~/Godot_v4.6.1-stable-double_linux.x86_64 --path . -s tests/zz_probe.gd`
Controllare: cruscotto e ruote anteriori visibili e non tagliati; orizzonte e base giusti; HUD a sinistra con
valori sensati; marcatori SHIP e SELENE; fari che illuminano il suolo al buio. Se qualcosa non va: correggere,
rilanciare il test del pezzo toccato.

- [ ] **Step 3: Cancellare la prova, scrivere le note, commit**

```bash
rm tests/zz_probe.gd
```

Aggiungere in fondo alla spec una sezione `## Cambiato durante l'esecuzione` con quello che è cambiato
rispetto al progetto (anche "niente").

```bash
git add docs/superpowers/specs/2026-10-04-moon-rover-design.md
git commit -m "MoonRover: notes after the GPU check

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
