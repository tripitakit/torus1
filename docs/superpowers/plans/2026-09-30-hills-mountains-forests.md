# Hills, Mountain Chains and Forests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the interior RELIEF zone with flat fields, forested multi-lot HILL patches and, in about a third of the sections, a MOUNTAIN chain up to 1500 m with massifs, saddles, spurs and spires, forested up to ~600 m.

**Architecture:** `section_plan.gd` gets zones HILL/MOUNTAIN and `is_raised`. `section_generator.gd` builds an optional `Chain` (ridge along the section, noise-driven crest and width, spires), marks MOUNTAIN lots, picks HILL patches (min 4 lots), and fills the height grid only inside raised lots. `terrain_dressing.gd` colours raised ground forest/rock and, in `build_ground` (worker threads), computes tree instance buffers; the main thread wraps them in two MultiMeshes per chunk with meshes from a new `tree_shapes.gd`.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility`, `FastNoiseLite`, `MultiMesh`. Headless `extends SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-09-30-hills-mountains-forests-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64` (never the `godot` on PATH). One test file: `<binary> --headless --path . -s tests/<file>.gd`. Scratchpad helper `rt.sh <test names...>` prints only relevant lines; `suite.sh` runs every `tests/*.gd` (paths: `/tmp/claude-1000/-home-patrick-projects-playground-torus1/88be7e76-cf17-4eba-b962-d57871ddb62e/scratchpad/`).
- In a worktree session, Bash refuses loops over variables and long compound commands: run single commands, put edit scripts in files.
- RED is a `FAIL`, `SCRIPT ERROR` or `Parse Error` line, never the summary alone. The user wants RED seen.
- Numbers verbatim from the spec: `HILL_SHARE = 0.12`, `HILL_MIN_LOTS = 4`, hill heights 50–150 m, `RELIEF_BLEND = 250`; `CHAIN_CHANCE = 1/3`, chain length 6–12 km, `CHAIN_END_MARGIN = 2000`, meander 400 m, crest 450–1150 m, half width 1000–2000 m, taper 1500 m, detail `0.7 + 0.45 × ridged`, profile `p^1.4`, 3–8 spires radius 80–125 m height +400–700 m, `MOUNTAIN_HEIGHT = 1500`, MOUNTAIN lot when chain height at the centre > 20 m; forest `Color(0.2, 0.34, 0.15)`, rock `Color(0.46, 0.44, 0.41)`, rock share `max(smoothstep(550, 650, h), smoothstep(0.9, 1.3, slope))`; trees every 17 m, edge margin 5 m, treeline `600 ± 50`, max slope 1.2, heights 10–25 m, widths 35–50 % of height, sink 0.5 m, conifer share 0.4 below 300 m rising to 1 at 450 m, visible to 3000 m.
- Flat land (FIELD, TOWN, CITY, WATER) stays exactly at height 0 (tests allow 0.001 m).
- Keep the relief work's guarantees: drawn ground on its collision, no cracks, ground built on worker threads (`build_ground` stays static and touches no node), docking build < 3 s, worst streaming frame < 50 ms (own alarm at 35 ms).
- GDScript: packed arrays are values (build in locals, assign whole); inner classes read outer constants but cannot call outer static functions; `@warning_ignore("integer_division")` where needed; integer literals must fit in signed 64 bits.
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Add `.uid` files of new scripts/tests (created by `<binary> --headless --path . --import`).

## Review Focus

1. **Flat land touched by raised terrain** — a lake or a town lot at the foot of the chain, or a field next to a hill, must stay exactly flat; the fade happens inside raised lots. Test: `_test_flat_zones_and_ends_stay_at_zero` (Task 1, extended with the chain plan in Task 2).
2. **A chain crossing the city or the end walls** — the bridge tubes and the city must stay clear. Tests: `_test_chain_stays_clear_of_ends_and_city` (Task 2).
3. **Trees floating, buried, on rock or cliffs, or in fields** — Tests: `_test_trees_stand_on_raised_ground_below_the_treeline` (Task 5).
4. **Tree seams** — no treeless lanes between two adjacent raised lots, no trees crossing into a flat lot. Test: `_test_trees_keep_off_flat_lots_only` (Task 5).
5. **Frame and docking cost of forests and of 1500 m chunk bounds** — Tests: docking/streaming timings and the 8-lights-per-object test (Task 6).

---

### Task 1: HILL zone replaces RELIEF; flat fields

**Files:**
- Modify: `scripts/section_plan.gd`, `scripts/section_generator.gd`, `scripts/terrain_dressing.gd` (only the zone name and colours needed to compile)
- Test: `tests/test_section_plan.gd`, `tests/test_section_generator.gd`, `tests/test_terrain_dressing.gd`

**Interfaces:**
- Produces: `SectionPlan.Zone { FIELD, TOWN, CITY, WATER, HILL, MOUNTAIN }`, `static func SectionPlan.is_raised(zone: int) -> bool`, `var SectionPlan.has_chain := false`; generator constants `HILL_SHARE`, `HILL_MIN_LOTS`, `HILL_PATCH_SIZE := 2000.0`, `HILL_FEATURE_SIZE := 700.0`, `HILL_HEIGHTS := Vector2(50, 150)`, `RELIEF_BLEND := 250.0`; `static func _noise(seed_value, feature_size, octaves) -> FastNoiseLite`; `_heights(plan, chain)` (chain may be null; Task 2 passes a real one).
- Removes: `RELIEF`, `relief_threshold`, `relief_peak`, `mountain_noise`, `RELIEF_SHARE`, `MOUNTAIN_FEATURE_SIZE`, `HILL_HEIGHT`, old `MOUNTAIN_HEIGHT`.

- [ ] **Step 1: Tests (RED).**
  - `test_section_plan.gd`: replace the RELIEF check in `_test_grid_size_and_step` with `SectionPlan.Zone.HILL != 4 or SectionPlan.Zone.MOUNTAIN != 5 or not SectionPlan.is_raised(SectionPlan.Zone.HILL) or not SectionPlan.is_raised(SectionPlan.Zone.MOUNTAIN) or SectionPlan.is_raised(SectionPlan.Zone.FIELD)`.
  - `test_section_generator.gd`:
    - `_land_use`: map `SectionPlan.is_raised(zone)` to FIELD (comment: raised zones come from their own noises).
    - `_expected_road`: NONE when either zone is WATER or raised.
    - Delete `_test_relief_lots_are_the_highest_five_percent_of_fields`, `_test_no_road_touches_relief`, `_test_heights_in_range_and_mountains_only_above_the_threshold` and their `_init()` lines.
    - `FLAT_ZONES` becomes `[FIELD, TOWN, CITY, WATER]`.
    - `_test_zone_shares`: water ≥ `384 - city - mountain` and town ≥ `576 - city - mountain` (mountain = count of MOUNTAIN lots; the chain covers lakes and towns).
    - Add `_test_hills_are_patches_of_several_lots`: HILL count in `[0.08, 0.13] × 3840`; flood-fill HILL lots (4-neighbours, around wraps, along does not): every patch ≥ 4 lots.
    - Add `_test_no_road_touches_raised_land`: like the old relief test, for any raised lot.
    - Add `_test_heights_without_a_chain_stay_under_150`: on a plan without chain (`_plan` if `not _plan.has_chain`, else the first index in 0..29 with `not SectionGenerator.chain_wanted(i)` — use `_plan` here and in Task 2 make the helper), every grid point in [0, 150.001].
  - `test_terrain_dressing.gd`: `_test_relief_colours` → `_test_raised_ground_colours`: `relief_color(10, 0.1)` ≈ `FOREST_COLOR`, `relief_color(700, 0.1)` ≈ `ROCK_COLOR`, `relief_color(10, 1.4)` ≈ `ROCK_COLOR`; chunk from `_find_chunk(SectionPlan.Zone.HILL, true)`; lot test `SectionPlan.is_raised(...)`.
- [ ] **Step 2: Run** `rt.sh test_section_plan test_section_generator test_terrain_dressing` → Parse Errors on `HILL`/`is_raised`/`FOREST_COLOR`.
- [ ] **Step 3: Implement.**
  - `section_plan.gd`: new enum; replace `relief_threshold`/`relief_peak` with `var has_chain := false`; add

```gdscript
# Hills and mountains: the zones with relief (and trees).
static func is_raised(zone: int) -> bool:
	return zone == Zone.HILL or zone == Zone.MOUNTAIN
```

  - `section_generator.gd`: replace the RELIEF constants block with

```gdscript
# Hills: HILL_SHARE of all lots, taken from fields where a patch noise is
# highest; patches of fewer than HILL_MIN_LOTS lots go back to field.
const HILL_SHARE := 0.12
const HILL_MIN_LOTS := 4
const HILL_PATCH_SIZE := 2000.0
const HILL_FEATURE_SIZE := 700.0
const HILL_HEIGHTS := Vector2(50.0, 150.0)
# Heights fade to 0 within this of flat land (field, town, city, lake) or an
# end wall, inside the raised lots: flat land stays exactly flat.
const RELIEF_BLEND := 250.0
```

    delete `mountain_noise` and `_with_relief`; in `generate()` replace `_with_relief` with

```gdscript
	plan.zones = _with_hills(plan, plan.zones)
```

    and `_heights(plan)` with `_heights(plan, null)` (Task 2 swaps in the chain). Add:

```gdscript
static func _noise(seed_value: int, feature_size: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0 / feature_size
	noise.fractal_octaves = octaves
	return noise

# The field lots where a patch noise is highest, HILL_SHARE of all lots,
# become HILL; patches too small to read as hills go back to field.
static func _with_hills(plan, zones: PackedByteArray) -> PackedByteArray:
	var values := _sample_lots(plan, _noise(hash([plan.section_index, "hill patches"]), HILL_PATCH_SIZE, 2))
	var field_values := PackedFloat64Array()
	for i in range(values.size()):
		if zones[i] == SectionPlanScript.Zone.FIELD:
			field_values.append(values[i])
	var count: int = mini(int(values.size() * HILL_SHARE), field_values.size())
	if count == 0:
		return zones
	field_values.sort()
	var threshold: float = field_values[field_values.size() - count]
	for i in range(values.size()):
		if zones[i] == SectionPlanScript.Zone.FIELD and values[i] >= threshold:
			zones[i] = SectionPlanScript.Zone.HILL
	return _without_small_hills(plan, zones)

# Hill patches (lots sharing an edge; the way round closes) of fewer than
# HILL_MIN_LOTS lots go back to field.
@warning_ignore("integer_division")
static func _without_small_hills(plan, zones: PackedByteArray) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(zones.size())
	for start in range(zones.size()):
		if zones[start] != SectionPlanScript.Zone.HILL or seen[start] == 1:
			continue
		seen[start] = 1
		var patch := [start]
		var k := 0
		while k < patch.size():
			var i: int = patch[k]
			k += 1
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var along: int = i / SectionPlanScript.LOTS_AROUND + step.y
				if along < 0 or along >= SectionPlanScript.LOTS_ALONG:
					continue
				var j: int = plan.lot_index(i % SectionPlanScript.LOTS_AROUND + step.x, along)
				if zones[j] == SectionPlanScript.Zone.HILL and seen[j] == 0:
					seen[j] = 1
					patch.append(j)
		if patch.size() < HILL_MIN_LOTS:
			for i: int in patch:
				zones[i] = SectionPlanScript.Zone.FIELD
	return zones
```

    Generalise `_flat_rects_by_lot(plan)` to `_rects_by_lot(plan, wanted: Callable)` (rectangles of the lot and its 8 neighbours whose zone satisfies `wanted`), delete `_is_flat`, and replace `_heights` with

```gdscript
# Heights only inside raised lots, fading to 0 within RELIEF_BLEND of flat
# land or an end wall: the chain's (Task 2) and, in hill lots, the hills',
# whichever is higher.
@warning_ignore("integer_division")
static func _heights(plan, chain) -> PackedFloat32Array:
	var hills := _noise(hash([plan.section_index, "hills"]), HILL_FEATURE_SIZE, 2)
	var flat_rects := _rects_by_lot(plan, func(zone: int) -> bool: return not SectionPlanScript.is_raised(zone))
	var open_rects := _rects_by_lot(plan, func(zone: int) -> bool: return zone != SectionPlanScript.Zone.HILL)
	var step: Vector2 = plan.height_step()
	var heights := PackedFloat32Array()
	heights.resize(SectionPlanScript.RELIEF_COLUMNS * SectionPlanScript.RELIEF_ROWS)
	for row in range(SectionPlanScript.RELIEF_ROWS):
		var z: float = row * step.y
		var along: int = mini(row / SectionPlanScript.RELIEF_POINTS_PER_LOT, SectionPlanScript.LOTS_ALONG - 1)
		for column in range(SectionPlanScript.RELIEF_COLUMNS):
			var x: float = column * step.x
			var lot: int = along * SectionPlanScript.LOTS_AROUND + column / SectionPlanScript.RELIEF_POINTS_PER_LOT
			var flat := _rect_distance(plan, x, z, flat_rects[lot])
			if flat <= 0.0:
				continue  # resize() filled it with 0
			var h := 0.0
			if chain != null:
				h = chain.height(x, z) * smoothstep(0.0, RELIEF_BLEND, flat)
			var open := _rect_distance(plan, x, z, open_rects[lot])
			if open > 0.0:
				var bump: float = clampf((hills.get_noise_3dv(surface_point(plan, x, z)) + 1.0) * 0.5, 0.0, 1.0)
				h = maxf(h, lerpf(HILL_HEIGHTS.x, HILL_HEIGHTS.y, bump) * smoothstep(0.0, RELIEF_BLEND, open))
			heights[row * SectionPlanScript.RELIEF_COLUMNS + column] = h
	return heights
```

    (`_rect_distance` is the old `_flat_distance`, renamed.) In `_edge_road`, the first check becomes `zone == WATER or SectionPlanScript.is_raised(zone)`, comment updated.
  - `terrain_dressing.gd`: `GRASS_COLOR` → `FOREST_COLOR := Color(0.2, 0.34, 0.15)`; `relief_color` rock share `maxf(smoothstep(0.9, 1.3, slope), smoothstep(550.0, 650.0, height))`, lerp from FOREST; the RELIEF branch of `build_ground` tests `SectionPlanScript.is_raised(zone)` and uses `FOREST_COLOR`; comments say "hills and mountains".
- [ ] **Step 4: Run** the three tests → `ALL TESTS PASSED`; note hill count and generate time (probe) in the ledger.
- [ ] **Step 5: Commit** "Flat fields and forested-to-be HILL patches replace RELIEF".

---

### Task 2: The mountain chain

**Files:** Modify `scripts/section_generator.gd`; Test `tests/test_section_generator.gd`.

**Interfaces:**
- Produces: constants `CHAIN_CHANCE := 1.0 / 3.0`, `CHAIN_LENGTHS := Vector2(6000, 12000)`, `CHAIN_END_MARGIN := 2000.0`, `CHAIN_MEANDER := 400.0`, `CHAIN_CREST := Vector2(450, 1150)`, `CHAIN_HALF_WIDTH := Vector2(1000, 2000)`, `CHAIN_TAPER := 1500.0`, `CHAIN_FEATURE_SIZE := 3000.0`, `CHAIN_DETAIL_SIZE := 600.0`, `SPIRE_COUNT := Vector2i(3, 8)`, `SPIRE_RADIUS := Vector2(80, 125)`, `SPIRE_HEIGHT := Vector2(400, 700)`, `MOUNTAIN_HEIGHT := 1500.0`, `MOUNTAIN_LOT_MIN := 20.0`; `class Chain` with `height(x, z) -> float`, `ridge_x(z) -> float`, members `z0`, `z1`, `x0`, `spires: Array[Vector4]`; `static func chain_wanted(section_index: int) -> bool`; `static func chain_of(plan) -> Chain` (null without chain; needs `plan.city_center`).

- [ ] **Step 1: Tests (RED).** Helpers `_chain_index()` (first `i` in 0..29 with `chain_wanted(i)`) and a lazily generated `_chain_plan`. Tests:
  - `_test_about_a_third_of_sections_have_a_chain`: count `chain_wanted(i)` for 0..29 in [5, 16]; `generate(i).has_chain == chain_wanted(i)` for the first two indices.
  - `_test_chain_reaches_1000_to_1500_m`: highest grid point of `_chain_plan` in [1000, 1500.001].
  - `_test_chain_stays_clear_of_ends_and_city`: every MOUNTAIN lot centre has `z` in [1500, length − 1500] and `surface_distance` to `city_center` ≥ 3000; no CITY lot became MOUNTAIN (the city lot count equals the count of lots within `CITY_RADIUS`).
  - `_test_chain_crest_varies_and_has_spires`: take `chain_of(_chain_plan)`; for 500 m bands along z inside `[z0 + 1500, z1 − 1500]` the band's highest grid point; `max − min ≥ 400`. Spires: grid points whose height exceeds the maximum over the 8 points two steps away (±2 columns/rows) by ≥ 150 m: at least 3.
  - `_test_flat_zones_and_ends_stay_at_zero` and `_test_buildings_stand_at_level_zero` also run on `_chain_plan` (loop over `[_plan, _chain_plan]`).
  - `_test_heights_without_a_chain_stay_under_150` also on `_chain_plan`, for points where `chain.height(x, z) == 0`.
- [ ] **Step 2: Run** `rt.sh test_section_generator` → Parse Error on `chain_wanted`.
- [ ] **Step 3: Implement** the constants above and

```gdscript
# A section's mountain chain: a ridge along the section. height() is read
# for every lot centre and grid point, on the generator's worker thread.
class Chain:
	extends RefCounted
	var circumference := 0.0
	var radius := 0.0
	var x0 := 0.0
	var z0 := 0.0
	var z1 := 0.0
	var meander: FastNoiseLite
	var massif: FastNoiseLite
	var detail: FastNoiseLite
	# Vector4(x, z, radius, height) per spire.
	var spires: Array[Vector4] = []

	func ridge_x(z: float) -> float:
		return x0 + CHAIN_MEANDER * meander.get_noise_1d(z)

	# Shortest way round between two x.
	func _gap(a: float, b: float) -> float:
		return absf(fposmod(a - b + circumference * 0.5, circumference) - circumference * 0.5)

	func height(x: float, z: float) -> float:
		if z <= z0 or z >= z1:
			return 0.0
		var dx: float = _gap(x, ridge_x(z))
		if dx >= CHAIN_HALF_WIDTH.y:
			return 0.0
		# Along the ridge one noise sets both crest and width: wide high
		# massifs, narrow low saddles. The ends taper down.
		var bulk: float = clampf((massif.get_noise_1d(z) + 1.0) * 0.5, 0.0, 1.0)
		var taper: float = smoothstep(0.0, CHAIN_TAPER, z - z0) * smoothstep(0.0, CHAIN_TAPER, z1 - z)
		var p: float = clampf(1.0 - dx / lerpf(CHAIN_HALF_WIDTH.x, CHAIN_HALF_WIDTH.y, bulk), 0.0, 1.0)
		var h := 0.0
		if p > 0.0:
			# Ridged noise on the flanks: spurs and the valleys between them.
			var angle: float = x / radius
			var ridged: float = 1.0 - absf(detail.get_noise_3d(cos(angle) * radius, sin(angle) * radius, z))
			h = taper * lerpf(CHAIN_CREST.x, CHAIN_CREST.y, bulk) * pow(p, 1.4) * (0.7 + 0.45 * ridged)
		for spire in spires:
			var d: float = Vector2(_gap(x, spire.x), z - spire.y).length()
			if d < spire.z:
				h += spire.w * pow(1.0 - d / spire.z, 1.2)
		return minf(h, MOUNTAIN_HEIGHT)

static func _chain_rng(section_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([section_index, "chain"])
	return rng

static func chain_wanted(section_index: int) -> bool:
	return _chain_rng(section_index).randf() < CHAIN_CHANCE

# The section's chain, or null: opposite the city round the section (give
# or take an eighth of a turn), CHAIN_END_MARGIN clear of both end walls.
static func chain_of(plan) -> Chain:
	var rng := _chain_rng(plan.section_index)
	if rng.randf() >= CHAIN_CHANCE:
		return null
	var chain := Chain.new()
	chain.circumference = plan.circumference()
	chain.radius = plan.radius
	var chain_length: float = minf(rng.randf_range(CHAIN_LENGTHS.x, CHAIN_LENGTHS.y), plan.length - 2.0 * CHAIN_END_MARGIN)
	chain.z0 = rng.randf_range(CHAIN_END_MARGIN, plan.length - CHAIN_END_MARGIN - chain_length)
	chain.z1 = chain.z0 + chain_length
	chain.x0 = fposmod(plan.city_center.x + chain.circumference * rng.randf_range(0.375, 0.625), chain.circumference)
	chain.meander = _noise(hash([plan.section_index, "meander"]), CHAIN_FEATURE_SIZE, 2)
	chain.massif = _noise(hash([plan.section_index, "massif"]), CHAIN_FEATURE_SIZE, 3)
	chain.detail = _noise(hash([plan.section_index, "detail"]), CHAIN_DETAIL_SIZE, 3)
	for k in range(rng.randi_range(SPIRE_COUNT.x, SPIRE_COUNT.y)):
		var z: float = rng.randf_range(chain.z0 + CHAIN_TAPER, chain.z1 - CHAIN_TAPER)
		var x: float = fposmod(chain.ridge_x(z) + rng.randf_range(-150.0, 150.0), chain.circumference)
		chain.spires.append(Vector4(x, z, rng.randf_range(SPIRE_RADIUS.x, SPIRE_RADIUS.y), rng.randf_range(SPIRE_HEIGHT.x, SPIRE_HEIGHT.y)))
	return chain

# Every lot but the city's whose centre the chain raises past
# MOUNTAIN_LOT_MIN becomes MOUNTAIN, lakes and towns included.
static func _with_mountain(plan, zones: PackedByteArray, chain: Chain) -> PackedByteArray:
	if chain == null:
		return zones
	for along in range(SectionPlanScript.LOTS_ALONG):
		for around in range(SectionPlanScript.LOTS_AROUND):
			var i: int = plan.lot_index(around, along)
			var center: Vector2 = plan.lot_center(around, along)
			if zones[i] != SectionPlanScript.Zone.CITY and chain.height(center.x, center.y) > MOUNTAIN_LOT_MIN:
				zones[i] = SectionPlanScript.Zone.MOUNTAIN
	return zones
```

  In `generate()`, after `_with_city`: `var chain := chain_of(plan)`, `plan.has_chain = chain != null`, `plan.zones = _with_mountain(plan, plan.zones, chain)`, then `_with_hills`; heights `_heights(plan, chain)`.
- [ ] **Step 4: Run** `rt.sh test_section_generator test_section_plan test_terrain_dressing` → all pass. Measure `generate()` on the chain plan (probe); over 1000 ms: optimise `Chain.height` (early z/x rejections) before moving on, ledger the numbers.
- [ ] **Step 5: Commit** "Mountain chains: ridge with massifs, saddles, spurs and spires".

---

### Task 3: Tree shapes

**Files:** Create `scripts/tree_shapes.gd`, `tests/test_tree_shapes.gd` (+ `.uid`).

**Interfaces:** `static func conifer() -> ArrayMesh`, `static func broadleaf() -> ArrayMesh`, `const TRUNK_COLOR`, `const CROWN_COLOR`.

- [ ] **Step 1: Test (RED)** `tests/test_tree_shapes.gd`: for both meshes: every vertex y in [0, 1] and horizontal radius ≤ 0.4, max y ≈ 1, min y ≈ 0; triangle count in [20, 80]; for every triangle, the normal (as stored, equal to the normalised `(c - a).cross(b - a)`) points outward: if `|n.y| < 0.99`, `n` · (centroid with y set to 0) > 0, else `n.y < 0` (only bottom discs are horizontal); vertex colour alpha is 0 where y < 0.14 (trunk only) and some vertices have alpha 1.
- [ ] **Step 2: Run** → Parse Error (missing script).
- [ ] **Step 3: Implement**

```gdscript
extends RefCounted

# Two low-poly trees as unit meshes: base at y = 0, top at y = 1, about 0.6
# wide, flat-shaded, faces outward. Vertex colour: the trunk brown with
# alpha 0, the crown white with alpha 1; the tree shader paints the crown in
# each instance's own green (terrain_dressing.gd).

const TRUNK_COLOR := Color(0.36, 0.25, 0.16, 0.0)
const CROWN_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SIDES := 7

# Two stacked cones on a short trunk.
static func conifer() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(st, [Vector2(0.0, 0.04), Vector2(0.22, 0.04)], TRUNK_COLOR)
	_lathe(st, [Vector2(0.15, 0.0), Vector2(0.15, 0.3), Vector2(0.75, 0.0)], CROWN_COLOR)
	_lathe(st, [Vector2(0.45, 0.0), Vector2(0.45, 0.21), Vector2(1.0, 0.0)], CROWN_COLOR)
	return st.commit()

# A faceted round crown on a taller trunk.
static func broadleaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(st, [Vector2(0.0, 0.05), Vector2(0.42, 0.05)], TRUNK_COLOR)
	_lathe(st, [Vector2(0.3, 0.0), Vector2(0.48, 0.3), Vector2(0.75, 0.36), Vector2(0.92, 0.22), Vector2(1.0, 0.0)], CROWN_COLOR)
	return st.commit()

# Turns a profile of (y, radius) points, bottom to top, round the y axis in
# SIDES flat faces. Each face is wound so its front faces out of the
# profile (away from the axis, or down for a bottom disc).
static func _lathe(st: SurfaceTool, profile: Array, color: Color) -> void:
	for k in range(profile.size() - 1):
		var a: Vector2 = profile[k]
		var b: Vector2 = profile[k + 1]
		# Outward normal of the profile segment in (radius, y).
		var out := Vector2(b.x - a.x, -(b.y - a.y))
		for i in range(SIDES):
			var t0: float = TAU * i / SIDES
			var t1: float = TAU * (i + 1) / SIDES
			var p00 := Vector3(cos(t0) * a.y, a.x, sin(t0) * a.y)
			var p10 := Vector3(cos(t1) * a.y, a.x, sin(t1) * a.y)
			var p01 := Vector3(cos(t0) * b.y, b.x, sin(t0) * b.y)
			var p11 := Vector3(cos(t1) * b.y, b.x, sin(t1) * b.y)
			var mid: float = (t0 + t1) * 0.5
			var outward := Vector3(cos(mid) * out.x, out.y, sin(mid) * out.x)
			if a.y > 0.0:
				_triangle(st, p00, p10, p01 if b.y > 0.0 else p01, outward, color)
			if b.y > 0.0:
				_triangle(st, p10, p11, p01, outward, color)

# One flat triangle, wound so its front faces `outward`.
static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a)
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	for p in [a, b, c]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(p)
```

  Note on `_lathe`'s profile vectors: `x` is y (height), `y` is radius, so the segment's outward normal in (radius, height) is `(Δheight, −Δradius)` = `Vector2(b.x − a.x, −(b.y − a.y))` read as (radial, vertical). A face with both radii 0 is skipped; a cone apex (radius 0 at `b`) gives one triangle per side, a disc centre (radius 0 at `a`) one triangle.
- [ ] **Step 4: Run** `rt.sh test_tree_shapes` → pass (fix winding/outward in `_lathe` if the test says so — the test is the authority). Import once to create the `.uid`.
- [ ] **Step 5: Commit** "Low-poly conifer and broadleaf tree meshes".

---

### Task 4: Trees on raised ground

**Files:** Modify `scripts/terrain_dressing.gd`; Test `tests/test_terrain_dressing.gd`.

**Interfaces:**
- Consumes: `TreeShapes.conifer()/broadleaf()` (Task 3), `SectionPlan.is_raised`, `plan.sample_at`.
- Produces: constants from Global Constraints (`TREE_SPACING := 17.0`, `TREE_EDGE_MARGIN := 5.0`, `TREELINE := 600.0`, `TREELINE_BAND := 50.0`, `TREE_MAX_SLOPE := 1.2`, `TREE_HEIGHTS := Vector2(10, 25)`, `TREE_WIDTHS := Vector2(0.35, 0.5)`, `TREE_SINK := 0.5`, `LOW_CONIFER_SHARE := 0.4`, `CONIFERS_FROM := 300.0`, `CONIFERS_ONLY := 450.0`, `CONIFER_GREEN := Color(0.12, 0.3, 0.16)`, `BROADLEAF_GREEN := Color(0.24, 0.42, 0.14)`, `TREE_VISIBILITY_END := 3000.0`, `TREE_FLOATS := 16`); `static func tree_buffers(plan, chunk_around, chunk_along) -> Array` = `[conifers: PackedFloat32Array, broadleaves: PackedFloat32Array, tallest: float]` (MultiMesh buffer layout: 12 transform floats `[X.x, Y.x, Z.x, O.x, X.y, Y.y, Z.y, O.y, X.z, Y.z, Z.z, O.z]` then custom data = crown colour r, g, b, 1); `build_ground` returns `[fields, paved, water, collision, trees]`; `_add_ground(chunk, ground, plan)`; nodes `Trees/Conifers`, `Trees/Broadleaves` (`MultiMeshInstance3D`).

- [ ] **Step 1: Tests (RED)**, helpers: `_trees(key)` = `TerrainDressing.build_ground(_plan, key.x, key.y)[4]`; `_forest_chunk()` = the chunk with the most HILL/MOUNTAIN lots; a per-instance reader (origin = floats 3, 7, 11; up column = 1, 5, 9 whose length is the tree height).
  - `_test_trees_stand_on_raised_ground_below_the_treeline`: for every tree of `_forest_chunk()` (and of the chain plan's highest chunk, if a chain plan is at hand from `SectionGenerator.chain_wanted`): section position from origin (`atan2 × R` + chunk start, `z` + chunk start) lies in a raised lot; `|origin radius − (R − height_at + TREE_SINK)| < 0.01`; `height_at ≤ 650`; `slope_at.length() ≤ 1.2`; conifer-only above 450 m; tree height in [10, 25]; up column points to the axis (dot with `(−x, −y, 0)` > 0).
  - `_test_trees_keep_off_flat_lots_only`: every tree is ≥ 5 m (−0.01) from any edge of its lot whose neighbour across it is flat or is the end wall; and some tree is < 5 m from an edge shared with another raised lot (no lanes between raised lots) — pick the forest chunk.
  - `_test_forest_density`: trees in `_forest_chunk()` / (raised area / 17²) in [0.6, 1.1].
  - `_test_trees_are_deterministic_and_built_on_workers`: two `build_ground` calls give equal buffers; the worker-built ground (extend `_test_ground_built_on_a_worker_matches_one_built_in_place`) has equal tree buffers.
  - `_test_tree_nodes`: dressing the forest chunk adds `Trees/Conifers` or `Trees/Broadleaves` with `multimesh.instance_count == buffer.size() / 16`, `visibility_range_end == 3000`, shadows off, `custom_aabb` covering `tallest`; a chunk with no raised lot has no `Trees` node.
- [ ] **Step 2: Run** `rt.sh test_terrain_dressing` → Parse Error on `tree_buffers`.
- [ ] **Step 3: Implement.** In `terrain_dressing.gd`: preload `TreeShapesScript`, the constants, `var conifer_mesh`, `var broadleaf_mesh`, `var tree_material` (in `_init`, shader below), and

```gdscript
const TREE_SHADER := """
shader_type spatial;

// Vertex colour: trunk brown with alpha 0, crown with alpha 1; each tree's
// crown green comes in its instance custom data.
varying vec3 crown;

void vertex() {
	crown = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	ALBEDO = mix(COLOR.rgb, crown, COLOR.a);
	ROUGHNESS = 0.9;
}
"""

# A 64-bit hash of a tree cell: eight 7-bit random numbers per tree.
static func _tree_hash(section_index: int, cx: int, cz: int) -> int:
	var h: int = section_index * 0x1E3779B97F4A7C15 + cx * 0x3F58476D1CE4E5B9 + cz * 0x14D049BB133111EB
	h = (h ^ (h >> 30)) * 0x3F58476D1CE4E5B9
	h = (h ^ (h >> 27)) * 0x14D049BB133111EB
	return h ^ (h >> 31)

# The trees of a chunk, for two MultiMeshes: one per TREE_SPACING cell of a
# global grid (section metres), jittered inside it, kept where its point
# lies in a hill or mountain lot, TREE_EDGE_MARGIN clear of flat land, under
# the treeline and not on a cliff. Pure: safe on a worker thread.
static func tree_buffers(plan, chunk_around: int, chunk_along: int) -> Array:
	var conifers := PackedFloat32Array()
	var broadleaves := PackedFloat32Array()
	var tallest := 0.0
	var chunk_start := Vector2(chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND * plan.lot_width, chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG * plan.lot_length)
	var radius: float = plan.radius
	for lot_x in range(SectionPlanScript.CHUNK_LOTS_AROUND):
		for lot_z in range(SectionPlanScript.CHUNK_LOTS_ALONG):
			var around: int = chunk_around * SectionPlanScript.CHUNK_LOTS_AROUND + lot_x
			var along: int = chunk_along * SectionPlanScript.CHUNK_LOTS_ALONG + lot_z
			if not SectionPlanScript.is_raised(plan.zone_at(around, along)):
				continue
			var x0: float = around * plan.lot_width
			var x1: float = x0 + plan.lot_width
			var z0: float = along * plan.lot_length
			var z1: float = z0 + plan.lot_length
			var west: float = 0.0 if SectionPlanScript.is_raised(plan.zone_at(around - 1, along)) else TREE_EDGE_MARGIN
			var east: float = 0.0 if SectionPlanScript.is_raised(plan.zone_at(around + 1, along)) else TREE_EDGE_MARGIN
			var south: float = TREE_EDGE_MARGIN if along == 0 or not SectionPlanScript.is_raised(plan.zone_at(around, along - 1)) else 0.0
			var north: float = TREE_EDGE_MARGIN if along + 1 >= SectionPlanScript.LOTS_ALONG or not SectionPlanScript.is_raised(plan.zone_at(around, along + 1)) else 0.0
			for cx in range(floori(x0 / TREE_SPACING), ceili(x1 / TREE_SPACING)):
				for cz in range(floori(z0 / TREE_SPACING), ceili(z1 / TREE_SPACING)):
					var bits := _tree_hash(plan.section_index, cx, cz)
					var x: float = (cx + 0.15 + 0.7 * float(bits & 127) / 128.0) * TREE_SPACING
					var z: float = (cz + 0.15 + 0.7 * float((bits >> 7) & 127) / 128.0) * TREE_SPACING
					if x < x0 + west or x >= x1 - east or z < z0 + south or z >= z1 - north:
						continue
					var sample: Vector3 = plan.sample_at(x, z)
					var h: float = sample.x
					if h > TREELINE + TREELINE_BAND * (float((bits >> 14) & 127) / 64.0 - 1.0) or Vector2(sample.y, sample.z).length() > TREE_MAX_SLOPE:
						continue
					var conifer: bool = float((bits >> 21) & 127) / 128.0 < lerpf(LOW_CONIFER_SHARE, 1.0, smoothstep(CONIFERS_FROM, CONIFERS_ONLY, h))
					var tree_height: float = lerpf(TREE_HEIGHTS.x, TREE_HEIGHTS.y, float((bits >> 28) & 127) / 128.0)
					var width: float = tree_height * lerpf(TREE_WIDTHS.x, TREE_WIDTHS.y, float((bits >> 35) & 127) / 128.0)
					var yaw: float = TAU * float((bits >> 42) & 127) / 128.0
					var shade: float = lerpf(0.8, 1.15, float((bits >> 49) & 127) / 128.0)
					var angle: float = (x - chunk_start.x) / radius
					var up := Vector3(-cos(angle), -sin(angle), 0.0)
					var side: Vector3 = Vector3(-sin(angle), cos(angle), 0.0) * cos(yaw) + Vector3(0.0, 0.0, sin(yaw))
					var front: Vector3 = side.cross(up)
					var bx: Vector3 = side * width
					var by: Vector3 = up * tree_height
					var bz: Vector3 = front * width
					var origin: Vector3 = -up * (radius - h + TREE_SINK) + Vector3(0.0, 0.0, z - chunk_start.y)
					var green: Color = (CONIFER_GREEN if conifer else BROADLEAF_GREEN) * shade
					var data := PackedFloat32Array([bx.x, by.x, bz.x, origin.x, bx.y, by.y, bz.y, origin.y, bx.z, by.z, bz.z, origin.z, green.r, green.g, green.b, 1.0])
					if conifer:
						conifers.append_array(data)
					else:
						broadleaves.append_array(data)
					tallest = maxf(tallest, h + tree_height)
	return [conifers, broadleaves, tallest]
```

  `build_ground` appends `tree_buffers(plan, chunk_around, chunk_along) if relief else [PackedFloat32Array(), PackedFloat32Array(), 0.0]`. `dress_chunk` passes `plan` to `_add_ground(chunk, ground, plan)`, which after the collision calls

```gdscript
# Two MultiMeshes of the chunk's trees (build_ground made the buffers).
@warning_ignore("integer_division")
func _add_trees(chunk: StaticBody3D, trees: Array, plan) -> void:
	var group := Node3D.new()
	group.name = "Trees"
	for part in [["Conifers", trees[0], conifer_mesh], ["Broadleaves", trees[1], broadleaf_mesh]]:
		var buffer: PackedFloat32Array = part[1]
		if buffer.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = part[2]
		multimesh.instance_count = buffer.size() / TREE_FLOATS
		multimesh.buffer = buffer
		var node := MultiMeshInstance3D.new()
		node.name = part[0]
		node.multimesh = multimesh
		node.material_override = tree_material
		node.visibility_range_end = TREE_VISIBILITY_END
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = _chunk_bounds(plan, trees[2])
		group.add_child(node)
	if group.get_child_count() > 0:
		chunk.add_child(group)
	else:
		group.free()
```

  (`_chunk_bounds(plan, tallest)` already exists for buildings: `tallest` there is height above the wall, as here.)
- [ ] **Step 4: Run** `rt.sh test_terrain_dressing test_tree_shapes` → pass. Probe one forest chunk's `build_ground` time and the tree count; ledger it.
- [ ] **Step 5: Commit** "Forests on hills and mountains: tree buffers built on workers, MultiMesh per chunk".

---

### Task 5: World, physics and timing

**Files:** Tests `tests/test_interior_world.gd`, `tests/test_interior_world_physics.gd`, `tests/test_interior_streaming.gd` (only if they need it); maybe `scripts/interior_world.gd` constants.

- [ ] **Step 1:** Run `rt.sh test_interior_world test_interior_world_physics test_interior_streaming`. Expected: all pass; ledger `interior build` and `worst frame`. The light test also checks the tree MultiMeshes.
- [ ] **Step 2: Decision rules.**
  - docking build > 3000 ms or worst frame > 50 ms: profile (phases: plans / grounds / dress, as in the relief work) and fix the dominant phase; first candidates: tree loop cost (hoist per-lot values), `TREE_SPACING` 17 → 20 m only with a ledgered ruling (it changes a spec number).
  - worst frame in 35–50 ms: lower `CHUNKS_DRESSED_PER_FRAME` (16 → 12 → 8) while `_test_flying_along_the_chain_finds_each_section_ready` passes.
- [ ] **Step 3:** If the physics hillside test's point search finds no spot, it now has hills and mountains to find: it should pass unchanged; if not, fix the search (not the bound).
- [ ] **Step 4:** Full suite `suite.sh` → every file ok (41 files: + `test_tree_shapes`).
- [ ] **Step 5: Commit** (only if files changed) "Interior world checks with hills, chains and forests".

---

### Task 6: Live check

- [ ] **Step 1:** Headless game run: `<binary> --headless --path . --quit-after 900` → no `SCRIPT ERROR|Parse Error|^ERROR|WARNING`.
- [ ] **Step 2:** xvfb render probe (as in the relief work, `scratchpad/probe_relief.gd` logic) from the docked bridge of a section index that has a chain (use `SectionGenerator.chain_wanted` to pick a `docked_bridge_index` whose section 0 = index + 1 has one), camera 300 m above ground looking at the highest point; save `scratchpad/chain.png`; look at it: chain with crest variation and spires, forest to ~600 m, rock above, forested hills, flat fields.
- [ ] **Step 3:** Hand over to the user for the live check (FPS over forests, chain look); tell them which station bridge to dock at to see a chain.
