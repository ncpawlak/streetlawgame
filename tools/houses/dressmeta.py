"""Lot / facade metadata that KitDressing (scripts/world/houses/kit_dressing.gd) reads from a kit
building's root to place seeded West Palm Beach dressing without hitting the building.

All coordinates are lot space (origin = front property line centre, street at +Z):
  dress_tier      String       low / medium / high / commercial / civic
  dress_solids    Vector4[]    building masses (x0, z0, x1, z1)
  dress_blocked   Vector4[]    porches, carports, fences, canopies, existing landscaping, door approaches
  dress_paved     Vector4[]    driveways, walks, parking
  dress_walls     float[] x8   x0, z0, x1, z1, nx, nz, top, front (1 = street face)
  dress_openings  float[] x8   x, y (centre), z, nx, nz, w, h, kind (0 window, 1 door, 2 shopfront,
                               3 window that already has bars / storm protection, 4 sign / awning /
                               facade feature: wall props avoid all of them)
"""
from tscn import f

NORMALS = {"front": (0, 1), "back": (0, -1), "right": (1, 0), "left": (-1, 0)}


class DressMeta:
    def __init__(self, tier):
        self.tier = tier
        self.solids, self.blocked, self.paved = [], [], []
        self.walls, self.openings = [], []

    @staticmethod
    def _rect(x0, x1, z0, z1, pad=0.0):
        return (min(x0, x1) - pad, min(z0, z1) - pad, max(x0, x1) + pad, max(z0, z1) + pad)

    def solid(self, x0, x1, z0, z1, top, front_sides=("front",), walls=True):
        self.solids.append(self._rect(x0, x1, z0, z1))
        if not walls:
            return
        for side, (nx, nz) in NORMALS.items():
            if side == "front":
                seg = (x0, z1, x1, z1)
            elif side == "back":
                seg = (x0, z0, x1, z0)
            elif side == "right":
                seg = (x1, z0, x1, z1)
            else:
                seg = (x0, z0, x0, z1)
            self.walls.append(seg + (nx, nz, top, 1 if side in front_sides else 0))

    def block(self, x0, x1, z0, z1, pad=0.0):
        self.blocked.append(self._rect(x0, x1, z0, z1, pad))

    def circle(self, x, z, r):
        self.blocked.append((x - r, z - r, x + r, z + r))

    def pave(self, x0, x1, z0, z1):
        self.paved.append(self._rect(x0, x1, z0, z1))

    def site(self, s):
        """Spec-level lot items shared by HouseBuilder and BusinessBuilder."""
        for pv in s.get("paving", []):
            self.pave(*pv[:4])
        for _, x0, z0, x1, z1 in s.get("fences", []):
            self.block(x0, x1, z0, z1, pad=0.45)
        for t in s.get("trees", []):
            self.circle(t[0], t[1], 2.2 * (t[2] if len(t) > 2 else 1.0))
        for sh in s.get("shrubs", []):
            self.circle(sh[0], sh[1], (sh[2] if len(sh) > 2 else 0.6) + 0.2)
        for x0, x1, z0, z1 in s.get("hedges", []):
            self.block(x0, x1, z0, z1, pad=0.2)
        for key, r in (("mailbox", 0.5), ("ac", 0.8)):
            if s.get(key):
                self.circle(s[key][0], s[key][1], r)
        for k in s.get("blocks", []):
            if k[2] < 2.0:
                self.block(k[0], k[1], k[4], k[5], pad=0.2)
        for cp in s.get("canopies", []):
            self.block(*cp["rect"], pad=0.3)
        for x, z in s.get("pumps", []):
            self.block(x - 0.8, x + 0.8, z - 2.9, z + 2.9)
        for c in s.get("columns", []):
            self.circle(c[0], c[1], (c[3] if len(c) > 3 else 0.35) + 0.3)
        for x, z, _ in s.get("posts", []):
            self.circle(x, z, 0.4)
        for x, z in s.get("lamps", []):
            self.circle(x, z, 0.5)
        for x, z in s.get("dumpsters", []):
            self.block(x - 1.2, x + 1.2, z - 0.9, z + 0.9)
        if s.get("pylon"):
            py = s["pylon"]
            self.block(py["x"] - py.get("w", 3.0) / 2, py["x"] + py.get("w", 3.0) / 2, py["z"] - 0.5, py["z"] + 0.5,
                       pad=0.3)

    def opening(self, pos, side, w, h, kind):
        nx, nz = NORMALS[side]
        self.openings.append((pos[0], pos[1], pos[2], nx, nz, w, h, kind))
        if kind in (1, 2):  # keep the approach to doors and shopfronts clear
            x, _, z = pos
            if nz:
                self.block(x - w / 2 - 0.4, x + w / 2 + 0.4, z, z + nz * 2.2)
            else:
                self.block(x, x + nx * 2.2, z - w / 2 - 0.4, z + w / 2 + 0.4)

    def props(self):
        def v4s(rs):
            return "PackedVector4Array(%s)" % ", ".join(", ".join(f(v) for v in r) for r in rs)

        def fl(rows):
            return "PackedFloat32Array(%s)" % ", ".join(f(v) for r in rows for v in r)

        return {"metadata/dress_tier": '"%s"' % self.tier, "metadata/dress_solids": v4s(self.solids),
                "metadata/dress_blocked": v4s(self.blocked), "metadata/dress_paved": v4s(self.paved),
                "metadata/dress_walls": fl(self.walls), "metadata/dress_openings": fl(self.openings)}
