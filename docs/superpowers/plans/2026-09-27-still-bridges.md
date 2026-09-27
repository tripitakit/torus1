# Still Bridges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the bridges turning (sections keep spinning) and simplify the docking assist to match: advised speed from steady braking over the path, the path ending on the pad itself, the brake stopping the ship in space.

**Architecture:** Task 1 strips the arrival planning from `docking_assist.gd` and `void_cruiser.gd` (no plan, no future pad, brake to rest). Task 2 stops `_rotate_sections` turning bridges, removes the bridge-velocity API from the station, and makes docking, undocking and the assist use the ship's own velocity.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript. Headless `extends SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-09-27-still-bridges-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64` (never the `godot` on PATH). One test file: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED|FAILED"`. A `SCRIPT ERROR` line is a failure even under an `ALL TESTS PASSED` summary.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` — every `tests/*.gd` prints exactly `ALL TESTS PASSED` (34 files).
- Worktree: run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import > /dev/null 2>&1` once first. Bash in the worktree refuses variables, loops and `bash -c`: literal paths, one command per call, multi-step edits in a Python file in the scratchpad.
- Numbers (spec): advised speed `sqrt(2 * 1 m/s^2 * length)`; brake `10 x thrust_power x precision factor` toward zero velocity; in docking range (150 m) a speed over 20 m/s is rated OVER.
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Live check: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"` prints nothing.
- This plan was written against master d79210f without a dry run; where an edit does not apply as written, rule on the smallest change that meets the spec and ledger it.

## Review Focus

1. **Sections turning next to still bridges:** the section end faces now slide past the bridge ends; check nothing (collision shapes, the rim-hysteresis path, lamps) assumed they turn together.
2. **Leftover references** to the removed station API (`get_bridge_point_velocity`, `get_docking_port_velocity`, `get_spin_rate`) or planning state (`_arrival_at`, `_guide_clock`, `_guide_length`, `_planned_length`) anywhere in scripts or tests.
3. **Physics of a ship resting on a still bridge next to a turning section** (`_test_rotating_hull_resting_on_bridge_does_not_jump` keeps running): judge whether it still means something.
4. **The panel near the pad:** with advised speed under 17.3 m/s inside 150 m, check the colours read sensibly against DOCK READY.

---

### Task 1: Simplify the assist (no plan, path to the pad, brake to rest)

**Files:**
- Modify: `scripts/docking_assist.gd`, `scripts/void_cruiser.gd`
- Test: `tests/test_docking_assist.gd`, `tests/test_docking_assist_in_tree.gd`, `tests/test_docking_hud_in_tree.gd`

**Interfaces:**
- Produces: `DockingAssist.advised_speed(length: float) -> float`; `DockingAssist.readout(length: float, speed: float, closing: float, distance: float) -> Dictionary` (same keys). Removed: `arrival_time`, `plan_arrival`, `keeps_plan`, `future_pad`, `brake_target`, `REPLAN_GROWTH`, `REPLAN_EARLY`, `REPLAN_LATE`. Void cruiser: `_approach_path(station, port)` (no time argument); no `_guide_length`, `_guide_clock`, `_arrival_at`, `_planned_length`.
- Consumes: `_nearest_dock()` as today (its `velocity` key stays until Task 2).

- [ ] **Step 1: Write the failing tests**

In `tests/test_docking_assist.gd`:
- Remove the registration lines and functions of `_test_arrival_time_brakes_steadily`, `_test_plan_holds_between_early_and_late`, `_test_plan_waits_for_the_pad_to_come_round`, `_test_future_pad_turns_with_the_bridge`, `_test_planned_arrival_keeps_the_path_still` (with its helpers `_drift` and `_path_drift`), `_test_brake_turns_with_the_bridge_only_near_a_dock`, `_test_plan_dropped_when_the_way_grows`. Drop the now unused `ApproachGuide` preload and the bridge constants/vars (`SECTION_RADIUS`, `HALF_GAP`, `BRIDGE_RADIUS`, `SPIN`, `PAD_ANGLE`, `PAD_RADIUS`) if nothing else uses them.
- Replace `_test_advised_speed_arrives_on_time` (and its registration) with:

```gdscript
func _test_advised_speed_brakes_steadily() -> int:
	# The speed from which braking at 1 m/s^2 stops on the pad.
	var result := 0
	for c in [[20000.0, 200.0], [1000.0, sqrt(2000.0)], [150.0, sqrt(300.0)], [0.0, 0.0]]:
		if not is_equal_approx(DockingAssist.advised_speed(c[0]), c[1]):
			print("FAIL _test_advised_speed_brakes_steadily: %.0f m gave %f, expected %f" % [c[0], DockingAssist.advised_speed(c[0]), c[1]])
			result = 1
	return result
```

- Replace `_test_readout_lines_and_status` with:

```gdscript
func _test_readout_lines_and_status() -> int:
	var result := 0
	# 1.2 km to go: advised 49 m/s; 55 m/s is a caution; closing at 60 m/s,
	# 20 s to go.
	var far: Dictionary = DockingAssist.readout(1200.0, 55.0, 60.0, 900.0)
	if far.dist != "DIST  1.2 km" or far.speed != "REL SPEED  55 m/s" or far.advised != "ADVISED  49 m/s" or far.eta != "ETA  20 s" or far.status != "" or far.rating != DockingAssist.Rating.CAUTION or far.ready:
		print("FAIL _test_readout_lines_and_status: far %s" % far)
		result = 1
	# Moving away: no time of arrival.
	if DockingAssist.readout(1200.0, 5.0, -5.0, 900.0).eta != "ETA  —":
		print("FAIL _test_readout_lines_and_status: an ETA while moving away")
		result = 1
	# In range: ready when slow enough, too fast otherwise.
	var slow: Dictionary = DockingAssist.readout(120.0, 12.0, 12.0, 120.0)
	var fast: Dictionary = DockingAssist.readout(120.0, 25.0, 25.0, 120.0)
	if slow.status != DockingAssist.READY_TEXT or not slow.ready or fast.status != DockingAssist.TOO_FAST_TEXT or fast.ready:
		print("FAIL _test_readout_lines_and_status: in range slow %s, fast %s" % [slow.status, fast.status])
		result = 1
	return result
```

- Replace `_test_advised_speed_capped_in_docking_range` (and its registration) with:

```gdscript
func _test_too_fast_to_dock_reads_red() -> int:
	# 120 m out: advised 15 m/s; 21 m/s is over the 20 m/s docking limit, so
	# it reads as too fast even though it is within the caution ratio.
	var near: Dictionary = DockingAssist.readout(120.0, 18.5, 18.5, 120.0)
	var over: Dictionary = DockingAssist.readout(120.0, 21.0, 21.0, 120.0)
	if near.rating != DockingAssist.Rating.CAUTION or over.rating != DockingAssist.Rating.OVER or over.status != DockingAssist.TOO_FAST_TEXT:
		print("FAIL _test_too_fast_to_dock_reads_red: 18.5 m/s rated %d, 21 m/s rated %d (%s)" % [near.rating, over.rating, over.status])
		return 1
	return 0
```

In `tests/test_docking_assist_in_tree.gd`:
- Remove the registration lines and functions `_test_brake_holds_the_ship_over_the_pad`, `_test_plan_follows_the_ship_round_the_bridge`, `_test_path_ends_where_the_pad_will_be`.
- Register and add after `_test_brake_stops_the_ship_in_space_far_out`:

```gdscript
func _test_brake_stops_the_ship_in_space_near_the_pad() -> int:
	# 500 m out, drifting: B stops the ship in space, not with the bridge.
	# Precision 0.25 there: 375 m/s^2 of braking, so 40 m/s goes in 0.11 s.
	await _park(500.0)
	_cruiser.velocity = Vector3(40.0, 0.0, 0.0)
	_press("brake")
	_fly(30)
	if _cruiser.velocity.length() > 0.01:
		print("FAIL _test_brake_stops_the_ship_in_space_near_the_pad: %.2f m/s after 0.5 s" % _cruiser.velocity.length())
		return 1
	return 0

func _test_path_ends_on_the_pad() -> int:
	# 2 km out, nose on the pad: the last gate sits by the pad itself.
	await _park(2000.0)
	var port: Node3D = _station.get_docking_port(0)
	var points: PackedVector3Array = ((_cruiser.get_node("ApproachGuide") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var last := Vector3.ZERO
	for k in range(8):
		last += points[points.size() - 8 + k]
	last = _cruiser.global_position + last / 8.0
	if last.distance_to(port.global_position) > 100.0:
		print("FAIL _test_path_ends_on_the_pad: last gate %.0f m from the pad" % last.distance_to(port.global_position))
		return 1
	return 0
```

In `tests/test_docking_hud_in_tree.gd`, in `_test_guide_keeps_its_shape_near_the_switch`, remove the lines that save, zero and restore `_station.target_gravity_g` and the comment sentence about holding the bridge still (the path now always ends on the pad).

- [ ] **Step 2: Run them to see them fail**

Run the three files. Expected:
- `test_docking_assist.gd`: `SCRIPT ERROR: Parse Error: Too many arguments for "readout()"` / `advised_speed()` call-count errors (the new signatures do not exist yet).
- `test_docking_assist_in_tree.gd`: `FAIL _test_brake_stops_the_ship_in_space_near_the_pad: ...` (the brake follows the bridge within 2 km) and `FAIL _test_path_ends_on_the_pad: ...` (the path leads to the planned meeting point).
- `test_docking_hud_in_tree.gd`: may fail the rim test while the lead is still in place (the bridge spins); record what it prints.

- [ ] **Step 3: Simplify the code**

`scripts/docking_assist.gd`:
- Header comment: "Help for flying to a dock, all pure: thrust that eases off near it, the brake step, the advised speed and the approach panel's lines."
- Delete `REPLAN_GROWTH`, `REPLAN_EARLY`, `REPLAN_LATE`, `brake_target`, `arrival_time`, `plan_arrival`, `keeps_plan`, `future_pad`. Keep `ADVISED_DECELERATION := 1.0` with the comment "The advised speed stops the ship on the pad braking steadily at this rate."
- `advised_speed`:

```gdscript
# The speed from which braking steadily at ADVISED_DECELERATION stops on the
# pad, `length` metres along the path.
static func advised_speed(length: float) -> float:
	return sqrt(2.0 * ADVISED_DECELERATION * maxf(length, 0.0))
```

- `readout(length: float, speed: float, closing: float, distance: float)`: comment without `time_left`; body starts

```gdscript
	var advised := advised_speed(length)
	var rating := speed_rating(speed, advised)
	# Too fast to dock reads as too fast.
	if distance <= DockingRules.DOCK_RANGE and speed > DockingRules.DOCK_MAX_SPEED:
		rating = Rating.OVER
```

  and the rest unchanged.

`scripts/void_cruiser.gd`:
- Delete the vars `_guide_length`, `_guide_clock`, `_arrival_at`, `_planned_length` and their comment; delete `_guide_clock += delta` in `_process`.
- `_fly`: the brake becomes `velocity = DockingAssist.brake_velocity(velocity, Vector3.ZERO, thrust_power * DockingAssist.BRAKE_MULTIPLIER * thrust_scale, delta)`; comments above `_fly` and on `BRAKE_RELEASE_ACTIONS` say the brake stops the ship in space (relative to the station).
- `_update_approach_guide`: drop the plan block (`length` before, `spin`, `keeps_plan`, `plan_arrival`, `_planned_length`) and every `_guide_length` / `_arrival_at` reset; the path call is `_approach_path(dock.station, port)`; the readout call is `DockingAssist.readout(length, motion.length(), closing, distance)`; comment no longer mentions the plan.
- `_approach_path(station: Node3D, port: Node3D)`: `var pad: Vector3 = port.transform.origin`; comment: ends on the pad.

- [ ] **Step 4: Run the tests to see them pass**

Run `test_docking_assist.gd`, `test_docking_assist_in_tree.gd`, `test_docking_hud_in_tree.gd`, `test_void_cruiser.gd`, `test_cockpit.gd`. Expected: `ALL TESTS PASSED`, no `SCRIPT ERROR`.

- [ ] **Step 5: Commit**

```bash
git add scripts/docking_assist.gd scripts/void_cruiser.gd tests/test_docking_assist.gd tests/test_docking_assist_in_tree.gd tests/test_docking_hud_in_tree.gd
git commit -m "Simplify the docking assist: advised speed from steady braking, path to the pad, brake to rest

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Still bridges

**Files:**
- Modify: `scripts/torus_station.gd`, `scripts/game_mode.gd`, `scripts/void_cruiser.gd`
- Test: `tests/test_torus_station.gd`, `tests/test_torus_station_physics.gd`, `tests/test_game_mode.gd`, `tests/test_docking_hud_in_tree.gd`, `tests/test_docking_assist_in_tree.gd`

**Interfaces:**
- Produces: `_rotate_sections(delta)` turns `Section*` only. Removed: `get_bridge_point_velocity`, `get_docking_port_velocity`, `get_spin_rate`. `_nearest_dock()` without the `velocity` key.
- Consumes: Task 1's simplified assist.

- [ ] **Step 1: Write the failing tests**

`tests/test_torus_station.gd`:
- Replace `_test_rotate_sections_also_rotates_bridges` (and its registration) with:

```gdscript
func _test_rotate_sections_leaves_bridges_still() -> int:
	# Sections spin for gravity; bridges, with their pads, stay put so the
	# ships outside have a still dock to fly to.
	var station := _make_station(4)
	station.build_station()
	var bridge: AnimatableBody3D = station.get_node("Bridge0")
	var section: Node3D = station.get_node("Section0")
	var bridge_basis: Basis = bridge.transform.basis
	var section_basis: Basis = section.transform.basis
	station._rotate_sections(0.1)
	var result := 0
	if not bridge.transform.basis.is_equal_approx(bridge_basis) or section.transform.basis.is_equal_approx(section_basis):
		print("FAIL _test_rotate_sections_leaves_bridges_still: bridge turned %s, section turned %s" % [not bridge.transform.basis.is_equal_approx(bridge_basis), not section.transform.basis.is_equal_approx(section_basis)])
		result = 1
	station.free()
	return result
```

- Replace `_test_port_turns_with_its_bridge` (and registration) with `_test_port_sits_on_its_still_bridge`: same setup; fail if the port is not a child of the bridge, or if `bridge.transform * port.position` changes after `station._rotate_sections(1.0)`.
- Remove `_test_spin_rate_is_public` and its registration.

`tests/test_torus_station_physics.gd`:
- Replace `_test_bridge_rotation_accumulates_across_physics_ticks` (and registration) with `_test_bridges_stay_still_across_physics_ticks`: same loop (3 ticks x 3 calls of `_rotate_sections(0.02)` with `await physics_frame`), then fail unless `bridge.transform.basis.is_equal_approx(original_basis)`.
- Remove `_test_port_velocity_matches_its_motion` and its registration.

`tests/test_game_mode.gd`:
- `_park_near_port`: `_void_cruiser.velocity = outward * speed`; comment: the pad is still.
- In `_test_dock_prompt_follows_distance_and_speed` remove the last block ("Still in space while the pad sweeps past").
- In the undock test replace the `carried` check with: the ship is 60 m out (±0.5) and `_void_cruiser.velocity.is_zero_approx()`; message "... velocity %s, expected at rest".

`tests/test_docking_hud_in_tree.gd` and `tests/test_docking_assist_in_tree.gd`: every `_station.get_docking_port_velocity(0)` becomes `Vector3.ZERO` (so `_station.get_docking_port_velocity(0) + x` becomes `x`); update the `_park` comments ("at rest").

- [ ] **Step 2: Run them to see them fail**

Expected:
- `test_torus_station.gd`: `FAIL _test_rotate_sections_leaves_bridges_still: bridge turned true, ...` and `FAIL _test_port_sits_on_its_still_bridge`.
- `test_torus_station_physics.gd`: `FAIL _test_bridges_stay_still_across_physics_ticks`.
- `test_game_mode.gd`: the undock check fails (the ship leaves with the bridge's velocity) and the prompt at rest may be hidden (the pad still moves).
- The two in-tree docking files: marker/panel checks fail where motion is measured against the moving pad.

- [ ] **Step 3: Still the bridges**

`scripts/torus_station.gd`:
- `_rotate_sections`: rotate only children whose name begins with `Section`; comment: "Sections spin for artificial gravity; bridges stay still, so their docks do not move."
- Delete `get_spin_rate`, `get_bridge_point_velocity`, `get_docking_port_velocity`. Update the bridge-body comment in `build_station` (bridges no longer rotate; they stay `AnimatableBody3D` with `sync_to_physics = false` — nothing else changes).

`scripts/game_mode.gd`:
- `_can_dock_now`: `var relative: Vector3 = _void_cruiser.velocity`, comment: the pad is still.
- `exit_interior`: `_void_cruiser.velocity = Vector3.ZERO`, comment: out at rest by the still pad.

`scripts/void_cruiser.gd`:
- `_nearest_dock`: return `{"station", "index", "port", "distance"}` only; comment without the pad's velocity.
- `_update_approach_guide`: `var motion: Vector3 = velocity`; the marker comment says motion relative to the station (the pad is still).

- [ ] **Step 4: Run the tests to see them pass**

Run the five test files of this task plus `test_void_cruiser.gd`. Expected: `ALL TESTS PASSED`, no `SCRIPT ERROR`. Then `grep -rn "get_bridge_point_velocity\|get_docking_port_velocity\|get_spin_rate\|_arrival_at\|_guide_clock\|_planned_length" scripts tests` prints nothing.

- [ ] **Step 5: Suite and live check**

Run the full suite (34/34) and the live check (no output).

- [ ] **Step 6: Commit**

```bash
git add scripts/torus_station.gd scripts/game_mode.gd scripts/void_cruiser.gd tests/test_torus_station.gd tests/test_torus_station_physics.gd tests/test_game_mode.gd tests/test_docking_hud_in_tree.gd tests/test_docking_assist_in_tree.gd
git commit -m "Keep the bridges still: only sections spin; docking and undocking use the ship's own velocity

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
