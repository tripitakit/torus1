extends RefCounted

const NO_READING := "—"

static func format_speed(speed: float) -> String:
	return "%d m/s" % roundi(speed)

static func format_distance(distance: float) -> String:
	if distance < 0.0:
		return NO_READING
	# Decide the unit on the rounded value, so 999.6 m never shows as "1000 m".
	var metres: int = roundi(distance)
	if metres < 1000:
		return "%d m" % metres
	return "%.1f km" % (distance / 1000.0)

# Height above the planet's surface, in whole kilometres.
static func format_altitude(metres: float) -> String:
	if is_inf(metres) or is_nan(metres):
		return NO_READING
	return "%d km" % roundi(metres / 1000.0)
