"""Minimal Godot 4 text-scene (.tscn) writer used by the house generator."""
import math

from materials import mat


def f(v):
    s = ("%.3f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def v2(x, y):
    return "Vector2(%s, %s)" % (f(x), f(y))


def v3(x, y, z):
    return "Vector3(%s, %s, %s)" % (f(x), f(y), f(z))


def xform(pos, yaw=0.0, scale=(1.0, 1.0, 1.0)):
    """Transform3D with a yaw (degrees, about +Y), per-axis scale and an origin."""
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    sx, sy, sz = scale
    vals = (c * sx, 0, s * sz, 0, sy, 0, -s * sx, 0, c * sz) + tuple(pos)
    return "Transform3D(%s)" % ", ".join(f(v) for v in vals)


def poly(points):
    return "PackedVector2Array(%s)" % ", ".join("%s, %s" % (f(x), f(y)) for x, y in points)


class Scene:
    def __init__(self, uid_hint=""):
        self.ext = []  # (type, path, id)
        self._ext_ids = {}
        self.nodes = []  # (header, props)
        self._names = {}

    def res(self, path, rtype="Resource"):
        if path not in self._ext_ids:
            rid = "%d_r" % (len(self.ext) + 1)
            self._ext_ids[path] = rid
            self.ext.append((rtype, path, rid))
        return 'ExtResource("%s")' % self._ext_ids[path]

    def mat(self, name):
        return self.res(mat(name), "Material")

    def _unique(self, parent, name):
        key = (parent, name)
        n = self._names.get(key, 0)
        self._names[key] = n + 1
        return name if n == 0 else "%s%d" % (name, n + 1)

    def node(self, name, ntype=None, parent=None, props=None, instance=None):
        """Adds a node; returns its path relative to the root (for use as a parent)."""
        if parent is None:
            header = '[node name="%s" type="%s"]' % (name, ntype)
            self.nodes.append((header, props or {}))
            return "."
        name = self._unique(parent, name)
        if instance:
            header = '[node name="%s" parent="%s" instance=%s]' % (name, parent, self.res(instance, "PackedScene"))
        else:
            header = '[node name="%s" type="%s" parent="%s"]' % (name, ntype, parent)
        self.nodes.append((header, props or {}))
        return name if parent == "." else parent + "/" + name

    def text(self):
        out = ["[gd_scene load_steps=%d format=3]" % (len(self.ext) + 1), ""]
        for rtype, path, rid in self.ext:
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (rtype, path, rid))
        out.append("")
        for header, props in self.nodes:
            out.append(header)
            for k, v in props.items():
                out.append("%s = %s" % (k, v))
            out.append("")
        return "\n".join(out)

    def save(self, path):
        with open(path, "w", newline="\n") as fh:
            fh.write(self.text())


# --- CSG convenience -----------------------------------------------------------------------

def box(sc, parent, name, x0, x1, y0, y1, z0, z1, material, op=None):
    """Axis-aligned CSGBox3D spanning [x0,x1] x [y0,y1] x [z0,z1]."""
    props = {
        "transform": xform(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)),
        "size": v3(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)),
    }
    if op:
        props["operation"] = str(op)
    if material:
        props["material"] = sc.mat(material)
    return sc.node(name, "CSGBox3D", parent, props)


def prism(sc, parent, name, pts, axis, a0, a1, c, material, op=None):
    """Extrudes cross-section `pts` (u, y) along world `axis` ('x' or 'z') over [a0, a1].

    u is measured along the other horizontal axis from `c`, increasing toward +X (axis 'z')
    or toward +Z (axis 'x')."""
    if axis == "z":
        tr = xform((c, 0, a1))
        p = pts
    else:
        # yaw +90: local +X -> world -Z, local -Z -> world -X. Flip u so it grows toward +Z.
        tr = xform((a1, 0, c), 90)
        p = [(-u, y) for u, y in reversed(pts)]
    props = {"transform": tr, "polygon": poly(p), "depth": f(a1 - a0)}
    if op:
        props["operation"] = str(op)
    if material:
        props["material"] = sc.mat(material)
    return sc.node(name, "CSGPolygon3D", parent, props)


def combiner(sc, parent, name, collision=False, op=None):
    props = {}
    if collision:
        props["use_collision"] = "true"
    if op:
        props["operation"] = str(op)
    return sc.node(name, "CSGCombiner3D", parent, props)


INTERSECT = 1
SUBTRACT = 2
