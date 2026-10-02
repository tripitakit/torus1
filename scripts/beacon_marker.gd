extends Control

# A target's marker over the pilot's view (Base Selene's, a portal's): a
# diamond with the name and distance on it when it is on the screen, an
# arrow on the screen's edge toward it when it is not (behind the camera
# included).

const COLOR := Color(1.0, 0.85, 0.35, 0.95)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.75)
const DIAMOND := 12.0
const ARROW := 18.0
const LINE_WIDTH := 2.0
const OUTLINE_WIDTH := 4.0
const FONT_SIZE := 18
# Off-screen the arrow waits this far inside the edge (px).
const EDGE_MARGIN := 40.0
# On screen the label sits at the end of a diagonal line from the diamond,
# out at a corner of its own, so markers on one spot (a gate and the flight
# computer's point in front of it, seen from afar) keep their labels apart.
const LABEL_UP_LEFT := Vector2(-70.0, -45.0)
const LABEL_UP_RIGHT := Vector2(70.0, -45.0)
const LABEL_DOWN_RIGHT := Vector2(70.0, 45.0)
const LABEL_GAP := 4.0

# The marker's colour and the name written before the distance.
var color := COLOR
var prefix := "SELENE"
var label_offset := LABEL_UP_RIGHT
var _place := {}
var _text := ""

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

# Where to draw for a target `local_dir` in the camera's own axes (-Z ahead),
# projected by the camera at `projected`, on a `screen`-sized view:
# {on_screen, point, angle} (angle: the edge arrow's direction, 0 = right,
# screen y down).
static func placement(local_dir: Vector3, projected: Vector2, screen: Vector2) -> Dictionary:
	# On a view smaller than the margins (headless runs) the margin shrinks.
	var margin: float = minf(EDGE_MARGIN, minf(screen.x, screen.y) * 0.25)
	var inside := Rect2(Vector2.ONE * margin, (screen - Vector2.ONE * margin * 2.0).max(Vector2.ZERO))
	if local_dir.z < 0.0 and inside.has_point(projected):
		return {"on_screen": true, "point": projected, "angle": 0.0}
	var across := Vector2(local_dir.x, -local_dir.y)
	if across.length() < 1e-6:
		across = Vector2(0.0, 1.0)  # dead astern: point down
	across = across.normalized()
	var half := screen * 0.5 - Vector2.ONE * margin
	var reach: float = minf(half.x / maxf(absf(across.x), 1e-6), half.y / maxf(absf(across.y), 1e-6))
	return {"on_screen": false, "point": screen * 0.5 + across * reach, "angle": across.angle()}

# The base at `target` (world) seen by `camera`, `distance` away; hidden when
# not `shown`.
func update_target(camera: Camera3D, target: Vector3, distance: float, shown: bool) -> void:
	visible = shown
	if not shown:
		return
	var view: Basis = camera.global_transform.basis.orthonormalized()
	var local_dir: Vector3 = view.inverse() * (target - camera.global_position).normalized()
	var projected := Vector2.ZERO if local_dir.z >= 0.0 else camera.unproject_position(target)
	_place = placement(local_dir, projected, Vector2(camera.get_viewport().size))
	_text = "%s  %s" % [prefix, _distance(distance)]
	queue_redraw()

# The diagonal from the diamond's edge out to where the label hangs.
static func leader_line(point: Vector2, offset: Vector2) -> Array:
	return [point + offset.normalized() * DIAMOND, point + offset]

# The label's box at the end of the line: beside it, on the line's side,
# centred on its height.
static func label_rect(point: Vector2, offset: Vector2, size: Vector2) -> Rect2:
	var end := point + offset
	var left := end.x + LABEL_GAP if offset.x >= 0.0 else end.x - LABEL_GAP - size.x
	return Rect2(Vector2(left, end.y - size.y * 0.5), size)

# Off the screen: the label inside the screen, on the side away from the
# edge, up or down by the marker's corner (so labels at one arrow part).
static func edge_label_at(point: Vector2, angle: float, offset: Vector2) -> Vector2:
	return point - Vector2.from_angle(angle) * (ARROW + 90.0) + Vector2(-60.0, FONT_SIZE * 0.35 + offset.y)

static func _distance(metres: float) -> String:
	if metres >= 100000.0:
		return "%d km" % roundi(metres / 1000.0)
	if metres >= 1000.0:
		return "%.1f km" % (metres / 1000.0)
	return "%d m" % roundi(metres)

func _draw() -> void:
	if _place.is_empty():
		return
	var point: Vector2 = _place.point
	var outline := PackedVector2Array()
	if _place.on_screen:
		outline = PackedVector2Array([point + Vector2(0, -DIAMOND), point + Vector2(DIAMOND, 0), point + Vector2(0, DIAMOND), point + Vector2(-DIAMOND, 0), point + Vector2(0, -DIAMOND)])
	else:
		var tip := Vector2.from_angle(_place.angle)
		var side := tip.orthogonal()
		outline = PackedVector2Array([point + tip * ARROW, point - tip * ARROW * 0.4 + side * ARROW * 0.6, point - tip * ARROW * 0.4 - side * ARROW * 0.6, point + tip * ARROW])
	draw_polyline(outline, OUTLINE_COLOR, OUTLINE_WIDTH)
	draw_polyline(outline, color, LINE_WIDTH)
	var font := get_theme_default_font()
	var at: Vector2
	if _place.on_screen:
		var line := leader_line(point, label_offset)
		draw_line(line[0], line[1], OUTLINE_COLOR, OUTLINE_WIDTH)
		draw_line(line[0], line[1], color, LINE_WIDTH)
		var rect := label_rect(point, label_offset, font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE))
		at = Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + FONT_SIZE * 0.35)
	else:
		at = edge_label_at(point, _place.angle, label_offset)
	draw_string_outline(font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, OUTLINE_COLOR)
	draw_string(font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
