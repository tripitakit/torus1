# Section Terrain (Piece B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the two interior sections with procedurally generated land use — crop fields, roads, lakes, towns and one city centre with towers — built deterministically from each section's index.

**Architecture:** `section_plan.gd` holds pure data (a 48 × 80 lot grid with zones, crops, row directions and edge roads, plus parallel arrays of buildings). `section_generator.gd` fills it from the section index with seeded noise and seeded RNGs. `terrain_dressing.gd` turns a plan into geometry chunk by chunk: a level-0 ground mosaic (fields/paved/roads, no overlapping layers), a water mesh, a `MultiMesh` of buildings with world-space window textures, and one box collider per building added straight to the chunk's static body. `interior_world.gd` generates each section from `behind_section_index` / `ahead_section_index`, which `game_mode.gd` sets from the docked bridge.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer. Headless `extends SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-09-24-section-terrain-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`. One test file: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (every `tests/*.gd` must print exactly `ALL TESTS PASSED`; exit 0). If the script is gone, recreate it: loop over `tests/*.gd`, grep each run for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the grep is exactly `ALL TESTS PASSED`.
- **Reading RED:** a missing method prints `SCRIPT ERROR: ... Nonexistent function` and the file may still end with `ALL TESTS PASSED`; a missing preload prints `Parse Error`. RED is those lines or `FAIL` lines, never the summary alone.
- **Fresh worktree:** run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import` once before the first test run.
- **Off-tree vs in-tree:** `global_position` / `global_transform` / `to_local` error on nodes outside the tree. Off-tree tests chain `transform`s by hand; physics and cameras need in-tree tests (`_initialize()` + `await physics_frame`).
- **Packed arrays are values (verified behaviour class):** calling `append()` on a packed-array property of *another* object, or on a packed array passed as an argument, can act on a copy. Build packed arrays in locals and assign them whole (`plan.zones = zones`); inside a class, mutate its own members directly. Plain `Array`/`Dictionary` are references and are safe.
- **Headless has no real renderer:** `MultiMesh.get_aabb()` / `MultiMeshInstance3D.get_aabb()` return an empty box there. Set `custom_aabb` explicitly and have tests read `custom_aabb`.
- `find_children()` on code-built nodes must pass `owned = false`.
- GDScript: explicit types where builtins return Variant; do not name locals `basis`, `transform`, `position`, `sign`, `owner`; avoid unused parameters (prefix with `_`) and integer division without `@warning_ignore("integer_division")` — both print `WARNING` lines.
- Mesh winding for surfaces facing the cylinder axis (verified in piece A): for quad corners `p00=(x0,z0)`, `p10=(x1,z0)`, `p01=(x0,z1)`, `p11=(x1,z1)` with `x` increasing with angle, the triangles are `(p00, p10, p01)` and `(p10, p11, p01)`.
- Unrolled coordinates: `x` = arc length around (angle = `x / radius`), `z` = distance from the section's low-`z` end. Chunk `(a, b)` of the interior (rotated `a * TAU / 16` about Z, shifted `start_z + b * 1000`) holds lots `3a .. 3a+2` around and `4b .. 4b+3` along.
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `.claude/worktrees/`. Add Godot-generated `.uid` files for new scripts/tests.
- Live check (the Godot MCP server is not connected): `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"` prints nothing. Never launch a windowed run (fullscreen game); offscreen renders go through `xvfb-run`.

## Review Focus

1. **The way round closes** — lot 47 and lot 0 are neighbours: zones, roads (`road_on_east` of lot 47 is `road_west` of lot 0) and distances (`surface_distance`) must treat them as adjacent. Tests: `_test_zones_join_up_where_the_way_round_closes`, `_test_surface_distance_wraps_around` (Task 1), `_test_road_kinds` (Task 2).
2. **Overlapping ground layers z-fight at distance** — any overlap or gap in the level-0 mosaic shows as flicker or black holes. Test: `_test_ground_area_is_the_chunk_area` (Task 3).
3. **A building standing in a road, in water, or across a lot edge** — Tests: `_test_buildings_stay_inside_their_lot_clear_of_roads`, `_test_buildings_only_in_towns_and_city`, `_test_buildings_do_not_overlap` (Task 2).
4. **Colliders that do not match the drawn buildings** — the ship would bounce off air or pass through walls. Test: `_test_building_colliders_match_the_drawn_buildings` (Task 4); in-tree `_test_hits_a_building_and_bounces` (Task 5).
5. **Docking now takes longer** — the interior build grows; transitions must still complete and tests must not rely on a fixed wait. Tests: `_test_building_both_sections_takes_under_three_seconds` (Task 5), condition-based `_wait_for_transition` (Task 6).

---

### Task 1: Section plan data and zones

**Files:**
- Create: `scripts/section_plan.gd`, `scripts/section_generator.gd`, `tests/test_section_generator.gd`

**Interfaces:**
- Produces `section_plan.gd`: enums `Zone { FIELD, TOWN, CITY, WATER }`, `Crop { WHEAT, CORN, SUNFLOWER, LAVENDER, RICE, PASTURE }`, `Road { NONE, STREET, MAIN }`; consts `LOTS_AROUND := 48`, `LOTS_ALONG := 80`, `CHUNK_LOTS_AROUND := 3`, `CHUNK_LOTS_ALONG := 4`, `MAIN_ROAD_WIDTH := 12.0`, `STREET_WIDTH := 8.0`; vars `section_index`, `radius`, `length`, `lot_width`, `lot_length`, `zones`, `crops`, `rows_along`, `road_west`, `road_south` (`PackedByteArray`, index `along * 48 + around`), `city_center: Vector2`, `building_x`, `building_z` (`PackedFloat64Array`), `building_size` (`PackedVector3Array`: width around, height, depth along), `building_color` (`PackedColorArray`), `building_lot` (`PackedInt32Array`); funcs `static road_width(road) -> float`, `lot_index(around, along) -> int` (wraps `around`), `zone_at`, `lot_center(around, along) -> Vector2`, `circumference() -> float`, `surface_distance(a: Vector2, b: Vector2) -> float`, `road_on_west/east/south/north(around, along) -> int`, `building_count() -> int`, `group_buildings_by_chunk() -> Dictionary` (`Vector2i(chunk_around, chunk_along)` → `Array` of building indices).
- Produces `section_generator.gd`: `static func generate(section_index: int, radius: float, length: float)` → a `section_plan.gd` instance. This task fills zones, city, crops and rows; roads and buildings come in Task 2 (arrays stay empty/zero until then).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_section_generator.gd`:

```gdscript
extends SceneTree

const SectionGenerator = preload("res://scripts/section_generator.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")

const RADIUS := 2000.0
const LENGTH := 20000.0

var _plan = SectionGenerator.generate(42, RADIUS, LENGTH)

func _init():
	var failures := 0
	failures += _test_grid_matches_the_terrain_chunks()
	failures += _test_same_index_same_plan()
	failures += _test_different_index_different_plan()
	failures += _test_zone_shares()
	failures += _test_one_city_centre_in_the_middle()
	failures += _test_zones_join_up_where_the_way_round_closes()
	failures += _test_every_crop_appears()
	failures += _test_surface_distance_wraps_around()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _count_zone(plan, zone: int) -> int:
	var count := 0
	for value in plan.zones:
		if value == zone:
			count += 1
	return count

func _test_grid_matches_the_terrain_chunks() -> int:
	# 16 chunks around x 3 lots, 20 chunks along x 4 lots.
	var result := 0
	if not is_equal_approx(_plan.lot_width * 48.0, TAU * RADIUS) or not is_equal_approx(_plan.lot_length, 250.0) or _plan.zones.size() != 3840:
		print("FAIL _test_grid_matches_the_terrain_chunks: lot %f x %f, %d lots" % [_plan.lot_width, _plan.lot_length, _plan.zones.size()])
		result = 1
	return result

func _test_same_index_same_plan() -> int:
	var again = SectionGenerator.generate(42, RADIUS, LENGTH)
	if again.zones != _plan.zones or again.crops != _plan.crops or again.rows_along != _plan.rows_along or again.city_center != _plan.city_center:
		print("FAIL _test_same_index_same_plan: two plans for section 42 differ")
		return 1
	return 0

func _test_different_index_different_plan() -> int:
	var other = SectionGenerator.generate(43, RADIUS, LENGTH)
	if other.zones == _plan.zones:
		print("FAIL _test_different_index_different_plan: sections 42 and 43 have the same zones")
		return 1
	return 0

func _test_zone_shares() -> int:
	# 10% water and 15% town exactly, before the city overwrites some lots.
	var water := _count_zone(_plan, SectionPlan.Zone.WATER)
	var town := _count_zone(_plan, SectionPlan.Zone.TOWN)
	var city := _count_zone(_plan, SectionPlan.Zone.CITY)
	var result := 0
	if city < 15 or city > 35:
		print("FAIL _test_zone_shares: %d city lots, expected about 23 (700 m radius)" % city)
		result = 1
	if water > 384 or water < 384 - city or town > 576 or town < 576 - city:
		print("FAIL _test_zone_shares: water %d (expected 384 minus city), town %d (expected 576 minus city)" % [water, town])
		result = 1
	return result

func _test_one_city_centre_in_the_middle() -> int:
	var result := 0
	if _plan.city_center.y < 0.2 * LENGTH or _plan.city_center.y > 0.8 * LENGTH:
		print("FAIL _test_one_city_centre_in_the_middle: centre at z %f" % _plan.city_center.y)
		result = 1
	for along in range(80):
		for around in range(48):
			var near: bool = _plan.surface_distance(_plan.lot_center(around, along), _plan.city_center) <= 700.0
			var is_city: bool = _plan.zone_at(around, along) == SectionPlan.Zone.CITY
			if near != is_city:
				print("FAIL _test_one_city_centre_in_the_middle: lot (%d, %d) city=%s but within 700 m=%s" % [around, along, is_city, near])
				return 1
	return result

func _agreement(around_a: int, around_b: int) -> float:
	var same := 0
	for along in range(80):
		if _plan.zone_at(around_a, along) == _plan.zone_at(around_b, along):
			same += 1
	return same / 80.0

func _test_zones_join_up_where_the_way_round_closes() -> int:
	# Neighbouring lots mostly share a zone (zones are km-sized). If the noise
	# were sampled on the unrolled strip, lots 47 and 0 would be 12 km apart
	# and agree only by chance (~0.6).
	var seam := _agreement(47, 0)
	var inside := _agreement(23, 24)
	if seam < 0.75 or inside < 0.75:
		print("FAIL _test_zones_join_up_where_the_way_round_closes: agreement at the seam %.2f, inside %.2f" % [seam, inside])
		return 1
	return 0

func _test_every_crop_appears() -> int:
	var counts := {}
	for i in range(_plan.zones.size()):
		if _plan.zones[i] == SectionPlan.Zone.FIELD:
			counts[_plan.crops[i]] = counts.get(_plan.crops[i], 0) + 1
	for crop in SectionPlan.Crop.values():
		if counts.get(crop, 0) < 20:
			print("FAIL _test_every_crop_appears: crop %d on %d field lots" % [crop, counts.get(crop, 0)])
			return 1
	return 0

func _test_surface_distance_wraps_around() -> int:
	var c: float = _plan.circumference()
	var result := 0
	if not is_equal_approx(_plan.surface_distance(Vector2(10.0, 0.0), Vector2(c - 10.0, 0.0)), 20.0):
		print("FAIL _test_surface_distance_wraps_around: across the seam %f expected 20" % _plan.surface_distance(Vector2(10.0, 0.0), Vector2(c - 10.0, 0.0)))
		result = 1
	if not is_equal_approx(_plan.surface_distance(Vector2(100.0, 0.0), Vector2(100.0, 300.0)), 300.0):
		print("FAIL _test_surface_distance_wraps_around: along z expected 300")
		result = 1
	return result
```

- [ ] **Step 2: Run to verify it fails** — `tests/test_section_generator.gd`. Expected: `Parse Error` (preload of `section_generator.gd`).

- [ ] **Step 3: Implement**

Create `scripts/section_plan.gd`:

```gdscript
extends RefCounted

# What stands on one section's inner surface: a grid of lots (zone, crop,
# roads) and a list of buildings. Pure data, made by section_generator.gd and
# turned into geometry by terrain_dressing.gd.
#
# Unrolled surface coordinates: x = arc length around the section
# (0 .. 2 pi radius), z = distance along it from its low-z end (0 .. length).
# Lot (around, along) covers x in [around, around + 1] * lot_width and
# z in [along, along + 1] * lot_length.

enum Zone { FIELD, TOWN, CITY, WATER }
enum Crop { WHEAT, CORN, SUNFLOWER, LAVENDER, RICE, PASTURE }
enum Road { NONE, STREET, MAIN }

const LOTS_AROUND := 48
const LOTS_ALONG := 80
# Lots per interior terrain chunk (16 x 20 chunks per section).
const CHUNK_LOTS_AROUND := 3
const CHUNK_LOTS_ALONG := 4
const MAIN_ROAD_WIDTH := 12.0
const STREET_WIDTH := 8.0

var section_index := 0
var radius := 0.0
var length := 0.0
var lot_width := 0.0
var lot_length := 0.0
# Per lot, index along * LOTS_AROUND + around.
var zones := PackedByteArray()
var crops := PackedByteArray()
var rows_along := PackedByteArray()
# Road on each lot's low-x (west) and low-z (south) edge.
var road_west := PackedByteArray()
var road_south := PackedByteArray()
var city_center := Vector2.ZERO
# Buildings: one entry per index across the parallel arrays.
var building_x := PackedFloat64Array()
var building_z := PackedFloat64Array()
# (width around, height, depth along), whole metres.
var building_size := PackedVector3Array()
var building_color := PackedColorArray()
var building_lot := PackedInt32Array()

static func road_width(road: int) -> float:
	if road == Road.MAIN:
		return MAIN_ROAD_WIDTH
	if road == Road.STREET:
		return STREET_WIDTH
	return 0.0

func lot_index(around: int, along: int) -> int:
	return along * LOTS_AROUND + posmod(around, LOTS_AROUND)

func zone_at(around: int, along: int) -> int:
	return zones[lot_index(around, along)]

func lot_center(around: int, along: int) -> Vector2:
	return Vector2((around + 0.5) * lot_width, (along + 0.5) * lot_length)

func circumference() -> float:
	return LOTS_AROUND * lot_width

# Distance on the surface; around the section, the shorter way round.
func surface_distance(a: Vector2, b: Vector2) -> float:
	var dx: float = absf(a.x - b.x)
	dx = minf(dx, circumference() - dx)
	return Vector2(dx, a.y - b.y).length()

# A lot's east edge is its east neighbour's west edge; its north edge is its
# north neighbour's south edge (none past the section's far end).
func road_on_west(around: int, along: int) -> int:
	return road_west[lot_index(around, along)]

func road_on_east(around: int, along: int) -> int:
	return road_west[lot_index(around + 1, along)]

func road_on_south(around: int, along: int) -> int:
	return road_south[lot_index(around, along)]

func road_on_north(around: int, along: int) -> int:
	if along + 1 >= LOTS_ALONG:
		return Road.NONE
	return road_south[lot_index(around, along + 1)]

func building_count() -> int:
	return building_x.size()

# Building indices per interior chunk: Vector2i(chunk_around, chunk_along) -> Array.
@warning_ignore("integer_division")
func group_buildings_by_chunk() -> Dictionary:
	var groups := {}
	for b in range(building_count()):
		var lot: int = building_lot[b]
		var key := Vector2i((lot % LOTS_AROUND) / CHUNK_LOTS_AROUND, (lot / LOTS_AROUND) / CHUNK_LOTS_ALONG)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(b)
	return groups
```

Create `scripts/section_generator.gd`:

```gdscript
extends RefCounted

# Builds the plan of one section's inner surface from the section's index
# alone: same index, same plan, every time (piece C regenerates sections as
# the player travels). Packed arrays are built in locals and assigned whole.

const SectionPlanScript = preload("res://scripts/section_plan.gd")

const WATER_SHARE := 0.10
const TOWN_SHARE := 0.15
const ZONE_FEATURE_SIZE := 2500.0
const CROP_FEATURE_SIZE := 800.0
# Crop bands per unit of noise: neighbouring patches get different crops.
const CROP_BANDS := 9.0
const CITY_RADIUS := 700.0
# Share of the length, from each end, the city centre keeps away from.
const CITY_END_MARGIN := 0.2

static func generate(section_index: int, radius: float, length: float):
	var plan = SectionPlanScript.new()
	plan.section_index = section_index
	plan.radius = radius
	plan.length = length
	plan.lot_width = TAU * radius / SectionPlanScript.LOTS_AROUND
	plan.lot_length = length / SectionPlanScript.LOTS_ALONG
	plan.zones = _zones_from_noise(plan)
	plan.city_center = _city_center(plan)
	plan.zones = _with_city(plan, plan.zones)
	plan.crops = _crops(plan)
	plan.rows_along = _rows(plan)
	return plan

# Noise sampled at the lot centre's 3D position on the cylinder, so zones join
# up seamlessly where the way round closes.
static func _lot_point(plan, around: int, along: int) -> Vector3:
	var angle: float = TAU * (around + 0.5) / SectionPlanScript.LOTS_AROUND
	return Vector3(cos(angle) * plan.radius, sin(angle) * plan.radius, (along + 0.5) * plan.lot_length)

static func _sample_lots(plan, noise: FastNoiseLite) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			values.append(noise.get_noise_3dv(_lot_point(plan, around, along)))
	return values

static func _zones_from_noise(plan) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = plan.section_index
	noise.frequency = 1.0 / ZONE_FEATURE_SIZE
	var values := _sample_lots(plan, noise)
	# Thresholds from the values themselves: exactly the lowest share is
	# water and the highest share is town, whatever the noise's spread.
	var sorted := values.duplicate()
	sorted.sort()
	var count := values.size()
	var water_below: float = sorted[int(count * WATER_SHARE)]
	var town_above: float = sorted[count - 1 - int(count * TOWN_SHARE)]
	var zones := PackedByteArray()
	for value in values:
		if value < water_below:
			zones.append(SectionPlanScript.Zone.WATER)
		elif value > town_above:
			zones.append(SectionPlanScript.Zone.TOWN)
		else:
			zones.append(SectionPlanScript.Zone.FIELD)
	return zones

static func _city_center(plan) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.section_index, "city"])
	var around := rng.randi_range(0, SectionPlanScript.LOTS_AROUND - 1)
	var along := rng.randi_range(int(SectionPlanScript.LOTS_ALONG * CITY_END_MARGIN), int(SectionPlanScript.LOTS_ALONG * (1.0 - CITY_END_MARGIN)) - 1)
	return plan.lot_center(around, along)

static func _with_city(plan, zones: PackedByteArray) -> PackedByteArray:
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			if plan.surface_distance(plan.lot_center(around, along), plan.city_center) <= CITY_RADIUS:
				zones[plan.lot_index(around, along)] = SectionPlanScript.Zone.CITY
	return zones

static func _crops(plan) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = plan.section_index + 7919
	noise.frequency = 1.0 / CROP_FEATURE_SIZE
	var crop_count: int = SectionPlanScript.Crop.size()
	var crops := PackedByteArray()
	for value in _sample_lots(plan, noise):
		crops.append(posmod(floori((value + 1.0) * CROP_BANDS), crop_count))
	return crops

static func _rows(plan) -> PackedByteArray:
	var rows := PackedByteArray()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([plan.section_index, around, along, "rows"])
			rows.append(rng.randi_range(0, 1))
	return rows
```

- [ ] **Step 4: Run to verify it passes.** If `_test_every_crop_appears` fails on a count, lower-bound only (a crop missing entirely is the real failure): record a `Ruling:` before changing the threshold.
- [ ] **Step 5: Full suite.**
- [ ] **Step 6: Commit**

```bash
git add scripts/section_plan.gd scripts/section_generator.gd tests/test_section_generator.gd
git commit -m "$(cat <<'EOF'
Add the section plan and generate zones, city centre and crops

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Roads and buildings in the generator

**Files:**
- Modify: `scripts/section_generator.gd`, `tests/test_section_generator.gd`

**Interfaces:**
- Consumes: Task 1.
- Produces: `generate()` now also fills `road_west`, `road_south` and the building arrays. Generator consts `TOWER_RADIUS := 250.0`, `LOT_MARGIN := 10.0`, footprint/height ranges as in the spec.

- [ ] **Step 1: Write the failing tests**

In `tests/test_section_generator.gd` add after `failures += _test_surface_distance_wraps_around()`:

```gdscript
	failures += _test_no_road_touches_water()
	failures += _test_road_kinds()
	failures += _test_buildings_only_in_towns_and_city()
	failures += _test_buildings_stay_inside_their_lot_clear_of_roads()
	failures += _test_building_sizes_match_their_zone()
	failures += _test_towers_only_near_the_city_centre()
	failures += _test_buildings_do_not_overlap()
	failures += _test_group_buildings_by_chunk_covers_every_building_once()
```

and append:

```gdscript
func _is_built(zone: int) -> bool:
	return zone == SectionPlan.Zone.TOWN or zone == SectionPlan.Zone.CITY

func _test_no_road_touches_water() -> int:
	for along in range(80):
		for around in range(48):
			if _plan.zone_at(around, along) != SectionPlan.Zone.WATER:
				continue
			if _plan.road_on_west(around, along) + _plan.road_on_east(around, along) + _plan.road_on_south(around, along) + _plan.road_on_north(around, along) != 0:
				print("FAIL _test_no_road_touches_water: lake lot (%d, %d) has a road on an edge" % [around, along])
				return 1
	return 0

func _expected_road(zone_a: int, zone_b: int, on_chunk_border: bool) -> int:
	if zone_a == SectionPlan.Zone.WATER or zone_b == SectionPlan.Zone.WATER:
		return SectionPlan.Road.NONE
	if on_chunk_border:
		return SectionPlan.Road.MAIN
	if _is_built(zone_a) or _is_built(zone_b):
		return SectionPlan.Road.STREET
	return SectionPlan.Road.NONE

func _test_road_kinds() -> int:
	# West edges include lot 0's, shared with lot 47 across the seam.
	for along in range(80):
		for around in range(48):
			var zone: int = _plan.zone_at(around, along)
			var west := _expected_road(zone, _plan.zone_at(around - 1, along), around % 3 == 0)
			var south := SectionPlan.Road.NONE if along == 0 else _expected_road(zone, _plan.zone_at(around, along - 1), along % 4 == 0)
			if _plan.road_on_west(around, along) != west or _plan.road_on_south(around, along) != south:
				print("FAIL _test_road_kinds: lot (%d, %d) west %d (expected %d) south %d (expected %d)" % [around, along, _plan.road_on_west(around, along), west, _plan.road_on_south(around, along), south])
				return 1
	return 0

func _test_buildings_only_in_towns_and_city() -> int:
	if _plan.building_count() < 5000:
		print("FAIL _test_buildings_only_in_towns_and_city: only %d buildings" % _plan.building_count())
		return 1
	for b in range(_plan.building_count()):
		if not _is_built(_plan.zones[_plan.building_lot[b]]):
			print("FAIL _test_buildings_only_in_towns_and_city: building %d stands on a field or lake lot" % b)
			return 1
	return 0

func _test_buildings_stay_inside_their_lot_clear_of_roads() -> int:
	# Clear of the widest road: half of 12 m on each side of a lot edge.
	var clearance := 6.0
	for b in range(_plan.building_count()):
		var lot: int = _plan.building_lot[b]
		var x0: float = (lot % 48) * _plan.lot_width
		var z0: float = floori(lot / 48.0) * _plan.lot_length
		var size: Vector3 = _plan.building_size[b]
		var left: float = _plan.building_x[b] - size.x * 0.5
		var right: float = _plan.building_x[b] + size.x * 0.5
		var near: float = _plan.building_z[b] - size.z * 0.5
		var far: float = _plan.building_z[b] + size.z * 0.5
		if left < x0 + clearance or right > x0 + _plan.lot_width - clearance or near < z0 + clearance or far > z0 + _plan.lot_length - clearance:
			print("FAIL _test_buildings_stay_inside_their_lot_clear_of_roads: building %d spans x %f..%f z %f..%f in lot x %f.. z %f.." % [b, left, right, near, far, x0, z0])
			return 1
	return 0

func _is_whole(value: float) -> bool:
	return is_equal_approx(value, roundf(value))

func _in_range(value: float, low: float, high: float) -> bool:
	return value >= low - 0.001 and value <= high + 0.001

func _test_building_sizes_match_their_zone() -> int:
	for b in range(_plan.building_count()):
		var lot: int = _plan.building_lot[b]
		var size: Vector3 = _plan.building_size[b]
		var ok := _is_whole(size.x) and _is_whole(size.y) and _is_whole(size.z)
		if _plan.zones[lot] == SectionPlan.Zone.TOWN:
			ok = ok and _in_range(size.y, 8.0, 40.0) and _in_range(size.x, 12.0, 25.0) and _in_range(size.z, 12.0, 25.0)
		elif size.y >= 150.0:
			ok = ok and _in_range(size.y, 150.0, 300.0) and _in_range(size.x, 25.0, 45.0) and _in_range(size.z, 25.0, 45.0)
		else:
			ok = ok and _in_range(size.y, 40.0, 120.0) and _in_range(size.x, 30.0, 60.0) and _in_range(size.z, 30.0, 60.0)
		if not ok:
			print("FAIL _test_building_sizes_match_their_zone: building %d size %s in a zone-%d lot" % [b, size, _plan.zones[lot]])
			return 1
	return 0

func _test_towers_only_near_the_city_centre() -> int:
	var towers := 0
	for b in range(_plan.building_count()):
		var lot: int = _plan.building_lot[b]
		if _plan.zones[lot] != SectionPlan.Zone.CITY:
			continue
		var center: Vector2 = _plan.lot_center(lot % 48, floori(lot / 48.0))
		var near: bool = _plan.surface_distance(center, _plan.city_center) <= 250.0
		var tower: bool = _plan.building_size[b].y >= 150.0
		if tower:
			towers += 1
		if near != tower:
			print("FAIL _test_towers_only_near_the_city_centre: building %d tower=%s, lot within 250 m=%s" % [b, tower, near])
			return 1
	if towers == 0:
		print("FAIL _test_towers_only_near_the_city_centre: no towers at all")
		return 1
	return 0

func _test_buildings_do_not_overlap() -> int:
	var by_lot := {}
	for b in range(_plan.building_count()):
		var lot: int = _plan.building_lot[b]
		if not by_lot.has(lot):
			by_lot[lot] = []
		by_lot[lot].append(b)
	for lot in by_lot:
		var list: Array = by_lot[lot]
		for i in range(list.size()):
			for j in range(i + 1, list.size()):
				var a: int = list[i]
				var c: int = list[j]
				var dx: float = absf(_plan.building_x[a] - _plan.building_x[c])
				var dz: float = absf(_plan.building_z[a] - _plan.building_z[c])
				if dx < (_plan.building_size[a].x + _plan.building_size[c].x) * 0.5 and dz < (_plan.building_size[a].z + _plan.building_size[c].z) * 0.5:
					print("FAIL _test_buildings_do_not_overlap: buildings %d and %d overlap in lot %d" % [a, c, lot])
					return 1
	return 0

func _test_group_buildings_by_chunk_covers_every_building_once() -> int:
	var groups: Dictionary = _plan.group_buildings_by_chunk()
	var seen := {}
	for key in groups:
		for b in groups[key]:
			var lot: int = _plan.building_lot[b]
			var expected := Vector2i(floori((lot % 48) / 3.0), floori(floori(lot / 48.0) / 4.0))
			if key != expected or seen.has(b):
				print("FAIL _test_group_buildings_by_chunk_covers_every_building_once: building %d under %s (expected %s, seen before %s)" % [b, key, expected, seen.has(b)])
				return 1
			seen[b] = true
	if seen.size() != _plan.building_count():
		print("FAIL _test_group_buildings_by_chunk_covers_every_building_once: %d of %d buildings grouped" % [seen.size(), _plan.building_count()])
		return 1
	return 0
```

- [ ] **Step 2: Run to verify it fails** — Expected `FAIL` lines: `_test_road_kinds` (all roads NONE today) and `_test_buildings_only_in_towns_and_city: only 0 buildings`, and others on empty data.

- [ ] **Step 3: Implement** in `scripts/section_generator.gd`:

Add after `const CITY_END_MARGIN := 0.2`:

```gdscript
const TOWER_RADIUS := 250.0
# Buildings keep this far from every lot edge: clear of the widest road
# (6 m on each side of an edge) with room to spare.
const LOT_MARGIN := 10.0
# Gap between a building and the edge of its plot.
const PLOT_CLEARANCE := 2.0
const TOWN_PLOTS := 5
const CITY_PLOTS := 3
const TOWN_BUILD_CHANCE := 0.8
const TOWN_FOOTPRINT := Vector2(12.0, 25.0)
const TOWN_HEIGHT := Vector2(8.0, 40.0)
const CITY_FOOTPRINT := Vector2(30.0, 60.0)
const CITY_HEIGHT := Vector2(40.0, 120.0)
const TOWER_FOOTPRINT := Vector2(25.0, 45.0)
const TOWER_HEIGHT := Vector2(150.0, 300.0)
const TOWN_COLORS := [Color(0.93, 0.9, 0.82), Color(0.9, 0.8, 0.65), Color(0.85, 0.7, 0.6), Color(0.8, 0.85, 0.88), Color(0.95, 0.93, 0.9)]
const CITY_COLORS := [Color(0.7, 0.75, 0.8), Color(0.6, 0.62, 0.66), Color(0.78, 0.78, 0.74), Color(0.5, 0.58, 0.66)]
```

In `generate()`, before `return plan`:

```gdscript
	var roads: Array = _roads(plan)
	plan.road_west = roads[0]
	plan.road_south = roads[1]
	_place_buildings(plan)
```

Append:

```gdscript
static func _is_built(zone: int) -> bool:
	return zone == SectionPlanScript.Zone.TOWN or zone == SectionPlanScript.Zone.CITY

# No road next to a lake; a main road on every chunk border; a street next to
# a town or the city; nothing between two fields.
static func _edge_road(zone_a: int, zone_b: int, on_chunk_border: bool) -> int:
	if zone_a == SectionPlanScript.Zone.WATER or zone_b == SectionPlanScript.Zone.WATER:
		return SectionPlanScript.Road.NONE
	if on_chunk_border:
		return SectionPlanScript.Road.MAIN
	if _is_built(zone_a) or _is_built(zone_b):
		return SectionPlanScript.Road.STREET
	return SectionPlanScript.Road.NONE

static func _roads(plan) -> Array:
	var west := PackedByteArray()
	var south := PackedByteArray()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var zone: int = plan.zone_at(around, along)
			west.append(_edge_road(zone, plan.zone_at(around - 1, along), around % SectionPlanScript.CHUNK_LOTS_AROUND == 0))
			if along == 0:
				# The section's end wall: no road.
				south.append(SectionPlanScript.Road.NONE)
			else:
				south.append(_edge_road(zone, plan.zone_at(around, along - 1), along % SectionPlanScript.CHUNK_LOTS_ALONG == 0))
	return [west, south]

static func _place_buildings(plan) -> void:
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var sizes := PackedVector3Array()
	var colors := PackedColorArray()
	var lots := PackedInt32Array()
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var zone: int = plan.zone_at(around, along)
			var plots: int
			var chance: float
			var footprint: Vector2
			var heights: Vector2
			var palette: Array
			if zone == SectionPlanScript.Zone.TOWN:
				plots = TOWN_PLOTS
				chance = TOWN_BUILD_CHANCE
				footprint = TOWN_FOOTPRINT
				heights = TOWN_HEIGHT
				palette = TOWN_COLORS
			elif zone == SectionPlanScript.Zone.CITY:
				var tower: bool = plan.surface_distance(plan.lot_center(around, along), plan.city_center) <= TOWER_RADIUS
				plots = CITY_PLOTS
				chance = 1.0
				footprint = TOWER_FOOTPRINT if tower else CITY_FOOTPRINT
				heights = TOWER_HEIGHT if tower else CITY_HEIGHT
				palette = CITY_COLORS
			else:
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([plan.section_index, around, along])
			var plot_width: float = (plan.lot_width - 2.0 * LOT_MARGIN) / plots
			var plot_depth: float = (plan.lot_length - 2.0 * LOT_MARGIN) / plots
			for plot_x in range(plots):
				for plot_z in range(plots):
					if rng.randf() >= chance:
						continue
					var width: float = minf(roundf(rng.randf_range(footprint.x, footprint.y)), floorf(plot_width - 2.0 * PLOT_CLEARANCE))
					var depth: float = minf(roundf(rng.randf_range(footprint.x, footprint.y)), floorf(plot_depth - 2.0 * PLOT_CLEARANCE))
					# Squaring the random number: many low buildings, a few tall.
					var height: float = roundf(lerpf(heights.x, heights.y, pow(rng.randf(), 2.0)))
					var plot_x0: float = around * plan.lot_width + LOT_MARGIN + plot_x * plot_width
					var plot_z0: float = along * plan.lot_length + LOT_MARGIN + plot_z * plot_depth
					xs.append(plot_x0 + rng.randf_range(PLOT_CLEARANCE + width * 0.5, plot_width - PLOT_CLEARANCE - width * 0.5))
					zs.append(plot_z0 + rng.randf_range(PLOT_CLEARANCE + depth * 0.5, plot_depth - PLOT_CLEARANCE - depth * 0.5))
					sizes.append(Vector3(width, height, depth))
					colors.append(palette[rng.randi_range(0, palette.size() - 1)])
					lots.append(plan.lot_index(around, along))
	plan.building_x = xs
	plan.building_z = zs
	plan.building_size = sizes
	plan.building_color = colors
	plan.building_lot = lots
```

- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Full suite.**
- [ ] **Step 6: Commit**

```bash
git add scripts/section_generator.gd tests/test_section_generator.gd
git commit -m "$(cat <<'EOF'
Generate roads and buildings: towns, city blocks and towers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Ground mosaic geometry

**Files:**
- Create: `scripts/terrain_dressing.gd`, `tests/test_terrain_dressing.gd`

**Interfaces:**
- Consumes: plan (Tasks 1–2).
- Produces `terrain_dressing.gd` (instantiate once, reuse for all chunks): consts `CROP_COLORS` (indexed by `Crop`), `TOWN_GROUND_COLOR`, `CITY_GROUND_COLOR`, `MAIN_ROAD_COLOR`, `STREET_COLOR`, `WATER_COLOR`; vars `field_material`, `paved_material`, `water_material`, `building_material`; `static func cell_road(column: int, row: int, west: int, east: int, south: int, north: int) -> int`; `func dress_chunk(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int, building_indices: Array) -> void` — adds `Surface` (`MeshInstance3D`, fields surface then paved surface, each only if non-empty) and `Water` (`MeshInstance3D`, only if the chunk has a lake lot). Buildings come in Task 4 (this task names the parameter `_building_indices`).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_terrain_dressing.gd`:

```gdscript
extends SceneTree

const SectionGenerator = preload("res://scripts/section_generator.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")
const TerrainDressing = preload("res://scripts/terrain_dressing.gd")

const RADIUS := 2000.0

var _plan = SectionGenerator.generate(42, RADIUS, 20000.0)
var _dressing = TerrainDressing.new()
var _groups: Dictionary = _plan.group_buildings_by_chunk()

func _init():
	var failures := 0
	failures += _test_cell_road_picks_edges_and_crossings()
	failures += _test_ground_vertices_at_level_zero_facing_the_axis()
	failures += _test_ground_area_is_the_chunk_area()
	failures += _test_water_only_where_the_plan_has_lakes()
	failures += _test_road_colours_where_the_plan_has_roads()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _chunk_has_zone(key: Vector2i, zone: int) -> bool:
	for lot_x in range(3):
		for lot_z in range(4):
			if _plan.zone_at(key.x * 3 + lot_x, key.y * 4 + lot_z) == zone:
				return true
	return false

func _find_chunk(zone: int, wanted: bool) -> Vector2i:
	for along in range(20):
		for around in range(16):
			var key := Vector2i(around, along)
			if _chunk_has_zone(key, zone) == wanted:
				return key
	return Vector2i(-1, -1)

func _dress(key: Vector2i) -> StaticBody3D:
	var chunk := StaticBody3D.new()
	_dressing.dress_chunk(chunk, _plan, key.x, key.y, _groups.get(key, []))
	return chunk

func _ground_meshes(chunk: Node) -> Array:
	var meshes := []
	for part in ["Surface", "Water"]:
		var node := chunk.get_node_or_null(part) as MeshInstance3D
		if node:
			meshes.append(node.mesh)
	return meshes

func _test_cell_road_picks_edges_and_crossings() -> int:
	var main: int = SectionPlan.Road.MAIN
	var street: int = SectionPlan.Road.STREET
	var none: int = SectionPlan.Road.NONE
	var cases := [
		[1, 1, none],      # centre: never road
		[0, 1, main],      # west band
		[2, 1, street],    # east band
		[1, 0, street],    # south band
		[1, 2, none],      # north band
		[0, 0, main],      # south-west crossing: the bigger road wins
	]
	for c in cases:
		var got: int = TerrainDressing.cell_road(c[0], c[1], main, street, street, none)
		if got != c[2]:
			print("FAIL _test_cell_road_picks_edges_and_crossings: cell (%d, %d) got %d expected %d" % [c[0], c[1], got, c[2]])
			return 1
	return 0

func _test_ground_vertices_at_level_zero_facing_the_axis() -> int:
	var chunk := _dress(_find_chunk(SectionPlan.Zone.WATER, true))
	var result := 0
	for mesh: Mesh in _ground_meshes(chunk):
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(vertices.size()):
				var v: Vector3 = vertices[i]
				if absf(Vector2(v.x, v.y).length() - RADIUS) > 0.001 or normals[i].dot(Vector3(-v.x, -v.y, 0.0)) <= 0.0:
					print("FAIL _test_ground_vertices_at_level_zero_facing_the_axis: vertex %s normal %s" % [v, normals[i]])
					chunk.free()
					return 1
	chunk.free()
	return result

func _triangle_area(mesh: Mesh) -> float:
	var area := 0.0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			var a: Vector3 = vertices[indices[t]]
			area += (vertices[indices[t + 1]] - a).cross(vertices[indices[t + 2]] - a).length() * 0.5
	return area

func _test_ground_area_is_the_chunk_area() -> int:
	# A mosaic with no gaps and no overlaps covers exactly the chunk (chords
	# are ~0.01% shorter than arcs). An overlap adds area; a gap removes it.
	var result := 0
	for key in [_find_chunk(SectionPlan.Zone.WATER, true), _find_chunk(SectionPlan.Zone.TOWN, true), _find_chunk(SectionPlan.Zone.CITY, true)]:
		var chunk := _dress(key)
		var area := 0.0
		for mesh: Mesh in _ground_meshes(chunk):
			area += _triangle_area(mesh)
		var expected: float = 3.0 * _plan.lot_width * 4.0 * _plan.lot_length
		if absf(area - expected) > expected * 0.001:
			print("FAIL _test_ground_area_is_the_chunk_area: chunk %s covers %.1f m2, expected %.1f" % [key, area, expected])
			result = 1
		chunk.free()
	return result

func _test_water_only_where_the_plan_has_lakes() -> int:
	var wet := _dress(_find_chunk(SectionPlan.Zone.WATER, true))
	var dry := _dress(_find_chunk(SectionPlan.Zone.WATER, false))
	var result := 0
	if wet.get_node_or_null("Water") == null or dry.get_node_or_null("Water") != null:
		print("FAIL _test_water_only_where_the_plan_has_lakes: water node present in the dry chunk or missing in the wet one")
		result = 1
	if dry.get_node_or_null("Surface") == null:
		print("FAIL _test_water_only_where_the_plan_has_lakes: dry chunk has no Surface")
		result = 1
	wet.free()
	dry.free()
	return result

func _has_color(mesh: Mesh, color: Color) -> bool:
	for s in range(mesh.get_surface_count()):
		for c in mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]:
			if c.is_equal_approx(color):
				return true
	return false

func _test_road_colours_where_the_plan_has_roads() -> int:
	# A town chunk has streets; every chunk border that is not by a lake has a
	# main road, so a dry chunk shows the main-road colour.
	var chunk := _dress(_find_chunk(SectionPlan.Zone.TOWN, true))
	var result := 0
	var surface: Mesh = (chunk.get_node("Surface") as MeshInstance3D).mesh
	if not _has_color(surface, TerrainDressing.STREET_COLOR) or not _has_color(surface, TerrainDressing.MAIN_ROAD_COLOR):
		print("FAIL _test_road_colours_where_the_plan_has_roads: town chunk lacks street or main-road colour")
		result = 1
	chunk.free()
	return result
```

- [ ] **Step 2: Run to verify it fails** — `Parse Error` (preload of `terrain_dressing.gd`).

- [ ] **Step 3: Implement** — create `scripts/terrain_dressing.gd`:

```gdscript
extends RefCounted

# Turns a section plan into geometry, one interior terrain chunk at a time,
# in the chunk's own frame (InteriorWorld turns each chunk about Z and shifts
# it along Z). The ground is a mosaic at level 0 with no overlapping layers:
# with the interior camera (near 0.2 m, far 60 km) the depth buffer cannot
# separate surfaces less than a metre apart at 2 km, so layers would flicker.

const SectionPlanScript = preload("res://scripts/section_plan.gd")

const CROP_COLORS := [
	Color(0.85, 0.72, 0.3),   # wheat
	Color(0.25, 0.45, 0.15),  # corn
	Color(0.95, 0.75, 0.1),   # sunflower
	Color(0.55, 0.45, 0.8),   # lavender
	Color(0.5, 0.75, 0.35),   # rice
	Color(0.45, 0.55, 0.3),   # pasture
]
const TOWN_GROUND_COLOR := Color(0.62, 0.6, 0.55)
const CITY_GROUND_COLOR := Color(0.5, 0.5, 0.52)
const MAIN_ROAD_COLOR := Color(0.2, 0.2, 0.22)
const STREET_COLOR := Color(0.32, 0.32, 0.34)
const WATER_COLOR := Color(0.12, 0.32, 0.5)

# Vertex data for one mesh surface. Kept as a class so its packed arrays are
# mutated in place (packed arrays are values).
class MeshArrays:
	const ROW_SPACING := 5.0
	# Longest arc of one flat quad: it strays at most ~0.5 m from the curve.
	const ARC_STEP := 90.0

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func is_empty() -> bool:
		return vertices.is_empty()

	# A rectangle of the inner wall, x0..x1 around (arc metres) and z0..z1
	# along, facing the axis. UVs count filari: along z or around.
	func add_patch(radius: float, x0: float, x1: float, z0: float, z1: float, color: Color, rows_along: bool) -> void:
		var steps: int = maxi(1, ceili((x1 - x0) / ARC_STEP))
		var base: int = vertices.size()
		for s in range(steps + 1):
			var x: float = lerpf(x0, x1, float(s) / steps)
			var angle: float = x / radius
			var inward := Vector3(-cos(angle), -sin(angle), 0.0)
			for z: float in [z0, z1]:
				vertices.append(Vector3(cos(angle) * radius, sin(angle) * radius, z))
				normals.append(inward)
				colors.append(color)
				uvs.append(Vector2(x, z) / ROW_SPACING if rows_along else Vector2(z, x) / ROW_SPACING)
		# Same winding as the interior terrain: the front faces the axis.
		for s in range(steps):
			var p00: int = base + s * 2
			indices.append_array(PackedInt32Array([p00, p00 + 2, p00 + 1, p00 + 2, p00 + 3, p00 + 1]))

	func to_arrays() -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		return arrays

var field_material: StandardMaterial3D
var paved_material: StandardMaterial3D
var water_material: StandardMaterial3D

func _init() -> void:
	field_material = StandardMaterial3D.new()
	field_material.vertex_color_use_as_albedo = true
	field_material.albedo_texture = _stripe_texture()
	field_material.roughness = 0.95
	paved_material = StandardMaterial3D.new()
	paved_material.vertex_color_use_as_albedo = true
	paved_material.roughness = 0.9
	water_material = StandardMaterial3D.new()
	water_material.albedo_color = WATER_COLOR
	water_material.roughness = 0.1
	water_material.metallic = 0.3

func dress_chunk(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int, _building_indices: Array) -> void:
	_build_ground(chunk, plan, chunk_around, chunk_along)

# Which road a lot cell carries. The lot is split 3 x 3 by its edge roads:
# column 0 is the west band, 2 the east band; row 0 south, 2 north. The
# centre is never road; a corner is a crossing of its two edges' roads.
static func cell_road(column: int, row: int, west: int, east: int, south: int, north: int) -> int:
	var column_road: int = west if column == 0 else (east if column == 2 else SectionPlanScript.Road.NONE)
	var row_road: int = south if row == 0 else (north if row == 2 else SectionPlanScript.Road.NONE)
	if column == 1:
		return row_road
	if row == 1:
		return column_road
	return maxi(column_road, row_road)

func _build_ground(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int) -> void:
	var fields := MeshArrays.new()
	var paved := MeshArrays.new()
	var water := MeshArrays.new()
	for lot_x in range(SectionPlanScript.CHUNK_LOTS_AROUND):
		for lot_z in range(SectionPlanScript.CHUNK_LOTS_ALONG):
			var around: int = chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND + lot_x
			var along: int = chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG + lot_z
			var x0: float = lot_x * plan.lot_width
			var x1: float = x0 + plan.lot_width
			var z0: float = lot_z * plan.lot_length
			var z1: float = z0 + plan.lot_length
			var zone: int = plan.zone_at(around, along)
			if zone == SectionPlanScript.Zone.WATER:
				water.add_patch(plan.radius, x0, x1, z0, z1, WATER_COLOR, true)
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
						paved.add_patch(plan.radius, cx0, cx1, cz0, cz1, MAIN_ROAD_COLOR, true)
					elif road == SectionPlanScript.Road.STREET:
						paved.add_patch(plan.radius, cx0, cx1, cz0, cz1, STREET_COLOR, true)
					elif zone == SectionPlanScript.Zone.FIELD:
						fields.add_patch(plan.radius, cx0, cx1, cz0, cz1, CROP_COLORS[plan.crops[lot]], plan.rows_along[lot] == 1)
					else:
						paved.add_patch(plan.radius, cx0, cx1, cz0, cz1, TOWN_GROUND_COLOR if zone == SectionPlanScript.Zone.TOWN else CITY_GROUND_COLOR, true)
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

# One filare per repeat: a lighter band and a darker furrow.
static func _stripe_texture() -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for x in range(16):
		var shade := 1.0 if x < 11 else 0.55
		for y in range(16):
			image.set_pixel(x, y, Color(shade, shade, shade))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
```

- [ ] **Step 4: Run to verify it passes.** A failing area check means an overlap or a gap: debug the cell edges before touching the tolerance.
- [ ] **Step 5: Full suite.**
- [ ] **Step 6: Commit**

```bash
git add scripts/terrain_dressing.gd tests/test_terrain_dressing.gd
git commit -m "$(cat <<'EOF'
Dress chunks with a level-0 ground mosaic: fields, paving, roads, lakes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Buildings and their colliders

**Files:**
- Modify: `scripts/terrain_dressing.gd`, `tests/test_terrain_dressing.gd`

**Interfaces:**
- Consumes: Task 3.
- Produces: `static func building_transform(radius: float, x: float, z: float, size: Vector3) -> Transform3D` (unit box scaled to `size`, base on the wall, "up" toward the axis); `dress_chunk` now also adds `Buildings` (`MultiMeshInstance3D`, `custom_aabb` set, `visibility_range_end` 12000) and one shape owner per building on the chunk body; var `building_material`; consts `WINDOW_SPACING := 4.0`, `WINDOW_GLOW_COLOR`, `BUILDING_VISIBILITY_END := 12000.0`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_terrain_dressing.gd` add after `failures += _test_road_colours_where_the_plan_has_roads()`:

```gdscript
	failures += _test_building_transform_stands_on_the_wall_facing_the_axis()
	failures += _test_chunk_buildings_match_the_plan()
	failures += _test_building_colliders_match_the_drawn_buildings()
	failures += _test_building_bounds_cover_the_tallest_building()
```

and append:

```gdscript
func _busiest_chunk() -> Vector2i:
	var best := Vector2i.ZERO
	var most := 0
	for key in _groups:
		if _groups[key].size() > most:
			most = _groups[key].size()
			best = key
	return best

func _test_building_transform_stands_on_the_wall_facing_the_axis() -> int:
	var size := Vector3(20.0, 60.0, 30.0)
	var x := 700.0
	var xform: Transform3D = TerrainDressing.building_transform(RADIUS, x, 400.0, size)
	var angle := x / RADIUS
	var up := Vector3(-cos(angle), -sin(angle), 0.0)
	var base: Vector3 = xform * Vector3(0.0, -0.5, 0.0)
	var result := 0
	if not base.is_equal_approx(Vector3(cos(angle) * RADIUS, sin(angle) * RADIUS, 400.0)):
		print("FAIL _test_building_transform_stands_on_the_wall_facing_the_axis: base at %s" % base)
		result = 1
	if not xform.basis.y.normalized().is_equal_approx(up) or not xform.basis.z.normalized().is_equal_approx(Vector3(0.0, 0.0, 1.0)):
		print("FAIL _test_building_transform_stands_on_the_wall_facing_the_axis: up %s along %s" % [xform.basis.y.normalized(), xform.basis.z.normalized()])
		result = 1
	if not Vector3(xform.basis.x.length(), xform.basis.y.length(), xform.basis.z.length()).is_equal_approx(size) or xform.basis.determinant() <= 0.0:
		print("FAIL _test_building_transform_stands_on_the_wall_facing_the_axis: scale %s (mirrored: %s)" % [Vector3(xform.basis.x.length(), xform.basis.y.length(), xform.basis.z.length()), xform.basis.determinant() <= 0.0])
		result = 1
	return result

func _test_chunk_buildings_match_the_plan() -> int:
	var key := _busiest_chunk()
	var indices: Array = _groups[key]
	var chunk := _dress(key)
	var result := 0
	var node := chunk.get_node_or_null("Buildings") as MultiMeshInstance3D
	if node == null or node.multimesh.instance_count != indices.size() or chunk.get_shape_owners().size() != indices.size():
		print("FAIL _test_chunk_buildings_match_the_plan: chunk %s expects %d buildings (instances %s, colliders %d)" % [key, indices.size(), str(node.multimesh.instance_count) if node else "none", chunk.get_shape_owners().size()])
		chunk.free()
		return 1
	for k in range(indices.size()):
		if not node.multimesh.get_instance_color(k).is_equal_approx(_plan.building_color[indices[k]]):
			print("FAIL _test_chunk_buildings_match_the_plan: instance %d colour differs from the plan" % k)
			result = 1
			break
	if node.visibility_range_end != TerrainDressing.BUILDING_VISIBILITY_END:
		print("FAIL _test_chunk_buildings_match_the_plan: visibility range %f" % node.visibility_range_end)
		result = 1
	chunk.free()
	return result

func _test_building_colliders_match_the_drawn_buildings() -> int:
	var key := _busiest_chunk()
	var indices: Array = _groups[key]
	var chunk := _dress(key)
	var node: MultiMeshInstance3D = chunk.get_node("Buildings")
	var owners: PackedInt32Array = chunk.get_shape_owners()
	var result := 0
	for k in range(indices.size()):
		var drawn: Transform3D = node.multimesh.get_instance_transform(k)
		var collider: Transform3D = chunk.shape_owner_get_transform(owners[k])
		var shape := chunk.shape_owner_get_shape(owners[k], 0) as BoxShape3D
		if not collider.is_equal_approx(drawn.orthonormalized()) or shape == null or not shape.size.is_equal_approx(_plan.building_size[indices[k]]):
			print("FAIL _test_building_colliders_match_the_drawn_buildings: building %d collider %s / %s vs drawn %s" % [indices[k], collider, str(shape.size) if shape else "none", drawn])
			result = 1
			break
	chunk.free()
	return result

func _test_building_bounds_cover_the_tallest_building() -> int:
	# Headless renderers report no MultiMesh bounds; custom_aabb must hold them.
	var key := _busiest_chunk()
	var chunk := _dress(key)
	var node: MultiMeshInstance3D = chunk.get_node("Buildings")
	var result := 0
	for k in range(node.multimesh.instance_count):
		var top: Vector3 = node.multimesh.get_instance_transform(k) * Vector3(0.0, 0.5, 0.0)
		if not node.custom_aabb.has_point(top):
			print("FAIL _test_building_bounds_cover_the_tallest_building: top %s outside %s" % [top, node.custom_aabb])
			result = 1
			break
	chunk.free()
	return result
```

- [ ] **Step 2: Run to verify it fails** — `SCRIPT ERROR ... Nonexistent function 'building_transform'` and `FAIL _test_chunk_buildings_match_the_plan`.

- [ ] **Step 3: Implement** in `scripts/terrain_dressing.gd`:

Add after `const WATER_COLOR := Color(0.12, 0.32, 0.5)`:

```gdscript
const WINDOW_SPACING := 4.0
const WINDOW_GLOW_COLOR := Color(1.0, 0.85, 0.55)
const BUILDING_VISIBILITY_END := 12000.0
```

Add the var `var building_material: StandardMaterial3D` and private vars after `var water_material: StandardMaterial3D`:

```gdscript
var building_material: StandardMaterial3D
var _box_mesh := BoxMesh.new()
var _box_shapes := {}
```

At the end of `_init()`:

```gdscript
	# Windows projected in world space: the same window size on a house and a
	# tower (a unit box stretched per building would stretch its UVs). The
	# instance colour tints the walls; a mask lights the panes.
	building_material = StandardMaterial3D.new()
	building_material.vertex_color_use_as_albedo = true
	building_material.albedo_texture = _window_texture(false)
	building_material.uv1_triplanar = true
	building_material.uv1_world_triplanar = true
	building_material.uv1_scale = Vector3.ONE / WINDOW_SPACING
	building_material.emission_enabled = true
	building_material.emission = WINDOW_GLOW_COLOR
	building_material.emission_energy_multiplier = 0.8
	building_material.emission_texture = _window_texture(true)
	building_material.roughness = 0.8
```

Replace `dress_chunk` with:

```gdscript
func dress_chunk(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int, building_indices: Array) -> void:
	_build_ground(chunk, plan, chunk_around, chunk_along)
	if not building_indices.is_empty():
		_build_buildings(chunk, plan, chunk_around, chunk_along, building_indices)
```

Add:

```gdscript
# A unit box scaled to size (width around, height, depth along), its base
# centred on the wall at (x, z) and its "up" toward the axis.
static func building_transform(radius: float, x: float, z: float, size: Vector3) -> Transform3D:
	var angle: float = x / radius
	var up := Vector3(-cos(angle), -sin(angle), 0.0)
	var around := Vector3(-sin(angle), cos(angle), 0.0)
	var base := Vector3(cos(angle) * radius, sin(angle) * radius, z)
	return Transform3D(Basis(around * size.x, up * size.y, Vector3(0.0, 0.0, size.z)), base + up * size.y * 0.5)

func _build_buildings(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int, indices: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _box_mesh
	multimesh.instance_count = indices.size()
	var chunk_x0: float = chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width
	var chunk_z0: float = chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length
	var tallest := 0.0
	for k in range(indices.size()):
		var b: int = indices[k]
		var size: Vector3 = plan.building_size[b]
		var xform := building_transform(plan.radius, plan.building_x[b] - chunk_x0, plan.building_z[b] - chunk_z0, size)
		multimesh.set_instance_transform(k, xform)
		multimesh.set_instance_color(k, plan.building_color[b])
		# Colliders straight on the chunk body: thousands of nodes would slow
		# docking down.
		var owner_id := chunk.create_shape_owner(chunk)
		chunk.shape_owner_add_shape(owner_id, _box_shape(size))
		chunk.shape_owner_set_transform(owner_id, xform.orthonormalized())
		tallest = maxf(tallest, size.y)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Buildings"
	instance.multimesh = multimesh
	instance.material_override = building_material
	instance.visibility_range_end = BUILDING_VISIBILITY_END
	instance.custom_aabb = _chunk_bounds(plan, tallest)
	chunk.add_child(instance)

# Boxes with the same (whole-metre) size share one shape.
func _box_shape(size: Vector3) -> BoxShape3D:
	var key := Vector3i(size)
	if not _box_shapes.has(key):
		var shape := BoxShape3D.new()
		shape.size = size
		_box_shapes[key] = shape
	return _box_shapes[key]

# The chunk's slice of wall up to its tallest building, in the chunk's frame.
func _chunk_bounds(plan, tallest: float) -> AABB:
	var span: float = SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width / plan.radius
	var chunk_length: float = SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length
	var bounds := AABB(Vector3(plan.radius, 0.0, 0.0), Vector3.ZERO)
	for step in range(9):
		var angle: float = span * step / 8.0
		for r: float in [plan.radius, plan.radius - tallest]:
			for z: float in [0.0, chunk_length]:
				bounds = bounds.expand(Vector3(cos(angle) * r, sin(angle) * r, z))
	return bounds.grow(1.0)

# One window per repeat. Albedo: white walls (tinted per building) with a
# darker pane. Glow mask: only the pane.
static func _window_texture(glow: bool) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for x in range(16):
		for y in range(16):
			var pane := x >= 4 and x < 12 and y >= 3 and y < 11
			var shade: float
			if glow:
				shade = 1.0 if pane else 0.0
			else:
				shade = 0.35 if pane else 1.0
			image.set_pixel(x, y, Color(shade, shade, shade))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
```

- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Full suite.**
- [ ] **Step 6: Commit**

```bash
git add scripts/terrain_dressing.gd tests/test_terrain_dressing.gd
git commit -m "$(cat <<'EOF'
Dress chunks with instanced buildings, lit windows and box colliders

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Sections built from their plans

**Files:**
- Modify: `scripts/interior_world.gd`, `tests/test_interior_world.gd`, `tests/test_interior_world_physics.gd`, `tests/test_internal_cruiser_physics.gd`

**Interfaces:**
- Consumes: `SectionGenerator.generate`, `TerrainDressing.dress_chunk`, plan accessors (Tasks 1–4).
- Produces on `interior_world.gd`: vars `behind_section_index := 0`, `ahead_section_index := 1` (set before `build()`); `func get_section_plan(side: float)` (`-1.0` ahead, `1.0` behind). Chunks keep `Collision` (shared trimesh) and gain `Surface`/`Water`/`Buildings` plus building shape owners; the old shared terrain `Mesh` child is gone.

- [ ] **Step 1: Write the failing tests**

In `tests/test_interior_world.gd`:

1. Replace `_test_two_sections_of_320_chunks_sharing_one_mesh_and_shape` (definition and its `failures +=` line) with `_test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape`:

```gdscript
func _test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape() -> int:
	var world := _make_world()
	var result := 0
	var first_shape: Shape3D = null
	for section_name in ["SectionAhead", "SectionBehind"]:
		var section := world.get_node_or_null(section_name)
		if section == null:
			print("FAIL _test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape: no %s" % section_name)
			result = 1
			continue
		var chunks := section.find_children("Chunk_*", "StaticBody3D", false, false)
		if chunks.size() != 320:
			print("FAIL _test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape: %s has %d chunks, expected 320" % [section_name, chunks.size()])
			result = 1
		for chunk in chunks:
			var shape: Shape3D = (chunk.get_node("Collision") as CollisionShape3D).shape
			if first_shape == null:
				first_shape = shape
			var dressed: bool = chunk.get_node_or_null("Surface") != null or chunk.get_node_or_null("Water") != null
			if shape != first_shape or not (shape is ConcavePolygonShape3D) or not dressed or chunk.get_node_or_null("Mesh") != null:
				print("FAIL _test_two_sections_of_320_dressed_chunks_sharing_one_collision_shape: %s/%s not dressed, still has the old Mesh, or does not share the trimesh shape" % [section_name, chunk.name])
				result = 1
				break
	world.free()
	return result
```

2. Make `_check_wall` walk every surface: replace its body's first three lines (`var arrays ... var normals ...`) and loop with a loop over `range(mesh.get_surface_count())` wrapping the existing per-vertex checks:

```gdscript
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
```

3. In `_test_terrain_vertices_on_the_wall_facing_the_axis`, check the chunk's dressed ground instead of `Mesh`:

```gdscript
func _test_terrain_vertices_on_the_wall_facing_the_axis() -> int:
	var world := _make_world()
	var chunk: Node3D = world.get_node("SectionAhead/Chunk_03_07")
	var result := 0
	for part in ["Surface", "Water"]:
		var node := chunk.get_node_or_null(part) as MeshInstance3D
		if node:
			result = maxi(result, _check_wall("_test_terrain_vertices_on_the_wall_facing_the_axis", node.mesh, chunk.transform, RADIUS))
	world.free()
	return result
```

4. Add to the failures list (after `failures += _test_axis_lights_reach_the_ground_without_distance_falloff()`):

```gdscript
	failures += _test_sections_come_from_their_indices()
	failures += _test_every_lit_object_gets_at_most_eight_lights()
	failures += _test_building_both_sections_takes_under_three_seconds()
```

and append:

```gdscript
func _world_transform(node: Node) -> Transform3D:
	var xform := Transform3D()
	var current := node
	while current != null and current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform

func _test_sections_come_from_their_indices() -> int:
	var world: Node3D = InteriorWorldScript.new()
	world.behind_section_index = 5
	world.ahead_section_index = 6
	world.build()
	var result := 0
	var behind = world.get_section_plan(1.0)
	var ahead = world.get_section_plan(-1.0)
	if behind.section_index != 5 or ahead.section_index != 6:
		print("FAIL _test_sections_come_from_their_indices: behind %d ahead %d, expected 5 and 6" % [behind.section_index, ahead.section_index])
		result = 1
	var groups: Dictionary = ahead.group_buildings_by_chunk()
	var key: Vector2i = groups.keys()[0]
	var buildings := world.get_node("SectionAhead/Chunk_%02d_%02d/Buildings" % [key.x, key.y]) as MultiMeshInstance3D
	if buildings == null or buildings.multimesh.instance_count != groups[key].size():
		print("FAIL _test_sections_come_from_their_indices: chunk %s does not hold the plan's %d buildings" % [key, groups[key].size()])
		result = 1
	world.free()
	return result

func _test_every_lit_object_gets_at_most_eight_lights() -> int:
	# The engine pairs a light with an object when their bounding boxes meet;
	# an omni light's box is a cube of +/- its range. Past 8, lights drop.
	var world := _make_world()
	var light_boxes := []
	for light: OmniLight3D in world.find_children("*", "OmniLight3D", true, false):
		var reach := Vector3.ONE * light.omni_range
		light_boxes.append(AABB(_world_transform(light).origin - reach, reach * 2.0))
	var result := 0
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		if node.name == "Globe" or node is Label3D:
			continue  # unshaded sun globes and the sign are not lit
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

func _test_building_both_sections_takes_under_three_seconds() -> int:
	# Built on docking, behind the fade to black: target 1.5 s, fail past 3 s.
	var start := Time.get_ticks_msec()
	var world := _make_world()
	var elapsed := Time.get_ticks_msec() - start
	print("  interior build: %d ms" % elapsed)
	world.free()
	if elapsed > 3000:
		print("FAIL _test_building_both_sections_takes_under_three_seconds: %d ms" % elapsed)
		return 1
	return 0
```

In `tests/test_interior_world_physics.gd`, the resting hull must sit on a field (no buildings). Replace the placement lines:

```gdscript
	# Floor at the bottom of the ahead section, halfway along it.
	var center_z: float = -(world.bridge_length + world.section_length) * 0.5
	hull.global_position = Vector3(0.0, -(world.section_radius - 1.0 - 0.05), center_z)
```

with:

```gdscript
	# Resting on a field lot of the ahead section: nothing built there.
	hull.global_position = _field_point(world, 1.0 + 0.05)
```

and append:

```gdscript
const SectionPlan = preload("res://scripts/section_plan.gd")

# A point `height` above the centre of the first field lot of the ahead section.
func _field_point(world: Node3D, height: float) -> Vector3:
	var plan = world.get_section_plan(-1.0)
	var start_z: float = -(world.bridge_length * 0.5 + world.section_length)
	for along in range(SectionPlan.LOTS_ALONG):
		for around in range(SectionPlan.LOTS_AROUND):
			if plan.zone_at(around, along) == SectionPlan.Zone.FIELD:
				var center: Vector2 = plan.lot_center(around, along)
				var angle: float = center.x / world.section_radius
				var r: float = world.section_radius - height
				return Vector3(cos(angle) * r, sin(angle) * r, start_z + center.y)
	return Vector3.ZERO
```

(Place the `const` line with the other `const` lines at the top of the file.)

In `tests/test_internal_cruiser_physics.gd` add `const SectionPlan = preload("res://scripts/section_plan.gd")` next to the other preloads, add

```gdscript
	_failures += await _test_hits_a_building_and_bounces()
	_failures += await _test_flies_over_a_lake_without_hitting_anything()
```

after `_failures += await _test_its_camera_is_the_live_camera()`, and append:

```gdscript
# World position (in the interior) of plan point (x, z) at `height` above the
# ahead section's floor.
func _ahead_point(x: float, z: float, height: float) -> Vector3:
	var start_z: float = -(1834.0 * 0.5 + 20000.0)
	var angle: float = x / 2000.0
	var r: float = 2000.0 - height
	return Vector3(cos(angle) * r, sin(angle) * r, start_z + z)

func _test_hits_a_building_and_bounces() -> int:
	# Toward the tallest tower, just below its roof, along +Z.
	var probe: Node3D = InteriorWorldScript.new()
	probe.build()
	var plan = probe.get_section_plan(-1.0)
	probe.free()
	var tallest := 0
	for b in range(plan.building_count()):
		if plan.building_size[b].y > plan.building_size[tallest].y:
			tallest = b
	var size: Vector3 = plan.building_size[tallest]
	var face_z: float = plan.building_z[tallest] - size.z * 0.5
	var start: Vector3 = _ahead_point(plan.building_x[tallest], face_z - 100.0, size.y - 3.0)
	var nodes := _make_world_with_cruiser(start, Vector3(0.0, 0.0, 50.0))
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	var face_world_z: float = _ahead_point(0.0, face_z, 0.0).z
	var deepest := -INF
	for tick in range(240):
		await physics_frame
		deepest = maxf(deepest, cruiser.position.z + 4.0)
	var result := 0
	if deepest > face_world_z + 0.5 or cruiser.velocity.z >= 0.0:
		print("FAIL _test_hits_a_building_and_bounces: bow reached z %.2f (face at %.2f), velocity %s" % [deepest, face_world_z, cruiser.velocity])
		result = 1
	world.free()
	return result

func _test_flies_over_a_lake_without_hitting_anything() -> int:
	var probe: Node3D = InteriorWorldScript.new()
	probe.build()
	var plan = probe.get_section_plan(-1.0)
	probe.free()
	var lake := Vector2.ZERO
	for along in range(SectionPlan.LOTS_ALONG):
		for around in range(SectionPlan.LOTS_AROUND):
			if plan.zone_at(around, along) == SectionPlan.Zone.WATER and lake == Vector2.ZERO:
				lake = plan.lot_center(around, along)
	var nodes := _make_world_with_cruiser(_ahead_point(lake.x, lake.y - 30.0, 20.0), Vector3(0.0, 0.0, 30.0))
	var world: Node3D = nodes[0]
	var cruiser: CharacterBody3D = nodes[1]
	for tick in range(120):
		await physics_frame
	var result := 0
	if not cruiser.velocity.is_equal_approx(Vector3(0.0, 0.0, 30.0)):
		print("FAIL _test_flies_over_a_lake_without_hitting_anything: velocity changed to %s" % cruiser.velocity)
		result = 1
	world.free()
	return result
```

(`_make_world_with_cruiser` builds a world with default section indices 0/1 — the same plans as the `probe` above.)

- [ ] **Step 2: Run to verify they fail**

`tests/test_interior_world.gd` — Expected: `FAIL _test_two_sections_of_320_dressed_chunks...` (old `Mesh`, not dressed) and `SCRIPT ERROR ... Nonexistent function 'get_section_plan'` / invalid property `behind_section_index`.
`tests/test_interior_world_physics.gd` and `tests/test_internal_cruiser_physics.gd` — Expected: `SCRIPT ERROR ... 'get_section_plan'`.

- [ ] **Step 3: Implement** in `scripts/interior_world.gd`:

- Add after `const InteriorLayout = preload(...)`:

```gdscript
const SectionGeneratorScript = preload("res://scripts/section_generator.gd")
const TerrainDressingScript = preload("res://scripts/terrain_dressing.gd")
```

- Add after `var bridge_length := 1834.0`:

```gdscript
# Which station sections this interior shows: bridge i joins section i
# (behind, +Z) and section i + 1 (ahead, -Z). Each is generated from its index.
var behind_section_index := 0
var ahead_section_index := 1
```

- Delete `const TERRAIN_COLOR := ...`, `var _terrain_material: StandardMaterial3D` and the line `_terrain_material = _make_material(TERRAIN_COLOR, 0.95)`. Add `var _plans := {}` after `var _sun_material: StandardMaterial3D`.
- In `build()`, replace

```gdscript
	# Every chunk is the same piece of wall, turned and shifted: one mesh and
	# one collision shape for all of them.
	var chunk_mesh := _build_band_mesh(section_radius, TAU / CHUNKS_AROUND, CHUNK_LENGTH, CHUNK_ARC_SEGMENTS, CHUNK_LENGTH_SEGMENTS)
	var chunk_shape := chunk_mesh.create_trimesh_shape()
	for side in [-1.0, 1.0]:
		_build_section(side, chunk_mesh, chunk_shape)
```

with

```gdscript
	# Every chunk's floor collides as the same piece of wall, turned and
	# shifted: one collision shape for all of them. What is drawn on it comes
	# from the section's plan.
	var chunk_shape := _build_band_mesh(section_radius, TAU / CHUNKS_AROUND, CHUNK_LENGTH, CHUNK_ARC_SEGMENTS, CHUNK_LENGTH_SEGMENTS).create_trimesh_shape()
	var dressing = TerrainDressingScript.new()
	for side in [-1.0, 1.0]:
		_build_section(side, chunk_shape, dressing)
```

- Add after `set_undock_ready`:

```gdscript
# The plan of the section ahead (side -1) or behind (side +1).
func get_section_plan(side: float):
	return _plans[side]
```

- Replace the head of `_build_section` and its chunk loop:

```gdscript
func _build_section(side: float, chunk_shape: Shape3D, dressing) -> void:
	var section := Node3D.new()
	section.name = "SectionAhead" if side < 0.0 else "SectionBehind"
	add_child(section)
	var plan = SectionGeneratorScript.generate(ahead_section_index if side < 0.0 else behind_section_index, section_radius, section_length)
	_plans[side] = plan
	var buildings_by_chunk: Dictionary = plan.group_buildings_by_chunk()
	var center_z: float = InteriorLayout.section_center_z(bridge_length, section_length, side)
	var start_z: float = center_z - section_length * 0.5
	var chunks_along: int = roundi(section_length / CHUNK_LENGTH)
	var angle_step: float = TAU / CHUNKS_AROUND
	for around in range(CHUNKS_AROUND):
		for along in range(chunks_along):
			var chunk := StaticBody3D.new()
			chunk.name = "Chunk_%02d_%02d" % [around, along]
			chunk.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), around * angle_step), Vector3(0.0, 0.0, start_z + along * CHUNK_LENGTH))
			var collision := CollisionShape3D.new()
			collision.name = "Collision"
			collision.shape = chunk_shape
			chunk.add_child(collision)
			dressing.dress_chunk(chunk, plan, around, along, buildings_by_chunk.get(Vector2i(around, along), []))
			section.add_child(chunk)
```

(The caps and suns that follow in `_build_section` stay unchanged.)

- [ ] **Step 4: Run to verify they pass** — the three files print `ALL TESTS PASSED`; note the printed `interior build: N ms`. If over 1500 ms, ledger it (the test only fails past 3000 ms).
- [ ] **Step 5: Full suite.** `tests/test_game_mode.gd` may now fail on its fixed 1.2 s wait — that is fixed in Task 6; if it fails here, ledger it and proceed.
- [ ] **Step 6: Commit**

```bash
git add scripts/interior_world.gd tests/test_interior_world.gd tests/test_interior_world_physics.gd tests/test_internal_cruiser_physics.gd
git commit -m "$(cat <<'EOF'
Build the interior sections from their generated plans

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Docking picks the right sections

**Files:**
- Modify: `scripts/game_mode.gd`, `tests/test_game_mode.gd`

**Interfaces:**
- Consumes: `behind_section_index`, `ahead_section_index`, `get_section_plan` (Task 5).
- Produces: `GameMode.is_transitioning() -> bool`; `enter_interior(i)` sets `behind = i`, `ahead = (i + 1) mod num_sections`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_game_mode.gd`:
- Replace `_wait_for_transition` with:

```gdscript
func _wait_for_transition() -> void:
	# Building the interior takes a moment now: wait for the whole fade-out,
	# swap and fade-in instead of a fixed time.
	await create_timer(0.1).timeout
	for i in range(200):
		if not _game_mode.is_transitioning():
			return
		await create_timer(0.05).timeout
```

- Add `_failures += await _test_interior_sections_follow_the_docked_bridge()` after `_failures += await _test_second_dock_press_during_transition_is_ignored()`, and append:

```gdscript
func _test_interior_sections_follow_the_docked_bridge() -> int:
	var result := 0
	var last: int = _station.num_sections - 1
	for case in [[0, 0, 1], [last, last, 0]]:
		_game_mode.enter_interior(case[0])
		var interior: Node3D = _scene.get_node("InteriorWorld")
		var behind: int = interior.get_section_plan(1.0).section_index
		var ahead: int = interior.get_section_plan(-1.0).section_index
		if behind != case[1] or ahead != case[2]:
			print("FAIL _test_interior_sections_follow_the_docked_bridge: bridge %d shows sections %d (behind) and %d (ahead), expected %d and %d" % [case[0], behind, ahead, case[1], case[2]])
			result = 1
		_game_mode.exit_interior()
	return result
```

- [ ] **Step 2: Run to verify it fails** — `SCRIPT ERROR ... Nonexistent function 'is_transitioning'` and the bridge test `FAIL` (bridge 1999 shows sections 0 and 1 today).

- [ ] **Step 3: Implement** in `scripts/game_mode.gd`:

After `func is_inside() -> bool: ...` add:

```gdscript
func is_transitioning() -> bool:
	return _transitioning
```

In `enter_interior`, after `_interior.bridge_length = _station.get_bridge_length()` add:

```gdscript
	# Bridge i joins section i (behind) and section i + 1 (ahead); the ring closes.
	_interior.behind_section_index = bridge_index
	_interior.ahead_section_index = posmod(bridge_index + 1, _station.num_sections)
```

- [ ] **Step 4: Run to verify it passes** — `tests/test_game_mode.gd` `ALL TESTS PASSED`.
- [ ] **Step 5: Full suite.**
- [ ] **Step 6: Live check** — the headless `--quit-after 900` run prints no `SCRIPT ERROR|Parse Error|^ERROR|WARNING`.
- [ ] **Step 7: Offscreen look** — write a throwaway script under the scratchpad (not committed) that builds `InteriorWorld` with the scene's `WorldEnvironment` settings (black background, ambient colour `(0.25, 0.27, 0.32)` energy 0.25), puts a 90° `KEEP_WIDTH` camera (near 0.2, far 60000) (a) at the spawn point looking -Z and (b) 300 m above the ahead section's city centre looking along -Z tilted 25° down, waits 6 frames, and saves `root.get_texture().get_image()` as PNGs. Run it with `xvfb-run -a -s "-screen 0 1280x720x24" /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --path . --rendering-driver opengl3 --script <file>`, then look at both PNGs: fields in colour with rows, roads, lakes, lit buildings visible, no flicker bands or black holes. Record what you saw in the ledger; anything wrong is a finding for the final review.
- [ ] **Step 8: Commit**

```bash
git add scripts/game_mode.gd tests/test_game_mode.gd
git commit -m "$(cat <<'EOF'
Show the two sections joined by the docked bridge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Manual verification (user, in game)

1. Dock and fly into a section: coloured fields with rows, roads on a 1 km grid, lakes, towns, and one city with towers.
2. The same bridge always shows the same land; a different bridge shows different land.
3. Flying into a building bounces the craft; flying over a lake does not.
4. Frame rate acceptable; if not, lower `BUILDING_VISIBILITY_END` in `terrain_dressing.gd`.
