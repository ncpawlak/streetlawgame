"""Stand-in business builder: commercial shells (flat roofs with parapets, glass storefronts,
awnings, sign bands, roll-up grates, parking lots). Closed stand-ins are solid; enterable shops
get a real doorway into an empty interior, an Entrance marker and a ShopCounter Interactable.

Spec keys (all coordinates in lot space: origin = front property line centre, street at +Z):
  body=(x0, x1, z0, z1), height (top of wall), parapet, roof "flat" | "gable" (+ pitch),
  wall, coping, fronts / doors / bays / upper / awnings / signs (each has a `side` of
  front|back|left|right and `a0`/`a1` or `at` measured along that face in lot x (front/back)
  or lot z (left/right)), paving, stalls, fences, trees, shrubs, hedges, lamps, dumpsters,
  pylon, pole (barber pole), cars.
"""
from builder import HouseBuilder
from dressmeta import DressMeta
from roofs import gable
from tscn import SUBTRACT, Scene, box, combiner, f, prism, v2, v3, xform

ROOT_SCRIPT = "res://scripts/world/houses/business_exterior.gd"
WALL_T = 0.3
FLOOR_Y = 0.1
SIDE_YAW = {"front": 0, "back": 180, "right": 90, "left": -90}


class BusinessBuilder:
    def __init__(self, spec):
        self.s = spec
        self.sc = Scene()
        self.lot_w, self.lot_d = spec["lot"]
        self.x0, self.x1, self.z0, self.z1 = spec["body"]
        self.h = spec["height"]
        # Face items (fronts, doors, upper, signs, awnings, extras) address the main body or,
        # with "mass": i, the i-th entry of spec["masses"] (1-based).
        self.rects = [spec["body"]] + [m["rect"] for m in spec.get("masses", [])]
        self.cur = self.rects[0]
        self.meta = DressMeta(spec.get("dress_tier", "commercial"))

    def on(self, item):
        self.cur = self.rects[item.get("mass", 0)]
        return item

    # --- face-relative geometry ----------------------------------------------------------
    def plane(self, side):
        x0, x1, z0, z1 = self.cur
        return {"front": z1, "back": z0, "right": x1, "left": x0}[side]

    def sbox(self, parent, name, side, a0, a1, y0, y1, d0, d1, material, op=None):
        """Box on a face: [a0, a1] along the face, [d0, d1] along its outward normal from the wall plane."""
        p = self.plane(side)
        if side == "front":
            return box(self.sc, parent, name, a0, a1, y0, y1, p + d0, p + d1, material, op)
        if side == "back":
            return box(self.sc, parent, name, a0, a1, y0, y1, p - d1, p - d0, material, op)
        if side == "right":
            return box(self.sc, parent, name, p + d0, p + d1, y0, y1, a0, a1, material, op)
        return box(self.sc, parent, name, p - d1, p - d0, y0, y1, a0, a1, material, op)

    def face_point(self, side, a, y, d):
        p = self.plane(side)
        return {"front": (a, y, p + d), "back": (a, y, p - d),
                "right": (p + d, y, a), "left": (p - d, y, a)}[side]

    def note(self, side, a0, a1, y0, y1, kind):
        """Records a facade opening / feature on the current mass for the dressing metadata."""
        self.meta.opening(self.face_point(side, (a0 + a1) / 2, (y0 + y1) / 2, 0), side, a1 - a0, y1 - y0, kind)

    def sprism(self, parent, name, side, a0, a1, pts, material):
        """Extrudes (d, y) profile `pts` (d = outward distance from the face) along the face."""
        p = self.plane(side)
        if side in ("front", "right"):
            uv = [(p + d, y) for d, y in pts]
        else:
            uv = [(p - d, y) for d, y in reversed(pts)]
        axis = "x" if side in ("front", "back") else "z"
        return prism(self.sc, parent, name, uv, axis, a0, a1, 0, material)

    # --- shell ---------------------------------------------------------------------------
    def shell(self, b):
        s = self.s
        x0, x1, z0, z1, h = self.x0, self.x1, self.z0, self.z1, self.h
        wall = s["wall"]
        para = s.get("parapet", 0.0) if s.get("roof", "flat") == "flat" else 0.0
        box(self.sc, b, "Body", x0, x1, 0, h + para, z0, z1, wall)
        if s.get("base"):
            box(self.sc, b, "Base", x0 - 0.04, x1 + 0.04, 0, 0.5, z0 - 0.04, z1 + 0.04, s["base"])
        for band in s.get("bands", []):
            y0, y1, m = band
            box(self.sc, b, "Band", x0 - 0.03, x1 + 0.03, y0, y1, z0 - 0.03, z1 + 0.03, m)
        if s.get("roof", "flat") == "flat":
            t = WALL_T
            box(self.sc, b, "RoofWell", x0 + t, x1 - t, h, h + para + 1, z0 + t, z1 - t, "roof_flat", SUBTRACT)
            cm = s.get("coping", "metal_dark")
            top = h + para
            for name, (a, bb, c, d) in (("CopingF", (x0 - 0.06, x1 + 0.06, z1 - t, z1 + 0.06)),
                                        ("CopingB", (x0 - 0.06, x1 + 0.06, z0 - 0.06, z0 + t)),
                                        ("CopingL", (x0 - 0.06, x0 + t, z0, z1)),
                                        ("CopingR", (x1 - t, x1 + 0.06, z0, z1))):
                box(self.sc, b, name, a, bb, top, top + 0.12, c, d, cm)
            for i, (rx, rz) in enumerate(s.get("rtu", [])):
                box(self.sc, b, "RooftopUnit", rx - 0.9, rx + 0.9, h, h + 1.2, rz - 0.7, rz + 0.7, "ac_unit")
        else:
            gable(self.sc, b, "Roof", x0, x1, z0, z1, h, {"axis": s.get("ridge", "x"), "pitch": s.get("pitch", 0.15),
                                                          "overhang": 0.35, "rake": 0.25},
                  s.get("roof_mat", "metal_roof"), wall)
        for m in s.get("masses", []):
            self.mass(b, m)

    def mass(self, b, m):
        """Extra flat-roofed (or gabled) block: wings, towers on a podium, annexes."""
        x0, x1, z0, z1 = m["rect"]
        y0, h, para = m.get("y0", 0.0), m["height"], m.get("parapet", 0.0)
        wall = m.get("wall", self.s["wall"])
        if m.get("roof", "flat") != "flat":
            box(self.sc, b, "Mass", x0, x1, y0, h, z0, z1, wall)
            gable(self.sc, b, "MassRoof", x0, x1, z0, z1, h, {"axis": m.get("ridge", "x"), "pitch": m.get("pitch", 0.2),
                                                              "overhang": 0.3, "rake": 0.2},
                  m.get("roof_mat", "metal_roof"), wall)
            return
        box(self.sc, b, "Mass", x0, x1, y0, h + para, z0, z1, wall)
        for y_0, y_1, mat in m.get("bands", []):
            box(self.sc, b, "MassBand", x0 - 0.03, x1 + 0.03, y_0, y_1, z0 - 0.03, z1 + 0.03, mat)
        if para > 0:
            t = WALL_T
            box(self.sc, b, "MassRoofWell", x0 + t, x1 - t, h, h + para + 1, z0 + t, z1 - t, "roof_flat", SUBTRACT)
        top = h + para
        box(self.sc, b, "MassCoping", x0 - 0.06, x1 + 0.06, top, top + 0.12, z0 - 0.06, z1 + 0.06,
            m.get("coping", self.s.get("coping", "metal_dark")))
        if para > 0:
            box(self.sc, b, "MassCopingCut", x0 + WALL_T, x1 - WALL_T, top - 0.01, top + 0.2, z0 + WALL_T, z1 - WALL_T,
                None, SUBTRACT)

    def interior(self, b):
        if not self.s.get("enterable"):
            return
        t = WALL_T
        ih = self.s.get("interior_h", min(self.h - 0.4, 3.6))
        box(self.sc, b, "Interior", self.x0 + t, self.x1 - t, FLOOR_Y, ih, self.z0 + t, self.z1 - t,
            "interior_wall", SUBTRACT)
        box(self.sc, b, "Floor", self.x0 + t, self.x1 - t, 0, FLOOR_Y + 0.02, self.z0 + t, self.z1 - t,
            "interior_floor")

    def counter(self, b, root):
        if not self.s.get("enterable"):
            return
        c = self.s.get("counter")
        cx = (self.x0 + self.x1) / 2 if c is None else c[0]
        cz = self.z0 + WALL_T + 2.2 if c is None else c[1]
        cw = min(4.0, self.x1 - self.x0 - 2.0) if c is None else c[2]
        box(self.sc, b, "Counter", cx - cw / 2, cx + cw / 2, 0, 1.0, cz - 0.35, cz + 0.35, "trim_dark")
        box(self.sc, b, "CounterTop", cx - cw / 2 - 0.05, cx + cw / 2 + 0.05, 1.0, 1.06, cz - 0.4, cz + 0.4,
            self.s.get("counter_top", "metal_grey"))
        self.sc.node("ShopCounter", "Area3D", ".", {
            "transform": xform((cx, 1.0, cz + 1.2)),
            "script": self.sc.res("res://scripts/framework/interaction/interactable.gd", "Script"),
            "prompt_name": '"%s"' % self.s["name"], "radius": "2.5"})
        ix = (self.x0 + self.x1) / 2
        iz = (self.z0 + self.z1) / 2
        self.sc.node("InteriorLight", "OmniLight3D", ".", {
            "transform": xform((ix, self.s.get("interior_h", 3.4) - 0.6, iz)),
            "light_color": "Color(1, 0.95, 0.85, 1)", "light_energy": "1.2",
            "omni_range": f(max(self.x1 - self.x0, self.z1 - self.z0) * 0.8)})


    # --- facade --------------------------------------------------------------------------
    def fronts(self, b):
        lit = "glass_lit" if self.s.get("enterable") else "glass"
        for fr in map(self.on, self.s.get("fronts", [])):
            side, a0, a1 = fr["side"], fr["a0"], fr["a1"]
            sill, top = fr.get("sill", 0.5), fr.get("top", 3.0)
            kind = fr.get("kind", "glass")
            self.note(side, a0, a1, sill, top + 0.5, 2)
            self.sbox(b, "Storefront", side, a0, a1, sill, top, -0.16, 0.05, fr.get("glass", lit), SUBTRACT)
            frame = fr.get("frame", "metal_dark")
            self.sbox(b, "Sill", side, a0 - 0.05, a1 + 0.05, sill - 0.06, sill, -0.16, 0.06, frame)
            self.sbox(b, "Head", side, a0 - 0.05, a1 + 0.05, top, top + 0.08, -0.16, 0.06, frame)
            n = max(1, round((a1 - a0) / fr.get("mull", 1.6)))
            for i in range(1, n):
                a = a0 + (a1 - a0) * i / n
                self.sbox(b, "Mullion", side, a - 0.04, a + 0.04, sill, top, -0.16, -0.06, frame)
            if fr.get("transom"):
                self.sbox(b, "Transom", side, a0, a1, top - 0.6, top - 0.54, -0.16, -0.06, frame)
            if kind == "grate":
                self.sbox(b, "Grate", side, a0 - 0.1, a1 + 0.1, 0.05, top + 0.1, 0.02, 0.08, "grate")
            elif kind == "boarded":
                self.sbox(b, "Boards", side, a0, a1, sill, top, -0.1, -0.02, "plywood")
            elif kind == "barred":
                for k in range(int((a1 - a0) / 0.18)):
                    a = a0 + 0.09 + k * 0.18
                    self.sbox(b, "Bar", side, a - 0.015, a + 0.015, sill, top, 0.0, 0.03, "metal_dark")
            if kind == "grate" or fr.get("housing"):
                self.sbox(b, "GrateBox", side, a0 - 0.15, a1 + 0.15, top + 0.1, top + 0.5, 0, 0.3, "metal_dark")

    def doors(self, b, root):
        entrance = None
        for dr in map(self.on, self.s.get("doors", []) + [dict(bay=True, **x) for x in self.s.get("bays", [])]):
            side, at = dr["side"], dr["at"]
            bay = dr.get("bay", False)
            w, h = dr.get("w", 3.6 if bay else 1.8), dr.get("h", 4.0 if bay else 2.6)
            a0, a1 = at - w / 2, at + w / 2
            frame = "metal_dark"
            self.note(side, a0, a1, 0.0, h + 0.5, 1)
            if dr.get("open"):
                self.sbox(b, "Doorway", side, a0, a1, FLOOR_Y + 0.02, h, -WALL_T - 0.1, 0.1, "interior_wall", SUBTRACT)
                if entrance is None:
                    entrance = (side, at, self.cur)
                if bay:
                    self.sbox(b, "BayRolled", side, a0 - 0.1, a1 + 0.1, h, h + 0.5, -0.15, 0.25, "grate")
            else:
                mat = "grate" if bay else ("glass" if dr.get("kind", "glass") == "glass" else "metal_grey")
                self.sbox(b, "Door", side, a0, a1, dr.get("y0", 0.02), h, -0.1, 0.05, mat, SUBTRACT)
                if not bay and dr.get("kind", "glass") == "glass":
                    self.sbox(b, "DoorMeet", side, at - 0.03, at + 0.03, 0.02, h, -0.1, -0.04, frame)
                    self.sbox(b, "DoorRail", side, a0, a1, 0.02, 0.25, -0.1, -0.04, frame)
                if bay:
                    self.sbox(b, "BayBox", side, a0 - 0.1, a1 + 0.1, h, h + 0.4, 0, 0.25, frame)
            y0 = dr.get("y0", 0.02)
            for name, (c0, c1, y0, y1) in (("JambL", (a0 - 0.1, a0, y0, h)), ("JambR", (a1, a1 + 0.1, y0, h)),
                                           ("DoorHead", (a0 - 0.1, a1 + 0.1, h, h + 0.1))):
                self.sbox(b, name, side, c0, c1, y0, y1, -0.02, 0.06, frame)
            if bay and dr.get("bollards", True):
                for a in (a0 - 0.35, a1 + 0.35):
                    x, _, z = self.face_point(side, a, 0, 0.3)
                    self.sc.node("Bollard", "CSGCylinder3D", b, {
                        "transform": xform((x, 0.5, z)), "radius": "0.12", "height": "1", "sides": "8",
                        "material": self.sc.mat("paint_yellow")})
        if entrance:
            side, at, rect = entrance
            self.cur = rect
            self.sc.node("Entrance", "Marker3D", ".", {
                "transform": xform(self.face_point(side, at, 0.1, 1.2), SIDE_YAW[side])})
        return entrance

    def upper(self, b):
        for row in map(self.on, self.s.get("upper", [])):
            side, y0, wh, ww = row["side"], row["y0"], row.get("h", 1.5), row.get("w", 1.2)
            for a in row["at"]:
                self.note(side, a - ww / 2, a + ww / 2, y0, y0 + wh, 0)
                self.sbox(b, "Window", side, a - ww / 2, a + ww / 2, y0, y0 + wh, -0.14, 0.05, "glass", SUBTRACT)
                self.sbox(b, "WinSill", side, a - ww / 2 - 0.08, a + ww / 2 + 0.08, y0 - 0.08, y0, -0.1, 0.1,
                          row.get("trim", "trim_cream"))
                self.sbox(b, "WinHead", side, a - ww / 2 - 0.08, a + ww / 2 + 0.08, y0 + wh, y0 + wh + 0.15,
                          -0.1, 0.06, row.get("trim", "trim_cream"))
                self.sbox(b, "WinBar", side, a - ww / 2, a + ww / 2, y0 + wh * 0.55, y0 + wh * 0.55 + 0.05,
                          -0.14, -0.08, "trim_white")

    def awnings(self, b):
        for aw in map(self.on, self.s.get("awnings", [])):
            side, a0, a1, y, d = aw["side"], aw["a0"], aw["a1"], aw.get("y", 3.2), aw.get("d", 1.3)
            self.note(side, a0, a1, y - 0.3, y + 0.7, 4)
            if aw.get("style", "slope") == "slope":
                pts = [(0, y + 0.7), (d, y), (d, y - 0.3), (d - 0.05, y - 0.3), (0, y + 0.6)]
            else:
                pts = [(0, y + 0.45), (d, y + 0.45), (d, y - 0.05), (0, y - 0.05)]
            self.sprism(b, "Awning", side, a0, a1, pts, aw["mat"])

    def signs(self, b):
        for sg in map(self.on, self.s.get("signs", [])):
            side, a0, a1, y0, y1 = sg["side"], sg["a0"], sg["a1"], sg["y0"], sg["y1"]
            d = sg.get("d", 0.15)
            self.note(side, a0, a1, y0, y1, 4)
            self.sbox(b, "SignBand", side, a0, a1, y0, y1, 0, d, sg["mat"])
            self.label(sg["text"], self.face_point(side, (a0 + a1) / 2, (y0 + y1) / 2, d + 0.02),
                       SIDE_YAW[side], a1 - a0, y1 - y0, sg.get("color", "white"))

    def label(self, text, pos, yaw, width, height, color):
        colors = {"white": "Color(1, 1, 0.97, 1)", "black": "Color(0.05, 0.05, 0.05, 1)",
                  "yellow": "Color(1, 0.85, 0.2, 1)", "red": "Color(0.9, 0.12, 0.1, 1)"}
        px = min(height * 0.62 / 96, width * 0.88 / (max(1, len(text)) * 0.62 * 96))
        self.sc.node("SignText", "Label3D", ".", {
            "transform": xform(pos, yaw), "pixel_size": "%.5f" % px, "text": '"%s"' % text,
            "font_size": "96", "outline_size": "6", "modulate": colors.get(color, color),
            "outline_modulate": "Color(0, 0, 0, 0.6)", "shaded": "false"})

    def posts(self, b):
        for x, z, h in self.s.get("posts", []):
            box(self.sc, b, "Post", x - 0.15, x + 0.15, 0, h, z - 0.15, z + 0.15, self.s.get("post_mat", "metal_dark"))

    def pole(self, b):
        p = self.s.get("pole")
        if not p:
            return
        side, at, y = p
        self.cur = self.rects[0]
        x, _, z = self.face_point(side, at, 0, 0.25)
        box(self.sc, b, "PoleBracket", x - 0.05, x + 0.05, y - 0.05, y + 1.25, z - 0.05, z + 0.05, "metal_grey")
        for i, m in enumerate(["awning_red", "awning_white", "awning_blue", "awning_white", "awning_red"]):
            self.sc.node("PoleStripe", "CSGCylinder3D", b, {
                "transform": xform((x, y + 0.1 + i * 0.2 + 0.1, z)), "radius": "0.11", "height": "0.2",
                "sides": "12", "material": self.sc.mat(m)})


    def canopies(self, b):
        """Free-standing flat canopies on columns (gas station, bank drive-thru, hospital drop-off)
        with an optional fascia band and sign text on its street face."""
        for cp in self.s.get("canopies", []):
            x0, x1, z0, z1 = cp["rect"]
            y, t = cp.get("y", 4.8), cp.get("t", 0.7)
            fascia = cp.get("fascia", "sign_white")
            box(self.sc, b, "Canopy", x0, x1, y, y + t, z0, z1, fascia)
            box(self.sc, b, "CanopySoffit", x0 + 0.1, x1 - 0.1, y - 0.05, y, z0 + 0.1, z1 - 0.1, cp.get("soffit", "paint_white"))
            if cp.get("stripe"):
                box(self.sc, b, "CanopyStripe", x0 - 0.03, x1 + 0.03, y + t * 0.3, y + t * 0.55, z0 - 0.03, z1 + 0.03,
                    cp["stripe"])
            for cx, cz in cp.get("cols", []):
                box(self.sc, b, "CanopyColumn", cx - 0.25, cx + 0.25, 0, y, cz - 0.25, cz + 0.25,
                    cp.get("col_mat", "paint_white"))
            if cp.get("text"):
                self.label(cp["text"], ((x0 + x1) / 2, y + t / 2, z1 + 0.02), 0, min(x1 - x0, 14), t,
                           cp.get("color", "red"))

    def pumps(self, b):
        """Fuel islands: (x, z) centre, island runs along z with two dispensers and bollards."""
        for x, z in self.s.get("pumps", []):
            box(self.sc, b, "Island", x - 0.6, x + 0.6, 0, 0.18, z - 2.6, z + 2.6, "concrete")
            for dz in (-1.2, 1.2):
                box(self.sc, b, "Pump", x - 0.35, x + 0.35, 0.18, 1.9, z + dz - 0.45, z + dz + 0.45, "sign_red")
                box(self.sc, b, "PumpFace", x - 0.37, x + 0.37, 1.2, 1.7, z + dz - 0.3, z + dz + 0.3, "metal_dark")
                box(self.sc, b, "PumpTop", x - 0.4, x + 0.4, 1.9, 2.2, z + dz - 0.5, z + dz + 0.5, "sign_white")
            for dz in (-2.4, 2.4):
                self.sc.node("Bollard", "CSGCylinder3D", b, {
                    "transform": xform((x, 0.6, z + dz)), "radius": "0.12", "height": "1.2", "sides": "8",
                    "material": self.sc.mat("paint_yellow")})

    def columns(self, b):
        for c in self.s.get("columns", []):
            x, z, h = c[:3]
            r = c[3] if len(c) > 3 else 0.35
            m = c[4] if len(c) > 4 else "paint_white"
            box(self.sc, b, "ColumnBase", x - r - 0.1, x + r + 0.1, 0, 0.3, z - r - 0.1, z + r + 0.1, m)
            self.sc.node("Column", "CSGCylinder3D", b, {
                "transform": xform((x, h / 2, z)), "radius": f(r), "height": f(h), "sides": "16",
                "material": self.sc.mat(m)})
            box(self.sc, b, "ColumnCap", x - r - 0.1, x + r + 0.1, h - 0.3, h, z - r - 0.1, z + r + 0.1, m)

    def extras(self, b):
        """Face-relative boxes: balconies, pilasters, murals, ATMs, cameras, vents, walkways."""
        for e in map(self.on, self.s.get("extras", [])):
            self.note(e["side"], e["a0"], e["a1"], e["y0"], e["y1"], 4)
            self.sbox(b, e.get("name", "Extra"), e["side"], e["a0"], e["a1"], e["y0"], e["y1"], e.get("d0", 0),
                      e.get("d1", 0.1), e.get("mat"), SUBTRACT if e.get("cut") else None)
        self.cur = self.rects[0]

    def blocks(self, b):
        """Free-form boxes in lot space: (x0, x1, y0, y1, z0, z1, material[, name])."""
        for k in self.s.get("blocks", []):
            box(self.sc, b, k[7] if len(k) > 7 else "Block", *k[:7])

    # --- site ----------------------------------------------------------------------------
    def site(self, root):
        HouseBuilder.lot(self, root)
        for st in self.s.get("stalls", []):
            w = st.get("w", 2.7)
            m = st.get("mat", "paint_white")
            for i in range(st["n"] + 1):
                c = st["a0"] + i * w
                if st.get("axis", "x") == "x":
                    box(self.sc, "Lot", "Stripe", c - 0.06, c + 0.06, 0.0, 0.058, st["b0"], st["b1"], m)
                else:
                    box(self.sc, "Lot", "Stripe", st["b0"], st["b1"], 0.0, 0.058, c - 0.06, c + 0.06, m)
        HouseBuilder.fences(self, root)
        HouseBuilder.landscape(self, root)
        if not any(self.s.get(k) for k in ("lamps", "dumpsters", "pylon")):
            return
        site = combiner(self.sc, root, "Site", collision=True)
        for x, z in self.s.get("lamps", []):
            box(self.sc, site, "LampBase", x - 0.25, x + 0.25, 0, 0.5, z - 0.25, z + 0.25, "concrete")
            box(self.sc, site, "LampPole", x - 0.08, x + 0.08, 0.5, 7.0, z - 0.08, z + 0.08, "metal_dark")
            box(self.sc, site, "LampHead", x - 0.3, x + 0.3, 6.8, 7.0, z - 0.6, z + 0.6, "metal_dark")
            box(self.sc, site, "LampLens", x - 0.25, x + 0.25, 6.78, 6.8, z - 0.5, z + 0.5, "sign_white")
        for x, z in self.s.get("dumpsters", []):
            box(self.sc, site, "Dumpster", x - 0.95, x + 0.95, 0.1, 1.3, z - 0.65, z + 0.65, "awning_green")
            box(self.sc, site, "DumpsterLid", x - 1.0, x + 1.0, 1.3, 1.38, z - 0.7, z + 0.7, "metal_dark")
        py = self.s.get("pylon")
        if py:
            x, z, ph, pw = py["x"], py["z"], py.get("h", 6.0), py.get("w", 3.0)
            for dx in (-pw / 2 + 0.2, pw / 2 - 0.2):
                box(self.sc, site, "PylonPost", x + dx - 0.12, x + dx + 0.12, 0, ph - 1.6, z - 0.12, z + 0.12, "metal_dark")
            box(self.sc, site, "PylonSign", x - pw / 2, x + pw / 2, ph - 1.6, ph, z - 0.2, z + 0.2, py["mat"])
            box(self.sc, site, "PylonCap", x - pw / 2 - 0.08, x + pw / 2 + 0.08, ph, ph + 0.12, z - 0.25, z + 0.25,
                "metal_dark")
            for yaw, dz in ((0, 0.22), (180, -0.22)):
                self.label(py["text"], (x, ph - 0.8, z + dz), yaw, pw, 1.6, py.get("color", "white"))

    # --- whole scene ---------------------------------------------------------------------
    def validate(self):
        s, hw = self.s, self.lot_w / 2
        problems = []
        rects = list(self.rects) + [pv[:4] for pv in s.get("paving", [])]
        rects += [c["rect"] for c in s.get("canopies", [])]
        rects += [(k[0], k[1], k[4], k[5]) for k in s.get("blocks", [])]
        rects += [(min(a[1], a[3]), max(a[1], a[3]), min(a[2], a[4]), max(a[2], a[4])) for a in s.get("fences", [])]
        for x0, x1, z0, z1 in rects:
            if x0 < -hw - 1e-6 or x1 > hw + 1e-6 or z0 < -self.lot_d - 1e-6 or z1 > 1e-6:
                problems.append("outside lot: %s" % ((x0, x1, z0, z1),))
        openings = [d for d in s.get("doors", []) + s.get("bays", []) if d.get("open")]
        if s.get("enterable") and not openings:
            problems.append("enterable shop has no open doorway")
        if not s.get("enterable") and openings:
            problems.append("closed stand-in has an open doorway")
        for d in s.get("doors", []):
            if d.get("w", 1.8) < 1.2 or d.get("h", 2.6) < 2.4:
                problems.append("door smaller than 1.2 x 2.4 m: %s" % d)
        return problems

    def footprint(self):
        if self.s.get("footprint"):
            return self.s["footprint"]
        return (max(r[1] for r in self.rects) - min(r[0] for r in self.rects),
                max(r[3] for r in self.rects) - min(r[2] for r in self.rects))

    def build(self):
        s, sc = self.s, self.sc
        root = sc.node("Business" + s["id"].replace("-", ""), "Node3D", None, {
            "script": sc.res(ROOT_SCRIPT, "Script"),
            "business_id": '"%s"' % s["id"], "display_name": '"%s"' % s["name"],
            "archetype": '"%s"' % s["archetype"], "shop_type": '"%s"' % s.get("shop_type", ""),
            "enterable": "true" if s.get("enterable") else "false", "floors": str(s.get("floors", 1)),
            "footprint": v2(*self.footprint()), "lot_size": v2(self.lot_w, self.lot_d),
            "lot_type": '"%s"' % s["lot_type"]})
        self.site(root)
        b = combiner(sc, root, "Building", collision=True)
        self.shell(b)
        self.interior(b)
        self.fronts(b)
        self.doors(b, root)
        self.upper(b)
        self.awnings(b)
        self.signs(b)
        self.posts(b)
        self.pole(b)
        self.extras(b)
        self.canopies(b)
        self.pumps(b)
        self.columns(b)
        self.blocks(b)
        self.counter(b, root)
        tops = [self.h + (s.get("parapet", 0.0) if s.get("roof", "flat") == "flat" else 0.0)]
        tops += [m["height"] + m.get("parapet", 0.0) for m in s.get("masses", [])]
        ground = [m.get("y0", 0.0) < 1.0 for m in s.get("masses", [])]
        for r, top, walls in zip(self.rects, tops, [True] + ground):
            self.meta.solid(r[0], r[1], r[2], r[3], top, walls=walls)
        self.meta.site(s)
        sc.nodes[0][1].update(self.meta.props())
        return sc
