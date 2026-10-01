#!/usr/bin/env python3
"""Converts NASA's CGI Moon Kit maps (SVS 4720, public domain) for the moon.

    python3 tools/moon_maps.py

Downloads (once, into ~/.cache/torus1_nasa) the LRO colour mosaic and the LOLA
elevation map, and writes:

  assets/textures/moon/color.jpg   8192x4096 colour
  assets/moon/heights.bin          4096x2048 int16 little endian: metres above
                                   the moon's radius, scaled to our moon
  assets/textures/moon/normal.png  4096x2048 tangent-space normals (x east,
                                   y north) from the heights

All equirectangular, longitude 0 in the middle, west on the left, north up:
u = (lon + 180) / 360, v = (90 - lat) / 180.
"""

import os
import urllib.request

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

SOURCE = "https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/"
CACHE = os.path.expanduser("~/.cache/torus1_nasa")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REAL_RADIUS = 1737400.0
OUR_RADIUS = 250000.0
HEIGHT_SIZE = (4096, 2048)
# The relief is true to scale; the normal map shows it this much stronger
# (from far the slopes of a 250 km moon read faint).
NORMAL_STRENGTH = 2.0


def fetch(name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print("downloading", name)
        urllib.request.urlretrieve(SOURCE + name, path)
    return path


def colour():
    image = Image.open(fetch("lroc_color_poles_8k.tif")).convert("RGB")
    out = os.path.join(ROOT, "assets/textures/moon/color.jpg")
    image.save(out, quality=90)
    print("wrote", out, image.size)


def heights():
    # LOLA: km above 1737.4 km, 16 pixels a degree.
    source = Image.open(fetch("ldem_16.tif"))
    resized = source.resize(HEIGHT_SIZE, Image.BILINEAR)
    metres = np.asarray(resized, dtype=np.float64) * 1000.0 * OUR_RADIUS / REAL_RADIUS
    data = np.round(metres).astype("<i2")
    out = os.path.join(ROOT, "assets/moon/heights.bin")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    data.tofile(out)
    print("wrote", out, data.shape, data.min(), data.max())
    return metres


def normals(metres):
    rows, columns = metres.shape
    latitude = np.radians(90.0 - (np.arange(rows) + 0.5) * 180.0 / rows)
    east_step = OUR_RADIUS * np.maximum(np.cos(latitude), 0.01) * 2.0 * np.pi / columns
    north_step = OUR_RADIUS * np.pi / rows
    # East: next column (wrapping round); north: the row above.
    d_east = (np.roll(metres, -1, axis=1) - np.roll(metres, 1, axis=1)) / (2.0 * east_step[:, None])
    above = np.vstack([metres[:1], metres[:-1]])
    below = np.vstack([metres[1:], metres[-1:]])
    d_north = (above - below) / (2.0 * north_step)
    n = np.dstack([-d_east * NORMAL_STRENGTH, -d_north * NORMAL_STRENGTH, np.ones_like(metres)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    pixels = np.round((n * 0.5 + 0.5) * 255.0).astype(np.uint8)
    out = os.path.join(ROOT, "assets/textures/moon/normal.png")
    Image.fromarray(pixels, "RGB").save(out)
    print("wrote", out, pixels.shape)


if __name__ == "__main__":
    colour()
    normals(heights())
