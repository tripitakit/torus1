# Interior Chain Travel (Piece C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fly continuously inside the station from section to section through always-open bridges, with the interior built around the craft as it flies, a dock on every bridge, and a stepped thrust ramp (void-cruiser to 100x, internal-cruiser to 10x).

**Architecture:** `interior_layout.gd` gains pure chain math: every bridge and section has an integer *slot* counted from the docked bridge (bridge `r` centred at `z = -r·P`, section `s` at `z = -(s+0.5)·P`, `P = section length + bridge length`). `interior_world.gd` becomes a chain under a `Chain` node: a `SectionLoad` record per section slot (plan generated on a `WorkerThreadPool` worker, chunks dressed a few per frame, nearest first, freed a few per frame), bridges built whole for both ends of every loaded section, every light fading out at 25 km, and a Z-only origin shift of `Chain` + craft past 10 km. `game_mode.gd` undocks at the nearest dock's bridge and frees the detached outside world if destroyed while inside. The thrust ramp moves into `flying_craft.gd` as a list of steps.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer, `WorkerThreadPool`. Headless `extends SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-09-24-interior-chain-travel-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`. One test file: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (every `tests/*.gd` must print exactly `ALL TESTS PASSED`; exit 0). If the script is gone, recreate it: loop over `tests/*.gd`, grep each run for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the grep is exactly `ALL TESTS PASSED`.
- **Reading RED:** a missing method prints `SCRIPT ERROR: ... Nonexistent function` and the file may still end with `ALL TESTS PASSED`; a missing preload prints `Parse Error`. RED is those lines or `FAIL` lines, never the summary alone.
- **Fresh worktree:** run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import` once before the first test run.
- **Off-tree vs in-tree:** `global_position` / `global_transform` / `to_local` error on nodes outside the tree. Off-tree tests chain `transform`s by hand (`_world_transform`); physics, `_process` and cameras need in-tree tests (`_initialize()` + `await process_frame` / `physics_frame`).
- **Packed arrays are values:** build them in locals and assign them whole. Plain `Array`/`Dictionary` are references.
- **Headless has no real renderer:** read `custom_aabb`, never `MultiMesh.get_aabb()`.
- `find_children()` on code-built nodes must pass `owned = false`.
- GDScript: explicit types where builtins return Variant; do not name locals `basis`, `transform`, `position`, `sign`, `owner`, `ready`; prefix unused parameters with `_`; no bare integer division (it prints a `WARNING`).
- Chain slots (spec, "Catena"): `P = section_length + bridge_length` (21 834 m at full scale). Bridge slot `r` centre `z = -r·P`, ring index `posmod(docked + r, ring_sections)`. Section slot `s` centre `z = -(s + 0.5)·P`, ring index `posmod(docked + s + 1, ring_sections)`. At docking the sections are slots -1 and 0, the bridges -1, 0, 1.
- Loading (spec, "Caricamento"): load within `1.25·P`, unload past `1.5·P` (centre distance along Z); at most 16 chunks dressed and 32 freed per frame; plans on `WorkerThreadPool`.
- Origin shift: past 10 000 m from the origin along Z, `Chain` and the craft move together along Z only.
- Lights: every interior `OmniLight3D` has `distance_fade_enabled = true`, `distance_fade_begin = 24000`, `distance_fade_length = 1000`.
- Ramp: `forward_thrust_step_duration = 5.0`; void-cruiser steps `[10, 100]`, internal-cruiser `[10]`; linear inside a step from the previous value (1x before the first).
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `.claude/worktrees/`. Add Godot-generated `.uid` files for new scripts/tests.
- Live check (the Godot MCP server is not connected): `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"` prints nothing. Never launch a windowed run (fullscreen game); offscreen renders go through `xvfb-run`.

## Review Focus

1. **A worker still generating a plan when the interior is freed** (undock or quit mid-load) — the world must wait for it, never free under it. Test: `_test_freeing_while_a_plan_is_generating_waits_for_it` (Task 4).
2. **The ring closing and negative slots** — bridge 1999 → 0, slot -1 of bridge 0 is bridge 1999. Tests: `_test_ring_indices_wrap` (Task 1), `_test_sections_come_from_their_ring_indices` (Task 3), `_test_undock_from_another_bridge_exits_at_its_collar` (Task 5, slot -1 → last bridge).
3. **Undocking after the origin has shifted** — dock positions must follow the chain. Test: `_test_undock_from_another_bridge_exits_at_its_collar` (Task 5; slot 1 is 21.8 km out, so the world has rebased) and `_test_rebase_moves_chain_and_craft_together` (Task 4).
4. **Hovering at the load edge** — a section must not be built and thrown away over and over. Test: `_test_hovering_at_the_load_edge_keeps_the_same_section` (Task 4).
5. **Frame hitches when a new section starts** (shell, bridges and first chunks in one frame). Test: `_test_flying_along_the_chain_finds_each_section_ready` measures the worst frame (Task 4).

---

### Task 1: Chain math

**Files:**
- Modify: `scripts/interior_layout.gd` (append functions)
- Test: `tests/test_interior_layout.gd`

**Interfaces:**
- Produces (all `static` on `interior_layout.gd`):
  - `chain_period(section_length: float, bridge_length: float) -> float`
  - `bridge_slot_z(slot: int, period: float) -> float`
  - `section_slot_z(slot: int, period: float) -> float`
  - `bridge_ring_index(docked_bridge: int, slot: int, ring_sections: int) -> int`
  - `section_ring_index(docked_bridge: int, slot: int, ring_sections: int) -> int`
  - `nearest_bridge_slot(z: float, period: float) -> int`
  - `sections_within(z: float, period: float, reach: float) -> Array` (ascending ints)
  - `bridges_of_sections(sections: Array) -> Array` (ascending ints, no repeats)

- [ ] **Step 1: Write the failing tests**

In `tests/test_interior_layout.gd`, add after the existing `failures += ...` lines in `_init()`:

```gdscript
	failures += _test_chain_slot_positions()
	failures += _test_ring_indices_wrap()
	failures += _test_nearest_bridge_slot()
	failures += _test_sections_within_reach()
	failures += _test_bridges_of_sections()
```

Append at the end of the file:

```gdscript
func _period() -> float:
	return InteriorLayout.chain_period(SECTION_LENGTH, _bridge_length)

func _test_chain_slot_positions() -> int:
	var p := _period()
	var result := 0
	if not is_equal_approx(p, SECTION_LENGTH + _bridge_length):
		print("FAIL _test_chain_slot_positions: period %f" % p)
		result = 1
	if not is_equal_approx(InteriorLayout.bridge_slot_z(0, p), 0.0) or not is_equal_approx(InteriorLayout.bridge_slot_z(2, p), -2.0 * p) or not is_equal_approx(InteriorLayout.bridge_slot_z(-1, p), p):
		print("FAIL _test_chain_slot_positions: bridge slots not at -slot * period")
		result = 1
	# Slot 0 is piece A's section "ahead", slot -1 the one "behind".
	if not is_equal_approx(InteriorLayout.section_slot_z(0, p), InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, -1.0)) or not is_equal_approx(InteriorLayout.section_slot_z(-1, p), InteriorLayout.section_center_z(_bridge_length, SECTION_LENGTH, 1.0)):
		print("FAIL _test_chain_slot_positions: sections 0 and -1 are not the old ahead and behind")
		result = 1
	# Section s ends exactly where bridges s and s + 1 end.
	var section_high_end: float = InteriorLayout.section_slot_z(3, p) + SECTION_LENGTH * 0.5
	var section_low_end: float = InteriorLayout.section_slot_z(3, p) - SECTION_LENGTH * 0.5
	if not is_equal_approx(section_high_end, InteriorLayout.bridge_slot_z(3, p) - _bridge_length * 0.5) or not is_equal_approx(section_low_end, InteriorLayout.bridge_slot_z(4, p) + _bridge_length * 0.5):
		print("FAIL _test_chain_slot_positions: section 3 does not meet bridges 3 and 4")
		result = 1
	return result

func _test_ring_indices_wrap() -> int:
	var result := 0
	var cases := [
		# [docked, slot, bridge ring index, section ring index]
		[0, 0, 0, 1],
		[0, -1, 1999, 0],
		[1999, 0, 1999, 0],
		[1999, 1, 0, 1],
		[5, -7, 1998, 1999],
	]
	for c in cases:
		var bridge: int = InteriorLayout.bridge_ring_index(c[0], c[1], 2000)
		var section: int = InteriorLayout.section_ring_index(c[0], c[1], 2000)
		if bridge != c[2] or section != c[3]:
			print("FAIL _test_ring_indices_wrap: docked %d slot %d gave bridge %d section %d, expected %d and %d" % [c[0], c[1], bridge, section, c[2], c[3]])
			result = 1
	return result

func _test_nearest_bridge_slot() -> int:
	var p := _period()
	var result := 0
	for c in [[0.0, 0], [-0.4 * p, 0], [-0.6 * p, 1], [0.7 * p, -1], [-3.2 * p, 3]]:
		var slot: int = InteriorLayout.nearest_bridge_slot(c[0], p)
		if slot != c[1]:
			print("FAIL _test_nearest_bridge_slot: z %f gave slot %d, expected %d" % [c[0], slot, c[1]])
			result = 1
	return result

func _test_sections_within_reach() -> int:
	var p := _period()
	var result := 0
	var cases := [
		# [z, reach in periods, expected slots]
		[0.0, 1.25, [-1, 0]],
		[-0.5 * p, 1.25, [-1, 0, 1]],
		[-2.2 * p, 1.25, [1, 2]],
		[-2.2 * p, 1.5, [1, 2, 3]],
		[3.0 * p, 1.25, [-4, -3]],
	]
	for c in cases:
		var slots: Array = InteriorLayout.sections_within(c[0], p, c[1] * p)
		if slots != c[2]:
			print("FAIL _test_sections_within_reach: z %f reach %f gave %s, expected %s" % [c[0], c[1], slots, c[2]])
			result = 1
	return result

func _test_bridges_of_sections() -> int:
	var result := 0
	for c in [[[-1, 0], [-1, 0, 1]], [[2, 1], [1, 2, 3]], [[], []]]:
		var bridges: Array = InteriorLayout.bridges_of_sections(c[0])
		if bridges != c[1]:
			print("FAIL _test_bridges_of_sections: sections %s gave bridges %s, expected %s" % [c[0], bridges, c[1]])
			result = 1
	return result
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_interior_layout.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
Expected: `SCRIPT ERROR` lines naming `chain_period` (nonexistent function).

- [ ] **Step 3: Implement the chain math**

Append to `scripts/interior_layout.gd`:

```gdscript
# The interior chain: bridges and sections in one straight row along -Z, each
# at a "slot" counted from the docked bridge (slot 0, centred on the origin
# at docking). Section slot s lies between bridge s (+Z side) and bridge
# s + 1 (-Z side): slot 0 is the section "ahead", slot -1 the one "behind".

static func chain_period(section_length: float, bridge_length: float) -> float:
	return section_length + bridge_length

static func bridge_slot_z(slot: int, period: float) -> float:
	return -slot * period

static func section_slot_z(slot: int, period: float) -> float:
	return -(slot + 0.5) * period

# Station numbers: bridge i joins section i and section i + 1; the ring closes.
static func bridge_ring_index(docked_bridge: int, slot: int, ring_sections: int) -> int:
	return posmod(docked_bridge + slot, ring_sections)

static func section_ring_index(docked_bridge: int, slot: int, ring_sections: int) -> int:
	return posmod(docked_bridge + slot + 1, ring_sections)

static func nearest_bridge_slot(z: float, period: float) -> int:
	return roundi(-z / period)

# Section slots whose centre is within `reach` of z along the axis, ascending.
static func sections_within(z: float, period: float, reach: float) -> Array:
	var slots := []
	var first: int = ceili(-(z + reach) / period - 0.5)
	var last: int = floori(-(z - reach) / period - 0.5)
	for slot in range(first, last + 1):
		slots.append(slot)
	return slots

# The bridges at both ends of the given sections, ascending, no repeats.
static func bridges_of_sections(sections: Array) -> Array:
	var bridges := []
	for slot in sections:
		for bridge in [slot, slot + 1]:
			if not bridges.has(bridge):
				bridges.append(bridge)
	bridges.sort()
	return bridges
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_interior_layout.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
Expected: `ALL TESTS PASSED` only.

- [ ] **Step 5: Commit**

```bash
git add scripts/interior_layout.gd tests/test_interior_layout.gd
git commit -m "Add the interior chain math: slots, ring numbers, load window

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Stepped thrust ramp shared by both craft

**Files:**
- Modify: `scripts/void_cruiser_physics.gd:13-17`, `scripts/flying_craft.gd`, `scripts/void_cruiser.gd` (lines 5-6, 29-30, 140-157), `scripts/internal_cruiser.gd`
- Test: `tests/test_void_cruiser_physics.gd`, `tests/test_void_cruiser.gd`, `tests/test_internal_cruiser.gd`, `tests/test_torus_station_physics.gd`

**Interfaces:**
- Produces:
  - `VoidCruiserPhysics.compute_forward_thrust_multiplier(hold_time: float, step_duration: float, steps: PackedFloat64Array) -> float` (replaces the old `(hold_time, ramp_duration, max_multiplier)` signature).
  - On `flying_craft.gd`: `@export var forward_thrust_steps: PackedFloat64Array` (default `[10.0]`), `@export var forward_thrust_step_duration: float` (5.0), `var _forward_hold_time`, `var _forward_hold_sign`, `func _update_forward_hold_time(forward_input: float, delta: float)`, `func forward_thrust_multiplier() -> float`, `func _fly(delta: float)`.
  - `void_cruiser.gd` loses `forward_thrust_ramp_multiplier` and `forward_thrust_ramp_duration`; its steps are `[10.0, 100.0]`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_void_cruiser_physics.gd`, replace the five `failures += _test_forward_thrust_multiplier_...` lines in `_init()` with:

```gdscript
	failures += _test_forward_thrust_multiplier_follows_the_steps()
	failures += _test_forward_thrust_multiplier_stays_at_a_single_step()
	failures += _test_forward_thrust_multiplier_zero_duration_is_the_last_step()
	failures += _test_forward_thrust_multiplier_no_steps_is_1x()
```

and replace the five `func _test_forward_thrust_multiplier_*` functions with:

```gdscript
func _test_forward_thrust_multiplier_follows_the_steps() -> int:
	var steps := PackedFloat64Array([10.0, 100.0])
	var result := 0
	# [hold time, expected]: 1x -> 10x over 0..5 s, 10x -> 100x over 5..10 s.
	for c in [[0.0, 1.0], [2.5, 5.5], [5.0, 10.0], [7.5, 55.0], [10.0, 100.0], [50.0, 100.0]]:
		var got: float = VoidCruiserPhysics.compute_forward_thrust_multiplier(c[0], 5.0, steps)
		if not is_equal_approx(got, c[1]):
			print("FAIL _test_forward_thrust_multiplier_follows_the_steps: at %.1f s got %f, expected %f" % [c[0], got, c[1]])
			result = 1
	return result

func _test_forward_thrust_multiplier_stays_at_a_single_step() -> int:
	var steps := PackedFloat64Array([10.0])
	var at_5: float = VoidCruiserPhysics.compute_forward_thrust_multiplier(5.0, 5.0, steps)
	var at_20: float = VoidCruiserPhysics.compute_forward_thrust_multiplier(20.0, 5.0, steps)
	if not is_equal_approx(at_5, 10.0) or not is_equal_approx(at_20, 10.0):
		print("FAIL _test_forward_thrust_multiplier_stays_at_a_single_step: %f at 5 s, %f at 20 s, expected 10" % [at_5, at_20])
		return 1
	return 0

func _test_forward_thrust_multiplier_zero_duration_is_the_last_step() -> int:
	var got: float = VoidCruiserPhysics.compute_forward_thrust_multiplier(0.0, 0.0, PackedFloat64Array([10.0, 100.0]))
	if not is_equal_approx(got, 100.0):
		print("FAIL _test_forward_thrust_multiplier_zero_duration_is_the_last_step: %f" % got)
		return 1
	return 0

func _test_forward_thrust_multiplier_no_steps_is_1x() -> int:
	var got: float = VoidCruiserPhysics.compute_forward_thrust_multiplier(7.0, 5.0, PackedFloat64Array())
	if not is_equal_approx(got, 1.0):
		print("FAIL _test_forward_thrust_multiplier_no_steps_is_1x: %f" % got)
		return 1
	return 0
```

In `tests/test_void_cruiser.gd`, replace the line `failures += _test_forward_thrust_ramps_up_velocity_over_time()` with:

```gdscript
	failures += _test_forward_thrust_ramps_to_100x_over_ten_seconds()
	failures += _test_top_speed_about_21_6_km_s_after_the_full_ramp()
```

and replace the whole `func _test_forward_thrust_ramps_up_velocity_over_time()` with:

```gdscript
func _test_forward_thrust_ramps_to_100x_over_ten_seconds() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	cruiser._update_forward_hold_time(1.0, 1.0)
	if not is_equal_approx(cruiser.forward_thrust_multiplier(), 1.0):
		print("FAIL _test_forward_thrust_ramps_to_100x_over_ten_seconds: first-tick multiplier %f, expected 1" % cruiser.forward_thrust_multiplier())
		result = 1
	for i in range(5):
		cruiser._update_forward_hold_time(1.0, 1.0)
	if not is_equal_approx(cruiser.forward_thrust_multiplier(), 10.0):
		print("FAIL _test_forward_thrust_ramps_to_100x_over_ten_seconds: after 5 s multiplier %f, expected 10" % cruiser.forward_thrust_multiplier())
		result = 1
	for i in range(5):
		cruiser._update_forward_hold_time(1.0, 1.0)
	if not is_equal_approx(cruiser.forward_thrust_multiplier(), 100.0):
		print("FAIL _test_forward_thrust_ramps_to_100x_over_ten_seconds: after 10 s multiplier %f, expected 100" % cruiser.forward_thrust_multiplier())
		result = 1
	cruiser.free()
	return result

func _test_top_speed_about_21_6_km_s_after_the_full_ramp() -> int:
	# thrust 150 x 100, damping 0.5: v = 15000 / ln 2 ~ 21.6 km/s (21.8 with
	# 60 Hz steps). 20 s: 10 s of ramp, then 10 s to settle.
	var cruiser: Node3D = VoidCruiserScript.new()
	Input.action_press("move_forward")
	for i in range(1200):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var result := 0
	var speed: float = cruiser.velocity.length()
	if speed < 21000.0 or speed > 22500.0 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_top_speed_about_21_6_km_s_after_the_full_ramp: velocity %s (speed %.0f)" % [cruiser.velocity, speed])
		result = 1
	cruiser.free()
	return result
```

In `tests/test_internal_cruiser.gd`, replace the line `failures += _test_top_speed_about_101_without_ramp()` with:

```gdscript
	failures += _test_ramp_stops_at_10x()
	failures += _test_top_speed_about_1_km_s_after_the_ramp()
```

and replace the whole `func _test_top_speed_about_101_without_ramp()` with:

```gdscript
func _test_ramp_stops_at_10x() -> int:
	var cruiser := _make_cruiser()
	var result := 0
	if cruiser.forward_thrust_steps != PackedFloat64Array([10.0]) or not is_equal_approx(cruiser.forward_thrust_step_duration, 5.0):
		print("FAIL _test_ramp_stops_at_10x: steps %s every %f s, expected [10] every 5 s" % [cruiser.forward_thrust_steps, cruiser.forward_thrust_step_duration])
		result = 1
	cruiser.free()
	return result

func _test_top_speed_about_1_km_s_after_the_ramp() -> int:
	# thrust 70 x 10, damping 0.5: v = 700 / ln 2 ~ 1010 m/s (1016 with 60 Hz
	# steps). Without the ramp it would stay near 101 m/s.
	var cruiser := _make_cruiser()
	Input.action_press("move_forward")
	for i in range(1200):
		cruiser._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var result := 0
	var speed: float = cruiser.velocity.length()
	if speed < 990.0 or speed > 1040.0 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_top_speed_about_1_km_s_after_the_ramp: velocity %s (speed %.1f), expected about 1016 m/s toward -Z" % [cruiser.velocity, speed])
		result = 1
	cruiser.free()
	return result
```

In `tests/test_torus_station_physics.gd`, add below `const TorusGeometry = ...`:

```gdscript
const VoidCruiserScript = preload("res://scripts/void_cruiser.gd")
```

add after `_failures += await _test_rotating_hull_resting_on_docking_collar_does_not_jump()`:

```gdscript
	_failures += await _test_void_cruiser_at_full_ramp_speed_bounces_off_a_section()
```

and append:

```gdscript
func _test_void_cruiser_at_full_ramp_speed_bounces_off_a_section() -> int:
	# At 100x the void-cruiser does ~21.6 km/s, 360 m per tick. The move is
	# swept, so the hull must still stop at the section, not pass through.
	var station := _make_full_scale_station()
	root.add_child(station)
	station.build_station()
	await physics_frame
	var section: Node3D = station.get_node("Section0")
	var axis: Vector3 = section.global_transform.basis.y.normalized()
	var outward: Vector3 = (Vector3.UP - axis * Vector3.UP.dot(axis)).normalized()
	var cruiser: CharacterBody3D = VoidCruiserScript.new()
	cruiser.set_physics_process(false)
	root.add_child(cruiser)
	cruiser.global_position = section.global_position + outward * (station.section_radius + 3000.0)
	await physics_frame
	cruiser.velocity = -outward * 21640.0
	var closest := INF
	for tick in range(40):
		cruiser._move(1.0 / 60.0)
		await physics_frame
		closest = minf(closest, (cruiser.global_position - section.global_position).dot(outward))
	var result := 0
	if closest < station.section_radius or cruiser.velocity.dot(outward) <= 0.0:
		print("FAIL _test_void_cruiser_at_full_ramp_speed_bounces_off_a_section: came within %.1f m of the axis (hull at %.1f), outward speed %.1f" % [closest, station.section_radius, cruiser.velocity.dot(outward)])
		result = 1
	cruiser.free()
	station.free()
	return result
```

- [ ] **Step 2: Run the tests to verify they fail**

Run each:
`/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser_physics.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
`/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_void_cruiser.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
`/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_internal_cruiser.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
`/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_torus_station_physics.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`

Expected:
- physics: `SCRIPT ERROR` (a `PackedFloat64Array` passed where a float is expected) or `FAIL` lines for the steps test.
- void-cruiser: `SCRIPT ERROR` naming `forward_thrust_multiplier`, and `FAIL _test_top_speed_about_21_6_km_s_after_the_full_ramp` (speed about 2.2 km/s).
- internal-cruiser: `FAIL _test_ramp_stops_at_10x` / `SCRIPT ERROR` (no `forward_thrust_steps`), and `FAIL _test_top_speed_about_1_km_s_after_the_ramp` (about 101 m/s).
- station physics: `ALL TESTS PASSED`. The new collision test pins existing behaviour at the new speed; a probe during design already saw the hull bounce (closest 2152 m, outward 5453 m/s). Record it in the ledger as expected-green.

- [ ] **Step 3: Implement the stepped ramp**

In `scripts/void_cruiser_physics.gd`, replace `compute_forward_thrust_multiplier` with:

```gdscript
# Forward-thrust multiplier after holding the key `hold_time` seconds. Each
# entry of `steps` is reached `step_duration` seconds after the previous one,
# rising in a straight line from it (from 1x for the first); past the last
# step the multiplier stays there.
static func compute_forward_thrust_multiplier(hold_time: float, step_duration: float, steps: PackedFloat64Array) -> float:
	if steps.is_empty():
		return 1.0
	if step_duration <= 0.0:
		return steps[steps.size() - 1]
	var t: float = maxf(hold_time, 0.0) / step_duration
	var step: int = floori(t)
	if step >= steps.size():
		return steps[steps.size() - 1]
	var from: float = 1.0 if step == 0 else steps[step - 1]
	return lerpf(from, steps[step], t - step)
```

In `scripts/flying_craft.gd`, change the header comment to:

```gdscript
# Flight model shared by the player's craft: 6-DOF thrust and torque with
# damping, a forward-thrust ramp, mouse-look, and a bounce on collision.
```

add after `@export_range(0.0, 1.0, 0.01) var collision_restitution: float = 0.4`:

```gdscript
# Holding forward or back ramps the thrust through these multipliers, one
# every forward_thrust_step_duration seconds (see
# VoidCruiserPhysics.compute_forward_thrust_multiplier).
@export var forward_thrust_steps: PackedFloat64Array = PackedFloat64Array([10.0])
@export var forward_thrust_step_duration: float = 5.0
```

add after `var _mouse_delta: Vector2 = Vector2.ZERO`:

```gdscript
var _forward_hold_time: float = 0.0
var _forward_hold_sign: float = 0.0
```

and add after `_read_torque_input`:

```gdscript
# One physics tick of player flight: input, ramped forward thrust, motion.
func _fly(delta: float) -> void:
	var thrust_input := _read_thrust_input()
	_update_forward_hold_time(thrust_input.z, delta)
	thrust_input.z *= forward_thrust_multiplier()
	_apply_physics_step(delta, thrust_input, _read_torque_input(delta))

func forward_thrust_multiplier() -> float:
	return VoidCruiserPhysics.compute_forward_thrust_multiplier(_forward_hold_time, forward_thrust_step_duration, forward_thrust_steps)

func _update_forward_hold_time(forward_input: float, delta: float) -> void:
	# Releasing the key, or reversing direction, starts the ramp over from 1x
	# on the very next press.
	var current_sign: float = sign(forward_input)
	if current_sign == 0.0 or current_sign != _forward_hold_sign:
		_forward_hold_time = 0.0
	else:
		_forward_hold_time += delta
	_forward_hold_sign = current_sign
```

In `scripts/void_cruiser.gd`:
- delete the two lines `@export var forward_thrust_ramp_multiplier: float = 10.0` and `@export var forward_thrust_ramp_duration: float = 5.0`, and put in their place:

```gdscript
# Out in the void the ramp goes on: 10x after 5 s, 100x after 10 s.
const VOID_THRUST_STEPS := [10.0, 100.0]
```

- delete `var _forward_hold_time: float = 0.0` and `var _forward_hold_sign: float = 0.0`;
- add before `func _ready() -> void:`:

```gdscript
func _init() -> void:
	forward_thrust_steps = PackedFloat64Array(VOID_THRUST_STEPS)
```

- replace `_physics_process` and delete `_update_forward_hold_time` (it now lives in `flying_craft.gd`); the end of the file becomes:

```gdscript
func _physics_process(delta: float) -> void:
	_fly(delta)
```

In `scripts/internal_cruiser.gd`, replace the header comment and the `_physics_process`:

```gdscript
# The small craft flown inside the station: same controls as the
# void-cruiser, a shorter thrust ramp (it stops at 10x, about 1 km/s), no HUD
# and no gravity.
```

```gdscript
func _physics_process(delta: float) -> void:
	_fly(delta)
```

and change the comment above `INTERNAL_THRUST` to:

```gdscript
# With linear_damping 0.5 the top speed is thrust / ln 2: about 101 m/s at
# 1x, about 1 km/s at the end of the ramp (10x).
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the four commands of Step 2.
Expected: `ALL TESTS PASSED` only, for each file.

Then the full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh > /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.out 2>&1; echo exit $?`
Expected: `exit 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/void_cruiser_physics.gd scripts/flying_craft.gd scripts/void_cruiser.gd scripts/internal_cruiser.gd tests/test_void_cruiser_physics.gd tests/test_void_cruiser.gd tests/test_internal_cruiser.gd tests/test_torus_station_physics.gd
git commit -m "Share a stepped thrust ramp: void-cruiser to 100x, internal-cruiser to 10x

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The interior as a chain of slots

**Files:**
- Modify (rewrite): `scripts/interior_world.gd`
- Modify: `scripts/game_mode.gd` (`_process`, `_can_undock_now`, `enter_interior`)
- Test (rewrite): `tests/test_interior_world.gd`
- Test (update): `tests/test_interior_world_physics.gd`, `tests/test_internal_cruiser_physics.gd`, `tests/test_game_mode.gd`

**Interfaces:**
- Consumes: Task 1's `InteriorLayout` chain functions.
- Produces on `interior_world.gd`:
  - vars `docked_bridge_index := 0`, `ring_sections := 2000` (plus the existing size vars); `behind_section_index` / `ahead_section_index` are gone.
  - consts `LOAD_REACH := 1.25`, `UNLOAD_REACH := 1.5`, `CHUNKS_DRESSED_PER_FRAME := 16`, `CHUNKS_FREED_PER_FRAME := 32`, `LIGHT_FADE_BEGIN := 24000.0`, `LIGHT_FADE_LENGTH := 1000.0`, `ALL_AT_ONCE := 1 << 30`.
  - inner class `SectionLoad` (vars `slot`, `ring_index`, `radius`, `length`, `node`, `plan`, `groups`, `task_id`, `pending_chunks`, `unloading`; funcs `generate()`, `is_ready()`).
  - `build()`, `load_now(focus_z: float)`, `period() -> float`, `get_chain_offset() -> float`, `chain_z(point: Vector3) -> float`, `get_spawn_transform() -> Transform3D`, `get_dock_position(slot: int) -> Vector3` (in this node's coordinates), `nearest_dock_slot(point: Vector3) -> int`, `get_bridge_ring_index(slot: int) -> int`, `set_undock_ready(slot: int, undock_ready: bool)`, `get_section_plan(slot: int)` (plan or null), `is_section_ready(slot: int) -> bool`, `get_loaded_section_slots() -> Array`, `get_bridge_slots() -> Array`.
  - private helpers Task 4 reuses: `_plan_window(focus_z)`, `_finish_plan(state, focus_z)`, `_dress_chunks(focus_z, budget) -> int`, `_free_unloading(budget)`, `_sections` (slot → `SectionLoad`), `_chain`.
  - node paths: `Chain/Section_<slot>/{Chunk_aa_bb, CapBehind, CapAhead, Sun_kk}`, `Chain/Bridge_<slot>/{Segment_k, Light_k, Dock/Platform, Dock/Light, Dock/Sign}`.
- `game_mode.gd` in this task still undocks only at slot 0; Task 5 makes it the nearest dock.

- [ ] **Step 1: Write the failing tests**

Replace `tests/test_interior_world.gd` entirely with:

```gdscript
extends SceneTree

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const SectionGenerator = preload("res://scripts/section_generator.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0
const BRIDGE_RADIUS := 600.0
const BRIDGE_LENGTH := 1834.0
const PERIOD := LENGTH + BRIDGE_LENGTH

func _init():
	var failures := 0
	failures += _test_docking_builds_sections_minus_one_and_zero_and_three_bridges()
	failures += _test_sections_of_320_dressed_chunks_sharing_one_collision_shape()
	failures += _test_terrain_vertices_on_the_wall_facing_the_axis()
	failures += _test_terrain_chunks_tile_the_whole_wall()
	failures += _test_both_caps_open_and_facing_in()
	failures += _test_twenty_suns_per_section_on_the_axis()
	failures += _test_every_bridge_has_its_tube_lights_and_dock()
	failures += _test_spawn_above_the_docked_bridge_platform()
	failures += _test_nearest_dock_slot_and_ring_numbers()
	failures += _test_only_the_named_sign_lights()
	failures += _test_sections_come_from_their_ring_indices()
	failures += _test_plan_from_the_worker_thread_matches_a_direct_one()
	failures += _test_loading_elsewhere_unloads_far_sections()
	failures += _test_axis_lights_reach_the_ground_without_distance_falloff()
	failures += _test_every_light_fades_out_by_25_km()
	failures += _test_at_most_64_lights_within_25_km_along_the_chain()
	failures += _test_every_lit_object_gets_at_most_eight_lights()
	failures += _test_building_at_docking_takes_under_three_seconds()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _make_world(docked := 0) -> Node3D:
	var world: Node3D = InteriorWorldScript.new()
	world.section_radius = RADIUS
	world.section_length = LENGTH
	world.bridge_radius = BRIDGE_RADIUS
	world.bridge_length = BRIDGE_LENGTH
	world.docked_bridge_index = docked
	world.build()
	return world

func _world_transform(node: Node) -> Transform3D:
	var xform := Transform3D()
	var current := node
	while current != null and current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform

func _section_start(slot: int) -> float:
	return -(slot + 0.5) * PERIOD - LENGTH * 0.5

# Every vertex of `mesh` placed by `xform`: at `radius` from the axis, normal
# pointing toward the axis.
func _check_wall(test_name: String, mesh: Mesh, xform: Transform3D, radius: float) -> int:
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(vertices.size()):
			var v: Vector3 = xform * vertices[i]
			var n: Vector3 = xform.basis * normals[i]
			if absf(Vector2(v.x, v.y).length() - radius) > 0.01:
				print("FAIL %s: vertex %s is %.3f m from the axis, expected %.1f" % [test_name, v, Vector2(v.x, v.y).length(), radius])
				return 1
			if n.dot(Vector3(-v.x, -v.y, 0.0)) <= 0.0:
				print("FAIL %s: normal %s at %s points away from the axis" % [test_name, n, v])
				return 1
	return 0

func _test_docking_builds_sections_minus_one_and_zero_and_three_bridges() -> int:
	var world := _make_world()
	var result := 0
	if world.get_loaded_section_slots() != [-1, 0] or world.get_bridge_slots() != [-1, 0, 1]:
		print("FAIL _test_docking_builds_sections_minus_one_and_zero_and_three_bridges: sections %s bridges %s" % [world.get_loaded_section_slots(), world.get_bridge_slots()])
		result = 1
	for slot in [-1, 0]:
		var section := world.get_node_or_null("Chain/Section_%d" % slot) as Node3D
		if section == null or not world.is_section_ready(slot) or not is_equal_approx(section.position.z, -(slot + 0.5) * PERIOD):
			print("FAIL _test_docking_builds_sections_minus_one_and_zero_and_three_bridges: section %d missing, not ready or misplaced" % slot)
			result = 1
	for slot in [-1, 0, 1]:
		var bridge := world.get_node_or_null("Chain/Bridge_%d" % slot) as Node3D
		if bridge == null or not is_equal_approx(bridge.position.z, -slot * PERIOD):
			print("FAIL _test_docking_builds_sections_minus_one_and_zero_and_three_bridges: bridge %d missing or misplaced" % slot)
			result = 1
	world.free()
	return result

func _test_sections_of_320_dressed_chunks_sharing_one_collision_shape() -> int:
	var world := _make_world()
	var result := 0
	var first_shape: Shape3D = null
	for slot in [-1, 0]:
		var section := world.get_node("Chain/Section_%d" % slot)
		var chunks := section.find_children("Chunk_*", "StaticBody3D", false, false)
		if chunks.size() != 320:
			print("FAIL _test_sections_of_320_dressed_chunks_sharing_one_collision_shape: section %d has %d chunks, expected 320" % [slot, chunks.size()])
			result = 1
		for chunk in chunks:
			var shape: Shape3D = (chunk.get_node("Collision") as CollisionShape3D).shape
			if first_shape == null:
				first_shape = shape
			var dressed: bool = chunk.get_node_or_null("Surface") != null or chunk.get_node_or_null("Water") != null
			if shape != first_shape or not (shape is ConcavePolygonShape3D) or not dressed:
				print("FAIL _test_sections_of_320_dressed_chunks_sharing_one_collision_shape: section %d %s not dressed or not sharing the trimesh shape" % [slot, chunk.name])
				result = 1
				break
	world.free()
	return result

func _test_terrain_vertices_on_the_wall_facing_the_axis() -> int:
	var world := _make_world()
	var chunk: Node3D = world.get_node("Chain/Section_0/Chunk_03_07")
	var result := 0
	for part in ["Surface", "Water"]:
		var node := chunk.get_node_or_null(part) as MeshInstance3D
		if node:
			result = maxi(result, _check_wall("_test_terrain_vertices_on_the_wall_facing_the_axis", node.mesh, _world_transform(chunk), RADIUS))
	world.free()
	return result

func _test_terrain_chunks_tile_the_whole_wall() -> int:
	var world := _make_world()
	var result := 0
	for slot in [-1, 0]:
		var first: Node3D = world.get_node("Chain/Section_%d/Chunk_00_00" % slot)
		var last: Node3D = world.get_node("Chain/Section_%d/Chunk_15_19" % slot)
		var start: float = _section_start(slot)
		var first_z: float = _world_transform(first).origin.z
		var last_z: float = _world_transform(last).origin.z
		if not is_equal_approx(first_z, start) or not is_equal_approx(last_z + 1000.0, start + LENGTH):
			print("FAIL _test_terrain_chunks_tile_the_whole_wall: section %d chunks span %f..%f expected %f..%f" % [slot, first_z, last_z + 1000.0, start, start + LENGTH])
			result = 1
		var last_angle: float = atan2(last.transform.basis.x.y, last.transform.basis.x.x)
		if not is_equal_approx(fposmod(last_angle, TAU), 15.0 * TAU / 16.0):
			print("FAIL _test_terrain_chunks_tile_the_whole_wall: section %d last chunk turned %f rad" % [slot, last_angle])
			result = 1
	world.free()
	return result

func _cap_min_radius_and_facing(cap: Node3D) -> Array:
	var mesh: Mesh = (cap.get_node("Mesh") as MeshInstance3D).mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var min_radius := INF
	for v in vertices:
		min_radius = minf(min_radius, Vector2(v.x, v.y).length())
	var facing_z: float = (cap.transform.basis * normals[0]).z
	return [min_radius, facing_z]

func _test_both_caps_open_and_facing_in() -> int:
	var world := _make_world()
	var result := 0
	for slot in [-1, 0]:
		var section := world.get_node("Chain/Section_%d" % slot)
		# [name, local z in section lengths, facing along Z]
		for c in [["CapBehind", 0.5, -1.0], ["CapAhead", -0.5, 1.0]]:
			var cap := section.get_node_or_null(c[0]) as StaticBody3D
			if cap == null:
				print("FAIL _test_both_caps_open_and_facing_in: section %d has no %s" % [slot, c[0]])
				result = 1
				continue
			var info: Array = _cap_min_radius_and_facing(cap)
			if absf(info[0] - BRIDGE_RADIUS) > 0.01 or signf(info[1]) != c[2] or not is_equal_approx(cap.position.z, c[1] * LENGTH):
				print("FAIL _test_both_caps_open_and_facing_in: section %d %s hole %f facing %f at z %f" % [slot, c[0], info[0], info[1], cap.position.z])
				result = 1
			if not ((cap.get_node("Collision") as CollisionShape3D).shape is ConcavePolygonShape3D):
				print("FAIL _test_both_caps_open_and_facing_in: section %d %s has no trimesh collision" % [slot, c[0]])
				result = 1
	world.free()
	return result

func _test_twenty_suns_per_section_on_the_axis() -> int:
	var world := _make_world()
	var result := 0
	for slot in [-1, 0]:
		var section := world.get_node("Chain/Section_%d" % slot)
		var suns := section.find_children("Sun_*", "Node3D", false, false)
		if suns.size() != 20:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: section %d has %d suns" % [slot, suns.size()])
			result = 1
			continue
		var first: Node3D = section.get_node("Sun_00")
		if not _world_transform(first).origin.is_equal_approx(Vector3(0.0, 0.0, _section_start(slot) + 500.0)):
			print("FAIL _test_twenty_suns_per_section_on_the_axis: section %d Sun_00 at %s" % [slot, _world_transform(first).origin])
			result = 1
		var light := first.get_node_or_null("Light") as OmniLight3D
		if light == null or not is_equal_approx(light.omni_range, 2600.0) or light.shadow_enabled or first.get_node_or_null("Globe") == null:
			print("FAIL _test_twenty_suns_per_section_on_the_axis: section %d Sun_00 light or globe wrong" % slot)
			result = 1
	world.free()
	return result

func _test_every_bridge_has_its_tube_lights_and_dock() -> int:
	var world := _make_world()
	var result := 0
	for slot in [-1, 0, 1]:
		var bridge: Node3D = world.get_node("Chain/Bridge_%d" % slot)
		for k in range(4):
			var segment := bridge.get_node_or_null("Segment_%d" % k) as StaticBody3D
			if segment == null or not is_equal_approx(segment.position.z, -BRIDGE_LENGTH * 0.5 + k * BRIDGE_LENGTH / 4.0):
				print("FAIL _test_every_bridge_has_its_tube_lights_and_dock: bridge %d Segment_%d missing or misplaced" % [slot, k])
				result = 1
				continue
			var mesh: Mesh = (segment.get_node("Mesh") as MeshInstance3D).mesh
			result = maxi(result, _check_wall("_test_every_bridge_has_its_tube_lights_and_dock", mesh, _world_transform(segment), BRIDGE_RADIUS))
		for k in range(3):
			var light := bridge.get_node_or_null("Light_%d" % k) as OmniLight3D
			if light == null or not light.position.is_equal_approx(Vector3(0.0, 0.0, BRIDGE_LENGTH * (k - 1) / 3.0)):
				print("FAIL _test_every_bridge_has_its_tube_lights_and_dock: bridge %d Light_%d missing or misplaced" % [slot, k])
				result = 1
		var platform := bridge.get_node_or_null("Dock/Platform") as StaticBody3D
		var undock_sign := bridge.get_node_or_null("Dock/Sign") as Label3D
		if platform == null or not platform.position.is_equal_approx(Vector3(0.0, -BRIDGE_RADIUS + 2.0, 0.0)) or bridge.get_node_or_null("Dock/Light") == null:
			print("FAIL _test_every_bridge_has_its_tube_lights_and_dock: bridge %d dock platform or light wrong" % slot)
			result = 1
		if undock_sign == null or undock_sign.text != "UNDOCK  [F]" or not undock_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
			print("FAIL _test_every_bridge_has_its_tube_lights_and_dock: bridge %d sign missing, wrong text or not idle" % slot)
			result = 1
	world.free()
	return result

func _test_spawn_above_the_docked_bridge_platform() -> int:
	var world := _make_world()
	var result := 0
	var platform := Vector3(0.0, -BRIDGE_RADIUS + 2.0, 0.0)
	for slot in [-1, 0, 1]:
		var expected: Vector3 = platform + Vector3(0.0, 0.0, -slot * PERIOD)
		if not world.get_dock_position(slot).is_equal_approx(expected):
			print("FAIL _test_spawn_above_the_docked_bridge_platform: dock %d at %s, expected %s" % [slot, world.get_dock_position(slot), expected])
			result = 1
	var spawn: Transform3D = world.get_spawn_transform()
	if not spawn.origin.is_equal_approx(platform + Vector3(0.0, 24.0, 0.0)) or not spawn.basis.is_equal_approx(Basis()):
		print("FAIL _test_spawn_above_the_docked_bridge_platform: spawn %s" % spawn)
		result = 1
	world.free()
	return result

func _test_nearest_dock_slot_and_ring_numbers() -> int:
	var world := _make_world()
	var result := 0
	for c in [[Vector3(0.0, 0.0, -0.4 * PERIOD), 0], [Vector3(100.0, -300.0, -0.6 * PERIOD), 1], [Vector3(0.0, 0.0, 0.7 * PERIOD), -1]]:
		if world.nearest_dock_slot(c[0]) != c[1]:
			print("FAIL _test_nearest_dock_slot_and_ring_numbers: %s gave slot %d, expected %d" % [c[0], world.nearest_dock_slot(c[0]), c[1]])
			result = 1
	world.free()
	var last: Node3D = InteriorWorldScript.new()
	last.docked_bridge_index = 1999
	last.ring_sections = 2000
	if last.get_bridge_ring_index(0) != 1999 or last.get_bridge_ring_index(1) != 0 or last.get_bridge_ring_index(-1) != 1998:
		print("FAIL _test_nearest_dock_slot_and_ring_numbers: from bridge 1999, slots -1/0/1 are bridges %d/%d/%d" % [last.get_bridge_ring_index(-1), last.get_bridge_ring_index(0), last.get_bridge_ring_index(1)])
		result = 1
	last.free()
	return result

func _sign_color(world: Node3D, slot: int) -> Color:
	return (world.get_node("Chain/Bridge_%d/Dock/Sign" % slot) as Label3D).modulate

func _test_only_the_named_sign_lights() -> int:
	var world := _make_world()
	var result := 0
	world.set_undock_ready(1, true)
	for slot in [-1, 0, 1]:
		var expected: Color = InteriorWorldScript.SIGN_READY_COLOR if slot == 1 else InteriorWorldScript.SIGN_IDLE_COLOR
		if not _sign_color(world, slot).is_equal_approx(expected):
			print("FAIL _test_only_the_named_sign_lights: sign %d is %s with slot 1 ready" % [slot, _sign_color(world, slot)])
			result = 1
	world.set_undock_ready(1, false)
	for slot in [-1, 0, 1]:
		if not _sign_color(world, slot).is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
			print("FAIL _test_only_the_named_sign_lights: sign %d still lit when nothing is ready" % slot)
			result = 1
	world.free()
	return result

func _test_sections_come_from_their_ring_indices() -> int:
	# Docked at the last bridge: behind is section 1999, ahead is section 0.
	var world := _make_world(1999)
	var result := 0
	var behind = world.get_section_plan(-1)
	var ahead = world.get_section_plan(0)
	if behind == null or ahead == null or behind.section_index != 1999 or ahead.section_index != 0:
		print("FAIL _test_sections_come_from_their_ring_indices: expected sections 1999 and 0")
		world.free()
		return 1
	var groups: Dictionary = ahead.group_buildings_by_chunk()
	var key: Vector2i = groups.keys()[0]
	var buildings := world.get_node("Chain/Section_0/Chunk_%02d_%02d/Buildings" % [key.x, key.y]) as MultiMeshInstance3D
	if buildings == null or buildings.multimesh.instance_count != groups[key].size():
		print("FAIL _test_sections_come_from_their_ring_indices: chunk %s does not hold the plan's %d buildings" % [key, groups[key].size()])
		result = 1
	world.free()
	return result

func _test_plan_from_the_worker_thread_matches_a_direct_one() -> int:
	var world := _make_world()
	var threaded = world.get_section_plan(0)
	var direct = SectionGenerator.generate(1, RADIUS, LENGTH)
	var result := 0
	if threaded == null or threaded.zones != direct.zones or threaded.crops != direct.crops or threaded.road_west != direct.road_west or threaded.road_south != direct.road_south or threaded.building_x != direct.building_x or threaded.building_z != direct.building_z or threaded.building_size != direct.building_size:
		print("FAIL _test_plan_from_the_worker_thread_matches_a_direct_one: plans differ")
		result = 1
	world.free()
	return result

func _test_loading_elsewhere_unloads_far_sections() -> int:
	var world := _make_world()
	world.load_now(-2.2 * PERIOD)
	var result := 0
	if world.get_loaded_section_slots() != [1, 2] or world.get_bridge_slots() != [1, 2, 3]:
		print("FAIL _test_loading_elsewhere_unloads_far_sections: sections %s bridges %s, expected [1, 2] and [1, 2, 3]" % [world.get_loaded_section_slots(), world.get_bridge_slots()])
		result = 1
	for gone in ["Chain/Section_-1", "Chain/Section_0", "Chain/Bridge_-1", "Chain/Bridge_0"]:
		if world.get_node_or_null(gone) != null:
			print("FAIL _test_loading_elsewhere_unloads_far_sections: %s still there" % gone)
			result = 1
	if not world.is_section_ready(1) or not world.is_section_ready(2):
		print("FAIL _test_loading_elsewhere_unloads_far_sections: sections 1 and 2 not ready")
		result = 1
	world.free()
	return result

func _axis_lights(world: Node3D) -> Array:
	var lights := []
	for slot in world.get_loaded_section_slots():
		for sun in world.get_node("Chain/Section_%d" % slot).find_children("Sun_*", "Node3D", false, false):
			lights.append(sun.get_node("Light"))
	for slot in world.get_bridge_slots():
		for k in range(3):
			lights.append(world.get_node("Chain/Bridge_%d/Light_%d" % [slot, k]))
	return lights

func _test_axis_lights_reach_the_ground_without_distance_falloff() -> int:
	# With the default attenuation 1.0 a light falls off as 1/d: 2000 m from the
	# axis a sun gives ~6e-4 of its energy and the ground reads near-black.
	var world := _make_world()
	var result := 0
	for light: OmniLight3D in _axis_lights(world):
		if light.omni_attenuation > 0.1:
			print("FAIL _test_axis_lights_reach_the_ground_without_distance_falloff: %s omni_attenuation=%f" % [light.name, light.omni_attenuation])
			result = 1
			break
	world.free()
	return result

func _test_every_light_fades_out_by_25_km() -> int:
	var world := _make_world()
	var result := 0
	for light: OmniLight3D in world.find_children("*", "OmniLight3D", true, false):
		if not light.distance_fade_enabled or not is_equal_approx(light.distance_fade_begin, 24000.0) or not is_equal_approx(light.distance_fade_length, 1000.0):
			print("FAIL _test_every_light_fades_out_by_25_km: %s/%s fade %s %f %f" % [light.get_parent().name, light.name, light.distance_fade_enabled, light.distance_fade_begin, light.distance_fade_length])
			result = 1
			break
	world.free()
	return result

func _test_at_most_64_lights_within_25_km_along_the_chain() -> int:
	# The renderer draws at most max_renderable_lights per frame and drops the
	# rest in cull order. Lights past their fade distance are not drawn, so
	# what counts is how many sit within 25 km of the camera.
	var world := _make_world()
	world.load_now(-0.5 * PERIOD)  # 3 sections, 4 bridges: the most ever loaded
	var budget: int = ProjectSettings.get_setting("rendering/limits/opengl/max_renderable_lights")
	var positions := []
	for light in world.find_children("*", "OmniLight3D", true, false):
		positions.append(_world_transform(light).origin)
	var worst := 0
	var z := 0.5 * PERIOD
	while z >= -1.5 * PERIOD:
		var count := 0
		for p: Vector3 in positions:
			if p.distance_to(Vector3(0.0, 0.0, z)) < 25000.0:
				count += 1
		worst = maxi(worst, count)
		z -= 500.0
	print("  %d interior lights loaded, at most %d within 25 km" % [positions.size(), worst])
	world.free()
	if worst > budget:
		print("FAIL _test_at_most_64_lights_within_25_km_along_the_chain: %d lights within 25 km, renderer draws %d" % [worst, budget])
		return 1
	return 0

func _test_every_lit_object_gets_at_most_eight_lights() -> int:
	# The engine pairs a light with an object when their bounding boxes meet;
	# an omni light's box is a cube of +/- its range. Past 8, lights drop.
	var world := _make_world()
	world.load_now(-0.5 * PERIOD)
	var light_boxes := []
	for light: OmniLight3D in world.find_children("*", "OmniLight3D", true, false):
		var reach := Vector3.ONE * light.omni_range
		light_boxes.append(AABB(_world_transform(light).origin - reach, reach * 2.0))
	var result := 0
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		if node.name == "Globe" or node is Label3D:
			continue  # unshaded sun globes and the signs are not lit
		var geometry := node as GeometryInstance3D
		var local: AABB = geometry.custom_aabb if geometry.custom_aabb.has_volume() else geometry.get_aabb()
		var box: AABB = _world_transform(geometry) * local
		var count := 0
		for light_box: AABB in light_boxes:
			if light_box.intersects(box):
				count += 1
		if count > 8:
			print("FAIL _test_every_lit_object_gets_at_most_eight_lights: %s/%s is reached by %d lights" % [geometry.get_parent().name, geometry.name, count])
			result = 1
			break
	world.free()
	return result

func _test_building_at_docking_takes_under_three_seconds() -> int:
	# Built on docking, behind the fade to black: target 1.5 s, fail past 3 s.
	var start := Time.get_ticks_msec()
	var world := _make_world()
	var elapsed := Time.get_ticks_msec() - start
	print("  interior build: %d ms" % elapsed)
	world.free()
	if elapsed > 3000:
		print("FAIL _test_building_at_docking_takes_under_three_seconds: %d ms" % elapsed)
		return 1
	return 0
```

In `tests/test_interior_world_physics.gd`, in `_field_point`, change `var plan = world.get_section_plan(-1.0)` to:

```gdscript
	var plan = world.get_section_plan(0)
```

In `tests/test_internal_cruiser_physics.gd`:
- change both `var plan = probe.get_section_plan(-1.0)` to `var plan = probe.get_section_plan(0)`;
- in `_test_hits_a_building_and_bounces`, change `deepest = maxf(deepest, cruiser.position.z + 4.0)` to (positions along Z are chain positions once the origin can shift):

```gdscript
		deepest = maxf(deepest, world.chain_z(cruiser.position) + 4.0)
```

- replace the line `_failures += await _test_cannot_fly_through_the_far_cap()` with `_failures += await _test_bounces_off_the_cap_around_the_hole()`, and replace the whole `func _test_cannot_fly_through_the_far_cap()` with:

```gdscript
func _test_bounces_off_the_cap_around_the_hole() -> int:
	# Every cap now has the bridge's hole (radius 600) in the middle; 1000 m
	# from the axis it is still a wall.
	var cap_z: float = -(1834.0 * 0.5 + 20000.0)
	var nodes := _make_world_with_cruiser(Vector3(1000.0, 0.0, cap_z + 200.0), Vector3(0.0, 0.0, -100.0))
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	var furthest := 0.0
	for tick in range(240):
		await physics_frame
		furthest = minf(furthest, world.chain_z(cruiser.position))
	var result := 0
	if furthest < cap_z or cruiser.velocity.z <= 0.0:
		print("FAIL _test_bounces_off_the_cap_around_the_hole: reached z %.2f (cap at %.2f), velocity %s" % [furthest, cap_z, cruiser.velocity])
		result = 1
	world.free()
	return result
```

In `tests/test_game_mode.gd`:
- change `var undock_sign: Label3D = interior.get_node("Dock/Sign")` to `var undock_sign: Label3D = interior.get_node("Chain/Bridge_0/Dock/Sign")`;
- change `interior.get_node("Dock/Sign")` in `_test_undock_key_far_from_dock_does_nothing` to `interior.get_node("Chain/Bridge_0/Dock/Sign")`;
- in `_test_interior_sections_follow_the_docked_bridge`, change the two plan lines to:

```gdscript
		var behind: int = interior.get_section_plan(-1).section_index
		var ahead: int = interior.get_section_plan(0).section_index
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_interior_world.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -20`
Expected: `SCRIPT ERROR` lines (no `docked_bridge_index` / `get_loaded_section_slots`) and `FAIL` lines.

- [ ] **Step 3: Rewrite `scripts/interior_world.gd`**

Replace the file with:

```gdscript
extends Node3D

# The inside of the station: a straight chain of sections and bridges along
# the Z axis (see InteriorLayout for slots), built around the craft as it
# flies. At docking the docked bridge is slot 0, centred on the origin. It
# does not rotate: this is the frame of the people living inside, so the
# ground stays still.

const InteriorLayout = preload("res://scripts/interior_layout.gd")
const SectionGeneratorScript = preload("res://scripts/section_generator.gd")
const TerrainDressingScript = preload("res://scripts/terrain_dressing.gd")

# Set before build(); defaults are the full-scale station's.
var section_radius := 2000.0
var section_length := 20000.0
var bridge_radius := 600.0
var bridge_length := 1834.0
# The station bridge docked at (slot 0) and how many sections the ring has:
# past the last one the chain goes on from section 0.
var docked_bridge_index := 0
var ring_sections := 2000

# Terrain split in chunks: the renderer lights each object with at most 8
# lights (see InteriorLayout.count_lights_reaching_band).
const CHUNKS_AROUND := 16
const CHUNK_LENGTH := 1000.0
const CHUNK_ARC_SEGMENTS := 8
const CHUNK_LENGTH_SEGMENTS := 4
const CAP_SEGMENTS := 128
const TUBE_SEGMENTS := 4
const TUBE_ARC_SEGMENTS := 64

# Sections load within LOAD_REACH chain periods of the craft (centre to
# craft, along the axis) and unload past UNLOAD_REACH: the gap keeps a
# section from being built and thrown away while hovering at the edge.
const LOAD_REACH := 1.25
const UNLOAD_REACH := 1.5
# Per-frame work while flying (about 13 ms and 7 ms measured).
const CHUNKS_DRESSED_PER_FRAME := 16
const CHUNKS_FREED_PER_FRAME := 32
const ALL_AT_ONCE := 1 << 30

const SUN_SPACING := 1000.0
const SUN_RANGE := 2600.0
const SUN_ENERGY := 1.5
# No distance falloff inside the range (only the range's soft edge): with
# the default 1/d falloff a sun 2000 m above the ground lights it at ~6e-4
# of its energy and the interior reads black.
const AXIS_LIGHT_ATTENUATION := 0.0
const SUN_COLOR := Color(1.0, 0.93, 0.8)
const SUN_GLOBE_RADIUS := 30.0
const BRIDGE_LIGHT_RANGE := 900.0
const BRIDGE_LIGHT_ENERGY := 1.0
# Up to 76 lights are loaded; the renderer draws at most 64. Past 25 km from
# the camera a light is gone, which leaves about 54.
const LIGHT_FADE_BEGIN := 24000.0
const LIGHT_FADE_LENGTH := 1000.0

const STRUCTURE_COLOR := Color(0.45, 0.47, 0.5)

const DOCK_PLATFORM_SIZE := Vector3(60.0, 4.0, 60.0)
const DOCK_LIGHT_RANGE := 150.0
const SPAWN_HEIGHT := 24.0
const SIGN_TEXT := "UNDOCK  [F]"
const SIGN_READY_COLOR := Color(0.3, 1.0, 0.4)
const SIGN_IDLE_COLOR := Color(0.5, 0.5, 0.5)

# One section of the chain, from the moment it is wanted until it is freed.
class SectionLoad:
	extends RefCounted
	var slot := 0
	var ring_index := 0
	var radius := 0.0
	var length := 0.0
	var node: Node3D
	var plan = null
	var groups := {}
	var task_id := -1
	var pending_chunks := []
	var unloading := false

	# Runs on a worker thread: touches nothing but this object.
	func generate() -> void:
		plan = SectionGeneratorScript.generate(ring_index, radius, length)
		groups = plan.group_buildings_by_chunk()

	func is_ready() -> bool:
		return task_id < 0 and plan != null and pending_chunks.is_empty() and not unloading

var _chain: Node3D
var _structure_material: StandardMaterial3D
var _dock_material: StandardMaterial3D
var _sun_mesh: SphereMesh
var _sun_material: StandardMaterial3D
var _chunk_shape: Shape3D
var _cap_mesh: ArrayMesh
var _cap_shape: Shape3D
var _tube_mesh: ArrayMesh
var _tube_shape: Shape3D
var _dressing
var _sections := {}
var _bridges := {}

func build() -> void:
	_structure_material = _make_material(STRUCTURE_COLOR, 0.6)
	_dock_material = _make_material(SIGN_READY_COLOR, 0.5)
	_dock_material.emission_enabled = true
	_dock_material.emission = SIGN_READY_COLOR
	_dock_material.emission_energy_multiplier = 1.5
	_sun_mesh = SphereMesh.new()
	_sun_mesh.radius = SUN_GLOBE_RADIUS
	_sun_mesh.height = SUN_GLOBE_RADIUS * 2.0
	_sun_material = StandardMaterial3D.new()
	_sun_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sun_material.albedo_color = SUN_COLOR
	# Every chunk's floor collides as the same piece of wall, turned and
	# shifted: one collision shape for all of them. What is drawn on it comes
	# from the section's plan.
	_chunk_shape = _build_band_mesh(section_radius, TAU / CHUNKS_AROUND, CHUNK_LENGTH, CHUNK_ARC_SEGMENTS, CHUNK_LENGTH_SEGMENTS).create_trimesh_shape()
	_cap_mesh = _build_annulus_mesh(bridge_radius, section_radius, CAP_SEGMENTS)
	_cap_shape = _cap_mesh.create_trimesh_shape()
	_tube_mesh = _build_band_mesh(bridge_radius, TAU, bridge_length / TUBE_SEGMENTS, TUBE_ARC_SEGMENTS, 1)
	_tube_shape = _tube_mesh.create_trimesh_shape()
	_dressing = TerrainDressingScript.new()
	_chain = Node3D.new()
	_chain.name = "Chain"
	add_child(_chain)
	# At docking the two sections beside the bridge are built whole, behind
	# the fade.
	load_now(0.0)

# Loads everything wanted around chain position `focus_z` at once, waiting
# for every plan, and frees what is too far.
func load_now(focus_z: float) -> void:
	_plan_window(focus_z)
	for state: SectionLoad in _sections.values():
		if state.task_id >= 0:
			_finish_plan(state, focus_z)
	_dress_chunks(focus_z, ALL_AT_ONCE)
	_free_unloading(ALL_AT_ONCE)

func period() -> float:
	return InteriorLayout.chain_period(section_length, bridge_length)

# How far the chain has been moved along Z to keep the craft near the origin.
func get_chain_offset() -> float:
	return _chain.position.z

# Position along the chain of a point given in this node's coordinates.
func chain_z(point: Vector3) -> float:
	return point.z - _chain.position.z

# Above the docked bridge's platform, bow toward -Z, "up" toward the tube's
# axis (the platform sits at the bottom of the tube).
func get_spawn_transform() -> Transform3D:
	return Transform3D(Basis(), get_dock_position(0) + Vector3(0.0, SPAWN_HEIGHT, 0.0))

# The dock platform of bridge `slot`, in this node's coordinates.
func get_dock_position(slot: int) -> Vector3:
	return _platform_position() + Vector3(0.0, 0.0, InteriorLayout.bridge_slot_z(slot, period()) + _chain.position.z)

func nearest_dock_slot(point: Vector3) -> int:
	return InteriorLayout.nearest_bridge_slot(chain_z(point), period())

func get_bridge_ring_index(slot: int) -> int:
	return InteriorLayout.bridge_ring_index(docked_bridge_index, slot, ring_sections)

# Lights the sign of bridge `slot` when undocking is possible there; every
# other sign stays idle.
func set_undock_ready(slot: int, undock_ready: bool) -> void:
	for bridge_slot in _bridges:
		var lit: bool = undock_ready and bridge_slot == slot
		(_bridges[bridge_slot].get_node("Dock/Sign") as Label3D).modulate = SIGN_READY_COLOR if lit else SIGN_IDLE_COLOR

# The plan of section `slot`, or null while it is not generated.
func get_section_plan(slot: int):
	var state: SectionLoad = _sections.get(slot)
	return state.plan if state != null and state.task_id < 0 else null

func is_section_ready(slot: int) -> bool:
	return _sections.has(slot) and (_sections[slot] as SectionLoad).is_ready()

func get_loaded_section_slots() -> Array:
	var slots := []
	for slot in _sections:
		if not (_sections[slot] as SectionLoad).unloading:
			slots.append(slot)
	slots.sort()
	return slots

func get_bridge_slots() -> Array:
	var slots := _bridges.keys()
	slots.sort()
	return slots

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# A worker may still be generating a plan: never let it outlive us.
		for state: SectionLoad in _sections.values():
			if state.task_id >= 0:
				WorkerThreadPool.wait_for_task_completion(state.task_id)
				state.task_id = -1

# Starts every wanted section, marks far ones for unloading, and keeps the
# bridges at both ends of the loaded sections.
func _plan_window(focus_z: float) -> void:
	var p := period()
	for slot in InteriorLayout.sections_within(focus_z, p, LOAD_REACH * p):
		if not _sections.has(slot):
			_start_section(slot)
	for slot in _sections:
		var state: SectionLoad = _sections[slot]
		if state.task_id < 0 and absf(InteriorLayout.section_slot_z(slot, p) - focus_z) > UNLOAD_REACH * p:
			state.unloading = true
	_update_bridges()

func _start_section(slot: int) -> void:
	var state := SectionLoad.new()
	state.slot = slot
	state.ring_index = InteriorLayout.section_ring_index(docked_bridge_index, slot, ring_sections)
	state.radius = section_radius
	state.length = section_length
	state.node = _build_section_shell(slot)
	_chain.add_child(state.node)
	state.task_id = WorkerThreadPool.add_task(state.generate)
	_sections[slot] = state

# Takes the finished plan and queues the section's chunks, nearest first.
func _finish_plan(state: SectionLoad, focus_z: float) -> void:
	WorkerThreadPool.wait_for_task_completion(state.task_id)
	state.task_id = -1
	var start_z: float = InteriorLayout.section_slot_z(state.slot, period()) - section_length * 0.5
	var chunks := []
	for along in range(roundi(section_length / CHUNK_LENGTH)):
		for around in range(CHUNKS_AROUND):
			chunks.append(Vector2i(around, along))
	chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return absf(start_z + (a.y + 0.5) * CHUNK_LENGTH - focus_z) < absf(start_z + (b.y + 0.5) * CHUNK_LENGTH - focus_z))
	state.pending_chunks = chunks

# Dresses up to `budget` chunks, nearest section first. Returns how many.
func _dress_chunks(focus_z: float, budget: int) -> int:
	var p := period()
	var order: Array = _sections.values().filter(func(s: SectionLoad) -> bool:
		return s.task_id < 0 and not s.unloading and not s.pending_chunks.is_empty())
	order.sort_custom(func(a: SectionLoad, b: SectionLoad) -> bool:
		return absf(InteriorLayout.section_slot_z(a.slot, p) - focus_z) < absf(InteriorLayout.section_slot_z(b.slot, p) - focus_z))
	var dressed := 0
	for state: SectionLoad in order:
		while dressed < budget and not state.pending_chunks.is_empty():
			var key: Vector2i = state.pending_chunks.pop_front()
			_build_chunk(state, key.x, key.y)
			dressed += 1
	return dressed

# Frees up to `budget` chunks of unloading sections; a section with no chunks
# left goes with its caps and suns.
func _free_unloading(budget: int) -> void:
	var freed := 0
	for slot in _sections.keys():
		var state: SectionLoad = _sections[slot]
		if not state.unloading:
			continue
		for chunk in state.node.find_children("Chunk_*", "StaticBody3D", false, false):
			if freed >= budget:
				return
			chunk.free()
			freed += 1
		state.node.free()
		_sections.erase(slot)

func _update_bridges() -> void:
	var wanted := InteriorLayout.bridges_of_sections(get_loaded_section_slots())
	for slot in _bridges.keys():
		if not wanted.has(slot):
			(_bridges[slot] as Node3D).free()
			_bridges.erase(slot)
	for slot in wanted:
		if not _bridges.has(slot):
			var bridge := _build_bridge(slot)
			_chain.add_child(bridge)
			_bridges[slot] = bridge

func _platform_position() -> Vector3:
	return Vector3(0.0, -bridge_radius + DOCK_PLATFORM_SIZE.y * 0.5, 0.0)

# The section node at its centre, with its caps and suns; chunks come later.
func _build_section_shell(slot: int) -> Node3D:
	var section := Node3D.new()
	section.name = "Section_%d" % slot
	section.position = Vector3(0.0, 0.0, InteriorLayout.section_slot_z(slot, period()))
	# Both caps face into the section and have the bridge's hole: the way on
	# is always open.
	section.add_child(_build_cap("CapBehind", section_length * 0.5, -1.0))
	section.add_child(_build_cap("CapAhead", -section_length * 0.5, 1.0))
	var suns: PackedVector3Array = InteriorLayout.sun_positions(0.0, section_length, SUN_SPACING)
	for k in range(suns.size()):
		section.add_child(_build_sun("Sun_%02d" % k, suns[k]))
	return section

func _build_chunk(state: SectionLoad, around: int, along: int) -> void:
	var chunk := StaticBody3D.new()
	chunk.name = "Chunk_%02d_%02d" % [around, along]
	chunk.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), around * TAU / CHUNKS_AROUND), Vector3(0.0, 0.0, -section_length * 0.5 + along * CHUNK_LENGTH))
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = _chunk_shape
	chunk.add_child(collision)
	_dressing.dress_chunk(chunk, state.plan, around, along, state.groups.get(Vector2i(around, along), []))
	state.node.add_child(chunk)

func _build_cap(cap_name: String, z: float, facing: float) -> StaticBody3D:
	var cap := StaticBody3D.new()
	cap.name = cap_name
	# The annulus faces -Z; half a turn around Y makes it face +Z.
	var cap_basis := Basis() if facing < 0.0 else Basis(Vector3.UP, PI)
	cap.transform = Transform3D(cap_basis, Vector3(0.0, 0.0, z))
	_add_mesh_and_collision(cap, _cap_mesh, _cap_shape, _structure_material)
	return cap

func _fade_with_distance(light: Light3D) -> void:
	light.distance_fade_enabled = true
	light.distance_fade_begin = LIGHT_FADE_BEGIN
	light.distance_fade_length = LIGHT_FADE_LENGTH

func _build_sun(sun_name: String, sun_position: Vector3) -> Node3D:
	var sun := Node3D.new()
	sun.name = sun_name
	sun.position = sun_position
	var globe := MeshInstance3D.new()
	globe.name = "Globe"
	globe.mesh = _sun_mesh
	globe.material_override = _sun_material
	sun.add_child(globe)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = SUN_COLOR
	light.light_energy = SUN_ENERGY
	light.omni_range = SUN_RANGE
	light.omni_attenuation = AXIS_LIGHT_ATTENUATION
	# No shadows: at kilometre scale shadow maps band and flicker (as the
	# headlights did), and 60 shadowed lights would cost too much.
	light.shadow_enabled = false
	_fade_with_distance(light)
	sun.add_child(light)
	return sun

func _build_bridge(slot: int) -> Node3D:
	var bridge := Node3D.new()
	bridge.name = "Bridge_%d" % slot
	bridge.position = Vector3(0.0, 0.0, InteriorLayout.bridge_slot_z(slot, period()))
	var segment_length: float = bridge_length / TUBE_SEGMENTS
	for k in range(TUBE_SEGMENTS):
		var segment := StaticBody3D.new()
		segment.name = "Segment_%d" % k
		segment.position = Vector3(0.0, 0.0, -bridge_length * 0.5 + k * segment_length)
		_add_mesh_and_collision(segment, _tube_mesh, _tube_shape, _structure_material)
		bridge.add_child(segment)
	for k in range(3):
		var light := OmniLight3D.new()
		light.name = "Light_%d" % k
		light.position = Vector3(0.0, 0.0, bridge_length * (k - 1) / 3.0)
		light.light_color = SUN_COLOR
		light.light_energy = BRIDGE_LIGHT_ENERGY
		light.omni_range = BRIDGE_LIGHT_RANGE
		light.omni_attenuation = AXIS_LIGHT_ATTENUATION
		light.shadow_enabled = false
		_fade_with_distance(light)
		bridge.add_child(light)
	bridge.add_child(_build_dock())
	return bridge

func _build_dock() -> Node3D:
	var dock := Node3D.new()
	dock.name = "Dock"

	var platform := StaticBody3D.new()
	platform.name = "Platform"
	platform.position = _platform_position()
	var box := BoxMesh.new()
	box.size = DOCK_PLATFORM_SIZE
	var box_shape := BoxShape3D.new()
	box_shape.size = DOCK_PLATFORM_SIZE
	_add_mesh_and_collision(platform, box, box_shape, _dock_material)
	dock.add_child(platform)

	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = _platform_position() + Vector3(0.0, 30.0, 0.0)
	light.light_color = SIGN_READY_COLOR
	light.light_energy = 2.0
	light.omni_range = DOCK_LIGHT_RANGE
	light.shadow_enabled = false
	_fade_with_distance(light)
	dock.add_child(light)

	# The only undock cue: there is no HUD inside.
	var undock_sign := Label3D.new()
	undock_sign.name = "Sign"
	undock_sign.text = SIGN_TEXT
	undock_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	undock_sign.font_size = 96
	undock_sign.pixel_size = 0.1
	undock_sign.position = _platform_position() + Vector3(0.0, 45.0, 0.0)
	undock_sign.modulate = SIGN_IDLE_COLOR
	dock.add_child(undock_sign)
	return dock

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _add_mesh_and_collision(body: Node3D, mesh: Mesh, shape: Shape3D, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)

# Inner wall of a cylinder: angle 0..angle_span, z 0..length, facing the axis.
func _build_band_mesh(radius: float, angle_span: float, length: float, arc_segments: int, length_segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(arc_segments):
		var a0: float = angle_span * i / arc_segments
		var a1: float = angle_span * (i + 1) / arc_segments
		for j in range(length_segments):
			var z0: float = length * j / length_segments
			var z1: float = length * (j + 1) / length_segments
			_add_quad(st,
				InteriorLayout.cylinder_point(radius, a0, z0),
				InteriorLayout.cylinder_point(radius, a1, z0),
				InteriorLayout.cylinder_point(radius, a0, z1),
				InteriorLayout.cylinder_point(radius, a1, z1))
	st.generate_normals()
	return st.commit()

# Flat ring in the z = 0 plane from inner_radius to outer_radius, facing -Z.
# inner_radius 0 gives a full disc.
func _build_annulus_mesh(inner_radius: float, outer_radius: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0: float = TAU * i / segments
		var a1: float = TAU * (i + 1) / segments
		var inner0 := InteriorLayout.cylinder_point(inner_radius, a0, 0.0)
		var inner1 := InteriorLayout.cylinder_point(inner_radius, a1, 0.0)
		var outer0 := InteriorLayout.cylinder_point(outer_radius, a0, 0.0)
		var outer1 := InteriorLayout.cylinder_point(outer_radius, a1, 0.0)
		if inner_radius > 0.0:
			_add_quad(st, inner0, outer0, inner1, outer1)
		else:
			_add_triangle(st, inner0, outer0, outer1)
	st.generate_normals()
	return st.commit()

# p00-p10 and p01-p11 are opposite edges. This winding is the one
# SurfaceTool.generate_normals turns into the facing direction documented on
# the two builders above (verified empirically).
func _add_quad(st: SurfaceTool, p00: Vector3, p10: Vector3, p01: Vector3, p11: Vector3) -> void:
	_add_triangle(st, p00, p10, p01)
	_add_triangle(st, p10, p11, p01)

func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
```

In `scripts/game_mode.gd`:
- in `_process`, change `_interior.set_undock_ready(_can_undock_now())` to `_interior.set_undock_ready(0, _can_undock_now())`;
- replace `_can_undock_now` with (Task 5 makes it the nearest dock):

```gdscript
func _can_undock_now() -> bool:
	var cruiser: CharacterBody3D = _interior.get_node("InternalCruiser")
	return DockingRules.can_dock(_interior.get_dock_position(0).distance_to(cruiser.position), cruiser.velocity.length())
```

- in `enter_interior`, replace the three lines from `# Bridge i joins section i (behind)...` to `_interior.ahead_section_index = ...` with:

```gdscript
	# The chain starts at the docked bridge and wraps round the ring.
	_interior.docked_bridge_index = bridge_index
	_interior.ring_sections = _station.num_sections
```

- [ ] **Step 4: Run the tests to verify they pass**

Run each:
`/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_interior_world.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED|interior|lights"`
`/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_interior_world_physics.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
`/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_internal_cruiser_physics.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
`/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_game_mode.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`

Expected: `ALL TESTS PASSED` for each; test_interior_world also prints `interior build: <n> ms` (under 3000) and `76 interior lights loaded, at most <n> within 25 km` (n about 54, at most 64). If the most-lights number is over 64, stop and ledger it: the spec's estimate is wrong and the fade distance needs to come down.

Then the full suite (command in Global Constraints). Expected: `exit 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/interior_world.gd scripts/game_mode.gd tests/test_interior_world.gd tests/test_interior_world_physics.gd tests/test_internal_cruiser_physics.gd tests/test_game_mode.gd
git commit -m "Build the interior as a chain of slots: open caps, a dock per bridge, fading lights

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Stream the chain around the craft and shift the origin

**Files:**
- Modify: `scripts/interior_world.gd`
- Create: `tests/test_interior_streaming.gd`

**Interfaces:**
- Consumes: Task 3's `_plan_window`, `_finish_plan`, `_dress_chunks`, `_free_unloading`, `_sections`, `_chain`, `SectionLoad`, `chain_z`, `get_chain_offset`, `is_section_ready`, `get_loaded_section_slots`.
- Produces on `interior_world.gd`: `const REBASE_DISTANCE := 10000.0`; `stream_step(focus_z: float, chunk_budget: int, free_budget: int) -> int` (chunks dressed); `rebase_around(craft: Node3D)`; `_process` streams and `_physics_process` rebases around the child named `InternalCruiser` (any `Node3D`).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_interior_streaming.gd`:

```gdscript
extends SceneTree

# The interior chain loading around the craft over real frames.

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const InternalCruiserScript = preload("res://scripts/internal_cruiser.gd")

const LENGTH := 20000.0
const BRIDGE_LENGTH := 1834.0
const PERIOD := LENGTH + BRIDGE_LENGTH

var _failures := 0

func _initialize():
	await process_frame
	_failures += _test_rebase_moves_chain_and_craft_together()
	_failures += _test_freeing_while_a_plan_is_generating_waits_for_it()
	_failures += await _test_a_step_dresses_at_most_16_chunks_nearest_first()
	_failures += await _test_hovering_at_the_load_edge_keeps_the_same_section()
	_failures += await _test_flying_along_the_chain_finds_each_section_ready()
	_failures += await _test_internal_cruiser_flies_through_a_bridge_into_the_next_section()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit()

func _make_world() -> Node3D:
	var world: Node3D = InteriorWorldScript.new()
	world.build()
	return world

func _test_rebase_moves_chain_and_craft_together() -> int:
	var world := _make_world()
	var craft := Node3D.new()
	craft.name = "InternalCruiser"
	world.add_child(craft)
	var result := 0
	craft.position = Vector3(5.0, 7.0, -9000.0)
	world.rebase_around(craft)
	if not is_zero_approx(world.get_chain_offset()) or not is_equal_approx(craft.position.z, -9000.0):
		print("FAIL _test_rebase_moves_chain_and_craft_together: shifted at 9 km (offset %f)" % world.get_chain_offset())
		result = 1
	craft.position = Vector3(5.0, 7.0, -15000.0)
	var dock_from_craft: Vector3 = world.get_dock_position(0) - craft.position
	world.rebase_around(craft)
	if not craft.position.is_equal_approx(Vector3(5.0, 7.0, 0.0)) or not is_equal_approx(world.get_chain_offset(), 15000.0) or not is_equal_approx(world.chain_z(craft.position), -15000.0):
		print("FAIL _test_rebase_moves_chain_and_craft_together: craft %s offset %f" % [craft.position, world.get_chain_offset()])
		result = 1
	if not (world.get_dock_position(0) - craft.position).is_equal_approx(dock_from_craft):
		print("FAIL _test_rebase_moves_chain_and_craft_together: the dock moved relative to the craft")
		result = 1
	world.free()
	return result

func _test_freeing_while_a_plan_is_generating_waits_for_it() -> int:
	var world := _make_world()
	world.stream_step(-0.5 * PERIOD, 16, 32)  # starts section 1's plan on a worker
	var state = world._sections.get(1)
	if state == null or state.task_id < 0:
		print("FAIL _test_freeing_while_a_plan_is_generating_waits_for_it: no plan in progress for section 1")
		world.free()
		return 1
	world.free()
	if state.task_id != -1 or state.plan == null:
		print("FAIL _test_freeing_while_a_plan_is_generating_waits_for_it: the world was freed without waiting for its worker")
		return 1
	return 0

func _test_a_step_dresses_at_most_16_chunks_nearest_first() -> int:
	var world := _make_world()
	root.add_child(world)
	var focus := -0.5 * PERIOD
	var dressed := 0
	for i in range(3000):
		dressed = world.stream_step(focus, 16, 32)
		if dressed > 0:
			break
		await process_frame
	var result := 0
	var section := world.get_node_or_null("Chain/Section_1")
	var chunks: Array = [] if section == null else section.find_children("Chunk_*", "StaticBody3D", false, false)
	if dressed != 16 or chunks.size() != 16:
		print("FAIL _test_a_step_dresses_at_most_16_chunks_nearest_first: one step dressed %d, section 1 has %d chunks" % [dressed, chunks.size()])
		result = 1
	else:
		# Section 1's row 19 is its +Z end, the one facing the craft.
		for chunk in chunks:
			if not String(chunk.name).ends_with("_19"):
				print("FAIL _test_a_step_dresses_at_most_16_chunks_nearest_first: %s dressed before the nearest row" % chunk.name)
				result = 1
				break
	world.free()
	return result

func _test_hovering_at_the_load_edge_keeps_the_same_section() -> int:
	var world := _make_world()
	root.add_child(world)
	# Section 1's centre is 1.25 periods from here: it loads just inside,
	# and must not unload just outside.
	var edge := -0.25 * PERIOD
	var seen := {}
	for i in range(200):
		world.stream_step(edge + (300.0 if i % 2 == 0 else -300.0), 16, 32)
		var section := world.get_node_or_null("Chain/Section_1")
		if section != null:
			seen[section.get_instance_id()] = true
		await process_frame
	var result := 0
	if seen.size() != 1:
		print("FAIL _test_hovering_at_the_load_edge_keeps_the_same_section: section 1 was built %d times" % seen.size())
		result = 1
	world.free()
	return result

func _test_flying_along_the_chain_finds_each_section_ready() -> int:
	# 50 m per frame along -Z for two sections; the world streams in _process
	# and rebases in _physics_process around its "InternalCruiser" child.
	var world := _make_world()
	var craft := Node3D.new()
	craft.name = "InternalCruiser"
	world.add_child(craft)
	root.add_child(world)
	var along := 0.0
	var worst_usec := 0
	var not_ready := []
	var frames := 0
	var last := Time.get_ticks_usec()
	while along > -2.2 * PERIOD:
		along -= 50.0
		craft.position.z = along + world.get_chain_offset()
		await process_frame
		var now := Time.get_ticks_usec()
		if frames > 2:
			worst_usec = maxi(worst_usec, now - last)
		last = now
		frames += 1
		var slot: int = floori(-along / PERIOD)
		if not world.is_section_ready(slot) and not not_ready.has(slot):
			not_ready.append(slot)
	for i in range(40):
		await process_frame
	print("  worst frame while streaming: %.1f ms" % (worst_usec / 1000.0))
	var result := 0
	if not not_ready.is_empty():
		print("FAIL _test_flying_along_the_chain_finds_each_section_ready: reached sections %s before they were ready" % [not_ready])
		result = 1
	if worst_usec > 50000:
		print("FAIL _test_flying_along_the_chain_finds_each_section_ready: a frame took %.1f ms" % (worst_usec / 1000.0))
		result = 1
	if world.get_loaded_section_slots() != [1, 2] or world.get_node_or_null("Chain/Section_-1") != null or world.get_node_or_null("Chain/Section_0") != null:
		print("FAIL _test_flying_along_the_chain_finds_each_section_ready: loaded %s, expected [1, 2] with -1 and 0 freed" % [world.get_loaded_section_slots()])
		result = 1
	if is_zero_approx(world.get_chain_offset()) or absf(craft.position.z) > 10050.0:
		print("FAIL _test_flying_along_the_chain_finds_each_section_ready: no origin shift (offset %f, craft z %f)" % [world.get_chain_offset(), craft.position.z])
		result = 1
	world.free()
	return result

func _test_internal_cruiser_flies_through_a_bridge_into_the_next_section() -> int:
	# On the axis, 2 km before section 0's -Z cap, heading -Z at 1 km/s:
	# through the cap's hole, bridge 1 and into section 1, touching nothing.
	var world := _make_world()
	var cruiser: CharacterBody3D = InternalCruiserScript.new()
	cruiser.name = "InternalCruiser"
	cruiser.linear_damping = 0.0
	cruiser.position = Vector3(0.0, 0.0, -PERIOD + BRIDGE_LENGTH * 0.5 + 2000.0)
	world.add_child(cruiser)
	root.add_child(world)
	for i in range(3000):
		if world.is_section_ready(1):
			break
		await process_frame
	if not world.is_section_ready(1):
		print("FAIL _test_internal_cruiser_flies_through_a_bridge_into_the_next_section: section 1 never loaded")
		world.free()
		return 1
	cruiser.velocity = Vector3(0.0, 0.0, -1000.0)
	for tick in range(360):
		await physics_frame
	var result := 0
	var end_z: float = world.chain_z(cruiser.position)
	if not cruiser.velocity.is_equal_approx(Vector3(0.0, 0.0, -1000.0)) or end_z > -(PERIOD + BRIDGE_LENGTH * 0.5):
		print("FAIL _test_internal_cruiser_flies_through_a_bridge_into_the_next_section: at chain z %.1f with velocity %s (section 1 starts at %.1f)" % [end_z, cruiser.velocity, -(PERIOD + BRIDGE_LENGTH * 0.5)])
		result = 1
	world.free()
	return result
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_interior_streaming.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -20`
Expected: `SCRIPT ERROR` lines naming `rebase_around` and `stream_step` (nonexistent function), plus `FAIL` lines.

- [ ] **Step 3: Implement streaming and the origin shift**

In `scripts/interior_world.gd`, add below `const ALL_AT_ONCE := 1 << 30`:

```gdscript
# Past this distance from the origin along Z, the chain and the craft move
# back together (Z only: the axis stays at x = y = 0).
const REBASE_DISTANCE := 10000.0
```

and add after `load_now`:

```gdscript
# One step of loading around chain position `focus_z` that never waits:
# unfinished plans are picked up on a later step. Returns chunks dressed.
func stream_step(focus_z: float, chunk_budget: int, free_budget: int) -> int:
	_plan_window(focus_z)
	for state: SectionLoad in _sections.values():
		if state.task_id >= 0 and WorkerThreadPool.is_task_completed(state.task_id):
			_finish_plan(state, focus_z)
	var dressed := _dress_chunks(focus_z, chunk_budget)
	_free_unloading(free_budget)
	return dressed

func rebase_around(craft: Node3D) -> void:
	if absf(craft.position.z) <= REBASE_DISTANCE:
		return
	var shift: float = craft.position.z
	_chain.position.z -= shift
	craft.position.z -= shift

func _process(_delta: float) -> void:
	var craft := get_node_or_null("InternalCruiser") as Node3D
	if craft != null and _chain != null:
		stream_step(chain_z(craft.position), CHUNKS_DRESSED_PER_FRAME, CHUNKS_FREED_PER_FRAME)

# Before the craft moves this tick (a parent runs before its children); the
# static bodies follow their moved parent.
func _physics_process(_delta: float) -> void:
	var craft := get_node_or_null("InternalCruiser") as Node3D
	if craft != null and _chain != null:
		rebase_around(craft)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_interior_streaming.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED|worst"`
Expected: `worst frame while streaming: <n> ms` (n below 50; about 13-20 expected) and `ALL TESTS PASSED`.

Then the full suite. Expected: `exit 0` (test_game_mode and test_internal_cruiser_physics now run with streaming and rebasing active).

- [ ] **Step 5: Commit**

```bash
git add scripts/interior_world.gd tests/test_interior_streaming.gd tests/test_interior_streaming.gd.uid
git commit -m "Stream the interior chain around the craft and shift the origin along the axis

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(The `.uid` file appears after the first run of the new test; if it is not there, run `--import` once and add it.)

---

### Task 5: Undock at the nearest bridge; free the outside world on exit

**Files:**
- Modify: `scripts/game_mode.gd`
- Test: `tests/test_game_mode.gd`

**Interfaces:**
- Consumes: Task 3's `nearest_dock_slot`, `get_dock_position(slot)`, `get_bridge_ring_index`, `set_undock_ready(slot, undock_ready)`; Task 4's rebase (active in these tests).
- Produces: `GameMode` undocks at `get_bridge_ring_index(nearest_dock_slot(cruiser.position))`; `docked_bridge` is updated to that bridge before the void-cruiser is placed; `GameMode` frees its detached nodes on `NOTIFICATION_PREDELETE`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_game_mode.gd`, add after `_failures += await _test_interior_sections_follow_the_docked_bridge()`:

```gdscript
	_failures += await _test_undock_from_another_bridge_exits_at_its_collar()
	_failures += await _test_outside_world_is_freed_if_the_scene_goes_while_inside()
```

and append:

```gdscript
func _test_undock_from_another_bridge_exits_at_its_collar() -> int:
	var result := 0
	var last: int = _station.num_sections - 1
	# [dock slot, station bridge]: slot 1 is 21.8 km out (the origin shifts),
	# slot -1 of bridge 0 is the last bridge (the ring closes).
	for case in [[1, 1], [-1, last]]:
		_game_mode.enter_interior(0)
		var interior: Node3D = _scene.get_node("InteriorWorld")
		var cruiser: CharacterBody3D = interior.get_node("InternalCruiser")
		cruiser.set_physics_process(false)
		cruiser.position = interior.get_dock_position(case[0]) + Vector3(0.0, 24.0, 0.0)
		await _frames(3)
		var lit: Label3D = interior.get_node("Chain/Bridge_%d/Dock/Sign" % case[0])
		var docked_sign: Label3D = interior.get_node("Chain/Bridge_0/Dock/Sign")
		if not lit.modulate.is_equal_approx(InteriorWorldScript.SIGN_READY_COLOR) or not docked_sign.modulate.is_equal_approx(InteriorWorldScript.SIGN_IDLE_COLOR):
			print("FAIL _test_undock_from_another_bridge_exits_at_its_collar: at dock %d the lit sign is wrong" % case[0])
			result = 1
		_press_dock()
		await _wait_for_transition()
		if _game_mode.is_inside():
			print("FAIL _test_undock_from_another_bridge_exits_at_its_collar: could not undock at dock %d" % case[0])
			_game_mode.exit_interior()
			result = 1
			continue
		var port: Node3D = _station.get_docking_port(case[1])
		var distance: float = _void_cruiser.global_position.distance_to(port.global_position)
		if absf(distance - 60.0) > 0.5:
			print("FAIL _test_undock_from_another_bridge_exits_at_its_collar: dock %d put the ship %.1f m from bridge %d's port (expected 60)" % [case[0], distance, case[1]])
			result = 1
	return result

func _test_outside_world_is_freed_if_the_scene_goes_while_inside() -> int:
	# Quitting while inside: the outside world is out of the tree and only
	# GameMode holds it.
	var scene: Node = load("res://scenes/torus1_system.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var cruiser: Node = scene.get_node("VoidCruiser")
	var station: Node = scene.get_node("PlanetSystem")
	scene.get_node("GameMode").enter_interior(0)
	await process_frame
	scene.free()
	if is_instance_valid(cruiser) or is_instance_valid(station):
		print("FAIL _test_outside_world_is_freed_if_the_scene_goes_while_inside: the detached outside world outlived the scene")
		if is_instance_valid(cruiser):
			cruiser.free()
		if is_instance_valid(station):
			station.free()
		return 1
	return 0
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_game_mode.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
Expected: `FAIL _test_undock_from_another_bridge_exits_at_its_collar` (sign wrong and/or could not undock at dock 1 and -1) and `FAIL _test_outside_world_is_freed_if_the_scene_goes_while_inside`.

- [ ] **Step 3: Implement**

In `scripts/game_mode.gd`:
- replace the `elif _interior:` branch of `_process` with:

```gdscript
	elif _interior:
		var cruiser := _interior.get_node("InternalCruiser") as Node3D
		_interior.set_undock_ready(_interior.nearest_dock_slot(cruiser.position), _can_undock_now())
```

- replace `_can_undock_now` with:

```gdscript
# Every bridge inside has a dock; the one nearest the craft counts.
func _can_undock_now() -> bool:
	var cruiser: CharacterBody3D = _interior.get_node("InternalCruiser")
	var dock: Vector3 = _interior.get_dock_position(_interior.nearest_dock_slot(cruiser.position))
	return DockingRules.can_dock(dock.distance_to(cruiser.position), cruiser.velocity.length())
```

- in `exit_interior`, insert at the top, before `var parent := get_parent()`:

```gdscript
	# Out through the collar of the bridge whose dock is nearest.
	var cruiser := _interior.get_node_or_null("InternalCruiser") as Node3D
	if cruiser != null:
		docked_bridge = _interior.get_bridge_ring_index(_interior.nearest_dock_slot(cruiser.position))
```

- add after `_ready`:

```gdscript
func _notification(what: int) -> void:
	# Freed while inside (the game quits): the outside world is out of the
	# tree and nothing else would ever free it.
	if what == NOTIFICATION_PREDELETE:
		for entry in _detached:
			var node: Node = entry[0]
			if is_instance_valid(node) and not node.is_inside_tree():
				node.free()
		_detached.clear()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_game_mode.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
Expected: `ALL TESTS PASSED` only.

Then the full suite. Expected: `exit 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/game_mode.gd tests/test_game_mode.gd
git commit -m "Undock at the nearest bridge's collar; free the outside world if freed inside

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Live check and an offscreen look through a bridge

**Files:**
- Create (scratchpad only, not committed): `/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_chain.gd`

- [ ] **Step 1: Headless live run**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"`
Expected: no output.

- [ ] **Step 2: Offscreen render**

Create the scratchpad script:

```gdscript
extends SceneTree

# Offscreen look along the chain: from section 0 at the open cap of bridge 1,
# and from inside bridge 1 into section 1.
const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const SCRATCH := "/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/"

func _initialize():
	root.size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.27, 0.32)
	e.ambient_light_energy = 0.25
	env.environment = e
	root.add_child(env)
	var world: Node3D = InteriorWorldScript.new()
	world.build()
	world.load_now(-world.period())
	root.add_child(world)
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 90.0
	cam.near = 0.2
	cam.far = 60000.0
	root.add_child(cam)
	cam.current = true
	var p: float = world.period()
	var views := {
		"chain_cap": Transform3D(Basis(), Vector3(0.0, -800.0, -p + 4000.0)),
		"chain_bridge": Transform3D(Basis(), Vector3(0.0, -300.0, -p + 600.0)),
	}
	for view_name in views:
		cam.global_transform = views[view_name]
		for i in range(6):
			await process_frame
		root.get_texture().get_image().save_png(SCRATCH + "%s.png" % view_name)
		print("saved ", view_name)
	quit()
```

Run: `xvfb-run -a /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --path . --script /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_chain.gd 2>&1 | grep -E "saved|ERROR"`
Expected: `saved chain_cap` and `saved chain_bridge`.

- [ ] **Step 3: Look at both images**

Open `chain_cap.png` and `chain_bridge.png` with the Read tool. Expected: in `chain_cap` the cap wall with a round hole, the lit tube beyond and a lit section past it; in `chain_bridge` the tube walls and section 1's lit ground through the far hole. Black patches of ground within ~20 km mean lights are being dropped: ledger it and lower `LIGHT_FADE_BEGIN` (spec, "Rischi noti").

- [ ] **Step 4: Full suite**

Run the full suite (Global Constraints). Expected: `exit 0`. No commit in this task unless Step 3 needed a fix; a fix gets its own failing test first (for a light problem: tighten `_test_at_most_64_lights_within_25_km_along_the_chain`).
