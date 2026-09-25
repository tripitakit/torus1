# Orbital Flight and Flight Assist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the void-cruiser a switchable flight assist (Tab) and real orbital forces in the frame of a ring orbiting at ~840 m/s, with an orbit HUD and the predicted orbit drawn in space.

**Architecture:** A new pure `orbital_frame.gd` holds the physics: acceleration in the frame turning with the ring (gravity + centrifugal + Coriolis), inertial velocity, Kepler orbit (periapsis/apoapsis) and points along the orbit. `flying_craft.gd` gains three hooks (`_linear_damping_now`, `_angular_damping_now`, `_external_acceleration`). `void_cruiser.gd` uses them: flight assist on = today's arcade flight, off = no damping and no ramp; orbital forces always, read from the `Planet` node every tick; cruise lock with assist off holds the velocity. `cockpit.gd` gets orbit lines; the ship draws an `OrbitLine` `ArrayMesh` centred on the planet.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer. Headless `extends SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-09-25-orbital-flight-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`. One test file: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (every `tests/*.gd` must print exactly `ALL TESTS PASSED`). If the script is gone, recreate it: loop over `tests/*.gd`, grep each run for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the grep is exactly `ALL TESTS PASSED`.
- **Reading RED:** a missing method prints `SCRIPT ERROR: ... Nonexistent function` and the file may still end with `ALL TESTS PASSED`; a missing preload prints `Parse Error`. RED is those lines or `FAIL` lines, never the summary alone. A script error before `quit()` can hang the run: always run probes and tests with `timeout 300`.
- **Fresh worktree:** run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import` once before the first test run; run it again after creating a new test file to get its `.uid`.
- **Worktree shell rule:** in a worktree session, Bash commands with shell variables, loops or `bash -c` constructs are refused. Use literal paths and one command per call; put multi-step edits in a Python file in the scratchpad and run it.
- Off-tree nodes: no `global_*`; tests set `position` directly. In-tree tests use `_initialize()` + `await process_frame` / `physics_frame`.
- **`ImmediateMesh` cannot be read back** (no `surface_get_array_len`; a script error there hangs the run). The orbit line uses an `ArrayMesh` (`PRIMITIVE_LINE_STRIP`), whose `surface_get_arrays` works headless (probed).
- Numbers (spec, "Numeri"): `MOON_GM = 4.9048e12`; ring radius `6949600.0`; ω ≈ `1.2088459e-4` rad/s; ring speed ≈ `840.0995` m/s.
- Keys: `flight_assist` = Tab (physical keycode `4194306`); `cruise` = C; `move_up` = Z; `move_down` = X.
- GDScript: explicit types where builtins return Variant; do not name locals `basis`, `transform`, `position`, `sign`, `owner`, `ready`; prefix unused parameters with `_`; no bare integer division.
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `.claude/worktrees/`. Add Godot-generated `.uid` files for new scripts/tests.
- Live check: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"` prints nothing. Never launch a windowed run; offscreen renders go through `xvfb-run`.

## Review Focus

1. **Origin shift moves the planet** — the planet centre must be re-read every physics tick and every frame, or gravity and the orbit line jump by thousands of metres after a rebase. Test: `_test_orbit_line_stays_on_the_planet_after_an_origin_shift` (Task 5, in-tree).
2. **Tab eaten by GUI focus navigation** — Godot's `ui_focus_next` is on Tab. Test: `_test_tab_key_reaches_the_ship` (Task 5, in-tree, real key event through the viewport).
3. **Degenerate orbits** — a ship at rest relative to the stars (radial fall, zero angular momentum) or exactly parabolic must not produce NaN on the HUD or the line. Tests: `_test_radial_fall_is_an_impact_without_nan` and `_test_orbit_points_follow_the_conic` (Task 1).
4. **Flight assist off changes the internal-cruiser by accident** — the hooks live in the shared base. Test: the existing internal-cruiser speed tests (1 km/s after the ramp) stay green in every task's full-suite run.
5. **Cruise hold meaning flips when assist toggles** — Tab must drop the lock. Test: `_test_tab_toggles_flight_assist_and_drops_cruise` (Task 2).

---

### Task 1: Orbital frame math

**Files:**
- Create: `scripts/orbital_frame.gd`, `tests/test_orbital_frame.gd`

**Interfaces:**
- Produces (all `static` on `orbital_frame.gd`):
  - `const MOON_GM := 4.9048e12`
  - `orbit_angular_velocity(gm: float, orbit_radius: float) -> float`
  - `frame_acceleration(offset: Vector3, velocity: Vector3, gm: float, omega: Vector3) -> Vector3`
  - `inertial_velocity(offset: Vector3, velocity: Vector3, omega: Vector3) -> Vector3`
  - `orbit_of(offset: Vector3, inertial: Vector3, gm: float) -> Dictionary` with keys `periapsis: float`, `apoapsis: float` (`INF` when open), `escape: bool`, `eccentricity: Vector3`, `semi_latus: float`, `normal: Vector3`
  - `orbit_points(orbit: Dictionary, count: int, max_radius: float) -> PackedVector3Array` (relative to the planet centre)

- [ ] **Step 1: Write the failing tests**

Create `tests/test_orbital_frame.gd`:

```gdscript
extends SceneTree

const OrbitalFrame = preload("res://scripts/orbital_frame.gd")

const GM := 4.9048e12
const RING := 6949600.0
const PLANET_RADIUS := 1737400.0

func _init():
	var failures := 0
	failures += _test_ring_turns_once_in_about_14_hours()
	failures += _test_forces_cancel_on_the_ring()
	failures += _test_on_the_axis_only_gravity_pulls()
	failures += _test_coriolis_is_across_the_motion()
	failures += _test_still_on_the_ring_is_a_circular_orbit()
	failures += _test_slower_than_circular_drops_the_periapsis()
	failures += _test_faster_than_escape_is_an_open_orbit()
	failures += _test_radial_fall_is_an_impact_without_nan()
	failures += _test_orbit_points_follow_the_conic()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _omega() -> Vector3:
	return Vector3.UP * OrbitalFrame.orbit_angular_velocity(GM, RING)

func _circular_speed(radius: float) -> float:
	return sqrt(GM / radius)

func _test_ring_turns_once_in_about_14_hours() -> int:
	var w: float = OrbitalFrame.orbit_angular_velocity(GM, RING)
	if absf(w - 1.2088459e-4) > 1e-9 or absf(w * RING - 840.0995) > 0.01:
		print("FAIL _test_ring_turns_once_in_about_14_hours: omega %.10f, ring speed %.4f" % [w, w * RING])
		return 1
	return 0

func _test_forces_cancel_on_the_ring() -> int:
	var result := 0
	for offset in [Vector3(RING, 0.0, 0.0), Vector3(0.0, 0.0, -RING), Vector3(RING * 0.6, 0.0, RING * 0.8)]:
		var a: Vector3 = OrbitalFrame.frame_acceleration(offset, Vector3.ZERO, GM, _omega())
		if a.length() > 1e-9:
			print("FAIL _test_forces_cancel_on_the_ring: at %s the net pull is %s" % [offset, a])
			result = 1
	return result

func _test_on_the_axis_only_gravity_pulls() -> int:
	# On the turning axis there is no centrifugal push: gravity alone.
	var offset := Vector3(0.0, 3.0e6, 0.0)
	var a: Vector3 = OrbitalFrame.frame_acceleration(offset, Vector3.ZERO, GM, _omega())
	var expected := Vector3(0.0, -GM / (3.0e6 * 3.0e6), 0.0)
	if not a.is_equal_approx(expected):
		print("FAIL _test_on_the_axis_only_gravity_pulls: %s expected %s" % [a, expected])
		return 1
	return 0

func _test_coriolis_is_across_the_motion() -> int:
	# On the ring gravity and centrifugal cancel: what is left is Coriolis.
	var v := Vector3(0.0, 0.0, -1000.0)
	var a: Vector3 = OrbitalFrame.frame_acceleration(Vector3(RING, 0.0, 0.0), v, GM, _omega())
	var w: float = _omega().length()
	if absf(a.dot(v)) > 1e-9 or absf(a.length() - 2.0 * w * 1000.0) > 1e-9:
		print("FAIL _test_coriolis_is_across_the_motion: %s (length %.6f, expected %.6f, across the motion)" % [a, a.length(), 2.0 * w * 1000.0])
		return 1
	return 0

func _test_still_on_the_ring_is_a_circular_orbit() -> int:
	var offset := Vector3(RING, 0.0, 0.0)
	var inertial: Vector3 = OrbitalFrame.inertial_velocity(offset, Vector3.ZERO, _omega())
	var orbit: Dictionary = OrbitalFrame.orbit_of(offset, inertial, GM)
	var result := 0
	if absf(inertial.length() - 840.0995) > 0.01:
		print("FAIL _test_still_on_the_ring_is_a_circular_orbit: true speed %.4f expected 840.0995" % inertial.length())
		result = 1
	if absf(orbit.periapsis - RING) > 1.0 or absf(orbit.apoapsis - RING) > 1.0 or orbit.escape:
		print("FAIL _test_still_on_the_ring_is_a_circular_orbit: periapsis %.1f apoapsis %.1f escape %s" % [orbit.periapsis, orbit.apoapsis, orbit.escape])
		result = 1
	return result

func _test_slower_than_circular_drops_the_periapsis() -> int:
	var offset := Vector3(RING, 0.0, 0.0)
	var inertial := Vector3(0.0, 0.0, -0.9 * _circular_speed(RING))
	var orbit: Dictionary = OrbitalFrame.orbit_of(offset, inertial, GM)
	if orbit.periapsis > RING - 1000.0 or absf(orbit.apoapsis - RING) > 1.0 or orbit.escape:
		print("FAIL _test_slower_than_circular_drops_the_periapsis: periapsis %.1f apoapsis %.1f" % [orbit.periapsis, orbit.apoapsis])
		return 1
	return 0

func _test_faster_than_escape_is_an_open_orbit() -> int:
	var offset := Vector3(RING, 0.0, 0.0)
	var inertial := Vector3(0.0, 0.0, -1.5 * _circular_speed(RING))
	var orbit: Dictionary = OrbitalFrame.orbit_of(offset, inertial, GM)
	if not orbit.escape or not is_inf(orbit.apoapsis) or absf(orbit.periapsis - RING) > 1.0:
		print("FAIL _test_faster_than_escape_is_an_open_orbit: escape %s apoapsis %f periapsis %.1f" % [orbit.escape, orbit.apoapsis, orbit.periapsis])
		return 1
	return 0

func _test_radial_fall_is_an_impact_without_nan() -> int:
	# At rest relative to the stars: no angular momentum, straight down.
	var offset := Vector3(RING, 0.0, 0.0)
	var orbit: Dictionary = OrbitalFrame.orbit_of(offset, Vector3.ZERO, GM)
	var points: PackedVector3Array = OrbitalFrame.orbit_points(orbit, 16, RING * 5.0)
	var result := 0
	if is_nan(orbit.periapsis) or orbit.periapsis > PLANET_RADIUS or is_nan(orbit.apoapsis):
		print("FAIL _test_radial_fall_is_an_impact_without_nan: periapsis %f apoapsis %f" % [orbit.periapsis, orbit.apoapsis])
		result = 1
	for p in points:
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
			print("FAIL _test_radial_fall_is_an_impact_without_nan: NaN in the orbit points")
			result = 1
			break
	return result

func _test_orbit_points_follow_the_conic() -> int:
	var result := 0
	var offset := Vector3(RING, 0.0, 0.0)
	# Closed: every point between periapsis and apoapsis, in the orbit plane, loop closed.
	var closed: Dictionary = OrbitalFrame.orbit_of(offset, Vector3(0.0, 0.0, -0.9 * _circular_speed(RING)), GM)
	var points: PackedVector3Array = OrbitalFrame.orbit_points(closed, 256, RING * 5.0)
	if points.size() != 256 or points[0].distance_to(points[255]) > 1.0:
		print("FAIL _test_orbit_points_follow_the_conic: %d points, loop gap %.1f m" % [points.size(), points[0].distance_to(points[points.size() - 1])])
		result = 1
	for p in points:
		var r := p.length()
		if r < closed.periapsis - 1.0 or r > closed.apoapsis + 1.0 or absf(p.dot(closed.normal)) > 1.0:
			print("FAIL _test_orbit_points_follow_the_conic: point %s off the ellipse (r %.1f)" % [p, r])
			result = 1
			break
	# Open: stops where the radius reaches the limit.
	var open: Dictionary = OrbitalFrame.orbit_of(offset, Vector3(0.0, 0.0, -1.5 * _circular_speed(RING)), GM)
	var branch: PackedVector3Array = OrbitalFrame.orbit_points(open, 64, RING * 5.0)
	if absf(branch[0].length() - RING * 5.0) > 1.0 or absf(branch[63].length() - RING * 5.0) > 1.0:
		print("FAIL _test_orbit_points_follow_the_conic: open branch ends at %.1f / %.1f, expected %.1f" % [branch[0].length(), branch[63].length(), RING * 5.0])
		result = 1
	for p in branch:
		if p.length() > RING * 5.0 + 1.0 or p.length() < open.periapsis - 1.0:
			print("FAIL _test_orbit_points_follow_the_conic: open branch point at %.1f m" % p.length())
			result = 1
			break
	return result
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_orbital_frame.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -5`
Expected: `Parse Error` (preload of `res://scripts/orbital_frame.gd` fails).

- [ ] **Step 3: Implement**

Create `scripts/orbital_frame.gd`:

```gdscript
extends RefCounted

# The void-cruiser flies in the frame of the orbiting ring: the ring stays
# still in the scene and the space around it turns. A craft in this frame
# feels the planet's gravity, a centrifugal push away from the ring's axis
# and a Coriolis pull across its motion. Physically this is the ring
# orbiting at ~840 m/s, seen from the ring.

const MOON_GM := 4.9048e12

# Angular velocity of a circular orbit of radius `orbit_radius`.
static func orbit_angular_velocity(gm: float, orbit_radius: float) -> float:
	return sqrt(gm / pow(orbit_radius, 3.0))

# `offset`: position minus the planet centre. `velocity`: relative to the
# turning frame. `omega`: the frame's rotation (axis times angular speed).
static func frame_acceleration(offset: Vector3, velocity: Vector3, gm: float, omega: Vector3) -> Vector3:
	var r := offset.length()
	var gravity := Vector3.ZERO if r <= 0.0 else -offset * (gm / (r * r * r))
	var centrifugal := -omega.cross(omega.cross(offset))
	var coriolis := -2.0 * omega.cross(velocity)
	return gravity + centrifugal + coriolis

# Velocity relative to the stars.
static func inertial_velocity(offset: Vector3, velocity: Vector3, omega: Vector3) -> Vector3:
	return velocity + omega.cross(offset)

# Kepler orbit from position and velocity relative to the stars. Distances
# are from the planet centre; apoapsis is INF for an open orbit.
static func orbit_of(offset: Vector3, inertial: Vector3, gm: float) -> Dictionary:
	var r := offset.length()
	var h := offset.cross(inertial)
	var e_vec := inertial.cross(h) / gm - offset / r
	var e := e_vec.length()
	# Semi-latus rectum: works for every conic, including a straight fall (0).
	var p := h.length_squared() / gm
	var normal := h.normalized() if h.length() > 0.0 else _any_perpendicular(offset)
	return {
		"periapsis": p / (1.0 + e),
		"apoapsis": INF if e >= 1.0 else p / (1.0 - e),
		"escape": e >= 1.0,
		"eccentricity": e_vec,
		"semi_latus": p,
		"normal": normal,
	}

# `count` points along the orbit around the planet centre, by true anomaly.
# A closed orbit goes all the way round (first point = last point); an open
# one stops where its radius reaches `max_radius`.
static func orbit_points(orbit: Dictionary, count: int, max_radius: float) -> PackedVector3Array:
	var e_vec: Vector3 = orbit.eccentricity
	var e := e_vec.length()
	var p: float = orbit.semi_latus
	var normal: Vector3 = orbit.normal
	var toward_periapsis: Vector3 = e_vec / e if e > 1e-9 else _any_perpendicular(normal)
	var along_motion := normal.cross(toward_periapsis)
	var limit := PI
	if e >= 1.0:
		# Where the radius reaches max_radius. A straight fall (p = 0, e = 1)
		# would reach nu = PI, where r = 0 / 0: stop just short of it.
		limit = minf(acos(clampf((p / max_radius - 1.0) / e, -1.0, 1.0)), PI - 1e-6)
	var points := PackedVector3Array()
	for k in range(count):
		var nu: float = -limit + 2.0 * limit * k / (count - 1)
		var r: float = p / (1.0 + e * cos(nu))
		points.append((toward_periapsis * cos(nu) + along_motion * sin(nu)) * r)
	return points

static func _any_perpendicular(v: Vector3) -> Vector3:
	var side := v.cross(Vector3.UP)
	if side.length() < 1e-9:
		side = v.cross(Vector3.RIGHT)
	if side.length() < 1e-9:
		return Vector3.RIGHT
	return side.normalized()
```

Note on the radial fall: `h = 0` gives `p = 0` and `e = 1` (`e_vec = -offset / r`), so periapsis 0 (inside the planet → IMPACT), apoapsis `INF`, and every point at radius 0. The `PI - 1e-6` cap keeps `1 + e cos(nu)` away from 0, so no NaN.

Integration check done while planning: the same semi-implicit step (velocity from the acceleration at the old state, then position from the new velocity) at 1/60 s keeps a 2500 km circular orbit within 2.4 m over 600 s, so the 50 m tolerance in Task 3 is comfortable.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_orbital_frame.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED|WARNING"`
Expected: `ALL TESTS PASSED` only.

Run `--import` once to get `tests/test_orbital_frame.gd.uid` and `scripts/orbital_frame.gd.uid`.

- [ ] **Step 5: Commit**

```bash
git add scripts/orbital_frame.gd scripts/orbital_frame.gd.uid tests/test_orbital_frame.gd tests/test_orbital_frame.gd.uid
git commit -m "Add the orbital frame math: forces in the ring's frame, Kepler orbit, orbit points

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Flight assist on Tab

**Files:**
- Modify: `project.godot` (new action), `scripts/flying_craft.gd` (`_apply_physics_step` + hooks), `scripts/void_cruiser.gd`
- Test: `tests/test_void_cruiser.gd`, `tests/test_scene_wiring.gd`

**Interfaces:**
- Produces on `flying_craft.gd`: `_linear_damping_now() -> float`, `_angular_damping_now() -> float`, `_external_acceleration() -> Vector3` (base: `linear_damping`, `angular_damping`, `Vector3.ZERO`).
- Produces on `void_cruiser.gd`: `var flight_assist := true`; Tab (`flight_assist` action) toggles it and sets `cruise_locked = false`; overrides of the two damping hooks and of `forward_thrust_multiplier()`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_void_cruiser.gd`, add after `failures += _test_process_shows_cruise_on_hud()`:

```gdscript
	failures += _test_tab_toggles_flight_assist_and_drops_cruise()
	failures += _test_without_assist_speed_and_spin_do_not_fade()
	failures += _test_without_assist_thrust_is_1x_and_unbounded()
	failures += _test_cruise_without_assist_does_not_push_forward()
```

and append:

```gdscript
func _test_tab_toggles_flight_assist_and_drops_cruise() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	if not cruiser.flight_assist:
		print("FAIL _test_tab_toggles_flight_assist_and_drops_cruise: assist off at start")
		result = 1
	_press(cruiser, "cruise")
	_press(cruiser, "flight_assist")
	if cruiser.flight_assist or cruiser.cruise_locked:
		print("FAIL _test_tab_toggles_flight_assist_and_drops_cruise: after Tab assist %s cruise %s, expected both off" % [cruiser.flight_assist, cruiser.cruise_locked])
		result = 1
	_press(cruiser, "flight_assist")
	if not cruiser.flight_assist:
		print("FAIL _test_tab_toggles_flight_assist_and_drops_cruise: a second Tab did not turn assist back on")
		result = 1
	cruiser.free()
	return result

func _test_without_assist_speed_and_spin_do_not_fade() -> int:
	# Default damping 0.5 would halve both every second; without assist, none.
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.flight_assist = false
	cruiser.velocity = Vector3(0.0, 0.0, -100.0)
	cruiser.angular_velocity = Vector3(0.2, 0.0, 0.0)
	for i in range(120):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if absf(cruiser.velocity.length() - 100.0) > 1e-6 or absf(cruiser.angular_velocity.length() - 0.2) > 1e-9:
		print("FAIL _test_without_assist_speed_and_spin_do_not_fade: speed %f spin %f after 2 s" % [cruiser.velocity.length(), cruiser.angular_velocity.length()])
		result = 1
	cruiser.free()
	return result

func _test_without_assist_thrust_is_1x_and_unbounded() -> int:
	# 150 m/s^2 for 10 s: 1500 m/s, no ramp and no drag to cap it.
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.flight_assist = false
	Input.action_press("move_forward")
	for i in range(600):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var result := 0
	if absf(cruiser.velocity.length() - 1500.0) > 5.0 or not is_equal_approx(cruiser.forward_thrust_multiplier(), 1.0):
		print("FAIL _test_without_assist_thrust_is_1x_and_unbounded: speed %.1f (expected 1500), multiplier %f" % [cruiser.velocity.length(), cruiser.forward_thrust_multiplier()])
		result = 1
	cruiser.free()
	return result

func _test_cruise_without_assist_does_not_push_forward() -> int:
	# Without assist C holds the current velocity instead of pushing.
	var cruiser := _make_cruiser()
	cruiser.flight_assist = false
	_press(cruiser, "cruise")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if not cruiser.cruise_locked or not cruiser.velocity.is_zero_approx():
		print("FAIL _test_cruise_without_assist_does_not_push_forward: cruise %s velocity %s" % [cruiser.cruise_locked, cruiser.velocity])
		result = 1
	cruiser.free()
	return result
```

In `tests/test_scene_wiring.gd`, add after `failures += _test_up_and_down_thrust_on_z_and_x()`:

```gdscript
	failures += _test_flight_assist_on_tab()
```

and append:

```gdscript
func _test_flight_assist_on_tab() -> int:
	var keys := _key_codes("flight_assist")
	if keys != [KEY_TAB]:
		print("FAIL _test_flight_assist_on_tab: flight_assist keys %s, expected [Tab]" % [keys])
		return 1
	return 0
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -8`
Expected: `SCRIPT ERROR` lines (no `flight_assist` property) and/or `FAIL` lines.
Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_scene_wiring.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
Expected: `FAIL _test_flight_assist_on_tab` (and possibly an `action_get_events` error for the missing action).

- [ ] **Step 3: Implement**

`project.godot`: after the `cruise={ ... }` block add (same format, Tab physical keycode):

```
flight_assist={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194306,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

`scripts/flying_craft.gd`: replace the first two lines of `_apply_physics_step` with:

```gdscript
	var outside := _external_acceleration()
	velocity = VoidCruiserPhysics.compute_new_velocity(velocity, local_thrust_input, transform.basis, thrust_power, _linear_damping_now(), delta) + outside * delta
	angular_velocity = VoidCruiserPhysics.compute_new_angular_velocity(angular_velocity, local_torque_input, torque_power, _angular_damping_now(), delta)
```

and add before `func _apply_physics_step(`:

```gdscript
# What this tick of flight uses; a craft can change them (see void_cruiser.gd).
func _linear_damping_now() -> float:
	return linear_damping

func _angular_damping_now() -> float:
	return angular_damping

# Pulls from outside the craft (gravity and the like), in world space.
func _external_acceleration() -> Vector3:
	return Vector3.ZERO

```

`scripts/void_cruiser.gd`:
- replace the comment above `CRUISE_RELEASE_ACTIONS` with:

```gdscript
# C locks the thrust. With flight assist it pushes forward as if W were held
# (the ramp runs on to its last step); without, it holds the current
# velocity. A new press of W/A/S/D, or C again, lets go; roll, mouse and
# up/down do not.
```

- add after `var cruise_locked := false`:

```gdscript
# Tab. On: drag on motion and spin, and the thrust ramp (arcade flight).
# Off: pure inertia, plain 1x thrust, no top speed.
var flight_assist := true
```

- in `_unhandled_input`, replace `if event.is_action_pressed("cruise"):` with:

```gdscript
	if event.is_action_pressed("flight_assist"):
		# The lock means something else in the other mode: let it go.
		flight_assist = not flight_assist
		cruise_locked = false
	elif event.is_action_pressed("cruise"):
```

- in `_read_thrust_input`, change `if cruise_locked:` to `if cruise_locked and flight_assist:`;
- add after `_read_thrust_input`:

```gdscript
func forward_thrust_multiplier() -> float:
	return super() if flight_assist else 1.0

func _linear_damping_now() -> float:
	return linear_damping if flight_assist else 0.0

func _angular_damping_now() -> float:
	return angular_damping if flight_assist else 0.0
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the two commands of Step 2. Expected: `ALL TESTS PASSED` only, for each.
Then the full suite. Expected: all files `ALL TESTS PASSED` (the internal-cruiser speed tests must stay green).

- [ ] **Step 5: Commit**

```bash
git add project.godot scripts/flying_craft.gd scripts/void_cruiser.gd tests/test_void_cruiser.gd tests/test_scene_wiring.gd
git commit -m "Add flight assist on Tab: off means no drag, no ramp, velocity hold on C

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Orbital forces on the void-cruiser

**Files:**
- Modify: `scripts/void_cruiser.gd`
- Test: `tests/test_void_cruiser.gd`, `tests/test_scene_wiring.gd`

**Interfaces:**
- Consumes: Task 1 `OrbitalFrame.*`; Task 2 hooks and `flight_assist`.
- Produces on `void_cruiser.gd`: exports `planet_path` (`../PlanetSystem/Planet`), `planet_gm` (`OrbitalFrame.MOON_GM`), `ring_radius` (`6949600.0`); vars `has_planet := false`, `planet_center`, `planet_axis`, `planet_radius := 1737400.0`; funcs `ring_omega() -> Vector3`, `current_orbit() -> Dictionary`, `orbit_readout() -> Dictionary` (`altitude`, `periapsis`, `apoapsis` above the surface; `{}` without a planet), `_sync_planet()`, `_world_position() -> Vector3`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_void_cruiser.gd`, add after `failures += _test_cruise_without_assist_does_not_push_forward()`:

```gdscript
	failures += _test_circular_orbit_holds_without_assist()
	failures += _test_cruise_without_assist_holds_velocity_in_strong_gravity()
	failures += _test_orbit_readout_on_the_ring()
```

and append:

```gdscript
func _orbiting_cruiser() -> Node3D:
	# A ship in the ring's frame around a planet at the origin (off-tree, so
	# the planet is set by hand instead of read from the scene).
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.has_planet = true
	cruiser.planet_center = Vector3.ZERO
	cruiser.planet_axis = Vector3.UP
	return cruiser

func _test_circular_orbit_holds_without_assist() -> int:
	# A true circular orbit at 2500 km from the centre, seen from the ring's
	# frame. Without the forces the ship would fly straight and end ~87 km
	# higher after 600 s.
	var cruiser := _orbiting_cruiser()
	cruiser.flight_assist = false
	var r0 := 2.5e6
	var circular: float = sqrt(cruiser.planet_gm / r0)
	cruiser.position = Vector3(r0, 0.0, 0.0)
	cruiser.velocity = Vector3(0.0, 0.0, -circular) - cruiser.ring_omega().cross(cruiser.position)
	for i in range(36000):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	var drift: float = cruiser.position.length() - r0
	if absf(drift) > 50.0:
		print("FAIL _test_circular_orbit_holds_without_assist: radius off by %.1f m after 600 s" % drift)
		result = 1
	cruiser.free()
	return result

func _test_cruise_without_assist_holds_velocity_in_strong_gravity() -> int:
	# 2000 km from the centre gravity is ~1.2 m/s^2: the lock cancels it.
	var cruiser := _orbiting_cruiser()
	cruiser.flight_assist = false
	cruiser.position = Vector3(2.0e6, 0.0, 0.0)
	cruiser.velocity = Vector3(0.0, 0.0, -300.0)
	_press(cruiser, "cruise")
	for i in range(120):
		cruiser._physics_process(1.0 / 60.0)
	var result := 0
	if not cruiser.velocity.is_equal_approx(Vector3(0.0, 0.0, -300.0)):
		print("FAIL _test_cruise_without_assist_holds_velocity_in_strong_gravity: velocity drifted to %s" % cruiser.velocity)
		result = 1
	# Z (dorsal thrust) changes it; the lock then holds the new velocity.
	Input.action_press("move_up")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_up")
	for i in range(60):
		cruiser._physics_process(1.0 / 60.0)
	if not cruiser.cruise_locked or absf(cruiser.velocity.y - 150.0) > 0.5 or absf(cruiser.velocity.z + 300.0) > 0.5:
		print("FAIL _test_cruise_without_assist_holds_velocity_in_strong_gravity: after Z velocity %s, cruise %s (expected y ~150, z -300, still locked)" % [cruiser.velocity, cruiser.cruise_locked])
		result = 1
	cruiser.free()
	return result

func _test_orbit_readout_on_the_ring() -> int:
	var cruiser := _orbiting_cruiser()
	cruiser.position = Vector3(cruiser.ring_radius, 0.0, 0.0)
	var readout: Dictionary = cruiser.orbit_readout()
	var expected: float = cruiser.ring_radius - cruiser.planet_radius
	var result := 0
	if absf(readout.altitude - expected) > 1.0 or absf(readout.periapsis - expected) > 1.0 or absf(readout.apoapsis - expected) > 1.0:
		print("FAIL _test_orbit_readout_on_the_ring: %s, expected all about %.1f" % [readout, expected])
		result = 1
	var loose: Node3D = VoidCruiserScript.new()
	if not loose.orbit_readout().is_empty():
		print("FAIL _test_orbit_readout_on_the_ring: a ship without a planet reports an orbit")
		result = 1
	loose.free()
	cruiser.free()
	return result
```

In `tests/test_scene_wiring.gd`, add after `failures += _test_flight_assist_on_tab()`:

```gdscript
	failures += _test_void_cruiser_orbits_with_the_station()
```

and append:

```gdscript
func _test_void_cruiser_orbits_with_the_station() -> int:
	var scene: Node = load("res://scenes/torus1_system.tscn").instantiate()
	var cruiser: Node = scene.get_node("VoidCruiser")
	var station: Node = scene.get_node("PlanetSystem/TorusStation")
	var result := 0
	if cruiser.get_node_or_null(cruiser.planet_path) != scene.get_node("PlanetSystem/Planet"):
		print("FAIL _test_void_cruiser_orbits_with_the_station: planet_path does not reach PlanetSystem/Planet")
		result = 1
	if not is_equal_approx(cruiser.ring_radius, station.planet_radius + station.orbit_altitude):
		print("FAIL _test_void_cruiser_orbits_with_the_station: ring_radius %f, station ring at %f" % [cruiser.ring_radius, station.planet_radius + station.orbit_altitude])
		result = 1
	scene.free()
	return result
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -8`
Expected: `SCRIPT ERROR` lines (no `has_planet` / `ring_omega`).
Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_scene_wiring.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
Expected: `SCRIPT ERROR` or `FAIL` (no `planet_path` / `ring_radius`).

- [ ] **Step 3: Implement**

In `scripts/void_cruiser.gd`:
- add below `const CockpitScript = ...`:

```gdscript
const OrbitalFrame = preload("res://scripts/orbital_frame.gd")

# The planet the ship orbits, and the ring's circular orbit around it. The
# ship flies in the frame turning with the ring (see orbital_frame.gd); the
# ring's axis is the planet node's Y axis.
@export var planet_path: NodePath = NodePath("../PlanetSystem/Planet")
@export var planet_gm: float = OrbitalFrame.MOON_GM
@export var ring_radius: float = 6949600.0
```

- add after `var flight_assist := true`:

```gdscript
# The planet as last read from the scene (see _sync_planet); without one,
# no orbital forces and no orbit readout.
var has_planet := false
var planet_center := Vector3.ZERO
var planet_axis := Vector3.UP
var planet_radius := 1737400.0
```

- change `_physics_process` to:

```gdscript
func _physics_process(delta: float) -> void:
	_sync_planet()
	_fly(delta)
```

- add after `_angular_damping_now`:

```gdscript
func _external_acceleration() -> Vector3:
	# Holding velocity without assist: the thrusters cancel the orbital pulls.
	if not has_planet or (cruise_locked and not flight_assist):
		return Vector3.ZERO
	return OrbitalFrame.frame_acceleration(_world_position() - planet_center, velocity, planet_gm, ring_omega())

func ring_omega() -> Vector3:
	return planet_axis * OrbitalFrame.orbit_angular_velocity(planet_gm, ring_radius)

# The ship's orbit relative to the stars (see OrbitalFrame.orbit_of).
func current_orbit() -> Dictionary:
	var offset := _world_position() - planet_center
	return OrbitalFrame.orbit_of(offset, OrbitalFrame.inertial_velocity(offset, velocity, ring_omega()), planet_gm)

# Heights above the surface: now, at periapsis, at apoapsis (INF when the
# orbit is open). Empty without a planet.
func orbit_readout() -> Dictionary:
	if not has_planet:
		return {}
	var orbit := current_orbit()
	return {
		"altitude": (_world_position() - planet_center).length() - planet_radius,
		"periapsis": orbit.periapsis - planet_radius,
		"apoapsis": orbit.apoapsis - planet_radius,
	}

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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the two commands of Step 2. Expected: `ALL TESTS PASSED` only, for each (the orbit test may take a few seconds).
Then the full suite. Expected: all files `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/void_cruiser.gd tests/test_void_cruiser.gd tests/test_scene_wiring.gd
git commit -m "Pull the void-cruiser with gravity, centrifugal and Coriolis in the ring's frame

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Orbit lines on the HUD

**Files:**
- Modify: `scripts/cockpit_hud_format.gd`, `scripts/cockpit.gd`, `scripts/void_cruiser.gd` (`_process`)
- Test: `tests/test_cockpit_hud_format.gd`, `tests/test_cockpit.gd`, `tests/test_void_cruiser.gd`

**Interfaces:**
- Consumes: Task 3 `orbit_readout()`, `_sync_planet()`; Task 2 `flight_assist`.
- Produces: `CockpitHudFormat.format_altitude(metres: float) -> String` (`"%d km"`, `—` for INF/NaN); `cockpit.update_orbit(assist_on: bool, readout: Dictionary)`; labels `AssistLabel`, `AltitudeLabel`, `PeriapsisLabel`, `ApoapsisLabel`, `ImpactLabel`, `EscapeLabel` after `CruiseLabel`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_cockpit_hud_format.gd`, add after `failures += _test_format_distance_kilometres_one_decimal()`:

```gdscript
	failures += _test_format_altitude_in_whole_kilometres()
```

and append:

```gdscript
func _test_format_altitude_in_whole_kilometres() -> int:
	var result := 0
	result += _check("_test_format_altitude_in_whole_kilometres", CockpitHudFormat.format_altitude(5222201.0), "5222 km")
	result += _check("_test_format_altitude_in_whole_kilometres", CockpitHudFormat.format_altitude(-1200400.0), "-1200 km")
	result += _check("_test_format_altitude_in_whole_kilometres", CockpitHudFormat.format_altitude(INF), "—")
	result += _check("_test_format_altitude_in_whole_kilometres", CockpitHudFormat.format_altitude(NAN), "—")
	return mini(result, 1)
```

In `tests/test_cockpit.gd`:
- change the `expected` list in `_test_hud_lines_in_display_order` to:

```gdscript
	var expected := ["SpeedLabel", "CruiseLabel", "AssistLabel", "AltitudeLabel", "PeriapsisLabel", "ApoapsisLabel", "ImpactLabel", "EscapeLabel", "BowLabel", "SternLabel", "PortLabel", "StarboardLabel", "DorsalLabel", "VentralLabel", "DockLabel"]
```

- add after `failures += _test_cruise_line_shown_only_while_cruising()`:

```gdscript
	failures += _test_update_orbit_writes_assist_and_altitudes()
	failures += _test_orbit_warnings_only_when_needed()
```

- append:

```gdscript
func _line(cockpit: Node, label_name: String) -> Label:
	return cockpit.get_node("Hud/Panel/Lines/" + label_name) as Label

func _test_update_orbit_writes_assist_and_altitudes() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	cockpit.update_orbit(false, {"altitude": 5222201.0, "periapsis": 5100000.0, "apoapsis": 5300400.0})
	var expected := {
		"AssistLabel": "ASSIST  OFF",
		"AltitudeLabel": "ALTITUDE  5222 km",
		"PeriapsisLabel": "PERIAPSIS  5100 km",
		"ApoapsisLabel": "APOAPSIS  5300 km",
	}
	for label_name in expected:
		if _line(cockpit, label_name).text != expected[label_name]:
			print("FAIL _test_update_orbit_writes_assist_and_altitudes: %s='%s' expected '%s'" % [label_name, _line(cockpit, label_name).text, expected[label_name]])
			result = 1
	if _line(cockpit, "AssistLabel").label_settings.font_color != CockpitScript.CRUISE_COLOR:
		print("FAIL _test_update_orbit_writes_assist_and_altitudes: ASSIST OFF is not yellow")
		result = 1
	cockpit.update_orbit(true, {})
	if _line(cockpit, "AssistLabel").text != "ASSIST  ON" or _line(cockpit, "AltitudeLabel").text != "ALTITUDE  —" or _line(cockpit, "ApoapsisLabel").text != "APOAPSIS  —":
		print("FAIL _test_update_orbit_writes_assist_and_altitudes: with no orbit data got '%s' / '%s' / '%s'" % [_line(cockpit, "AssistLabel").text, _line(cockpit, "AltitudeLabel").text, _line(cockpit, "ApoapsisLabel").text])
		result = 1
	cockpit.free()
	return result

func _test_orbit_warnings_only_when_needed() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var cases := [
		# [readout, IMPACT visible, ESCAPE visible]
		[{}, false, false],
		[{"altitude": 5.0e6, "periapsis": 4.0e6, "apoapsis": 6.0e6}, false, false],
		[{"altitude": 5.0e6, "periapsis": -3.0e5, "apoapsis": 5.0e6}, true, false],
		[{"altitude": 5.0e6, "periapsis": 5.0e6, "apoapsis": INF}, false, true],
	]
	for c in cases:
		cockpit.update_orbit(true, c[0])
		if _line(cockpit, "ImpactLabel").visible != c[1] or _line(cockpit, "EscapeLabel").visible != c[2]:
			print("FAIL _test_orbit_warnings_only_when_needed: %s gave IMPACT %s ESCAPE %s" % [c[0], _line(cockpit, "ImpactLabel").visible, _line(cockpit, "EscapeLabel").visible])
			result = 1
	if _line(cockpit, "ImpactLabel").text != "IMPACT" or _line(cockpit, "EscapeLabel").text != "ESCAPE":
		print("FAIL _test_orbit_warnings_only_when_needed: warning texts wrong")
		result = 1
	cockpit.free()
	return result
```

In `tests/test_void_cruiser.gd`, add after `failures += _test_orbit_readout_on_the_ring()`:

```gdscript
	failures += _test_process_shows_orbit_on_hud()
```

and append:

```gdscript
func _test_process_shows_orbit_on_hud() -> int:
	var cruiser := _orbiting_cruiser()
	cruiser.build_proximity_sensors()
	cruiser.build_cockpit()
	cruiser.position = Vector3(cruiser.ring_radius + 10000.0, 0.0, 0.0)
	cruiser._process(0.016)
	var altitude: Label = cruiser.get_node("Cockpit/Hud/Panel/Lines/AltitudeLabel")
	var assist: Label = cruiser.get_node("Cockpit/Hud/Panel/Lines/AssistLabel")
	var result := 0
	if altitude.text != "ALTITUDE  5222 km" or assist.text != "ASSIST  ON":
		print("FAIL _test_process_shows_orbit_on_hud: '%s' / '%s'" % [altitude.text, assist.text])
		result = 1
	cruiser.free()
	return result
```

- [ ] **Step 2: Run the tests to verify they fail**

Run each:
`timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit_hud_format.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
`timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -6`
`timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -6`
Expected: `Parse Error`/`SCRIPT ERROR` naming `format_altitude` / `update_orbit`, `FAIL _test_hud_lines_in_display_order`, and node-not-found errors for the new labels.

- [ ] **Step 3: Implement**

`scripts/cockpit_hud_format.gd`, append:

```gdscript
# Height above the planet's surface, in whole kilometres.
static func format_altitude(metres: float) -> String:
	if is_inf(metres) or is_nan(metres):
		return NO_READING
	return "%d km" % roundi(metres / 1000.0)
```

`scripts/cockpit.gd`:
- add after `const CRUISE_COLOR := Color(1.0, 0.8, 0.3)`:

```gdscript
const WARNING_COLOR := Color(1.0, 0.3, 0.25)
# Orbit lines: [label node name, HUD prefix, readout key], in display order.
const ORBIT_LABELS := [
	["AltitudeLabel", "ALTITUDE", "altitude"],
	["PeriapsisLabel", "PERIAPSIS", "periapsis"],
	["ApoapsisLabel", "APOAPSIS", "apoapsis"],
]
```

- add member vars after the constants block (before `func build()`):

```gdscript
var _text_settings: LabelSettings
var _cruise_settings: LabelSettings
```

- add after `set_cruise`:

```gdscript
# `readout`: heights above the surface (see void_cruiser.gd orbit_readout);
# empty when there is no planet.
func update_orbit(assist_on: bool, readout: Dictionary) -> void:
	var lines := get_node("Hud/Panel/Lines")
	var assist: Label = lines.get_node("AssistLabel")
	assist.text = "ASSIST  ON" if assist_on else "ASSIST  OFF"
	assist.label_settings = _text_settings if assist_on else _cruise_settings
	for entry in ORBIT_LABELS:
		var value: float = readout.get(entry[2], INF)
		(lines.get_node(entry[0]) as Label).text = "%s  %s" % [entry[1], CockpitHudFormat.format_altitude(value)]
	(lines.get_node("ImpactLabel") as Label).visible = readout.has("periapsis") and readout.periapsis < 0.0
	(lines.get_node("EscapeLabel") as Label).visible = readout.has("apoapsis") and is_inf(readout.apoapsis)
```

- in `_build_hud`, after `var label_settings := LabelSettings.new()` and its two setting lines add `_text_settings = label_settings`; after the three `cruise_settings` lines add `_cruise_settings = cruise_settings`; and after the block that sets up `cruise_label` (the line `cruise_label.visible = false`) insert:

```gdscript
	_add_hud_label(lines, "AssistLabel", label_settings)
	for entry in ORBIT_LABELS:
		_add_hud_label(lines, entry[0], label_settings)
	var warning_settings := LabelSettings.new()
	warning_settings.font_size = HUD_FONT_SIZE
	warning_settings.font_color = WARNING_COLOR
	for warning in [["ImpactLabel", "IMPACT"], ["EscapeLabel", "ESCAPE"]]:
		_add_hud_label(lines, warning[0], warning_settings)
		var warning_label: Label = lines.get_node(warning[0])
		warning_label.text = warning[1]
		warning_label.visible = false
```

- at the end of `_build_hud`, after `update_hud(0.0, {})`, add `update_orbit(true, {})`.

`scripts/void_cruiser.gd`, in `_process`:
- make the first line `_sync_planet()` (before `_strobe_time += delta`);
- after `cockpit.set_cruise(cruise_locked)` add `cockpit.update_orbit(flight_assist, orbit_readout())`.

- [ ] **Step 4: Run the tests to verify they pass**

Run the three commands of Step 2. Expected: `ALL TESTS PASSED` only, for each.
Then the full suite. Expected: all files `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/cockpit_hud_format.gd scripts/cockpit.gd scripts/void_cruiser.gd tests/test_cockpit_hud_format.gd tests/test_cockpit.gd tests/test_void_cruiser.gd
git commit -m "Show flight assist, altitude, periapsis, apoapsis and impact/escape on the HUD

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The predicted orbit drawn in space

**Files:**
- Modify: `scripts/void_cruiser.gd`
- Test: `tests/test_void_cruiser.gd`; create `tests/test_orbital_flight_in_tree.gd`

**Interfaces:**
- Consumes: Task 1 `orbit_points`; Task 3 `current_orbit`, `has_planet`, `planet_center`, `_world_position`.
- Produces on `void_cruiser.gd`: consts `ORBIT_LINE_POINTS := 256`, `ORBIT_LINE_COLOR`, `ESCAPE_LINE_REACH := 5.0`; `build_orbit_line()` (node `OrbitLine`, `MeshInstance3D`, `top_level`, `ArrayMesh`), `_update_orbit_line()` called from `_process`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_void_cruiser.gd`, add after `failures += _test_process_shows_orbit_on_hud()`:

```gdscript
	failures += _test_orbit_line_has_256_points_around_the_planet()
	failures += _test_orbit_line_hidden_without_planet()
```

and append:

```gdscript
func _test_orbit_line_has_256_points_around_the_planet() -> int:
	var cruiser := _orbiting_cruiser()
	cruiser.planet_center = Vector3(10.0, -20.0, 30.0)
	cruiser.position = cruiser.planet_center + Vector3(cruiser.ring_radius, 0.0, 0.0)
	cruiser.build_orbit_line()
	cruiser._process(0.016)
	var line := cruiser.get_node_or_null("OrbitLine") as MeshInstance3D
	var result := 0
	if line == null or not line.visible or not line.top_level or not line.position.is_equal_approx(cruiser.planet_center):
		print("FAIL _test_orbit_line_has_256_points_around_the_planet: line missing, hidden, not top-level or not on the planet")
		cruiser.free()
		return 1
	var mesh := line.mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_LINE_STRIP or points.size() != 256:
		print("FAIL _test_orbit_line_has_256_points_around_the_planet: %d points, primitive %d" % [points.size(), mesh.surface_get_primitive_type(0)])
		result = 1
	for p in points:
		# At rest on the ring the orbit is the ring's circle.
		if absf(p.length() - cruiser.ring_radius) > 2.0:
			print("FAIL _test_orbit_line_has_256_points_around_the_planet: point at %.1f m from the centre" % p.length())
			result = 1
			break
	cruiser._process(0.016)
	if (line.mesh as ArrayMesh).get_surface_count() != 1:
		print("FAIL _test_orbit_line_has_256_points_around_the_planet: surfaces pile up (%d)" % (line.mesh as ArrayMesh).get_surface_count())
		result = 1
	cruiser.free()
	return result

func _test_orbit_line_hidden_without_planet() -> int:
	var cruiser: Node3D = VoidCruiserScript.new()
	cruiser.build_orbit_line()
	cruiser._process(0.016)
	var result := 0
	if (cruiser.get_node("OrbitLine") as MeshInstance3D).visible:
		print("FAIL _test_orbit_line_hidden_without_planet: line shown with no planet")
		result = 1
	cruiser.free()
	return result
```

Create `tests/test_orbital_flight_in_tree.gd`:

```gdscript
extends SceneTree

# The orbital flight on the real scene (planet, station, origin shift).

var _failures := 0
var _scene: Node3D
var _cruiser: CharacterBody3D
var _planet: Node3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	await process_frame
	_cruiser = _scene.get_node("VoidCruiser")
	_planet = _scene.get_node("PlanetSystem/Planet")

	_failures += _test_ship_finds_the_planet_and_shows_its_altitude()
	_failures += await _test_orbit_line_stays_on_the_planet_after_an_origin_shift()
	_failures += await _test_tab_key_reaches_the_ship()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _test_ship_finds_the_planet_and_shows_its_altitude() -> int:
	# The ship starts 10 km outside the ring and 4 km above its plane:
	# 6 959 601 m from the centre, 5222 km above the surface.
	var altitude: Label = _cruiser.get_node("Cockpit/Hud/Panel/Lines/AltitudeLabel")
	if not _cruiser.has_planet or altitude.text != "ALTITUDE  5222 km":
		print("FAIL _test_ship_finds_the_planet_and_shows_its_altitude: has_planet %s, '%s'" % [_cruiser.has_planet, altitude.text])
		return 1
	return 0

func _test_orbit_line_stays_on_the_planet_after_an_origin_shift() -> int:
	# Past 5000 m the world shifts back under the ship, planet included.
	var before: Vector3 = _planet.global_position
	_cruiser.global_position += Vector3(0.0, 0.0, -6000.0)
	for i in range(3):
		await physics_frame
		await process_frame
	var line: MeshInstance3D = _cruiser.get_node("OrbitLine")
	var result := 0
	if _planet.global_position.is_equal_approx(before):
		print("FAIL _test_orbit_line_stays_on_the_planet_after_an_origin_shift: no origin shift happened")
		result = 1
	if line.global_position.distance_to(_planet.global_position) > 1.0:
		print("FAIL _test_orbit_line_stays_on_the_planet_after_an_origin_shift: line %.1f m off the planet centre" % line.global_position.distance_to(_planet.global_position))
		result = 1
	return result

func _key(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.physical_keycode = KEY_TAB
	event.pressed = pressed
	return event

func _test_tab_key_reaches_the_ship() -> int:
	# Through the viewport, as a real key press: GUI focus must not eat it.
	var was: bool = _cruiser.flight_assist
	root.push_input(_key(true))
	root.push_input(_key(false))
	await process_frame
	if _cruiser.flight_assist == was:
		print("FAIL _test_tab_key_reaches_the_ship: Tab did not toggle flight assist")
		return 1
	root.push_input(_key(true))
	root.push_input(_key(false))
	await process_frame
	return 0
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -6`
Expected: `SCRIPT ERROR` naming `build_orbit_line`.
Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_orbital_flight_in_tree.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED|ERROR" | head -6`
Expected: `_test_ship_finds_the_planet_and_shows_its_altitude` and `_test_tab_key_reaches_the_ship` pass already (Tasks 3-4); the origin-shift test errors with `Node not found: "OrbitLine"`. Ledger which parts were already green.

- [ ] **Step 3: Implement**

In `scripts/void_cruiser.gd`:
- add after `@export var ring_radius: float = 6949600.0`:

```gdscript
const ORBIT_LINE_POINTS := 256
const ORBIT_LINE_COLOR := Color(0.4, 0.8, 1.0, 0.6)
# An open orbit is drawn out to this many times the ship's distance.
const ESCAPE_LINE_REACH := 5.0
```

- in `_ready`, add `build_orbit_line()` after `build_cockpit()`;
- in `_process`, add `_update_orbit_line()` as the last line;
- add after `build_cockpit`:

```gdscript
# The predicted orbit, relative to the stars, drawn around the planet. It
# does not move with the ship (top_level): _update_orbit_line puts it on
# the planet and redraws it every frame.
func build_orbit_line() -> void:
	var line := MeshInstance3D.new()
	line.name = "OrbitLine"
	line.top_level = true
	line.mesh = ArrayMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = ORBIT_LINE_COLOR
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.visible = false
	add_child(line)

func _update_orbit_line() -> void:
	var line := get_node_or_null("OrbitLine") as MeshInstance3D
	if line == null:
		return
	line.visible = has_planet
	if not has_planet:
		return
	var reach: float = (_world_position() - planet_center).length() * ESCAPE_LINE_REACH
	var points := OrbitalFrame.orbit_points(current_orbit(), ORBIT_LINE_POINTS, reach)
	if line.is_inside_tree():
		line.global_position = planet_center
	else:
		line.position = planet_center
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := line.mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the two commands of Step 2. Expected: `ALL TESTS PASSED` only, for each.
Run `--import` once for `tests/test_orbital_flight_in_tree.gd.uid`.
Then the full suite. Expected: all files `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/void_cruiser.gd tests/test_void_cruiser.gd tests/test_orbital_flight_in_tree.gd tests/test_orbital_flight_in_tree.gd.uid
git commit -m "Draw the predicted orbit around the planet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Live check and an offscreen look at the orbit line

**Files:**
- Create (scratchpad only, not committed): `/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_orbit.gd`

- [ ] **Step 1: Headless live run**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"`
Expected: no output.

- [ ] **Step 2: Offscreen render from above**

Create the scratchpad script:

```gdscript
extends SceneTree

# From the top-down camera: the planet, the ring, and the ship's orbit after
# a 500 m/s retrograde kick (an ellipse inside the ring).
const SCRATCH := "/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/"

func _initialize():
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(scene)
	for i in range(3):
		await process_frame
	var cruiser: CharacterBody3D = scene.get_node("VoidCruiser")
	cruiser.flight_assist = false
	cruiser.velocity = Vector3(0.0, 0.0, 500.0)
	(scene.get_node("PlanetSystem/TopDownCamera") as Camera3D).make_current()
	for i in range(10):
		await process_frame
	root.get_texture().get_image().save_png(SCRATCH + "orbit_top.png")
	print("saved orbit_top, HUD: ", (cruiser.get_node("Cockpit/Hud/Panel/Lines/PeriapsisLabel") as Label).text)
	quit()
```

Run: `xvfb-run -a /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --path . --script /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_orbit.gd 2>&1 | grep -E "saved|ERROR"`
Expected: `saved orbit_top, HUD: PERIAPSIS  <n> km` with n well below 5212.

- [ ] **Step 3: Look at the image**

Open `orbit_top.png` with the Read tool. Expected: the planet, the ring around it, and a thin light-blue ellipse touching the ring at the ship and dipping inside it on the far side. If the line is invisible at this scale, ledger it; it is still checked by tests, and a thicker look is a follow-up, not a fix in this plan.

- [ ] **Step 4: Full suite**

Run the full suite. Expected: every file `ALL TESTS PASSED`. No commit in this task.
