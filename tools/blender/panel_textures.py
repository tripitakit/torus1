# Panel textures for the station (run inside Blender):
#   bridge/        outside of the bridges: rectangular metal panels of two
#                  sizes, dark seams, some grilles, small position lights;
#   interior_tube/ inside of a bridge: large panels, ring ribs, a light strip
#                  along the tube;
#   interior_cap/  the flat end walls inside a section: rings of panels and
#                  yellow/black hazard bands at the inner and outer edge.
# Every set: color.png (sRGB), roughness.png, normal.png (tangent space),
# emission.png, 2048 x 2048. bridge and interior_tube repeat seamlessly in
# both directions; interior_cap repeats around (u) and spans the wall once
# from the bridge's hole (v = 0) to the section's rim (v = 1).
#
#   TOOLS = '<repo>/tools/blender'
#   exec(open(TOOLS + '/panel_textures.py').read())
#   run('<repo>/assets/textures')

import os

exec(open(os.path.join(TOOLS, 'bake_lib.py')).read())

SIZE = (2048, 2048)
CHANNELS = {'color': 'color', 'roughness': 'data', 'normal': 'normal', 'emission': 'color'}
LIGHT = (1.0, 0.85, 0.6, 1.0)
STRIP = (0.6, 0.9, 1.0, 1.0)


def _step(g, edge, width):
    """1 away from seams, 0 on them (soft over `width`)."""
    return g.math('MINIMUM', g.math('DIVIDE', edge, width), 1.0)


def _metal(g, u, v, shade, base=0.42, spread=0.14, tint=(0.95, 0.97, 1.0)):
    grime = g.tile_noise(u, v, 12.0, detail=6.0)
    value = g.math('ADD', base - spread * 0.5, g.math('MULTIPLY', shade, spread))
    value = g.math('MULTIPLY', value, g.math('ADD', 0.8, g.math('MULTIPLY', grime, 0.35)))
    return g.combine(g.math('MULTIPLY', value, tint[0]), g.math('MULTIPLY', value, tint[1]), g.math('MULTIPLY', value, tint[2])), grime


def build_bridge(g):
    u, v = g.uv()
    big_edge, big_rand, big_fu, big_fv = g.cells(u, v, 6, 3)
    small_edge, small_rand, _, _ = g.cells(u, v, 12, 6, seed=3.0)
    # Some big panels split into four smaller ones.
    split = g.math('LESS_THAN', big_rand, 0.35)
    edge = g.mixf(split, big_edge, g.math('MINIMUM', big_edge, small_edge))
    shade = g.mixf(split, big_rand, small_rand)
    panel = _step(g, edge, 0.0012)
    color, grime = _metal(g, u, v, shade, base=0.2, spread=0.1, tint=(0.92, 0.96, 1.0))
    # Grilles on a few panels: fine dark slats.
    grille = g.math('GREATER_THAN', big_rand, 0.86)
    slats = g.math('GREATER_THAN', g.math('FRACT', g.math('MULTIPLY', v, 240.0)), 0.5)
    grille_dark = g.math('MULTIPLY', grille, g.math('MULTIPLY', slats, 0.55))
    color = g.mix(g.math('MAXIMUM', grille_dark, g.math('SUBTRACT', 1.0, panel)), color, (0.05, 0.05, 0.06, 1.0))
    # Position lights near one corner of some big panels.
    lit = g.math('LESS_THAN', big_rand, 0.12)
    corner = g.math('MULTIPLY', g.math('LESS_THAN', g.math('ABSOLUTE', g.math('SUBTRACT', big_fu, 0.08)), 0.02), g.math('LESS_THAN', g.math('ABSOLUTE', g.math('SUBTRACT', big_fv, 0.08)), 0.04))
    light = g.math('MULTIPLY', lit, corner)
    emission = g.mix(light, (0.0, 0.0, 0.0, 1.0), LIGHT)
    color = g.mix(light, color, LIGHT)
    rough = g.math('ADD', 0.35, g.math('ADD', g.math('MULTIPLY', shade, 0.2), g.math('MULTIPLY', grime, 0.25)))
    height = g.math('SUBTRACT', g.math('MULTIPLY', panel, g.math('ADD', 0.9, g.math('MULTIPLY', shade, 0.1))), g.math('MULTIPLY', grille_dark, 0.3))
    return {'color': color, 'roughness': rough, 'height': height, 'emission': emission}


def build_tube(g):
    u, v = g.uv()
    edge, rand, fu, fv = g.cells(u, v, 4, 2)
    panel = _step(g, edge, 0.0015)
    color, grime = _metal(g, u, v, rand, base=0.36, spread=0.12, tint=(1.0, 0.98, 0.94))
    # A ring rib across the tube at v = 0 (repeats with the texture).
    rib = g.math('LESS_THAN', g.math('MINIMUM', v, g.math('SUBTRACT', 1.0, v)), 0.035)
    color = g.mix(rib, color, (0.18, 0.19, 0.2, 1.0))
    color = g.mix(g.math('SUBTRACT', 1.0, panel), color, (0.04, 0.04, 0.05, 1.0))
    # A light strip along the tube at u = 0.5.
    strip = g.math('LESS_THAN', g.math('ABSOLUTE', g.math('SUBTRACT', u, 0.5)), 0.006)
    strip = g.math('MULTIPLY', strip, g.math('SUBTRACT', 1.0, rib))
    emission = g.mix(strip, (0.0, 0.0, 0.0, 1.0), STRIP)
    color = g.mix(strip, color, STRIP)
    rough = g.math('ADD', 0.5, g.math('MULTIPLY', grime, 0.3))
    height = g.math('ADD', g.math('MULTIPLY', panel, 0.8), g.math('MULTIPLY', rib, 0.6))
    return {'color': color, 'roughness': rough, 'height': height, 'emission': emission}


def build_cap(g):
    u, v = g.uv()
    edge, rand, fu, fv = g.cells(u, v, 4, 6)
    panel = _step(g, edge, 0.0015)
    color, grime = _metal(g, u, v, rand, base=0.38, spread=0.12, tint=(1.0, 0.99, 0.96))
    color = g.mix(g.math('SUBTRACT', 1.0, panel), color, (0.04, 0.04, 0.05, 1.0))
    # Hazard bands at the hole (v < 0.035) and the rim (v > 0.965).
    band = g.math('MAXIMUM', g.math('LESS_THAN', v, 0.035), g.math('GREATER_THAN', v, 0.965))
    stripes = g.math('GREATER_THAN', g.math('FRACT', g.math('MULTIPLY', g.math('ADD', u, g.math('MULTIPLY', v, 4.0)), 24.0)), 0.5)
    hazard = g.mix(stripes, (0.03, 0.03, 0.03, 1.0), (0.95, 0.72, 0.08, 1.0))
    color = g.mix(band, color, hazard)
    # Small lamps along the hazard bands.
    lamp_u = g.math('LESS_THAN', g.math('ABSOLUTE', g.math('SUBTRACT', g.math('FRACT', g.math('MULTIPLY', u, 8.0)), 0.5)), 0.01)
    lamp_v = g.math('MAXIMUM', g.math('LESS_THAN', g.math('ABSOLUTE', g.math('SUBTRACT', v, 0.045)), 0.004), g.math('LESS_THAN', g.math('ABSOLUTE', g.math('SUBTRACT', v, 0.955)), 0.004))
    lamp = g.math('MULTIPLY', lamp_u, lamp_v)
    emission = g.mix(lamp, (0.0, 0.0, 0.0, 1.0), LIGHT)
    color = g.mix(lamp, color, LIGHT)
    rough = g.math('ADD', 0.5, g.math('MULTIPLY', grime, 0.3))
    height = g.math('MULTIPLY', panel, g.math('ADD', 0.8, g.math('MULTIPLY', band, 0.1)))
    return {'color': color, 'roughness': rough, 'height': height, 'emission': emission}


def run(textures):
    written = []
    written += bake_set('bridge', build_bridge, SIZE, os.path.join(textures, 'bridge'), CHANNELS)
    written += bake_set('interior_tube', build_tube, SIZE, os.path.join(textures, 'interior_tube'), CHANNELS)
    written += bake_set('interior_cap', build_cap, SIZE, os.path.join(textures, 'interior_cap'), CHANNELS)
    return written
