"""Extracts the North End greybox layout from docs/map/north_end_wireframe.svg.

Writes scripts/world/north_end_layout.gd: blocks (with lot cells), explicit buildings, road
polylines and street-name labels, all in wireframe pixels (~2 m/px, north up). The world builder
(scripts/world/city_generator.gd) scales them into meters. Run from the repo root:

    python tools/extract_north_end_layout.py
"""

import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "docs" / "map" / "north_end_wireframe.svg"
OUT = ROOT / "scripts" / "world" / "north_end_layout.gd"

# Map area (the legend lives at x > 1010).
MAP_MAX_X = 1010.0

ATTR = re.compile(r'(\w[\w-]*)="([^"]*)"')
NUM = re.compile(r"-?\d+(?:\.\d+)?")


def attrs(line: str) -> dict:
    return dict(ATTR.findall(line))


def bezier(p0, p1, p2, p3, steps):
    pts = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1.0 - t
        x = u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0]
        y = u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1]
        pts.append((x, y))
    return pts


def quad(p0, p1, p2, steps):
    pts = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1.0 - t
        pts.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return pts


def parse_path(d: str):
    """M/L/H/V/C/Q (absolute) into a polyline; curves are sampled."""
    tokens = re.findall(r"[MLHVCQZ]|-?\d+(?:\.\d+)?", d)
    pts = []
    cur = (0.0, 0.0)
    i = 0
    cmd = None
    while i < len(tokens):
        tok = tokens[i]
        if tok.isalpha():
            cmd = tok
            i += 1
            if cmd == "Z" and pts:
                pts.append(pts[0])
            continue
        if cmd in ("M", "L"):
            cur = (float(tokens[i]), float(tokens[i + 1]))
            pts.append(cur)
            i += 2
        elif cmd == "H":
            cur = (float(tokens[i]), cur[1])
            pts.append(cur)
            i += 1
        elif cmd == "V":
            cur = (cur[0], float(tokens[i]))
            pts.append(cur)
            i += 1
        elif cmd == "C":
            c1 = (float(tokens[i]), float(tokens[i + 1]))
            c2 = (float(tokens[i + 2]), float(tokens[i + 3]))
            end = (float(tokens[i + 4]), float(tokens[i + 5]))
            pts.extend(bezier(cur, c1, c2, end, max(2, int(math.dist(cur, end) / 25.0))))
            cur = end
            i += 6
        elif cmd == "Q":
            c1 = (float(tokens[i]), float(tokens[i + 1]))
            end = (float(tokens[i + 2]), float(tokens[i + 3]))
            pts.extend(quad(cur, c1, end, 6))
            cur = end
            i += 4
        else:
            i += 1
    return simplify(pts)


def simplify(pts, min_step=4.0):
    if len(pts) < 3:
        return pts
    out = [pts[0]]
    for p in pts[1:-1]:
        if math.dist(out[-1], p) >= min_step:
            out.append(p)
    out.append(pts[-1])
    return out


def main():
    lines = [l.strip() for l in SVG.read_text(encoding="utf-8").splitlines()]
    blocks, lot_lines, buildings, roads, labels = [], [], [], [], []
    for line in lines:
        a = attrs(line)
        cls = a.get("class", "")
        if line.startswith("<rect") and cls in ("blk", "blk-off"):
            blocks.append({"rect": [float(a["x"]), float(a["y"]), float(a["width"]), float(a["height"])], "off": cls == "blk-off"})
        elif line.startswith("<rect") and cls == "bldg":
            buildings.append([float(a["x"]), float(a["y"]), float(a["width"]), float(a["height"])])
        elif line.startswith("<line") and cls == "lot":
            lot_lines.append((float(a["x1"]), float(a["y1"]), float(a["x2"]), float(a["y2"])))
        elif line.startswith("<path") and cls in ("road-loc", "road-ave", "road-art"):
            roads.append({"kind": cls[5:], "pts": parse_path(a["d"])})
        elif line.startswith("<path") and a.get("stroke") == "#7a4c05" and "d" in a:
            pts = parse_path(a["d"])
            if a.get("stroke-width") == "26":
                roads.append({"kind": "highway", "pts": pts})
            elif a.get("stroke-width") == "7" and max(p[0] for p in pts) < MAP_MAX_X:
                roads.append({"kind": "ramp", "pts": pts})
        elif line.startswith("<path") and a.get("stroke") == "#3d3d3d" and a.get("stroke-width") == "4" and "d" in a:
            pts = parse_path(a["d"])
            if max(p[0] for p in pts) < MAP_MAX_X:
                roads.append({"kind": "rail", "pts": pts})
        elif line.startswith("<text") and cls in ("rlab", "rlab-art"):
            m = re.search(r">([^<]*)<", line)
            if not m:
                continue
            text = m.group(1).replace("&amp;", "&")
            rot = float(NUM.findall(a["transform"])[0]) if "transform" in a else 0.0
            labels.append({"text": text, "x": float(a["x"]), "y": float(a["y"]), "rot": rot, "art": cls == "rlab-art"})

    seen = set()
    unique_roads = []
    for road in roads:
        key = (road["kind"], tuple((round(x, 1), round(y, 1)) for x, y in road["pts"]))
        if key in seen:
            continue
        seen.add(key)
        unique_roads.append(road)

    for block in blocks:
        x, y, w, h = block["rect"]
        xs = sorted({x1 for x1, y1, x2, y2 in lot_lines if x1 == x2 and x < x1 < x + w and min(y1, y2) >= y - 0.5 and max(y1, y2) <= y + h + 0.5})
        ys = sorted({y1 for x1, y1, x2, y2 in lot_lines if y1 == y2 and y < y1 < y + h and min(x1, x2) >= x - 0.5 and max(x1, x2) <= x + w + 0.5})
        if not xs and not ys:
            block["lots"] = []
            continue
        cols = [x] + xs + [x + w]
        rows = [y] + ys + [y + h]
        block["lots"] = [[round(cols[c], 1), round(rows[r], 1), round(cols[c + 1] - cols[c], 1), round(rows[r + 1] - rows[r], 1)]
                         for c in range(len(cols) - 1) for r in range(len(rows) - 1)]

    def fmt_rect(r):
        return "Rect2(%.1f, %.1f, %.1f, %.1f)" % tuple(r)

    out = [
        "class_name NorthEndLayout",
        "extends RefCounted",
        "## GENERATED by tools/extract_north_end_layout.py from docs/map/north_end_wireframe.svg. Do not edit.",
        "## Wireframe pixels (~2 m/px, north up = -Z). CityGenerator scales these into meters.",
        "",
        "## {rect: Rect2, off: bool (hatched neighbour), lots: Array of Rect2 (empty = one building)}.",
        "const BLOCKS := [",
    ]
    for block in blocks:
        lots = ", ".join(fmt_rect(l) for l in block["lots"])
        out.append("\t{\"rect\": %s, \"off\": %s, \"lots\": [%s]}," % (fmt_rect(block["rect"]), "true" if block["off"] else "false", lots))
    out += ["]", "", "## Explicit building footprints drawn on the wireframe.", "const BUILDINGS := ["]
    out += ["\t%s," % fmt_rect(b) for b in buildings]
    out += ["]", "", "## {kind: loc|ave|art|highway|ramp|rail, pts: Array[Vector2] (consts cannot hold packed-array constructors)}.", "const ROADS := ["]
    for road in unique_roads:
        pts = ", ".join("Vector2(%.1f, %.1f)" % p for p in road["pts"])
        out.append("\t{\"kind\": &\"%s\", \"pts\": [%s]}," % (road["kind"], pts))
    out += ["]", "", "## Street names: {text, pos: Vector2, rot: degrees (SVG), art: arterial}.", "const STREET_LABELS := ["]
    for lab in labels:
        out.append("\t{\"text\": \"%s\", \"pos\": Vector2(%.1f, %.1f), \"rot\": %.1f, \"art\": %s}," % (
            lab["text"].replace('"', '\\"'), lab["x"], lab["y"], lab["rot"], "true" if lab["art"] else "false"))
    out += ["]", ""]
    OUT.write_text("\n".join(out), encoding="utf-8", newline="\n")
    kinds = {}
    for r in unique_roads:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    print("blocks %d (lots %d), buildings %d, roads %s, labels %d" % (
        len(blocks), sum(len(b["lots"]) for b in blocks), len(buildings), kinds, len(labels)))


if __name__ == "__main__":
    main()
