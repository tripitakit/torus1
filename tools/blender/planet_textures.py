# Earth-like planet textures (run inside Blender), equirectangular for
# Godot's SphereMesh: u goes round the planet, v from the north pole (v = 0,
# top row of the image) to the south pole. A pixel's direction on the sphere
# is (sin(2 pi u) sin(pi v), cos(pi v), cos(2 pi u) sin(pi v)), the same
# formula SphereMesh uses, so the maps meet the mesh exactly.
#
#   planet/  color.png  oceans (deep and shallow), land (green, brown,
#                       deserts in the subtropics), polar ice
#            roughness.png  glossy oceans, rough land
#            normal.png     relief on land only
#   clouds/  clouds.png     white, alpha = cloud cover: bands by latitude and
#                           a hurricane spiral over an ocean near 20 degrees
#
#   TOOLS = '<repo>/tools/blender'
#   exec(open(TOOLS + '/planet_textures.py').read())
#   run('<repo>/assets/textures')

import os
import math

exec(open(os.path.join(TOOLS, 'bake_lib.py')).read())

SIZE = (4096, 2048)
SEA_LEVEL = 0.5
# The hurricane: radius on the sphere (radians; the planet is 1737 km, so
# 0.25 rad is 430 km) and latitude of its centre.
STORM_RADIUS = 0.25
STORM_LATITUDE = 20.0


def direction(g):
    u, v = g.uv()
    # Blender's v runs up from the bottom row; Godot's down from the top.
    vg = g.math('SUBTRACT', 1.0, v)
    lon = g.math('MULTIPLY', u, math.tau)
    lat = g.math('MULTIPLY', vg, math.pi)
    ring = g.math('SINE', lat)
    return g.combine(g.math('MULTIPLY', g.math('SINE', lon), ring), g.math('COSINE', lat), g.math('MULTIPLY', g.math('COSINE', lon), ring)), u, v


def noise3(g, vec, scale, detail, roughness=0.55, offset=(0.0, 0.0, 0.0)):
    n = g.nodes.new('ShaderNodeTexNoise')
    n.noise_dimensions = '3D'
    g.set(n.inputs['Vector'], g.vmath('ADD', vec, offset))
    g.set(n.inputs['Scale'], scale)
    g.set(n.inputs['Detail'], detail)
    g.set(n.inputs['Roughness'], roughness)
    return n.outputs['Fac']


def build_surface(g):
    d, u, v = direction(g)
    lat = g.math('ABSOLUTE', _y(g, d))
    height = g.mixf(0.35, noise3(g, d, 1.6, 3.0), noise3(g, d, 4.0, 10.0, 0.6, (7.0, 1.0, 3.0)))
    land = g.math('GREATER_THAN', height, SEA_LEVEL)
    # Ocean: deep far from the coast, shallow next to it.
    shallow = g.math('DIVIDE', g.math('SUBTRACT', height, SEA_LEVEL - 0.06), 0.06, clamp=True)
    ocean = g.mix(shallow, (0.008, 0.035, 0.13, 1.0), (0.03, 0.2, 0.33, 1.0))
    # Land: green and brown, deserts in the subtropics where it is dry,
    # grey-brown on high ground.
    moisture = noise3(g, d, 3.0, 6.0, 0.5, (2.0, 9.0, 4.0))
    greenish = g.mix(moisture, (0.36, 0.3, 0.16, 1.0), (0.09, 0.27, 0.07, 1.0))
    subtropic = g.math('SUBTRACT', 1.0, g.math('DIVIDE', g.math('ABSOLUTE', g.math('SUBTRACT', lat, 0.42)), 0.28, clamp=True))
    dry = noise3(g, d, 7.0, 6.0, 0.6, (3.0, 8.0, 1.0))
    desert = g.math('GREATER_THAN', g.math('ADD', g.math('MULTIPLY', subtropic, 0.22), dry), 0.71)
    ground = g.mix(desert, greenish, (0.72, 0.6, 0.38, 1.0))
    high = g.math('DIVIDE', g.math('SUBTRACT', height, SEA_LEVEL + 0.12), 0.1, clamp=True)
    ground = g.mix(high, ground, (0.42, 0.38, 0.33, 1.0))
    color = g.mix(land, ocean, ground)
    # Polar ice, ragged at the edge.
    ice_edge = g.math('ADD', 0.93, g.math('MULTIPLY', noise3(g, d, 6.0, 6.0, 0.5, (5.0, 5.0, 5.0)), 0.06))
    ice = g.math('GREATER_THAN', lat, ice_edge)
    color = g.mix(ice, color, (0.88, 0.92, 0.96, 1.0))
    rough = g.mixf(ice, g.mixf(land, 0.12, 0.85), 0.5)
    relief = g.math('MULTIPLY', land, g.math('SUBTRACT', height, SEA_LEVEL))
    return {'color': color, 'roughness': rough, 'height': g.math('MULTIPLY', relief, 3.0)}


def _y(g, vec):
    sep = g.nodes.new('ShaderNodeSeparateXYZ')
    g.set(sep.inputs[0], vec)
    return sep.outputs[1]


def storm_centre(roughness_path):
    """The longitude at STORM_LATITUDE (north) with the most ocean around it,
    read back from the baked roughness (oceans are glossy)."""
    img = bpy.data.images.load(roughness_path, check_existing=False)
    w, h = img.size
    px = list(img.pixels)
    bpy.data.images.remove(img)
    # Godot's v from the north pole; Blender rows count from the bottom.
    v_godot = (90.0 - STORM_LATITUDE) / 180.0
    row = int((1.0 - v_godot) * h)
    window = max(4, int(w * STORM_RADIUS / math.tau))
    best, best_u = -1.0, 0.0
    run_start = run_end = 0
    for col in range(0, w, 8):
        ocean = 0
        count = 0
        for dr in range(-window // 2, window // 2 + 1, 4):
            r = min(max(row + dr, 0), h - 1)
            for dc in range(-window, window + 1, 4):
                c = (col + dc) % w
                ocean += 1 if px[(r * w + c) * 4] < 0.3 else 0
                count += 1
        score = ocean / count
        if score > best + 1e-9:
            best, best_u, run_start = score, col / w, col
            run_end = col
        elif abs(score - best) < 1e-9 and col == run_end + 8:
            run_end = col
            best_u = (run_start + run_end) * 0.5 / w
    lon = best_u * math.tau
    lat = math.radians(90.0 - STORM_LATITUDE)
    return (math.sin(lon) * math.sin(lat), math.cos(lat), math.cos(lon) * math.sin(lat)), best


def build_clouds(centre):
    def build(g):
        d, u, v = direction(g)
        lat = g.math('ABSOLUTE', _y(g, d))
        # Cover by latitude: wet equator and mid-latitudes, dry subtropics.
        wet = g.math('ADD', 0.5, g.math('MULTIPLY', g.math('COSINE', g.math('MULTIPLY', lat, math.tau / 0.8)), 0.5))
        belts = g.math('SUBTRACT', 0.6, g.math('MULTIPLY', wet, 0.14))
        base = noise3(g, d, 3.5, 8.0, 0.6, (11.0, 3.0, 7.0))
        streaks = noise3(g, g.vmath('MULTIPLY', d, (1.0, 3.0, 1.0)), 5.0, 6.0, 0.55, (1.0, 13.0, 2.0))
        field = g.mixf(0.3, base, streaks)
        cover = g.math('DIVIDE', g.math('SUBTRACT', field, belts), 0.12, clamp=True)
        # The hurricane: a two-armed log spiral round `centre` with a clear eye.
        c = centre
        e1 = _perpendicular(c)
        e2 = _cross(c, e1)
        cos_d = g.vmath('DOT_PRODUCT', d, c)
        dist = g.math('ARCCOSINE', g.math('MINIMUM', cos_d, 1.0))
        x = g.vmath('DOT_PRODUCT', d, e1)
        y = g.vmath('DOT_PRODUCT', d, e2)
        theta = g.math('ARCTAN2', y, x)
        r = g.math('DIVIDE', dist, STORM_RADIUS)
        log_r = g.math('LOGARITHM', g.math('ADD', r, 0.02), math.e)
        arms = g.math('ADD', 0.5, g.math('MULTIPLY', g.math('COSINE', g.math('ADD', g.math('MULTIPLY', theta, 2.0), g.math('MULTIPLY', log_r, 5.0))), 0.5))
        falloff = g.math('SUBTRACT', 1.0, g.math('DIVIDE', r, 1.0, clamp=True))
        core = g.math('SUBTRACT', 1.0, g.math('DIVIDE', r, 0.35, clamp=True))
        eye = g.math('GREATER_THAN', r, 0.05)
        storm = g.math('MULTIPLY', g.math('MAXIMUM', g.math('MULTIPLY', g.math('POWER', arms, 0.7), falloff), core), eye)
        storm = g.math('MULTIPLY', storm, g.math('ADD', 0.75, g.math('MULTIPLY', streaks, 0.5)), clamp=True)
        clear = g.math('SUBTRACT', 1.0, g.math('DIVIDE', r, 1.3, clamp=True))
        cover = g.math('MAXIMUM', g.math('MULTIPLY', cover, g.math('SUBTRACT', 1.0, clear)), storm)
        return {'cover': cover}
    return build


def _perpendicular(c):
    ref = (0.0, 1.0, 0.0) if abs(c[1]) < 0.9 else (1.0, 0.0, 0.0)
    p = _cross(ref, c)
    n = math.sqrt(sum(a * a for a in p))
    return tuple(a / n for a in p)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _cover_to_rgba(cover_path, out_path):
    """White clouds with the baked cover as alpha."""
    img = bpy.data.images.load(cover_path, check_existing=False)
    w, h = img.size
    px = list(img.pixels)
    rgba = bpy.data.images.new('clouds_rgba', width=w, height=h, alpha=True)
    rgba.colorspace_settings.name = 'sRGB'
    out = [0.0] * (w * h * 4)
    for i in range(w * h):
        out[i * 4] = 1.0
        out[i * 4 + 1] = 1.0
        out[i * 4 + 2] = 1.0
        out[i * 4 + 3] = px[i * 4]
    rgba.pixels.foreach_set(out)
    rgba.filepath_raw = out_path
    rgba.file_format = 'PNG'
    rgba.save()
    bpy.data.images.remove(img)
    bpy.data.images.remove(rgba)
    os.remove(cover_path)


def run(textures, size=SIZE):
    planet = os.path.join(textures, 'planet')
    written = bake_set('planet', build_surface, size, planet, {'color': 'color', 'roughness': 'data', 'normal': 'normal'})
    centre, ocean = storm_centre(os.path.join(planet, 'roughness.png'))
    clouds = os.path.join(textures, 'clouds')
    bake_set('clouds', build_clouds(centre), size, clouds, {'cover': 'data'})
    _cover_to_rgba(os.path.join(clouds, 'cover.png'), os.path.join(clouds, 'clouds.png'))
    return written + [os.path.join(clouds, 'clouds.png')], centre, ocean
