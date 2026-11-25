"""Builds one exterior-only house scene (lot + CSG shell) from a spec dict. See specs_*.py."""
import math

import roofs
from tscn import SUBTRACT, Scene, box, combiner, f, prism, v2, v3, xform

PARTS = "res://scenes/houses/parts/"
ROOT_SCRIPT = "res://scripts/world/houses/house_exterior.gd"
FLOOR_Y = 0.4
STOREY = 3.0
SIDES = {  # normal, yaw
    "front": ((0, 1), 0), "back": ((0, -1), 180), "right": ((1, 0), 90), "left": ((-1, 0), -90)}


class Wing:
    def __init__(self, spec, w):
        self.x0 = w["x"]
        self.x1 = w["x"] + w["w"]
        self.z1 = -w["s"]
        self.z0 = -w["s"] - w["d"]
        self.kind = w.get("kind", "house")
        self.floors = w.get("floors", spec["floors"] if self.kind == "house" else 1)
        self.wall = w.get("wall", spec["wall"])
        self.trim = w.get("trim", spec.get("trim", "trim_white"))
        self.roof = w.get("roof", spec.get("roof_shape", {"t": "gable", "axis": "x", "pitch": 0.5}))
        self.roof_mat = "roof_" + w.get("roof_color", spec.get("roof", "charcoal"))
        self.detached = w.get("detached", False)
        self.band = w.get("band", True)
        if self.kind == "house":
            self.top = FLOOR_Y + STOREY * self.floors
        elif self.kind == "shed":
            self.top = 2.3
        else:
            self.top = 3.0
        self.ridge = roofs.ridge_height(self.roof, self.x0, self.x1, self.z0, self.z1, self.top)
        default_win = None if self.kind == "house" else 0
        self.win = {s: w.get("win", {}).get(s, default_win) for s in SIDES}

    def span(self, side):
        return (self.x0, self.x1) if side in ("front", "back") else (self.z0, self.z1)

    def face(self, side, at, y):
        if side == "front":
            return (at, y, self.z1)
        if side == "back":
            return (at, y, self.z0)
        if side == "right":
            return (self.x1, y, at)
        return (self.x0, y, at)

    def contains(self, x, y, z, pad=0.05):
        return (self.x0 - pad <= x <= self.x1 + pad and self.z0 - pad <= z <= self.z1 + pad
                and y <= self.ridge)


class HouseBuilder:
    def __init__(self, spec):
        self.s = spec
        self.sc = Scene()
        self.wings = [Wing(spec, w) for w in spec["wings"]]
        self.reserved = {}  # (wing, side, floor) -> [(at, half width)]
        self.lot_w, self.lot_d = spec["lot"]

    # --- helpers ----------------------------------------------------------------------
    def reserve(self, wi, side, floor, at, half):
        self.reserved.setdefault((wi, side, floor), []).append((at, half))

    def part(self, parent, kind, wing, side, at, y, props):
        x, yy, z = wing.face(side, at, y)
        p = {"transform": xform((x, yy, z), SIDES[side][1])}
        p.update(props)
        return self.sc.node(kind.title().replace("_", ""), None, parent, p,
                            instance=PARTS + kind + ".tscn")

    def outside(self, wing, side, at, y, d=0.4):
        x, yy, z = wing.face(side, at, y)
        n = SIDES[side][0]
        return x + n[0] * d, yy, z + n[1] * d

    # --- shell --------------------------------------------------------------------------
    def walls(self, house):
        sc = self.sc
        for i, w in enumerate(self.wings):
            box(sc, house, "Wing%d" % (i + 1), w.x0, w.x1, 0, w.top, w.z0, w.z1, w.wall)
        for i, w in enumerate(self.wings):
            if w.band:
                box(sc, house, "Foundation", w.x0 - 0.05, w.x1 + 0.05, 0, 0.45, w.z0 - 0.05, w.z1 + 0.05, "foundation")
            if w.roof["t"] not in ("flat",):
                box(sc, house, "Frieze", w.x0 - 0.03, w.x1 + 0.03, w.top - 0.3, w.top, w.z0 - 0.03, w.z1 + 0.03, w.trim)
            if w.kind == "house" and w.floors == 2 and self.s.get("belt", True):
                y = FLOOR_Y + STOREY
                box(sc, house, "Belt", w.x0 - 0.04, w.x1 + 0.04, y - 0.08, y + 0.08, w.z0 - 0.04, w.z1 + 0.04, w.trim)
            for x in (w.x0, w.x1):
                for z in (w.z0, w.z1):
                    if self.s.get("corner_boards", w.wall.startswith("siding")):
                        box(sc, house, "Corner", x - 0.07, x + 0.07, 0.45, w.top, z - 0.07, z + 0.07, w.trim)

    def doors(self, house):
        for d in self.s.get("doors", []):
            w = self.wings[d.get("wing", 0)]
            side = d.get("side", "front")
            width = d.get("w", 1.2)
            props = {"opening": v2(width, 2.4), "style": str(d.get("style", 0)),
                     "door_material": self.sc.mat(d.get("mat", self.s.get("door", "door_red")))}
            if w.trim != "trim_white":
                props["frame_material"] = self.sc.mat(w.trim)
            y0 = d.get("y", FLOOR_Y)
            self.part(house, "house_door", w, side, d["at"], y0 + 1.2, props)
            self.reserve(d.get("wing", 0), side, 0, d["at"], width / 2 + 0.25)
        for g in self.s.get("garage_doors", []):
            w = self.wings[g["wing"]]
            side = g.get("side", "front")
            gw = g.get("w", 2.7)
            props = {"opening": v2(gw, 2.3), "window_row": "true" if g.get("windows") else "false"}
            if g.get("mat"):
                props["panel_material"] = self.sc.mat(g["mat"])
            if w.trim != "trim_white":
                props["frame_material"] = self.sc.mat(w.trim)
            self.part(house, "garage_door", w, side, g["at"], 1.15, props)
            self.reserve(g["wing"], side, 0, g["at"], gw / 2 + 0.3)
        for p in self.s.get("pictures", []):
            w = self.wings[p.get("wing", 0)]
            side = p.get("side", "front")
            size = p.get("size", (2.4, 1.6))
            floor = p.get("floor", 0)
            props = {"opening": v2(*size), "muntins": "false"}
            if w.trim != "trim_white":
                props["frame_material"] = self.sc.mat(w.trim)
            y = FLOOR_Y + STOREY * floor + 0.9 + size[1] / 2
            self.part(house, "house_window", w, side, p["at"], y, props)
            self.reserve(p.get("wing", 0), side, floor, p["at"], size[0] / 2 + 0.2)

    def _auto_positions(self, length):
        n = int((length - 0.6) / 3.1)
        if length >= 2.4:
            n = max(n, 1)
        return [(i + 0.5) * length / n for i in range(n)] if n else []

    def windows(self, house):
        s = self.s
        size = s.get("win_size", (1.1, 1.5))
        baths_left = int(math.ceil(s["baths"]))
        for wi, w in enumerate(self.wings):
            for side in SIDES:
                rule = w.win[side]
                if rule == 0:
                    continue
                a0, a1 = w.span(side)
                for floor in range(w.floors if w.kind == "house" else 1):
                    if rule is None:
                        ats = [a0 + t for t in self._auto_positions(a1 - a0)]
                    else:
                        ats = list(rule)
                    y = FLOOR_Y + STOREY * floor + 0.9 + size[1] / 2
                    placed = []
                    for at in ats:
                        if any(abs(at - r) < h + size[0] / 2 + 0.3 for r, h in self.reserved.get((wi, side, floor), [])):
                            continue
                        blocked = False
                        for k in (-0.6, 0, 0.6):
                            px, py, pz = self.outside(w, side, at + k, y + 0.7)
                            if any(o is not w and o.contains(px, py, pz) for o in self.wings):
                                blocked = True
                        if not blocked:
                            placed.append(at)
                    is_bath_wall = side == "back" and wi == 0 and floor == w.floors - 1
                    for j, at in enumerate(placed):
                        props = {"opening": v2(*size)}
                        wy = y
                        if is_bath_wall and baths_left > 0 and j % 2 == 1 and len(placed) > 1:
                            props = {"opening": v2(0.7, 0.7), "muntins": "false"}
                            wy = FLOOR_Y + STOREY * floor + 2.0
                            baths_left -= 1
                        elif not s.get("muntins", True):
                            props["muntins"] = "false"
                        if s.get("shutters") and side == "front" and w.kind == "house":
                            props["shutters"] = "true"
                            if s.get("shutter_mat"):
                                props["shutter_material"] = self.sc.mat(s["shutter_mat"])
                        if w.trim != "trim_white":
                            props["frame_material"] = self.sc.mat(w.trim)
                        self.part(house, "house_window", w, side, at, wy, props)

    def roof_all(self, house):
        for i, w in enumerate(self.wings):
            roofs.build(self.sc, house, "Roof%d" % (i + 1), w.x0, w.x1, w.z0, w.z1, w.top, w.roof,
                        w.roof_mat, w.wall, w.trim)
        for c in self.s.get("chimneys", []):
            x, z, top = c[:3]
            box(self.sc, house, "Chimney", x - 0.45, x + 0.45, 0, top, z - 0.35, z + 0.35, c[3] if len(c) > 3 else "brick_red")
            box(self.sc, house, "ChimneyCap", x - 0.52, x + 0.52, top, top + 0.12, z - 0.42, z + 0.42, "trim_dark")

    # --- porches, stoops, carports -------------------------------------------------------
    @staticmethod
    def _edges(x0, x1, z0, z1):
        """side -> (fixed coord axis, fixed value, along-axis span)."""
        return {"front": ("z", z1, (x0, x1)), "back": ("z", z0, (x0, x1)),
                "right": ("x", x1, (z0, z1)), "left": ("x", x0, (z0, z1))}

    def _edge_box(self, parent, name, side, value, a0, a1, y0, y1, t, material, outward=0.0):
        n = SIDES[side][0]
        if side in ("front", "back"):
            z = value + n[1] * outward
            box(self.sc, parent, name, a0, a1, y0, y1, z - t / 2, z + t / 2, material)
        else:
            x = value + n[0] * outward
            box(self.sc, parent, name, x - t / 2, x + t / 2, y0, y1, a0, a1, material)

    def _steps(self, parent, side, value, at, width, top):
        n = SIDES[side][0]
        k = max(1, int(round(top / 0.18)) - 1)
        for i in range(k):
            h = top * (k - i) / (k + 1)
            d0, d1 = 0.3 * i, 0.3 * (i + 1)
            if side in ("front", "back"):
                za, zb = value + n[1] * d0, value + n[1] * d1
                box(self.sc, parent, "Step", at - width / 2, at + width / 2, 0, h, min(za, zb), max(za, zb), "concrete")
            else:
                xa, xb = value + n[0] * d0, value + n[0] * d1
                box(self.sc, parent, "Step", min(xa, xb), max(xa, xb), 0, h, at - width / 2, at + width / 2, "concrete")

    def porches(self, house):
        trim = self.s.get("trim", "trim_white")
        for pi, p in enumerate(self.s.get("porches", [])):
            x0, x1, z0, z1 = p["rect"]
            out = p.get("out", "front")
            wall_side = {"front": "back", "back": "front", "left": "right", "right": "left"}[out]
            hi, lo = p.get("hi", 3.3), p.get("lo", 3.0)
            deck = p.get("deck", "wood_deck")
            name = "Porch%d" % (pi + 1)
            box(self.sc, house, name + "Deck", x0, x1, 0, FLOOR_Y, z0, z1, deck)
            edges = self._edges(x0, x1, z0, z1)
            steps = p.get("steps", [(out, None)])
            cols = set()
            for side, (axis, value, (a0, a1)) in edges.items():
                if side == wall_side:
                    continue
                gaps = [(at if at is not None else (a0 + a1) / 2) for s_, at in steps if s_ == side]
                for at in gaps:
                    self._steps(house, side, value, at, p.get("step_w", 1.6), FLOOR_Y)
                if side == out:
                    n = max(1, int(math.ceil((a1 - a0) / 3.0)))
                    for i in range(n + 1):
                        cols.add((side, value, a0 + (a1 - a0) * i / n))
                if p.get("rail", True) and side not in p.get("open", ()):
                    segs, cur = [], a0 + 0.1
                    for at in sorted(gaps):
                        segs.append((cur, at - 0.85))
                        cur = at + 0.85
                    segs.append((cur, a1 - 0.1))
                    for s0, s1 in segs:
                        if s1 - s0 < 0.3:
                            continue
                        self._edge_box(house, name + "Rail", side, value, s0, s1, 1.28, 1.36, 0.08, trim, -0.1)
                        self._edge_box(house, name + "Rail", side, value, s0, s1, 0.5, 0.56, 0.06, trim, -0.1)
                        self._edge_box(house, name + "Balusters", side, value, s0, s1, 0.56, 1.28, 0.03, "fence_picket", -0.1)
            for side, value, at in cols:
                if side in ("front", "back"):
                    zc = value - SIDES[side][0][1] * 0.15
                    box(self.sc, house, name + "Post", at - 0.1, at + 0.1, FLOOR_Y, lo, zc - 0.1, zc + 0.1, trim)
                else:
                    xc = value - SIDES[side][0][0] * 0.15
                    box(self.sc, house, name + "Post", xc - 0.1, xc + 0.1, FLOOR_Y, lo, at - 0.1, at + 0.1, trim)
            rt = p.get("roof", "shed")
            if rt is None:
                continue
            rm = "roof_" + p.get("roof_color", self.s.get("roof", "charcoal"))
            depth = (z1 - z0) if out in ("front", "back") else (x1 - x0)
            if rt == "shed":
                r = {"t": "shed", "high": wall_side, "pitch": (hi - lo) / depth, "overhang": 0.3, "rake": 0.15, "fill": False}
                roofs.shed(self.sc, house, name + "Roof", x0, x1, z0, z1, lo, r, rm, trim)
            elif rt == "hip":
                roofs.hip(self.sc, house, name + "Roof", x0, x1, z0, z1, lo, {"pitch": 0.35, "overhang": 0.3}, rm)
            elif rt == "gable":
                axis = "z" if out in ("front", "back") else "x"
                roofs.gable(self.sc, house, name + "Roof", x0, x1, z0, z1, lo,
                            {"axis": axis, "pitch": p.get("pitch", 0.6), "overhang": 0.25, "rake": 0.2}, rm, trim)
            else:
                box(self.sc, house, name + "Roof", x0 - 0.2, x1 + 0.2, lo, lo + 0.25, z0 - 0.2 * (out == "back"),
                    z1 + 0.2 * (out == "front"), trim)
            self._edge_box(house, name + "Beam", out, edges[out][1], edges[out][2][0], edges[out][2][1],
                           lo - 0.3, lo, 0.24, trim, -0.15)

    def stoops(self, house):
        for d in self.s.get("doors", []):
            if not d.get("stoop", True):
                continue
            w = self.wings[d.get("wing", 0)]
            side = d.get("side", "front")
            at = d["at"]
            n = SIDES[side][0]
            depth, half = d.get("stoop_d", 1.3), d.get("stoop_w", 2.0) / 2
            _, value, _ = self._edges(w.x0, w.x1, w.z0, w.z1)[side]
            if side in ("front", "back"):
                za, zb = value, value + n[1] * depth
                box(self.sc, house, "Stoop", at - half, at + half, 0, FLOOR_Y, min(za, zb), max(za, zb), "concrete")
            else:
                xa, xb = value, value + n[0] * depth
                box(self.sc, house, "Stoop", min(xa, xb), max(xa, xb), 0, FLOOR_Y, at - half, at + half, "concrete")
            outer = value + (n[1] if side in ("front", "back") else n[0]) * depth
            self._steps(house, side, outer, at, half * 2 - 0.4, FLOOR_Y)
            canopy = d.get("canopy")
            if canopy:
                cy = FLOOR_Y + 2.75
                if side in ("front", "back"):
                    za, zb = value, value + n[1] * (depth - 0.1)
                    rect = (at - half, at + half, min(za, zb), max(za, zb))
                else:
                    xa, xb = value, value + n[0] * (depth - 0.1)
                    rect = (min(xa, xb), max(xa, xb), at - half, at + half)
                trim = self.s.get("trim", "trim_white")
                if canopy == "gable":
                    axis = "z" if side in ("front", "back") else "x"
                    roofs.gable(self.sc, house, "Canopy", *rect, cy, {"axis": axis, "pitch": 0.6, "overhang": 0.15, "rake": 0.1},
                                "roof_" + self.s.get("roof", "charcoal"), trim)
                else:
                    box(self.sc, house, "Canopy", rect[0], rect[1], cy, cy + 0.18, rect[2], rect[3], trim)
                    for sgn in (-1, 1):
                        if side in ("front", "back"):
                            box(self.sc, house, "Bracket", at + sgn * (half - 0.15) - 0.05, at + sgn * (half - 0.15) + 0.05,
                                cy - 0.5, cy, rect[2], rect[3], trim)

    def carports(self, house):
        for c in self.s.get("carports", []):
            x0, x1, z0, z1 = c["rect"]
            h = c.get("h", 2.8)
            mat = c.get("post_mat", "metal_dark")
            posts = c.get("posts", [(x0, z0), (x0, z1), (x1, z0), (x1, z1)])
            for px, pz in posts:
                px = min(max(px, x0 + 0.1), x1 - 0.1)
                pz = min(max(pz, z0 + 0.1), z1 - 0.1)
                box(self.sc, house, "CarportPost", px - 0.08, px + 0.08, 0, h, pz - 0.08, pz + 0.08, mat)
            box(self.sc, house, "CarportRoof", x0, x1, h, h + 0.2, z0, z1, c.get("roof_mat", "roof_metal"))
            box(self.sc, house, "CarportFascia", x0 - 0.03, x1 + 0.03, h - 0.1, h + 0.08, z0 - 0.03, z1 + 0.03, mat)

    def blocks(self, house):
        """Free-form boxes (x0, x1, y0, y1, z0, z1, material[, name]) added last to the shell:
        boarded windows, bars, skirting, exterior stairs, rooftop clutter."""
        for b in self.s.get("blocks", []):
            box(self.sc, house, b[7] if len(b) > 7 else "Block", *b[:7])

    # --- lot, fences, landscape ---------------------------------------------------------
    def lot(self, root):
        lot = combiner(self.sc, root, "Lot", collision=True)
        hw = self.lot_w / 2
        box(self.sc, lot, "Grass", -hw, hw, -0.2, 0.02, -self.lot_d, 0, "grass")
        for i, pv in enumerate(self.s.get("paving", [])):
            x0, x1, z0, z1 = pv[:4]
            m = pv[4] if len(pv) > 4 else "concrete"
            top = 0.04 if m == "gravel" else 0.05
            box(self.sc, lot, "Gravel" if m == "gravel" else "Paving", x0, x1, -0.1, top, z0, z1, m)

    def fences(self, root):
        segs = self.s.get("fences", [])
        if not segs:
            return
        fence = combiner(self.sc, root, "Fence", collision=True)
        for kind, x0, z0, x1, z1 in segs:
            along_x = abs(z1 - z0) < 1e-6
            length = abs(x1 - x0) if along_x else abs(z1 - z0)
            h, t, mat, post_mat = {
                "privacy": (1.8, 0.05, "fence_wood", "fence_wood"),
                "picket": (0.95, 0.03, "fence_picket", "trim_white"),
                "chain": (1.2, 0.02, "fence_chain", "metal_grey"),
                "hedge": (1.2, 0.8, "hedge", None),
                "wall": (0.7, 0.3, "brick_red", None),
            }[kind]
            lo_x, hi_x, lo_z, hi_z = min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1)
            if along_x:
                box(self.sc, fence, kind.title(), lo_x, hi_x, 0, h, z0 - t / 2, z0 + t / 2, mat)
            else:
                box(self.sc, fence, kind.title(), x0 - t / 2, x0 + t / 2, 0, h, lo_z, hi_z, mat)
            if not post_mat:
                continue
            n = max(1, int(math.ceil(length / 2.4)))
            ps = 0.06 if kind == "chain" else 0.1
            for i in range(n + 1):
                k = i / n
                px, pz = x0 + (x1 - x0) * k, z0 + (z1 - z0) * k
                box(self.sc, fence, "Post", px - ps, px + ps, 0, h + 0.05, pz - ps, pz + ps, post_mat)
            if kind == "chain":
                if along_x:
                    box(self.sc, fence, "TopRail", lo_x, hi_x, h - 0.04, h, z0 - 0.03, z0 + 0.03, post_mat)
                else:
                    box(self.sc, fence, "TopRail", x0 - 0.03, x0 + 0.03, h - 0.04, h, lo_z, hi_z, post_mat)

    def landscape(self, root):
        s = self.s
        if not any(s.get(k) for k in ("trees", "shrubs", "hedges", "mailbox", "ac")):
            return
        land = combiner(self.sc, root, "Landscape", collision=True)
        for t in s.get("trees", []):
            x, z = t[:2]
            k = t[2] if len(t) > 2 else 1.0
            self.sc.node("Trunk", "CSGCylinder3D", land, {
                "transform": xform((x, 1.4 * k, z)), "radius": f(0.2 * k), "height": f(2.8 * k),
                "sides": "8", "material": self.sc.mat("bark")})
            for j, (dx, dy, dz, r) in enumerate(((0, 3.6, 0, 2.0), (0.8, 3.0, 0.5, 1.4), (-0.7, 3.2, -0.6, 1.5))):
                self.sc.node("Canopy", "CSGSphere3D", land, {
                    "transform": xform((x + dx * k, dy * k, z + dz * k)), "radius": f(r * k),
                    "radial_segments": "10", "rings": "6",
                    "material": self.sc.mat("foliage" if j == 0 else "foliage_dark")})
        for sh in s.get("shrubs", []):
            x, z = sh[:2]
            r = sh[2] if len(sh) > 2 else 0.6
            self.sc.node("Shrub", "CSGSphere3D", land, {
                "transform": xform((x, r * 0.55, z), 0, (1, 0.8, 1)), "radius": f(r),
                "radial_segments": "8", "rings": "5", "material": self.sc.mat("hedge")})
        for x0, x1, z0, z1 in s.get("hedges", []):
            box(self.sc, land, "Hedge", x0, x1, 0, 1.0, z0, z1, "hedge")
        if s.get("mailbox"):
            x, z = s["mailbox"]
            box(self.sc, land, "MailboxPost", x - 0.05, x + 0.05, 0, 1.0, z - 0.05, z + 0.05, "fence_wood")
            box(self.sc, land, "Mailbox", x - 0.12, x + 0.12, 1.0, 1.25, z - 0.25, z + 0.25, "metal_dark")
        if s.get("ac"):
            x, z = s["ac"]
            box(self.sc, land, "AcPad", x - 0.55, x + 0.55, 0, 0.08, z - 0.55, z + 0.55, "concrete")
            box(self.sc, land, "AcUnit", x - 0.4, x + 0.4, 0.08, 0.85, z - 0.4, z + 0.4, "ac_unit")

    # --- whole scene ---------------------------------------------------------------------
    def footprint(self):
        ws = [w for w in self.wings if not w.detached and w.kind != "shed"]
        return (max(w.x1 for w in ws) - min(w.x0 for w in ws), max(w.z1 for w in ws) - min(w.z0 for w in ws))

    def validate(self):
        hw = self.lot_w / 2
        problems = []
        rects = [(w.x0, w.x1, w.z0, w.z1) for w in self.wings]
        rects += [p["rect"] for p in self.s.get("porches", [])]
        rects += [c["rect"] for c in self.s.get("carports", [])]
        rects += [pv[:4] for pv in self.s.get("paving", [])]
        rects += [(min(a[1], a[3]), max(a[1], a[3]), min(a[2], a[4]), max(a[2], a[4])) for a in self.s.get("fences", [])]
        for x0, x1, z0, z1 in rects:
            if x0 < -hw - 1e-6 or x1 > hw + 1e-6 or z0 < -self.lot_d - 1e-6 or z1 > 1e-6:
                problems.append("outside lot: %s" % ((x0, x1, z0, z1),))
        s = self.s
        if s["floors"] == 1 and (s["beds"] > 4 or s["baths"] > 2):
            problems.append("1-floor houses are capped at 4 bed / 2 bath")
        return problems

    def build(self):
        s, sc = self.s, self.sc
        fw, fd = self.footprint()
        root = sc.node("House" + s["id"].replace("-", ""), "Node3D", None, {
            "script": sc.res(ROOT_SCRIPT, "Script"),
            "house_id": '"%s"' % s["id"], "display_name": '"%s"' % s["name"],
            "floors": str(s["floors"]), "bedrooms": str(s["beds"]), "bathrooms": f(s["baths"]),
            "footprint": v2(fw, fd), "lot_size": v2(self.lot_w, self.lot_d),
            "lot_type": '"%s"' % s["lot_type"], "archetype": '"%s"' % s.get("archetype", "")})
        self.lot(root)
        house = combiner(sc, root, "House", collision=True)
        self.walls(house)
        self.doors(house)
        self.windows(house)
        self.roof_all(house)
        self.porches(house)
        self.stoops(house)
        self.carports(house)
        self.blocks(house)
        self.fences(root)
        self.landscape(root)
        return sc
