# Sci-fi Buildings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the box buildings inside the sections with nine low-poly sci-fi shapes (by zone) and one shader with four facade types, per-building light colours and no windows on roofs, colliding as convex hulls.

**Architecture:** `section_plan.gd` gains `Style`/`Facade` enums and four per-building arrays (style, facade, accent, lit share) that `section_generator.gd` fills from a separate seeded RNG per building (positions and sizes unchanged). A new `building_shapes.gd` builds each shape once as an `ArrayMesh` in the centred unit box, mostly by "lathing" a footprint outline through rings of (height, scale), and gives its convex hull. `terrain_dressing.gd` draws one `MultiMeshInstance3D` per style present in a chunk (under a `Buildings` node) with per-instance colour and custom data, collides each building with its style's hull scaled to its size, and uses a new shader that paints facades only on walls.

**Tech Stack:** Godot 4.6.1 double-precision build, GDScript, `gl_compatibility` renderer. Headless `extends SceneTree` tests; offscreen renders through `xvfb-run`.

**Spec:** `docs/superpowers/specs/2026-09-26-scifi-buildings-design.md`

## Global Constraints

- Godot binary: `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64`. One test file: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/<file>.gd`.
- Full suite: `bash /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/suite.sh` (every `tests/*.gd` must print exactly `ALL TESTS PASSED`). If the script is gone, recreate it: loop over `tests/*.gd`, run each with `timeout 600`, grep for `ALL TESTS PASSED|TEST\(S\) FAILED|FAIL |SCRIPT ERROR|Parse Error`, fail unless the grep is exactly `ALL TESTS PASSED`.
- **Reading RED:** a missing method prints `SCRIPT ERROR: ... Nonexistent function`; a missing preload or member prints `Parse Error`. RED is those lines or `FAIL` lines, never the summary alone. A script error before `quit()` can hang: always use `timeout`.
- **Fresh worktree:** run `/home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --import > /dev/null 2>&1` once before the first test run, and again after creating a new script/test to get its `.uid`.
- **Worktree shell rule:** in a worktree session, Bash commands with shell variables, loops or `bash -c` are refused. Use literal paths, one command per call; put multi-step edits in a Python file in the scratchpad and run it.
- **Headless MultiMesh:** the dummy renderer stores no instance data (transforms, colours, custom data read back empty) and reports no AABB. Tests read the pure functions that feed the MultiMesh (`chunk_building_transforms`, `building_custom`) and `custom_aabb`; `instance_count` and flags are readable.
- **Winding (probed):** for a triangle (a, b, c) Godot's front face normal is opposite to `(b - a).cross(c - a)`.
- **Convex shapes (probed):** `Mesh.create_convex_shape(true, false)` works headless; a `ConvexPolygonShape3D` with ~24 points costs ~24.5 µs to create.
- `find_children()` on code-built nodes must pass `owned = false`.
- GDScript: explicit types where builtins return Variant; do not name locals `basis`, `transform`, `position`, `sign`, `owner`, `ready`, `round`; prefix unused parameters with `_`; no bare integer division.
- Code and comments in English, docs in Italian. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `.claude/worktrees/`. Add Godot-generated `.uid` files.
- Live check: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"` prints nothing. Never launch a windowed run; renders through `xvfb-run -a`.

## Review Focus

1. **Shader compile errors only show with a real renderer** — headless tests cannot catch them. Task 4 renders under xvfb and greps for `SHADER ERROR`/`ERROR`; Task 5 looks at the images.
2. **Loading hitches from thousands of new convex shapes** — worst streaming frame must stay under 50 ms. Test: existing `_test_flying_along_the_chain_finds_each_section_ready` (Task 5 reads its printed worst frame; the spec's fallback is rounding collider sizes to even metres).
3. **Colliders that do not enclose the drawn shape** — the ship would clip into a building. Test: `_test_building_colliders_match_the_drawn_buildings` (Task 3, support-function containment over 26 directions).
4. **Back faces showing or faces culled** — wrong winding makes walls vanish. Test: `_test_faces_wind_the_way_their_normals_point` (Task 2).
5. **Building positions shifting because the RNG sequence changed** — the look uses its own RNG. Test: existing placement tests stay green, plus `_test_same_index_same_looks` (Task 1).

---

### Task 1: Building looks in the plan

**Files:**
- Modify: `scripts/section_plan.gd`, `scripts/section_generator.gd`
- Test: `tests/test_section_generator.gd`

**Interfaces:**
- Produces on `section_plan.gd`: `enum Style { DOME, VAULT, BLOCK, RING_HOUSE, STEPPED, TAPERED, RING_TOWER, FIN_SLAB, SPIRE }`, `enum Facade { BANDS, SPARSE, GLASS, PANELS }`, `const ACCENT_COUNT := 5`, `var building_style: PackedByteArray`, `var building_facade: PackedByteArray`, `var building_accent: PackedByteArray`, `var building_lit: PackedFloat64Array`.
- Produces on `section_generator.gd`: consts `TOWN_LOW_STYLES`, `TOWN_TALL_STYLES`, `CITY_STYLES`, `TOWER_STYLES`, `ACCENT_WEIGHTS`, `LOW_AND_WIDE := 0.7`, `LIT_SHARE := Vector2(0.2, 0.6)`; new `TOWN_COLORS`/`CITY_COLORS` palettes.

- [ ] **Step 1: Write the failing tests**

In `tests/test_section_generator.gd`, add after `failures += _test_group_buildings_by_chunk_covers_every_building_once()`:

```gdscript
	failures += _test_every_building_has_a_look()
	failures += _test_styles_fit_the_zone_and_the_shape()
	failures += _test_looks_vary()
	failures += _test_same_index_same_looks()
```

and append:

```gdscript
func _test_every_building_has_a_look() -> int:
	var n: int = _plan.building_count()
	if _plan.building_style.size() != n or _plan.building_facade.size() != n or _plan.building_accent.size() != n or _plan.building_lit.size() != n:
		print("FAIL _test_every_building_has_a_look: %d buildings, looks %d/%d/%d/%d" % [n, _plan.building_style.size(), _plan.building_facade.size(), _plan.building_accent.size(), _plan.building_lit.size()])
		return 1
	for b in range(n):
		if _plan.building_style[b] >= SectionPlan.Style.size() or _plan.building_facade[b] >= SectionPlan.Facade.size() or _plan.building_accent[b] >= SectionPlan.ACCENT_COUNT or not _in_range(_plan.building_lit[b], 0.2, 0.6):
			print("FAIL _test_every_building_has_a_look: building %d look out of range" % b)
			return 1
	return 0

func _test_styles_fit_the_zone_and_the_shape() -> int:
	for b in range(_plan.building_count()):
		var size: Vector3 = _plan.building_size[b]
		var style: int = _plan.building_style[b]
		var allowed: Array
		if _plan.zones[_plan.building_lot[b]] == SectionPlan.Zone.TOWN:
			var low_and_wide: bool = size.y <= 0.7 * minf(size.x, size.z)
			allowed = SectionGenerator.TOWN_LOW_STYLES if low_and_wide else SectionGenerator.TOWN_TALL_STYLES
		elif size.y >= 150.0:
			allowed = SectionGenerator.TOWER_STYLES
		else:
			allowed = SectionGenerator.CITY_STYLES
		if not allowed.has(style):
			print("FAIL _test_styles_fit_the_zone_and_the_shape: building %d size %s has style %d, allowed %s" % [b, size, style, allowed])
			return 1
	return 0

func _test_looks_vary() -> int:
	var styles := {}
	var facades := {}
	var accents := {}
	var magenta := 0
	for b in range(_plan.building_count()):
		styles[_plan.building_style[b]] = true
		facades[_plan.building_facade[b]] = true
		accents[_plan.building_accent[b]] = true
		if _plan.building_accent[b] == 4:
			magenta += 1
	var share := float(magenta) / _plan.building_count()
	if styles.size() < 8 or facades.size() != 4 or accents.size() != 5 or share >= 0.1 or share <= 0.0:
		print("FAIL _test_looks_vary: %d styles, %d facades, %d accents, magenta share %.3f" % [styles.size(), facades.size(), accents.size(), share])
		return 1
	return 0

func _test_same_index_same_looks() -> int:
	var again = SectionGenerator.generate(42, RADIUS, LENGTH)
	if again.building_x != _plan.building_x or again.building_style != _plan.building_style or again.building_facade != _plan.building_facade or again.building_accent != _plan.building_accent or again.building_lit != _plan.building_lit:
		print("FAIL _test_same_index_same_looks: two plans for section 42 differ")
		return 1
	return 0
```

(`_in_range` already exists in this file.)

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_section_generator.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -5`
Expected: `Parse Error` naming `TOWN_LOW_STYLES` (or `Style`).

- [ ] **Step 3: Implement**

`scripts/section_plan.gd`: after `enum Road { NONE, STREET, MAIN }` add:

```gdscript
# How a building looks (see building_shapes.gd and the building shader).
enum Style { DOME, VAULT, BLOCK, RING_HOUSE, STEPPED, TAPERED, RING_TOWER, FIN_SLAB, SPIRE }
enum Facade { BANDS, SPARSE, GLASS, PANELS }
# Window light colours: warm white, cool white, cyan, amber, magenta.
const ACCENT_COUNT := 5
```

and after `var building_lot := PackedInt32Array()`:

```gdscript
var building_style := PackedByteArray()
var building_facade := PackedByteArray()
var building_accent := PackedByteArray()
# Share of the building's windows that are lit, 0..1.
var building_lit := PackedFloat64Array()
```

`scripts/section_generator.gd`:
- replace the two palette lines with:

```gdscript
# Sci-fi facade colours: towns light (white, light grey, sand, blue-grey,
# pale teal), the city darker (graphite, grey, white, blue-grey, bronze).
const TOWN_COLORS := [Color(0.92, 0.93, 0.95), Color(0.78, 0.8, 0.83), Color(0.85, 0.8, 0.7), Color(0.62, 0.68, 0.75), Color(0.72, 0.82, 0.8)]
const CITY_COLORS := [Color(0.3, 0.32, 0.35), Color(0.55, 0.57, 0.6), Color(0.88, 0.9, 0.92), Color(0.5, 0.58, 0.68), Color(0.42, 0.38, 0.33)]
# Shapes by zone. Domes and vaults only for low, wide town buildings: a dome
# 40 m high on a 12 m base would read as a bullet. Towers are mostly spires.
const TOWN_LOW_STYLES := [SectionPlanScript.Style.DOME, SectionPlanScript.Style.VAULT, SectionPlanScript.Style.BLOCK, SectionPlanScript.Style.RING_HOUSE]
const TOWN_TALL_STYLES := [SectionPlanScript.Style.BLOCK, SectionPlanScript.Style.RING_HOUSE]
const CITY_STYLES := [SectionPlanScript.Style.STEPPED, SectionPlanScript.Style.TAPERED, SectionPlanScript.Style.RING_TOWER, SectionPlanScript.Style.FIN_SLAB]
const TOWER_STYLES := [SectionPlanScript.Style.SPIRE, SectionPlanScript.Style.SPIRE, SectionPlanScript.Style.STEPPED, SectionPlanScript.Style.RING_TOWER]
const LOW_AND_WIDE := 0.7
# Warm white, cool white, cyan, amber, magenta (rare).
const ACCENT_WEIGHTS := [0.3, 0.25, 0.2, 0.18, 0.07]
const LIT_SHARE := Vector2(0.2, 0.6)
```

- in `_place_buildings`:
  - after `var lots := PackedInt32Array()` add:

```gdscript
	var styles := PackedByteArray()
	var facades := PackedByteArray()
	var accents := PackedByteArray()
	var lits := PackedFloat64Array()
```

  - after `var palette: Array` add `var tower := false`;
  - change `var tower: bool = plan.surface_distance(...) <= TOWER_RADIUS` to `tower = plan.surface_distance(plan.lot_center(around, along), plan.city_center) <= TOWER_RADIUS`;
  - after `lots.append(plan.lot_index(around, along))` add:

```gdscript
					var look := _building_look(plan.section_index, around, along, plot_x, plot_z, zone == SectionPlanScript.Zone.TOWN, tower, Vector3(width, height, depth))
					styles.append(look[0])
					facades.append(look[1])
					accents.append(look[2])
					lits.append(look[3])
```

  - after `plan.building_lot = lots` add:

```gdscript
	plan.building_style = styles
	plan.building_facade = facades
	plan.building_accent = accents
	plan.building_lit = lits
```

- append:

```gdscript
# Shape, facade, light colour and lit share of one building, from its own
# RNG: the placement RNG's sequence (positions, sizes) stays as it was.
static func _building_look(section_index: int, around: int, along: int, plot_x: int, plot_z: int, town: bool, tower: bool, size: Vector3) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([section_index, around, along, plot_x, plot_z, "look"])
	var styles: Array
	if town:
		styles = TOWN_LOW_STYLES if size.y <= LOW_AND_WIDE * minf(size.x, size.z) else TOWN_TALL_STYLES
	elif tower:
		styles = TOWER_STYLES
	else:
		styles = CITY_STYLES
	var style: int = styles[rng.randi_range(0, styles.size() - 1)]
	var facade: int = rng.randi_range(0, SectionPlanScript.Facade.size() - 1)
	var accent: int = _pick_weighted(rng.randf(), ACCENT_WEIGHTS)
	var lit: float = rng.randf_range(LIT_SHARE.x, LIT_SHARE.y)
	return [style, facade, accent, lit]

static func _pick_weighted(u: float, weights: Array) -> int:
	var total := 0.0
	for w: float in weights:
		total += w
	var running := 0.0
	for k in range(weights.size()):
		running += weights[k] / total
		if u < running:
			return k
	return weights.size() - 1
```

- [ ] **Step 4: Run to verify it passes**

Run the Step 2 command. Expected: `ALL TESTS PASSED` only (the old placement tests too).
Then the full suite. Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/section_plan.gd scripts/section_generator.gd tests/test_section_generator.gd
git commit -m "Give every building a shape, facade, light colour and lit share

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The shapes

**Files:**
- Create: `scripts/building_shapes.gd`, `tests/test_building_shapes.gd`

**Interfaces:**
- Consumes: Task 1 `SectionPlan.Style`.
- Produces: `building_shapes.gd` with `const NAMES` (node names by style), `const MAX_TRIANGLES := 256`, `static func mesh(style: int) -> ArrayMesh` (cached), `static func hull_points(style: int) -> PackedVector3Array` (cached, unit box).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_building_shapes.gd`:

```gdscript
extends SceneTree

const BuildingShapes = preload("res://scripts/building_shapes.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")

func _init():
	var failures := 0
	failures += _test_one_named_shape_per_style()
	failures += _test_every_shape_fits_the_unit_box_on_its_base()
	failures += _test_faces_wind_the_way_their_normals_point()
	failures += _test_at_most_256_triangles()
	failures += _test_every_shape_has_roof_and_walls()
	failures += _test_every_hull_holds_its_shape()
	failures += _test_spire_ends_in_a_thin_antenna()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	quit()

func _arrays(style: int) -> Array:
	return BuildingShapes.mesh(style).surface_get_arrays(0)

func _test_one_named_shape_per_style() -> int:
	if BuildingShapes.NAMES.size() != SectionPlan.Style.size():
		print("FAIL _test_one_named_shape_per_style: %d names for %d styles" % [BuildingShapes.NAMES.size(), SectionPlan.Style.size()])
		return 1
	if BuildingShapes.mesh(SectionPlan.Style.DOME) != BuildingShapes.mesh(SectionPlan.Style.DOME):
		print("FAIL _test_one_named_shape_per_style: meshes are rebuilt instead of shared")
		return 1
	return 0

func _test_every_shape_fits_the_unit_box_on_its_base() -> int:
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var vertices: PackedVector3Array = _arrays(style)[Mesh.ARRAY_VERTEX]
		var box := AABB(vertices[0], Vector3.ZERO)
		var base := AABB(Vector3.ZERO, Vector3.ZERO)
		var base_started := false
		for v in vertices:
			box = box.expand(v)
			if is_equal_approx(v.y, -0.5):
				if not base_started:
					base = AABB(v, Vector3.ZERO)
					base_started = true
				base = base.expand(v)
		var inside := box.position.x >= -0.5001 and box.end.x <= 0.5001 and box.position.z >= -0.5001 and box.end.z <= 0.5001
		var spans := is_equal_approx(box.position.y, -0.5) and is_equal_approx(box.end.y, 0.5)
		var footprint := base_started and base.size.x >= 0.9 and base.size.z >= 0.9
		if not inside or not spans or not footprint:
			print("FAIL _test_every_shape_fits_the_unit_box_on_its_base: %s box %s base %s" % [BuildingShapes.NAMES[style], box, base])
			result = 1
	return result

func _test_faces_wind_the_way_their_normals_point() -> int:
	# Godot's front face normal is opposite to (b - a) x (c - a).
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var arrays := _arrays(style)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for t in range(0, vertices.size(), 3):
			var cross := (vertices[t + 1] - vertices[t]).cross(vertices[t + 2] - vertices[t])
			if cross.dot(normals[t]) >= 0.0 or not is_equal_approx(normals[t].length(), 1.0):
				print("FAIL _test_faces_wind_the_way_their_normals_point: %s triangle at vertex %d winds against its normal %s" % [BuildingShapes.NAMES[style], t, normals[t]])
				result = 1
				break
	return result

func _test_at_most_256_triangles() -> int:
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var vertices: PackedVector3Array = _arrays(style)[Mesh.ARRAY_VERTEX]
		if vertices.size() > BuildingShapes.MAX_TRIANGLES * 3 or vertices.size() % 3 != 0:
			print("FAIL _test_at_most_256_triangles: %s has %d vertices" % [BuildingShapes.NAMES[style], vertices.size()])
			result = 1
	return result

func _test_every_shape_has_roof_and_walls() -> int:
	# The shader paints facades only where |n.y| < 0.5: every shape needs both.
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var normals: PackedVector3Array = _arrays(style)[Mesh.ARRAY_NORMAL]
		var roof := false
		var wall := false
		for n in normals:
			roof = roof or n.y > 0.9
			wall = wall or absf(n.y) < 0.5
		if not roof or not wall:
			print("FAIL _test_every_shape_has_roof_and_walls: %s roof %s walls %s" % [BuildingShapes.NAMES[style], roof, wall])
			result = 1
	return result

func _directions() -> Array:
	var dirs := []
	for x in [-1.0, 0.0, 1.0]:
		for y in [-1.0, 0.0, 1.0]:
			for z in [-1.0, 0.0, 1.0]:
				if x != 0.0 or y != 0.0 or z != 0.0:
					dirs.append(Vector3(x, y, z).normalized())
	return dirs

func _test_every_hull_holds_its_shape() -> int:
	# In every direction the hull reaches at least as far as the mesh.
	var result := 0
	for style in range(SectionPlan.Style.size()):
		var hull: PackedVector3Array = BuildingShapes.hull_points(style)
		var vertices: PackedVector3Array = _arrays(style)[Mesh.ARRAY_VERTEX]
		if hull.size() < 4:
			print("FAIL _test_every_hull_holds_its_shape: %s hull has %d points" % [BuildingShapes.NAMES[style], hull.size()])
			result = 1
			continue
		for d: Vector3 in _directions():
			var hull_reach := -INF
			for p in hull:
				hull_reach = maxf(hull_reach, p.dot(d))
			var mesh_reach := -INF
			for v in vertices:
				mesh_reach = maxf(mesh_reach, v.dot(d))
			if hull_reach < mesh_reach - 1e-4:
				print("FAIL _test_every_hull_holds_its_shape: %s hull short by %f toward %s" % [BuildingShapes.NAMES[style], mesh_reach - hull_reach, d])
				result = 1
				break
	return result

func _test_spire_ends_in_a_thin_antenna() -> int:
	var vertices: PackedVector3Array = _arrays(SectionPlan.Style.SPIRE)[Mesh.ARRAY_VERTEX]
	for v in vertices:
		if v.y > 0.45 and (absf(v.x) > 0.05 or absf(v.z) > 0.05):
			print("FAIL _test_spire_ends_in_a_thin_antenna: vertex %s near the top is too wide" % v)
			return 1
	return 0
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 120 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_building_shapes.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -3`
Expected: `Parse Error` (preload of `building_shapes.gd` fails).

- [ ] **Step 3: Implement**

Create `scripts/building_shapes.gd`:

```gdscript
extends RefCounted

# The sci-fi building shapes, built in code once each: low-poly meshes in
# the unit box centred on the origin (x and z from -0.5 to 0.5, y from -0.5
# to 0.5, base at y = -0.5), so terrain_dressing's building_transform
# stretches them to each building's size. Most are "lathed": a footprint
# outline repeated in rings of (height 0..1, scale); a ring at the same
# height as the one before but narrower makes a ledge, which is roof.
# Normals are flat per face (low-poly look).

const SectionPlanScript = preload("res://scripts/section_plan.gd")

# Node names, by SectionPlan.Style.
const NAMES := ["Dome", "Vault", "Block", "RingHouse", "Stepped", "Tapered", "RingTower", "FinSlab", "Spire"]
const MAX_TRIANGLES := 256
const ROUND_SIDES := 12

static var _meshes := {}
static var _hulls := {}

static func mesh(style: int) -> ArrayMesh:
	if not _meshes.has(style):
		_meshes[style] = _build(style)
	return _meshes[style]

# The shape's convex hull in the unit box. Buildings of this style collide
# as it, stretched to their size: recesses (steps, gaps between fins) are
# solid.
static func hull_points(style: int) -> PackedVector3Array:
	if not _hulls.has(style):
		var shape := mesh(style).create_convex_shape(true, false) as ConvexPolygonShape3D
		_hulls[style] = shape.points
	return _hulls[style]

static func _build(style: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var square := _polygon(4, sqrt(0.5), PI / 4.0)
	var octagon := _polygon(8, 0.5 / cos(PI / 8.0), PI / 8.0)
	var circle := _polygon(ROUND_SIDES, 0.5, 0.0)
	if style == SectionPlanScript.Style.DOME:
		var rings := [Vector2(0.0, 1.0), Vector2(0.3, 1.0)]
		for k in range(1, 5):
			var a: float = k * PI / 8.0
			rings.append(Vector2(0.3 + 0.7 * sin(a), cos(a)))
		_lathe(st, circle, rings)
	elif style == SectionPlanScript.Style.VAULT:
		_vault(st)
	elif style == SectionPlanScript.Style.BLOCK:
		_lathe(st, octagon, [Vector2(0.0, 1.0), Vector2(0.88, 1.0), Vector2(0.88, 0.82), Vector2(1.0, 0.82)])
	elif style == SectionPlanScript.Style.RING_HOUSE:
		_lathe(st, circle, [Vector2(0.0, 0.85), Vector2(0.45, 0.85), Vector2(0.45, 1.0), Vector2(0.55, 1.0), Vector2(0.55, 0.85), Vector2(1.0, 0.85)])
	elif style == SectionPlanScript.Style.STEPPED:
		_lathe(st, square, [Vector2(0.0, 1.0), Vector2(0.5, 1.0), Vector2(0.5, 0.8), Vector2(0.75, 0.8), Vector2(0.75, 0.6), Vector2(1.0, 0.6)])
	elif style == SectionPlanScript.Style.TAPERED:
		_lathe(st, octagon, [Vector2(0.0, 1.0), Vector2(0.88, 0.72), Vector2(0.88, 0.62), Vector2(1.0, 0.62)])
	elif style == SectionPlanScript.Style.RING_TOWER:
		_lathe(st, circle, [Vector2(0.0, 0.8), Vector2(0.35, 0.8), Vector2(0.35, 1.0), Vector2(0.4, 1.0), Vector2(0.4, 0.8), Vector2(0.7, 0.8), Vector2(0.7, 1.0), Vector2(0.75, 1.0), Vector2(0.75, 0.8), Vector2(1.0, 0.8)])
	elif style == SectionPlanScript.Style.FIN_SLAB:
		_lathe(st, _rect(-0.3, 0.3, -0.5, 0.5), [Vector2(0.0, 1.0), Vector2(1.0, 1.0)])
		for side in [-1.0, 1.0]:
			for z0 in [-0.42, 0.34]:
				var x0: float = 0.28 if side > 0.0 else -0.5
				_lathe(st, _rect(x0, x0 + 0.22, z0, z0 + 0.08), [Vector2(0.0, 1.0), Vector2(0.94, 1.0)])
	else:  # SPIRE
		_lathe(st, octagon, [Vector2(0.0, 1.0), Vector2(0.45, 0.78), Vector2(0.7, 0.55), Vector2(0.82, 0.35), Vector2(0.82, 0.06), Vector2(1.0, 0.04)])
	return st.commit()

# Regular polygon in the (x, z) plane, anticlockwise seen from above.
static func _polygon(sides: int, radius: float, turn: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in range(sides):
		var a: float = turn + TAU * k / sides
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points

# Rectangle in (x, z), same turning sense as _polygon.
static func _rect(x0: float, x1: float, z0: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x1, z1), Vector2(x0, z1), Vector2(x0, z0), Vector2(x1, z0)])

# Outline point p (x, z) at ring (height 0..1, scale), in the centred box.
static func _at(p: Vector2, ring: Vector2) -> Vector3:
	return Vector3(p.x * ring.y, ring.x - 0.5, p.y * ring.y)

static func _lathe(st: SurfaceTool, outline: PackedVector2Array, rings: Array) -> void:
	for r in range(rings.size() - 1):
		var low: Vector2 = rings[r]
		var high: Vector2 = rings[r + 1]
		for i in range(outline.size()):
			var p := outline[i]
			var q := outline[(i + 1) % outline.size()]
			var edge := q - p
			var out := Vector3(edge.y, 0.0, -edge.x).normalized()
			# Out as the profile climbs, up as it steps in, down as it steps out.
			var hint: Vector3 = out * (high.x - low.x) + Vector3.UP * (low.y - high.y) * ((p + q) * 0.5).length()
			_quad(st, _at(p, low), _at(q, low), _at(q, high), _at(p, high), hint)
	var top: Vector2 = rings[rings.size() - 1]
	if top.y > 1e-6:
		var centre := Vector2.ZERO
		for p in outline:
			centre += p
		centre /= outline.size()
		for i in range(outline.size()):
			_face(st, _at(centre, top), _at(outline[i], top), _at(outline[(i + 1) % outline.size()], top), Vector3.UP)

# A module lying along z: walls to half height, a half-round roof, flat ends.
static func _vault(st: SurfaceTool) -> void:
	var profile := PackedVector2Array([Vector2(-0.5, 0.0), Vector2(-0.5, 0.5)])
	for k in range(1, 7):
		var a: float = PI - k * PI / 6.0
		profile.append(Vector2(0.5 * cos(a), 0.5 + 0.5 * sin(a)))
	profile.append(Vector2(0.5, 0.0))
	for i in range(profile.size() - 1):
		var p := profile[i]
		var q := profile[i + 1]
		var hint := Vector3(-(q.y - p.y), q.x - p.x, 0.0)
		_quad(st, Vector3(p.x, p.y - 0.5, -0.5), Vector3(q.x, q.y - 0.5, -0.5), Vector3(q.x, q.y - 0.5, 0.5), Vector3(p.x, p.y - 0.5, 0.5), hint)
	for z in [-0.5, 0.5]:
		var centre := Vector3(0.0, -0.1, z)
		for i in range(profile.size()):
			var p := profile[i]
			var q := profile[(i + 1) % profile.size()]
			_face(st, centre, Vector3(p.x, p.y - 0.5, z), Vector3(q.x, q.y - 0.5, z), Vector3(0.0, 0.0, z))

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
	_face(st, a, b, c, hint)
	_face(st, a, c, d, hint)

# One flat triangle facing the `hint` side, wound as Godot expects (its
# normal opposite to (b - a) x (c - a)). Degenerate ones are skipped.
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length() < 1e-9:
		return
	var n := cross.normalized()
	if n.dot(hint) < 0.0:
		n = -n
	if cross.dot(n) > 0.0:
		var swap := b
		b = c
		c = swap
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)
```

- [ ] **Step 4: Run to verify it passes**

Run the Step 2 command. Expected: `ALL TESTS PASSED` only. Then run `--import` for the two `.uid` files.

If `_test_faces_wind_the_way_their_normals_point` fails only on the vault end caps (their fan centre sits on the cap plane, so hints are exact) or `_test_every_shape_fits_the_unit_box_on_its_base` fails on a footprint, fix the shape data, not the test, and ledger it.

- [ ] **Step 5: Commit**

```bash
git add scripts/building_shapes.gd scripts/building_shapes.gd.uid tests/test_building_shapes.gd tests/test_building_shapes.gd.uid
git commit -m "Add nine low-poly sci-fi building shapes built in code

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: One MultiMesh per shape, convex colliders

**Files:**
- Modify: `scripts/terrain_dressing.gd` (`_build_buildings`, `_box_mesh`, `_box_shapes`, `_box_shape`)
- Test: `tests/test_terrain_dressing.gd`, `tests/test_interior_world.gd`, `tests/test_internal_cruiser_physics.gd`

**Interfaces:**
- Consumes: Task 1 look arrays; Task 2 `BuildingShapes.mesh`, `hull_points`, `NAMES`.
- Produces on `terrain_dressing.gd`: `static func building_custom(plan, b: int) -> Color` (facade, accent, lit, seed); chunk node `Buildings` (Node3D) with one `MultiMeshInstance3D` per style present, named `BuildingShapes.NAMES[style]`, `use_colors` and `use_custom_data` on; one convex shape owner per building in index order.

- [ ] **Step 1: Write the failing tests**

In `tests/test_terrain_dressing.gd`:
- add below `const TerrainDressing = ...`:

```gdscript
const BuildingShapes = preload("res://scripts/building_shapes.gd")
```

- replace the line `failures += _test_windows_follow_each_building()` with nothing (the shader test comes in Task 4) and add after `failures += _test_building_bounds_cover_the_tallest_building()`:

```gdscript
	failures += _test_building_custom_data_carries_the_look()
```

- replace the whole functions `_test_chunk_buildings_match_the_plan`, `_test_building_colliders_match_the_drawn_buildings`, `_test_building_bounds_cover_the_tallest_building` and `_test_windows_follow_each_building` with:

```gdscript
# The chunk's buildings of `style`, in index order.
func _indices_of_style(indices: Array, style: int) -> Array:
	return indices.filter(func(b: int) -> bool: return _plan.building_style[b] == style)

func _test_chunk_buildings_match_the_plan() -> int:
	var key := _busiest_chunk()
	var indices: Array = _groups[key]
	var chunk := _dress(key)
	var result := 0
	var group := chunk.get_node_or_null("Buildings")
	if group == null or chunk.get_shape_owners().size() != indices.size():
		print("FAIL _test_chunk_buildings_match_the_plan: chunk %s has no Buildings node or %d colliders for %d buildings" % [key, chunk.get_shape_owners().size(), indices.size()])
		chunk.free()
		return 1
	var total := 0
	for style in range(SectionPlan.Style.size()):
		var expected: int = _indices_of_style(indices, style).size()
		var node := group.get_node_or_null(BuildingShapes.NAMES[style]) as MultiMeshInstance3D
		if expected == 0:
			if node != null:
				print("FAIL _test_chunk_buildings_match_the_plan: %s drawn with no building of that shape" % BuildingShapes.NAMES[style])
				result = 1
			continue
		if node == null or node.multimesh.instance_count != expected or node.multimesh.mesh != BuildingShapes.mesh(style) or not node.multimesh.use_colors or not node.multimesh.use_custom_data:
			print("FAIL _test_chunk_buildings_match_the_plan: %s expected %d instances of its mesh with colours and custom data" % [BuildingShapes.NAMES[style], expected])
			result = 1
			continue
		if node.visibility_range_end != TerrainDressing.BUILDING_VISIBILITY_END or node.material_override != _dressing.building_material:
			print("FAIL _test_chunk_buildings_match_the_plan: %s visibility %f or wrong material" % [BuildingShapes.NAMES[style], node.visibility_range_end])
			result = 1
		total += node.multimesh.instance_count
	if total != indices.size():
		print("FAIL _test_chunk_buildings_match_the_plan: %d instances for %d buildings" % [total, indices.size()])
		result = 1
	chunk.free()
	return result

func _directions() -> Array:
	var dirs := []
	for x in [-1.0, 0.0, 1.0]:
		for y in [-1.0, 0.0, 1.0]:
			for z in [-1.0, 0.0, 1.0]:
				if x != 0.0 or y != 0.0 or z != 0.0:
					dirs.append(Vector3(x, y, z).normalized())
	return dirs

func _test_building_colliders_match_the_drawn_buildings() -> int:
	var key := _busiest_chunk()
	var indices: Array = _groups[key]
	var chunk := _dress(key)
	# Headless runs cannot read MultiMesh instances back; compare with the
	# transforms the dressing draws them with.
	var drawn_list := TerrainDressing.chunk_building_transforms(_plan, key.x, key.y, indices)
	var owners: PackedInt32Array = chunk.get_shape_owners()
	var result := 0
	for k in range(indices.size()):
		var b: int = indices[k]
		var drawn: Transform3D = drawn_list[k]
		var collider: Transform3D = chunk.shape_owner_get_transform(owners[k])
		var shape := chunk.shape_owner_get_shape(owners[k], 0) as ConvexPolygonShape3D
		if not collider.is_equal_approx(drawn.orthonormalized()) or shape == null:
			print("FAIL _test_building_colliders_match_the_drawn_buildings: building %d collider %s (%s) vs drawn %s" % [b, collider, shape, drawn])
			result = 1
			break
		# Every drawn vertex, in the collider's frame, lies within the hull.
		var size: Vector3 = _plan.building_size[b]
		var vertices: PackedVector3Array = BuildingShapes.mesh(_plan.building_style[b]).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for d: Vector3 in _directions():
			var hull_reach := -INF
			for p in shape.points:
				hull_reach = maxf(hull_reach, p.dot(d))
			var mesh_reach := -INF
			for v in vertices:
				mesh_reach = maxf(mesh_reach, (v * size).dot(d))
			if hull_reach < mesh_reach - 1e-3:
				print("FAIL _test_building_colliders_match_the_drawn_buildings: building %d collider short by %f toward %s" % [b, mesh_reach - hull_reach, d])
				result = 1
				break
		if result:
			break
	chunk.free()
	return result

func _test_building_bounds_cover_the_tallest_building() -> int:
	# Headless renderers report no MultiMesh bounds; custom_aabb must hold them.
	var key := _busiest_chunk()
	var indices: Array = _groups[key]
	var chunk := _dress(key)
	var xforms := TerrainDressing.chunk_building_transforms(_plan, key.x, key.y, indices)
	var result := 0
	for k in range(indices.size()):
		var node: MultiMeshInstance3D = chunk.get_node("Buildings/" + BuildingShapes.NAMES[_plan.building_style[indices[k]]])
		var top: Vector3 = xforms[k] * Vector3(0.0, 0.5, 0.0)
		if not node.custom_aabb.has_point(top):
			print("FAIL _test_building_bounds_cover_the_tallest_building: top %s outside %s" % [top, node.custom_aabb])
			result = 1
			break
	chunk.free()
	return result

func _test_building_custom_data_carries_the_look() -> int:
	var result := 0
	for b in range(0, _plan.building_count(), 97):
		var custom: Color = TerrainDressing.building_custom(_plan, b)
		if not is_equal_approx(custom.r, _plan.building_facade[b]) or not is_equal_approx(custom.g, _plan.building_accent[b]) or not is_equal_approx(custom.b, _plan.building_lit[b]) or custom.a < 0.0 or custom.a >= 1.0:
			print("FAIL _test_building_custom_data_carries_the_look: building %d custom %s" % [b, custom])
			result = 1
			break
	return result
```

In `tests/test_interior_world.gd`, in `_test_sections_come_from_their_ring_indices`, replace the four lines from `var buildings := world.get_node(...)` to the `result = 1` that closes that check with:

```gdscript
	var buildings := world.get_node_or_null("Chain/Section_0/Chunk_%02d_%02d/Buildings" % [key.x, key.y])
	var drawn := 0
	if buildings != null:
		for node in buildings.get_children():
			drawn += (node as MultiMeshInstance3D).multimesh.instance_count
	if drawn != groups[key].size():
		print("FAIL _test_sections_come_from_their_ring_indices: chunk %s draws %d of the plan's %d buildings" % [key, drawn, groups[key].size()])
		result = 1
```

In `tests/test_internal_cruiser_physics.gd`, in `_test_hits_a_building_and_bounces`, change the comment `# Toward the tallest tower, just below its roof, along +Z.` to `# Toward the tallest tower, a third of the way up (shapes narrow toward the top), along +Z.` and change `size.y - 3.0` to `size.y * 0.3`.

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_terrain_dressing.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -6`
Expected: `SCRIPT ERROR` naming `building_custom` and `FAIL` lines (no per-style nodes, box colliders).
Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_interior_world.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -4`
Expected: `SCRIPT ERROR` (casting the old `Buildings` MultiMeshInstance3D's children) or `FAIL _test_sections_come_from_their_ring_indices`.

- [ ] **Step 3: Implement**

In `scripts/terrain_dressing.gd`:
- add below `const SectionPlanScript = ...`:

```gdscript
const BuildingShapesScript = preload("res://scripts/building_shapes.gd")
```

- replace `var _box_mesh := BoxMesh.new()` and `var _box_shapes := {}` with:

```gdscript
# Convex colliders by (style, whole-metre size): equal buildings share one.
var _convex_shapes := {}
```

- replace `_build_buildings` and `_box_shape` with:

```gdscript
# Per-instance data for the building shader: facade, light colour, share of
# windows lit, and a seed in 0..1 that varies the pattern between buildings.
static func building_custom(plan, b: int) -> Color:
	return Color(float(plan.building_facade[b]), float(plan.building_accent[b]), plan.building_lit[b], fposmod(b * 0.618034, 1.0))

func _build_buildings(chunk: StaticBody3D, plan, chunk_around: int, chunk_along: int, indices: Array) -> void:
	var xforms := chunk_building_transforms(plan, chunk_around, chunk_along, indices)
	# Colliders straight on the chunk body, in index order: thousands of
	# nodes would slow docking down.
	var by_style := {}
	for k in range(indices.size()):
		var b: int = indices[k]
		var style: int = plan.building_style[b]
		if not by_style.has(style):
			by_style[style] = []
		by_style[style].append(k)
		var owner_id := chunk.create_shape_owner(chunk)
		chunk.shape_owner_add_shape(owner_id, _convex_shape(style, plan.building_size[b]))
		chunk.shape_owner_set_transform(owner_id, xforms[k].orthonormalized())
	var group := Node3D.new()
	group.name = "Buildings"
	chunk.add_child(group)
	# One MultiMesh per shape present in the chunk.
	for style: int in by_style:
		var ks: Array = by_style[style]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = BuildingShapesScript.mesh(style)
		multimesh.instance_count = ks.size()
		var tallest := 0.0
		for i in range(ks.size()):
			var k: int = ks[i]
			var b: int = indices[k]
			multimesh.set_instance_transform(i, xforms[k])
			multimesh.set_instance_color(i, plan.building_color[b])
			multimesh.set_instance_custom_data(i, building_custom(plan, b))
			tallest = maxf(tallest, plan.building_size[b].y)
		var instance := MultiMeshInstance3D.new()
		instance.name = BuildingShapesScript.NAMES[style]
		instance.multimesh = multimesh
		instance.material_override = building_material
		instance.visibility_range_end = BUILDING_VISIBILITY_END
		instance.custom_aabb = _chunk_bounds(plan, tallest)
		group.add_child(instance)

func _convex_shape(style: int, size: Vector3) -> ConvexPolygonShape3D:
	var key := Vector4i(style, roundi(size.x), roundi(size.y), roundi(size.z))
	if not _convex_shapes.has(key):
		var points := PackedVector3Array()
		for p in BuildingShapesScript.hull_points(style):
			points.append(p * size)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		_convex_shapes[key] = shape
	return _convex_shapes[key]
```

- [ ] **Step 4: Run to verify it passes**

Run the two Step 2 commands, plus:
`timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_internal_cruiser_physics.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED"`
Expected: `ALL TESTS PASSED` only, for each. (The old window shader still works on the new meshes until Task 4.)
Then the full suite. Expected: all green; note the `worst frame while streaming` line of `test_interior_streaming` in the ledger.

- [ ] **Step 5: Commit**

```bash
git add scripts/terrain_dressing.gd tests/test_terrain_dressing.gd tests/test_interior_world.gd tests/test_internal_cruiser_physics.gd
git commit -m "Draw buildings as one MultiMesh per shape and collide them as convex hulls

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The facade shader

**Files:**
- Modify: `scripts/terrain_dressing.gd` (`BUILDING_SHADER`, window constants, `_init`, `_window_texture`)
- Test: `tests/test_terrain_dressing.gd`
- Create (scratchpad only): `/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_buildings.gd`

**Interfaces:**
- Consumes: Task 3 custom data layout (`r` facade, `g` accent, `b` lit share, `a` seed) and instance colour.
- Produces: `building_material` (ShaderMaterial) with one uniform `glow_energy`; no window textures.

- [ ] **Step 1: Write the failing test**

In `tests/test_terrain_dressing.gd`, add after `failures += _test_building_custom_data_carries_the_look()`:

```gdscript
	failures += _test_building_shader_reads_each_building()
```

and append:

```gdscript
func _test_building_shader_reads_each_building() -> int:
	# Headless has no real renderer: check the code; Task 4 renders it too.
	var material = _dressing.building_material
	if not (material is ShaderMaterial):
		print("FAIL _test_building_shader_reads_each_building: building material is %s" % material.get_class())
		return 1
	var code: String = (material as ShaderMaterial).shader.code
	var result := 0
	for needle in ["INSTANCE_CUSTOM", "abs(local_normal.y) >= 0.5", "atan(local_position.z, local_position.x)", "ACCENTS[", "EMISSION = accent * glow"]:
		if not code.contains(needle):
			print("FAIL _test_building_shader_reads_each_building: shader lacks '%s'" % needle)
			result = 1
	if (material as ShaderMaterial).get_shader_parameter("glow_energy") == null:
		print("FAIL _test_building_shader_reads_each_building: glow_energy not set")
		result = 1
	return result
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_terrain_dressing.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|FAIL|PASSED" | head -6`
Expected: `FAIL _test_building_shader_reads_each_building` lines (old shader).

- [ ] **Step 3: Implement**

In `scripts/terrain_dressing.gd`:
- delete `const WINDOW_SPACING := 4.0`, `const WINDOW_GLOW_COLOR := ...`, `const WINDOW_GLOW_ENERGY := 0.8`, and the whole `_window_texture` function;
- replace the comment block above `var building_material` (the "Windows projected in each building's own frame..." lines) with:

```gdscript
# One shader for every building (see BUILDING_SHADER): facades only on walls,
# driven by each instance's colour and custom data (building_custom).
```

- replace the `BUILDING_SHADER` constant with:

```gdscript
const BUILDING_GLOW_ENERGY := 1.2
const BUILDING_SHADER := """
shader_type spatial;

uniform float glow_energy = 1.2;

// Filled in vertex(): position in metres in the building's own frame (base
// centre at the origin), the surface normal after the stretch, and the
// per-building data (TerrainDressing.building_custom).
varying vec3 local_position;
varying vec3 local_normal;
varying vec4 look;
varying float half_width;
varying float height;

// Warm white, cool white, cyan, amber, magenta.
const vec3 ACCENTS[5] = vec3[5](
	vec3(1.0, 0.82, 0.55),
	vec3(0.8, 0.9, 1.0),
	vec3(0.3, 0.9, 1.0),
	vec3(1.0, 0.6, 0.2),
	vec3(1.0, 0.3, 0.8));

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local_position = VERTEX * scale + vec3(0.0, 0.5 * scale.y, 0.0);
	local_normal = normalize(NORMAL / scale);
	half_width = 0.25 * (scale.x + scale.z);
	height = scale.y;
	look = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 wall = COLOR.rgb;
	int facade = int(look.x + 0.5);
	vec3 accent = ACCENTS[clamp(int(look.y + 0.5), 0, 4)];
	float lit_share = look.z;
	float seed = look.w;
	// Metres round the building and up from its base: the same window size
	// on any shape, and no seams on the round ones.
	float around = atan(local_position.z, local_position.x) * half_width;
	float up = local_position.y;
	vec3 albedo = wall;
	float glow = 0.0;
	float metal = 0.1;
	float rough = 0.8;
	if (abs(local_normal.y) >= 0.5) {
		// Roofs, ledges and the tops of domes: plain, never windows.
		albedo = wall * 0.7;
	} else if (facade == 0) {
		// Bands of glass every 1 to 3 floors, each 8 m stretch lit or not.
		float period = 4.0 * (1.0 + floor(hash(vec2(seed, 1.0)) * 3.0));
		float band = step(mod(up, period), 1.2) * step(2.0, up);
		float lit = step(hash(vec2(floor(around / 8.0), floor(up / period)) + seed), 0.3 + lit_share);
		albedo = mix(wall, vec3(0.08, 0.1, 0.12), band);
		glow = band * lit;
	} else if (facade == 1) {
		// Sparse square windows, 1.5 m every 6 m across and 4 m up.
		vec2 cell = vec2(floor(around / 6.0), floor(up / 4.0));
		float pane = step(mod(around, 6.0), 1.5) * step(1.5, mod(up, 4.0)) * step(mod(up, 4.0), 3.0) * step(2.0, up);
		float lit = step(hash(cell + seed), lit_share);
		albedo = mix(wall, vec3(0.08, 0.1, 0.12), pane);
		glow = pane * lit;
	} else if (facade == 2) {
		// Dark glass all over, a light here and there.
		vec2 cell = vec2(floor(around / 3.0), floor(up / 4.0));
		float spot = step(0.3, fract(around / 3.0)) * step(fract(around / 3.0), 0.7) * step(0.3, fract(up / 4.0)) * step(fract(up / 4.0), 0.7);
		albedo = vec3(0.05, 0.07, 0.09) + wall * 0.05;
		metal = 0.8;
		rough = 0.15;
		glow = spot * step(hash(cell + seed), 0.05);
	} else {
		// Blind panels with seams, and a thin glowing band under the roof.
		float seam = max(step(mod(around, 4.0), 0.15), step(mod(up, 4.0), 0.15));
		albedo = wall * (1.0 - 0.4 * seam);
		metal = 0.5;
		rough = 0.5;
		glow = step(height - 2.0, up) * step(up, height - 1.4);
	}
	ALBEDO = albedo;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = accent * glow * glow_energy;
}
"""
```

- in `_init`, replace the five `building_material.set_shader_parameter(...)` lines with:

```gdscript
	building_material.set_shader_parameter("glow_energy", BUILDING_GLOW_ENERGY)
```

- [ ] **Step 4: Run to verify it passes, then compile it for real**

Run the Step 2 command. Expected: `ALL TESTS PASSED` only.

Create the scratchpad render script `/tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_buildings.gd`:

```gdscript
extends SceneTree

# Offscreen look at the new buildings: over the city centre and over a town.
const InteriorWorldScript = preload("res://scripts/interior_world.gd")
const SectionPlan = preload("res://scripts/section_plan.gd")
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
	root.add_child(world)
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 90.0
	cam.near = 0.2
	cam.far = 60000.0
	root.add_child(cam)
	cam.current = true
	var plan = world.get_section_plan(0)
	var town := Vector2.ZERO
	for along in range(SectionPlan.LOTS_ALONG):
		for around in range(SectionPlan.LOTS_AROUND):
			if town == Vector2.ZERO and plan.zone_at(around, along) == SectionPlan.Zone.TOWN:
				town = plan.lot_center(around, along)
	var views := {"city": [plan.city_center, 350.0, 700.0], "town": [town, 60.0, 180.0]}
	var start_z: float = -(world.bridge_length * 0.5 + world.section_length)
	for view_name in views:
		var spot: Vector2 = views[view_name][0]
		var angle: float = spot.x / world.section_radius
		var r: float = world.section_radius - views[view_name][1]
		var eye := Vector3(cos(angle) * r, sin(angle) * r, start_z + spot.y + views[view_name][2])
		var up := Vector3(-cos(angle), -sin(angle), 0.0)
		var forward := (Vector3(0.0, 0.0, -1.0) * cos(deg_to_rad(25.0)) - up * sin(deg_to_rad(25.0))).normalized()
		cam.global_transform = Transform3D(Basis.looking_at(forward, up), eye)
		for i in range(8):
			await process_frame
		root.get_texture().get_image().save_png(SCRATCH + "buildings_%s.png" % view_name)
		print("saved ", view_name)
	quit()
```

Run: `timeout 300 xvfb-run -a /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --path . --script /tmp/claude-1000/-home-patrick-projects-playground-torus1/62184356-307e-4346-96fb-b38ef4ab52f3/scratchpad/render_buildings.gd 2>&1 | grep -E "saved|ERROR|error"`
Expected: `saved city` and `saved town`, and no `SHADER ERROR` / `ERROR` lines. A shader compile error here is a code bug: fix the shader and re-run until clean.

Then the full suite. Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/terrain_dressing.gd tests/test_terrain_dressing.gd
git commit -m "Paint facades only on walls: light bands, sparse windows, dark glass or blind panels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Verification

- [ ] **Step 1: Live check**

Run: `timeout 300 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --quit-after 900 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR|WARNING"`
Expected: no output.

- [ ] **Step 2: Loading cost**

Run: `timeout 600 /home/patrick/Godot_v4.6.1-stable-double_linux.x86_64 --headless --path . --script tests/test_interior_streaming.gd 2>&1 | grep -E "worst|FAIL|PASSED"`
Expected: `worst frame while streaming: <n> ms` with n under 50, and `ALL TESTS PASSED`. If n is 50 or more, apply the spec's fallback (round the collider size in `_convex_shape` to even metres, `2 * ceili(size / 2)` per axis, so hulls stay outside the drawn shape), add a test that two buildings 1 m apart in size share one shape, and ledger it as a ruling.

- [ ] **Step 3: Look at the renders**

Re-run the Task 4 render command and open `buildings_city.png` and `buildings_town.png` with the Read tool.
Expected:
- city: several tower shapes (steps, tapers, rings, fins, spires), roofs without windows, different facade types and light colours;
- town: domes, vaults, octagonal blocks and ring houses, low and rounded.

A problem that is visual only (proportions, colours) goes to the final message as an observation, not a silent change.

- [ ] **Step 4: Full suite**

Run the full suite. Expected: every file `ALL TESTS PASSED`. No commit unless Step 2 needed the fallback.
