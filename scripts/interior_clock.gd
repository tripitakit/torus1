extends RefCounted

# The interior's time of day. A day lasts 24 game minutes (one minute an
# hour), counted from the game's start, so it runs on while the ship is
# outside. Time zones round the ring: the hour moves on 24 h over all the
# sections, the far side is always 12 h apart. Daylight is full from 7 to
# 17, NIGHT_LIGHT from 20 to 4, with dawn and dusk between.

const START_HOUR := 10.0
const SECONDS_PER_HOUR := 60.0
const NIGHT_LIGHT := 0.15
const DAWN := Vector2(4.0, 7.0)
const DUSK := Vector2(17.0, 20.0)
const NOON_COLOR := Color(1.0, 0.93, 0.8)
const DUSK_COLOR := Color(1.0, 0.55, 0.25)
const NIGHT_COLOR := Color(0.55, 0.65, 1.0)
# How far toward DUSK_COLOR the light goes at mid dawn and dusk.
const TWILIGHT_TINT := 0.6

# The hour of ring section 0, `seconds` after the start.
static func base_hour(seconds: float) -> float:
	return fposmod(START_HOUR + seconds / SECONDS_PER_HOUR, 24.0)

# Where a point of the interior chain (its z along the chain) lies on the
# ring, in sections: a section slot's centre gives its ring index (see
# InteriorLayout: slot s centred at -(s + 0.5) * period, ring index
# docked + s + 1).
static func ring_position(chain_z: float, docked_bridge: int, period: float) -> float:
	return docked_bridge + 0.5 - chain_z / period

static func hour_at(base: float, ring_pos: float, ring_sections: int) -> float:
	return fposmod(base + 24.0 * ring_pos / ring_sections, 24.0)

# The hour along the interior world's z as a line, (origin, slope): hour =
# origin + slope * z, modulo 24 (what the shaders read). `chain_offset` is
# how far the chain has been moved along z.
static func hour_line(base: float, docked_bridge: int, period: float, chain_offset: float, ring_sections: int) -> Vector2:
	var per_section := 24.0 / ring_sections
	return Vector2(fposmod(base + per_section * (docked_bridge + 0.5 + chain_offset / period), 24.0), -per_section / period)

static func daylight(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var up := smoothstep(DAWN.x, DAWN.y, h) * (1.0 - smoothstep(DUSK.x, DUSK.y, h))
	return lerpf(NIGHT_LIGHT, 1.0, up)

# 0 by day, 1 by night.
static func night(hour: float) -> float:
	return (1.0 - daylight(hour)) / (1.0 - NIGHT_LIGHT)

# White by day, orange-tinted at mid dawn and dusk, bluish at night.
static func sun_color(hour: float) -> Color:
	var n := night(hour)
	var twilight := 1.0 - absf(n * 2.0 - 1.0)
	var color := NOON_COLOR.lerp(NIGHT_COLOR, smoothstep(0.5, 1.0, n))
	return color.lerp(DUSK_COLOR, twilight * TWILIGHT_TINT)

static func format(hour: float) -> String:
	var minutes := floori(fposmod(hour, 24.0) * 60.0 + 0.0001)
	@warning_ignore("integer_division")
	return "ORA %02d:%02d" % [minutes / 60, minutes % 60]
