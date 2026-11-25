"""Minimal Godot 4 text-scene (.tscn) writer for the vehicle generator.

Meshes, shapes and materials are written as sub_resources and de-duplicated by value, so a scene
with forty identical lug-nut boxes still only stores one BoxMesh."""
import math


def f(v):
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def v3(x, y, z):
    return "Vector3(%s, %s, %s)" % (f(x), f(y), f(z))


def color(c):
    r, g, b = c[:3]
    a = c[3] if len(c) > 3 else 1.0
    return "Color(%s, %s, %s, %s)" % (f(r), f(g), f(b), f(a))


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def basis(rot_deg=(0.0, 0.0, 0.0)):
    """Godot's default YXZ Euler order: basis = Ry * Rx * Rz (angles in degrees)."""
    rx, ry, rz = (math.radians(a) for a in rot_deg)
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    X = ((1, 0, 0), (0, cx, -sx), (0, sx, cx))
    Y = ((cy, 0, sy), (0, 1, 0), (-sy, 0, cy))
    Z = ((cz, -sz, 0), (sz, cz, 0), (0, 0, 1))

    def mul(a, b):
        return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))

    return mul(mul(Y, X), Z)


def xform(pos=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0)):
    m = basis(rot)
    # Transform3D(xx, xy, xz, yx, yy, yz, zx, zy, zz, ox, oy, oz) lists the basis columns.
    vals = (m[0][0], m[1][0], m[2][0], m[0][1], m[1][1], m[2][1], m[0][2], m[1][2], m[2][2]) + tuple(pos)
    return "Transform3D(%s)" % ", ".join(f(v) for v in vals)


def quote(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


class Scene:
    def __init__(self):
        self.ext = []  # (type, path, id)
        self._ext_ids = {}
        self.subs = []  # (type, id, props)
        self._sub_ids = {}
        self.nodes = []  # (header, props)
        self._names = {}

    def res(self, path, rtype="Resource"):
        if path not in self._ext_ids:
            rid = "%d_r" % (len(self.ext) + 1)
            self._ext_ids[path] = rid
            self.ext.append((rtype, path, rid))
        return 'ExtResource("%s")' % self._ext_ids[path]

    def sub(self, rtype, props):
        key = (rtype, tuple(sorted(props.items())))
        if key not in self._sub_ids:
            rid = "%s_%d" % (rtype, len(self.subs) + 1)
            self._sub_ids[key] = rid
            self.subs.append((rtype, rid, props))
        return 'SubResource("%s")' % self._sub_ids[key]

    def _unique(self, parent, name):
        key = (parent, name)
        n = self._names.get(key, 0)
        self._names[key] = n + 1
        return name if n == 0 else "%s%d" % (name, n + 1)

    def node(self, name, ntype=None, parent=None, props=None, instance=None):
        """Adds a node; returns its path relative to the root (for use as a parent)."""
        if parent is None:
            self.nodes.append(('[node name="%s" type="%s"]' % (name, ntype), props or {}))
            return "."
        name = self._unique(parent, name)
        if instance:
            header = '[node name="%s" parent="%s" instance=%s]' % (name, parent, self.res(instance, "PackedScene"))
        else:
            header = '[node name="%s" type="%s" parent="%s"]' % (name, ntype, parent)
        self.nodes.append((header, props or {}))
        return name if parent == "." else parent + "/" + name

    def text(self):
        out = ["[gd_scene load_steps=%d format=3]" % (len(self.ext) + len(self.subs) + 1), ""]
        for rtype, path, rid in self.ext:
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (rtype, path, rid))
        if self.ext:
            out.append("")
        for rtype, rid, props in self.subs:
            out.append('[sub_resource type="%s" id="%s"]' % (rtype, rid))
            for k, v in props.items():
                out.append("%s = %s" % (k, v))
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
