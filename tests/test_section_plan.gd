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
	failures += _test_sample_at_gives_height_and_slope_in_one_call()

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
	if SectionPlan.Zone.HILL != 4 or SectionPlan.Zone.MOUNTAIN != 5 or not SectionPlan.is_raised(SectionPlan.Zone.HILL) or not SectionPlan.is_raised(SectionPlan.Zone.MOUNTAIN) or SectionPlan.is_raised(SectionPlan.Zone.FIELD):
		print("FAIL _test_grid_size_and_step: HILL %d, MOUNTAIN %d (expected 4, 5), or is_raised wrong" % [SectionPlan.Zone.HILL, SectionPlan.Zone.MOUNTAIN])
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

func _test_sample_at_gives_height_and_slope_in_one_call() -> int:
	# (h, dh/dx, dh/dz). The slope is bilinear between the grid points' own
	# central differences: on a grid point it is that point's difference,
	# halfway between two points the mean of theirs.
	var plan = _plan_with(func(c: int, r: int) -> float: return float((c * 7 + r * 13) % 50) + 0.1 * c * r)
	var step: Vector2 = plan.height_step()
	var result := 0
	for p in [Vector2(3.0, 4.0), Vector2(17.25, 100.5), Vector2(239.5, 7.75), Vector2(120.0, 399.5)]:
		var sample: Vector3 = plan.sample_at(p.x * step.x, p.y * step.y)
		var slope: Vector2 = plan.slope_at(p.x * step.x, p.y * step.y)
		if not is_equal_approx(sample.x, plan.height_at(p.x * step.x, p.y * step.y)) or not is_equal_approx(sample.y, slope.x) or not is_equal_approx(sample.z, slope.y):
			print("FAIL _test_sample_at_gives_height_and_slope_in_one_call: at grid %s sample %s, height %f slope %s" % [p, sample, plan.height_at(p.x * step.x, p.y * step.y), slope])
			result = 1
	var at_point: Vector2 = plan.slope_at(10.0 * step.x, 20.0 * step.y)
	var expected := Vector2((plan.grid_height(11, 20) - plan.grid_height(9, 20)) / (2.0 * step.x), (plan.grid_height(10, 21) - plan.grid_height(10, 19)) / (2.0 * step.y))
	if not at_point.is_equal_approx(expected):
		print("FAIL _test_sample_at_gives_height_and_slope_in_one_call: slope on a grid point %s, expected %s" % [at_point, expected])
		result = 1
	var halfway: Vector2 = plan.slope_at(10.5 * step.x, 20.0 * step.y)
	var next: Vector2 = plan.slope_at(11.0 * step.x, 20.0 * step.y)
	if not halfway.is_equal_approx((at_point + next) * 0.5):
		print("FAIL _test_sample_at_gives_height_and_slope_in_one_call: slope halfway %s, expected %s" % [halfway, (at_point + next) * 0.5])
		result = 1
	return result
