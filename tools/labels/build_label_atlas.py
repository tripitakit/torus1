# Builds the shared glyph atlas for the station's section ID labels (see
# scripts/section_label.gd, which the GLYPHS/ATLAS_COLS/ATLAS_ROWS constants
# here must match exactly). White glyphs, transparent background, one cell
# per character.
#
#   python3 tools/labels/build_label_atlas.py <repo>/assets/textures/labels

import os
import sys

from PIL import Image, ImageDraw, ImageFont

GLYPHS = "0123456789T-"
ATLAS_COLS = 4
ATLAS_ROWS = 3
CELL_SIZE = 256
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/liberation2/LiberationMono-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
]


def _font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    raise RuntimeError("no bold monospace font found among %s" % FONT_CANDIDATES)


def build(out_dir):
    atlas = Image.new("RGBA", (CELL_SIZE * ATLAS_COLS, CELL_SIZE * ATLAS_ROWS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)
    font = _font(int(CELL_SIZE * 0.78))
    for i, glyph in enumerate(GLYPHS):
        col, row = i % ATLAS_COLS, i // ATLAS_COLS
        bbox = draw.textbbox((0, 0), glyph, font=font)
        w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
        x = col * CELL_SIZE + (CELL_SIZE - w) / 2 - bbox[0]
        y = row * CELL_SIZE + (CELL_SIZE - h) / 2 - bbox[1]
        draw.text((x, y), glyph, font=font, fill=(255, 255, 255, 255))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "atlas.png")
    atlas.save(path)
    return path


if __name__ == "__main__":
    print(build(sys.argv[1]))
