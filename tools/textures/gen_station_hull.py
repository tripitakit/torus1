"""Generates the tileable sci-fi hull texture set used by torus_station.gd (needs numpy, scipy, Pillow)."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "textures" / "station"
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"

W = 4096
N_ACROSS = 8
M_ROWPAIRS = 5
SEED = 11

DX = W / N_ACROSS
R = DX / np.sqrt(3.0)
A = DX / 2.0  # hex inradius in pixels; every feature size below is a fraction of it
H = int(round(2 * M_ROWPAIRS * 1.5 * R))
DY = H / (2 * M_ROWPAIRS)
N_CELLS = N_ACROSS * 2 * M_ROWPAIRS

PLAIN, HATCH, VENT, CONDUIT, LIGHTS = range(5)

MORTAR = np.array([0.10, 0.10, 0.11], np.float32)
HAZARD_YELLOW = np.array([0.85, 0.62, 0.08], np.float32)
HAZARD_DARK = np.array([0.07, 0.07, 0.07], np.float32)
RUST = np.array([0.36, 0.28, 0.21], np.float32)
LIGHT_PALETTE = np.array([[0.55, 0.85, 1.0], [1.0, 0.97, 0.9], [1.0, 0.18, 0.10]], np.float32)
PIPE_PALETTE = np.array([[0.30, 0.31, 0.34], [0.45, 0.31, 0.20], [0.22, 0.38, 0.40]], np.float32)
PAINT_PALETTE = np.array([[0.86, 0.87, 0.83], [0.85, 0.65, 0.12]], np.float32)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def blend(base, color, t):
    return base + (np.asarray(color, np.float32) - base) * t[..., None]


def periodic_noise(beta, seed):
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(H)[:, None]
    fx = np.fft.rfftfreq(W)[None, :]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1.0
    spec = (rng.normal(size=f.shape) + 1j * rng.normal(size=f.shape)) / f ** beta
    spec[0, 0] = 0.0
    n = np.fft.irfft2(spec, s=(H, W))
    return ((n - n.min()) / (n.max() - n.min())).astype(np.float32)


def hex_cells():
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    px = xs + 0.5
    # <0.1% vertical stretch so the integer pixel height holds exactly 2*M_ROWPAIRS hex rows
    py = (ys + 0.5) * np.float32(1.5 * R / DY)
    cx = (np.sqrt(3.0) / 3.0 * px - py / 3.0) / R
    cz = (2.0 / 3.0 * py) / R
    cy = -cx - cz
    rx, ry, rz = np.round(cx), np.round(cy), np.round(cz)
    ddx, ddy, ddz = np.abs(rx - cx), np.abs(ry - cy), np.abs(rz - cz)
    fix_x = (ddx > ddy) & (ddx > ddz)
    fix_y = ~fix_x & (ddy > ddz)
    fix_z = ~fix_x & ~fix_y
    rx = np.where(fix_x, -ry - rz, rx)
    ry = np.where(fix_y, -rx - rz, ry)
    rz = np.where(fix_z, -rx - ry, rz)
    q, r = rx, rz
    lx = (px - R * np.sqrt(3.0) * (q + r / 2.0)).astype(np.float32)
    ly = (py - R * 1.5 * r).astype(np.float32)
    col = np.mod(q + np.floor(r / 2.0), N_ACROSS)
    row = np.mod(r, 2 * M_ROWPAIRS)
    cid = (row * N_ACROSS + col).astype(np.int32)
    return lx, ly, cid


def cell_center_px(cell):
    row, col = divmod(cell, N_ACROSS)
    return col * DX + (row % 2) * DX / 2.0, row * DY


def main():
    rng = np.random.default_rng(SEED)
    cell_type = rng.choice(5, size=N_CELLS, p=[0.36, 0.16, 0.16, 0.16, 0.16])
    cell_rot = rng.integers(0, 3, size=N_CELLS)
    cell_alt = rng.integers(0, 2, size=N_CELLS)
    cell_tint = rng.uniform(-0.035, 0.035, size=N_CELLS).astype(np.float32)
    sub_tint = rng.uniform(-0.02, 0.02, size=(N_CELLS, 3)).astype(np.float32)
    cell_light = rng.choice(3, size=N_CELLS, p=[0.65, 0.2, 0.15])
    cell_pipe = rng.integers(0, 3, size=N_CELLS)
    has_label = (cell_type == PLAIN) & (rng.random(N_CELLS) < 0.4)
    has_nav = (cell_type == PLAIN) & (rng.random(N_CELLS) < 0.35)
    nav_dir = rng.integers(0, 6, size=N_CELLS)
    label_paint = rng.integers(0, 2, size=N_CELLS)
    label_text = [f"{chr(65 + rng.integers(0, 26))}{rng.integers(1, 100):02d}" for _ in range(N_CELLS)]

    lx, ly, cid = hex_cells()
    t = cell_type[cid]

    normals = [(1.0, 0.0), (0.5, np.sqrt(3.0) / 2.0), (-0.5, np.sqrt(3.0) / 2.0)]
    projs = [lx * nx + ly * ny for nx, ny in normals]
    abs_p = np.stack([np.abs(p) for p in projs])
    k = np.argmax(abs_p, axis=0)
    edge_dist = (A - abs_p.max(axis=0)).astype(np.float32)
    del abs_p, projs
    along = lx * np.choose(k, [-ny for _, ny in normals]) + ly * np.choose(k, [nx for nx, _ in normals])
    del k

    rot = cell_rot[cid] * (np.pi / 3.0)
    c, s = np.cos(rot).astype(np.float32), np.sin(rot).astype(np.float32)
    u = lx * c + ly * s
    v = -lx * s + ly * c
    del rot, c, s

    grime_n = periodic_noise(1.3, SEED + 1)
    grain_n = periodic_noise(0.5, SEED + 2)

    # --- base plating and seams ---
    height = smoothstep(0.012 * A, 0.05 * A, edge_dist)
    albedo = np.empty((H, W, 3), np.float32)
    albedo[:] = np.array([0.60, 0.62, 0.65], np.float32)
    albedo += cell_tint[cid][..., None]
    seam = 1.0 - smoothstep(0.012 * A, 0.03 * A, edge_dist)
    albedo = blend(albedo, MORTAR, seam)
    rough = 0.42 + 0.25 * seam

    inset = 0.18 * A
    inner = edge_dist > inset
    ring = 1.0 - smoothstep(0.006 * A, 0.014 * A, np.abs(edge_dist - inset))
    height -= 0.45 * ring
    albedo = blend(albedo, MORTAR, ring * 0.6)
    rough += 0.15 * ring

    # --- sub-panels: plating split into three rhombi (PLAIN, LIGHTS) ---
    sub = (t == PLAIN) | (t == LIGHTS)
    base_ang = np.radians(30.0) + cell_alt[cid] * np.radians(60.0)
    radial = np.zeros((H, W), np.float32)
    for j in range(3):
        a = base_ang + j * np.radians(120.0)
        vx, vy = np.cos(a).astype(np.float32), np.sin(a).astype(np.float32)
        cross = np.abs(lx * vy - ly * vx)
        g = (1.0 - smoothstep(0.006 * A, 0.014 * A, cross)) * ((lx * vx + ly * vy) > 0)
        radial = np.maximum(radial, g)
    radial *= smoothstep(inset, inset + 0.01 * A, edge_dist) * sub
    height -= 0.45 * radial
    albedo = blend(albedo, MORTAR, radial * 0.6)
    sector = np.clip(np.floor(np.mod(np.arctan2(ly, lx) - base_ang, 2 * np.pi) / (2 * np.pi / 3)), 0, 2).astype(np.int32)
    albedo += (sub_tint[cid, sector] * (sub & inner))[..., None]
    del base_ang, sector

    # --- hatches with hazard-striped frames ---
    hm = t == HATCH
    box = np.maximum(np.abs(u) - 0.46 * A, np.abs(v) - 0.32 * A)
    band = hm & (box > 0) & (box < 0.07 * A)
    stripes = (np.floor((u + v) / (0.08 * A)) % 2) == 0
    albedo = np.where((band & stripes)[..., None], HAZARD_YELLOW, albedo)
    albedo = np.where((band & ~stripes)[..., None], HAZARD_DARK, albedo)
    rough = np.where(band, 0.55, rough)
    hatch_in = hm & (box < -0.016 * A)
    height += 0.25 * hatch_in
    albedo = np.where(hatch_in[..., None], np.array([0.46, 0.48, 0.51], np.float32), albedo)
    border = (1.0 - smoothstep(0.006 * A, 0.016 * A, np.abs(box))) * hm
    height -= 0.7 * border
    albedo = blend(albedo, MORTAR, border * 0.7)
    split = hatch_in & (np.abs(v) < 0.01 * A)
    height -= 0.4 * split
    albedo = blend(albedo, MORTAR, split * 0.7)
    handle = hatch_in & (np.abs(u) < 0.1 * A) & (np.abs(np.abs(v) - 0.18 * A) < 0.018 * A)
    height += 0.4 * handle
    albedo = np.where(handle[..., None], np.array([0.62, 0.63, 0.65], np.float32), albedo)
    del box, band, stripes, hatch_in, border, split, handle

    # --- ventilation grilles ---
    vm = t == VENT
    phase = np.mod(v / (0.045 * A), 1.0)
    slat = smoothstep(0.15, 0.45, phase) * (1.0 - smoothstep(0.55, 0.85, phase))
    for cu in (-0.4 * A, 0.0, 0.4 * A):
        du = np.abs(u - cu)
        in_g = vm & (du < 0.15 * A) & (np.abs(v) < 0.34 * A)
        frame = in_g & ((du > 0.12 * A) | (np.abs(v) > 0.31 * A))
        slots = in_g & ~frame
        height = np.where(frame, height + 0.3, height)
        height = np.where(slots, 0.2 + 0.55 * slat, height)
        albedo = np.where(frame[..., None], np.array([0.50, 0.52, 0.55], np.float32), albedo)
        albedo = np.where(slots[..., None], blend(np.full_like(albedo, 0.05), [0.40, 0.42, 0.45], slat), albedo)
        rough = np.where(slots, 0.55, rough)
    del phase, slat

    # --- conduits with clamps ---
    cm = (t == CONDUIT) & (edge_dist > 0.12 * A)
    clamp_band = np.abs(np.mod(u + 0.15 * A, 0.3 * A) - 0.15 * A) < 0.025 * A
    pipe_color = PIPE_PALETTE[cell_pipe[cid]]
    for off, rad, colored in ((-0.22 * A, 0.07 * A, False), (0.0, 0.09 * A, True), (0.22 * A, 0.06 * A, False)):
        d = np.abs(v - off)
        prof = np.sqrt(np.clip(1.0 - (d / rad) ** 2, 0.0, 1.0))
        pm = cm & (d < rad)
        h_pipe = 1.0 + prof * 1.6 * (rad / (0.08 * A))
        height = np.where(pm, np.maximum(height, h_pipe), height)
        col = pipe_color if colored else PIPE_PALETTE[0]
        shaded = col * (0.8 + 0.2 * prof)[..., None]
        albedo = np.where(pm[..., None], shaded, albedo)
        rough = np.where(pm, 0.3, rough)
        clamp = cm & clamp_band & (d < rad * 1.2)
        height = np.where(clamp, np.maximum(height, h_pipe + 0.25), height)
        albedo = np.where(clamp[..., None], np.array([0.55, 0.56, 0.58], np.float32), albedo)
    del clamp_band, pipe_color

    # --- rivets along every seam ---
    spacing = 0.13 * A
    sd = np.abs(np.mod(along + spacing / 2.0, spacing) - spacing / 2.0)
    rd = np.sqrt((edge_dist - 0.085 * A) ** 2 + sd ** 2)
    dome = np.sqrt(np.clip(1.0 - (rd / (0.02 * A)) ** 2, 0.0, 1.0)) * (np.abs(along) < R / 2.0 - 0.1 * A)
    height += 0.35 * dome
    albedo = blend(albedo, [0.70, 0.71, 0.73], dome * 0.7)
    del sd, rd, dome, along

    # --- painted sector labels ---
    label_img = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(label_img)
    try:
        font = ImageFont.truetype(FONT_PATH, int(0.22 * A))
    except OSError:
        font = ImageFont.load_default()
    label_offset = 0.46 * A * DY / (1.5 * R)
    for cell in np.flatnonzero(has_label):
        x0, y0 = cell_center_px(cell)
        y0 += label_offset if cell_alt[cell] == 0 else -label_offset
        for sx in (-W, 0, W):
            for sy in (-H, 0, H):
                draw.text((x0 + sx, y0 + sy), label_text[cell], fill=255, font=font, anchor="mm")
    label = np.asarray(label_img, np.float32) / 255.0
    label *= 0.55 + 0.45 * smoothstep(0.3, 0.6, grain_n)
    paint = PAINT_PALETTE[label_paint[cid]]
    albedo = albedo + (paint - albedo) * (label * 0.9)[..., None]
    rough = rough + (0.55 - rough) * label
    del label_img, label, paint

    # --- grime and oxidation, heavier near seams ---
    near_edge = 1.0 - smoothstep(0.02 * A, 0.25 * A, edge_dist)
    grime = np.clip((grime_n - 0.45) * 2.2, 0.0, 1.0) * (0.3 + 0.7 * near_edge) * 0.45
    albedo = blend(albedo, RUST, grime * 0.55) * (1.0 - grime * 0.25)[..., None]
    albedo *= (0.96 + 0.08 * grain_n)[..., None]
    rough += grime * 0.25 + (grain_n - 0.5) * 0.08
    del near_edge, grime, grime_n

    # --- lights: ring + beacon on LIGHTS cells, single nav lights on some PLAIN cells ---
    emission = np.zeros((H, W, 3), np.float32)
    ang_q = np.round(np.arctan2(ly, lx) / (np.pi / 3.0)) * (np.pi / 3.0)
    d_ring = np.hypot(lx - 0.6 * A * np.cos(ang_q), ly - 0.6 * A * np.sin(ang_q))
    d_beacon = np.hypot(lx, ly)
    nav_a = nav_dir[cid] * (np.pi / 3.0)
    d_nav = np.hypot(lx - 0.72 * A * np.cos(nav_a), ly - 0.72 * A * np.sin(nav_a))
    lm = t == LIGHTS
    nav = has_nav[cid]
    light_color = LIGHT_PALETTE[cell_light[cid]]
    for d, mask, house_r, core_r in (
        (d_ring, lm, 0.06 * A, 0.035 * A),
        (d_beacon, lm, 0.09 * A, 0.055 * A),
        (d_nav, nav, 0.06 * A, 0.035 * A),
    ):
        housing = np.sqrt(np.clip(1.0 - (d / house_r) ** 2, 0.0, 1.0)) * mask
        core = (1.0 - smoothstep(core_r * 0.8, core_r, d)) * mask
        height = np.where(housing > 0, np.maximum(height, 1.0 + 0.5 * housing), height)
        albedo = blend(albedo, [0.25, 0.26, 0.28], (housing > 0).astype(np.float32))
        albedo = blend(albedo, [0.95, 0.95, 0.95], core)
        rough = np.where(housing > 0, 0.25, rough)
        emission = np.maximum(emission, light_color * core[..., None])
    del ang_q, d_ring, d_beacon, nav_a, d_nav, light_color
    halo_sigma = 0.03 * A
    for ch in range(3):
        emission[..., ch] += 0.8 * gaussian_filter(emission[..., ch], halo_sigma, mode="wrap")

    # --- ambient occlusion from the height field, lightly baked into albedo too ---
    cav = (gaussian_filter(height, 0.02 * A, mode="wrap") - height) * 1.2
    cav += (gaussian_filter(height, 0.08 * A, mode="wrap") - height) * 0.5
    ao = np.clip(1.0 - np.clip(cav, 0.0, 1.0), 0.25, 1.0)
    albedo *= (0.65 + 0.35 * ao)[..., None]
    del cav

    # --- normal map, OpenGL convention (green = toward the top of the image), as Godot expects ---
    strength = 6.0
    dhdx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dhdy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nx, ny, nz = -dhdx * strength, dhdy * strength, np.ones_like(height)
    norm = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    normal = np.stack([nx / norm, ny / norm, nz / norm], axis=-1) * 0.5 + 0.5
    del dhdx, dhdy, nx, ny, nz, norm

    def save_rgb(arr, name):
        Image.fromarray((np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGB").save(OUT_DIR / name)

    def save_gray(arr, name):
        save_rgb(np.repeat(arr[..., None], 3, axis=2), name)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    save_rgb(albedo, "albedo.png")
    save_gray(np.clip(rough, 0.05, 1.0), "roughness.png")
    save_rgb(normal, "normal.png")
    save_rgb(emission, "emission.png")
    save_gray(ao, "ao.png")
    print(f"wrote {W}x{H} hull textures to {OUT_DIR} ({N_CELLS} cells:",
          {name: int((cell_type == i).sum()) for i, name in enumerate(["plain", "hatch", "vent", "conduit", "lights"])}, ")")


if __name__ == "__main__":
    main()
