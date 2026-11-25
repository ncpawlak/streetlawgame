"""Extracts the North End greybox layout from docs/map/north_end_wireframe.svg.

Writes scripts/world/north_end_layout.gd: blocks (with lot cells), explicit buildings, road
polylines, rail crossings, lakes and street-name labels, all in wireframe pixels (~2 m/px, north
up). The world builder (scripts/world/city_generator.gd) scales them into meters and draws the
roads exactly as written here.

The wireframe only draws the zone's own streets, so fix_network() turns them into one connected
town: streets cross the tracks at grade, the hatched neighbours (Riviera, Clement Street) get real
street grids, Clear Lake gets a lakeside drive, Lake Mangona's ring gets spokes, roads are clipped
at the water, and stubs are snapped onto the nearest road. check_network() fails the run if any
road is cut off, dead-ends or touches water. Run from the repo root:

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


# --- Road network -------------------------------------------------------------------------------

# Keep in sync with CityGenerator (PLAY_RECT_PX, ROAD_WIDTHS in m, METERS_PER_PX).
PLAY_RECT = (150.0, 150.0, 932.0, 1170.0)  # x0, y0, x1, y1
HALF_WIDTH = {k: w / 1.2 / 2.0 for k, w in {"loc": 9.0, "ave": 12.0, "art": 16.0, "highway": 26.0, "ramp": 8.0}.items()}
# Only these may leave the map (they continue into the next zone); every other end must meet a road.
EXIT_KINDS = ("art", "highway")
LAKES = [
    {"name": "LAKE MANGONA", "center": (394.0, 439.0), "radii": (75.0, 175.0)},
    {"name": "CLEAR LAKE", "center": (344.0, 862.0), "radii": (52.0, 105.0)},
]
LAGOON_X = 950.0
CLEAR_LAKE_DRIVE = {"center": (344.0, 862.0), "radii": (60.0, 114.0)}
# Buildings drawn over a street in the wireframe; the street stops at them.
ROAD_OBSTACLES = [(574.0, 342.0, 664.0, 430.0)]  # Grove General Hospital
SNAP_PX = 24.0
MIN_RUN_PX = 15.0
# Hatched neighbours rebuilt as street grids (rows/cols are street centrelines; the west edge is the rail).
RIVIERA = {"rows": [170.0, 225.0, 280.0, 330.0], "cols": [575.0, 680.0, 765.0, 850.0, 918.0]}
CLEMENT = {"rows": [720.0, 770.0, 830.0, 890.0, 940.0, 1000.0, 1060.0, 1110.0, 1150.0],
           "cols": [None, 620.0, 680.0, 740.0, 795.0, 850.0, 918.0]}
BLOCK_INSET = 6.0
# I-59 is an elevated viaduct. Only arterials pass under it, and only ramps connect to it: each
# arterial crossing gets a diamond interchange (NB/SB on and off ramps, one per quadrant).
# Ramp geometry in px: leaves the deck `length` before the arterial, `edge` off the centreline
# (flush with the deck), after a `taper` merge lane on the deck; meets the arterial `terminal` out.
INTERCHANGE = {"length": 55.0, "taper": 18.0, "edge": 14.0, "on_deck": 8.0, "terminal": 40.0}
HIGHWAY_GAP_PX = 1.5  # minimum asphalt gap between the deck/ramps and any street beside them


def seg_point_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / l2))
    q = (ax + t * dx, ay + t * dy)
    return math.dist(p, q), q


def poly_closest(p, pts):
    best = (1e9, None)
    for i in range(len(pts) - 1):
        d = seg_point_dist(p, pts[i], pts[i + 1])
        if d[0] < best[0]:
            best = d
    return best


def seg_intersect(p1, p2, p3, p4):
    d = (p2[0] - p1[0]) * (p4[1] - p3[1]) - (p2[1] - p1[1]) * (p4[0] - p3[0])
    if abs(d) < 1e-9:
        return None
    t = ((p3[0] - p1[0]) * (p4[1] - p3[1]) - (p3[1] - p1[1]) * (p4[0] - p3[0])) / d
    u = ((p3[0] - p1[0]) * (p2[1] - p1[1]) - (p3[1] - p1[1]) * (p2[0] - p1[0])) / d
    if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0:
        return (p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1]))
    return None


def poly_hit(a, b, pts):
    """First point where segment a->b crosses polyline pts (nearest to a)."""
    hits = [h for i in range(len(pts) - 1) if (h := seg_intersect(a, b, pts[i], pts[i + 1]))]
    return min(hits, key=lambda h: math.dist(a, h)) if hits else None


def in_ellipse(p, center, radii):
    return ((p[0] - center[0]) / radii[0]) ** 2 + ((p[1] - center[1]) / radii[1]) ** 2 < 1.0


def in_water(p, margin=0.0):
    if p[0] >= LAGOON_X - margin:
        return True
    return any(in_ellipse(p, l["center"], (l["radii"][0] + margin, l["radii"][1] + margin)) for l in LAKES)


def ellipse(center, radii, n=56):
    pts = [(round(center[0] + radii[0] * math.cos(math.tau * i / n), 1), round(center[1] + radii[1] * math.sin(math.tau * i / n), 1)) for i in range(n)]
    return pts + [pts[0]]


def rail_x(rail, y):
    for i in range(len(rail) - 1):
        (x0, y0), (x1, y1) = rail[i], rail[i + 1]
        if y0 <= y <= y1:
            return x0 + (x1 - x0) * ((y - y0) / (y1 - y0) if y1 != y0 else 0.0)
    return rail[-1][0]


def _blocked(p):
    if in_ellipse(p, CLEAR_LAKE_DRIVE["center"], (CLEAR_LAKE_DRIVE["radii"][0] - 2.0, CLEAR_LAKE_DRIVE["radii"][1] - 2.0)):
        return True
    if in_water(p, 2.0):
        return True
    return any(x0 + 1 < p[0] < x1 - 1 and y0 + 1 < p[1] < y1 - 1 for x0, y0, x1, y1 in ROAD_OBSTACLES)


def clip(road, blocked=_blocked):
    """Splits a road into the runs that stay out of the water and obstacles."""
    runs, cur, last_open = [], [], None
    pts = road["pts"]
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        steps = max(1, int(math.ceil(math.dist(a, b))))
        for s in range(steps + 1):
            p = (a[0] + (b[0] - a[0]) * s / steps, a[1] + (b[1] - a[1]) * s / steps)
            if blocked(p):
                if cur:
                    if cur[-1] != last_open:
                        cur.append(last_open)
                    runs.append(cur)
                cur = []
                continue
            if not cur:
                cur = [p]
            elif s in (0, steps) and cur[-1] != p:
                cur.append(p)  # keep the bends
            last_open = p
    if cur:
        if cur[-1] != last_open:
            cur.append(last_open)
        runs.append(cur)
    out = []
    for run in runs:
        if len(run) >= 2 and sum(math.dist(run[i], run[i + 1]) for i in range(len(run) - 1)) >= MIN_RUN_PX:
            out.append({**road, "pts": [(round(x, 1), round(y, 1)) for x, y in run]})
    return out

def connects(kind, other):
    """Which road kinds may join: ramps link I-59 to arterials; nothing else touches the highway."""
    if "rail" in (kind, other):
        return False
    if kind == "ramp" or other == "ramp":
        return {kind, other} in ({"ramp", "highway"}, {"ramp", "art"})
    return "highway" not in (kind, other)


def on_road(p, roads, skip, kind=None):
    """True when p lies on the asphalt of a road it may join (kind=None: any road)."""
    for j, r in enumerate(roads):
        if j == skip or r["kind"] == "rail" or (kind is not None and not connects(kind, r["kind"])):
            continue
        if poly_closest(p, r["pts"])[0] <= HALF_WIDTH[r["kind"]] + 1.0:
            return True
    return False


def off_map(p):
    x0, y0, x1, y1 = PLAY_RECT
    return not (x0 <= p[0] <= x1 and y0 <= p[1] <= y1)


def snap(roads):
    for i, road in enumerate(roads):
        if road["kind"] in ("rail", "highway", "ramp") or road["pts"][0] == road["pts"][-1]:
            continue
        for end in (0, -1):
            p = road["pts"][end]
            if on_road(p, roads, i, road["kind"]) or (off_map(p) and road["kind"] in EXIT_KINDS):
                continue
            best = (SNAP_PX, None)
            for j, r in enumerate(roads):
                if j != i and connects(road["kind"], r["kind"]):
                    d, q = poly_closest(p, r["pts"])
                    if d < best[0]:
                        best = (d, q)
            if best[1] is not None:
                road["pts"][end] = (round(best[1][0], 1), round(best[1][1], 1))


def x_at(pts, y):
    """x of a mostly north-south polyline at y."""
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        if min(y0, y1) <= y <= max(y0, y1) and y0 != y1:
            return x0 + (x1 - x0) * (y - y0) / (y1 - y0)
    return pts[0][0] if abs(y - pts[0][1]) < abs(y - pts[-1][1]) else pts[-1][0]


def diamond_ramps(highway, arterial):
    """The four ramps of a diamond interchange where `arterial` passes under `highway`.

    Right-hand traffic: the northbound carriageway is the east half. NB off = east/south quadrant,
    NB on = east/north, SB off = west/north, SB on = west/south. Each ramp's first point is on the deck.
    """
    hit = None
    for i in range(len(arterial) - 1):
        hit = hit or poly_hit(arterial[i], arterial[i + 1], highway)
    if hit is None or off_map(hit):
        return []
    ya = hit[1]
    g = INTERCHANGE
    ramps = []
    for sx in (1.0, -1.0):
        for sy in (-1.0, 1.0):
            y1 = ya + sy * g["length"]
            y0 = y1 + sy * g["taper"]
            p0 = (x_at(highway, y0) + sx * g["on_deck"], y0)
            p1 = (x_at(highway, y1) + sx * g["edge"], y1)
            tx = x_at(highway, ya) + sx * g["terminal"]
            end = poly_hit((tx, ya - 30.0), (tx, ya + 30.0), arterial) or (tx, ya)
            yc = y1 - sy * g["length"] * 0.5
            c1 = (x_at(highway, yc) + sx * g["edge"], yc)
            c2 = (tx, ya + sy * g["length"] * 0.35)
            pts = [p0]
            for k in range(1, 11):
                t = k / 10.0
                u = 1.0 - t
                pts.append(tuple(u ** 3 * p1[n] + 3 * u * u * t * c1[n] + 3 * u * t * t * c2[n] + t ** 3 * end[n] for n in (0, 1)))
            pts.insert(1, p1)
            pts.pop(2)  # t=0.1 sample sits right next to p1
            ramps.append({"kind": "ramp", "pts": [(round(x, 1), round(y, 1)) for x, y in pts]})
    return ramps


def highway_clear(kind, highway, ramps):
    """Blocked test for a street of `kind`: too close to the I-59 deck or any ramp."""
    hw = HALF_WIDTH[kind]

    def blocked(p):
        if poly_closest(p, highway)[0] < HALF_WIDTH["highway"] + hw + HIGHWAY_GAP_PX:
            return True
        return any(poly_closest(p, r)[0] < HALF_WIDTH["ramp"] + hw + HIGHWAY_GAP_PX for r in ramps)

    return blocked


def arc_positions(pts):
    out = [0.0]
    for i in range(len(pts) - 1):
        out.append(out[-1] + math.dist(pts[i], pts[i + 1]))
    return out


def sub_polyline(pts, s0, s1):
    """The part of pts between arc lengths s0 < s1."""
    acc = arc_positions(pts)

    def at(s):
        for i in range(len(pts) - 1):
            if acc[i + 1] >= s:
                t = 0.0 if acc[i + 1] == acc[i] else (s - acc[i]) / (acc[i + 1] - acc[i])
                return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
        return pts[-1]

    mid = [pts[i] for i in range(len(pts)) if s0 < acc[i] < s1]
    return [(round(x, 1), round(y, 1)) for x, y in [at(s0)] + mid + [at(s1)]]


def junctions(road, i, roads):
    """Arc lengths along `road` where another road it may join crosses it or ends on it."""
    pts = road["pts"]
    acc = arc_positions(pts)
    out = []
    for j, other in enumerate(roads):
        if j == i or not connects(road["kind"], other["kind"]):
            continue
        op = other["pts"]
        for s in range(len(pts) - 1):
            for t in range(len(op) - 1):
                h = seg_intersect(pts[s], pts[s + 1], op[t], op[t + 1])
                if h:
                    out.append(acc[s] + math.dist(pts[s], h))
        if op[0] == op[-1]:
            continue
        for e in (op[0], op[-1]):
            best = (1e9, 0.0)
            for s in range(len(pts) - 1):
                d, q = seg_point_dist(e, pts[s], pts[s + 1])
                if d < best[0]:
                    best = (d, acc[s] + math.dist(pts[s], q))
            if best[0] <= HALF_WIDTH[road["kind"]] + 1.0:
                out.append(best[1])
    return out


def prune_dead_ends(roads):
    """Cuts every loose street end back to its last junction; drops streets left with none."""
    changed = True
    while changed:
        changed = False
        for i, road in enumerate(roads):
            pts = road["pts"]
            if road["kind"] in ("rail", "highway", "ramp") or pts[0] == pts[-1]:
                continue
            loose = [end for end in (0, -1) if not on_road(pts[end], roads, i, road["kind"])
                     and not (off_map(pts[end]) and road["kind"] in EXIT_KINDS)]
            if not loose:
                continue
            total = arc_positions(pts)[-1]
            js = sorted(junctions(road, i, roads))
            s0 = min((s for s in js if s > 0.5), default=None) if 0 in loose else 0.0
            s1 = max((s for s in js if s < total - 0.5), default=None) if -1 in loose else total
            changed = True
            if s0 is None or s1 is None or s1 - s0 < MIN_RUN_PX:
                roads.pop(i)
            else:
                road["pts"] = sub_polyline(pts, s0, s1)
            break


def find(roads, kind, start):
    for r in roads:
        if r["kind"] == kind and math.dist(r["pts"][0], start) < 1.0:
            return r
    raise KeyError((kind, start))


def fix_network(roads, rail):
    roads = [{**r, "pts": list(r["pts"])} for r in roads]
    loc = lambda start: find(roads, "loc", start)
    ave = lambda start: find(roads, "ave", start)
    ring = next(r for r in roads if r["kind"] == "loc" and r["pts"][0] == (481.8, 445.0))
    # The wireframe loop overlaps itself instead of closing; close it so it has no ends.
    back = next((k for k in range(10, len(ring["pts"])) if math.dist(ring["pts"][k], ring["pts"][0]) < 3.0), None)
    ring["pts"] = ring["pts"][:back] + [ring["pts"][0]] if back else ring["pts"] + [ring["pts"][0]]
    mangona_ring = ring["pts"]
    # Tamarack Row streets cross the tracks and run on through Clement Street to the east road.
    for y in (770.0, 830.0, 890.0, 940.0, 1000.0, 1110.0):
        road = next(r for r in roads if r["kind"] == "loc" and r["pts"][0][1] == y and r["pts"][0][0] < 320)
        road["pts"][-1] = (918.0, y)
    # Mangona <-> Riviera / Northgrove crossings.
    loc((194.2, 225.0))["pts"][-1] = (918.0, 225.0)
    loc((515.0, 300.0))["pts"][-1] = (575.0, 300.0)
    loc((557.5, 330.0))["pts"][0] = (575.0, 330.0)
    roads.remove(loc((563.9, 450.0)))
    loc((515.0, 440.0))["pts"] = [(482.0, 440.0), (550.0, 440.0), (566.0, 450.0), (921.2, 450.0)]
    ave((565.2, 520.0))["pts"][0] = (515.0, 520.0)
    roads.remove(loc((515.0, 540.0)))  # stub to the tracks; 520 now crosses right beside it
    loc((566.6, 590.0))["pts"][0] = (515.0, 590.0)
    roads.remove(loc((567.7, 650.0)))
    loc((253.9, 670.0))["pts"] = [(253.9, 670.0), (546.0, 670.0), (568.0, 650.0), (923.9, 650.0)]
    # Spokes onto Lake Mangona's ring road (it was an island).
    west = loc((229.3, 500.0))
    west["pts"][-1] = poly_hit((262.0, 500.0), (400.0, 500.0), mangona_ring)
    north = poly_hit((391.0, 225.0), (391.0, 400.0), mangona_ring)
    south = poly_hit((391.0, 670.0), (391.0, 500.0), mangona_ring)
    roads.append({"kind": "loc", "pts": [(391.0, 225.0), north]})
    roads.append({"kind": "loc", "pts": [south, (391.0, 670.0)]})
    # Clear Lake: a lakeside drive instead of streets running into the water.
    drive = ellipse(CLEAR_LAKE_DRIVE["center"], CLEAR_LAKE_DRIVE["radii"])
    roads.append({"kind": "loc", "pts": drive})
    # The wireframe's street beside I-59 south of Clear Lake is interchange land now; the next street
    # east carries its cross streets.
    roads.remove(loc((300.0, 975.0)))
    # Short connectors just east of the Okee Blvd ramps keep the house rows there on a street:
    # Clear Lake Dr -> 12th St (y1000), and 8th St (y1110) -> the south edge street.
    for y, x in ((1000.0, 312.0), (1110.0, 311.5)):
        next(r for r in roads if r["kind"] == "loc" and r["pts"][0][1] == y and r["pts"][-1] == (918.0, y))["pts"][0] = (x, y)
    roads.append({"kind": "loc", "pts": [poly_hit((312.0, 1000.0), (312.0, 900.0), drive), (312.0, 1000.0)]})
    roads.append({"kind": "loc", "pts": [(311.5, 1110.0), (311.5, 1150.0)]})
    # Northgrove's columns carry on south through Clement Street; the east road runs the whole zone.
    for x in (620.0, 740.0, 795.0):
        loc((x, 330.0))["pts"][-1] = (x, 1150.0)
    east = loc((918.0, 330.0))
    east["pts"].insert(0, (918.0, 170.0))
    # Riviera grid and the zone's north and south edge streets.
    roads.append({"kind": "loc", "pts": [(171.0, 170.0), (918.0, 170.0)]})
    roads.append({"kind": "loc", "pts": [(575.0, 280.0), (918.0, 280.0)]})
    for x in (575.0, 765.0):
        roads.append({"kind": "loc", "pts": [(x, 170.0), (x, 330.0)]})
    roads.append({"kind": "loc", "pts": [(290.5, 1150.0), (918.0, 1150.0)]})
    # Tamarack Row's avenue lines up with Industrial Way across Lakes Blvd (the wireframe offsets them).
    for road in roads:
        if road["kind"] == "ave" and all(x == 505.0 for x, _ in road["pts"]):
            road["pts"] = [(515.0, y) for _, y in road["pts"]]
    # Replace the wireframe's stub ramps with full diamond interchanges.
    roads = [r for r in roads if r["kind"] != "ramp"]
    highway = next(r for r in roads if r["kind"] == "highway")["pts"]
    ramps = [ramp for r in roads if r["kind"] == "art" for ramp in diamond_ramps(highway, r["pts"])]
    ramp_pts = [r["pts"] for r in ramps]
    out = []
    for road in roads:
        if road["kind"] in ("rail", "highway"):
            out.append(road)
            continue
        runs = [road] if road["pts"] in (drive, mangona_ring) else clip(road)
        for run in runs:
            if run["kind"] == "art":
                out.append(run)
            else:
                blocked = highway_clear(run["kind"], highway, ramp_pts)
                out.extend(clip(run, blocked) if _near(run, blocked) else [run])
    out += ramps
    snap(out)
    prune_dead_ends(out)
    return out


def _near(road, blocked):
    pts = road["pts"]
    for i in range(len(pts) - 1):
        steps = max(1, int(math.dist(pts[i], pts[i + 1])))
        if any(blocked((pts[i][0] + (pts[i + 1][0] - pts[i][0]) * s / steps, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * s / steps)) for s in range(steps + 1)):
            return True
    return False


def check_network(roads):
    """Every road meets another (or leaves the map as an arterial), none touch water, all connected,
    and I-59 is grade-separated: only arterials pass under it, only ramps join it, and every arterial
    crossing has all four diamond ramps."""
    problems = []
    net = [r for r in roads if r["kind"] != "rail"]
    highway = next(r for r in net if r["kind"] == "highway")["pts"]
    ramps = [r["pts"] for r in net if r["kind"] == "ramp"]
    for i, road in enumerate(net):
        for p in road["pts"]:
            if in_water(p):
                problems.append("%s point %s is in the water" % (road["kind"], p))
        if road["kind"] not in ("highway", "ramp", "art") and _near(road, highway_clear(road["kind"], highway, ramps)):
            problems.append("%s %s..%s touches I-59 or a ramp without a junction" % (road["kind"], road["pts"][0], road["pts"][-1]))
        if road["pts"][0] == road["pts"][-1]:
            continue
        for p in (road["pts"][0], road["pts"][-1]):
            if not on_road(p, net, i, road["kind"]) and not (off_map(p) and road["kind"] in EXIT_KINDS):
                problems.append("%s dead-ends at %s" % (road["kind"], p))
    for art in (r for r in net if r["kind"] == "art"):
        hit = next((h for i in range(len(art["pts"]) - 1) if (h := poly_hit(art["pts"][i], art["pts"][i + 1], highway))), None)
        if hit is None or off_map(hit):
            continue
        quadrants = set()
        for ramp in ramps:
            if poly_closest(ramp[-1], art["pts"])[0] <= HALF_WIDTH["art"] + 1.0 and poly_closest(ramp[0], highway)[0] <= HALF_WIDTH["highway"]:
                quadrants.add((ramp[0][0] > x_at(highway, ramp[0][1]), ramp[0][1] > hit[1]))
        if len(quadrants) != 4:
            problems.append("interchange at %s has %d of 4 ramps" % (hit, len(quadrants)))
    parent = list(range(len(net)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i, a in enumerate(net):
        for j in range(i + 1, len(net)):
            b = net[j]
            if not connects(a["kind"], b["kind"]):
                continue
            touch = any(poly_closest(p, b["pts"])[0] <= HALF_WIDTH[b["kind"]] + 1.0 for p in (a["pts"][0], a["pts"][-1])) \
                or any(poly_closest(p, a["pts"])[0] <= HALF_WIDTH[a["kind"]] + 1.0 for p in (b["pts"][0], b["pts"][-1])) \
                or any(seg_intersect(a["pts"][s], a["pts"][s + 1], b["pts"][t], b["pts"][t + 1])
                       for s in range(len(a["pts"]) - 1) for t in range(len(b["pts"]) - 1))
            if touch:
                parent[root(i)] = root(j)
    groups = len({root(i) for i in range(len(net))})
    if groups != 1:
        problems.append("road network has %d separate parts" % groups)
    return problems


def rail_crossings(roads):
    rail = next(r for r in roads if r["kind"] == "rail")["pts"]
    out = []
    for road in roads:
        if road["kind"] == "rail":
            continue
        pts = road["pts"]
        for i in range(len(pts) - 1):
            for k in range(len(rail) - 1):
                hit = seg_intersect(pts[i], pts[i + 1], rail[k], rail[k + 1])
                if hit and not off_map(hit) and all(math.dist(hit, x["at"]) > 3.0 for x in out):
                    d = math.dist(pts[i], pts[i + 1])
                    out.append({"at": hit, "dir": ((pts[i + 1][0] - pts[i][0]) / d, (pts[i + 1][1] - pts[i][1]) / d), "kind": road["kind"]})
    return out


def grid_blocks(rows, cols, rail, roads):
    """Filler blocks for a rebuilt neighbour grid, inset from the streets around them."""
    def inset(kind_x):
        return BLOCK_INSET + (5.0 if kind_x else 0.0)  # arterials are wider and gently curved

    arterial_x = {680.0, 850.0}
    arterial_y = {720.0, 1060.0}
    blocks = []
    for r in range(len(rows) - 1):
        y0 = rows[r] + inset(rows[r] in arterial_y)
        y1 = rows[r + 1] - inset(rows[r + 1] in arterial_y)
        for c in range(len(cols) - 1):
            if cols[c] is None:
                x0 = max(rail_x(rail, y0), rail_x(rail, y1)) + 8.0
            else:
                x0 = cols[c] + inset(cols[c] in arterial_x)
            x1 = cols[c + 1] - inset(cols[c + 1] in arterial_x)
            if x1 - x0 > 8.0 and y1 - y0 > 8.0:
                blocks.append({"rect": [round(x0, 1), round(y0, 1), round(x1 - x0, 1), round(y1 - y0, 1)], "off": True, "lots": []})
    return blocks


def road_distance(rect, roads):
    """Closest distance from a rect's centre to any non-rail road centreline sample."""
    cx, cy = rect[0] + rect[2] / 2, rect[1] + rect[3] / 2
    best = math.inf
    for road in roads:
        if road["kind"] == "rail":
            continue
        pts = road["pts"]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            steps = max(1, int(math.dist(a, b) / 1.5))
            for s in range(steps + 1):
                t = s / steps
                best = min(best, math.dist((cx, cy), (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)) - HALF_WIDTH[road["kind"]])
    return best


FRONTAGE_PX = 24.0  # half a street + sidewalk + one lot depth; tests/location_tests.gd uses the same limit


def edge_distance(rect, pts):
    """Closest distance from a road centreline (sampled) to the edge of a rect."""
    x, y, w, h = rect
    best = math.inf
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        steps = max(1, int(math.dist(a, b) / 1.5))
        for s in range(steps + 1):
            t = s / steps
            px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            best = min(best, math.hypot(px - min(max(px, x), x + w), py - min(max(py, y), y + h)))
    return best


def fronts_street(rect, roads):
    """A lot must face a drivable street, and not back onto I-59 or a ramp with no street in front."""
    street = min((edge_distance(rect, r["pts"]) for r in roads if r["kind"] in ("loc", "ave", "art")), default=math.inf)
    freeway = min((edge_distance(rect, r["pts"]) for r in roads if r["kind"] in ("highway", "ramp")), default=math.inf)
    return street <= FRONTAGE_PX and street <= freeway


def rect_hits_road(rect, roads):
    x, y, w, h = rect
    for road in roads:
        if road["kind"] == "rail":
            continue
        hw = HALF_WIDTH[road["kind"]] - 0.5
        pts = road["pts"]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            steps = max(1, int(math.dist(a, b) / 1.5))
            for s in range(steps + 1):
                t = s / steps
                px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                if x - hw < px < x + w + hw and y - hw < py < y + h + hw:
                    return True
    return False


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

    rail = next(r for r in unique_roads if r["kind"] == "rail")["pts"]
    unique_roads = fix_network(unique_roads, rail)
    problems = check_network(unique_roads)
    crossings = rail_crossings(unique_roads)
    labels.append({"text": "Clear Lake Dr", "x": 300.0, "y": 760.0, "rot": 0.0, "art": False})
    blocks = [b for b in blocks if not b["off"]]
    blocks += grid_blocks(RIVIERA["rows"], RIVIERA["cols"], rail, unique_roads)
    blocks += grid_blocks(CLEMENT["rows"], CLEMENT["cols"], rail, unique_roads)

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

    dropped = unfronted = 0
    for block in blocks:
        if block["off"]:
            if rect_hits_road(block["rect"], unique_roads):
                problems.append("filler block %s overlaps a road" % block["rect"])
            continue
        had_lots = bool(block["lots"])
        keep = [l for l in block["lots"] if not rect_hits_road(l, unique_roads)]
        dropped += len(block["lots"]) - len(keep)
        stranded = [l for l in keep if not fronts_street(l, unique_roads)]
        unfronted += len(stranded)
        keep = [l for l in keep if l not in stranded]
        block["lots"] = keep
        if keep and rect_hits_road(block["rect"], unique_roads):
            # Shrink the block pad to its surviving lots so it doesn't run under a road or ramp;
            # an L-shaped remainder still overlaps, so shed lots nearest the road until clear.
            def bbox(ls):
                x0, y0 = min(l[0] for l in ls), min(l[1] for l in ls)
                return [x0, y0, round(max(l[0] + l[2] for l in ls) - x0, 1), round(max(l[1] + l[3] for l in ls) - y0, 1)]
            while keep and rect_hits_road(bbox(keep), unique_roads):
                hitting = [r for r in unique_roads if rect_hits_road(bbox(keep), [r])]
                keep.remove(min(keep, key=lambda l: road_distance(l, hitting)))
                dropped += 1
            block["lots"] = keep
            if keep:
                block["rect"] = bbox(keep)
        if had_lots and not block["lots"]:
            block["rect"] = [0, 0, 0, 0]  # every lot was under a road or stranded: leave the ground empty
            continue
        if not block["lots"] and not fronts_street(block["rect"], unique_roads):
            unfronted += 1
            block["rect"] = [0, 0, 0, 0]  # a lone building backing onto I-59 with no street in front
            continue
        if not block["lots"] and rect_hits_road([block["rect"][0] + 3, block["rect"][1] + 3, block["rect"][2] - 6, block["rect"][3] - 6], unique_roads):
            problems.append("block %s overlaps a road" % block["rect"])
    blocks = [b for b in blocks if b["rect"][2] > 0]

    # Wireframe buildings sit where drawn, but one left facing I-59 slides up to its nearest street.
    for i, b in enumerate(buildings):
        if fronts_street(b, unique_roads):
            continue
        street = min((r for r in unique_roads if r["kind"] in ("loc", "ave", "art")), key=lambda r: edge_distance(b, r["pts"]))
        cx, cy = b[0] + b[2] / 2, b[1] + b[3] / 2
        best = (math.inf, None)
        pts = street["pts"]
        for k in range(len(pts) - 1):
            a, c = pts[k], pts[k + 1]
            steps = max(1, int(math.dist(a, c) / 1.5))
            for st in range(steps + 1):
                t = st / steps
                q = (a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t)
                d = math.hypot(q[0] - min(max(q[0], b[0]), b[0] + b[2]), q[1] - min(max(q[1], b[1]), b[1] + b[3]))
                if d < best[0]:
                    best = (d, q)
        d, (qx, qy) = best
        near = (min(max(qx, b[0]), b[0] + b[2]), min(max(qy, b[1]), b[1] + b[3]))
        move = d - HALF_WIDTH[street["kind"]] - 3.0
        moved = [round(b[0] + (qx - near[0]) / d * move, 1), round(b[1] + (qy - near[1]) / d * move, 1), b[2], b[3]]
        if rect_hits_road(moved, unique_roads) or not fronts_street(moved, unique_roads):
            problems.append("building %s has no street frontage" % b)
        buildings[i] = moved

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
    out += ["]", "", "## Where a road crosses the tracks at grade: {at: Vector2, dir: Vector2 (road direction), kind}.", "const RAIL_CROSSINGS := ["]
    for x in crossings:
        out.append("\t{\"at\": Vector2(%.1f, %.1f), \"dir\": Vector2(%.3f, %.3f), \"kind\": &\"%s\"}," % (x["at"] + x["dir"] + (x["kind"],)))
    out += ["]", "", "## Lakes (ellipses, px). Roads stay out of them; the lagoon is everything east of LAGOON_X.", "const LAKES := ["]
    for lake in LAKES:
        out.append("\t{\"name\": \"%s\", \"center\": Vector2(%.1f, %.1f), \"radii\": Vector2(%.1f, %.1f)}," % ((lake["name"],) + lake["center"] + lake["radii"]))
    out += ["]", "const LAGOON_X := %.1f" % LAGOON_X]
    out += ["", "## Street names: {text, pos: Vector2, rot: degrees (SVG), art: arterial}.", "const STREET_LABELS := ["]
    for lab in labels:
        out.append("\t{\"text\": \"%s\", \"pos\": Vector2(%.1f, %.1f), \"rot\": %.1f, \"art\": %s}," % (
            lab["text"].replace('"', '\\"'), lab["x"], lab["y"], lab["rot"], "true" if lab["art"] else "false"))
    out += ["]", ""]
    OUT.write_text("\n".join(out), encoding="utf-8", newline="\n")
    kinds = {}
    for r in unique_roads:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    print("blocks %d (lots %d, %d dropped under roads, %d with no street frontage), buildings %d, roads %s, rail crossings %d, labels %d" % (
        len(blocks), sum(len(b["lots"]) for b in blocks), dropped, unfronted, len(buildings), kinds, len(crossings), len(labels)))
    for p in problems:
        print("PROBLEM:", p)
    if problems:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
