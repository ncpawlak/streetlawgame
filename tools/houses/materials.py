"""Procedural textures (PIL) and StandardMaterial3D .tres files for the house kit."""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

TEX_DIR = "assets/textures/houses"
MAT_DIR = "assets/materials/houses"
TEX_RES = "res://" + TEX_DIR
MAT_RES = "res://" + MAT_DIR


def _noise(img, amount, seed):
    rnd = random.Random(seed)
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            d = rnd.randint(-amount, amount)
            px[x, y] = tuple(max(0, min(255, c + d)) for c in p[:3]) + tuple(p[3:])
    return img


def _siding():
    img = Image.new("RGB", (256, 256), (235, 235, 235))
    d = ImageDraw.Draw(img)
    board = 32
    for i in range(256 // board):
        y0 = i * board
        for k in range(board):
            v = 250 - int(k * 0.9)
            d.line([(0, y0 + k), (255, y0 + k)], fill=(v, v, v))
        d.line([(0, y0 + board - 2), (255, y0 + board - 2)], fill=(150, 150, 150))
        d.line([(0, y0 + board - 1), (255, y0 + board - 1)], fill=(120, 120, 120))
    return _noise(img, 6, 1)


def _brick(base, seed):
    rnd = random.Random(seed)
    img = Image.new("RGB", (256, 256), (190, 186, 178))
    d = ImageDraw.Draw(img)
    bh, bw, mortar = 22, 56, 3
    for row in range(256 // bh + 1):
        off = (bw // 2) if row % 2 else 0
        for col in range(-1, 256 // bw + 2):
            x0 = col * bw + off
            y0 = row * bh
            k = rnd.uniform(0.75, 1.15)
            c = tuple(int(max(0, min(255, ch * k))) for ch in base)
            d.rectangle([x0 + mortar, y0 + mortar, x0 + bw - 1, y0 + bh - 1], fill=c)
    return _noise(img, 10, seed)


def _shingles():
    rnd = random.Random(7)
    img = Image.new("RGB", (256, 256), (60, 60, 60))
    d = ImageDraw.Draw(img)
    row_h, tab = 21, 32
    for row in range(256 // row_h + 1):
        off = rnd.randint(0, tab)
        y0 = row * row_h
        for col in range(-1, 256 // tab + 2):
            x0 = col * tab + off
            v = rnd.randint(185, 235)
            d.rectangle([x0 + 1, y0, x0 + tab - 2, y0 + row_h - 4], fill=(v, v, v))
            d.line([(x0 + 1, y0 + row_h - 4), (x0 + tab - 2, y0 + row_h - 4)], fill=(110, 110, 110))
    return _noise(img, 14, 8)


def _speckle(base, amount, seed, blur=0.0):
    img = _noise(Image.new("RGB", (256, 256), base), amount, seed)
    return img.filter(ImageFilter.GaussianBlur(blur)) if blur else img


def _grass():
    rnd = random.Random(3)
    img = Image.new("RGB", (256, 256))
    px = img.load()
    for y in range(256):
        for x in range(256):
            k = rnd.uniform(0.75, 1.2)
            px[x, y] = (int(74 * k), int(116 * k), int(50 * k))
    return img.filter(ImageFilter.GaussianBlur(0.6))


def _planks():
    rnd = random.Random(11)
    img = Image.new("RGB", (256, 256), (120, 120, 120))
    d = ImageDraw.Draw(img)
    w = 32
    for i in range(256 // w):
        v = rnd.randint(200, 245)
        d.rectangle([i * w, 0, i * w + w - 3, 255], fill=(v, v, v))
    return _noise(img, 12, 12)


def _picket():
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    white = (245, 245, 240, 255)
    for i in range(4):
        x0 = i * 64 + 14
        d.rectangle([x0, 36, x0 + 36, 255], fill=white)
        d.polygon([(x0, 36), (x0 + 18, 6), (x0 + 36, 36)], fill=white)
    d.rectangle([0, 80, 255, 96], fill=(235, 235, 230, 255))
    d.rectangle([0, 200, 255, 216], fill=(235, 235, 230, 255))
    return img


def _chainlink():
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = (190, 195, 198, 255)
    for k in range(-128, 256, 16):
        d.line([(k, 0), (k + 128, 128)], fill=c, width=2)
        d.line([(k + 128, 0), (k, 128)], fill=c, width=2)
    return img


def _cmu():
    img = Image.new("RGB", (256, 256), (175, 175, 170))
    d = ImageDraw.Draw(img)
    bh, bw = 32, 64
    for row in range(256 // bh):
        off = (row % 2) * bw // 2
        for i in range(-1, 256 // bw + 1):
            x = i * bw + off
            d.rectangle([x + 2, row * bh + 2, x + bw - 2, row * bh + bh - 2], fill=(222, 222, 218))
    return _noise(img, 10, 31)


def _corrugated():
    img = Image.new("RGB", (256, 256))
    d = ImageDraw.Draw(img)
    for x in range(256):
        v = int(205 + 35 * math.cos(x / 256 * 16 * math.pi))
        d.line([x, 0, x, 255], fill=(v, v, v))
    return _noise(img, 4, 32)


def _slats():
    img = _corrugated().rotate(90)
    d = ImageDraw.Draw(img)
    for y in range(0, 256, 32):
        d.line([0, y, 255, y], fill=(120, 120, 120), width=2)
    return img


def _barrel_tile():
    """Spanish / barrel roof tile: alternating round caps and pans in staggered courses."""
    img = Image.new("RGB", (256, 256))
    px = img.load()
    course, pitch = 64, 32
    for y in range(256):
        lap = (y % course) / course
        for x in range(256):
            u = (x % pitch) / pitch
            v = 0.62 + 0.38 * math.sin(u * math.pi * 2.0)
            v *= 0.78 + 0.22 * (1.0 - lap)
            if lap > 0.93:
                v *= 0.6
            c = int(255 * max(0.0, min(1.0, v)))
            px[x, y] = (c, c, c)
    return _noise(img, 10, 41)


def _pavers():
    rnd = random.Random(42)
    img = Image.new("RGB", (256, 256), (150, 145, 138))
    d = ImageDraw.Draw(img)
    s = 32
    for row in range(256 // s):
        for col in range(256 // s):
            k = rnd.uniform(0.85, 1.1)
            v = int(232 * k)
            if (row + col) % 2:
                d.rectangle([col * s + 2, row * s + 2, col * s + s - 2, row * s + s // 2 - 1], fill=(v, v, v))
                d.rectangle([col * s + 2, row * s + s // 2 + 1, col * s + s - 2, row * s + s - 2], fill=(v, v, v))
            else:
                d.rectangle([col * s + 2, row * s + 2, col * s + s // 2 - 1, row * s + s - 2], fill=(v, v, v))
                d.rectangle([col * s + s // 2 + 1, row * s + 2, col * s + s - 2, row * s + s - 2], fill=(v, v, v))
    return _noise(img, 8, 43)


def _palm_trunk():
    """Ringed palm trunk (rings run around the trunk: horizontal bands in triplanar side view)."""
    img = Image.new("RGB", (256, 256))
    d = ImageDraw.Draw(img)
    for y in range(256):
        k = (y % 16) / 16
        v = int(200 + 40 * math.sin(k * math.pi)) if k > 0.12 else 140
        d.line([0, y, 255, y], fill=(v, v, v))
    return _noise(img, 10, 44)


def _water():
    img = _speckle((235, 235, 235), 10, 45, 1.6)
    d = ImageDraw.Draw(img)
    rnd = random.Random(46)
    for _ in range(40):
        x, y = rnd.randint(0, 255), rnd.randint(0, 255)
        d.arc([x, y, x + rnd.randint(14, 40), y + rnd.randint(4, 10)], 180, 360, fill=(255, 255, 255))
    return img


TEXTURES = {
    "cmu": _cmu,
    "corrugated": _corrugated,
    "slats": _slats,
    "siding": _siding,
    "shingles": _shingles,
    "shingles_z": lambda: _shingles().rotate(90),
    "brick_red": lambda: _brick((150, 62, 44), 21),
    "brick_brown": lambda: _brick((108, 70, 52), 22),
    "brick_tan": lambda: _brick((196, 160, 118), 23),
    "stucco": lambda: _speckle((230, 230, 230), 14, 4, 0.8),
    "concrete": lambda: _speckle((205, 205, 200), 12, 5, 0.5),
    "asphalt": lambda: _speckle((60, 60, 62), 16, 6),
    "gravel": lambda: _speckle((150, 142, 130), 45, 9, 0.4),
    "grass": _grass,
    "planks": _planks,
    "picket": _picket,
    "chainlink": _chainlink,
    "barrel_tile": _barrel_tile,
    "barrel_tile_z": lambda: _barrel_tile().rotate(90),
    "pavers": _pavers,
    "palm_trunk": _palm_trunk,
    "sand": lambda: _speckle((225, 225, 225), 22, 47, 0.5),
    "water": _water,
}

_SIDING = {"white": (0.93, 0.93, 0.9), "cream": (0.94, 0.88, 0.72), "sage": (0.62, 0.7, 0.57),
           "blue": (0.56, 0.66, 0.77), "grey": (0.62, 0.64, 0.65), "yellow": (0.93, 0.82, 0.5),
           "tan": (0.77, 0.68, 0.54), "mint": (0.66, 0.81, 0.72), "red": (0.6, 0.22, 0.18),
           "navy": (0.26, 0.31, 0.43)}
# West Palm Beach: concrete-block houses in pastel stucco.
_STUCCO = {"pink": (0.92, 0.72, 0.68), "beige": (0.88, 0.8, 0.66), "white": (0.93, 0.92, 0.88),
           "peach": (0.96, 0.78, 0.6), "grey": (0.7, 0.7, 0.68), "mint": (0.72, 0.88, 0.78),
           "lavender": (0.8, 0.75, 0.9), "sky": (0.66, 0.82, 0.92), "salmon": (0.95, 0.64, 0.54),
           "butter": (0.97, 0.9, 0.6), "seafoam": (0.6, 0.85, 0.8), "coral": (0.93, 0.52, 0.46)}
_ROOF = {"charcoal": (0.32, 0.32, 0.34), "brown": (0.46, 0.34, 0.26), "slate": (0.42, 0.47, 0.52),
         "green": (0.3, 0.42, 0.33), "red": (0.62, 0.3, 0.22), "white": (0.86, 0.86, 0.84)}
# Barrel (Spanish) tile roofs for the nicer homes.
_ROOF_TILE = {"terracotta": (0.8, 0.44, 0.28), "tan": (0.88, 0.7, 0.52), "brown": (0.58, 0.36, 0.25)}
_FLAT = {
    "trim_white": (0.95, 0.95, 0.93), "trim_cream": (0.92, 0.87, 0.74), "trim_dark": (0.16, 0.16, 0.17),
    "trim_brown": (0.36, 0.25, 0.18), "brass": (0.8, 0.65, 0.3), "shutter_dark": (0.13, 0.2, 0.17),
    "shutter_blue": (0.2, 0.3, 0.45), "shutter_black": (0.08, 0.08, 0.09), "shutter_red": (0.45, 0.12, 0.1),
    "door_red": (0.6, 0.1, 0.09), "door_blue": (0.13, 0.25, 0.45), "door_green": (0.12, 0.3, 0.2),
    "door_black": (0.07, 0.07, 0.08), "door_white": (0.92, 0.92, 0.9), "door_yellow": (0.9, 0.7, 0.2),
    "door_wood": (0.45, 0.28, 0.15), "metal_dark": (0.2, 0.21, 0.22), "metal_grey": (0.6, 0.62, 0.64),
    "roof_metal": (0.55, 0.58, 0.6), "roof_flat": (0.35, 0.35, 0.36), "bark": (0.3, 0.22, 0.16),
    "foliage": (0.2, 0.42, 0.18), "foliage_dark": (0.14, 0.3, 0.14), "hedge": (0.18, 0.36, 0.16),
    "ac_unit": (0.78, 0.79, 0.77), "road_line": (0.95, 0.8, 0.2),
}
_PROPS = {
    "frond": (0.3, 0.52, 0.2), "frond_light": (0.42, 0.6, 0.24), "frond_dry": (0.62, 0.5, 0.28),
    "sabal_frond": (0.32, 0.46, 0.27), "coconut": (0.45, 0.32, 0.13), "banyan_bark": (0.5, 0.47, 0.41),
    "oak_bark": (0.27, 0.23, 0.19), "moss": (0.62, 0.66, 0.56), "oak_leaf": (0.2, 0.33, 0.16),
    "banyan_leaf": (0.18, 0.38, 0.16), "sea_grape": (0.3, 0.5, 0.2), "brush": (0.36, 0.44, 0.2),
    "brush_dry": (0.58, 0.52, 0.32), "weeds": (0.46, 0.54, 0.24), "leaf_dark": (0.14, 0.32, 0.14),
    "flower_red": (0.86, 0.1, 0.14), "flower_pink": (0.88, 0.18, 0.56), "flower_yellow": (0.98, 0.82, 0.16),
    "flower_white": (0.96, 0.95, 0.92), "flower_orange": (0.96, 0.5, 0.12), "flower_purple": (0.56, 0.24, 0.72),
    "wire": (0.04, 0.04, 0.05), "bin_green": (0.16, 0.36, 0.2), "bin_blue": (0.14, 0.3, 0.62),
    "bin_black": (0.1, 0.1, 0.11), "plastic_white": (0.9, 0.9, 0.88), "pool_liner": (0.32, 0.55, 0.82),
    "rust": (0.46, 0.24, 0.11), "rust_light": (0.6, 0.36, 0.18),
    "paint_pink": (0.95, 0.3, 0.6), "paint_green": (0.2, 0.75, 0.35), "paint_orange": (0.98, 0.55, 0.1),
    "paint_purple": (0.5, 0.25, 0.78), "paint_black": (0.06, 0.06, 0.07), "paint_red": (0.85, 0.12, 0.12),
    "paint_teal": (0.1, 0.65, 0.68), "paint_cyan": (0.3, 0.8, 0.92),
    "cloth_white": (0.95, 0.95, 0.94), "cloth_blue": (0.3, 0.45, 0.75), "cloth_red": (0.8, 0.25, 0.25),
    "cloth_yellow": (0.95, 0.85, 0.35), "cart_red": (0.75, 0.1, 0.1), "news_blue": (0.1, 0.25, 0.6),
    "news_red": (0.72, 0.1, 0.1), "news_yellow": (0.95, 0.78, 0.1), "news_green": (0.1, 0.45, 0.25),
    "storm_panel": (0.74, 0.76, 0.77), "tire": (0.07, 0.07, 0.07),
}


def material_table():
    """name -> (texture or None, rgb, uv scale = tiles per metre, extra)."""
    t = {}
    for k, c in _SIDING.items():
        t["siding_" + k] = ("siding", c, 0.75, {})
    for k, c in _STUCCO.items():
        t["stucco_" + k] = ("stucco", c, 0.5, {})
    for k in ("red", "brown", "tan"):
        t["brick_" + k] = ("brick_" + k, (1, 1, 1), 0.85, {})
    for k, c in _ROOF.items():
        t["roof_%s_x" % k] = ("shingles", c, 0.8, {"sharp": 8.0})
        t["roof_%s_z" % k] = ("shingles_z", c, 0.8, {"sharp": 8.0})
    for k, c in _ROOF_TILE.items():
        t["roof_tile_%s_x" % k] = ("barrel_tile", c, 0.9, {"sharp": 8.0})
        t["roof_tile_%s_z" % k] = ("barrel_tile_z", c, 0.9, {"sharp": 8.0})
    for k, c in _FLAT.items():
        t[k] = (None, c, 1.0, {})
    # --- West Palm Beach landscaping / street dressing (scenes/props/) ------------------------
    t["palm_trunk"] = ("palm_trunk", (0.62, 0.58, 0.5), 1.2, {})
    t["royal_trunk"] = ("palm_trunk", (0.82, 0.8, 0.76), 0.8, {})
    t["crownshaft"] = (None, (0.38, 0.55, 0.3), 1.0, {})
    t["sand"] = ("sand", (0.86, 0.79, 0.62), 0.5, {})
    t["dirt"] = ("sand", (0.56, 0.46, 0.34), 0.5, {})
    t["mulch"] = ("gravel", (0.6, 0.42, 0.3), 0.8, {})
    t["pavers"] = ("pavers", (0.9, 0.78, 0.64), 0.6, {})
    t["pavers_grey"] = ("pavers", (0.78, 0.77, 0.74), 0.6, {})
    t["water"] = ("water", (0.22, 0.38, 0.34), 0.15, {"metallic": 0.2, "roughness": 0.06})
    t["canal_water"] = ("water", (0.16, 0.3, 0.3), 0.1, {"metallic": 0.2, "roughness": 0.06})
    t["pool_water"] = ("water", (0.32, 0.72, 0.86), 0.3, {"roughness": 0.05, "emission": (0.1, 0.35, 0.45),
                                                          "energy": 0.3})
    t["screen"] = (None, (0.12, 0.13, 0.14), 1.0, {"blend": 0.35})
    t["wood_pole"] = ("planks", (0.42, 0.33, 0.25), 0.4, {})
    for k, c in _PROPS.items():
        t[k] = (None, c, 1.0, {})
    t["glass"] = (None, (0.16, 0.22, 0.28), 1.0, {"metallic": 0.5, "roughness": 0.08})
    t["garage_panel"] = ("siding", (0.92, 0.92, 0.9), 1.6, {})
    t["foundation"] = ("concrete", (0.62, 0.61, 0.58), 0.5, {})
    t["concrete"] = ("concrete", (0.8, 0.79, 0.76), 0.4, {})
    t["sidewalk"] = ("concrete", (0.74, 0.74, 0.72), 0.5, {})
    t["asphalt"] = ("asphalt", (1, 1, 1), 0.25, {})
    t["gravel"] = ("gravel", (1, 1, 1), 0.6, {})
    t["grass"] = ("grass", (1, 1, 1), 0.3, {})
    t["ground"] = ("grass", (0.85, 0.85, 0.8), 0.15, {})
    t["wood_deck"] = ("planks", (0.58, 0.42, 0.29), 0.7, {})
    t["wood_cladding"] = ("planks", (0.62, 0.45, 0.3), 0.6, {})
    t["fence_wood"] = ("planks", (0.62, 0.48, 0.33), 0.55, {})
    t["fence_picket"] = ("picket", (1, 1, 1), 1.0, {"alpha": True})
    t["fence_chain"] = ("chainlink", (1, 1, 1), 2.0, {"alpha": True})
    # --- commercial -----------------------------------------------------------------------
    for k, c in {"grey": (1, 1, 1), "tan": (0.95, 0.85, 0.68), "white": (1.08, 1.08, 1.06),
                 "green": (0.72, 0.85, 0.74)}.items():
        t["cmu_" + k] = ("cmu", c, 0.5, {})
    for k, c in {"grey": (0.72, 0.74, 0.76), "blue": (0.42, 0.55, 0.7), "tan": (0.82, 0.74, 0.6),
                 "red": (0.62, 0.24, 0.2), "white": (0.92, 0.93, 0.93)}.items():
        t["metal_wall_" + k] = ("corrugated", c, 0.5, {"metallic": 0.3, "roughness": 0.6})
    t["tilt_up"] = ("concrete", (0.86, 0.84, 0.8), 0.15, {})
    t["metal_roof_x"] = ("corrugated", (0.62, 0.64, 0.66), 0.5, {"metallic": 0.4, "roughness": 0.5})
    t["metal_roof_z"] = ("corrugated", (0.62, 0.64, 0.66), 0.5, {"metallic": 0.4, "roughness": 0.5})
    t["tilt_up_band"] = (None, (0.33, 0.43, 0.52), 1.0, {})
    t["grate"] = ("slats", (0.7, 0.72, 0.74), 1.0, {"metallic": 0.5, "roughness": 0.5})
    t["plywood"] = ("planks", (0.78, 0.66, 0.47), 0.6, {})
    t["interior_wall"] = (None, (0.86, 0.85, 0.82), 1.0, {})
    t["interior_floor"] = ("concrete", (0.55, 0.53, 0.5), 0.6, {})
    t["glass_lit"] = (None, (0.55, 0.62, 0.6), 1.0, {"metallic": 0.3, "roughness": 0.1,
                                                     "emission": (0.95, 0.85, 0.6), "energy": 0.5})
    t["paint_white"] = (None, (0.95, 0.95, 0.93), 1.0, {})
    t["paint_yellow"] = (None, (0.95, 0.8, 0.2), 1.0, {})
    t["paint_blue"] = (None, (0.15, 0.35, 0.75), 1.0, {})
    for k, c in {"red": (0.7, 0.12, 0.1), "green": (0.1, 0.42, 0.22), "blue": (0.12, 0.28, 0.6),
                 "black": (0.08, 0.08, 0.09), "yellow": (0.95, 0.75, 0.15), "orange": (0.92, 0.45, 0.1),
                 "purple": (0.42, 0.16, 0.5), "teal": (0.08, 0.5, 0.5), "white": (0.95, 0.95, 0.93),
                 "maroon": (0.4, 0.08, 0.1)}.items():
        t["awning_" + k] = (None, c, 1.0, {"roughness": 0.7})
        t["sign_" + k] = (None, c, 1.0, {"roughness": 0.4, "emission": c, "energy": 0.25})
    return t


def _fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def write_all(root):
    os.makedirs(os.path.join(root, TEX_DIR), exist_ok=True)
    os.makedirs(os.path.join(root, MAT_DIR), exist_ok=True)
    for name, fn in TEXTURES.items():
        fn().save(os.path.join(root, TEX_DIR, name + ".png"))
    for name, (tex, rgb, scale, extra) in material_table().items():
        if tex:
            lines = ['[gd_resource type="StandardMaterial3D" load_steps=2 format=3]', "",
                     '[ext_resource type="Texture2D" path="%s/%s.png" id="1_tex"]' % (TEX_RES, tex), ""]
        else:
            lines = ['[gd_resource type="StandardMaterial3D" format=3]', ""]
        lines.append("[resource]")
        lines.append('resource_name = "%s"' % name)
        if extra.get("alpha"):
            lines += ["transparency = 2", "alpha_scissor_threshold = 0.5", "cull_mode = 2"]
        if "blend" in extra:
            lines += ["transparency = 1", "cull_mode = 2"]
            rgb = tuple(rgb) + (extra["blend"],)
        a = rgb[3] if len(rgb) > 3 else 1
        lines.append("albedo_color = Color(%s, %s, %s, %s)" % (tuple(_fmt(c) for c in rgb[:3]) + (_fmt(a),)))
        if tex:
            lines.append('albedo_texture = ExtResource("1_tex")')
        if "metallic" in extra:
            lines.append("metallic = %s" % _fmt(extra["metallic"]))
        lines.append("roughness = %s" % _fmt(extra.get("roughness", 0.9)))
        if "emission" in extra:
            lines.append("emission_enabled = true")
            lines.append("emission = Color(%s, %s, %s, 1)" % tuple(_fmt(c) for c in extra["emission"]))
            lines.append("emission_energy_multiplier = %s" % _fmt(extra.get("energy", 1.0)))
        if tex:
            lines.append("uv1_scale = Vector3(%s, %s, %s)" % ((_fmt(scale),) * 3))
            lines.append("uv1_triplanar = true")
            lines.append("uv1_triplanar_sharpness = %s" % _fmt(extra.get("sharp", 1.0)))
            lines.append("texture_filter = 5")
        with open(os.path.join(root, MAT_DIR, name + ".tres"), "w", newline="\n") as f:
            f.write("\n".join(lines) + "\n")


def mat(name):
    return "%s/%s.tres" % (MAT_RES, name)
