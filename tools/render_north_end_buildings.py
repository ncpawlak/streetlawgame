"""Render the as-built North End building map.

Reads the generated layout (scripts/world/north_end_layout.gd) and the building census
(data/areas/north_end_buildings.json) and writes docs/map/north_end_buildings.svg + .png:
roads as the game builds them (after the extractor's fix_network), lakes, rail, I-59, and every
census building coloured by category. Unbuilt roster places are drawn as hollow diamonds.

The hand-drawn docs/map/north_end_wireframe.svg stays the *source* the extractor reads; this map
is the *output* picture. Rerun after any layout or census change:

    python tools/extract_north_end_layout.py
    Godot --headless --path . --import
    Godot --headless --path . res://tools/north_end_census.tscn
    python tools/render_north_end_buildings.py
"""
import json
import math
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
LAYOUT = ROOT / "scripts/world/north_end_layout.gd"
CENSUS = ROOT / "data/areas/north_end_buildings.json"
OUT_SVG = ROOT / "docs/map/north_end_buildings.svg"
OUT_PNG = ROOT / "docs/map/north_end_buildings.png"

PNG_SCALE = 2.0
LEGEND_W = 260

CATEGORY_COLOURS = {
    "house_1f": ("#8fc98f", "1-storey house"),
    "house_2f": ("#3f8f4f", "2-storey house"),
    "large_building": ("#7d8fa8", "Large building (apartments, warehouse, shops)"),
    "special_building": ("#b05fc4", "Special building (one-off landmark)"),
    "specialized_location": ("#e0453a", "Specialized location (robbery, trap, stick-up)"),
    "purchasable_business": ("#f0b323", "Purchasable business"),
    "out_of_area": ("#d6d2c8", "Neighbour filler (out of area)"),
}
ROAD_STYLE = {  # kind: (width px, colour)
    "highway": (16, "#5a5a5a"),
    "ramp": (6, "#7a7a7a"),
    "art": (11, "#b8b0a0"),
    "ave": (8, "#c8c2b4"),
    "loc": (6, "#d8d3c6"),
}
BG = "#f4f1ea"
WATER = "#a9cbe6"

VEC = re.compile(r"Vector2\(([-\d.]+), ([-\d.]+)\)")
RECT = re.compile(r"Rect2\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)")


def const_block(text: str, name: str) -> list[str]:
    start = text.index(f"const {name} := [")
    end = text.index("\n]", start)
    return [ln.strip() for ln in text[start:end].splitlines()[1:] if ln.strip().startswith("{")]


def parse_layout() -> dict:
    text = LAYOUT.read_text(encoding="utf-8")
    roads = []
    for ln in const_block(text, "ROADS"):
        kind = re.search(r'"kind": &"(\w+)"', ln).group(1)
        roads.append((kind, [(float(x), float(y)) for x, y in VEC.findall(ln)]))
    blocks = []
    for ln in const_block(text, "BLOCKS"):
        rects = [tuple(map(float, r)) for r in RECT.findall(ln)]
        blocks.append((rects[0], '"off": true' in ln))
    lakes = []
    for ln in const_block(text, "LAKES"):
        (cx, cy), (rx, ry) = [(float(x), float(y)) for x, y in VEC.findall(ln)]
        lakes.append((re.search(r'"name": "([^"]+)"', ln).group(1), cx, cy, rx, ry))
    labels = []
    for ln in const_block(text, "STREET_LABELS"):
        m = re.search(r'"text": "([^"]+)", "pos": Vector2\(([-\d.]+), ([-\d.]+)\), "rot": ([-\d.]+)', ln)
        labels.append((m.group(1), float(m.group(2)), float(m.group(3)), float(m.group(4))))
    lagoon = float(re.search(r"const LAGOON_X := ([-\d.]+)", text).group(1))
    return {"roads": roads, "blocks": blocks, "lakes": lakes, "labels": labels, "lagoon": lagoon}


def bounds(layout: dict) -> tuple[float, float, float, float]:
    xs, ys = [], []
    for _, pts in layout["roads"]:
        xs += [p[0] for p in pts]
        ys += [p[1] for p in pts]
    return min(xs) - 20, min(ys) - 20, max(xs) + 40, max(ys) + 20


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def render_svg(layout: dict, census: dict, box) -> str:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0} {y0} {w + LEGEND_W} {h}" '
           f'width="{(w + LEGEND_W) * PNG_SCALE:.0f}" height="{h * PNG_SCALE:.0f}" font-family="Segoe UI, Arial">',
           f'<rect x="{x0}" y="{y0}" width="{w + LEGEND_W}" height="{h}" fill="{BG}"/>',
           f'<rect x="{layout["lagoon"]}" y="{y0}" width="{x1 - layout["lagoon"]}" height="{h}" fill="{WATER}"/>']
    for name, cx, cy, rx, ry in layout["lakes"]:
        out.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{WATER}"/>')
        out.append(f'<text x="{cx}" y="{cy}" font-size="9" fill="#4a6f8f" text-anchor="middle">{esc(name)}</text>')
    for (bx, by, bw, bh), off in layout["blocks"]:
        out.append(f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" fill="{"#e6e2d8" if off else "#ebe7dc"}"/>')
    for kind in ("loc", "ave", "art", "ramp", "highway", "rail"):
        for k, pts in layout["roads"]:
            if k != kind:
                continue
            d = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
            if kind == "rail":
                out.append(f'<polyline points="{d}" fill="none" stroke="#6b4a2f" stroke-width="2" stroke-dasharray="5 3"/>')
            else:
                wdt, col = ROAD_STYLE[kind]
                out.append(f'<polyline points="{d}" fill="none" stroke="{col}" stroke-width="{wdt}" stroke-linecap="round" stroke-linejoin="round"/>')
    for entry in census["out_of_area"] + census["buildings"]:
        bx, by, bw, bh = entry["rect_px"]
        col = CATEGORY_COLOURS[entry["category"]][0]
        out.append(f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" fill="{col}" stroke="#333" stroke-width="0.3">'
                   f'<title>{esc(entry["id"])} · {entry["category"]} · {entry["design_archetype"]}</title></rect>')
    for entry in census.get("unbuilt", []):
        px, py = entry["rect_px"][:2]
        col = CATEGORY_COLOURS[entry["category"]][0] if entry["category"] else "#000"
        out.append(f'<polygon points="{px},{py - 7} {px + 7},{py} {px},{py + 7} {px - 7},{py}" fill="none" stroke="{col}" stroke-width="2">'
                   f'<title>{esc(entry["id"])} (unbuilt)</title></polygon>')
    for text, lx, ly, rot in layout["labels"]:
        out.append(f'<text x="{lx}" y="{ly}" font-size="7" fill="#333" text-anchor="middle" '
                   f'transform="rotate({rot} {lx} {ly})">{esc(text)}</text>')
    lx, ly = x1 + 12, y0 + 24
    out.append(f'<text x="{lx}" y="{ly}" font-size="13" font-weight="bold">North End buildings (as built)</text>')
    counts = dict(census["counts"])
    counts["out_of_area"] = len(census["out_of_area"])
    for i, (cat, (col, label)) in enumerate(CATEGORY_COLOURS.items()):
        y = ly + 22 + i * 18
        out.append(f'<rect x="{lx}" y="{y - 9}" width="12" height="10" fill="{col}" stroke="#333" stroke-width="0.4"/>')
        out.append(f'<text x="{lx + 18}" y="{y}" font-size="8.5">{esc(label)} ({counts.get(cat, 0)})</text>')
    y = ly + 22 + len(CATEGORY_COLOURS) * 18
    out.append(f'<polygon points="{lx + 6},{y - 10} {lx + 12},{y - 4} {lx + 6},{y + 2} {lx},{y - 4}" fill="none" stroke="#e0453a" stroke-width="1.5"/>')
    out.append(f'<text x="{lx + 18}" y="{y}" font-size="8.5">Unbuilt roster place (no lot yet) ({len(census.get("unbuilt", []))})</text>')
    out.append(f'<text x="{lx}" y="{y + 22}" font-size="7.5" fill="#555">1 px = {census["meters_per_px"]} m. Generated by</text>')
    out.append(f'<text x="{lx}" y="{y + 32}" font-size="7.5" fill="#555">tools/render_north_end_buildings.py</text>')
    out.append("</svg>")
    return "\n".join(out)


def font(size: int):
    for name in ("segoeui.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def render_png(layout: dict, census: dict, box) -> Image.Image:
    x0, y0, x1, y1 = box
    s = PNG_SCALE
    img = Image.new("RGB", (round((x1 - x0 + LEGEND_W) * s), round((y1 - y0) * s)), BG)
    d = ImageDraw.Draw(img)

    def p(x, y):
        return ((x - x0) * s, (y - y0) * s)

    def rect(r, **kw):
        bx, by, bw, bh = r
        d.rectangle([p(bx, by), p(bx + bw, by + bh)], **kw)

    d.rectangle([p(layout["lagoon"], y0), p(x1, y1)], fill=WATER)
    for _, cx, cy, rx, ry in layout["lakes"]:
        d.ellipse([p(cx - rx, cy - ry), p(cx + rx, cy + ry)], fill=WATER)
    for r, off in layout["blocks"]:
        rect(r, fill="#e6e2d8" if off else "#ebe7dc")
    for kind in ("loc", "ave", "art", "ramp", "highway", "rail"):
        for k, pts in layout["roads"]:
            if k != kind:
                continue
            xy = [p(*q) for q in pts]
            if kind == "rail":
                d.line(xy, fill="#6b4a2f", width=round(2 * s))
                continue
            wdt, col = ROAD_STYLE[kind]
            d.line(xy, fill=col, width=round(wdt * s), joint="curve")
            r = wdt * s / 2
            for q in (xy[0], xy[-1]):
                d.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=col)
    for entry in census["out_of_area"] + census["buildings"]:
        rect(entry["rect_px"], fill=CATEGORY_COLOURS[entry["category"]][0], outline="#333")
    for entry in census.get("unbuilt", []):
        cx, cy = p(*entry["rect_px"][:2])
        r = 7 * s
        col = CATEGORY_COLOURS[entry["category"]][0] if entry["category"] else "#000"
        d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], outline=col, width=round(2 * s))
    f = font(round(7 * s))
    for text, lx, ly, rot in layout["labels"]:
        tw = d.textlength(text, font=f)
        tile = Image.new("RGBA", (round(tw) + 4, round(10 * s)), (0, 0, 0, 0))
        ImageDraw.Draw(tile).text((2, 0), text, font=f, fill="#333")
        tile = tile.rotate(-rot, expand=True)
        cx, cy = p(lx, ly)
        img.paste(tile, (round(cx - tile.width / 2), round(cy - tile.height / 2 - 3 * s)), tile)
    lx, ly = (x1 - x0 + 12) * s, 14 * s
    d.text((lx, ly), "North End buildings (as built)", font=font(round(13 * s)), fill="#000")
    counts = dict(census["counts"])
    counts["out_of_area"] = len(census["out_of_area"])
    fl = font(round(8.5 * s))
    y = ly + 26 * s
    for cat, (col, label) in CATEGORY_COLOURS.items():
        d.rectangle([lx, y, lx + 12 * s, y + 10 * s], fill=col, outline="#333")
        d.text((lx + 18 * s, y - 1 * s), f"{label} ({counts.get(cat, 0)})", font=fl, fill="#000")
        y += 18 * s
    c = (lx + 6 * s, y + 5 * s)
    r = 6 * s
    d.polygon([(c[0], c[1] - r), (c[0] + r, c[1]), (c[0], c[1] + r), (c[0] - r, c[1])], outline="#e0453a", width=round(1.5 * s))
    d.text((lx + 18 * s, y - 1 * s), f"Unbuilt roster place ({len(census.get('unbuilt', []))})", font=fl, fill="#000")
    d.text((lx, y + 24 * s), f"1 px = {census['meters_per_px']} m", font=font(round(7.5 * s)), fill="#555")
    return img


def main() -> None:
    layout = parse_layout()
    census = json.loads(CENSUS.read_text(encoding="utf-8"))
    box = bounds(layout)
    OUT_SVG.write_text(render_svg(layout, census, box), encoding="utf-8")
    render_png(layout, census, box).save(OUT_PNG, optimize=True)
    n = len(census["buildings"]) + len(census["out_of_area"])
    print(f"rendered {n} buildings, {len(census.get('unbuilt', []))} unbuilt -> {OUT_SVG.name}, {OUT_PNG.name}")


if __name__ == "__main__":
    main()
