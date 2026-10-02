#!/usr/bin/env python3
"""Converts NASA's Earth maps (Visible Earth, public domain) for the planet.

    python3 tools/earth_maps.py

Downloads (once, into ~/.cache/torus1_nasa) and writes:

  assets/textures/planet/color.jpg     8192x4096 Blue Marble Next Generation,
                                       July 2004, land and dark oceans
  assets/textures/planet/lights.jpg    8192x4096 Black Marble 2016, city
                                       lights at night
  assets/textures/clouds/clouds.jpg    8192x4096 grey: the cloud cover (0
                                       clear, 255 overcast)
  assets/textures/planet/normal.png    4096x2048 tangent-space normals (x east,
                                       y north) from GEBCO land heights
  assets/textures/planet/roughness.png 4096x2048 glossy water, rough land
                                       (land: GEBCO height above 0; the few
                                       lands below sea level read as water)

All equirectangular, longitude -180 at the left edge, north up. planet.gd
turns the maps round the axis (LONGITUDE_OFFSET) to set which side faces the
ring's start.
"""

import os
import urllib.request

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

SOURCE = "https://eoimages.gsfc.nasa.gov/images/imagerecords/"
FILES = {
    "color": "74000/74393/world.topo.200407.3x21600x10800.jpg",
    "lights": "144000/144898/BlackMarble_2016_3km.jpg",
    "clouds": "57000/57747/cloud_combined_8192.tif",
    "land": "73000/73934/gebco_08_rev_elev_21600x10800.png",
}
CACHE = os.path.expanduser("~/.cache/torus1_nasa")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIG = (8192, 4096)
SMALL = (4096, 2048)
# GEBCO's land map: 0..255 for 0..~6400 m.
METRES_PER_STEP = 25.0
EARTH_RADIUS = 6371000.0
# True slopes (the same on our smaller planet, everything scaled alike) are
# too faint to read from orbit: the normal map shows them this much steeper.
NORMAL_STRENGTH = 12.0
WATER_ROUGHNESS = 60
LAND_ROUGHNESS = 220


def fetch(key):
    name = FILES[key].split("/")[-1]
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print("downloading", name)
        urllib.request.urlretrieve(SOURCE + FILES[key], path)
    return path


def out(relative):
    path = os.path.join(ROOT, relative)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def colour_maps():
    for key, name in [("color", "assets/textures/planet/color.jpg"), ("lights", "assets/textures/planet/lights.jpg")]:
        image = Image.open(fetch(key)).convert("RGB").resize(BIG, Image.LANCZOS)
        image.save(out(name), quality=90)
        print("wrote", name, image.size)


def clouds():
    cover = Image.open(fetch("clouds")).convert("L").resize(BIG, Image.LANCZOS)
    alpha = np.asarray(cover, dtype=np.float64) / 255.0
    # A thin haze reads as clear sky; the thickest as fully overcast.
    alpha = np.clip((alpha - 0.08) / 0.75, 0.0, 1.0)
    grey = np.round(alpha * 255.0).astype(np.uint8)
    Image.fromarray(grey, "L").save(out("assets/textures/clouds/clouds.jpg"), quality=90)
    print("wrote clouds", grey.shape)


def relief_and_roughness():
    land = np.asarray(Image.open(fetch("land")).convert("L").resize(SMALL, Image.BILINEAR), dtype=np.float64)
    metres = land * METRES_PER_STEP
    rows, columns = metres.shape
    latitude = np.radians(90.0 - (np.arange(rows) + 0.5) * 180.0 / rows)
    east_step = EARTH_RADIUS * np.maximum(np.cos(latitude), 0.01) * 2.0 * np.pi / columns
    north_step = EARTH_RADIUS * np.pi / rows
    d_east = (np.roll(metres, -1, axis=1) - np.roll(metres, 1, axis=1)) / (2.0 * east_step[:, None])
    above = np.vstack([metres[:1], metres[:-1]])
    below = np.vstack([metres[1:], metres[-1:]])
    d_north = (above - below) / (2.0 * north_step)
    n = np.dstack([-d_east * NORMAL_STRENGTH, -d_north * NORMAL_STRENGTH, np.ones_like(metres)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(np.round((n * 0.5 + 0.5) * 255.0).astype(np.uint8), "RGB").save(out("assets/textures/planet/normal.png"))
    print("wrote normal", n.shape)
    # Land: any height above sea level, its share of each pixel.
    above = (np.asarray(Image.open(fetch("land")).convert("L")) > 0).astype(np.uint8) * 255
    land_share = np.asarray(Image.fromarray(above, "L").resize(SMALL, Image.BOX), dtype=np.float64) / 255.0
    rough = WATER_ROUGHNESS + (LAND_ROUGHNESS - WATER_ROUGHNESS) * land_share
    Image.fromarray(np.round(rough).astype(np.uint8), "L").save(out("assets/textures/planet/roughness.png"))
    print("wrote roughness", rough.shape)


if __name__ == "__main__":
    colour_maps()
    clouds()
    relief_and_roughness()
