// The interior's hour at a point and its light, as InteriorClock computes
// them (keep the two in step): hour = origin + slope * z of the interior
// world, modulo 24; full day 7-17, 0.15 at night 20-4, ramps between.
global uniform float interior_hour_origin;
global uniform float interior_hour_slope;

float interior_hour(float world_z) {
	return mod(interior_hour_origin + interior_hour_slope * world_z, 24.0);
}

float interior_daylight(float hour) {
	float up = smoothstep(4.0, 7.0, hour) * (1.0 - smoothstep(17.0, 20.0, hour));
	return mix(0.15, 1.0, up);
}

// 0 by day, 1 by night.
float interior_night(float hour) {
	return (1.0 - interior_daylight(hour)) / 0.85;
}
