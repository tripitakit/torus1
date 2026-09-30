# Interior Relief (Hills and Small Mountains) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the interior sections rolling hills on the fields and a rare RELIEF zone with small mountains, keeping towns, city, lakes and buildings flat at level 0.

**Architecture:** `section_plan.gd` gains a height grid (5 points per lot each way, 240 × 401 floats) with bilinear lookup and slope. `section_generator.gd` (worker thread) marks the 5% highest-noise field lots as `Zone.RELIEF`, keeps roads off them, and fills the grid from two noises blended to zero near flat zones and the end caps. `terrain_dressing.gd` keeps today's flat path for chunks with no height; chunks with height get patches split on every grid line and road-band edge (watertight), vertices lifted toward the axis, slope normals, grass/rock colours on RELIEF lots, and their own trimesh collision.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer, `FastNoiseLite`. Headless `extends SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-09-30-interior-relief-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64` (double precision). Never the `godot` on PATH. One test file: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/<file>.gd`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/88be7e76-cf17-4eba-b962-d57871ddb62e/scratchpad/suite.sh`. If the script is gone, recreate it: loop over `tests/*.gd`, run each with `timeout 120`, grep for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the only match is `ALL TESTS PASSED`.
- **Reading RED:** a missing method prints `SCRIPT ERROR: ... Nonexistent function` and the file may still end with `ALL TESTS PASSED`; a missing constant or preload prints `Parse Error`. RED is those lines or `FAIL` lines, never the summary alone. The user wants to see RED really happen.
- **Fresh worktree:** run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import` once before the first test run.
- **Packed arrays are values:** build packed arrays in locals and assign them whole (`plan.heights = heights`). Inside a class, mutate its own members directly.
- GDScript: explicit types where builtins return Variant; no locals named `basis`, `transform`, `position`, `sign`, `owner`; prefix unused parameters with `_`; `@warning_ignore("integer_division")` on integer division — otherwise `WARNING` lines appear.
- Unrolled coordinates: `x` = arc length around (angle = `x / radius`), `z` = distance from the section's low-`z` end. Chunk `(a, b)` holds lots `3a .. 3a+2` around and `4b .. 4b+3` along; in chunk-local coordinates its `x` starts at 0 (section `x` = `a * 3 * lot_width` + local `x`), its `z` starts at 0 (section `z` = `b * 4 * lot_length` + local `z`).
- Mesh winding (facing the axis), quad corners `p00=(x0,z0)`, `p10=(x1,z0)`, `p01=(x0,z1)`, `p11=(x1,z1)`: triangles `(p00, p10, p01)` and `(p10, p11, p01)`.
- Numbers from the spec, verbatim: `RELIEF_POINTS_PER_LOT = 5`; grid 240 columns (wrapping) × 401 rows; `RELIEF_SHARE = 0.05` of all lots (192 of 3840); `HILL_HEIGHT = 100`; `MOUNTAIN_HEIGHT = 350`; `RELIEF_BLEND = 250`; mountain noise ~1500 m, 4 octaves, seed `hash([index, "relief"])`; hill noise ~800 m, seed `hash([index, "hills"])`; grass `Color(0.36, 0.5, 0.26)`, rock `Color(0.46, 0.44, 0.41)`; rock share `max(smoothstep(0.5, 0.9, slope), smoothstep(180, 300, h))`.
- Flat means **exactly** flat: towns, city, lakes and both section ends at height 0 (tests allow 0.001 m for float rounding).
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `.claude/worktrees/`. Add the Godot-generated `.uid` file of any new script or test.
- The interior renders no shadows; relief reads only through normals. Do not add shadows.

## Review Focus

1. **Cracks between mosaic patches on a slope** — a 6 m road band next to a 250 m field must share every vertex on their common edge, or thin black slits show against the background. Test: `_test_relief_chunk_has_no_cracks` (Task 4).
2. **Hills poking into towns, lakes or buildings** — a lake that tilts, or a building floating/buried at a lot edge. Tests: `_test_flat_zones_and_ends_stay_at_zero`, `_test_buildings_stand_at_level_zero` (Task 3).
3. **The way round closes** — column 240 is column 0; noise sampled on the cylinder in 3D. Test: `_test_heights_join_where_the_way_round_closes` (Task 3), `_test_height_at_wraps_and_interpolates` (Task 1).
4. **Flying into a hillside** — the craft must stop on the drawn surface, not pass through it or bounce off air. Tests: `_test_relief_chunk_owns_a_collision_matching_its_mesh` (Task 5), in-tree `_test_hull_pushed_into_a_hillside_stops_on_it` (Task 6).
5. **Docking and streaming get slower** — plan generation grows by the height grid, dressing by the denser mesh and trimesh. Tests: `_test_building_at_docking_takes_under_three_seconds`, `_test_flying_along_the_chain_finds_each_section_ready` (Task 6), with measured numbers written in the task log.

---

### Task 1: Height grid in the section plan

**Files:**
- Modify: `scripts/section_plan.gd`
- Test: `tests/test_section_plan.gd` (new) and its `.uid`

**Interfaces:**
- Produces (on `section_plan.gd`):
  - `enum Zone { FIELD, TOWN, CITY, WATER, RELIEF }` (RELIEF appended last)
  - `const RELIEF_POINTS_PER_LOT := 5`, `const RELIEF_COLUMNS := LOTS_AROUND * RELIEF_POINTS_PER_LOT` (240), `const RELIEF_ROWS := LOTS_ALONG * RELIEF_POINTS_PER_LOT + 1` (401)
  - `var heights := PackedFloat32Array()` (index `row * RELIEF_COLUMNS + column`; empty means all zero)
  - `var relief_threshold := 0.0`, `var relief_peak := 0.0`
  - `func height_step() -> Vector2` — (lot_width / 5, lot_length / 5)
  - `func grid_height(column: int, row: int) -> float` — column wraps, row clamps, 0 when `heights` is empty
  - `func height_at(x: float, z: float) -> float` — bilinear
  - `func slope_at(x: float, z: float) -> Vector2` — (dh/dx, dh/dz), central differences one grid step each way
  - `func chunk_has_relief(chunk_around: int, chunk_along: int) -> bool`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_section_plan.gd`:

```gdscript
extends SceneTree

# The section plan's height grid: lookup, interpolation, slope, per-chunk flag.

const SectionPlan = preload("res://scripts/section_plan.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0

func _init():
	var failures := 0
	failures += _test_grid_size_and_step()
	failures += _test_empty_heights_read_as_zero()
	failures += _test_height_at_wraps_and_interpolates()
	failures += _test_slope_of_a_ramp()
	failures += _test_chunk_has_relief_looks_at_its_own_grid_points()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _plan_with(fill: Callable):
	var plan = SectionPlan.new()
	plan.radius = RADIUS
	plan.length = LENGTH
	plan.lot_width = TAU * RADIUS / SectionPlan.LOTS_AROUND
	plan.lot_length = LENGTH / SectionPlan.LOTS_ALONG
	var heights := PackedFloat32Array()
	heights.resize(SectionPlan.RELIEF_COLUMNS * SectionPlan.RELIEF_ROWS)
	for row in range(SectionPlan.RELIEF_ROWS):
		for column in range(SectionPlan.RELIEF_COLUMNS):
			heights[row * SectionPlan.RELIEF_COLUMNS + column] = fill.call(column, row)
	plan.heights = heights
	return plan

func _test_grid_size_and_step() -> int:
	var plan = _plan_with(func(_c: int, _r: int) -> float: return 0.0)
	var step: Vector2 = plan.height_step()
	if SectionPlan.RELIEF_COLUMNS != 240 or SectionPlan.RELIEF_ROWS != 401 or not is_equal_approx(step.x * 240.0, TAU * RADIUS) or not is_equal_approx(step.y, 50.0):
		print("FAIL _test_grid_size_and_step: %d x %d, step %s" % [SectionPlan.RELIEF_COLUMNS, SectionPlan.RELIEF_ROWS, step])
		return 1
	if SectionPlan.Zone.RELIEF != 4:
		print("FAIL _test_grid_size_and_step: RELIEF is %d, expected 4 (appended)" % SectionPlan.Zone.RELIEF)
		return 1
	return 0

func _test_empty_heights_read_as_zero() -> int:
	var plan = SectionPlan.new()
	plan.radius = RADIUS
	plan.length = LENGTH
	plan.lot_width = TAU * RADIUS / SectionPlan.LOTS_AROUND
	plan.lot_length = LENGTH / SectionPlan.LOTS_ALONG
	if plan.height_at(1234.0, 5678.0) != 0.0 or plan.slope_at(1234.0, 5678.0) != Vector2.ZERO or plan.chunk_has_relief(3, 7):
		print("FAIL _test_empty_heights_read_as_zero: a plan with no heights is not flat")
		return 1
	return 0

func _test_height_at_wraps_and_interpolates() -> int:
	# Distinct value per grid point: column + 1000 * row.
	var plan = _plan_with(func(c: int, r: int) -> float: return float(c + 1000 * r))
	var step: Vector2 = plan.height_step()
	var result := 0
	if not is_equal_approx(plan.height_at(7.0 * step.x, 123.0 * step.y), plan.grid_height(7, 123)):
		print("FAIL _test_height_at_wraps_and_interpolates: on a grid point")
		result = 1
	var mid: float = plan.height_at(7.5 * step.x, 123.0 * step.y)
	if not is_equal_approx(mid, 0.5 * (plan.grid_height(7, 123) + plan.grid_height(8, 123))):
		print("FAIL _test_height_at_wraps_and_interpolates: halfway got %f" % mid)
		result = 1
	# Column 240 is column 0: x = circumference reads like x = 0.
	if plan.grid_height(240, 5) != plan.grid_height(0, 5) or not is_equal_approx(plan.height_at(plan.circumference(), 5.0 * step.y), plan.height_at(0.0, 5.0 * step.y)):
		print("FAIL _test_height_at_wraps_and_interpolates: the way round does not close")
		result = 1
	# Between the last column and column 0: halfway between their values.
	var seam: float = plan.height_at(239.5 * step.x, 5.0 * step.y)
	if not is_equal_approx(seam, 0.5 * (plan.grid_height(239, 5) + plan.grid_height(0, 5))):
		print("FAIL _test_height_at_wraps_and_interpolates: across the seam got %f" % seam)
		result = 1
	# Rows clamp at both ends.
	if plan.grid_height(3, -1) != plan.grid_height(3, 0) or plan.grid_height(3, 401) != plan.grid_height(3, 400):
		print("FAIL _test_height_at_wraps_and_interpolates: rows do not clamp")
		result = 1
	return result

func _test_slope_of_a_ramp() -> int:
	# h = 2 m per row: dh/dz = 2 / 50, dh/dx = 0.
	var plan = _plan_with(func(_c: int, r: int) -> float: return 2.0 * r)
	var step: Vector2 = plan.height_step()
	var slope: Vector2 = plan.slope_at(100.0 * step.x, 200.0 * step.y)
	if not is_equal_approx(slope.y, 2.0 / step.y) or absf(slope.x) > 1e-9:
		print("FAIL _test_slope_of_a_ramp: along a z ramp got %s" % slope)
		return 1
	# h = 1 m per column (away from the seam): dh/dx = 1 / step.x.
	plan = _plan_with(func(c: int, _r: int) -> float: return float(c))
	slope = plan.slope_at(100.0 * step.x, 200.0 * step.y)
	if not is_equal_approx(slope.x, 1.0 / step.x) or absf(slope.y) > 1e-9:
		print("FAIL _test_slope_of_a_ramp: along an x ramp got %s" % slope)
		return 1
	return 0

func _test_chunk_has_relief_looks_at_its_own_grid_points() -> int:
	# One raised point: column 20, row 45 is inside chunk (1, 2) (columns
	# 15..30, rows 40..60). Chunk (0, 0) stays flat.
	var plan = _plan_with(func(c: int, r: int) -> float: return 5.0 if c == 20 and r == 45 else 0.0)
	if not plan.chunk_has_relief(1, 2) or plan.chunk_has_relief(0, 0):
		print("FAIL _test_chunk_has_relief_looks_at_its_own_grid_points: wrong flag")
		return 1
	# A point on a chunk border belongs to both chunks it touches.
	plan = _plan_with(func(c: int, r: int) -> float: return 5.0 if c == 30 and r == 45 else 0.0)
	if not plan.chunk_has_relief(1, 2) or not plan.chunk_has_relief(2, 2):
		print("FAIL _test_chunk_has_relief_looks_at_its_own_grid_points: border point not shared")
		return 1
	return 0
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_section_plan.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED"`
Expected: `Parse Error` (no `RELIEF_COLUMNS`).

- [ ] **Step 3: Implement**

In `scripts/section_plan.gd`, change the enum and add constants after `STREET_WIDTH`:

```gdscript
enum Zone { FIELD, TOWN, CITY, WATER, RELIEF }
```

```gdscript
# Height grid: RELIEF_POINTS_PER_LOT points per lot each way, so grid lines
# fall on every lot and chunk edge. Columns wrap (column RELIEF_COLUMNS is
# column 0); rows run from z = 0 to z = length inclusive.
const RELIEF_POINTS_PER_LOT := 5
const RELIEF_COLUMNS := LOTS_AROUND * RELIEF_POINTS_PER_LOT
const RELIEF_ROWS := LOTS_ALONG * RELIEF_POINTS_PER_LOT + 1
```

Add members after `building_lit`:

```gdscript
# Ground height toward the axis in metres, per grid point, index
# row * RELIEF_COLUMNS + column. Empty: all flat.
var heights := PackedFloat32Array()
# Mountain-noise level above which lot centres became RELIEF, and the
# highest lot-centre value (see section_generator.gd).
var relief_threshold := 0.0
var relief_peak := 0.0
```

Add functions after `surface_distance`:

```gdscript
func height_step() -> Vector2:
	return Vector2(lot_width, lot_length) / RELIEF_POINTS_PER_LOT

func grid_height(column: int, row: int) -> float:
	if heights.is_empty():
		return 0.0
	return heights[clampi(row, 0, RELIEF_ROWS - 1) * RELIEF_COLUMNS + posmod(column, RELIEF_COLUMNS)]

# Bilinear between the four grid points around (x, z); x wraps around.
func height_at(x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	var step := height_step()
	var gx: float = fposmod(x, circumference()) / step.x
	var gz: float = clampf(z / step.y, 0.0, RELIEF_ROWS - 1)
	var column := floori(gx)
	var row := mini(floori(gz), RELIEF_ROWS - 2)
	var fx: float = gx - column
	var fz: float = gz - row
	var low: float = lerpf(grid_height(column, row), grid_height(column + 1, row), fx)
	var high: float = lerpf(grid_height(column, row + 1), grid_height(column + 1, row + 1), fx)
	return lerpf(low, high, fz)

# (dh/dx, dh/dz) by central differences one grid step each way.
func slope_at(x: float, z: float) -> Vector2:
	if heights.is_empty():
		return Vector2.ZERO
	var step := height_step()
	return Vector2(
		(height_at(x + step.x, z) - height_at(x - step.x, z)) / (2.0 * step.x),
		(height_at(x, z + step.y) - height_at(x, z - step.y)) / (2.0 * step.y))

# True when any grid point of the chunk, borders included, is above 0.
func chunk_has_relief(chunk_around: int, chunk_along: int) -> bool:
	if heights.is_empty():
		return false
	var columns := CHUNK_LOTS_AROUND * RELIEF_POINTS_PER_LOT
	var rows := CHUNK_LOTS_ALONG * RELIEF_POINTS_PER_LOT
	for row in range(chunk_along * rows, chunk_along * rows + rows + 1):
		for column in range(chunk_around * columns, chunk_around * columns + columns + 1):
			if grid_height(column, row) > 0.0:
				return true
	return false
```

Note: `slope_at` near `z = 0` reads a clamped row, which is fine (the ends are flat).

- [ ] **Step 4: Run the test to verify it passes**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_section_plan.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|WARNING|PASSED"`
Expected: `ALL TESTS PASSED` only.

Also run `tests/test_section_generator.gd` and `tests/test_terrain_dressing.gd`: both still `ALL TESTS PASSED` (nothing uses RELIEF yet).

- [ ] **Step 5: Commit**

```bash
git add scripts/section_plan.gd tests/test_section_plan.gd tests/test_section_plan.gd.uid
git commit -m "Add a height grid to the section plan

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(If the `.uid` does not exist yet, run the Godot import command from Global Constraints once to create it.)

---

### Task 2: RELIEF zone and no roads beside it

**Files:**
- Modify: `scripts/section_generator.gd`
- Test: `tests/test_section_generator.gd`

**Interfaces:**
- Consumes: `SectionPlan.Zone.RELIEF`, `plan.relief_threshold`, `plan.relief_peak` (Task 1).
- Produces (on `section_generator.gd`, static):
  - `const RELIEF_SHARE := 0.05`, `const MOUNTAIN_FEATURE_SIZE := 1500.0`
  - `static func mountain_noise(section_index: int) -> FastNoiseLite`
  - `static func surface_point(plan, x: float, z: float) -> Vector3` — 3D point on the cylinder for noise sampling
  - `generate()` now sets RELIEF lots, `relief_threshold`, `relief_peak`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_section_generator.gd`, add to `_init()` after `_test_road_kinds()`:

```gdscript
	failures += _test_relief_lots_are_the_highest_five_percent_of_fields()
	failures += _test_no_road_touches_relief()
```

Replace `_expected_road` with:

```gdscript
func _expected_road(zone_a: int, zone_b: int, on_chunk_border: bool) -> int:
	for zone in [zone_a, zone_b]:
		if zone == SectionPlan.Zone.WATER or zone == SectionPlan.Zone.RELIEF:
			return SectionPlan.Road.NONE
	if on_chunk_border:
		return SectionPlan.Road.MAIN
	if _is_built(zone_a) or _is_built(zone_b):
		return SectionPlan.Road.STREET
	return SectionPlan.Road.NONE
```

Add the tests:

```gdscript
func _test_relief_lots_are_the_highest_five_percent_of_fields() -> int:
	# 5% of all 3840 lots, taken from fields only: every RELIEF lot's centre
	# is at or above the threshold, every field's below it.
	var noise: FastNoiseLite = SectionGenerator.mountain_noise(_plan.section_index)
	var relief := 0
	var result := 0
	for along in range(80):
		for around in range(48):
			var zone: int = _plan.zone_at(around, along)
			var center: Vector2 = _plan.lot_center(around, along)
			var value: float = noise.get_noise_3dv(SectionGenerator.surface_point(_plan, center.x, center.y))
			if zone == SectionPlan.Zone.RELIEF:
				relief += 1
				if value < _plan.relief_threshold or _plan.surface_distance(center, _plan.city_center) <= SectionGenerator.CITY_RADIUS:
					print("FAIL _test_relief_lots_are_the_highest_five_percent_of_fields: RELIEF lot (%d, %d) below the threshold or in the city" % [around, along])
					result = 1
			elif zone == SectionPlan.Zone.FIELD and value >= _plan.relief_threshold:
				print("FAIL _test_relief_lots_are_the_highest_five_percent_of_fields: field lot (%d, %d) above the threshold" % [around, along])
				result = 1
	if relief != 192:
		print("FAIL _test_relief_lots_are_the_highest_five_percent_of_fields: %d RELIEF lots, expected 192" % relief)
		result = 1
	if _plan.relief_peak < _plan.relief_threshold:
		print("FAIL _test_relief_lots_are_the_highest_five_percent_of_fields: peak %f below threshold %f" % [_plan.relief_peak, _plan.relief_threshold])
		result = 1
	return result

func _test_no_road_touches_relief() -> int:
	for along in range(80):
		for around in range(48):
			if _plan.zone_at(around, along) != SectionPlan.Zone.RELIEF:
				continue
			if _plan.road_on_west(around, along) + _plan.road_on_east(around, along) + _plan.road_on_south(around, along) + _plan.road_on_north(around, along) != 0:
				print("FAIL _test_no_road_touches_relief: RELIEF lot (%d, %d) has a road on an edge" % [around, along])
				return 1
	return 0
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_section_generator.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED"`
Expected: `SCRIPT ERROR` on `mountain_noise` (nonexistent function).

- [ ] **Step 3: Implement**

In `scripts/section_generator.gd`, add constants after `TOWN_SHARE`:

```gdscript
# The field lots with the highest mountain noise become RELIEF: this share of
# all lots (see _with_relief).
const RELIEF_SHARE := 0.05
const MOUNTAIN_FEATURE_SIZE := 1500.0
```

In `generate()`, after `plan.zones = _with_city(plan, plan.zones)`:

```gdscript
	plan.zones = _with_relief(plan, plan.zones)
```

Add after `_with_city`:

```gdscript
static func mountain_noise(section_index: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = hash([section_index, "relief"])
	noise.frequency = 1.0 / MOUNTAIN_FEATURE_SIZE
	noise.fractal_octaves = 4
	return noise

# A point of the unrolled surface on the cylinder in 3D, where the noises are
# sampled: the way round closes with no seam.
static func surface_point(plan, x: float, z: float) -> Vector3:
	var angle: float = x / plan.radius
	return Vector3(cos(angle) * plan.radius, sin(angle) * plan.radius, z)

# The field lots with the highest mountain noise at their centre, RELIEF_SHARE
# of all lots, become RELIEF. Keeps the threshold and the highest centre value
# for the heights.
static func _with_relief(plan, zones: PackedByteArray) -> PackedByteArray:
	var noise := mountain_noise(plan.section_index)
	var values := PackedFloat64Array()
	var field_values := PackedFloat64Array()
	var peak := -INF
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var center: Vector2 = plan.lot_center(around, along)
			var value: float = noise.get_noise_3dv(surface_point(plan, center.x, center.y))
			values.append(value)
			peak = maxf(peak, value)
			if zones[plan.lot_index(around, along)] == SectionPlanScript.Zone.FIELD:
				field_values.append(value)
	field_values.sort()
	var count: int = mini(int(values.size() * RELIEF_SHARE), field_values.size())
	var threshold: float = field_values[field_values.size() - count]
	for i in range(values.size()):
		if zones[i] == SectionPlanScript.Zone.FIELD and values[i] >= threshold:
			zones[i] = SectionPlanScript.Zone.RELIEF
	plan.relief_threshold = threshold
	plan.relief_peak = peak
	return zones
```

Note: `values` is indexed like `zones` (`along * LOTS_AROUND + around`), because the loops run in the same order as `lot_index`.

Replace `_edge_road`'s first check:

```gdscript
# No road next to a lake or a RELIEF lot; a main road on every chunk border; a
# street next to a town or the city; nothing between two fields.
static func _edge_road(zone_a: int, zone_b: int, on_chunk_border: bool) -> int:
	for zone in [zone_a, zone_b]:
		if zone == SectionPlanScript.Zone.WATER or zone == SectionPlanScript.Zone.RELIEF:
			return SectionPlanScript.Road.NONE
```

(keep the rest of the function as it is).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_section_generator.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|WARNING|PASSED"`
Expected: `ALL TESTS PASSED` only. Also `tests/test_terrain_dressing.gd` stays `ALL TESTS PASSED` (until Task 4 a RELIEF lot falls into the paved branch with the city ground colour and no roads; Task 4 gives it its own colours).

- [ ] **Step 5: Commit**

```bash
git add scripts/section_generator.gd tests/test_section_generator.gd
git commit -m "Mark the highest-noise field lots as RELIEF, with no roads beside them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Heights in the generator

**Files:**
- Modify: `scripts/section_generator.gd`
- Test: `tests/test_section_generator.gd`

**Interfaces:**
- Consumes: Task 1 plan API, Task 2 `mountain_noise`, `surface_point`, `relief_threshold`, `relief_peak`.
- Produces: `generate()` fills `plan.heights`; constants `HILL_HEIGHT := 100.0`, `MOUNTAIN_HEIGHT := 350.0`, `RELIEF_BLEND := 250.0`, `HILL_FEATURE_SIZE := 800.0`.

- [ ] **Step 1: Write the failing tests**

Add to `_init()` in `tests/test_section_generator.gd`, after `_test_no_road_touches_relief()`:

```gdscript
	failures += _test_same_index_same_heights()
	failures += _test_flat_zones_and_ends_stay_at_zero()
	failures += _test_heights_in_range_and_mountains_only_above_the_threshold()
	failures += _test_heights_join_where_the_way_round_closes()
	failures += _test_buildings_stand_at_level_zero()
	failures += _test_some_chunks_flat_some_raised()
```

Add the tests:

```gdscript
const FLAT_ZONES := [SectionPlan.Zone.TOWN, SectionPlan.Zone.CITY, SectionPlan.Zone.WATER]

func _test_same_index_same_heights() -> int:
	var again = SectionGenerator.generate(42, RADIUS, LENGTH)
	var other = SectionGenerator.generate(43, RADIUS, LENGTH)
	if _plan.heights.size() != 240 * 401 or again.heights != _plan.heights or other.heights == _plan.heights:
		print("FAIL _test_same_index_same_heights: %d heights, same index equal %s, other index differs %s" % [_plan.heights.size(), again.heights == _plan.heights, other.heights != _plan.heights])
		return 1
	return 0

func _test_flat_zones_and_ends_stay_at_zero() -> int:
	# Every grid point inside or on the edge of a town, city or lake lot, and
	# both end rows.
	for along in range(80):
		for around in range(48):
			if not (_plan.zone_at(around, along) in FLAT_ZONES):
				continue
			for row in range(along * 5, along * 5 + 6):
				for column in range(around * 5, around * 5 + 6):
					if absf(_plan.grid_height(column, row)) > 0.001:
						print("FAIL _test_flat_zones_and_ends_stay_at_zero: lot (%d, %d) point (%d, %d) at %f m" % [around, along, column, row, _plan.grid_height(column, row)])
						return 1
	for column in range(240):
		if absf(_plan.grid_height(column, 0)) > 0.001 or absf(_plan.grid_height(column, 400)) > 0.001:
			print("FAIL _test_flat_zones_and_ends_stay_at_zero: end row not flat at column %d" % column)
			return 1
	return 0

func _test_heights_in_range_and_mountains_only_above_the_threshold() -> int:
	var noise: FastNoiseLite = SectionGenerator.mountain_noise(_plan.section_index)
	var step: Vector2 = _plan.height_step()
	var highest := 0.0
	for row in range(401):
		for column in range(240):
			var h: float = _plan.grid_height(column, row)
			highest = maxf(highest, h)
			if h < 0.0 or h > SectionGenerator.MOUNTAIN_HEIGHT + 0.001:
				print("FAIL _test_heights_in_range_and_mountains_only_above_the_threshold: %f m at (%d, %d)" % [h, column, row])
				return 1
			if h > SectionGenerator.HILL_HEIGHT + 0.001:
				var value: float = noise.get_noise_3dv(SectionGenerator.surface_point(_plan, column * step.x, row * step.y))
				if value <= _plan.relief_threshold:
					print("FAIL _test_heights_in_range_and_mountains_only_above_the_threshold: %f m at (%d, %d) with mountain noise below the threshold" % [h, column, row])
					return 1
	if highest < 200.0:
		print("FAIL _test_heights_in_range_and_mountains_only_above_the_threshold: highest point %f m, expected a mountain over 200 m" % highest)
		return 1
	print("  highest point: %.0f m" % highest)
	return 0

func _test_heights_join_where_the_way_round_closes() -> int:
	for k in range(40):
		var z: float = 250.0 + k * 490.0
		if not is_equal_approx(_plan.height_at(0.0, z), _plan.height_at(_plan.circumference(), z)) or absf(_plan.height_at(-1.0, z) - _plan.height_at(_plan.circumference() - 1.0, z)) > 1e-6:
			print("FAIL _test_heights_join_where_the_way_round_closes: at z %f" % z)
			return 1
	return 0

func _test_buildings_stand_at_level_zero() -> int:
	for b in range(_plan.building_count()):
		var size: Vector3 = _plan.building_size[b]
		for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
			var x: float = _plan.building_x[b] + corner.x * size.x
			var z: float = _plan.building_z[b] + corner.y * size.z
			if absf(_plan.height_at(x, z)) > 0.001:
				print("FAIL _test_buildings_stand_at_level_zero: building %d corner at %f m" % [b, _plan.height_at(x, z)])
				return 1
	return 0

func _test_some_chunks_flat_some_raised() -> int:
	var raised := 0
	for along in range(20):
		for around in range(16):
			if _plan.chunk_has_relief(around, along):
				raised += 1
	print("  chunks with relief: %d of 320" % raised)
	if raised == 0:
		print("FAIL _test_some_chunks_flat_some_raised: no chunk has relief")
		return 1
	return 0
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_section_generator.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED"`
Expected: `Parse Error` or `SCRIPT ERROR` on `MOUNTAIN_HEIGHT`, and/or `FAIL _test_same_index_same_heights: 0 heights`.

- [ ] **Step 3: Implement**

In `scripts/section_generator.gd`, add after `MOUNTAIN_FEATURE_SIZE`:

```gdscript
# Hills roll up to HILL_HEIGHT everywhere on open land; mountains add up to
# MOUNTAIN_HEIGHT in total where the mountain noise passes the RELIEF
# threshold. Both fade to 0 within RELIEF_BLEND of a town, the city, a lake
# or an end wall.
const HILL_FEATURE_SIZE := 800.0
const HILL_HEIGHT := 100.0
const MOUNTAIN_HEIGHT := 350.0
const RELIEF_BLEND := 250.0
```

At the end of `generate()`, before `return plan`:

```gdscript
	plan.heights = _heights(plan)
```

Add:

```gdscript
static func _is_flat(zone: int) -> bool:
	return zone == SectionPlanScript.Zone.TOWN or zone == SectionPlanScript.Zone.CITY or zone == SectionPlanScript.Zone.WATER

# Distance from (x, z) to the nearest flat lot or end wall. RELIEF_BLEND is
# under one lot, so the lot of the point and its 8 neighbours are enough.
# A point inside or on the edge of a flat lot is at 0.
static func _flat_distance(plan, x: float, z: float) -> float:
	var nearest: float = minf(z, plan.length - z)
	var home_x := floori(x / plan.lot_width)
	var home_z := floori(z / plan.lot_length)
	for dz in range(-1, 2):
		var lot_z: int = home_z + dz
		if lot_z < 0 or lot_z >= SectionPlanScript.LOTS_ALONG:
			continue
		for dx in range(-1, 2):
			var lot_x: int = home_x + dx
			if not _is_flat(plan.zone_at(lot_x, lot_z)):
				continue
			var gap_x: float = maxf(0.0, maxf(lot_x * plan.lot_width - x, x - (lot_x + 1) * plan.lot_width))
			var gap_z: float = maxf(0.0, maxf(lot_z * plan.lot_length - z, z - (lot_z + 1) * plan.lot_length))
			nearest = minf(nearest, Vector2(gap_x, gap_z).length())
	return nearest

static func _heights(plan) -> PackedFloat32Array:
	var mountains := mountain_noise(plan.section_index)
	var hills := FastNoiseLite.new()
	hills.seed = hash([plan.section_index, "hills"])
	hills.frequency = 1.0 / HILL_FEATURE_SIZE
	hills.fractal_octaves = 2
	var step: Vector2 = plan.height_step()
	var heights := PackedFloat32Array()
	heights.resize(SectionPlanScript.RELIEF_COLUMNS * SectionPlanScript.RELIEF_ROWS)
	for row in range(SectionPlanScript.RELIEF_ROWS):
		var z: float = row * step.y
		for column in range(SectionPlanScript.RELIEF_COLUMNS):
			var x: float = column * step.x
			var distance := _flat_distance(plan, x, z)
			if distance <= 0.0:
				continue  # resize() filled it with 0
			var p := surface_point(plan, x, z)
			var hill: float = HILL_HEIGHT * clampf((hills.get_noise_3dv(p) + 1.0) * 0.5, 0.0, 1.0)
			var mountain: float = (MOUNTAIN_HEIGHT - HILL_HEIGHT) * smoothstep(plan.relief_threshold, plan.relief_peak, mountains.get_noise_3dv(p))
			heights[row * SectionPlanScript.RELIEF_COLUMNS + column] = minf(hill + mountain, MOUNTAIN_HEIGHT) * smoothstep(0.0, RELIEF_BLEND, distance)
	return heights
```

Note: grid points on a flat lot's edge give `gap_x`/`gap_z` of ~1e-12 from float rounding, so their height is ~1e-20, not exactly 0; the tests allow 0.001 m. `smoothstep` of a noise value at or below the threshold is 0, so heights over `HILL_HEIGHT` only happen above the threshold.

- [ ] **Step 4: Run the tests to verify they pass, and measure**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_section_generator.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|WARNING|PASSED|highest|chunks with"`
Expected: `ALL TESTS PASSED`, a highest point between 200 and 350 m, the chunk count printed.

If `_test_heights_in_range...` fails only on `highest < 200` for section 42, print the highest point for sections 0..9; if most sections exceed 200 m, change the test's section to one that does and note why in the task log. Do **not** raise the heights past the spec.

Measure generation time with a throwaway probe in the scratchpad (copied into the project root to run, then deleted):

```gdscript
extends SceneTree
const G = preload("res://scripts/section_generator.gd")
func _init():
	var t := Time.get_ticks_usec()
	for i in range(3):
		G.generate(42 + i, 2000.0, 20000.0)
	print("generate avg ms: ", (Time.get_ticks_usec() - t) / 3000.0)
	quit()
```

Before this task it was ~118 ms. Write the new number in the task log. Above 1000 ms, stop and report (docking waits for two plans).

- [ ] **Step 5: Commit**

```bash
git add scripts/section_generator.gd tests/test_section_generator.gd
git commit -m "Generate section heights: hills on open land, mountains on RELIEF, flat elsewhere

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Relief mesh in the terrain dressing

**Files:**
- Modify: `scripts/terrain_dressing.gd`
- Test: `tests/test_terrain_dressing.gd`

**Interfaces:**
- Consumes: plan `height_at`, `slope_at`, `chunk_has_relief`, `height_step`, `Zone.RELIEF` (Tasks 1–3).
- Produces (on `terrain_dressing.gd`):
  - `const GRASS_COLOR := Color(0.36, 0.5, 0.26)`, `const ROCK_COLOR := Color(0.46, 0.44, 0.41)`
  - `static func relief_color(height: float, slope: float) -> Color` (outer wrapper of `MeshArrays.relief_color`)
  - `static func relief_breaks(a: float, b: float, chunk_start: float, step: float, lot_start: float, lot_size: float) -> PackedFloat64Array` (outer wrapper of `MeshArrays.relief_breaks`)
  - `MeshArrays.add_relief_patch(plan, chunk_start: Vector2, lot_start: Vector2, x0: float, x1: float, z0: float, z1: float, color: Color, rows_along: bool, relief_lot: bool) -> void`
  - `MeshArrays.faces() -> PackedVector3Array` (used in Task 5)

- [ ] **Step 1: Write the failing tests**

In `tests/test_terrain_dressing.gd`:

Replace `_test_ground_vertices_at_level_zero_facing_the_axis` (and its line in `_init()`) with `_test_ground_vertices_at_their_height_facing_the_axis`; replace `_test_ground_area_is_the_chunk_area`'s body so it projects onto the cylinder; add the new tests to `_init()` after `_test_ground_area_is_the_chunk_area()`:

```gdscript
	failures += _test_flat_plan_keeps_the_level_zero_mosaic()
	failures += _test_relief_normals_lean_downhill()
	failures += _test_relief_chunk_has_no_cracks()
	failures += _test_relief_colours()
```

Helpers and tests:

```gdscript
func _chunk_start(key: Vector2i) -> Vector2:
	return Vector2(key.x * 3 * _plan.lot_width, key.y * 4 * _plan.lot_length)

# Section coordinates of a chunk-local vertex.
func _section_xz(key: Vector2i, v: Vector3) -> Vector2:
	return _chunk_start(key) + Vector2(atan2(v.y, v.x) * RADIUS, v.z)

func _raised_chunk() -> Vector2i:
	# The chunk with the highest grid point: surely dressed with relief.
	var best := Vector2i.ZERO
	var highest := 0.0
	for along in range(20):
		for around in range(16):
			for row in range(along * 20, along * 20 + 21, 5):
				for column in range(around * 15, around * 15 + 16, 5):
					if _plan.grid_height(column, row) > highest:
						highest = _plan.grid_height(column, row)
						best = Vector2i(around, along)
	return best

func _check_ground_heights(test_name: String, plan, key: Vector2i, chunk: Node) -> int:
	for mesh: Mesh in _ground_meshes(chunk):
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(vertices.size()):
				var v: Vector3 = vertices[i]
				var at := Vector2(key.x * 3 * plan.lot_width, key.y * 4 * plan.lot_length) + Vector2(atan2(v.y, v.x) * RADIUS, v.z)
				var expected: float = RADIUS - plan.height_at(at.x, at.y)
				if absf(Vector2(v.x, v.y).length() - expected) > 0.001 or normals[i].dot(Vector3(-v.x, -v.y, 0.0)) <= 0.0:
					print("FAIL %s: vertex %s is %.3f from the axis (expected %.3f), normal %s" % [test_name, v, Vector2(v.x, v.y).length(), expected, normals[i]])
					return 1
	return 0

func _test_ground_vertices_at_their_height_facing_the_axis() -> int:
	var result := 0
	for key in [_find_chunk(SectionPlan.Zone.WATER, true), _raised_chunk()]:
		var chunk := _dress(key)
		result = maxi(result, _check_ground_heights("_test_ground_vertices_at_their_height_facing_the_axis", _plan, key, chunk))
		chunk.free()
	return result

# Area of the mesh pushed back onto the cylinder: the relief lifts vertices
# toward the axis, but the patches still tile the chunk once.
func _projected_area(mesh: Mesh) -> float:
	var area := 0.0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var flat := PackedVector3Array()
		for v in vertices:
			var r := Vector2(v.x, v.y).length()
			flat.append(Vector3(v.x * RADIUS / r, v.y * RADIUS / r, v.z))
		for t in range(0, indices.size(), 3):
			var a: Vector3 = flat[indices[t]]
			area += (flat[indices[t + 1]] - a).cross(flat[indices[t + 2]] - a).length() * 0.5
	return area

func _test_ground_area_is_the_chunk_area() -> int:
	# A mosaic with no gaps and no overlaps covers exactly the chunk (chords
	# are ~0.01% shorter than arcs). An overlap adds area; a gap removes it.
	var result := 0
	for key in [_find_chunk(SectionPlan.Zone.WATER, true), _find_chunk(SectionPlan.Zone.TOWN, true), _find_chunk(SectionPlan.Zone.CITY, true), _raised_chunk()]:
		var chunk := _dress(key)
		var area := 0.0
		for mesh: Mesh in _ground_meshes(chunk):
			area += _projected_area(mesh)
		var expected: float = 3.0 * _plan.lot_width * 4.0 * _plan.lot_length
		if absf(area - expected) > expected * 0.001:
			print("FAIL _test_ground_area_is_the_chunk_area: chunk %s covers %.1f m2, expected %.1f" % [key, area, expected])
			result = 1
		chunk.free()
	return result

func _test_flat_plan_keeps_the_level_zero_mosaic() -> int:
	# The same plan with no heights: the old path, every vertex at the radius,
	# the same vertex count as a plain level-0 dressing.
	var flat = SectionGenerator.generate(42, RADIUS, 20000.0)
	flat.heights = PackedFloat32Array()
	var key := _raised_chunk()
	var chunk := StaticBody3D.new()
	_dressing.dress_chunk(chunk, flat, key.x, key.y, _groups.get(key, []))
	var result := _check_ground_heights("_test_flat_plan_keeps_the_level_zero_mosaic", flat, key, chunk)
	var raised := _dress(key)
	var flat_vertices := 0
	var raised_vertices := 0
	for mesh: Mesh in _ground_meshes(chunk):
		for s in range(mesh.get_surface_count()):
			flat_vertices += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for mesh: Mesh in _ground_meshes(raised):
		for s in range(mesh.get_surface_count()):
			raised_vertices += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("  chunk %s: %d vertices flat, %d with relief" % [key, flat_vertices, raised_vertices])
	if raised_vertices <= flat_vertices:
		print("FAIL _test_flat_plan_keeps_the_level_zero_mosaic: the relief chunk is not split finer than the flat one")
		result = 1
	chunk.free()
	raised.free()
	return result

func _test_relief_normals_lean_downhill() -> int:
	var key := _raised_chunk()
	var chunk := _dress(key)
	var result := 0
	var checked := 0
	var surface: Mesh = (chunk.get_node("Surface") as MeshInstance3D).mesh
	for s in range(surface.get_surface_count()):
		var arrays: Array = surface.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(vertices.size()):
			var v: Vector3 = vertices[i]
			var at := _section_xz(key, v)
			var slope: Vector2 = _plan.slope_at(at.x, at.y)
			var angle := atan2(v.y, v.x)
			var around := Vector3(-sin(angle), cos(angle), 0.0)
			# Uphill toward +x: the face turns toward -x (and likewise for z).
			if (slope.x > 0.1 and normals[i].dot(around) >= 0.0) or (slope.x < -0.1 and normals[i].dot(around) <= 0.0) or (slope.y > 0.1 and normals[i].z >= 0.0) or (slope.y < -0.1 and normals[i].z <= 0.0):
				print("FAIL _test_relief_normals_lean_downhill: normal %s at %s with slope %s" % [normals[i], v, slope])
				result = 1
				break
			if slope.length() > 0.1:
				checked += 1
	if checked == 0:
		print("FAIL _test_relief_normals_lean_downhill: no sloped vertex in chunk %s" % key)
		result = 1
	chunk.free()
	return result

func _test_relief_chunk_has_no_cracks() -> int:
	# Every triangle edge used by only one triangle must lie on the chunk's
	# border: inside, every edge is shared by exactly two triangles, even
	# between a 6 m road band and a 250 m field.
	var key := _raised_chunk()
	var chunk := _dress(key)
	var edges := {}
	for mesh: Mesh in _ground_meshes(chunk):
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t in range(0, indices.size(), 3):
				for e in range(3):
					var a: Vector3 = vertices[indices[t + e]].snappedf(0.001)
					var b: Vector3 = vertices[indices[t + (e + 1) % 3]].snappedf(0.001)
					var edge_key := [a, b] if str(a) < str(b) else [b, a]
					edges[edge_key] = edges.get(edge_key, 0) + 1
	var chunk_width: float = 3.0 * _plan.lot_width
	var chunk_length: float = 4.0 * _plan.lot_length
	var result := 0
	for edge_key in edges:
		if edges[edge_key] != 1:
			continue
		var on_border := true
		for p: Vector3 in edge_key:
			var x: float = atan2(p.y, p.x) * RADIUS
			var at_side: bool = absf(x) < 0.01 or absf(x - chunk_width) < 0.01
			var at_end: bool = absf(p.z) < 0.01 or absf(p.z - chunk_length) < 0.01
			on_border = on_border and (at_side or at_end)
		if not on_border:
			print("FAIL _test_relief_chunk_has_no_cracks: open edge %s inside chunk %s" % [edge_key, key])
			result = 1
			break
	chunk.free()
	return result

func _test_relief_colours() -> int:
	var result := 0
	if not TerrainDressing.relief_color(10.0, 0.1).is_equal_approx(TerrainDressing.GRASS_COLOR) or not TerrainDressing.relief_color(320.0, 0.1).is_equal_approx(TerrainDressing.ROCK_COLOR) or not TerrainDressing.relief_color(10.0, 1.0).is_equal_approx(TerrainDressing.ROCK_COLOR):
		print("FAIL _test_relief_colours: grass low and flat, rock high or steep")
		result = 1
	# Inside a RELIEF lot, each vertex takes the colour of its height and slope.
	var key := _find_chunk(SectionPlan.Zone.RELIEF, true)
	var chunk := _dress(key)
	var surface: Mesh = (chunk.get_node("Surface") as MeshInstance3D).mesh
	var checked := 0
	for s in range(surface.get_surface_count()):
		var arrays: Array = surface.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in range(vertices.size()):
			var at := _section_xz(key, vertices[i])
			var lot := Vector2i(floori(at.x / _plan.lot_width), floori(at.y / _plan.lot_length))
			var inside: bool = fposmod(at.x, _plan.lot_width) > 1.0 and fposmod(at.x, _plan.lot_width) < _plan.lot_width - 1.0 and fposmod(at.y, _plan.lot_length) > 1.0 and fposmod(at.y, _plan.lot_length) < _plan.lot_length - 1.0
			if not inside or _plan.zone_at(lot.x, lot.y) != SectionPlan.Zone.RELIEF:
				continue
			var expected: Color = TerrainDressing.relief_color(_plan.height_at(at.x, at.y), _plan.slope_at(at.x, at.y).length())
			if absf(colors[i].r - expected.r) > 1.0 / 255.0 or absf(colors[i].g - expected.g) > 1.0 / 255.0 or absf(colors[i].b - expected.b) > 1.0 / 255.0:
				print("FAIL _test_relief_colours: vertex %s coloured %s, expected %s" % [vertices[i], colors[i], expected])
				result = 1
				break
			checked += 1
	if checked == 0:
		print("FAIL _test_relief_colours: no RELIEF vertex found in chunk %s" % key)
		result = 1
	chunk.free()
	return result
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_terrain_dressing.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED"`
Expected: `Parse Error` / `SCRIPT ERROR` on `relief_color` or `GRASS_COLOR`, and `FAIL _test_ground_vertices_at_their_height_facing_the_axis` (vertices still at the radius). To see the height test fail on its own, temporarily comment out `_test_relief_colours` in `_init()`, run, then put it back.

- [ ] **Step 3: Implement**

In `scripts/terrain_dressing.gd`:

Update the header comment's second sentence:

```gdscript
# Turns a section plan into geometry, one interior terrain chunk at a time,
# in the chunk's own frame (InteriorWorld turns each chunk about Z and shifts
# it along Z). The ground is a mosaic with no overlapping layers, at level 0
# or following the plan's heights: with the interior camera (near 0.2 m, far
# 60 km) the depth buffer cannot separate surfaces less than a metre apart at
# 2 km, so layers would flicker.
```

Add constants after `WATER_COLOR`:

```gdscript
# RELIEF lots: grass low and gentle, rock on steep slopes and high up.
const GRASS_COLOR := Color(0.36, 0.5, 0.26)
const ROCK_COLOR := Color(0.46, 0.44, 0.41)
# Two breaks closer than this are one (float rounding at lot edges).
const BREAK_TOLERANCE := 0.01
```

Inside `class MeshArrays`, add after `add_patch`:

```gdscript
	# The same rectangle following the plan's heights. chunk_start is the
	# chunk's (x, z) origin in section metres, lot_start the lot's (x, z) in
	# chunk metres. Split on every height-grid line and road-band edge
	# (relief_breaks below) so neighbours share every edge vertex.
	# RELIEF lots take their colour from height and slope.
	func add_relief_patch(plan, chunk_start: Vector2, lot_start: Vector2, x0: float, x1: float, z0: float, z1: float, color: Color, rows_along: bool, relief_lot: bool) -> void:
		var step: Vector2 = plan.height_step()
		var xs := relief_breaks(x0, x1, chunk_start.x, step.x, lot_start.x, plan.lot_width)
		var zs := relief_breaks(z0, z1, chunk_start.y, step.y, lot_start.y, plan.lot_length)
		var radius: float = plan.radius
		var base: int = vertices.size()
		for x: float in xs:
			var angle: float = x / radius
			var outward := Vector3(cos(angle), sin(angle), 0.0)
			var around := Vector3(-sin(angle), cos(angle), 0.0)
			for z: float in zs:
				var h: float = plan.height_at(chunk_start.x + x, chunk_start.y + z)
				var slope: Vector2 = plan.slope_at(chunk_start.x + x, chunk_start.y + z)
				var k: float = (radius - h) / radius
				vertices.append(outward * (radius - h) + Vector3(0.0, 0.0, z))
				normals.append((-outward * k - around * slope.x - Vector3(0.0, 0.0, k * slope.y)).normalized())
				colors.append(relief_color(h, slope.length()) if relief_lot else color)
				uvs.append(Vector2(x, z) / ROW_SPACING if rows_along else Vector2(z, x) / ROW_SPACING)
		# Same winding as add_patch: (x_i, z_j) is base + i * zs.size() + j.
		var nz: int = zs.size()
		for i in range(xs.size() - 1):
			for j in range(nz - 1):
				var p00: int = base + i * nz + j
				indices.append_array(PackedInt32Array([p00, p00 + nz, p00 + 1, p00 + nz, p00 + nz + 1, p00 + 1]))

	# Triangle corners in draw order, for a collision shape.
	func faces() -> PackedVector3Array:
		var out := PackedVector3Array()
		for i in indices:
			out.append(vertices[i])
		return out
```

Verified in Godot 4.6.1: an inner class reads the outer script's constants (including preloaded scripts) but **cannot** call its static functions (`Parse Error: Function "helper()" not found in base self`). So both helpers live inside `MeshArrays`, after `faces()`:

```gdscript
	static func relief_color(height: float, slope: float) -> Color:
		var rock := maxf(smoothstep(0.5, 0.9, slope), smoothstep(180.0, 300.0, height))
		return GRASS_COLOR.lerp(ROCK_COLOR, rock)

	# Where a relief patch from a to b (chunk metres, one axis) is split: its
	# two ends, every height-grid line inside it (grid lines sit at whole
	# steps of section metres, chunk_start being the chunk's origin), and
	# every edge a road band of its lot could have (half a street or main
	# road in from either lot edge). Two patches sharing an edge thus share
	# every vertex on it.
	static func relief_breaks(a: float, b: float, chunk_start: float, step: float, lot_start: float, lot_size: float) -> PackedFloat64Array:
		var street: float = SectionPlanScript.road_width(SectionPlanScript.Road.STREET) * 0.5
		var main: float = SectionPlanScript.road_width(SectionPlanScript.Road.MAIN) * 0.5
		var lot_end: float = lot_start + lot_size
		var cuts: Array[float] = [lot_start + street, lot_start + main, lot_end - main, lot_end - street]
		var k := ceili((chunk_start + a) / step)
		while k * step - chunk_start < b:
			cuts.append(k * step - chunk_start)
			k += 1
		cuts.sort()
		var out := PackedFloat64Array([a])
		for cut in cuts:
			if cut > out[out.size() - 1] + BREAK_TOLERANCE and cut < b - BREAK_TOLERANCE:
				out.append(cut)
		out.append(b)
		return out
```

`lot_end` is written `lot_start + lot_size`, the same expression `_build_ground` uses for `x1`/`z1` (`x0 + plan.lot_width`), so the cut and the cell edge are the same float.

On the outer script, after `_stripe_texture`, thin wrappers for the tests:

```gdscript
static func relief_color(height: float, slope: float) -> Color:
	return MeshArrays.relief_color(height, slope)

static func relief_breaks(a: float, b: float, chunk_start: float, step: float, lot_start: float, lot_size: float) -> PackedFloat64Array:
	return MeshArrays.relief_breaks(a, b, chunk_start, step, lot_start, lot_size)
```

Replace `_build_ground` with:

```gdscript
func _build_ground(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int) -> void:
	var fields := MeshArrays.new()
	var paved := MeshArrays.new()
	var water := MeshArrays.new()
	var relief: bool = plan.chunk_has_relief(chunk_around, chunk_along)
	var chunk_start := Vector2(chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width, chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length)
	for lot_x in range(SectionPlanScript.CHUNK_LOTS_AROUND):
		for lot_z in range(SectionPlanScript.CHUNK_LOTS_ALONG):
			var around: int = chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND + lot_x
			var along: int = chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG + lot_z
			var x0: float = lot_x * plan.lot_width
			var x1: float = x0 + plan.lot_width
			var z0: float = lot_z * plan.lot_length
			var z1: float = z0 + plan.lot_length
			var lot_start := Vector2(x0, z0)
			var zone: int = plan.zone_at(around, along)
			if zone == SectionPlanScript.Zone.WATER or zone == SectionPlanScript.Zone.RELIEF:
				# Whole lot, no roads (none border a lake or a RELIEF lot).
				var wet: bool = zone == SectionPlanScript.Zone.WATER
				var color: Color = WATER_COLOR if wet else GRASS_COLOR
				_add(water if wet else paved, relief, plan, chunk_start, lot_start, x0, x1, z0, z1, color, true, not wet)
				continue
			var west: int = plan.road_on_west(around, along)
			var east: int = plan.road_on_east(around, along)
			var south: int = plan.road_on_south(around, along)
			var north: int = plan.road_on_north(around, along)
			# Each road is split down its middle: half its width in each lot.
			var xs := [x0, x0 + SectionPlanScript.road_width(west) * 0.5, x1 - SectionPlanScript.road_width(east) * 0.5, x1]
			var zs := [z0, z0 + SectionPlanScript.road_width(south) * 0.5, z1 - SectionPlanScript.road_width(north) * 0.5, z1]
			var lot: int = plan.lot_index(around, along)
			for column in range(3):
				for row in range(3):
					var cx0: float = xs[column]
					var cx1: float = xs[column + 1]
					var cz0: float = zs[row]
					var cz1: float = zs[row + 1]
					if cx1 - cx0 < 0.001 or cz1 - cz0 < 0.001:
						continue
					var road := cell_road(column, row, west, east, south, north)
					if road == SectionPlanScript.Road.MAIN:
						_add(paved, relief, plan, chunk_start, lot_start, cx0, cx1, cz0, cz1, MAIN_ROAD_COLOR, true, false)
					elif road == SectionPlanScript.Road.STREET:
						_add(paved, relief, plan, chunk_start, lot_start, cx0, cx1, cz0, cz1, STREET_COLOR, true, false)
					elif zone == SectionPlanScript.Zone.FIELD:
						_add(fields, relief, plan, chunk_start, lot_start, cx0, cx1, cz0, cz1, CROP_COLORS[plan.crops[lot]], plan.rows_along[lot] == 1, false)
					else:
						_add(paved, relief, plan, chunk_start, lot_start, cx0, cx1, cz0, cz1, TOWN_GROUND_COLOR if zone == SectionPlanScript.Zone.TOWN else CITY_GROUND_COLOR, true, false)
	var surface_mesh := ArrayMesh.new()
	for part in [[fields, field_material], [paved, paved_material]]:
		var arrays: MeshArrays = part[0]
		if not arrays.is_empty():
			surface_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays.to_arrays())
			surface_mesh.surface_set_material(surface_mesh.get_surface_count() - 1, part[1])
	if surface_mesh.get_surface_count() > 0:
		var surface := MeshInstance3D.new()
		surface.name = "Surface"
		surface.mesh = surface_mesh
		chunk.add_child(surface)
	if not water.is_empty():
		var water_mesh := ArrayMesh.new()
		water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water.to_arrays())
		var water_node := MeshInstance3D.new()
		water_node.name = "Water"
		water_node.mesh = water_mesh
		water_node.material_override = water_material
		chunk.add_child(water_node)

# One patch: split and lifted to the plan's heights in a chunk with relief,
# the old level-0 patch otherwise.
static func _add(arrays: MeshArrays, relief: bool, plan, chunk_start: Vector2, lot_start: Vector2, x0: float, x1: float, z0: float, z1: float, color: Color, rows_along: bool, relief_lot: bool) -> void:
	if relief:
		arrays.add_relief_patch(plan, chunk_start, lot_start, x0, x1, z0, z1, color, rows_along, relief_lot)
	else:
		arrays.add_patch(plan.radius, x0, x1, z0, z1, color, rows_along)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_terrain_dressing.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|WARNING|PASSED|vertices"`
Expected: `ALL TESTS PASSED`, with the vertex counts printed (write them in the task log).

- [ ] **Step 5: Commit**

```bash
git add scripts/terrain_dressing.gd tests/test_terrain_dressing.gd
git commit -m "Dress chunks with relief: split on the height grid, lifted, slope normals, grass and rock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Collision for chunks with relief

**Files:**
- Modify: `scripts/terrain_dressing.gd`
- Test: `tests/test_terrain_dressing.gd`

**Interfaces:**
- Consumes: `MeshArrays.faces()` (Task 4).
- Produces: `dress_chunk` gives a chunk with relief a `CollisionShape3D` named `Collision` holding its own `ConcavePolygonShape3D`; a flat chunk's `Collision` is untouched.

- [ ] **Step 1: Write the failing test**

Add to `_init()` after `_test_relief_colours()`:

```gdscript
	failures += _test_relief_chunk_owns_a_collision_matching_its_mesh()
```

```gdscript
# A chunk as InteriorWorld builds it: a Collision node with the shared shape.
func _chunk_with_shared_shape(shared: Shape3D) -> StaticBody3D:
	var chunk := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shared
	chunk.add_child(collision)
	return chunk

func _test_relief_chunk_owns_a_collision_matching_its_mesh() -> int:
	var shared := ConcavePolygonShape3D.new()
	var key := _raised_chunk()
	var raised := _chunk_with_shared_shape(shared)
	_dressing.dress_chunk(raised, _plan, key.x, key.y, _groups.get(key, []))
	var result := 0
	var shape: Shape3D = (raised.get_node("Collision") as CollisionShape3D).shape
	var triangles := 0
	for mesh: Mesh in _ground_meshes(raised):
		for s in range(mesh.get_surface_count()):
			triangles += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	if shape == shared or not (shape is ConcavePolygonShape3D) or (shape as ConcavePolygonShape3D).get_faces().size() != triangles * 3:
		print("FAIL _test_relief_chunk_owns_a_collision_matching_its_mesh: relief chunk shape %s, %d face corners for %d triangles" % [shape, 0 if not (shape is ConcavePolygonShape3D) else (shape as ConcavePolygonShape3D).get_faces().size(), triangles])
		result = 1
	# The same chunk from a plan with no heights keeps the shared shape.
	var flat = SectionGenerator.generate(42, RADIUS, 20000.0)
	flat.heights = PackedFloat32Array()
	var level := _chunk_with_shared_shape(shared)
	_dressing.dress_chunk(level, flat, key.x, key.y, _groups.get(key, []))
	if (level.get_node("Collision") as CollisionShape3D).shape != shared:
		print("FAIL _test_relief_chunk_owns_a_collision_matching_its_mesh: a flat chunk lost the shared shape")
		result = 1
	raised.free()
	level.free()
	return result
```

(`@warning_ignore("integer_division")` above the function if Godot warns on `/ 3`.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_terrain_dressing.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED"`
Expected: `FAIL _test_relief_chunk_owns_a_collision_matching_its_mesh: relief chunk shape ...` (still the shared one).

- [ ] **Step 3: Implement**

At the end of `_build_ground` in `scripts/terrain_dressing.gd`, add:

```gdscript
	if relief:
		_set_ground_collision(chunk, [fields, paved, water])
```

and the function:

```gdscript
# A chunk with relief collides with its own drawn ground, not the shared
# level-0 shape: same triangles as the mesh.
func _set_ground_collision(chunk: StaticBody3D, parts: Array) -> void:
	var faces := PackedVector3Array()
	for arrays: MeshArrays in parts:
		faces.append_array(arrays.faces())
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := chunk.get_node_or_null("Collision") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "Collision"
		chunk.add_child(collision)
	collision.shape = shape
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/test_terrain_dressing.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|WARNING|PASSED"`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/terrain_dressing.gd tests/test_terrain_dressing.gd
git commit -m "Give chunks with relief their own trimesh collision

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Interior world, physics and timing

**Files:**
- Modify: `tests/test_interior_world.gd`, `tests/test_interior_world_physics.gd`
- Modify (only if the measurement says so): `scripts/interior_world.gd` (`CHUNKS_DRESSED_PER_FRAME`)

**Interfaces:**
- Consumes: everything above; `world.get_section_plan(slot)`, `world._chunk_shape` (private member, read by tests only).

- [ ] **Step 1: Run the interior suites to see what the relief breaks**

Run each and keep the output:

```bash
for t in test_interior_world test_interior_world_physics test_interior_streaming; do /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . -s tests/$t.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|PASSED| ms|lights"; done
```

Expected RED: `FAIL _test_sections_of_320_dressed_chunks_sharing_one_collision_shape` (relief chunks own their shape), `FAIL _test_terrain_vertices_on_the_wall_facing_the_axis` (vertices no longer at the radius) if chunk 03_07 has relief, and possibly the physics test (the hull placed 1.05 m above level 0 now starts inside a hill). Write the timings printed (`interior build`, `worst frame while streaming`) in the task log.

- [ ] **Step 2: Update the world tests**

In `tests/test_interior_world.gd`, rename `_test_sections_of_320_dressed_chunks_sharing_one_collision_shape` to `_test_sections_of_320_dressed_chunks_flat_ones_sharing_one_shape` (in `_init()` too) and replace its body:

```gdscript
func _test_sections_of_320_dressed_chunks_flat_ones_sharing_one_shape() -> int:
	# Flat chunks share the level-0 trimesh; chunks with relief own theirs.
	var world := _make_world()
	var result := 0
	var shared: Shape3D = world._chunk_shape
	var owned := {}
	for slot in [-1, 0]:
		var section := world.get_node("Chain/Section_%d" % slot)
		var plan = world.get_section_plan(slot)
		var chunks := section.find_children("Chunk_*", "StaticBody3D", false, false)
		if chunks.size() != 320:
			print("FAIL _test_sections_of_320_dressed_chunks_flat_ones_sharing_one_shape: section %d has %d chunks, expected 320" % [slot, chunks.size()])
			result = 1
		for chunk in chunks:
			var parts := String(chunk.name).split("_")
			var raised: bool = plan.chunk_has_relief(int(parts[1]), int(parts[2]))
			var shape: Shape3D = (chunk.get_node("Collision") as CollisionShape3D).shape
			var dressed: bool = chunk.get_node_or_null("Surface") != null or chunk.get_node_or_null("Water") != null
			var right: bool = (shape != shared and not owned.has(shape)) if raised else shape == shared
			if not right or not (shape is ConcavePolygonShape3D) or not dressed:
				print("FAIL _test_sections_of_320_dressed_chunks_flat_ones_sharing_one_shape: section %d %s (relief %s) not dressed or wrong shape" % [slot, chunk.name, raised])
				result = 1
				break
			if raised:
				owned[shape] = true
	world.free()
	return result
```

Replace `_test_terrain_vertices_on_the_wall_facing_the_axis` (rename to `_test_terrain_vertices_at_their_height_facing_the_axis`, in `_init()` too):

```gdscript
func _test_terrain_vertices_at_their_height_facing_the_axis() -> int:
	# In the chunk's own frame (the Surface and Water nodes sit at its origin).
	var world := _make_world()
	var plan = world.get_section_plan(0)
	var result := 0
	for key in [Vector2i(3, 7), Vector2i(10, 12)]:
		var chunk: Node3D = world.get_node("Chain/Section_0/Chunk_%02d_%02d" % [key.x, key.y])
		var start := Vector2(key.x * 3 * plan.lot_width, key.y * 4 * plan.lot_length)
		for part in ["Surface", "Water"]:
			var node := chunk.get_node_or_null(part) as MeshInstance3D
			if node == null:
				continue
			for s in range(node.mesh.get_surface_count()):
				var arrays: Array = node.mesh.surface_get_arrays(s)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in range(vertices.size()):
					var v: Vector3 = vertices[i]
					var expected: float = RADIUS - plan.height_at(start.x + atan2(v.y, v.x) * RADIUS, start.y + v.z)
					if absf(Vector2(v.x, v.y).length() - expected) > 0.01 or normals[i].dot(Vector3(-v.x, -v.y, 0.0)) <= 0.0:
						print("FAIL _test_terrain_vertices_at_their_height_facing_the_axis: chunk %s vertex %s at %.3f, expected %.3f" % [key, v, Vector2(v.x, v.y).length(), expected])
						world.free()
						return 1
	world.free()
	return result
```

If `_check_wall` is no longer used by any test after this change, delete it (Godot does not warn on unused functions, but dead helpers mislead).

- [ ] **Step 3: Update and extend the physics test**

In `tests/test_interior_world_physics.gd`, in `_field_point`, lift the point by the ground height:

```gdscript
				var r: float = world.section_radius - plan.height_at(center.x, center.y) - height
```

Add to `_initialize()` after the first test:

```gdscript
	_failures += await _test_hull_pushed_into_a_hillside_stops_on_it()
```

```gdscript
func _test_hull_pushed_into_a_hillside_stops_on_it() -> int:
	# No gravity inside: push the hull 60 m straight at a hillside from 30 m
	# above it. It must stop on the drawn ground, not pass through.
	var world: Node3D = InteriorWorldScript.new()
	world.build()
	root.add_child(world)
	var plan = world.get_section_plan(0)
	var start_z: float = -(world.bridge_length * 0.5 + world.section_length)
	var spot := Vector2(-1.0, -1.0)
	for along in range(SectionPlan.LOTS_ALONG):
		for around in range(SectionPlan.LOTS_AROUND):
			var center: Vector2 = plan.lot_center(around, along)
			if plan.height_at(center.x, center.y) > 50.0 and plan.slope_at(center.x, center.y).length() > 0.1:
				spot = center
				break
		if spot.x >= 0.0:
			break
	var result := 0
	if spot.x < 0.0:
		print("FAIL _test_hull_pushed_into_a_hillside_stops_on_it: no sloped point over 50 m in section 0")
		world.free()
		return 1
	var ground: float = plan.height_at(spot.x, spot.y)
	var angle: float = spot.x / world.section_radius
	var outward := Vector3(cos(angle), sin(angle), 0.0)
	var hull := CharacterBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 8.0)
	shape_node.shape = box
	hull.add_child(shape_node)
	root.add_child(hull)
	hull.global_position = outward * (world.section_radius - ground - 30.0) + Vector3(0.0, 0.0, start_z + spot.y)
	await physics_frame
	var hit := hull.move_and_collide(outward * 60.0)
	var reached: float = Vector2(hull.global_position.x, hull.global_position.y).length()
	# Stopped with its centre above the ground (nearer the axis than it), and
	# within the hull's half diagonal plus the slope's lean.
	if hit == null or reached > world.section_radius - ground or reached < world.section_radius - ground - 15.0:
		print("FAIL _test_hull_pushed_into_a_hillside_stops_on_it: hit %s, centre %.1f m from the axis, ground at %.1f" % [hit != null, reached, world.section_radius - ground])
		result = 1
	hull.free()
	world.free()
	return result
```

- [ ] **Step 4: Run the three interior suites; decide the dressing budget**

Run the loop from Step 1 again.
Expected: `ALL TESTS PASSED` in all three. Write in the task log: `interior build` ms (was ~1047), `worst frame while streaming` ms (was ~27).

Decision rule for `CHUNKS_DRESSED_PER_FRAME` in `scripts/interior_world.gd` (today 16):
- worst frame ≤ 35 ms: leave it at 16.
- worst frame > 35 ms: lower it (12, then 8) until the worst frame is ≤ 35 ms and `_test_flying_along_the_chain_finds_each_section_ready` still passes. Update the comment above the constant with the new measured times, e.g.:

```gdscript
# Per-frame work while flying (about N ms and 7 ms measured, with relief).
const CHUNKS_DRESSED_PER_FRAME := 12
```

- interior build > 3000 ms: stop and report; do not raise the test limit.

- [ ] **Step 5: Run the full suite**

Run: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/88be7e76-cf17-4eba-b962-d57871ddb62e/scratchpad/suite.sh`
Expected: every file `ALL TESTS PASSED` (40 files: 39 before + `test_section_plan.gd`).

- [ ] **Step 6: Commit**

```bash
git add tests/test_interior_world.gd tests/test_interior_world_physics.gd scripts/interior_world.gd
git commit -m "Check interior relief in the world: own shapes, heights, hillside collision

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Live check

**Files:** none changed unless a problem shows.

- [ ] **Step 1: Headless run of the real game**

Run: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"`
Expected: nothing.

- [ ] **Step 2: Offscreen render inside a section**

Write this throwaway probe as `probe_relief.gd` in the scratchpad, copy it into the project root only to run it, then delete the copy. It waits with a node's real `_process()` (not a long `await process_frame` loop: see HANDOFF).

```gdscript
extends SceneTree

# Throwaway: section 0 of the interior seen from 300 m above the ground,
# 2 km short of its highest lot, looking at it.

const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")
const OUT := "/tmp/claude-1000/-home-patrick-projects-playground-torus1/88be7e76-cf17-4eba-b962-d57871ddb62e/scratchpad/relief.png"

class Shooter:
	extends Node
	var frames := 0
	func _process(_delta: float) -> void:
		frames += 1
		if frames == 180:
			get_viewport().get_texture().get_image().save_png(OUT)
			get_tree().quit()

func _initialize() -> void:
	var world: Node3D = InteriorWorldScript.new()
	world.build()
	root.add_child(world)
	var plan = world.get_section_plan(0)
	var start_z: float = -(world.bridge_length * 0.5 + world.section_length)
	var peak := Vector2.ZERO
	for along in range(SectionPlan.LOTS_ALONG):
		for around in range(SectionPlan.LOTS_AROUND):
			var center: Vector2 = plan.lot_center(around, along)
			if plan.height_at(center.x, center.y) > plan.height_at(peak.x, peak.y):
				peak = center
	var angle: float = peak.x / world.section_radius
	var outward := Vector3(cos(angle), sin(angle), 0.0)
	var target: Vector3 = outward * (world.section_radius - plan.height_at(peak.x, peak.y)) + Vector3(0.0, 0.0, start_z + peak.y)
	var eye_z: float = clampf(peak.y + 2000.0, 0.0, world.section_length)
	var eye: Vector3 = outward * (world.section_radius - plan.height_at(peak.x, eye_z) - 300.0) + Vector3(0.0, 0.0, start_z + eye_z)
	var camera := Camera3D.new()
	camera.near = 0.2
	camera.far = 60000.0
	root.add_child(camera)
	camera.look_at_from_position(eye, target, -outward)
	camera.make_current()
	print("peak %.0f m at %s" % [plan.height_at(peak.x, peak.y), peak])
	root.add_child(Shooter.new())
```

Run it with `xvfb-run -a /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --path . -s probe_relief.gd` (no `--headless`: it does not render). If it does not return in ~60 s, `pkill -9 -f probe_relief.gd`.

Look at the image: hills visible through shading, a mountain with rock on top, flat towns and lakes, no black slits along roads.

- [ ] **Step 3: Hand over to the user for the live check**

Report to the user: what was measured (generation, build, worst frame), the render, and ask them to run the game (`~/Godot_v4.6.1-stable-double_linux.x86_64 --path .`), dock, and fly over hills and into a mountainside. Their check is the final gate; headless and xvfb probes do not replace it.
