"""Generates the equirectangular Moon-like surface texture set used by planet.gd (needs numpy, scipy, Pillow)."""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates

OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "textures" / "planet"

W, H = 4096, 2048


def sinusoidal_noise_3d(x, y, z, n_waves, freq_range, seed):
    rng = np.random.default_rng(seed)
    total = np.zeros_like(x, dtype=np.float32)
    for _ in range(n_waves):
        d = rng.normal(size=3)
        d /= np.linalg.norm(d)
        freq = rng.uniform(*freq_range)
        phase = rng.uniform(0, 2 * np.pi)
        total += np.sin((x * d[0] + y * d[1] + z * d[2]) * freq + phase).astype(np.float32)
    return total / n_waves


def value_noise_3d(x, y, z, grid_size, seed):
    rng = np.random.default_rng(seed)
    grid = rng.random((grid_size, grid_size, grid_size)).astype(np.float32)
    coords = np.stack([(c * 0.5 + 0.5) * grid_size for c in (x, y, z)], axis=0)
    return map_coordinates(grid, coords, order=1, mode="wrap")


def fractal_value_noise(x, y, z, octaves, base_grid, base_seed):
    total = np.zeros_like(x, dtype=np.float32)
    amp, amp_sum, grid = 1.0, 0.0, base_grid
    for o in range(octaves):
        total += amp * value_noise_3d(x, y, z, grid, base_seed + o * 101)
        amp_sum += amp
        amp *= 0.5
        grid *= 2
    return total / amp_sum


def main():
    rng = np.random.default_rng(42)
    lon = (np.arange(W) + 0.5) / W * 2 * np.pi - np.pi
    lat = (np.arange(H) + 0.5) / H * np.pi - np.pi / 2
    LON, LAT = np.meshgrid(lon, lat)
    # sampling noise on the 3D unit sphere keeps the map seamless at the poles and the lon=±pi seam
    X, Y, Z = np.cos(LAT) * np.cos(LON), np.cos(LAT) * np.sin(LON), np.sin(LAT)

    # sinusoids, not grid noise: a coarse 3D lattice sliced by the sphere shows as bands and lens-shaped blobs
    mare = sinusoidal_noise_3d(X, Y, Z, n_waves=10, freq_range=(1.5, 4.0), seed=1)
    mare = ((mare - mare.min()) / (mare.max() - mare.min())) ** 1.5

    grain = fractal_value_noise(X, Y, Z, octaves=4, base_grid=24, base_seed=100)
    grain = (grain - grain.min()) / (grain.max() - grain.min())

    n_craters = 140
    pts = rng.normal(size=(n_craters, 3))
    pts /= np.linalg.norm(pts, axis=1, keepdims=True)
    radii = rng.uniform(0.015, 0.05, size=n_craters)
    crater_height = np.zeros_like(X, dtype=np.float32)
    for (px, py, pz), r in zip(pts, radii):
        t = np.arccos(np.clip(X * px + Y * py + Z * pz, -1.0, 1.0)) / r
        bowl = np.where(t < 1.0, -0.6 * (1.0 - t) ** 2 + 0.35 * np.exp(-((t - 0.9) ** 2) / 0.01), 0.0)
        crater_height += bowl.astype(np.float32)
    crater_height = np.clip(crater_height, -1.0, 0.6)

    albedo = np.array([0.62, 0.60, 0.58])[None, None, :] * (1.0 - 0.35 * mare[..., None])
    albedo = albedo * (1.0 - 0.5 * np.clip(-crater_height, 0, 1)[..., None])
    albedo = albedo + np.clip(crater_height, 0, 1)[..., None] * 0.25
    albedo = np.clip(albedo * (0.9 + 0.2 * grain[..., None]), 0.0, 1.0)

    roughness = np.clip(0.8 + 0.15 * (grain - 0.5) - 0.1 * np.clip(crater_height, 0, 1), 0.55, 1.0)

    # fine grain stays out of the normal map (it read as static noise); only mare + craters give relief
    height = gaussian_filter(0.5 * (mare - 0.5) + 0.5 * crater_height, sigma=1.5, mode="wrap")
    dhdx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * W / (2 * np.pi)
    dhdy = np.gradient(height, axis=0) * H / np.pi
    strength = 3.0
    # OpenGL convention (green = toward the top of the image), as Godot expects
    nx, ny, nz = -dhdx * strength, dhdy * strength, np.ones_like(height)
    norm = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    normal = np.stack([nx / norm, ny / norm, nz / norm], axis=-1) * 0.5 + 0.5

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    Image.fromarray((albedo * 255).astype(np.uint8), "RGB").save(OUT_DIR / "albedo.png")
    Image.fromarray(np.repeat((roughness * 255).astype(np.uint8)[..., None], 3, axis=2), "RGB").save(OUT_DIR / "roughness.png")
    Image.fromarray((normal * 255).astype(np.uint8), "RGB").save(OUT_DIR / "normal.png")
    print(f"wrote {W}x{H} planet textures to {OUT_DIR}")


if __name__ == "__main__":
    main()
