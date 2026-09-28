extends WorldEnvironment

# Space's backdrop: the star dome (tools/blender/sky_textures.py) with the
# sun drawn where the scene's light comes from — at infinity, fixed on the
# dome, out of reach. Only a backdrop: ambient light and reflections are
# left as the scene set them (fixed colour, no sky reflections).

const STARS_PATH := "res://assets/textures/sky/stars.png"
# The map is baked dim (many faint stars); lift it on screen.
const STAR_ENERGY := 2.0
const SKY_SHADER := """
shader_type sky;
uniform sampler2D star_map : source_color, filter_linear_mipmap, repeat_enable;
uniform float star_energy = 1.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.82);
// Angular radius of the disc and width of its glow (radians).
uniform float sun_radius = 0.0087;
uniform float glow_width = 0.05;
uniform float sun_energy = 6.0;
void sky() {
	vec3 d = normalize(EYEDIR);
	// The map's layout (see sky_textures.py): u = atan(x, z) / TAU, v from +Y.
	vec2 uv = vec2(atan(d.x, d.z) / TAU, acos(clamp(d.y, -1.0, 1.0)) / PI);
	// Gradients without the jump where u wraps, so no seam picks a tiny mip.
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x -= round(dx.x);
	dy.x -= round(dy.x);
	vec3 color = textureGrad(star_map, fract(uv), dx, dy).rgb * star_energy;
	if (LIGHT0_ENABLED) {
		float angle = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));
		float disc = 1.0 - smoothstep(sun_radius * 0.85, sun_radius, angle);
		float glow = exp(-angle / glow_width);
		color = mix(color, sun_color * sun_energy, disc) + sun_color * glow * 0.8;
	}
	COLOR = color;
}
"""

func _ready() -> void:
	build_sky()

func build_sky() -> void:
	var env := environment if environment != null else Environment.new()
	var shader := Shader.new()
	shader.code = SKY_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("star_map", load(STARS_PATH))
	material.set_shader_parameter("star_energy", STAR_ENERGY)
	var sky := Sky.new()
	sky.sky_material = material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment = env

# Inside the station the dome is switched off (plain black): the chain's
# open ends must not show the stars.
func show_dome(shown: bool) -> void:
	if environment != null:
		environment.background_mode = Environment.BG_SKY if shown else Environment.BG_COLOR
