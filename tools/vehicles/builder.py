"""Primitive geometry and node helpers for one generated vehicle scene.

Axes follow the game's Vehicle: +Z is forward, +Y is up, +X is the driver's (left) side. The body
origin sits on the ground plane, so every y below is a height above the road when the car is at
rest on its suspension."""
import math

from tscn import Scene, basis, color, f, hex_rgb, quote, v3, xform

# Material library: name -> StandardMaterial3D props. "paint" / "paint2" are recoloured per spawn.
MATERIALS = {
    "glass": {"transparency": "1", "albedo_color": color((0.08, 0.11, 0.14, 0.55)), "metallic": "0.6", "roughness": "0.08"},
    "chrome": {"albedo_color": color((0.86, 0.87, 0.9)), "metallic": "1.0", "roughness": "0.14"},
    "black": {"albedo_color": color((0.05, 0.05, 0.055)), "roughness": "0.75"},
    "plastic": {"albedo_color": color((0.12, 0.12, 0.13)), "roughness": "0.85"},
    "tire": {"albedo_color": color((0.03, 0.03, 0.03)), "roughness": "0.95"},
    "rim": {"albedo_color": color((0.55, 0.56, 0.6)), "metallic": "0.8", "roughness": "0.3"},
    "gold": {"albedo_color": color((0.95, 0.72, 0.25)), "metallic": "1.0", "roughness": "0.2"},
    "whitewall": {"albedo_color": color((0.92, 0.92, 0.88)), "roughness": "0.7"},
    "interior": {"albedo_color": color((0.16, 0.14, 0.13)), "roughness": "0.9"},
    "leather": {"albedo_color": color((0.55, 0.38, 0.22)), "roughness": "0.6"},
    "white": {"albedo_color": color((0.93, 0.93, 0.92)), "roughness": "0.45"},
    "yellow": {"albedo_color": color((0.98, 0.78, 0.08)), "roughness": "0.45"},
    "red": {"albedo_color": color((0.78, 0.06, 0.05)), "roughness": "0.45"},
    "blue": {"albedo_color": color((0.06, 0.18, 0.55)), "roughness": "0.45"},
    "orange": {"albedo_color": color((0.95, 0.45, 0.08)), "roughness": "0.5"},
    "green": {"albedo_color": color((0.12, 0.45, 0.22)), "roughness": "0.5"},
    "steel": {"albedo_color": color((0.42, 0.44, 0.46)), "metallic": "0.7", "roughness": "0.45"},
    "rust": {"albedo_color": color((0.45, 0.22, 0.1)), "roughness": "0.95"},
    "primer": {"albedo_color": color((0.5, 0.5, 0.48)), "roughness": "0.95"},
    "wood": {"albedo_color": color((0.5, 0.32, 0.16)), "roughness": "0.8"},
    "canvas": {"albedo_color": color((0.3, 0.32, 0.22)), "roughness": "0.95"},
    "headlight": {"albedo_color": color((1.0, 0.97, 0.85)), "emission_enabled": "true",
                  "emission": color((1.0, 0.95, 0.8)), "emission_energy_multiplier": "1.2"},
    "taillight": {"albedo_color": color((0.8, 0.05, 0.04)), "emission_enabled": "true",
                  "emission": color((0.9, 0.05, 0.03)), "emission_energy_multiplier": "0.8"},
    "amber": {"albedo_color": color((1.0, 0.55, 0.05)), "emission_enabled": "true",
              "emission": color((1.0, 0.5, 0.0)), "emission_energy_multiplier": "0.8"},
    "siren_red": {"albedo_color": color((1.0, 0.08, 0.05)), "emission_enabled": "true",
                  "emission": color((1.0, 0.05, 0.03)), "emission_energy_multiplier": "2.0"},
    "siren_blue": {"albedo_color": color((0.1, 0.25, 1.0)), "emission_enabled": "true",
                   "emission": color((0.1, 0.3, 1.0)), "emission_energy_multiplier": "2.0"},
    "sign": {"albedo_color": color((1.0, 0.92, 0.4)), "emission_enabled": "true",
             "emission": color((1.0, 0.85, 0.3)), "emission_energy_multiplier": "0.6"},
    "neon": {"albedo_color": color((0.9, 0.1, 0.9)), "emission_enabled": "true",
             "emission": color((0.9, 0.1, 1.0)), "emission_energy_multiplier": "1.5"},
}
PAINT_SLOTS = {"paint": "primary", "paint2": "secondary"}
# Node names that are painted-on livery (stripes, panels, lettering): never allowed over the glass.
DECAL_NAMES = ("Stripe", "SidePanel", "Livery", "RearLivery")


def _transform_points(points, pos, rot):
    m = basis(rot)
    return [tuple(sum(m[i][k] * p[k] for k in range(3)) + pos[i] for i in range(3)) for p in points]


def _hull(points):
    """Convex hull (counter-clockwise) of 2D points."""
    pts = sorted(set((round(a, 5), round(b, 5)) for a, b in points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def hull_distance(hull, p):
    """Distance from 2D point `p` to a convex polygon (0 inside)."""
    n = len(hull)
    if n == 0:
        return float("inf")
    inside = n >= 3
    best = float("inf")
    for i in range(n):
        a, b = hull[i], hull[(i + 1) % n]
        ex, ey = b[0] - a[0], b[1] - a[1]
        if ex * (p[1] - a[1]) - ey * (p[0] - a[0]) < 0:
            inside = False
        seg = ex * ex + ey * ey
        t = 0.0 if seg < 1e-12 else max(0.0, min(1.0, ((p[0] - a[0]) * ex + (p[1] - a[1]) * ey) / seg))
        best = min(best, math.hypot(p[0] - a[0] - t * ex, p[1] - a[1] - t * ey))
    return 0.0 if inside else best


def clip_z(poly, z0, z1):
    """Clip a 2D (z, y) polygon to z0 <= z <= z1 (Sutherland-Hodgman against two half-planes)."""
    def clip(points, inside, cut):
        out = []
        for i, cur in enumerate(points):
            prev = points[i - 1]
            if inside(cur):
                if not inside(prev):
                    out.append(cut(prev, cur))
                out.append(cur)
            elif inside(prev):
                out.append(cut(prev, cur))
        return out

    def at(zc):
        def cut(a, b):
            t = (zc - a[0]) / (b[0] - a[0])
            return (zc, a[1] + t * (b[1] - a[1]))
        return cut

    poly = clip(list(poly), lambda p: p[0] >= z0, at(z0))
    return clip(poly, lambda p: p[0] <= z1, at(z1)) if poly else []


class Part:
    """Vehicle-space footprint of one mesh: x range, side-view (z, y) hull and interior sample points."""

    def __init__(self, name, corners, samples=()):
        self.name = name
        xs = [c[0] for c in corners]
        self.x0, self.x1 = min(xs), max(xs)
        self.zy = _hull([(c[2], c[1]) for c in corners])
        self.samples = list(samples)

    def touches(self, p, tol):
        return self.x0 - tol <= p[0] <= self.x1 + tol and hull_distance(self.zy, (p[2], p[1])) <= tol


def _box_part(name, size, pos, rot, margin=0.015):
    hx, hy, hz = (s / 2 for s in size)
    corners = _transform_points([(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)],
                                pos, rot)

    def axis(h):
        inner = h - margin if h > margin * 1.5 else 0.0
        return [-inner + 2 * inner * i / 6 for i in range(7)] if inner > 0 else [0.0]

    samples = _transform_points([(a, b, c) for a in axis(hx) for b in axis(hy) for c in axis(hz)], pos, rot)
    return Part(name, corners, samples)


class VehicleBuilder:
    def __init__(self, spec):
        self.spec = spec
        self.sc = Scene()
        self.paint = spec["palette"][0]
        self.paint2 = spec.get("trim_palette", ["#1a1a1c"])[0]
        drivable = spec.get("drivable", True)
        root_props = {}
        if drivable:
            root_props["script"] = self.sc.res("res://scripts/vehicles/vehicle.gd", "Script")
        self.root = self.sc.node(spec["scene_name"], "VehicleBody3D" if drivable else "StaticBody3D", None, root_props)
        self.root_props = root_props
        self.body = self.sc.node("Body", "Node3D", ".")
        self.wheels = []
        self.shapes = []
        self.glass_zones = []
        self.decals = []

    # --- glass vs livery ------------------------------------------------------------------------

    GLASS_TOL = 0.03

    def glass_zone(self, name, x0, x1, poly):
        """Register a see-through region: x range plus a side-view (z, y) polygon."""
        if len(poly) >= 3:
            self.glass_zones.append(Part(name, [(x0, y, z) for z, y in poly] + [(x1, y, z) for z, y in poly]))

    def over_glass(self, p, tol=None):
        tol = self.GLASS_TOL if tol is None else tol
        return any(z.touches(p, tol) for z in self.glass_zones)

    def decal_conflicts(self):
        """[(decal name, glass name)] for every painted-on decal that lies over a window."""
        hits = []
        for d in self.decals:
            for z in self.glass_zones:
                if any(z.touches(p, self.GLASS_TOL) for p in d.samples):
                    hits.append((d.name, z.name))
                    break
        return hits

    # --- materials ------------------------------------------------------------------------

    def mat(self, name):
        if name in PAINT_SLOTS:
            hexcol = self.paint if name == "paint" else self.paint2
            props = {"albedo_color": color(hex_rgb(hexcol)), "metallic": "0.35", "roughness": "0.32",
                     "resource_name": quote(name)}
            if self.spec.get("matte"):
                props.update({"metallic": "0.0", "roughness": "0.85"})
        else:
            props = dict(MATERIALS[name])
            props["resource_name"] = quote(name)
        return self.sc.sub("StandardMaterial3D", props)

    def _mesh_node(self, name, mesh, pos, rot, material, parent):
        props = {"transform": xform(pos, rot), "mesh": mesh}
        if material in PAINT_SLOTS:
            props["metadata/paint"] = quote(PAINT_SLOTS[material])
        return self.sc.node(name, "MeshInstance3D", parent or self.body, props)

    # --- primitives -------------------------------------------------------------------------

    def box(self, name, size, pos, material, rot=(0, 0, 0), parent=None, mirror=False):
        """Box of `size` centred on `pos`. mirror=True also places one at -x."""
        if min(size) <= 0.0:
            return
        mesh = self.sc.sub("BoxMesh", {"material": self.mat(material), "size": v3(*size)})
        self._mesh_node(name, mesh, pos, rot, material, parent)
        if mirror:
            self._mesh_node(name, mesh, (-pos[0], pos[1], pos[2]), (rot[0], -rot[1], -rot[2]), material, parent)
        if parent is None:
            placed = [(pos, rot)] + ([((-pos[0], pos[1], pos[2]), (rot[0], -rot[1], -rot[2]))] if mirror else [])
            for p, r in placed:
                if name in DECAL_NAMES:
                    self.decals.append(_box_part(name, size, p, r))
                elif material == "glass" and name != "Glass":
                    # car() registers its greenhouse zones itself (with the roof and panels cut out).
                    part = _box_part(name, size, p, r)
                    self.glass_zones.append(part)

    def span(self, name, x0, x1, y0, y1, z0, z1, material, parent=None):
        """Axis-aligned box from corner ranges."""
        self.box(name, (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
                 material, parent=parent)

    def cyl(self, name, radius, height, pos, material, rot=(0, 0, 0), sides=16, parent=None, mirror=False, top=None):
        props = {"material": self.mat(material), "top_radius": f(radius if top is None else top),
                 "bottom_radius": f(radius), "height": f(height), "radial_segments": str(sides), "rings": "1"}
        mesh = self.sc.sub("CylinderMesh", props)
        self._mesh_node(name, mesh, pos, rot, material, parent)
        if mirror:
            self._mesh_node(name, mesh, (-pos[0], pos[1], pos[2]), rot, material, parent)

    def sphere(self, name, radius, pos, material, parent=None, mirror=False, height=None):
        mesh = self.sc.sub("SphereMesh", {"material": self.mat(material), "radius": f(radius),
                                          "height": f(height or radius * 2), "radial_segments": "16", "rings": "8"})
        self._mesh_node(name, mesh, pos, (0, 0, 0), material, parent)
        if mirror:
            self._mesh_node(name, mesh, (-pos[0], pos[1], pos[2]), (0, 0, 0), material, parent)

    def wedge(self, name, z_vert, z_end, y0, y1, width, material, x=0.0, flip=False, parent=None):
        """Right-triangle profile extruded across `width`: a vertical edge at z_vert from y0 to y1,
        sloping down to (z_end, y0). flip=True hangs it upside down (vertical edge at y0..y1, the
        slope rising from (z_end, y1))."""
        length = abs(z_end - z_vert)
        if length < 1e-3 or abs(y1 - y0) < 1e-3:
            return
        # PrismMesh's triangle lies in local XY; yaw 90 puts local +X on world -Z and extrudes along X.
        ltr = 1.0 if z_vert < z_end else 0.0
        rot = (0, 90, 0)
        if flip:
            ltr = 1.0 - ltr
            rot = (0, 90, 180)
        mesh = self.sc.sub("PrismMesh", {"material": self.mat(material), "left_to_right": f(ltr),
                                         "size": v3(length, abs(y1 - y0), width)})
        self._mesh_node(name, mesh, (x, (y0 + y1) / 2, (z_vert + z_end) / 2), rot, material, parent)

    def profile(self, name, points, bottom, width, material, x=0.0):
        """Solid whose side outline is the polyline `points` [(z, top_y), ...] over a flat bottom."""
        for (za, ya), (zb, yb) in zip(points, points[1:]):
            z0, z1 = min(za, zb), max(za, zb)
            lo = min(ya, yb)
            if lo > bottom:
                self.box(name, (width, lo - bottom, z1 - z0), (x, (bottom + lo) / 2, (z0 + z1) / 2), material)
            if abs(ya - yb) > 1e-3:
                zv, ze = (za, zb) if ya > yb else (zb, za)
                self.wedge(name, zv, ze, lo, max(ya, yb), width, material, x=x)

    def strut(self, name, p0, p1, thick, material, mirror=False, depth=None):
        """Box running from p0 to p1 (its long axis), `thick` across, `depth` deep."""
        dx, dy, dz = (p1[i] - p0[i] for i in range(3))
        length = math.sqrt(dx * dx + dy * dy + dz * dz)
        if length < 1e-4:
            return
        pitch = math.degrees(math.asin(-dy / length))
        yaw = math.degrees(math.atan2(dx, dz))
        mid = tuple((p0[i] + p1[i]) / 2 for i in range(3))
        self.box(name, (thick, depth or thick, length), mid, material, rot=(pitch, yaw, 0), mirror=mirror)

    # --- physics / gameplay nodes ----------------------------------------------------------

    def shape(self, name, size, pos, rot=(0, 0, 0)):
        shape = self.sc.sub("BoxShape3D", {"size": v3(*size)})
        self.shapes.append((size, pos))
        self.sc.node(name, "CollisionShape3D", ".", {"transform": xform(pos, rot), "shape": shape})

    def marker(self, name, pos, parent="."):
        return self.sc.node(name, "Marker3D", parent, {"transform": xform(pos)})

    def wheel(self, name, x, z, radius, width, steer, drive, style="rim", rest=0.25, travel=None, rim_ratio=0.62,
              hidden=False, visual_x=None, sag=0.0):
        """VehicleWheel3D hung so its tyre touches the ground (y = 0) once the suspension has
        compressed by `sag` under the car's weight."""
        y = radius + rest - sag
        h = self.spec["handling"]
        grip = h["grip"] * (h.get("rear_grip", 1.0) if z < 0 else 1.0)
        props = {
            "transform": xform((x, y, z)),
            "use_as_traction": "true" if drive else "false",
            "use_as_steering": "true" if steer else "false",
            "wheel_roll_influence": f(h.get("roll", 0.1)),
            "wheel_radius": f(radius),
            "wheel_rest_length": f(rest),
            "wheel_friction_slip": f(grip),
            "suspension_travel": f(travel if travel is not None else rest),
            "suspension_stiffness": f(h.get("stiffness", 60.0)),
            "suspension_max_force": f(self.spec["mass"] * 9.8 * 4.0 / max(2, self.spec.get("wheel_count", 4))),
            "damping_compression": f(h.get("damp_c", 1.6)),
            "damping_relaxation": f(h.get("damp_r", 2.2)),
        }
        path = self.sc.node(name, "VehicleWheel3D", ".", props)
        self.wheels.append((name, x, z, radius, steer, drive))
        if hidden:
            return path
        vx = 0.0 if visual_x is None else visual_x - x
        side = 1 if x >= 0 else -1
        # Tyre and rim are children of the wheel so they spin and steer with it.
        self.cyl("Tire", radius, width, (vx, 0, 0), "tire", rot=(0, 0, 90), sides=20, parent=path)
        if style == "wire":
            self.cyl("Whitewall", radius * 0.82, width + 0.01, (vx, 0, 0), "whitewall", rot=(0, 0, 90), sides=20, parent=path)
            self.cyl("Rim", radius * rim_ratio, width + 0.02, (vx, 0, 0), "chrome", rot=(0, 0, 90), sides=16, parent=path)
            for i in range(6):
                self.box("Spoke", (0.02, radius * rim_ratio * 1.8, 0.02), (vx + side * (width / 2 + 0.012), 0, 0), "chrome",
                         rot=(i * 30, 0, 0), parent=path)
        elif style == "donk":
            self.cyl("Rim", radius * rim_ratio, width + 0.02, (vx, 0, 0), "chrome", rot=(0, 0, 90), sides=24, parent=path)
            self.cyl("Lip", radius * rim_ratio * 0.72, width + 0.04, (vx, 0, 0), "gold" if self.spec.get("gold_rims") else "black",
                     rot=(0, 0, 90), sides=24, parent=path)
            for i in range(5):
                self.box("Spoke", (0.03, radius * rim_ratio * 1.6, 0.05), (vx + side * (width / 2 + 0.02), 0, 0), "chrome",
                         rot=(i * 36, 0, 0), parent=path)
        else:
            rim_mat = {"rim": "rim", "chrome": "chrome", "steel": "steel", "black": "plastic"}[style]
            self.cyl("Rim", radius * rim_ratio, width + 0.02, (vx, 0, 0), rim_mat, rot=(0, 0, 90), sides=12, parent=path)
            self.box("Hub", (0.03, radius * rim_ratio * 1.3, 0.05), (vx + side * (width / 2 + 0.012), 0, 0), "plastic",
                     parent=path)
            self.box("Hub", (0.03, 0.05, radius * rim_ratio * 1.3), (vx + side * (width / 2 + 0.012), 0, 0), "plastic",
                     parent=path)
        return path

    def wheel_well(self, x_side, z, radius, y_floor):
        """Black disc behind a tyre so the body reads as having a wheel arch."""
        self.cyl("WheelWell", radius + 0.07, 0.02, (x_side, radius, z), "black", rot=(0, 0, 90), sides=20)

    def label(self, name, text, pos, rot=(0, 0, 0), size=0.006, col=(1, 1, 1), font=64, outline=10,
              outline_col=(0, 0, 0)):
        self.sc.node(name, "Label3D", self.body, {
            "transform": xform(pos, rot), "pixel_size": f(size), "double_sided": "false",
            "modulate": color(col), "outline_modulate": color(outline_col), "text": quote(text),
            "font_size": str(font), "outline_size": str(outline)})
        if name in DECAL_NAMES:
            # Rough text extent of the default font (~0.55 em per glyph, 1.2 em per line).
            lines = text.split("\n")
            hw = max(len(line) for line in lines) * font * size * 0.55 / 2 * 0.85
            hh = len(lines) * font * size * 1.2 / 2 * 0.85
            local = [(-hw + 2 * hw * i / 8, -hh + 2 * hh * j / 4, 0.0) for i in range(9) for j in range(5)]
            corners = [(sx * hw, sy * hh, 0.0) for sx in (-1, 1) for sy in (-1, 1)]
            self.decals.append(Part(name, _transform_points(corners, pos, rot), _transform_points(local, pos, rot)))

    def side_label(self, name, text, y, z, half_width, **kw):
        """The same decal on both flanks, readable from outside the vehicle."""
        self.label(name, text, (half_width + 0.012, y, z), (0, 90, 0), **kw)
        self.label(name, text, (-half_width - 0.012, y, z), (0, -90, 0), **kw)

    # --- output ---------------------------------------------------------------------------------

    def save(self, path, root_props):
        self.sc.nodes[0][1].update(root_props)
        self.sc.save(path)
