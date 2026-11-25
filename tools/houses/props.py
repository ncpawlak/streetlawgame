"""West Palm Beach landscaping / yard / street props for the building kit.

Writes low-poly prop scenes to scenes/props/<category>/<id>.tscn (primitive MeshInstance3D parts
with shared sub-resource meshes, so KitDressing can batch them into MultiMeshes) and the seeded
dressing rules to data/buildings/kit_dressing.json.

Collision rule: trunks, poles, fences / walls, pools, bins, benches and other solid street
furniture get a StaticBody3D; brush, flowers, ground patches, wall decals and other small wall
clutter get none. Props are origin-at-ground (y = 0 is the surface they stand on); wall props
(mount "wall" / "window") have their origin on the wall face with local +Z pointing out of it.
"""
import json
import math
import os
import random

from tscn import Scene, f, v3

ROOT_SCRIPT = "res://scripts/world/houses/kit_prop.gd"
PROP_DIR = "scenes/props"
DRESSING_JSON = "data/buildings/kit_dressing.json"


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def basis(rot=(0, 0, 0), scale=(1, 1, 1)):
    """Godot Euler (YXZ order, degrees) basis times a per-axis scale; returns rows."""
    rx, ry, rz = (math.radians(a) for a in rot)
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    mx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    my = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    mz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    m = _mul(_mul(my, mx), mz)
    return [[m[i][j] * scale[j] for j in range(3)] for i in range(3)]


def xf(pos, rot=(0, 0, 0), scale=(1, 1, 1)):
    b = basis(rot, scale)
    return "Transform3D(%s)" % ", ".join(f(v) for v in [b[0][0], b[0][1], b[0][2], b[1][0], b[1][1], b[1][2],
                                                       b[2][0], b[2][1], b[2][2]] + list(pos))


def direction(yaw, pitch):
    """Unit vector for local +Z after rot (-pitch, yaw, 0)."""
    y, p = math.radians(yaw), math.radians(pitch)
    return (math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p))


def add(a, b, k=1.0):
    return tuple(a[i] + b[i] * k for i in range(3))


class Prop:
    def __init__(self, pid, category, label, radius=1.0, mount="ground", collides=False, height=2.0):
        self.id, self.category, self.label = pid, category, label
        self.radius, self.mount, self.collides, self.height = radius, mount, collides, height
        self.parts = []  # (mesh type, mesh props, transform, material)
        self.shapes = []  # (shape type, shape props, transform)
        self.labels = []  # (text, pos, yaw)
        self.anchors = []
        self.cut = None
        self.tiers = []

    # --- mesh parts ----------------------------------------------------------------------
    def box(self, size, pos, mat, rot=(0, 0, 0)):
        self.parts.append(("BoxMesh", {"size": v3(*size)}, xf(pos, rot), mat))

    def cyl(self, r_top, r_bot, h, pos, mat, rot=(0, 0, 0), sides=8, scale=(1, 1, 1)):
        self.parts.append(("CylinderMesh", {"top_radius": f(r_top), "bottom_radius": f(r_bot), "height": f(h),
                                            "radial_segments": str(sides), "rings": "1"}, xf(pos, rot, scale), mat))

    def sphere(self, r, pos, mat, scale=(1, 1, 1), rot=(0, 0, 0), seg=8, rings=5):
        self.parts.append(("SphereMesh", {"radius": f(r), "height": f(2 * r), "radial_segments": str(seg),
                                          "rings": str(rings)}, xf(pos, rot, scale), mat))

    def seg(self, a, b, r, mat, sides=6, taper=1.0):
        """Cylinder from point a to point b (local)."""
        d = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        length = math.sqrt(sum(c * c for c in d))
        yaw = math.degrees(math.atan2(d[0], d[2]))
        pitch = math.degrees(math.asin(d[1] / length))
        # Cylinder axis is local +Y: tilt +Y onto d = rot (90 - pitch about X) after yaw.
        self.cyl(r * taper, r, length, add(a, d, 0.5), mat, (90 - pitch, yaw, 0), sides)
        return length, yaw, pitch

    def frond(self, base, yaw, pitch, length, width, mat, droop=35.0, segs=3):
        """Arching palm frond: `segs` flat boxes, each drooping a bit more."""
        p = base
        for i in range(segs):
            ang = pitch - droop * i
            l = length / segs
            w = width * (0.75, 1.0, 0.65, 0.45)[min(i, 3)]
            d = direction(yaw, ang)
            self.box((w, 0.03, l + 0.05), add(p, d, l / 2), mat, (-ang, yaw, 0))
            p = add(p, d, l)

    # --- collision -----------------------------------------------------------------------
    def col_box(self, size, pos, rot=(0, 0, 0)):
        self.shapes.append(("BoxShape3D", {"size": v3(*size)}, xf(pos, rot)))

    def col_cyl(self, r, h, pos, rot=(0, 0, 0)):
        self.shapes.append(("CylinderShape3D", {"height": f(h), "radius": f(r)}, xf(pos, rot)))

    def col_seg(self, a, b, r):
        d = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        length = math.sqrt(sum(c * c for c in d))
        yaw = math.degrees(math.atan2(d[0], d[2]))
        pitch = math.degrees(math.asin(d[1] / length))
        self.col_cyl(r, length, add(a, d, 0.5), (90 - pitch, yaw, 0))

    # --- output --------------------------------------------------------------------------
    def scene(self):
        sc = Scene()
        props = {"script": sc.res(ROOT_SCRIPT, "Script"), "prop_id": '"%s"' % self.id,
                 "category": '"%s"' % self.category, "display_name": '"%s"' % self.label,
                 "collides": "true" if self.shapes else "false", "radius": f(self.radius),
                 "mount": '"%s"' % self.mount, "label_height": f(self.height + 0.6)}
        if self.anchors:
            props["metadata/anchors"] = "PackedVector3Array(%s)" % ", ".join(
                "%s, %s, %s" % (f(a[0]), f(a[1]), f(a[2])) for a in self.anchors)
        if self.cut:
            props["metadata/ground_cut"] = "Rect2(%s, %s, %s, %s)" % tuple(f(v) for v in self.cut)
        root = sc.node(self.id.title().replace("_", ""), "Node3D", None, props)
        counts = {}
        for mtype, mprops, t, mat in self.parts:
            name = mat.title().replace("_", "")
            counts[name] = counts.get(name, 0) + 1
            sc.node(name, "MeshInstance3D", root, {
                "transform": t, "mesh": sc.sub(mtype, mprops), "material_override": sc.mat(mat)})
        if self.shapes:
            body = sc.node("Collision", "StaticBody3D", root)
            for stype, sprops, t in self.shapes:
                sc.node("Shape", "CollisionShape3D", body, {"transform": t, "shape": sc.sub(stype, sprops)})
        for text, pos, yaw in self.labels:
            sc.node("Sign", "Label3D", root, {
                "transform": xf(pos, (0, yaw, 0)), "text": '"%s"' % text, "font_size": "48",
                "pixel_size": "0.006", "outline_size": "8", "modulate": "Color(1, 1, 1, 1)"})
        return sc

    def path(self):
        return "%s/%s/%s.tscn" % (PROP_DIR, self.category, self.id)


# --------------------------------------------------------------------------------------------
# Trees and palms
# --------------------------------------------------------------------------------------------

def royal_palm():
    p = Prop("royal_palm", "palms", "Royal palm", radius=1.6, collides=True, height=12.5)
    p.cyl(0.24, 0.3, 4.5, (0, 2.25, 0), "royal_trunk")
    p.cyl(0.22, 0.27, 4.5, (0, 6.75, 0), "royal_trunk")
    p.cyl(0.26, 0.24, 2.0, (0, 10.0, 0), "crownshaft")
    for i in range(10):
        yaw = i * 36 + (13 if i % 2 else 0)
        p.frond((0, 11.0, 0), yaw, 38 if i % 2 else 22, 3.6, 0.75, "frond" if i % 3 else "frond_light", droop=30)
    p.frond((0, 11.0, 0), 20, 75, 2.0, 0.5, "frond_light", droop=10, segs=2)
    p.col_cyl(0.3, 9.0, (0, 4.5, 0))
    return p


def coconut_palm():
    p = Prop("coconut_palm", "palms", "Coconut palm (leaning)", radius=1.5, collides=True, height=8.5)
    pt = (0.0, 0.0, 0.0)
    for i in range(4):
        lean = 8 + 7 * i
        d = (math.sin(math.radians(lean)), math.cos(math.radians(lean)), 0.0)
        nxt = add(pt, d, 2.1)
        p.seg(pt, nxt, 0.22 - 0.015 * i, "palm_trunk", taper=0.93)
        p.col_seg(pt, nxt, 0.22)
        pt = nxt
    for i in range(9):
        p.frond(pt, i * 40 + 10, 25 if i % 2 else 5, 3.4, 0.65, "frond" if i % 2 else "frond_light", droop=38)
    for k in range(5):
        a = k * 72
        p.sphere(0.14, add(pt, (0.3 * math.cos(math.radians(a)), -0.35, 0.3 * math.sin(math.radians(a)))),
                 "coconut", seg=6, rings=4)
    return p


def sabal_palm():
    p = Prop("sabal_palm", "palms", "Sabal (cabbage) palm", radius=1.3, collides=True, height=7.0)
    p.cyl(0.26, 0.28, 5.6, (0, 2.8, 0), "palm_trunk", sides=7)
    for k in range(14):  # leaf boots on the upper trunk
        y = 3.4 + k * 0.16
        a = k * 137.5
        p.box((0.16, 0.22, 0.1), (0.27 * math.sin(math.radians(a)), y, 0.27 * math.cos(math.radians(a))),
              "palm_trunk", (25, a, 0))
    rnd = random.Random(7)
    top = (0, 5.8, 0)
    for i in range(18):
        yaw = i * 20 + rnd.uniform(-6, 6)
        pitch = rnd.choice((55, 35, 15, -5))
        p.frond(top, yaw, pitch, 2.0, 1.0, "sabal_frond", droop=22, segs=2)
    for i in range(7):  # dead skirt
        p.frond((0, 5.4, 0), i * 51, -70, 1.4, 0.6, "frond_dry", droop=5, segs=2)
    p.col_cyl(0.3, 5.6, (0, 2.8, 0))
    return p


def banyan():
    p = Prop("banyan", "trees", "Banyan", radius=5.5, collides=True, height=9.0)
    for dx, dz, r in ((0, 0, 0.7), (0.8, 0.4, 0.5), (-0.6, 0.6, 0.45)):
        p.cyl(r * 0.8, r, 5.0, (dx, 2.5, dz), "banyan_bark", sides=9)
        p.col_cyl(r, 5.0, (dx, 2.5, dz))
    rnd = random.Random(11)
    for i in range(5):
        a = math.radians(i * 72 + 20)
        p.seg((0, 4.0, 0), (4.5 * math.cos(a), 6.5, 4.5 * math.sin(a)), 0.32, "banyan_bark", taper=0.6)
    for i in range(9):  # aerial prop roots
        a = math.radians(i * 40 + rnd.uniform(-10, 10))
        rr = rnd.uniform(2.5, 5.0)
        x, z = rr * math.cos(a), rr * math.sin(a)
        r = rnd.uniform(0.08, 0.22)
        p.cyl(r, r * 1.2, 6.0, (x, 3.0, z), "banyan_bark", sides=6)
        if r > 0.15:
            p.col_cyl(r * 1.2, 6.0, (x, 3.0, z))
    for i in range(8):
        a = math.radians(i * 45)
        rr = 0 if i == 0 else rnd.uniform(3.0, 4.5)
        p.sphere(3.4, (rr * math.cos(a), rnd.uniform(6.8, 7.6), rr * math.sin(a)), "banyan_leaf",
                 scale=(1, 0.42, 1), seg=10, rings=5)
    return p


def live_oak():
    p = Prop("live_oak", "trees", "Live oak with Spanish moss", radius=4.0, collides=True, height=8.0)
    p.cyl(0.4, 0.5, 2.4, (0, 1.2, 0), "oak_bark", sides=8)
    p.col_cyl(0.5, 2.4, (0, 1.2, 0))
    rnd = random.Random(12)
    tips = []
    for i in range(5):
        a = math.radians(i * 72 + 15)
        tip = (4.5 * math.cos(a), rnd.uniform(4.0, 5.2), 4.5 * math.sin(a))
        p.seg((0, 2.2, 0), tip, 0.28, "oak_bark", taper=0.5)
        tips.append(tip)
    p.sphere(3.0, (0, 5.6, 0), "oak_leaf", scale=(1, 0.5, 1), seg=10)
    for t in tips:
        p.sphere(2.2, (t[0], t[1] + 0.9, t[2]), "oak_leaf", scale=(1, 0.5, 1))
    for i in range(16):  # Spanish moss
        t = tips[i % len(tips)]
        k = rnd.uniform(0.35, 0.9)
        x, z = t[0] * k + rnd.uniform(-0.6, 0.6), t[2] * k + rnd.uniform(-0.6, 0.6)
        y = 2.2 + (t[1] - 2.2) * k
        h = rnd.uniform(0.7, 1.4)
        p.box((0.22, h, 0.05), (x, y - h / 2, z), "moss", (0, rnd.uniform(0, 180), 0))
    return p


def sea_grape():
    p = Prop("sea_grape", "shrubs", "Sea grape shrub", radius=1.5, height=2.2)
    rnd = random.Random(13)
    for i in range(6):
        a = math.radians(i * 60)
        r = rnd.uniform(0.6, 0.95)
        p.sphere(r, (0.7 * math.cos(a), 0.7 + rnd.uniform(0, 0.8), 0.7 * math.sin(a)), "sea_grape",
                 scale=(1, 0.85, 1), seg=7, rings=4)
    for i in range(10):  # big round leaves
        a = rnd.uniform(0, 360)
        p.cyl(0.22, 0.22, 0.02, (1.2 * math.cos(math.radians(a)), rnd.uniform(0.6, 1.9),
                                 1.2 * math.sin(math.radians(a))), "leaf_dark", (rnd.uniform(40, 80), a, 0))
    return p


def sea_grape_hedge():
    p = Prop("sea_grape_hedge", "shrubs", "Sea grape hedge (6 m)", radius=3.0, height=2.0)
    p.box((6.0, 1.4, 1.2), (0, 0.7, 0), "sea_grape")
    rnd = random.Random(14)
    for i in range(7):
        p.sphere(0.75, (-2.7 + i * 0.9, 1.35 + rnd.uniform(0, 0.25), rnd.uniform(-0.15, 0.15)), "sea_grape",
                 scale=(1, 0.7, 0.9), seg=7, rings=4)
    return p


def brush_clump():
    p = Prop("brush_clump", "shrubs", "Saw palmetto brush", radius=1.1, height=1.2)
    rnd = random.Random(15)
    p.sphere(0.5, (0, 0.25, 0), "brush", scale=(1.2, 0.6, 1.2), seg=6, rings=3)
    for i in range(12):
        p.frond((0, 0.15, 0), i * 30 + rnd.uniform(-8, 8), rnd.uniform(25, 60), 1.0, 0.45,
                "brush" if i % 3 else "brush_dry", droop=20, segs=2)
    return p


def weeds_tall():
    p = Prop("weeds_tall", "shrubs", "Tall weeds / overgrowth", radius=0.9, height=1.1)
    rnd = random.Random(16)
    for i in range(18):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0, 0.8)
        h = rnd.uniform(0.5, 1.1)
        p.box((0.05, h, 0.05), (r * math.cos(a), h / 2, r * math.sin(a)), "weeds" if i % 3 else "brush_dry",
              (rnd.uniform(-15, 15), rnd.uniform(0, 180), rnd.uniform(-15, 15)))
    p.sphere(0.45, (0, 0.15, 0), "weeds", scale=(1.6, 0.5, 1.6), seg=6, rings=3)
    return p


def hibiscus_bed():
    p = Prop("hibiscus_bed", "flowers", "Hibiscus bed", radius=1.6, mount="bed", height=1.2)
    p.box((3.0, 0.08, 1.1), (0, 0.04, 0), "mulch")
    rnd = random.Random(17)
    for i in range(3):
        x = -1.0 + i
        p.sphere(0.5, (x, 0.55, 0), "leaf_dark", scale=(1, 1.1, 1), seg=7, rings=4)
        for k in range(5):
            a = rnd.uniform(0, math.tau)
            p.box((0.16, 0.06, 0.16), (x + 0.45 * math.cos(a), rnd.uniform(0.45, 1.0), 0.45 * math.sin(a)),
                  ("flower_red", "flower_pink", "flower_yellow")[(i + k) % 3], (0, rnd.uniform(0, 90), 0))
    return p


def bougainvillea():
    p = Prop("bougainvillea", "flowers", "Bougainvillea", radius=1.3, mount="bed", height=2.4)
    rnd = random.Random(18)
    p.cyl(0.04, 0.05, 2.0, (0, 1.0, -0.3), "oak_bark")
    for i in range(9):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0.35, 0.6)
        p.sphere(r, (0.7 * math.cos(a), rnd.uniform(0.5, 2.1), 0.4 * math.sin(a)),
                 ("flower_pink", "flower_purple", "leaf_dark")[i % 3], seg=7, rings=4)
    return p


def flower_bed():
    p = Prop("flower_bed", "flowers", "Round flower bed", radius=1.1, height=0.8)
    p.cyl(1.0, 1.0, 0.08, (0, 0.04, 0), "mulch", sides=12)
    rnd = random.Random(19)
    for i in range(14):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0, 0.8)
        p.sphere(0.16, (r * math.cos(a), 0.22, r * math.sin(a)),
                 ("flower_orange", "flower_yellow", "flower_white", "flower_red")[i % 4], seg=6, rings=3)
        p.sphere(0.2, (r * math.cos(a + 0.4), 0.14, r * math.sin(a + 0.4)), "leaf_dark", seg=6, rings=3)
    return p


def sand_patch():
    p = Prop("sand_patch", "ground", "Patchy sandy grass", radius=1.8, height=0.3)
    rnd = random.Random(20)
    for i in range(4):
        r = rnd.uniform(0.7, 1.4)
        p.cyl(r, r, 0.016, (rnd.uniform(-0.8, 0.8), 0.008 + 0.002 * i, rnd.uniform(-0.8, 0.8)), "sand",
              sides=9, scale=(1, 1, rnd.uniform(0.5, 0.9)))
    return p


def dirt_patch():
    p = Prop("dirt_patch", "ground", "Bare dirt patch", radius=1.5, height=0.3)
    rnd = random.Random(21)
    for i in range(3):
        r = rnd.uniform(0.6, 1.2)
        p.cyl(r, r, 0.016, (rnd.uniform(-0.6, 0.6), 0.009 + 0.002 * i, rnd.uniform(-0.6, 0.6)), "dirt", sides=8,
              scale=(1, 1, 0.7))
    return p


def fallen_frond():
    p = Prop("fallen_frond", "ground", "Fallen palm frond", radius=1.3, height=0.3)
    p.box((0.08, 0.05, 2.4), (0, 0.03, 0), "frond_dry", (0, 0, 0))
    for i in range(9):
        for side in (-1, 1):
            p.box((0.7, 0.02, 0.06), (side * 0.36, 0.04, -1.0 + i * 0.25), "frond_dry", (0, side * 30, 0))
    return p


def garden_pond():
    p = Prop("garden_pond", "water", "Small garden pond", radius=2.0, height=0.6)
    p.cyl(1.6, 1.6, 0.02, (0, 0.03, 0), "water", sides=14, scale=(1, 1, 0.7))
    rnd = random.Random(22)
    for i in range(16):
        a = i / 16 * math.tau
        p.sphere(rnd.uniform(0.18, 0.3), (1.7 * math.cos(a), 0.08, 1.2 * math.sin(a)), "concrete",
                 scale=(1, 0.6, 1), seg=6, rings=3)
    for i in range(4):
        a = rnd.uniform(0, math.tau)
        p.cyl(0.18, 0.18, 0.01, (0.8 * math.cos(a), 0.045, 0.5 * math.sin(a)), "leaf_dark", sides=8)
    p.cyl(0.4, 0.4, 0.02, (0.3, 0.05, -0.2), "flower_white", sides=6, scale=(0.3, 1, 0.3))
    return p


def _bank(p, length, run, drop, center, yaw, mat="grass"):
    """Sloped bank slab: top surface falls `drop` over `run` metres inward (local -Z after yaw)."""
    ang = math.degrees(math.atan2(drop, run))
    slope = math.hypot(run, drop)
    t = 0.3
    # Slab top passes through the rim (local z = 0, y = 0) and the toe (z = -run, y = -drop).
    nrm = (0, math.cos(math.radians(ang)), -math.sin(math.radians(ang)))  # unrotated: tilt about X
    c = (0, -drop / 2 - nrm[1] * t / 2, -run / 2 - nrm[2] * t / 2)
    yr = math.radians(yaw)
    cx = c[0] * math.cos(yr) + c[2] * math.sin(yr)
    cz = -c[0] * math.sin(yr) + c[2] * math.cos(yr)
    pos = (center[0] + cx, c[1], center[2] + cz)
    p.box((length, t, slope), pos, mat, (-ang, yaw, 0))
    p.col_box((length, t, slope), pos, (-ang, yaw, 0))


def retention_pond():
    w, d, run, drop = 16.0, 11.0, 3.0, 1.3
    p = Prop("retention_pond", "water", "Fenced retention pond", radius=10.0, collides=True, height=2.2)
    p.cut = (-w / 2, -d / 2, w, d)
    hw, hd = w / 2, d / 2
    _bank(p, w, run, drop, (0, 0, hd), 0)
    _bank(p, w, run, drop, (0, 0, -hd), 180)
    _bank(p, d, run, drop, (hw, 0, 0), 90)
    _bank(p, d, run, drop, (-hw, 0, 0), -90)
    p.box((w, 0.2, d), (0, -drop - 0.4, 0), "dirt")
    p.col_box((w, 0.2, d), (0, -drop - 0.4, 0))
    p.box((w - 0.2, 0.02, d - 0.2), (0, -drop * 0.6, 0), "water")
    # Chain-link fence 1 m outside the rim with a maintenance gate gap on the +Z side.
    fx, fz, h = hw + 1.0, hd + 1.0, 1.5
    spans = [((-fx, -fz), (fx, -fz)), ((-fx, -fz), (-fx, fz)), ((fx, -fz), (fx, fz)),
             ((-fx, fz), (-1.5, fz)), ((1.5, fz), (fx, fz))]
    for (x0, z0), (x1, z1) in spans:
        _chain_span(p, x0, z0, x1, z1, h)
    p.cyl(0.04, 0.04, 2.0, (2.4, 1.0, fz + 0.3), "metal_grey")
    p.box((1.0, 0.6, 0.03), (2.4, 1.8, fz + 0.33), "sign_white")
    p.labels.append(("NO SWIMMING\nNO FISHING", (2.4, 1.8, fz + 0.36), 0))
    return p


def _chain_span(p, x0, z0, x1, z1, h=1.5):
    length = math.hypot(x1 - x0, z1 - z0)
    yaw = math.degrees(math.atan2(x1 - x0, z1 - z0))
    mid = ((x0 + x1) / 2, h / 2, (z0 + z1) / 2)
    p.box((0.02, h, length), mid, "fence_chain", (0, yaw, 0))
    p.box((0.05, 0.05, length), (mid[0], h, mid[2]), "metal_grey", (0, yaw, 0))
    p.col_box((0.08, h, length), mid, (0, yaw, 0))
    n = max(1, int(math.ceil(length / 3.0)))
    for i in range(n + 1):
        k = i / n
        p.cyl(0.04, 0.04, h + 0.1, (x0 + (x1 - x0) * k, (h + 0.1) / 2, z0 + (z1 - z0) * k), "metal_grey", sides=6)


def canal_segment():
    length, width, run, drop = 24.0, 14.0, 3.5, 2.0
    p = Prop("canal_segment", "water", "Canal segment (24 m)", radius=12.0, collides=True, height=1.0)
    p.cut = (-length / 2, -width / 2, length, width)
    hw = width / 2
    _bank(p, length, run, drop, (0, 0, -hw), 180)  # grass bank on the far (-Z) side
    # Concrete seawall on the street (+Z) side, with a cap.
    p.box((length, drop + 0.6, 0.4), (0, -(drop + 0.6) / 2 + 0.1, hw - 0.2), "concrete")
    p.col_box((length, drop + 0.6, 0.4), (0, -(drop + 0.6) / 2 + 0.1, hw - 0.2))
    p.box((length, 0.15, 0.6), (0, 0.12, hw - 0.25), "concrete")
    p.box((length, 0.2, width), (0, -drop - 0.6, 0), "dirt")
    p.col_box((length, 0.2, width), (0, -drop - 0.6, 0))
    p.box((length, 0.02, width - 0.4), (0, -drop * 0.7, 0), "canal_water")
    for x in (-8.0, 0.0, 8.0):  # guard-rail posts and rail along the seawall
        p.box((0.15, 0.9, 0.15), (x, 0.45, hw - 0.1), "metal_grey")
        p.col_box((0.15, 0.9, 0.15), (x, 0.45, hw - 0.1))
    p.box((length, 0.3, 0.06), (0, 0.75, hw - 0.02), "metal_grey")
    p.col_box((length, 0.9, 0.1), (0, 0.45, hw - 0.05))
    return p


# --------------------------------------------------------------------------------------------
# Yard clutter
# --------------------------------------------------------------------------------------------

def chain_fence():
    p = Prop("chain_fence_3m", "yard", "Chain-link fence (3 m)", radius=1.5, collides=True, height=1.4)
    _chain_span(p, -1.5, 0, 1.5, 0, 1.2)
    return p


def block_wall():
    p = Prop("block_wall_3m", "yard", "Stucco block wall (3 m)", radius=1.5, collides=True, height=1.8)
    p.box((3.0, 1.5, 0.2), (0, 0.75, 0), "stucco_beige")
    p.box((3.08, 0.08, 0.28), (0, 1.54, 0), "trim_white")
    for x in (-1.4, 1.4):
        p.box((0.4, 1.7, 0.4), (x, 0.85, 0), "stucco_beige")
    for x in (-0.6, 0.6):  # a little rust bleeding from the rebar
        p.box((0.06, 0.5, 0.01), (x, 1.15, 0.105), "rust_light")
    p.col_box((3.0, 1.6, 0.4), (0, 0.8, 0))
    return p


def carport():
    p = Prop("carport_metal", "yard", "Metal carport", radius=3.2, collides=True, height=3.0)
    for x in (-1.6, 1.6):
        for z in (-2.8, 2.8):
            p.box((0.1, 2.6, 0.1), (x, 1.3, z), "metal_grey")
            p.col_box((0.12, 2.6, 0.12), (x, 1.3, z))
    p.box((3.6, 0.08, 6.2), (0, 2.66, 0), "roof_metal", (0, 0, 4))
    for z in (-2.8, 2.8):
        p.box((3.4, 0.1, 0.1), (0, 2.56, z), "metal_grey")
    return p


def wall_ac():
    p = Prop("wall_ac", "yard", "Through-wall AC unit", radius=0.5, mount="wall", height=0.6)
    p.box((0.7, 0.45, 0.55), (0, 0, 0.2), "ac_unit")
    p.box((0.6, 0.35, 0.02), (0, 0, 0.48), "metal_grey")
    for x in (-0.3, 0.3):
        p.box((0.04, 0.04, 0.45), (x, -0.27, 0.2), "metal_dark", (30, 0, 0))
    p.box((0.05, 0.4, 0.01), (0.15, -0.45, 0.005), "rust")
    return p


def window_ac():
    p = Prop("window_ac", "yard", "Window AC unit", radius=0.45, mount="window", height=0.5)
    p.box((0.62, 0.4, 0.55), (0, 0.2, 0.12), "ac_unit")
    p.box((0.52, 0.3, 0.02), (0, 0.2, 0.4), "metal_grey")
    for x in (-0.45, 0.45):
        p.box((0.25, 0.38, 0.02), (x, 0.2, 0.0), "plastic_white")
    return p


def window_bars():
    p = Prop("window_bars", "yard", "Window security bars (1 x 1 m, scaled to the opening)", radius=0.5,
             mount="window", height=1.0)
    for i in range(1, 8):
        p.box((0.025, 1.0, 0.025), (-0.5 + i / 8, 0, 0.07), "metal_dark")
    for y in (-0.45, 0.0, 0.45):
        p.box((1.04, 0.04, 0.02), (0, y, 0.07), "metal_dark")
    return p


def storm_panel():
    p = Prop("storm_panel", "yard", "Hurricane storm panel (1 x 1 m, scaled to the opening)", radius=0.5,
             mount="window", height=1.0)
    p.box((1.2, 1.2, 0.02), (0, 0, 0.06), "storm_panel")
    for i in range(8):
        p.box((0.03, 1.2, 0.03), (-0.525 + i * 0.15, 0, 0.08), "storm_panel")
    return p


def satellite_dish():
    p = Prop("satellite_dish", "yard", "Satellite dish", radius=0.5, mount="wall", height=0.8)
    p.box((0.08, 0.3, 0.04), (0, 0, 0.02), "metal_grey")
    p.box((0.05, 0.05, 0.45), (0, 0, 0.25), "metal_grey")
    p.sphere(0.38, (0, 0.12, 0.5), "plastic_white", scale=(1, 1, 0.25), rot=(-30, 0, 0), seg=10, rings=4)
    p.box((0.03, 0.03, 0.45), (0, 0.0, 0.75), "metal_grey", (-25, 0, 0))
    p.box((0.08, 0.08, 0.1), (0, -0.08, 0.95), "metal_dark")
    return p


def trash_bin(pid="trash_bin", mat="bin_green", label="Rolling trash bin"):
    p = Prop(pid, "yard", label, radius=0.5, collides=True, height=1.1)
    p.box((0.58, 0.95, 0.68), (0, 0.52, 0), mat)
    p.box((0.62, 0.06, 0.74), (0, 1.02, 0.02), mat)
    for x in (-0.24, 0.24):
        p.cyl(0.1, 0.1, 0.06, (x, 0.1, -0.33), "tire", rot=(0, 0, 90), sides=8)
    p.col_box((0.6, 1.05, 0.72), (0, 0.52, 0))
    return p


def laundry_line():
    p = Prop("laundry_line", "yard", "Laundry line", radius=2.8, collides=True, height=2.2)
    for x in (-2.5, 2.5):
        p.box((0.08, 2.0, 0.08), (x, 1.0, 0), "metal_grey")
        p.box((0.06, 0.06, 1.0), (x, 1.95, 0), "metal_grey")
        p.col_box((0.1, 2.0, 0.1), (x, 1.0, 0))
    for z in (-0.4, 0.0, 0.4):
        p.box((5.0, 0.015, 0.015), (0, 1.94, z), "wire")
    rnd = random.Random(23)
    x = -2.1
    cloths = ("cloth_white", "cloth_blue", "cloth_red", "cloth_yellow")
    while x < 2.0:
        w = rnd.uniform(0.35, 0.8)
        h = rnd.uniform(0.4, 0.9)
        z = rnd.choice((-0.4, 0.0, 0.4))
        p.box((w, h, 0.02), (x + w / 2, 1.94 - h / 2, z), rnd.choice(cloths))
        x += w + rnd.uniform(0.1, 0.4)
    return p


def above_ground_pool():
    p = Prop("above_ground_pool", "yard", "Above-ground pool", radius=3.0, collides=True, height=1.4)
    p.cyl(2.4, 2.4, 1.2, (0, 0.6, 0), "pool_liner", sides=20)
    p.cyl(2.5, 2.5, 0.08, (0, 1.22, 0), "plastic_white", sides=20)
    p.cyl(2.32, 2.32, 0.02, (0, 1.1, 0), "pool_water", sides=20)
    for i in range(10):
        a = i / 10 * math.tau
        p.box((0.1, 1.2, 0.06), (2.43 * math.cos(a), 0.6, 2.43 * math.sin(a)), "plastic_white",
              (0, -math.degrees(a) + 90, 0))
    for side in (-1, 1):  # A-frame ladder over the wall on +X
        p.box((0.05, 1.6, 0.05), (2.4 + side * 0.45, 0.75, 0.3), "metal_grey", (0, 0, side * 25))
        p.box((0.05, 1.6, 0.05), (2.4 + side * 0.45, 0.75, -0.3), "metal_grey", (0, 0, side * 25))
    p.col_cyl(2.5, 1.3, (0, 0.65, 0))
    return p


def screened_pool(pid="screened_pool", w=10.0, d=8.0):
    """Paver deck + in-ground pool + aluminium screen cage. +Z faces the house wall it attaches to."""
    p = Prop(pid, "yard", "Screened pool enclosure (%g x %g m)" % (w, d), radius=max(w, d) / 2, collides=True,
             height=4.0)
    p.cut = (-w / 2, -d / 2, w, d)
    pw, pd = w - 4.0, d - 4.4
    pz = -0.4
    hw, hd = w / 2, d / 2
    # Deck as four paver strips around the pool, white coping, water just below the deck.
    p.box((w, 0.06, hd - pd / 2 - pz), (0, 0.03, (hd + pd / 2 + pz) / 2), "pavers")
    p.box((w, 0.06, hd - pd / 2 + pz), (0, 0.03, (-hd - pd / 2 + pz) / 2), "pavers")
    for s in (-1, 1):
        p.box(((w - pw) / 2, 0.06, pd), (s * (hw + pw / 2) / 2, 0.03, pz), "pavers")
    c = 0.15
    for s in (-1, 1):
        p.box((pw, 0.07, c), (0, 0.035, pz + s * (pd / 2 - c / 2)), "plastic_white")
        p.box((c, 0.07, pd), (s * (pw / 2 - c / 2), 0.035, pz), "plastic_white")
    p.box((pw - 2 * c, 0.02, pd - 2 * c), (0, 0.03, pz), "pool_water")
    h = 3.0
    posts = []
    for i in range(5):
        x = -hw + i * w / 4
        posts += [(x, -hd), (x, hd)]
    for i in range(1, 4):
        z = -hd + i * d / 4
        posts += [(-hw, z), (hw, z)]
    for x, z in posts:
        p.box((0.1, h, 0.1), (x, h / 2, z), "trim_white")
    for z in (-hd, hd):
        p.box((w, 0.12, 0.12), (0, h, z), "trim_white")
        p.box((w, 0.08, 0.08), (0, 1.0, z), "trim_white")
    for x in (-hw, hw):
        p.box((0.12, 0.12, d), (x, h, 0), "trim_white")
        p.box((0.08, 0.08, d), (x, 1.0, 0), "trim_white")
    p.box((w, h, 0.02), (0, h / 2, -hd), "screen")
    p.box((0.02, h, d), (-hw, h / 2, 0), "screen")
    p.box((0.02, h, d), (hw, h / 2, 0), "screen")
    # Mansard screen roof: flat top + four sloped skirts.
    rise, inset = 0.9, 1.2
    p.box((w - 2 * inset, 0.02, d - 2 * inset), (0, h + rise, 0), "screen")
    ang = math.degrees(math.atan2(rise, inset))
    sl = math.hypot(rise, inset)
    for s in (-1, 1):
        p.box((w, 0.02, sl), (0, h + rise / 2, s * (hd - inset / 2)), "screen", (s * ang, 0, 0))
        p.box((sl, 0.02, d), (s * (hw - inset / 2), h + rise / 2, 0), "screen", (0, 0, -s * ang))
    for x in (-hw + inset, hw - inset):
        p.box((0.08, 0.08, d - 2 * inset), (x, h + rise, 0), "trim_white")
    p.col_box((w, h, 0.1), (0, h / 2, -hd))
    p.col_box((0.1, h, d), (-hw, h / 2, 0))
    p.col_box((0.1, h, d), (hw, h / 2, 0))
    # House side: screen with a 1.2 m door near the -X end.
    p.box((w - 2.0, h, 0.02), (1.0, h / 2, hd), "screen")
    p.col_box((w - 2.0, h, 0.1), (1.0, h / 2, hd))
    return p


def pavers_patio():
    p = Prop("pavers_patio", "yard", "Paver patio (4 x 4 m)", radius=2.0, height=0.3)
    p.box((4.0, 0.06, 4.0), (0, 0.03, 0), "pavers")
    p.box((4.1, 0.07, 0.1), (0, 0.035, 2.0), "pavers_grey")
    p.box((4.1, 0.07, 0.1), (0, 0.035, -2.0), "pavers_grey")
    return p


def shopping_cart():
    p = Prop("shopping_cart", "yard", "Abandoned shopping cart", radius=0.6, collides=True, height=1.1)
    p.box((0.55, 0.02, 0.85), (0, 0.45, 0), "metal_grey")
    for x in (-0.27, 0.27):
        p.box((0.02, 0.5, 0.85), (x, 0.7, 0), "fence_chain")
    p.box((0.55, 0.5, 0.02), (0, 0.7, 0.42), "fence_chain")
    p.box((0.5, 0.45, 0.02), (0, 0.68, -0.42), "fence_chain")
    p.box((0.6, 0.04, 0.04), (0, 1.0, -0.5), "cart_red")
    for x in (-0.22, 0.22):
        for z in (-0.35, 0.35):
            p.box((0.03, 0.42, 0.03), (x, 0.24, z), "metal_grey")
            p.cyl(0.06, 0.06, 0.03, (x, 0.06, z), "tire", rot=(0, 0, 90), sides=6)
    p.col_box((0.6, 1.0, 0.95), (0, 0.5, 0))
    return p


def graffiti_tag():
    p = Prop("graffiti_tag", "decals", "Graffiti tag", radius=1.4, mount="wall", height=1.6)
    rnd = random.Random(24)
    cols = ("paint_pink", "paint_green", "paint_black", "paint_cyan", "paint_orange")
    for i in range(14):
        x = -1.2 + i * 0.18 + rnd.uniform(-0.05, 0.05)
        h = rnd.uniform(0.4, 0.9)
        p.box((0.09, h, 0.01), (x, rnd.uniform(-0.15, 0.15), 0.01), cols[i % 2 if i % 5 else 2],
              (0, 0, rnd.uniform(-35, 35)))
    p.box((2.6, 0.06, 0.01), (0, -0.5, 0.012), cols[3], (0, 0, 4))
    return p


def mural():
    p = Prop("mural", "decals", "Mural (6 x 3 m)", radius=3.0, mount="wall", height=3.0)
    p.box((6.0, 3.0, 0.01), (0, 0, 0.006), "paint_teal")
    p.box((6.0, 1.0, 0.01), (0, -1.0, 0.009), "paint_cyan")
    p.cyl(0.75, 0.75, 0.01, (1.6, 0.6, 0.012), "paint_orange", rot=(90, 0, 0), sides=16)
    for x, h in ((-2.0, 2.2), (-0.6, 1.7)):  # palm silhouettes
        p.box((0.12, h, 0.01), (x, -1.5 + h / 2, 0.014), "paint_black", (0, 0, 6))
        for k in range(6):
            p.box((0.9, 0.08, 0.01), (x + 0.1, -1.5 + h, 0.015), "paint_green", (0, 0, k * 30 - 75))
    p.box((5.6, 0.25, 0.01), (0, 1.25, 0.012), "paint_pink")
    p.box((5.6, 0.12, 0.01), (0, 0.95, 0.012), "paint_purple")
    return p


def rust_streak():
    p = Prop("rust_streak", "decals", "Rust stain", radius=0.4, mount="wall", height=1.2)
    rnd = random.Random(25)
    p.box((0.12, 0.08, 0.05), (0, 0, 0.025), "metal_dark")
    for i in range(4):
        h = rnd.uniform(0.5, 1.4)
        p.box((rnd.uniform(0.05, 0.14), h, 0.01), (-0.15 + i * 0.1, -h / 2, 0.006),
              "rust" if i % 2 else "rust_light")
    return p


# --------------------------------------------------------------------------------------------
# Street furniture
# --------------------------------------------------------------------------------------------

def power_pole(pid="power_pole", transformer=False):
    p = Prop(pid, "street", "Wooden power pole" + (" + transformer" if transformer else ""), radius=0.4,
             collides=True, height=10.0)
    p.cyl(0.13, 0.17, 10.0, (0, 5.0, 0), "wood_pole")
    p.box((2.6, 0.12, 0.12), (0, 9.2, 0), "wood_pole")
    for x in (-1.1, 1.1):
        p.box((0.05, 0.05, 0.9), (x * 0.5, 8.95, 0), "metal_dark", (0, 90, 40 if x > 0 else -40))
    for x in (-1.1, 0.0, 1.1):
        p.cyl(0.05, 0.06, 0.2, (x, 9.36 if x else 9.95, 0), "plastic_white")
    p.anchors = [(-1.1, 9.46, 0), (1.1, 9.46, 0), (0, 10.05, 0), (0, 7.0, 0.18)]
    p.box((0.1, 0.1, 0.12), (0, 7.0, 0.15), "metal_dark")
    if transformer:
        p.cyl(0.3, 0.3, 1.0, (0, 7.8, 0.42), "metal_grey")
        p.cyl(0.32, 0.32, 0.06, (0, 8.32, 0.42), "metal_dark")
    p.col_cyl(0.18, 10.0, (0, 5.0, 0))
    return p


def bus_bench():
    p = Prop("bus_bench", "street", "Bus bench with ad back", radius=1.1, collides=True, height=1.3)
    p.box((2.0, 0.06, 0.45), (0, 0.45, 0), "fence_wood")
    p.box((2.0, 0.6, 0.06), (0, 0.85, -0.22), "sign_white")
    p.box((1.9, 0.5, 0.01), (0, 0.85, -0.185), "paint_teal")
    for x in (-0.9, 0.9):
        p.box((0.08, 0.45, 0.45), (x, 0.22, 0), "concrete")
    p.col_box((2.0, 1.2, 0.5), (0, 0.6, 0))
    p.labels.append(("CALL SAUL\nFL INJURY LAW", (0, 0.85, -0.178), 0))
    return p


def bus_shelter():
    p = Prop("bus_shelter", "street", "Bus shelter", radius=2.2, collides=True, height=2.8)
    w, d, h = 4.0, 1.5, 2.5
    for x in (-w / 2 + 0.05, w / 2 - 0.05):
        for z in (-d / 2 + 0.05, d / 2 - 0.05):
            p.box((0.08, h, 0.08), (x, h / 2, z), "metal_grey")
            p.col_box((0.1, h, 0.1), (x, h / 2, z))
    p.box((w + 0.2, 0.12, d + 0.3), (0, h + 0.06, 0.1), "metal_grey")
    p.box((w - 0.1, 2.0, 0.02), (0, 1.2, -d / 2 + 0.05), "glass")
    p.col_box((w, 2.0, 0.08), (0, 1.2, -d / 2 + 0.05))
    p.box((0.02, 1.8, d - 0.2), (-w / 2 + 0.05, 1.2, 0), "sign_white")
    p.col_box((0.06, 1.8, d - 0.2), (-w / 2 + 0.05, 1.2, 0))
    p.box((2.0, 0.06, 0.4), (0.6, 0.45, -0.4), "metal_grey")
    p.col_box((2.0, 0.5, 0.4), (0.6, 0.25, -0.4))
    p.cyl(0.04, 0.04, 2.8, (w / 2 + 0.4, 1.4, 0.5), "metal_grey")
    p.box((0.45, 0.6, 0.03), (w / 2 + 0.4, 2.5, 0.52), "news_blue")
    p.labels.append(("BUS", (w / 2 + 0.4, 2.55, 0.54), 0))
    return p


def mailbox():
    p = Prop("mailbox", "street", "Curbside mailbox", radius=0.3, collides=True, height=1.4)
    p.box((0.1, 1.05, 0.1), (0, 0.52, 0), "fence_wood")
    p.box((0.24, 0.24, 0.5), (0, 1.15, 0), "metal_dark")
    p.cyl(0.12, 0.12, 0.5, (0, 1.27, 0), "metal_dark", rot=(90, 0, 0), sides=8)
    p.box((0.03, 0.15, 0.04), (0.13, 1.35, -0.18), "cart_red")
    p.col_box((0.15, 1.3, 0.15), (0, 0.65, 0))
    return p


def mailbox_cluster():
    p = Prop("mailbox_cluster", "street", "Cluster mailbox (CBU)", radius=0.6, collides=True, height=1.8)
    p.box((1.0, 1.4, 0.45), (0, 0.9, 0), "metal_wall_tan")
    p.box((1.06, 0.12, 0.5), (0, 1.66, 0), "metal_dark")
    p.box((0.4, 0.2, 0.3), (0, 0.1, 0), "metal_dark")
    for i in range(4):
        for j in range(3):
            p.box((0.28, 0.25, 0.01), (-0.32 + j * 0.32, 0.55 + i * 0.3, 0.23), "metal_grey")
    p.col_box((1.0, 1.7, 0.5), (0, 0.85, 0))
    return p


def newspaper_boxes():
    p = Prop("newspaper_boxes", "street", "Newspaper boxes", radius=0.9, collides=True, height=1.2)
    for i, m in enumerate(("news_blue", "news_red", "news_yellow")):
        x = -0.6 + i * 0.6
        p.box((0.5, 0.75, 0.45), (x, 0.55, 0), m)
        p.box((0.4, 0.3, 0.01), (x, 0.7, 0.23), "glass")
        p.box((0.06, 0.18, 0.06), (x, 0.09, 0), "metal_dark")
    p.col_box((1.8, 1.0, 0.5), (0, 0.5, 0))
    return p


def overgrown_lot():
    w, d = 12.0, 20.0
    p = Prop("overgrown_lot", "lots", "Overgrown empty lot (12 x 20 m)", radius=6.0, collides=True, height=2.5)
    p.box((w, 0.22, d), (0, -0.09, -d / 2), "grass")
    p.col_box((w, 0.22, d), (0, -0.09, -d / 2))
    rnd = random.Random(26)
    for _ in range(9):
        r = rnd.uniform(0.8, 2.0)
        p.cyl(r, r, 0.016, (rnd.uniform(-4.5, 4.5), 0.028, rnd.uniform(-18, -2)), rnd.choice(("sand", "dirt")),
              sides=9, scale=(1, 1, rnd.uniform(0.5, 1.0)))
    for _ in range(26):
        x, z = rnd.uniform(-5.4, 5.4), rnd.uniform(-19.4, -0.8)
        for k in range(6):
            h = rnd.uniform(0.5, 1.3)
            p.box((0.05, h, 0.05), (x + rnd.uniform(-0.4, 0.4), h / 2, z + rnd.uniform(-0.4, 0.4)),
                  "weeds" if k % 3 else "brush_dry", (rnd.uniform(-15, 15), rnd.uniform(0, 180), rnd.uniform(-15, 15)))
    for _ in range(6):
        x, z = rnd.uniform(-4.5, 4.5), rnd.uniform(-18, -3)
        p.sphere(rnd.uniform(0.6, 1.1), (x, 0.4, z), rnd.choice(("brush", "sea_grape", "brush_dry")),
                 scale=(1.3, 0.7, 1.2), seg=7, rings=4)
    # Litter: a dumped mattress, tyres, a busted TV, bags.
    p.box((1.4, 0.2, 1.9), (2.5, 0.12, -14), "cloth_white", (0, 25, 4))
    for x, z in ((-3.0, -9.0), (-2.4, -9.4)):
        p.cyl(0.35, 0.35, 0.22, (x, 0.12, z), "tire", sides=10)
    p.box((0.6, 0.45, 0.45), (-1.0, 0.23, -4.0), "bin_black", (0, 40, 0))
    for x, z in ((3.0, -3.5), (3.4, -3.0), (-4.2, -16.0)):
        p.sphere(0.3, (x, 0.22, z), "bin_black", scale=(1, 0.8, 1), seg=6, rings=4)
    # A volunteer sabal palm.
    p.cyl(0.24, 0.26, 4.0, (-3.5, 2.0, -15.0), "palm_trunk", sides=7)
    p.col_cyl(0.26, 4.0, (-3.5, 2.0, -15.0))
    for i in range(12):
        p.frond((-3.5, 4.1, -15.0), i * 30, (50, 25, 0)[i % 3], 1.8, 0.9, "sabal_frond", droop=22, segs=2)
    p.box((1.0, 0.8, 0.04), (-4.0, 1.0, -0.6), "sign_white")
    p.box((0.06, 1.4, 0.06), (-4.0, 0.7, -0.65), "fence_wood")
    p.labels.append(("FOR SALE\nBY OWNER", (-4.0, 1.0, -0.57), 0))
    return p


PROPS = [
    royal_palm, coconut_palm, sabal_palm, banyan, live_oak,
    sea_grape, sea_grape_hedge, brush_clump, weeds_tall,
    hibiscus_bed, bougainvillea, flower_bed,
    sand_patch, dirt_patch, fallen_frond,
    garden_pond, retention_pond, canal_segment,
    chain_fence, block_wall, carport, wall_ac, window_ac, window_bars, storm_panel, satellite_dish,
    trash_bin, lambda: trash_bin("recycle_bin", "bin_blue", "Recycling bin"), laundry_line, above_ground_pool,
    screened_pool, lambda: screened_pool("screened_pool_small", 8.0, 6.5), pavers_patio, shopping_cart,
    graffiti_tag, mural, rust_streak,
    power_pole, lambda: power_pole("power_pole_transformer", True), bus_bench, bus_shelter, mailbox,
    mailbox_cluster, newspaper_boxes, overgrown_lot,
]

# Categories that must (True) / must not (False) carry collision; enforced here and in tests.
COLLISION_RULE = {"palms": True, "trees": True, "shrubs": False, "flowers": False, "ground": False,
                  "decals": False, "street": True, "lots": True}

# Seeded dressing rules per income tier (KitDressing). zone: front / back / side / any /
# front_edge / side_edge / back_edge / wall (non-front walls) / wall_any / wall_foot (ground bed
# along the front walls) / window (an opening) / back_attach (behind the back wall, needs room).
# count = [min, max]; chance = probability the rule fires at all; y = wall mount height range.
TIERS = {
    "low": [  # Tamarack: sandy yards, overgrowth, clutter, bars and window units, wear.
        {"prop": "sand_patch", "zone": "any", "count": [3, 6], "overlap": True},
        {"prop": "dirt_patch", "zone": "any", "count": [1, 3], "overlap": True},
        {"prop": "weeds_tall", "zone": "side_edge", "count": [2, 5]},
        {"prop": "brush_clump", "zone": "any", "count": [1, 3]},
        {"prop": "coconut_palm", "zone": "front", "count": [0, 1], "chance": 0.6},
        {"prop": "sabal_palm", "zone": "back", "count": [1, 2]},
        {"prop": "fallen_frond", "zone": "any", "count": [1, 3], "overlap": True},
        {"prop": "trash_bin", "zone": "side", "count": [1, 2]},
        {"prop": "shopping_cart", "zone": "any", "count": [1, 1], "chance": 0.35},
        {"prop": "laundry_line", "zone": "back", "count": [1, 1], "chance": 0.6},
        {"prop": "above_ground_pool", "zone": "back", "count": [1, 1], "chance": 0.25},
        {"prop": "window_ac", "zone": "window", "count": [1, 3]},
        {"prop": "window_bars", "zone": "window", "count": [2, 6], "chance": 0.75, "fit": True},
        {"prop": "wall_ac", "zone": "wall", "count": [0, 1], "y": [1.3, 1.6]},
        {"prop": "satellite_dish", "zone": "wall", "count": [1, 1], "chance": 0.7, "y": [2.4, 2.8]},
        {"prop": "rust_streak", "zone": "wall", "count": [1, 3], "y": [1.8, 2.6]},
        {"prop": "graffiti_tag", "zone": "wall", "count": [1, 1], "chance": 0.4, "y": [1.1, 1.4]},
    ],
    "medium": [  # Northgrove: tidy but plain; palms, sea grape, some flowers, a dish.
        {"prop": "sand_patch", "zone": "any", "count": [0, 2], "overlap": True},
        {"prop": "sabal_palm", "zone": "front", "count": [1, 2]},
        {"prop": "coconut_palm", "zone": "back", "count": [0, 1], "chance": 0.6},
        {"prop": "live_oak", "zone": "back", "count": [1, 1], "chance": 0.35},
        {"prop": "sea_grape", "zone": "side_edge", "count": [1, 3]},
        {"prop": "hibiscus_bed", "zone": "wall_foot", "count": [1, 2]},
        {"prop": "flower_bed", "zone": "front", "count": [0, 1], "chance": 0.5},
        {"prop": "fallen_frond", "zone": "any", "count": [0, 1], "overlap": True},
        {"prop": "trash_bin", "zone": "side", "count": [1, 1]},
        {"prop": "recycle_bin", "zone": "side", "count": [1, 1], "chance": 0.6},
        {"prop": "storm_panel", "zone": "window", "count": [1, 3], "chance": 0.3, "fit": True},
        {"prop": "satellite_dish", "zone": "wall", "count": [1, 1], "chance": 0.5, "y": [2.4, 2.8]},
        {"prop": "wall_ac", "zone": "wall", "count": [0, 1], "chance": 0.4, "y": [1.3, 1.6]},
        {"prop": "pavers_patio", "zone": "back", "count": [1, 1], "chance": 0.4},
        {"prop": "laundry_line", "zone": "back", "count": [1, 1], "chance": 0.2},
    ],
    "high": [  # Nicer homes: royal palms, beds, pavers, screened pool, hedges, a garden pond.
        {"prop": "royal_palm", "zone": "front_edge", "count": [2, 3]},
        {"prop": "coconut_palm", "zone": "back", "count": [1, 2]},
        {"prop": "screened_pool", "zone": "back_attach", "count": [1, 1], "alt": "screened_pool_small"},
        {"prop": "sea_grape_hedge", "zone": "side_edge", "count": [1, 2]},
        {"prop": "hibiscus_bed", "zone": "wall_foot", "count": [2, 3]},
        {"prop": "bougainvillea", "zone": "wall_foot", "count": [1, 2]},
        {"prop": "flower_bed", "zone": "front", "count": [1, 2]},
        {"prop": "garden_pond", "zone": "front", "count": [1, 1], "chance": 0.35},
        {"prop": "live_oak", "zone": "back", "count": [0, 1], "chance": 0.4},
        {"prop": "trash_bin", "zone": "side", "count": [1, 1]},
        {"prop": "recycle_bin", "zone": "side", "count": [1, 1]},
    ],
    "commercial": [  # Strips, stores, garages: palms at the edges, bins, carts, tags, murals, rust.
        {"prop": "sabal_palm", "zone": "front_edge", "count": [1, 2]},
        {"prop": "coconut_palm", "zone": "side_edge", "count": [0, 1], "chance": 0.5},
        {"prop": "brush_clump", "zone": "back", "count": [1, 2]},
        {"prop": "weeds_tall", "zone": "back_edge", "count": [1, 3]},
        {"prop": "sand_patch", "zone": "any", "count": [1, 3], "overlap": True},
        {"prop": "fallen_frond", "zone": "any", "count": [0, 2], "overlap": True},
        {"prop": "trash_bin", "zone": "side", "count": [1, 2]},
        {"prop": "shopping_cart", "zone": "any", "count": [1, 2], "chance": 0.5},
        {"prop": "newspaper_boxes", "zone": "front_edge", "count": [1, 1], "chance": 0.5},
        {"prop": "mural", "zone": "wall", "count": [1, 1], "chance": 0.35, "y": [2.0, 2.0], "min_wall": 7.0},
        {"prop": "graffiti_tag", "zone": "wall", "count": [1, 2], "chance": 0.7, "y": [1.0, 1.5]},
        {"prop": "rust_streak", "zone": "wall", "count": [1, 3], "y": [2.6, 3.4]},
        {"prop": "wall_ac", "zone": "wall", "count": [1, 2], "y": [2.2, 2.6]},
    ],
    "civic": [  # Bank, hospital, church: manicured royal palms, hedges and flower beds.
        {"prop": "royal_palm", "zone": "front_edge", "count": [2, 4]},
        {"prop": "sabal_palm", "zone": "side_edge", "count": [1, 2]},
        {"prop": "sea_grape_hedge", "zone": "side_edge", "count": [1, 2]},
        {"prop": "hibiscus_bed", "zone": "wall_foot", "count": [1, 3]},
        {"prop": "flower_bed", "zone": "front", "count": [1, 2]},
        {"prop": "live_oak", "zone": "back", "count": [0, 1], "chance": 0.5},
    ],
}


def build_all(root):
    from materials import material_table
    known = set(material_table())
    out = []
    for fn in PROPS:
        p = fn()
        want = COLLISION_RULE.get(p.category)
        if want is not None and bool(p.shapes) != want:
            raise ValueError("%s: collision %s breaks the %s rule" % (p.id, bool(p.shapes), p.category))
        unknown = {m for _, _, _, m in p.parts} - known
        if unknown:
            raise ValueError("%s: unknown materials %s" % (p.id, sorted(unknown)))
        os.makedirs(os.path.join(root, PROP_DIR, p.category), exist_ok=True)
        p.scene().save(os.path.join(root, p.path()))
        out.append(p)
    used = {r["prop"] for rules in TIERS.values() for r in rules} | {r["alt"] for rules in TIERS.values()
                                                                    for r in rules if "alt" in r}
    by_id = {p.id: p for p in out}
    missing = used - set(by_id)
    if missing:
        raise ValueError("dressing rules use unknown props: %s" % sorted(missing))
    for rules in TIERS.values():
        for r in rules:
            r["scene"] = "res://" + by_id[r["prop"]].path()
            if "alt" in r:
                r["alt_scene"] = "res://" + by_id[r["alt"]].path()
    data = {
        "comment": "Generated by tools/houses/props.py. Seeded West Palm Beach dressing rules per income "
                   "tier for KitDressing (scripts/world/houses/kit_dressing.gd). Tier 'auto' resolves from "
                   "the building's dress_tier metadata (census tier / building type).",
        "tiers": TIERS,
    }
    with open(os.path.join(root, DRESSING_JSON), "w", newline="\n") as fh:
        json.dump(data, fh, indent=1)
        fh.write("\n")
    return out


def mapping_entries(props):
    tiers = {}
    for t, rules in TIERS.items():
        for r in rules:
            tiers.setdefault(r["prop"], set()).add(t)
            if "alt" in r:
                tiers.setdefault(r["alt"], set()).add(t)
    return {p.id: {"name": p.label, "category": p.category, "scene": "res://" + p.path(),
                   "collision": bool(p.shapes), "mount": p.mount, "radius_m": p.radius,
                   "tiers": sorted(tiers.get(p.id, [])),
                   **({"ground_cut": list(p.cut)} if p.cut else {})} for p in props}
