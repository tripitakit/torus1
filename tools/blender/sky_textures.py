# The star dome (run inside Blender): an equirectangular map for the sky
# shader, laid out like Godot's SphereMesh UVs (the planet's maps too): a
# pixel (u, v) is the direction (sin 2 pi u sin pi v, cos pi v,
# cos 2 pi u sin pi v), v = 0 straight up (+Y).
#
#   sky/stars.png  black sky; thousands of stars (many faint, few bright,
#                  bluish to orange) and the Milky Way: a band along a great
#                  circle tilted from the ring's plane, denser with stars,
#                  a faint milky glow brighter toward its core, dark dust
#                  lanes across it.
#
#   TOOLS = '<repo>/tools/blender'
#   exec(open(TOOLS + '/sky_textures.py').read())
#   run('<repo>/assets/textures')

import os
import math

exec(open(os.path.join(TOOLS, 'bake_lib.py')).read())

SIZE = (8192, 4096)
# The galactic plane's normal (tilted ~60 degrees from +Y) and the direction
# of the galaxy's core, on that plane.
GALACTIC_POLE = (math.sin(math.radians(60.0)) * math.cos(math.radians(30.0)), math.cos(math.radians(60.0)), math.sin(math.radians(60.0)) * math.sin(math.radians(30.0)))


def _normalize(v):
    n = math.sqrt(sum(a * a for a in v))
    return tuple(a / n for a in v)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


GALACTIC_CORE = _normalize(_cross(GALACTIC_POLE, (0.0, 0.0, 1.0)))


def direction(g):
    u, v = g.uv()
    vg = g.math('SUBTRACT', 1.0, v)
    lon = g.math('MULTIPLY', u, math.tau)
    lat = g.math('MULTIPLY', vg, math.pi)
    ring = g.math('SINE', lat)
    return g.combine(g.math('MULTIPLY', g.math('SINE', lon), ring), g.math('COSINE', lat), g.math('MULTIPLY', g.math('COSINE', lon), ring))


def star_layer(g, d, scale, radius_px, power, seed):
    """One layer of stars: a point per Voronoi cell of `scale` on the unit
    sphere, radius about `radius_px` map pixels, brightness a random ** power
    (most faint). Returns (brightness, colour 0..1 per star)."""
    vor = g.nodes.new('ShaderNodeTexVoronoi')
    vor.voronoi_dimensions = '3D'
    vor.feature = 'F1'
    g.set(vor.inputs['Vector'], g.vmath('ADD', d, (seed, seed * 2.0, seed * 3.0)))
    g.set(vor.inputs['Scale'], scale)
    g.set(vor.inputs['Randomness'], 1.0)
    # Distance is in scaled units: radians x scale.
    radius = radius_px * (math.tau / SIZE[0]) * scale
    dot = g.math('SUBTRACT', 1.0, g.math('DIVIDE', vor.outputs['Distance'], radius, clamp=True))
    sep = g.nodes.new('ShaderNodeSeparateColor')
    g.set(sep.inputs[0], vor.outputs['Color'])
    bright = g.math('POWER', sep.outputs[0], power)
    return g.math('MULTIPLY', dot, bright), sep.outputs[1]


def build_stars(g):
    d = direction(g)
    band_offset = g.vmath('DOT_PRODUCT', d, GALACTIC_POLE)
    band = g.math('EXPONENT', g.math('MULTIPLY', g.math('POWER', g.math('DIVIDE', band_offset, 0.16), 2.0), -1.0))
    core = g.math('EXPONENT', g.math('MULTIPLY', g.math('SUBTRACT', 1.0, g.vmath('DOT_PRODUCT', d, GALACTIC_CORE)), -4.0))
    # Stars: a sparse bright layer everywhere, a dense faint one, and a
    # denser one only inside the band.
    bright, tint_a = star_layer(g, d, 40.0, 1.6, 8.0, 1.0)
    faint, tint_b = star_layer(g, d, 110.0, 1.1, 14.0, 7.0)
    milky, tint_c = star_layer(g, d, 250.0, 1.0, 10.0, 13.0)
    milky = g.math('MULTIPLY', milky, band)
    stars = g.math('ADD', g.math('ADD', bright, g.math('MULTIPLY', faint, 0.5)), g.math('MULTIPLY', milky, 0.4))
    tint = g.ramp(g.mixf(0.5, tint_a, tint_b), [(0.0, (0.7, 0.8, 1.0, 1.0)), (0.55, (1.0, 1.0, 1.0, 1.0)), (1.0, (1.0, 0.8, 0.6, 1.0))])
    star_color = tint
    # The milky glow and dust lanes.
    cloud = g.nodes.new('ShaderNodeTexNoise')
    cloud.noise_dimensions = '3D'
    g.set(cloud.inputs['Vector'], d)
    g.set(cloud.inputs['Scale'], 6.0)
    g.set(cloud.inputs['Detail'], 10.0)
    g.set(cloud.inputs['Roughness'], 0.6)
    dust = g.nodes.new('ShaderNodeTexNoise')
    dust.noise_dimensions = '3D'
    g.set(dust.inputs['Vector'], g.vmath('ADD', d, (4.0, 1.0, 2.0)))
    g.set(dust.inputs['Scale'], 9.0)
    g.set(dust.inputs['Detail'], 8.0)
    g.set(dust.inputs['Roughness'], 0.65)
    lanes = g.math('DIVIDE', g.math('SUBTRACT', dust.outputs['Fac'], 0.52), 0.1, clamp=True)
    glow = g.math('MULTIPLY', g.math('MULTIPLY', band, g.math('ADD', 0.35, g.math('MULTIPLY', core, 1.2))), cloud.outputs['Fac'])
    glow = g.math('MULTIPLY', g.math('MULTIPLY', glow, g.math('SUBTRACT', 1.0, g.math('MULTIPLY', lanes, 0.85))), 0.05)
    glow_color = g.mix(core, (0.55, 0.6, 0.8, 1.0), (0.85, 0.75, 0.6, 1.0))
    sky = g.nodes.new('ShaderNodeMix')
    sky.data_type = 'RGBA'
    sky.blend_type = 'ADD'
    g.set(sky.inputs['Factor'], 1.0)
    g.set(sky.inputs[6], g.mix(glow, (0.0, 0.0, 0.0, 1.0), glow_color))
    g.set(sky.inputs[7], g.mix(g.math('MINIMUM', stars, 1.0), (0.0, 0.0, 0.0, 1.0), star_color))
    return {'stars': sky.outputs[2]}


def run(textures, size=SIZE):
    global SIZE
    SIZE = size
    return bake_set('sky', build_stars, size, os.path.join(textures, 'sky'), {'stars': 'color'})
