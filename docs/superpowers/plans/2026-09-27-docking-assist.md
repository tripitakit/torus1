# Docking Assist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make flying to a dock friendlier: a brake on B that stops the ship against the dock, thrust that eases off near it, an approach panel with an advised speed, and an approach path that stays still in space by aiming at a planned meeting point.

**Architecture:** `scripts/docking_assist.gd` holds every rule as pure static functions. `void_cruiser.gd` finds the nearest dock (`_nearest_dock`), overrides `_fly` for the brake and the precision thrust, plans the arrival (the first pass of the pad below the ship after the steady-braking time) and feeds the cockpit. `cockpit.gd` gains the BRAKE and THRUST lines and a top-right `ApproachPanel`. The station exposes its spin rate.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer. Headless `extends SceneTree` tests; offscreen renders through `xvfb-run`.

**Spec:** `docs/superpowers/specs/2026-09-27-docking-assist-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64` (the `godot` on PATH is single precision: the pilot camera renders black). One test file: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (every `tests/*.gd` must print exactly `ALL TESTS PASSED`; 34 files at the end). If the script is gone, recreate it: loop over `tests/*.gd`, run each with `timeout 600` and the binary above, grep for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the grep is exactly `ALL TESTS PASSED`.
- **Reading RED:** parse and runtime script errors go to stderr (`SCRIPT ERROR: ...`); always run with `2>&1`. A `SCRIPT ERROR` line is a RED even when the summary still says `ALL TESTS PASSED`.
- **Fresh worktree / new files:** run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import > /dev/null 2>&1` once before the first test run and after creating a new script or test (its `.uid`). Add the generated `.uid` files to the commit.
- **Worktree shell rule:** in a worktree session, Bash commands with shell variables, loops or `bash -c` are refused. Use literal paths, one command per call; put multi-step edits in a Python file in the scratchpad and run it.
- Numbers (from the spec): precision 1x at 2 km to 0.1x at 200 m (linear, all axes, no ramp); brake up to 10x base thrust times the precision factor; steady braking 1 m/s^2; replan outside 0.3x .. 3x steady time + one bridge turn; caution up to 1.25x the advised speed; ETA needs 0.5 m/s closing; panel within 20 km (even under 100 m); DOCK READY / TOO FAST inside 150 m.
- The code in this plan was run before writing it: every RED and GREEN below is the output it gave, stage by stage.
- GDScript: explicit types where builtins return Variant; do not name locals `basis`, `transform`, `position`, `sign`, `owner`, `ready`, `size`; no bare integer division.
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `.claude/worktrees/`.
- Live check: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"` prints nothing. Never launch a windowed run; renders through `xvfb-run -a`.

## Review Focus

1. **Holding the brake near the pad for long:** the brake matches the pad's velocity, which turns with the bridge; a ship holding it follows a straight line while the pad goes round, so it drifts off the pad over tens of seconds. Judge whether this reads as a bug in play.
2. **A stale plan after flying round the bridge:** the plan holds up to 3x the steady time plus a turn; a ship that moves far round the axis keeps an old meeting point, and the path leads there. Judge whether a replan on a large change of the ship's angle is needed.
3. **Feedback between plan and path length:** the plan uses last frame's path length, which depends on the meeting point; check that replans do not chain (a replan changing the length enough to trigger the next).
4. **Returning from the interior:** the cruiser is out of the tree while docked; on return `_arrival_at` may be in the past; check that the plan is remade and nothing reads a stale path length.
5. **Feel of 0.1x thrust (15 m/s^2) near the pad and 10x braking far out:** numbers are from the spec; say if they look wrong in the render or the tests.

---

### Task 1: The pure helpers

`scripts/docking_assist.gd`: precision factor, scaled thrust, brake step, arrival planning, advised speed, future pad, rating, time format and the panel readout.

**Files:**
- Create: `scripts/docking_assist.gd`
- Create: `tests/test_docking_assist.gd`

**Interfaces:**
- Consumes: `ApproachGuide.over_rim`, `ApproachGuide.approach_path` (the drift simulation test), `DockingRules.can_dock`, `CockpitHudFormat`.
- Produces:
- `DockingAssist.precision_factor(distance: float) -> float`; `scaled_thrust(input: Vector3, ramp: float, precision: float) -> Vector3`; `brake_velocity(velocity: Vector3, target: Vector3, max_acceleration: float, delta: float) -> Vector3`
- `arrival_time(length: float) -> float`; `plan_arrival(ship: Vector3, pad: Vector3, spin: float, length: float) -> float` (bridge frame); `keeps_plan(time_left: float, length: float, spin: float) -> bool`; `advised_speed(length: float, time_left: float) -> float`; `future_pad(pad: Vector3, spin: float, time: float) -> Vector3`
- `speed_rating(speed, advised) -> int` (`Rating.OK/CAUTION/OVER` = 0/1/2); `format_time(seconds) -> String`; `readout(length, time_left, speed, closing, distance) -> Dictionary` with keys `dist`, `speed`, `advised`, `eta`, `status`, `rating`, `ready`
- Constants `PRECISION_RANGE` 2000, `PRECISION_FLOOR` 200, `PRECISION_MIN` 0.1, `BRAKE_MULTIPLIER` 10, `ADVISED_DECELERATION` 1, `REPLAN_EARLY` 0.3, `REPLAN_LATE` 3, `CAUTION_RATIO` 1.25, `MIN_CLOSING` 0.5, `READY_TEXT` "DOCK READY", `TOO_FAST_TEXT` "TOO FAST".

- [ ] **Step 1: Write the failing tests**

Create `tests/test_docking_assist.gd`:

```gdscript
extends SceneTree

const DockingAssist = preload("res://scripts/docking_assist.gd")
const ApproachGuide = preload("res://scripts/approach_guide.gd")

# The real bridge, in its own frame (see test_approach_guide.gd), turning
# like the real one.
const SECTION_RADIUS := 2000.0
const HALF_GAP := 917.0
const BRIDGE_RADIUS := 600.0
const SPIN := 0.0586
var PAD_ANGLE := 15.5 * TAU / 64.0
var PAD_RADIUS := BRIDGE_RADIUS * cos(PI / 64.0) + 0.3

func _init():
	var failures := 0
	failures += _test_precision_eases_off_near_a_dock()
	failures += _test_thrust_ramps_far_and_scales_near()
	failures += _test_brake_is_limited_per_tick()
	failures += _test_arrival_time_brakes_steadily()
	failures += _test_plan_holds_between_early_and_late()
	failures += _test_plan_waits_for_the_pad_to_come_round()
	failures += _test_advised_speed_arrives_on_time()
	failures += _test_future_pad_turns_with_the_bridge()
	failures += _test_speed_rating()
	failures += _test_time_format()
	failures += _test_readout_lines_and_status()
	failures += _test_planned_arrival_keeps_the_path_still()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _test_precision_eases_off_near_a_dock() -> int:
	var result := 0
	# [distance, factor]: 1x from 2 km out, 0.1x from 200 m in, straight between.
	for c in [[20000.0, 1.0], [2000.0, 1.0], [1100.0, 0.55], [200.0, 0.1], [50.0, 0.1], [0.0, 0.1]]:
		if not is_equal_approx(DockingAssist.precision_factor(c[0]), c[1]):
			print("FAIL _test_precision_eases_off_near_a_dock: %.0f m gave %f, expected %f" % [c[0], DockingAssist.precision_factor(c[0]), c[1]])
			result = 1
	return result

func _test_thrust_ramps_far_and_scales_near() -> int:
	var result := 0
	var input := Vector3(1.0, -1.0, -1.0)
	# Far: only forward thrust takes the ramp.
	if not DockingAssist.scaled_thrust(input, 10.0, 1.0).is_equal_approx(Vector3(1.0, -1.0, -10.0)):
		print("FAIL _test_thrust_ramps_far_and_scales_near: far thrust %s" % DockingAssist.scaled_thrust(input, 10.0, 1.0))
		result = 1
	# Near: every axis scaled, no ramp.
	if not DockingAssist.scaled_thrust(input, 10.0, 0.4).is_equal_approx(input * 0.4):
		print("FAIL _test_thrust_ramps_far_and_scales_near: near thrust %s" % DockingAssist.scaled_thrust(input, 10.0, 0.4))
		result = 1
	return result

func _test_brake_is_limited_per_tick() -> int:
	var result := 0
	var target := Vector3(0.0, 35.0, 0.0)
	# 1000 m/s off at 500 m/s^2: 5 m/s off after a hundredth of a second...
	var braked := DockingAssist.brake_velocity(Vector3(1000.0, 35.0, 0.0), target, 500.0, 0.01)
	if not braked.is_equal_approx(Vector3(995.0, 35.0, 0.0)):
		print("FAIL _test_brake_is_limited_per_tick: one tick gave %s" % braked)
		result = 1
	# ...and exactly on target once within reach, not past it.
	braked = DockingAssist.brake_velocity(Vector3(3.0, 35.0, 0.0), target, 500.0, 0.01)
	if not braked.is_equal_approx(target):
		print("FAIL _test_brake_is_limited_per_tick: the last tick gave %s" % braked)
		result = 1
	return result

func _test_arrival_time_brakes_steadily() -> int:
	# Braking at 1 m/s^2 over 20 km takes 200 s (from 200 m/s).
	if not is_equal_approx(DockingAssist.arrival_time(20000.0), 200.0) or not is_equal_approx(DockingAssist.arrival_time(0.0), 0.0):
		print("FAIL _test_arrival_time_brakes_steadily: 20 km in %f s" % DockingAssist.arrival_time(20000.0))
		return 1
	return 0

func _test_plan_holds_between_early_and_late() -> int:
	var result := 0
	# 20 km takes 200 s braking steadily: with the bridge still, plans from
	# 60 s to 600 s hold; turning, a turn's wait (107 s) more is fine too.
	for c in [[200.0, 0.0, true], [61.0, 0.0, true], [59.0, 0.0, false], [599.0, 0.0, true], [601.0, 0.0, false], [-5.0, 0.0, false], [650.0, SPIN, true], [710.0, SPIN, false]]:
		if DockingAssist.keeps_plan(c[0], 20000.0, c[1]) != c[2]:
			print("FAIL _test_plan_holds_between_early_and_late: %.0f s left for 20 km at spin %.4f, expected %s" % [c[0], c[1], c[2]])
			result = 1
	return result

func _test_plan_waits_for_the_pad_to_come_round() -> int:
	var result := 0
	var pad := Vector3(0.0, 0.0, 600.0)
	# 50 m to go brakes in 10 s. [ship's angle about the axis, spin, planned time]
	for c in [[2.0, 0.1, 20.0], [0.0, 0.1, 10.0 + (TAU - 1.0) / 0.1], [2.0, 0.0, 10.0]]:
		var ship := Vector3(sin(c[0]), 0.0, cos(c[0])) * 3000.0
		var planned: float = DockingAssist.plan_arrival(ship, pad, c[1], 50.0)
		if not is_equal_approx(planned, c[2]):
			print("FAIL _test_plan_waits_for_the_pad_to_come_round: ship at %.1f rad, spin %.1f: %f s, expected %f" % [c[0], c[1], planned, c[2]])
			result = 1
		elif c[1] > 0.0:
			var met := DockingAssist.future_pad(pad, c[1], planned)
			if absf(wrapf(atan2(met.x, met.z) - c[0], -PI, PI)) > 1e-6:
				print("FAIL _test_plan_waits_for_the_pad_to_come_round: the pad is not below the ship then")
				result = 1
	return result

func _test_advised_speed_arrives_on_time() -> int:
	var result := 0
	# 20 km in 200 s braking steadily: start at 200 m/s.
	if not is_equal_approx(DockingAssist.advised_speed(20000.0, 200.0), 200.0):
		print("FAIL _test_advised_speed_arrives_on_time: %f m/s" % DockingAssist.advised_speed(20000.0, 200.0))
		result = 1
	# Late on the plan: faster. Time up: nothing sensible, so 0.
	if not is_equal_approx(DockingAssist.advised_speed(20000.0, 100.0), 400.0) or DockingAssist.advised_speed(500.0, 0.0) != 0.0:
		print("FAIL _test_advised_speed_arrives_on_time: late %f, time up %f" % [DockingAssist.advised_speed(20000.0, 100.0), DockingAssist.advised_speed(500.0, 0.0)])
		result = 1
	return result

func _test_future_pad_turns_with_the_bridge() -> int:
	var pad := Vector3(0.0, 0.0, 600.0)
	var later := DockingAssist.future_pad(pad, 0.5, PI)
	# Half a radian a second for pi seconds: a quarter turn about +Y.
	if not later.is_equal_approx(pad.rotated(Vector3.UP, PI * 0.5)):
		print("FAIL _test_future_pad_turns_with_the_bridge: got %s" % later)
		return 1
	return 0

func _test_speed_rating() -> int:
	var result := 0
	for c in [[40.0, 50.0, DockingAssist.Rating.OK], [50.0, 50.0, DockingAssist.Rating.OK], [62.0, 50.0, DockingAssist.Rating.CAUTION], [63.0, 50.0, DockingAssist.Rating.OVER]]:
		if DockingAssist.speed_rating(c[0], c[1]) != c[2]:
			print("FAIL _test_speed_rating: %.0f against %.0f advised gave %d" % [c[0], c[1], DockingAssist.speed_rating(c[0], c[1])])
			result = 1
	return result

func _test_time_format() -> int:
	var result := 0
	for c in [[42.4, "42 s"], [59.4, "59 s"], [185.0, "3:05"], [-1.0, "—"]]:
		if DockingAssist.format_time(c[0]) != c[1]:
			print("FAIL _test_time_format: %f gave '%s', expected '%s'" % [c[0], DockingAssist.format_time(c[0]), c[1]])
			result = 1
	return result

func _test_readout_lines_and_status() -> int:
	var result := 0
	# 1.2 km to go, 40 s left: advised 60 m/s; 70 m/s is a caution.
	var far: Dictionary = DockingAssist.readout(1200.0, 40.0, 70.0, 60.0, 900.0)
	if far.dist != "DIST  1.2 km" or far.speed != "REL SPEED  70 m/s" or far.advised != "ADVISED  60 m/s" or far.eta != "ETA  20 s" or far.status != "" or far.rating != DockingAssist.Rating.CAUTION or far.ready:
		print("FAIL _test_readout_lines_and_status: far %s" % far)
		result = 1
	# Moving away: no time of arrival.
	if DockingAssist.readout(1200.0, 40.0, 5.0, -5.0, 900.0).eta != "ETA  —":
		print("FAIL _test_readout_lines_and_status: an ETA while moving away")
		result = 1
	# In range: ready when slow enough, too fast otherwise.
	var slow: Dictionary = DockingAssist.readout(120.0, 10.0, 12.0, 12.0, 120.0)
	var fast: Dictionary = DockingAssist.readout(120.0, 10.0, 25.0, 25.0, 120.0)
	if slow.status != DockingAssist.READY_TEXT or not slow.ready or fast.status != DockingAssist.TOO_FAST_TEXT or fast.ready:
		print("FAIL _test_readout_lines_and_status: in range slow %s, fast %s" % [slow.status, fast.status])
		result = 1
	return result

# How far the points of `now` (past its first tenth) lie from the polyline
# `before`, at most.
func _drift(before: PackedVector3Array, now: PackedVector3Array) -> float:
	var worst := 0.0
	for i in range(int(now.size() * 0.1), now.size(), 8):
		var best := INF
		for j in range(1, before.size()):
			best = minf(best, Geometry3D.get_closest_point_to_segment(now[i], before[j - 1], before[j]).distance_to(now[i]))
		worst = maxf(worst, best)
	return worst

# A pilot flying the path at the advised speed, nose on the path 500 m ahead,
# with the bridge turning: the mean speed (m/s) at which the path itself
# moves in space, aiming at the pad as it is (`plan` false) or where it will
# be at the planned arrival.
func _path_drift(plan: bool) -> float:
	var pad := Vector3(sin(PAD_ANGLE), 0.0, cos(PAD_ANGLE)) * PAD_RADIUS
	var ship := Vector3(sin(PAD_ANGLE + 1.0), 0.0, cos(PAD_ANGLE + 1.0)) * 8000.0 + Vector3(0.0, 2000.0, 0.0)
	var nose := (pad - ship).normalized()
	var length := ship.distance_to(pad)
	var arrive := -1.0
	var over := false
	var before := PackedVector3Array()
	var total := 0.0
	var steps := 0
	var dt := 1.0
	for s in range(200):
		var t := s * dt
		var turn := -SPIN * t
		var ship_here := ship.rotated(Vector3.UP, turn)
		var nose_here := nose.rotated(Vector3.UP, turn)
		if arrive < 0.0 or not DockingAssist.keeps_plan(arrive - t, length, SPIN):
			arrive = t + DockingAssist.plan_arrival(ship_here, pad, SPIN, length)
		var target := DockingAssist.future_pad(pad, SPIN, arrive - t) if plan else pad
		over = ApproachGuide.over_rim(ship_here, nose_here, target, SECTION_RADIUS, HALF_GAP, over)
		var path := PackedVector3Array()
		for p in ApproachGuide.approach_path(ship_here, nose_here, target, SECTION_RADIUS, HALF_GAP, BRIDGE_RADIUS, over):
			path.append(p.rotated(Vector3.UP, -turn))
		length = 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		if length < 300.0:
			break
		if not before.is_empty():
			total += _drift(before, path) / dt
			steps += 1
		before = path
		var walked := 0.0
		var k := 1
		while k < path.size() - 1 and walked < 500.0:
			walked += path[k - 1].distance_to(path[k])
			k += 1
		nose = (path[k] - path[0]).normalized()
		ship += nose * DockingAssist.advised_speed(length, arrive - t) * dt
	return total / maxi(steps, 1)

func _test_planned_arrival_keeps_the_path_still() -> int:
	# Aimed at the pad as it is, the path swings round with the bridge;
	# aimed at the planned meeting point it barely moves.
	var still := _path_drift(true)
	var swinging := _path_drift(false)
	if still > 15.0 or still * 5.0 > swinging:
		print("FAIL _test_planned_arrival_keeps_the_path_still: path moves %.0f m/s planned, %.0f m/s unplanned" % [still, swinging])
		return 1
	return 0
```

- [ ] **Step 2: Run them to see them fail**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `SCRIPT ERROR: Parse Error: Preload file "res://scripts/docking_assist.gd" does not exist.` (plus type-inference errors that follow from it).

- [ ] **Step 3: Write the code**

Create `scripts/docking_assist.gd`:

```gdscript
extends RefCounted

# Help for flying to a dock, all pure: thrust that eases off near it, the
# brake that stops the ship against it, the advised speed and the time to
# arrive at it, where the pad will be by then, and the approach panel's
# lines.

const DockingRules = preload("res://scripts/docking_rules.gd")
const CockpitHudFormat = preload("res://scripts/cockpit_hud_format.gd")

# Within PRECISION_RANGE of a dock the thrust drops with the distance, from
# 1x there to PRECISION_MIN at PRECISION_FLOOR and closer, with no ramp.
const PRECISION_RANGE := 2000.0
const PRECISION_FLOOR := 200.0
const PRECISION_MIN := 0.1
# The brake pushes at up to this many times the base thrust (times the
# precision factor near a dock).
const BRAKE_MULTIPLIER := 10.0
# The arrival is planned once: no sooner than braking steadily at
# ADVISED_DECELERATION allows, then on to when the pad, turning with its
# bridge, comes round below the ship. The path aims at that meeting point,
# a place that stays put in space while the bridge turns. The plan is made
# again when the time left falls under REPLAN_EARLY times the steady
# braking time, or grows past REPLAN_LATE times it plus a turn of the
# bridge (the longest the pad can keep the ship waiting).
const ADVISED_DECELERATION := 1.0
const REPLAN_EARLY := 0.3
const REPLAN_LATE := 3.0
# Faster than advised by up to this ratio is a caution; beyond, too fast.
const CAUTION_RATIO := 1.25
# Closing slower than this gives no time of arrival.
const MIN_CLOSING := 0.5
const READY_TEXT := "DOCK READY"
const TOO_FAST_TEXT := "TOO FAST"

enum Rating { OK, CAUTION, OVER }

static func precision_factor(distance: float) -> float:
	if distance >= PRECISION_RANGE:
		return 1.0
	return clampf(lerpf(PRECISION_MIN, 1.0, (distance - PRECISION_FLOOR) / (PRECISION_RANGE - PRECISION_FLOOR)), PRECISION_MIN, 1.0)

# The thrust input to fly with: the forward ramp away from docks, the
# precision factor on every axis near one.
static func scaled_thrust(input: Vector3, ramp: float, precision: float) -> Vector3:
	if precision < 1.0:
		return input * precision
	return Vector3(input.x, input.y, input.z * ramp)

# One tick of braking toward the `target` velocity, changing it by at most
# `max_acceleration` * delta.
static func brake_velocity(velocity: Vector3, target: Vector3, max_acceleration: float, delta: float) -> Vector3:
	return velocity + (target - velocity).limit_length(max_acceleration * delta)

# How long braking steadily at ADVISED_DECELERATION takes to stop at the
# pad, `length` metres along the path.
static func arrival_time(length: float) -> float:
	return sqrt(2.0 * maxf(length, 0.0) / ADVISED_DECELERATION)

# The planned time to arrival, from the ship and the pad in the bridge's
# frame (axis = Y), the bridge turning at `spin` rad/s: the steady braking
# time for `length`, then the wait until the pad is round below the ship.
static func plan_arrival(ship: Vector3, pad: Vector3, spin: float, length: float) -> float:
	var steady := arrival_time(length)
	if spin <= 0.0:
		return steady
	var behind := atan2(ship.x, ship.z) - atan2(pad.x, pad.z) - spin * steady
	return steady + fposmod(behind, TAU) / spin

# Whether an arrival `time_left` seconds away still fits `length` to go.
static func keeps_plan(time_left: float, length: float, spin: float) -> bool:
	var steady := arrival_time(length)
	var turn := TAU / spin if spin > 0.0 else 0.0
	return time_left > steady * REPLAN_EARLY and time_left < steady * REPLAN_LATE + turn

# The speed that arrives on time braking steadily: the average speed is
# half of it.
static func advised_speed(length: float, time_left: float) -> float:
	if time_left <= 0.0:
		return 0.0
	return 2.0 * maxf(length, 0.0) / time_left

# Where the pad (in its bridge's frame, axis = Y) will be `time` seconds
# from now, the bridge turning at `spin` rad/s about its axis.
static func future_pad(pad: Vector3, spin: float, time: float) -> Vector3:
	return pad.rotated(Vector3.UP, spin * time)

static func speed_rating(speed: float, advised: float) -> int:
	if speed <= advised:
		return Rating.OK
	if speed <= advised * CAUTION_RATIO:
		return Rating.CAUTION
	return Rating.OVER

# "42 s" under a minute, "3:05" beyond; a dash for no reading (negative).
static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return CockpitHudFormat.NO_READING
	var whole := roundi(seconds)
	if whole < 60:
		return "%d s" % whole
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]

# The approach panel: `length` to go along the path, `time_left` to the
# planned arrival, `speed` and `closing` (toward the dock along the path)
# relative to the pad, `distance` to the pad in a straight line (for the
# docking rule).
static func readout(length: float, time_left: float, speed: float, closing: float, distance: float) -> Dictionary:
	var advised := advised_speed(length, time_left)
	var eta := length / closing if closing >= MIN_CLOSING else -1.0
	var ready := DockingRules.can_dock(distance, speed)
	var status := ""
	if ready:
		status = READY_TEXT
	elif distance <= DockingRules.DOCK_RANGE:
		status = TOO_FAST_TEXT
	return {
		"dist": "DIST  " + CockpitHudFormat.format_distance(length),
		"speed": "REL SPEED  " + CockpitHudFormat.format_speed(speed),
		"advised": "ADVISED  " + CockpitHudFormat.format_speed(advised),
		"eta": "ETA  " + format_time(eta),
		"status": status,
		"rating": speed_rating(speed, advised),
		"ready": ready,
	}
```

Then run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import > /dev/null 2>&1` (new script).

- [ ] **Step 4: Run the tests to see them pass**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

- [ ] **Step 5: Commit**

```bash
git add scripts/docking_assist.gd tests/test_docking_assist.gd
git add -A scripts/*.uid tests/*.uid
git commit -m "Add the docking assist helpers: precision thrust, brake step, planned arrival, advised speed and panel readout

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: The brake on B

B brakes the ship to the nearest dock's velocity (to rest past 20 km) and holds it; C and B exclude each other; thrust keys release it; the HUD shows BRAKE.

**Files:**
- Modify: `project.godot`
- Modify: `scripts/cockpit.gd`
- Modify: `scripts/void_cruiser.gd`
- Modify: `tests/test_cockpit.gd`
- Create: `tests/test_docking_assist_in_tree.gd`
- Modify: `tests/test_scene_wiring.gd`
- Modify: `tests/test_void_cruiser.gd`

**Interfaces:**
- Consumes: Task 1: `DockingAssist.brake_velocity`, `BRAKE_MULTIPLIER`.
- Produces:
- Input action `brake` on B (`physical_keycode` 66).
- Void cruiser: `brake_engaged: bool`, `BRAKE_RELEASE_ACTIONS`, `_fly(delta)` override, `_nearest_dock() -> Dictionary` (`station`, `index`, `port`, `distance`, `velocity`; empty off-tree, without station, or past `ApproachGuide.MAX_RANGE`).
- Cockpit: `BrakeLabel` (after `CruiseLabel`), `set_brake(active: bool)`.
- New test file `tests/test_docking_assist_in_tree.gd` with `_park(distance, nose)`, `_press(action)`, `_fly(ticks)` helpers and a `# (more tests)` marker line in `_initialize` that later tasks replace.

- [ ] **Step 1: Write the failing tests**

In `tests/test_scene_wiring.gd`, after:

```gdscript
	failures += _test_no_flight_assist_key()
```

add:

```gdscript
	failures += _test_brake_action_is_bound_to_b()
```

At the end of `tests/test_scene_wiring.gd` append, after one blank line:

```gdscript
func _test_brake_action_is_bound_to_b() -> int:
	if not InputMap.has_action("brake") or _key_codes("brake") != [KEY_B]:
		print("FAIL _test_brake_action_is_bound_to_b: no 'brake' action on the B key")
		return 1
	return 0
```

In `tests/test_cockpit.gd` replace:

```gdscript
	var expected := ["SpeedLabel", "CruiseLabel", "BowLabel",
```

with:

```gdscript
	var expected := ["SpeedLabel", "CruiseLabel", "BrakeLabel", "BowLabel",
```

In `tests/test_cockpit.gd`, after:

```gdscript
	failures += _test_cruise_line_shown_only_while_cruising()
```

add:

```gdscript
	failures += _test_brake_line_shown_only_while_braking()
```

At the end of `tests/test_cockpit.gd` append, after one blank line:

```gdscript
func _test_brake_line_shown_only_while_braking() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var label := cockpit.get_node_or_null("Hud/Panel/Lines/BrakeLabel") as Label
	if label == null or label.visible or label.text != "BRAKE":
		print("FAIL _test_brake_line_shown_only_while_braking: missing, shown from the start, or not 'BRAKE'")
		cockpit.free()
		return 1
	cockpit.set_brake(true)
	if not label.visible:
		print("FAIL _test_brake_line_shown_only_while_braking: set_brake(true) did not show it")
		result = 1
	cockpit.set_brake(false)
	if label.visible:
		print("FAIL _test_brake_line_shown_only_while_braking: set_brake(false) did not hide it")
		result = 1
	cockpit.free()
	return result
```

In `tests/test_void_cruiser.gd`, after:

```gdscript
	failures += _test_process_feeds_the_navball()
```

add:

```gdscript
	failures += _test_brake_key_toggles_and_turns_cruise_off()
	failures += _test_thrust_keys_release_the_brake()
	failures += _test_brake_stops_the_ship_at_ten_times_thrust()
```

At the end of `tests/test_void_cruiser.gd` append, after one blank line:

```gdscript
func _test_brake_key_toggles_and_turns_cruise_off() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	_press(cruiser, "cruise")
	_press(cruiser, "brake")
	if not cruiser.brake_engaged or cruiser.cruise_locked:
		print("FAIL _test_brake_key_toggles_and_turns_cruise_off: B gave brake %s, cruise %s" % [cruiser.brake_engaged, cruiser.cruise_locked])
		result = 1
	_press(cruiser, "cruise")
	if cruiser.brake_engaged or not cruiser.cruise_locked:
		print("FAIL _test_brake_key_toggles_and_turns_cruise_off: C after B gave brake %s, cruise %s" % [cruiser.brake_engaged, cruiser.cruise_locked])
		result = 1
	cruiser.cruise_locked = false
	_press(cruiser, "brake")
	_press(cruiser, "brake")
	if cruiser.brake_engaged:
		print("FAIL _test_brake_key_toggles_and_turns_cruise_off: a second B left the brake on")
		result = 1
	cruiser.free()
	return result

func _test_thrust_keys_release_the_brake() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	for action in ["move_forward", "move_backward", "move_left", "move_right", "move_up", "move_down"]:
		_press(cruiser, "brake")
		_press(cruiser, action)
		if cruiser.brake_engaged:
			print("FAIL _test_thrust_keys_release_the_brake: %s left the brake on" % action)
			result = 1
			cruiser.brake_engaged = false
	# Rolling does not.
	_press(cruiser, "brake")
	_press(cruiser, "roll_left")
	if not cruiser.brake_engaged:
		print("FAIL _test_thrust_keys_release_the_brake: rolling let go of the brake")
		result = 1
	cruiser.free()
	return result

func _test_brake_stops_the_ship_at_ten_times_thrust() -> int:
	# Away from any dock the brake stops the ship: 50 m/s^2 base thrust,
	# 500 m/s^2 braking, so 300 m/s takes 0.6 s.
	var cruiser := _make_cruiser()
	var result := 0
	cruiser.velocity = Vector3(300.0, 0.0, 0.0)
	_press(cruiser, "brake")
	for i in range(20):
		cruiser._physics_process(1.0 / 60.0)
	if absf(cruiser.velocity.x - (300.0 - 500.0 / 3.0)) > 0.5:
		print("FAIL _test_brake_stops_the_ship_at_ten_times_thrust: %s after 1/3 s, expected %.1f m/s" % [cruiser.velocity, 300.0 - 500.0 / 3.0])
		result = 1
	for i in range(40):
		cruiser._physics_process(1.0 / 60.0)
	if not cruiser.velocity.is_zero_approx() or not cruiser.brake_engaged:
		print("FAIL _test_brake_stops_the_ship_at_ten_times_thrust: %s after 1 s, brake %s" % [cruiser.velocity, cruiser.brake_engaged])
		result = 1
	cruiser.free()
	return result
```

Create `tests/test_docking_assist_in_tree.gd`:

```gdscript
extends SceneTree

# Docking help on the real scene: the brake against the pad, the precision
# thrust, the approach panel and the planned meeting point.

const ApproachGuide = preload("res://scripts/approach_guide.gd")
const DockingAssist = preload("res://scripts/docking_assist.gd")

const TICK := 1.0 / 60.0

var _failures := 0
var _scene: Node3D
var _cruiser: CharacterBody3D
var _station: Node3D

func _initialize():
	_scene = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	_cruiser = _scene.get_node("VoidCruiser")
	_station = _scene.get_node("PlanetSystem/TorusStation")
	_cruiser.set_physics_process(false)
	_station.set_process(false)

	_failures += await _test_brake_stops_the_ship_against_the_pad()
	# (more tests)

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

# Parks the ship `distance` out from port 0 along its outward axis, nose
# along `nose` (in the port's axes: x out, y along the bridge, z across),
# at rest with the pad. The world shifts on the next tick.
func _park(distance: float, nose: Vector3 = Vector3(-1.0, 0.0, 0.0)) -> void:
	var port: Node3D = _station.get_docking_port(0)
	var axes: Basis = port.global_transform.basis.orthonormalized()
	var at: Vector3 = port.global_position + axes.x * distance
	var up: Vector3 = axes.y if absf(nose.y) < 0.9 else axes.x
	_cruiser.global_transform = Transform3D(Basis.looking_at(axes * nose, up), at)
	_cruiser.velocity = _station.get_docking_port_velocity(0)
	_cruiser.brake_engaged = false
	_cruiser.cruise_locked = false
	for i in range(3):
		await physics_frame
		await process_frame

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_cruiser._unhandled_input(event)

func _fly(ticks: int) -> void:
	for i in range(ticks):
		_cruiser._physics_process(TICK)

func _test_brake_stops_the_ship_against_the_pad() -> int:
	# 5 km out, drifting 300 m/s against the pad: B brings it to the pad's
	# own velocity (it turns with the bridge) in well under a second.
	await _park(5000.0)
	_cruiser.velocity += Vector3(300.0, -120.0, 40.0)
	_press("brake")
	_fly(30)
	var off: Vector3 = _cruiser.velocity - _station.get_docking_port_velocity(0)
	if off.length() > 0.01 or not _cruiser.brake_engaged:
		print("FAIL _test_brake_stops_the_ship_against_the_pad: %.2f m/s off the pad after 0.5 s, brake %s" % [off.length(), _cruiser.brake_engaged])
		return 1
	return 0
```

Then run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import > /dev/null 2>&1` (new test file).

- [ ] **Step 2: Run them to see them fail**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_scene_wiring.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `FAIL _test_brake_action_is_bound_to_b: no 'brake' action on the B key`, `1 TEST(S) FAILED`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `FAIL _test_hud_lines_in_display_order: ...` and `FAIL _test_brake_line_shown_only_while_braking: missing, shown from the start, or not 'BRAKE'`, `2 TEST(S) FAILED`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `SCRIPT ERROR: Invalid access to property or key 'brake_engaged' ...` lines and `FAIL _test_brake_stops_the_ship_at_ten_times_thrust: (300.0, 0.0, 0.0) after 1/3 s, expected 133.3 m/s`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `SCRIPT ERROR: Invalid assignment of property or key 'brake_engaged' ...` (the summary line still reads ALL TESTS PASSED: the script error is the RED)

- [ ] **Step 3: Write the code**

In `project.godot` replace:

```ini
cruise={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":67,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

with:

```ini
cruise={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":67,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
brake={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":66,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

In `scripts/cockpit.gd` replace:

```gdscript
const CRUISE_COLOR := Color(1.0, 0.8, 0.3)
```

with:

```gdscript
const CRUISE_COLOR := Color(1.0, 0.8, 0.3)
const BRAKE_TEXT := "BRAKE"
const BRAKE_COLOR := Color(1.0, 0.45, 0.3)
```

In `scripts/cockpit.gd` replace:

```gdscript
func set_cruise(active: bool) -> void:
	(get_node("Hud/Panel/Lines/CruiseLabel") as Label).visible = active
```

with:

```gdscript
func set_cruise(active: bool) -> void:
	(get_node("Hud/Panel/Lines/CruiseLabel") as Label).visible = active

func set_brake(active: bool) -> void:
	(get_node("Hud/Panel/Lines/BrakeLabel") as Label).visible = active
```

In `scripts/cockpit.gd` replace:

```gdscript
	cruise_label.text = CRUISE_TEXT
	cruise_label.visible = false
```

with:

```gdscript
	cruise_label.text = CRUISE_TEXT
	cruise_label.visible = false
	var brake_settings := LabelSettings.new()
	brake_settings.font_size = HUD_FONT_SIZE
	brake_settings.font_color = BRAKE_COLOR
	_add_hud_label(lines, "BrakeLabel", brake_settings)
	var brake_label: Label = lines.get_node("BrakeLabel")
	brake_label.text = BRAKE_TEXT
	brake_label.visible = false
```

In `scripts/void_cruiser.gd` replace:

```gdscript
const Attitude = preload("res://scripts/attitude.gd")
```

with:

```gdscript
const Attitude = preload("res://scripts/attitude.gd")
const DockingAssist = preload("res://scripts/docking_assist.gd")
```

In `scripts/void_cruiser.gd` replace:

```gdscript
# C holds the current velocity: the thrusters cancel the orbital pulls. A
# new press of W/A/S/D, or C again, lets go; roll, mouse and up/down do not
# (up/down change the held velocity).
const CRUISE_RELEASE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right"]
```

with:

```gdscript
# C holds the current velocity: the thrusters cancel the orbital pulls. A
# new press of W/A/S/D, or C again, lets go; roll, mouse and up/down do not
# (up/down change the held velocity).
const CRUISE_RELEASE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right"]
# B brakes to the nearest dock's velocity (to rest past MAX_RANGE of the
# guide) and holds it, cancelling the orbital pulls too. B again, or any
# thrust key, lets go. C and B turn each other off.
const BRAKE_RELEASE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right", "move_up", "move_down"]
```

In `scripts/void_cruiser.gd` replace:

```gdscript
var cruise_locked := false
```

with:

```gdscript
var cruise_locked := false
var brake_engaged := false
```

In `scripts/void_cruiser.gd` replace:

```gdscript
		cockpit.set_cruise(cruise_locked)
```

with:

```gdscript
		cockpit.set_cruise(cruise_locked)
		cockpit.set_brake(brake_engaged)
```

In `scripts/void_cruiser.gd` replace:

```gdscript
	if event.is_action_pressed("cruise"):
		cruise_locked = not cruise_locked
	elif cruise_locked:
		for action in CRUISE_RELEASE_ACTIONS:
			if event.is_action_pressed(action):
				cruise_locked = false
```

with:

```gdscript
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
```

In `scripts/void_cruiser.gd` replace:

```gdscript
	# Holding velocity: the thrusters cancel the orbital pulls.
	if not has_planet or cruise_locked:
```

with:

```gdscript
	# Holding velocity or braking: the thrusters cancel the orbital pulls.
	if not has_planet or cruise_locked or brake_engaged:
```

In `scripts/void_cruiser.gd` replace:

```gdscript
func ring_omega() -> Vector3:
```

with:

```gdscript
# The brake steers the velocity to the nearest dock's (to rest away from
# docks) at up to BRAKE_MULTIPLIER times the base thrust.
func _fly(delta: float) -> void:
	var thrust_input := _read_thrust_input()
	_update_forward_hold_time(thrust_input.z, delta)
	thrust_input.z *= forward_thrust_multiplier()
	if brake_engaged:
		var dock := _nearest_dock()
		var target: Vector3 = Vector3.ZERO if dock.is_empty() else dock.velocity
		velocity = DockingAssist.brake_velocity(velocity, target, thrust_power * DockingAssist.BRAKE_MULTIPLIER, delta)
	_apply_physics_step(delta, thrust_input, _read_torque_input(delta))

# The nearest dock within the guide's MAX_RANGE: station, bridge index,
# port, straight distance to the pad and the pad's velocity. Empty off the
# tree, with no station, or past that range.
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
	return {"station": station, "index": index, "port": port, "distance": distance, "velocity": station.get_docking_port_velocity(index)}

func ring_omega() -> Vector3:
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_scene_wiring.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

- [ ] **Step 5: Commit**

```bash
git add project.godot scripts/cockpit.gd scripts/void_cruiser.gd tests/test_cockpit.gd tests/test_docking_assist_in_tree.gd tests/test_scene_wiring.gd tests/test_void_cruiser.gd
git add -A scripts/*.uid tests/*.uid
git commit -m "Brake on B: stop against the nearest dock and hold, C and B exclusive, thrust keys let go

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Precision thrust near a dock

Within 2 km every thruster scales with the distance (1x at 2 km to 0.1x at 200 m), no ramp; the brake scales too; the HUD shows THRUST 0.4x.

**Files:**
- Modify: `scripts/cockpit.gd`
- Modify: `scripts/void_cruiser.gd`
- Modify: `tests/test_cockpit.gd`
- Modify: `tests/test_docking_assist_in_tree.gd`

**Interfaces:**
- Consumes: Task 1: `precision_factor`, `scaled_thrust`. Task 2: `_fly`, `_nearest_dock`, the in-tree test file.
- Produces:
- Void cruiser: `thrust_scale: float` (this tick's precision factor). Cockpit: `ThrustLabel` (after `BrakeLabel`), `set_thrust_scale(scale: float)`, `THRUST_TEXT`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_cockpit.gd` replace:

```gdscript
	var expected := ["SpeedLabel", "CruiseLabel", "BrakeLabel", "BowLabel",
```

with:

```gdscript
	var expected := ["SpeedLabel", "CruiseLabel", "BrakeLabel", "ThrustLabel", "BowLabel",
```

In `tests/test_cockpit.gd`, after:

```gdscript
	failures += _test_brake_line_shown_only_while_braking()
```

add:

```gdscript
	failures += _test_thrust_line_shows_the_scale_near_a_dock()
```

At the end of `tests/test_cockpit.gd` append, after one blank line:

```gdscript
func _test_thrust_line_shows_the_scale_near_a_dock() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var label := cockpit.get_node_or_null("Hud/Panel/Lines/ThrustLabel") as Label
	if label == null or label.visible:
		print("FAIL _test_thrust_line_shows_the_scale_near_a_dock: missing or shown from the start")
		cockpit.free()
		return 1
	cockpit.set_thrust_scale(0.4)
	if not label.visible or label.text != "THRUST  0.4x":
		print("FAIL _test_thrust_line_shows_the_scale_near_a_dock: 0.4 gave visible %s, '%s'" % [label.visible, label.text])
		result = 1
	cockpit.set_thrust_scale(1.0)
	if label.visible:
		print("FAIL _test_thrust_line_shows_the_scale_near_a_dock: full thrust still shown")
		result = 1
	cockpit.free()
	return result
```

In `tests/test_docking_assist_in_tree.gd` replace:

```gdscript
	# (more tests)
```

with:

```gdscript
	_failures += await _test_thrust_eases_off_near_the_dock()
	# (more tests)
```

At the end of `tests/test_docking_assist_in_tree.gd` append, after one blank line:

```gdscript
func _test_thrust_eases_off_near_the_dock() -> int:
	var result := 0
	# 1100 m out, nose across the bridge (the distance barely changes): half
	# of 150 m/s^2 and no ramp, so about 82 m/s after a second of W.
	await _park(1100.0, Vector3(0.0, 0.0, 1.0))
	var start: Vector3 = _cruiser.velocity
	Input.action_press("move_forward")
	_fly(60)
	Input.action_release("move_forward")
	var gained: float = (_cruiser.velocity - start).length()
	if absf(gained - 150.0 * 0.55) > 3.0 or absf(_cruiser.thrust_scale - 0.55) > 0.02:
		print("FAIL _test_thrust_eases_off_near_the_dock: gained %.1f m/s in 1 s at scale %.2f, expected about 82.5 at 0.55" % [gained, _cruiser.thrust_scale])
		result = 1
	await process_frame
	if not (_cruiser.get_node("Cockpit/Hud/Panel/Lines/ThrustLabel") as Label).visible:
		print("FAIL _test_thrust_eases_off_near_the_dock: the THRUST line is hidden at 1.1 km")
		result = 1
	# 5 km out: full thrust with the ramp, and no THRUST line.
	await _park(5000.0)
	_fly(1)
	await process_frame
	if _cruiser.thrust_scale != 1.0 or (_cruiser.get_node("Cockpit/Hud/Panel/Lines/ThrustLabel") as Label).visible:
		print("FAIL _test_thrust_eases_off_near_the_dock: scale %.2f at 5 km" % _cruiser.thrust_scale)
		result = 1
	return result
```

- [ ] **Step 2: Run them to see them fail**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `FAIL _test_hud_lines_in_display_order: ...` and `FAIL _test_thrust_line_shows_the_scale_near_a_dock: missing or shown from the start`, `2 TEST(S) FAILED`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `SCRIPT ERROR: Invalid access to property or key 'thrust_scale' ...`

- [ ] **Step 3: Write the code**

In `scripts/cockpit.gd` replace:

```gdscript
const BRAKE_COLOR := Color(1.0, 0.45, 0.3)
```

with:

```gdscript
const BRAKE_COLOR := Color(1.0, 0.45, 0.3)
const THRUST_TEXT := "THRUST  %.1fx"
```

In `scripts/cockpit.gd` replace:

```gdscript
func set_brake(active: bool) -> void:
	(get_node("Hud/Panel/Lines/BrakeLabel") as Label).visible = active
```

with:

```gdscript
func set_brake(active: bool) -> void:
	(get_node("Hud/Panel/Lines/BrakeLabel") as Label).visible = active

# Shown only while the thrust is scaled down near a dock.
func set_thrust_scale(scale: float) -> void:
	var label := get_node("Hud/Panel/Lines/ThrustLabel") as Label
	label.visible = scale < 1.0
	label.text = THRUST_TEXT % scale
```

In `scripts/cockpit.gd` replace:

```gdscript
	brake_label.text = BRAKE_TEXT
	brake_label.visible = false
```

with:

```gdscript
	brake_label.text = BRAKE_TEXT
	brake_label.visible = false
	_add_hud_label(lines, "ThrustLabel", label_settings)
	(lines.get_node("ThrustLabel") as Label).visible = false
```

In `scripts/void_cruiser.gd` replace:

```gdscript
var brake_engaged := false
```

with:

```gdscript
var brake_engaged := false
# The precision factor this tick (1 away from docks; see DockingAssist).
var thrust_scale := 1.0
```

In `scripts/void_cruiser.gd` replace:

```gdscript
		cockpit.set_brake(brake_engaged)
```

with:

```gdscript
		cockpit.set_brake(brake_engaged)
		cockpit.set_thrust_scale(thrust_scale)
```

In `scripts/void_cruiser.gd` replace:

```gdscript
# The brake steers the velocity to the nearest dock's (to rest away from
# docks) at up to BRAKE_MULTIPLIER times the base thrust.
func _fly(delta: float) -> void:
	var thrust_input := _read_thrust_input()
	_update_forward_hold_time(thrust_input.z, delta)
	thrust_input.z *= forward_thrust_multiplier()
	if brake_engaged:
		var dock := _nearest_dock()
		var target: Vector3 = Vector3.ZERO if dock.is_empty() else dock.velocity
		velocity = DockingAssist.brake_velocity(velocity, target, thrust_power * DockingAssist.BRAKE_MULTIPLIER, delta)
```

with:

```gdscript
# Near a dock the precision factor scales every thruster and stops the
# ramp. The brake steers the velocity to the nearest dock's (to rest away
# from docks) at up to BRAKE_MULTIPLIER times the base thrust, scaled too.
func _fly(delta: float) -> void:
	var thrust_input := _read_thrust_input()
	_update_forward_hold_time(thrust_input.z, delta)
	var dock := _nearest_dock()
	thrust_scale = 1.0 if dock.is_empty() else DockingAssist.precision_factor(dock.distance)
	thrust_input = DockingAssist.scaled_thrust(thrust_input, forward_thrust_multiplier(), thrust_scale)
	if brake_engaged:
		var target: Vector3 = Vector3.ZERO if dock.is_empty() else dock.velocity
		velocity = DockingAssist.brake_velocity(velocity, target, thrust_power * DockingAssist.BRAKE_MULTIPLIER * thrust_scale, delta)
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

- [ ] **Step 5: Commit**

```bash
git add scripts/cockpit.gd scripts/void_cruiser.gd tests/test_cockpit.gd tests/test_docking_assist_in_tree.gd
git add -A scripts/*.uid tests/*.uid
git commit -m "Ease the thrust off near a dock: 1x at 2 km down to 0.1x at 200 m, no ramp, shown on the HUD

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: The approach panel and the planned arrival

A top-right panel within 20 km: distance along the path, speed relative to the pad (coloured against the advised speed), advised speed, ETA and DOCK READY / TOO FAST. The arrival is planned for when the pad comes round below the ship.

**Files:**
- Modify: `scripts/cockpit.gd`
- Modify: `scripts/torus_station.gd`
- Modify: `scripts/void_cruiser.gd`
- Modify: `tests/test_cockpit.gd`
- Modify: `tests/test_docking_assist_in_tree.gd`
- Modify: `tests/test_torus_station.gd`

**Interfaces:**
- Consumes: Task 1: `plan_arrival`, `keeps_plan`, `readout`. Task 2: `_nearest_dock`.
- Produces:
- Station: `get_spin_rate() -> float`.
- Cockpit: `ApproachPanel` (PanelContainer, top right, `Lines` with `DistLabel`, `RelSpeedLabel`, `AdvisedLabel`, `EtaLabel`, `StatusLabel`), `update_approach(readout: Dictionary)`, `APPROACH_LINES`, `APPROACH_COLORS`, `APPROACH_PANEL_WIDTH`.
- Void cruiser: `_guide_length`, `_guide_clock`, `_arrival_at`; `_update_approach_guide() -> Dictionary` (the readout; empty past 20 km).

- [ ] **Step 1: Write the failing tests**

In `tests/test_cockpit.gd`, after:

```gdscript
	failures += _test_thrust_line_shows_the_scale_near_a_dock()
```

add:

```gdscript
	failures += _test_approach_panel_top_right_hidden_until_fed()
	failures += _test_approach_panel_writes_and_colours_the_readout()
```

At the end of `tests/test_cockpit.gd` append, after one blank line:

```gdscript
func _test_approach_panel_top_right_hidden_until_fed() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var panel := cockpit.get_node_or_null("Hud/ApproachPanel") as Control
	if panel == null or panel.visible or not is_equal_approx(panel.anchor_left, 1.0) or not is_equal_approx(panel.anchor_right, 1.0) or not is_equal_approx(panel.offset_right, -cockpit.HUD_MARGIN) or not is_equal_approx(panel.offset_top, cockpit.HUD_MARGIN):
		print("FAIL _test_approach_panel_top_right_hidden_until_fed: missing, shown from the start, or not top right")
		cockpit.free()
		return 1
	var names: Array = []
	for child in panel.get_node("Lines").get_children():
		names.append(String(child.name))
	if names != ["DistLabel", "RelSpeedLabel", "AdvisedLabel", "EtaLabel", "StatusLabel"]:
		print("FAIL _test_approach_panel_top_right_hidden_until_fed: lines %s" % [names])
		result = 1
	cockpit.free()
	return result

func _test_approach_panel_writes_and_colours_the_readout() -> int:
	var cockpit := _make_cockpit()
	var result := 0
	var lines := cockpit.get_node("Hud/ApproachPanel/Lines")
	var readout := {"dist": "DIST  1.2 km", "speed": "REL SPEED  70 m/s", "advised": "ADVISED  60 m/s", "eta": "ETA  20 s", "status": "", "rating": 1, "ready": false}
	cockpit.update_approach(readout)
	var speed := lines.get_node("RelSpeedLabel") as Label
	if not (cockpit.get_node("Hud/ApproachPanel") as Control).visible or (lines.get_node("DistLabel") as Label).text != "DIST  1.2 km" or speed.text != "REL SPEED  70 m/s" or (lines.get_node("EtaLabel") as Label).text != "ETA  20 s" or not speed.label_settings.font_color.is_equal_approx(cockpit.APPROACH_COLORS[1]) or (lines.get_node("StatusLabel") as Label).visible:
		print("FAIL _test_approach_panel_writes_and_colours_the_readout: far readout not shown as expected")
		result = 1
	readout.status = "DOCK READY"
	readout.ready = true
	readout.rating = 0
	cockpit.update_approach(readout)
	var status := lines.get_node("StatusLabel") as Label
	if not status.visible or status.text != "DOCK READY" or not status.label_settings.font_color.is_equal_approx(cockpit.APPROACH_COLORS[0]):
		print("FAIL _test_approach_panel_writes_and_colours_the_readout: ready status not shown green")
		result = 1
	cockpit.update_approach({})
	if (cockpit.get_node("Hud/ApproachPanel") as Control).visible:
		print("FAIL _test_approach_panel_writes_and_colours_the_readout: an empty readout left it shown")
		result = 1
	cockpit.free()
	return result
```

In `tests/test_docking_assist_in_tree.gd` replace:

```gdscript
	# (more tests)
```

with:

```gdscript
	_failures += await _test_panel_shows_within_range()
	_failures += await _test_panel_says_when_docking_is_possible()
	# (more tests)
```

At the end of `tests/test_docking_assist_in_tree.gd` append, after one blank line:

```gdscript
func _panel() -> Control:
	return _cruiser.get_node("Cockpit/Hud/ApproachPanel")

func _panel_text(label: String) -> String:
	return (_cruiser.get_node("Cockpit/Hud/ApproachPanel/Lines/" + label) as Label).text

func _test_panel_shows_within_range() -> int:
	var result := 0
	await _park(5000.0)
	# At rest with the pad: no time of arrival, an advised speed to start at.
	if not _panel().visible or not _panel_text("DistLabel").begins_with("DIST  ") or _panel_text("EtaLabel") != "ETA  —" or _panel_text("RelSpeedLabel") != "REL SPEED  0 m/s":
		print("FAIL _test_panel_shows_within_range: at 5 km visible %s, '%s' '%s' '%s'" % [_panel().visible, _panel_text("DistLabel"), _panel_text("EtaLabel"), _panel_text("RelSpeedLabel")])
		result = 1
	await _park(25000.0)
	if _panel().visible:
		print("FAIL _test_panel_shows_within_range: shown 25 km from the nearest dock")
		result = 1
	return result

func _test_panel_says_when_docking_is_possible() -> int:
	var result := 0
	# 120 m out, inside the 150 m docking range: the panel says whether
	# docking works now.
	await _park(120.0)
	var status := _cruiser.get_node("Cockpit/Hud/ApproachPanel/Lines/StatusLabel") as Label
	if not _panel().visible or not status.visible or status.text != DockingAssist.READY_TEXT:
		print("FAIL _test_panel_says_when_docking_is_possible: at rest 120 m out, visible %s, status '%s'" % [_panel().visible, status.text])
		result = 1
	_cruiser.velocity = _station.get_docking_port_velocity(0) + Vector3(25.0, 0.0, 0.0)
	await process_frame
	if status.text != DockingAssist.TOO_FAST_TEXT:
		print("FAIL _test_panel_says_when_docking_is_possible: 25 m/s against the pad gave '%s'" % status.text)
		result = 1
	return result
```

In `tests/test_torus_station.gd`, after:

```gdscript
	failures += _test_bridge_radius_and_length_helpers()
```

add:

```gdscript
	failures += _test_spin_rate_is_public()
```

At the end of `tests/test_torus_station.gd` append, after one blank line:

```gdscript
func _test_spin_rate_is_public() -> int:
	# 1 g on a 30 m radius: sqrt(9.81 / 30) rad/s.
	var station := _make_station(4)
	var result := 0
	if not is_equal_approx(station.get_spin_rate(), sqrt(9.81 / 30.0)):
		print("FAIL _test_spin_rate_is_public: %f rad/s" % station.get_spin_rate())
		result = 1
	station.free()
	return result
```

- [ ] **Step 2: Run them to see them fail**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_torus_station.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `SCRIPT ERROR: Invalid call. Nonexistent function 'get_spin_rate' in base 'Node3D (torus_station.gd)'.`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `FAIL _test_approach_panel_top_right_hidden_until_fed: missing, shown from the start, or not top right` and `SCRIPT ERROR: Invalid call. Nonexistent function 'update_approach' ...`

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `SCRIPT ERROR: Invalid access to property or key 'visible' on a base object of type 'null instance'.` (twice)

- [ ] **Step 3: Write the code**

In `scripts/cockpit.gd` replace:

```gdscript
const THRUST_TEXT := "THRUST  %.1fx"
```

with:

```gdscript
const THRUST_TEXT := "THRUST  %.1fx"
# The approach panel, top right: readout key -> label, in display order.
const APPROACH_LINES := {
	"dist": "DistLabel",
	"speed": "RelSpeedLabel",
	"advised": "AdvisedLabel",
	"eta": "EtaLabel",
	"status": "StatusLabel",
}
const APPROACH_PANEL_WIDTH := 300.0
# By DockingAssist.Rating: OK, CAUTION, OVER.
const APPROACH_COLORS := [Color(0.3, 1.0, 0.4), Color(1.0, 0.8, 0.3), Color(1.0, 0.3, 0.25)]
```

In `scripts/cockpit.gd` replace:

```gdscript
# Shown only while the thrust is scaled down near a dock.
```

with:

```gdscript
# The approach panel from a DockingAssist.readout; hidden when empty. The
# relative speed is coloured by its rating, the status green when ready.
func update_approach(readout: Dictionary) -> void:
	var panel := get_node("Hud/ApproachPanel") as Control
	panel.visible = not readout.is_empty()
	if readout.is_empty():
		return
	var lines := panel.get_node("Lines")
	for key in APPROACH_LINES:
		(lines.get_node(APPROACH_LINES[key]) as Label).text = readout[key]
	(lines.get_node("RelSpeedLabel") as Label).label_settings.font_color = APPROACH_COLORS[readout.rating]
	var status := lines.get_node("StatusLabel") as Label
	status.visible = readout.status != ""
	status.label_settings.font_color = APPROACH_COLORS[0] if readout.ready else APPROACH_COLORS[2]

# Shown only while the thrust is scaled down near a dock.
```

In `scripts/cockpit.gd` replace:

```gdscript
	# Top centre.
	var navball: Control = NavballScript.new()
```

with:

```gdscript
	# Top right, growing leftward: the approach to the nearest dock.
	var approach := PanelContainer.new()
	approach.name = "ApproachPanel"
	approach.anchor_left = 1.0
	approach.anchor_right = 1.0
	approach.offset_left = -HUD_MARGIN - APPROACH_PANEL_WIDTH
	approach.offset_right = -HUD_MARGIN
	approach.offset_top = HUD_MARGIN
	approach.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	approach.add_theme_stylebox_override("panel", background)
	approach.visible = false
	hud.add_child(approach)
	var approach_lines := VBoxContainer.new()
	approach_lines.name = "Lines"
	approach.add_child(approach_lines)
	for key in APPROACH_LINES:
		# Each its own settings: the speed and status lines change colour.
		var settings := LabelSettings.new()
		settings.font_size = HUD_FONT_SIZE
		settings.font_color = HUD_TEXT_COLOR
		_add_hud_label(approach_lines, APPROACH_LINES[key], settings)
	# Top centre.
	var navball: Control = NavballScript.new()
```

In `scripts/void_cruiser.gd` replace:

```gdscript
var _guide_over_rim := false
var _guide_bridge := -1
```

with:

```gdscript
var _guide_over_rim := false
var _guide_bridge := -1
# The last path's length, the guide's clock and the planned arrival on it
# (see DockingAssist.keeps_plan); -1: no plan.
var _guide_length := 0.0
var _guide_clock := 0.0
var _arrival_at := -1.0
```

In `scripts/void_cruiser.gd` replace:

```gdscript
		cockpit.update_attitude(attitude_matrix())
	_update_approach_guide()
```

with:

```gdscript
		cockpit.update_attitude(attitude_matrix())
	_guide_clock += delta
	var readout := _update_approach_guide()
	if cockpit:
		cockpit.update_approach(readout)
```

In `scripts/void_cruiser.gd` replace:

```gdscript
# Shown between MIN_RANGE and MAX_RANGE (straight line) from the nearest
# dock. The marker sits on the motion relative to the dock, as far out as
# the first gate: cyan when wholly inside it, red otherwise; hidden under
# MARKER_MIN_SPEED.
func _update_approach_guide() -> void:
	var guide := get_node_or_null("ApproachGuide") as MeshInstance3D
	var marker := get_node_or_null("HeadingMarker") as MeshInstance3D
	if guide == null or marker == null:
		return
	var gate_lines := PackedVector3Array()
	var marker_lines := PackedVector3Array()
	var on_path := false
	var station: Node3D = null
	if is_inside_tree():
		station = get_node_or_null(station_path) as Node3D
	if station != null and station.is_inside_tree():
		var index: int = station.nearest_bridge_index(global_position)
		var port: Node3D = station.get_docking_port(index)
		var distance := global_position.distance_to(port.global_position)
		if index != _guide_bridge:
			_guide_over_rim = false
			_guide_bridge = index
		if distance >= ApproachGuide.MIN_RANGE and distance <= ApproachGuide.MAX_RANGE:
			var up := global_transform.basis.y
			var path := _approach_path(station, port)
			gate_lines = ApproachGuide.gates_along(path, up)
			var gates := ApproachGuide.gate_centres(path)
			var motion: Vector3 = velocity - station.get_docking_port_velocity(index)
			if not gates.is_empty() and motion.length() >= ApproachGuide.MARKER_MIN_SPEED:
				var first: Vector3 = gates[0][0]
				var centre := motion.normalized() * first.length()
				marker_lines = ApproachGuide.marker_segments(centre, motion.normalized(), up)
				on_path = ApproachGuide.marker_on_path(first, gates[0][1], up, centre)
	if gate_lines.is_empty():
		_guide_over_rim = false
	_show_lines(guide, gate_lines)
	(marker.material_override as StandardMaterial3D).albedo_color = MARKER_ON_PATH_COLOR if on_path else MARKER_OFF_PATH_COLOR
	_show_lines(marker, marker_lines)
```

with:

```gdscript
# Shown between MIN_RANGE and MAX_RANGE (straight line) from the nearest
# dock. The marker sits on the motion relative to the dock, as far out as
# the first gate: cyan when wholly inside it, red otherwise; hidden under
# MARKER_MIN_SPEED. Returns the approach panel's readout (empty past
# MAX_RANGE), keeping the planned arrival as it goes.
func _update_approach_guide() -> Dictionary:
	var guide := get_node_or_null("ApproachGuide") as MeshInstance3D
	var marker := get_node_or_null("HeadingMarker") as MeshInstance3D
	if guide == null or marker == null:
		return {}
	var gate_lines := PackedVector3Array()
	var marker_lines := PackedVector3Array()
	var on_path := false
	var readout := {}
	var dock := _nearest_dock()
	if dock.is_empty():
		_guide_bridge = -1
		_guide_length = 0.0
		_arrival_at = -1.0
	else:
		if dock.index != _guide_bridge:
			_guide_over_rim = false
			_guide_bridge = dock.index
			_guide_length = 0.0
			_arrival_at = -1.0
		var port: Node3D = dock.port
		var distance: float = dock.distance
		var length: float = _guide_length if _guide_length > 0.0 else distance
		var spin: float = dock.station.get_spin_rate()
		if _arrival_at < 0.0 or not DockingAssist.keeps_plan(_arrival_at - _guide_clock, length, spin):
			var bridge_frame: Transform3D = (port.get_parent() as Node3D).global_transform
			_arrival_at = _guide_clock + DockingAssist.plan_arrival(bridge_frame.affine_inverse() * global_position, port.transform.origin, spin, length)
		var motion: Vector3 = velocity - dock.velocity
		var closing := motion.dot((port.global_position - global_position).normalized())
		length = distance
		_guide_length = 0.0
		if distance >= ApproachGuide.MIN_RANGE:
			var up := global_transform.basis.y
			var path := _approach_path(dock.station, port)
			length = 0.0
			for i in range(1, path.size()):
				length += path[i - 1].distance_to(path[i])
			_guide_length = length
			gate_lines = ApproachGuide.gates_along(path, up)
			var gates := ApproachGuide.gate_centres(path)
			if not gates.is_empty():
				var first: Vector3 = gates[0][0]
				closing = motion.dot(first.normalized())
				if motion.length() >= ApproachGuide.MARKER_MIN_SPEED:
					var centre := motion.normalized() * first.length()
					marker_lines = ApproachGuide.marker_segments(centre, motion.normalized(), up)
					on_path = ApproachGuide.marker_on_path(first, gates[0][1], up, centre)
		readout = DockingAssist.readout(length, _arrival_at - _guide_clock, motion.length(), closing, distance)
	if gate_lines.is_empty():
		_guide_over_rim = false
	_show_lines(guide, gate_lines)
	(marker.material_override as StandardMaterial3D).albedo_color = MARKER_ON_PATH_COLOR if on_path else MARKER_OFF_PATH_COLOR
	_show_lines(marker, marker_lines)
	return readout
```

In `scripts/torus_station.gd` replace:

```gdscript
func get_bridge_radius() -> float:
```

with:

```gdscript
# How fast sections and bridges spin about their own axes (rad/s).
func get_spin_rate() -> float:
	return _spin_rate()

func get_bridge_radius() -> float:
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_torus_station.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_cockpit.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

- [ ] **Step 5: Commit**

```bash
git add scripts/cockpit.gd scripts/torus_station.gd scripts/void_cruiser.gd tests/test_cockpit.gd tests/test_docking_assist_in_tree.gd tests/test_torus_station.gd
git add -A scripts/*.uid tests/*.uid
git commit -m "Add the approach panel and plan the arrival for when the pad comes round below the ship

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: The path to the meeting point

The approach path ends where the pad will be at the planned arrival, a place that stays put in space while the bridge turns.

**Files:**
- Modify: `scripts/void_cruiser.gd`
- Modify: `tests/test_docking_assist_in_tree.gd`
- Modify: `tests/test_docking_hud_in_tree.gd`

**Interfaces:**
- Consumes: Task 1: `future_pad`. Task 4: `get_spin_rate`, `_arrival_at`, `_guide_clock`.
- Produces:
- Void cruiser: `_approach_path(station, port, time_left: float)`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_docking_hud_in_tree.gd` replace:

```gdscript
func _test_guide_keeps_its_shape_near_the_switch() -> int:
	# Where the single curve only just clears the rim, the guide keeps the
	# shape it had last frame: the ship carries the choice.
	var result := 0
```

with:

```gdscript
func _test_guide_keeps_its_shape_near_the_switch() -> int:
	# Where the single curve only just clears the rim, the guide keeps the
	# shape it had last frame: the ship carries the choice. The bridge is
	# held still, so the path ends on the pad itself (no meeting point ahead).
	var result := 0
	var gravity: float = _station.target_gravity_g
	_station.target_gravity_g = 0.0
```

In `tests/test_docking_hud_in_tree.gd` replace:

```gdscript
			print("FAIL _test_guide_keeps_its_shape_near_the_switch: held %s, now %s, %d points for %d gates" % [held, _cruiser._guide_over_rim, points.size(), gates.size()])
			result = 1
	return result
```

with:

```gdscript
			print("FAIL _test_guide_keeps_its_shape_near_the_switch: held %s, now %s, %d points for %d gates" % [held, _cruiser._guide_over_rim, points.size(), gates.size()])
			result = 1
	_station.target_gravity_g = gravity
	return result
```

In `tests/test_docking_assist_in_tree.gd` replace:

```gdscript
	# (more tests)
```

with:

```gdscript
	_failures += await _test_path_ends_where_the_pad_will_be()
```

At the end of `tests/test_docking_assist_in_tree.gd` append, after one blank line:

```gdscript
func _test_path_ends_where_the_pad_will_be() -> int:
	# 2 km from the bridge's axis, a quarter turn round from the pad: the
	# plan waits for the pad to come round below the ship, and the gates
	# lead down to that meeting point, not across to where the pad is now.
	var bridge: Node3D = _station.get_node("Bridge0")
	var port: Node3D = _station.get_docking_port(0)
	var pad: Vector3 = port.transform.origin
	var angle := atan2(pad.x, pad.z) + PI * 0.5
	var ship := Vector3(sin(angle), 0.0, cos(angle)) * 2000.0
	var down: Vector3 = (bridge.global_transform.basis * -ship).normalized()
	_cruiser.global_transform = Transform3D(Basis.looking_at(down, bridge.global_transform.basis.y), bridge.global_transform * ship)
	_cruiser.velocity = Vector3.ZERO
	# A jump like this never happens in flight: drop the last test's plan.
	_cruiser._arrival_at = -1.0
	_cruiser._guide_length = 0.0
	for i in range(3):
		await physics_frame
		await process_frame
	var time_left: float = _cruiser._arrival_at - _cruiser._guide_clock
	var later: Vector3 = bridge.global_transform * DockingAssist.future_pad(pad, _station.get_spin_rate(), time_left)
	var points: PackedVector3Array = ((_cruiser.get_node("ApproachGuide") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var last := Vector3.ZERO
	for k in range(8):
		last += points[points.size() - 8 + k]
	last = _cruiser.global_position + last / 8.0
	if later.distance_to(port.global_position) < 500.0 or last.distance_to(later) > 200.0:
		print("FAIL _test_path_ends_where_the_pad_will_be: last gate %.0f m from the meeting point, %.0f m from the pad now (%.0f s ahead)" % [last.distance_to(later), last.distance_to(port.global_position), time_left])
		return 1
	return 0
```

- [ ] **Step 2: Run them to see them fail**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_hud_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` (this edit only holds the bridge still for the rim-hysteresis test, which the lead would otherwise move; it must keep passing).

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `FAIL _test_path_ends_where_the_pad_will_be: last gate 869 m from the meeting point, 31 m from the pad now (134 s ahead)`, `1 TEST(S) FAILED`

- [ ] **Step 3: Write the code**

In `scripts/void_cruiser.gd` replace:

```gdscript
			var path := _approach_path(dock.station, port)
```

with:

```gdscript
			var path := _approach_path(dock.station, port, _arrival_at - _guide_clock)
```

In `scripts/void_cruiser.gd` replace:

```gdscript
# The approach path to `port`, relative to the ship: worked out in the frame
# of the port's bridge (see approach_guide.gd), where the station near the
# dock is round about the axis. It leaves along the nose (-Z). Updates the
# shape carried to the next frame.
func _approach_path(station: Node3D, port: Node3D) -> PackedVector3Array:
```

with:

```gdscript
# The approach path to `port`, relative to the ship: worked out in the frame
# of the port's bridge (see approach_guide.gd), where the station near the
# dock is round about the axis. It leaves along the nose (-Z) and ends where
# the pad will be `time_left` seconds from now, a place that stays put while
# the bridge turns. Updates the shape carried to the next frame.
func _approach_path(station: Node3D, port: Node3D, time_left: float) -> PackedVector3Array:
```

In `scripts/void_cruiser.gd` replace:

```gdscript
	var half_gap: float = station.get_bridge_length() * 0.5
	_guide_over_rim = ApproachGuide.over_rim(ship, nose, port.transform.origin, station.section_radius, half_gap, _guide_over_rim)
	var local_path := ApproachGuide.approach_path(ship, nose, port.transform.origin, station.section_radius, half_gap, station.get_bridge_radius(), _guide_over_rim)
```

with:

```gdscript
	var half_gap: float = station.get_bridge_length() * 0.5
	var pad := DockingAssist.future_pad(port.transform.origin, station.get_spin_rate(), time_left)
	_guide_over_rim = ApproachGuide.over_rim(ship, nose, pad, station.section_radius, half_gap, _guide_over_rim)
	var local_path := ApproachGuide.approach_path(ship, nose, pad, station.section_radius, half_gap, station.get_bridge_radius(), _guide_over_rim)
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_hud_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_docking_assist_in_tree.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`
Expected: `ALL TESTS PASSED` and no `SCRIPT ERROR` line.

- [ ] **Step 5: Run the suite and the live check**

Run: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh`
Expected: exit 0, all 34 files `ALL TESTS PASSED`.

Run the live check from Global Constraints. Expected: no output.

- [ ] **Step 6: Render and look**

Write this probe to the scratchpad as `probe_assist.gd` (replace `SCRATCH` with the scratchpad path) and run `xvfb-run -a /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --path . -s <scratchpad>/probe_assist.gd`:

```gdscript
extends SceneTree

func _initialize():
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(scene)
	for i in range(3):
		await process_frame
	var station: Node3D = scene.get_node("PlanetSystem/TorusStation")
	var cruiser: CharacterBody3D = scene.get_node("VoidCruiser")
	cruiser.set_physics_process(false)
	var port: Node3D = station.get_docking_port(0)
	var out: Vector3 = port.global_transform.basis.x.normalized()
	var eye: Vector3 = port.global_position + out * 1500.0
	cruiser.global_transform = Transform3D(Basis.looking_at(port.global_position - eye, port.global_transform.basis.y), eye)
	cruiser.velocity = station.get_docking_port_velocity(0) - out * 30.0
	for i in range(6):
		await physics_frame
		cruiser._physics_process(1.0 / 60.0)
		await process_frame
	root.get_texture().get_image().save_png("SCRATCH/assist_cockpit.png")
	var cam := Camera3D.new()
	cam.far = 100000.0
	root.add_child(cam)
	port = station.get_docking_port(0)
	var cam_pos: Vector3 = port.global_position + port.global_transform.basis.y.normalized() * 6000.0 + port.global_transform.basis.x.normalized() * 500.0
	cam.global_transform = Transform3D(Basis.looking_at(port.global_position - cam_pos, port.global_transform.basis.x), cam_pos)
	cam.current = true
	for i in range(3):
		await process_frame
	root.get_texture().get_image().save_png("SCRATCH/assist_axis.png")
	quit()
```

Expected, read with the Read tool:
- `assist_cockpit.png`: top-right panel with `DIST  1.5 km`, `REL SPEED` about 29 m/s, `ADVISED` about 28 m/s, an ETA near 52 s; `THRUST  0.7x` in the left panel; gates straight ahead down to the bridge, marker cyan.
- `assist_axis.png` (looking along the bridge): the dotted path runs straight down from the ship toward the bridge, not round it.

- [ ] **Step 7: Commit**

```bash
git add scripts/void_cruiser.gd tests/test_docking_assist_in_tree.gd tests/test_docking_hud_in_tree.gd
git add -A scripts/*.uid tests/*.uid
git commit -m "Aim the approach path at the planned meeting point, still in space while the bridge turns

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
