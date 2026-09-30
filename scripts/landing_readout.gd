extends RefCounted

# The landing limits and the moon panel's lines: pad, altitude, vertical
# speed, drift, level and status, each limit green inside and red past it.

# Landing: slower than these and level (the ship's up within LEVEL_LIMIT
# degrees of the local vertical; the nose any way). Otherwise a crash.
const DESCENT_LIMIT := 5.0
const DRIFT_LIMIT := 2.0
const LEVEL_LIMIT := 25.0
# Below this, a speed past a limit shows TOO FAST.
const WARN_ALTITUDE := 200.0
const GOOD := Color(0.3, 1.0, 0.4)
const BAD := Color(1.0, 0.3, 0.25)

# `vertical`: up positive (m/s); `tilt`: degrees off level; `pad` 0 for none.
static func readout(altitude: float, vertical: float, drift: float, tilt: float, pad: int, landed: bool) -> Dictionary:
	var descent_ok: bool = -vertical < DESCENT_LIMIT
	var drift_ok: bool = drift < DRIFT_LIMIT
	var level_ok: bool = tilt < LEVEL_LIMIT
	var status := ""
	if landed:
		status = "LANDED"
	elif altitude < WARN_ALTITUDE and not (descent_ok and drift_ok):
		status = "TOO FAST"
	return {
		"pad": "PAD %d" % pad if pad > 0 else "",
		# Resting, the hull's bottom can sit a hair under the pad's top.
		"alt": "ALT %.0f m" % maxf(altitude, 0.0),
		"vs": "V/S %+.1f m/s" % vertical,
		"drift": "DRIFT %.1f m/s" % drift,
		"level": "LEVEL %.0f°" % tilt,
		"status": status,
		"colors": {
			"vs": GOOD if descent_ok else BAD,
			"drift": GOOD if drift_ok else BAD,
			"level": GOOD if level_ok else BAD,
		},
	}
