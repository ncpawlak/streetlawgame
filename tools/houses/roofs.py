"""Roof builders. A roof sits on a rectangle (cross span x ridge-axis span) at eave height e.

Cross-section coordinates are (u, y), where u is measured from the centre of the cross span
toward +X (ridge axis 'z') or toward +Z (ridge axis 'x'); see tscn.prism."""
from tscn import INTERSECT, SUBTRACT, box, combiner, prism

OVERHANG = 0.45
RAKE = 0.3
SLAB = 0.22


def _slab(top, tv):
    return top + [(u, y - tv) for u, y in reversed(top)]


def rect_axes(x0, x1, z0, z1, axis):
    """-> (c, hw, a0, a1): cross centre/half width and ridge-axis span."""
    if axis == "z":
        return (x0 + x1) / 2, (x1 - x0) / 2, z0, z1
    return (z0 + z1) / 2, (z1 - z0) / 2, x0, x1


def ridge_height(r, x0, x1, z0, z1, e):
    t = r["t"]
    p = r.get("pitch", 0.5)
    if t == "gable":
        _, hw, _, _ = rect_axes(x0, x1, z0, z1, r.get("axis", "x"))
        return e + 2 * hw * r.get("ridge", 0.5) * p
    if t == "hip":
        return e + min(x1 - x0, z1 - z0) / 2 * p
    if t == "shed":
        _, hw, _, _ = rect_axes(x0, x1, z0, z1, _shed_axis(r))
        return e + 2 * hw * p
    return e + 0.6


def gable(sc, parent, name, x0, x1, z0, z1, e, r, roof_mat, wall_mat):
    axis = r.get("axis", "x")
    p = r.get("pitch", 0.5)
    o = r.get("overhang", OVERHANG)
    rake = r.get("rake", RAKE)
    c, hw, a0, a1 = rect_axes(x0, x1, z0, z1, axis)
    xr = -hw + 2 * hw * r.get("ridge", 0.5)
    hr = e + (xr + hw) * p
    pr = (hr - e) / (hw - xr)
    top = [(-hw - o, e - o * p), (xr, hr), (hw + o, e - o * pr)]
    prism(sc, parent, name, _slab(top, SLAB), axis, a0 - rake, a1 + rake, c, "%s_%s" % (roof_mat, axis))
    if r.get("fill", True):
        fill = [(-hw, e - 0.05), (xr, hr - 0.03), (hw, e - 0.05)]
        prism(sc, parent, name + "Gable", fill, axis, a0, a1, c, wall_mat)
    return hr


def hip(sc, parent, name, x0, x1, z0, z1, e, r, roof_mat):
    p = r.get("pitch", 0.5)
    o = r.get("overhang", OVERHANG)
    fascia = 0.2
    b = e - o * p
    sub = combiner(sc, parent, name)
    axis = "x" if (x1 - x0) >= (z1 - z0) else "z"
    other = "z" if axis == "x" else "x"
    for i, ax in enumerate((axis, other)):
        c, hw, a0, a1 = rect_axes(x0, x1, z0, z1, ax)
        pts = [(-hw - o, b - fascia), (hw + o, b - fascia), (hw + o, b),
               (0, b + (hw + o) * p), (-hw - o, b)]
        prism(sc, sub, "Hip" + ax.upper(), pts, ax, a0 - o, a1 + o, c,
              "%s_%s" % (roof_mat, ax), INTERSECT if i else None)
    return e + min(x1 - x0, z1 - z0) / 2 * p


def _shed_axis(r):
    return "x" if r.get("high", "back") in ("front", "back") else "z"


def shed(sc, parent, name, x0, x1, z0, z1, e, r, roof_mat, wall_mat):
    """Single slope; r['high'] names the tall side."""
    axis = _shed_axis(r)
    p = r.get("pitch", 0.25)
    o = r.get("overhang", OVERHANG)
    rake = r.get("rake", RAKE)
    c, hw, a0, a1 = rect_axes(x0, x1, z0, z1, axis)
    up = 1 if r.get("high", "back") in ("front", "right") else -1
    lo_e, hi_e = e, e + 2 * hw * p
    if up > 0:
        top = [(-hw - o, lo_e - o * p), (hw + o, hi_e + o * p)]
        fill = [(-hw, e - 0.05), (hw, e - 0.05), (hw, hi_e - 0.03), (-hw, e - 0.02)]
    else:
        top = [(-hw - o, hi_e + o * p), (hw + o, lo_e - o * p)]
        fill = [(-hw, e - 0.05), (hw, e - 0.05), (hw, e - 0.02), (-hw, hi_e - 0.03)]
    prism(sc, parent, name, _slab(top, SLAB), axis, a0 - rake, a1 + rake, c, "%s_%s" % (roof_mat, axis))
    if r.get("fill", True):
        prism(sc, parent, name + "Fill", fill, axis, a0, a1, c, wall_mat)
    return hi_e


def flat(sc, parent, name, x0, x1, z0, z1, e, r, wall_mat, trim_mat):
    """Parapet with coping around a membrane roof."""
    sub = combiner(sc, parent, name)
    h = r.get("parapet", 0.6)
    box(sc, sub, "Parapet", x0, x1, e - 0.1, e + h, z0, z1, wall_mat)
    box(sc, sub, "Coping", x0 - 0.06, x1 + 0.06, e + h, e + h + 0.08, z0 - 0.06, z1 + 0.06, trim_mat)
    box(sc, sub, "Inside", x0 + 0.25, x1 - 0.25, e, e + h + 0.5, z0 + 0.25, z1 - 0.25, None, SUBTRACT)
    box(sc, sub, "Membrane", x0 + 0.24, x1 - 0.24, e - 0.05, e + 0.02, z0 + 0.24, z1 - 0.24, "roof_flat")
    return e + h


def flat_overhang(sc, parent, name, x0, x1, z0, z1, e, r, trim_mat):
    """Thin modern roof plate with a deep overhang."""
    o = r.get("overhang", 0.6)
    sub = combiner(sc, parent, name)
    box(sc, sub, "Plate", x0 - o, x1 + o, e, e + 0.3, z0 - o, z1 + o, trim_mat)
    box(sc, sub, "Membrane", x0 - o + 0.08, x1 + o - 0.08, e + 0.3, e + 0.33, z0 - o + 0.08, z1 + o - 0.08, "roof_flat")
    return e + 0.33


def build(sc, parent, name, x0, x1, z0, z1, e, r, roof_mat, wall_mat, trim_mat):
    t = r["t"]
    if t == "gable":
        return gable(sc, parent, name, x0, x1, z0, z1, e, r, roof_mat, wall_mat)
    if t == "hip":
        return hip(sc, parent, name, x0, x1, z0, z1, e, r, roof_mat)
    if t == "shed":
        return shed(sc, parent, name, x0, x1, z0, z1, e, r, roof_mat, wall_mat)
    if t == "flat":
        return flat(sc, parent, name, x0, x1, z0, z1, e, r, wall_mat, trim_mat)
    if t == "flatover":
        return flat_overhang(sc, parent, name, x0, x1, z0, z1, e, r, trim_mat)
    raise ValueError(t)
