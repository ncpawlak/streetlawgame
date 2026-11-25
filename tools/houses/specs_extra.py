"""Phase 2: every remaining North End census archetype (data/areas/north_end_buildings.json and
docs/design/NORTH_END_BUILDINGS.md on the census branch). Names, footprints and lot sizes come from
the census; the gas station follows its actual Gas-N-Go placement (24 x 36 lot, 21 x 32 box).

Same lot convention as the other specs: origin = centre of the front property line, street +Z.
Each spec carries `folder` (scenes/buildings/<folder>/) and `archetype` (census id).

RESIDENTIAL  trailers (T-xx) and 3-storey walk-ups (A-xx)
SPECIAL      hospital and safehouses
LOCATIONS    the named specialized locations (hit / trap / stick-up targets)
PURCHASABLE  the 9 purchasable businesses (enterable, shop_type)
FOOD_SHOP    the enterable shop-below-flat-above stand-in (food)
"""
from specs_one import W

FLAT = {"t": "flat", "parapet": 0.5}
LOWGZ = {"t": "gable", "axis": "z", "pitch": 0.12}


# --- helpers -----------------------------------------------------------------------------
def _face_box(side, face, a0, a1, y0, y1, d0, d1, mat, name):
    """Box on a house wall face, d measured outward from the wall plane."""
    if side == "front":
        return (a0, a1, y0, y1, face + d0, face + d1, mat, name)
    if side == "back":
        return (a0, a1, y0, y1, face - d1, face - d0, mat, name)
    if side == "right":
        return (face + d0, face + d1, y0, y1, a0, a1, mat, name)
    return (face - d1, face - d0, y0, y1, a0, a1, mat, name)


def boards(side, face, ats, floor=0, mat="plywood"):
    """Plywood over house windows (HouseBuilder window: 1.1 x 1.5, sill at 1.3 m + 3 m per floor)."""
    y = 3.0 * floor
    return [_face_box(side, face, a - 0.72, a + 0.72, 1.18 + y, 2.95 + y, 0.16, 0.22, mat, "Boards") for a in ats]


def bars(side, face, ats, floor=0):
    """Burglar bars over house windows: frame plus vertical bars."""
    y, out = 3.0 * floor, []
    for a in ats:
        out.append(_face_box(side, face, a - 0.7, a + 0.7, 1.2 + y, 1.26 + y, 0.17, 0.23, "metal_dark", "BarRail"))
        out.append(_face_box(side, face, a - 0.7, a + 0.7, 2.86 + y, 2.92 + y, 0.17, 0.23, "metal_dark", "BarRail"))
        for k in range(8):
            b = a - 0.6 + k * (1.2 / 7)
            out.append(_face_box(side, face, b - 0.02, b + 0.02, 1.2 + y, 2.92 + y, 0.18, 0.22, "metal_dark", "Bar"))
    return out


def stairs(x0, x1, za, zb, y0, y1, mat="concrete", solid=True):
    """Straight flight along z from (za, y0) up to (zb, y1). Solid flights sit on the ground."""
    n = max(1, round((y1 - y0) / 0.2))
    rise, run = (y1 - y0) / n, (zb - za) / n
    out = []
    for i in range(n):
        za_, zb_ = za + run * i, za + run * (i + 1)
        top = y0 + rise * (i + 1)
        out.append((x0, x1, 0.0 if solid else top - 0.25, top, min(za_, zb_), max(za_, zb_), mat, "Step"))
    return out


def stairs_x(xa, xb, z0, z1, y0, y1, mat="concrete", solid=True):
    """Straight flight along x."""
    n = max(1, round((y1 - y0) / 0.2))
    rise, run = (y1 - y0) / n, (xb - xa) / n
    out = []
    for i in range(n):
        xa_, xb_ = xa + run * i, xa + run * (i + 1)
        top = y0 + rise * (i + 1)
        out.append((min(xa_, xb_), max(xa_, xb_), 0.0 if solid else top - 0.25, top, z0, z1, mat, "Step"))
    return out


def lot_fence(kind, hw, d, gaps=()):
    """Fence the whole lot; gaps = [(x0, x1)] openings on the front line."""
    out, cur = [], -hw + 0.1
    for g0, g1 in sorted(gaps):
        out.append((kind, cur, -0.3, g0, -0.3))
        cur = g1
    out.append((kind, cur, -0.3, hw - 0.1, -0.3))
    out += [(kind, -hw + 0.1, -0.3, -hw + 0.1, -d + 0.1), (kind, hw - 0.1, -0.3, hw - 0.1, -d + 0.1),
            (kind, -hw + 0.1, -d + 0.1, hw - 0.1, -d + 0.1)]
    return out


def trailer_bits(x0, x1, zf, zb, deck=None):
    """Skirting, tow hitch and a few utility boxes for a single-wide (long axis along z)."""
    out = [(x0 - 0.04, x1 + 0.04, 0.0, 0.42, zb - 0.04, zf + 0.04, "metal_grey", "Skirt"),
           ((x0 + x1) / 2 - 0.15, (x0 + x1) / 2 + 0.15, 0.22, 0.42, zf, zf + 1.5, "metal_dark", "Hitch"),
           ((x0 + x1) / 2 - 0.9, (x0 + x1) / 2 + 0.9, 0.22, 0.3, zf + 1.1, zf + 1.4, "metal_dark", "HitchBar"),
           (x0 - 0.5, x0 - 0.04, 0.0, 1.2, zb + 2.0, zb + 2.6, "metal_grey", "PropaneTank")]
    return out


# --- residential: trailers and walk-ups ---------------------------------------------------
TRAILER_NOTE = "Single-wide, long side along the lot, gravel pad"

RESIDENTIAL = [
    dict(id="T-01", name="Single-Wide", archetype="trailer_1f", folder="residential", floors=1, beds=2, baths=1,
         lot=(14, 24), lot_type=TRAILER_NOTE + ", side deck",
         wall="siding_white", roof="slate", door="door_white", trim="trim_white", muntins=False,
         wings=[W(-5.5, 4.5, 4, 16, roof=LOWGZ, win={"front": [-3.25], "back": [-3.25],
                                                     "right": [-6.5, -14, -17.5], "left": [-7, -12, -17]})],
         doors=[dict(side="right", at=-10.2, stoop=False)],
         porches=[dict(rect=(-1, 2.2, -12, -8.4), out="right", roof=None, steps=[("right", -10.2)])],
         blocks=trailer_bits(-5.5, -1, -4, -20),
         paving=[(2.6, 5.8, -16, 0, "gravel")],
         fences=[("chain", -6.9, -21, -6.9, -23.9), ("chain", -6.9, -23.9, 6.9, -23.9), ("chain", 6.9, -23.9, 6.9, -18)],
         trees=[(4.2, -20.5, 1.0)], shrubs=[(-6.2, -2.2, 0.5)], mailbox=(2.2, -0.4), ac=(-6.3, -15)),

    dict(id="T-02", name="Single-Wide with Carport", archetype="trailer_1f", folder="residential", floors=1,
         beds=3, baths=2, lot=(14, 24), lot_type=TRAILER_NOTE + ", metal carport alongside",
         wall="siding_tan", roof="brown", door="door_wood", trim="trim_brown", muntins=False,
         wings=[W(-6.4, 4.5, 6, 16, roof=LOWGZ, win={"front": [-4.15], "back": [-4.15],
                                                     "right": [-8, -13, -19], "left": [-8.5, -13.5, -18.5]})],
         doors=[dict(side="right", at=-15.8, stoop=False)],
         porches=[dict(rect=(-1.9, 0.0, -17, -14.6), out="right", roof=None, rail=False, steps=[("right", -15.8)])],
         carports=[dict(rect=(0.6, 5.4, -14, -6))],
         blocks=trailer_bits(-6.4, -1.9, -6, -22),
         paving=[(0.8, 5.2, -14, 0, "gravel")],
         fences=[("privacy", -6.9, -23.9, 6.9, -23.9)],
         trees=[(4.6, -19.5, 1.1)], shrubs=[(-6.4, -3.2, 0.5), (-4.0, -3.2, 0.4)], mailbox=(0.4, -0.4),
         ac=(-7.0 + 0.1, -11.5)),

    dict(id="T-03", name="Weathered Single-Wide", archetype="trailer_1f", folder="residential", floors=1,
         beds=2, baths=1, lot=(14, 24), lot_type="Run-down single-wide, dirt yard, chain-link",
         wall="siding_grey", roof="charcoal", door="door_white", trim="trim_dark", muntins=False,
         wings=[W(-2.0, 4.5, 3, 16, roof=LOWGZ, win={"front": [0.25], "back": [0.25],
                                                    "left": [-5.5, -12.5, -16.5], "right": [-6, -11, -16]})],
         doors=[dict(side="left", at=-9.0, stoop=False)],
         porches=[dict(rect=(-4.4, -2.0, -10.2, -7.8), out="left", roof=None, rail=False, steps=[("left", -9.0)])],
         blocks=trailer_bits(-2.0, 2.5, -3, -19) + boards("right", 2.5, [-11])
                + [(3.4, 5.6, 0.0, 0.9, -21.5, -20.3, "metal_grey", "JunkWasher"),
                   (-6.2, -4.8, 0.0, 0.5, -16.4, -15.0, "metal_dark", "Tyres")],
         paving=[(-6.2, -2.6, -14, 0, "gravel")],
         fences=lot_fence("chain", 7, 24, gaps=[(-6.4, -2.4)]),
         trees=[(4.8, -6, 0.9)], mailbox=(-1.8, -0.5)),
]

APT_ROWS = lambda side, at, floors=3, y0=1.2: [dict(side=side, y0=y0 + 3.0 * f, h=1.6, w=1.3, at=at)
                                                for f in range(floors)]

WALKUPS = [
    dict(id="A-01", name="Brick Walk-up", archetype="apartment_walkup_3f", folder="residential", floors=3,
         lot=(34, 36), lot_type="3-storey walk-up, central stair door, rear parking",
         body=(-14, 14, -26, -6), height=9.4, parapet=0.9, wall="brick_brown", base="cmu_grey",
         bands=[(3.3, 3.45, "trim_cream"), (6.3, 6.45, "trim_cream"), (9.1, 9.4, "trim_cream")],
         doors=[dict(side="front", at=0, w=1.8, h=2.6, kind="glass")],
         upper=[dict(side="front", y0=1.2, h=1.6, w=1.3, at=[-11.5, -8, -4.5, 4.5, 8, 11.5]),
                dict(side="front", y0=3.9, h=1.4, w=1.0, at=[0])] +
               [r for f in (1, 2) for r in [dict(side="front", y0=1.2 + 3.0 * f, h=1.6, w=1.3,
                                                 at=[-11.5, -8, -4.5, 4.5, 8, 11.5])]] +
               [dict(side="front", y0=6.9, h=1.4, w=1.0, at=[0])] +
               APT_ROWS("right", [-23, -19, -13, -9]) + APT_ROWS("left", [-23, -19, -13, -9]) +
               APT_ROWS("back", [-11, -7, -3, 3, 7, 11]),
         awnings=[dict(side="front", a0=-1.6, a1=1.6, y=3.0, d=1.2, style="box", mat="awning_green")],
         signs=[dict(side="front", a0=-3.5, a1=3.5, y0=8.15, y1=8.85, mat="trim_cream", text="TAMARACK ARMS",
                     color="black", d=0.06)],
         extras=[dict(side="back", a0=-3, a1=3, y0=0.4, y1=9.0, d0=0, d1=0.3, mat="cmu_grey", name="StairCore")],
         paving=[(-17, 17, -6, 0, "concrete"), (-17, 17, -36, -26, "asphalt"), (-1, 1, -6, -0.1, "concrete")],
         stalls=[dict(a0=-16.2, n=12, b0=-36, b1=-31)], shrubs=[(-6, -5.2), (-3, -5.2, 0.5), (3, -5.2, 0.5), (6, -5.2)],
         trees=[(-14.5, -2.5, 1.0), (14.5, -2.5, 1.0)], rtu=[(-7, -16), (7, -16)], dumpsters=[(15.5, -34)],
         cars=[(-13.5, -33.5, 0), (-2.7, -33.5, 0)]),

    dict(id="A-02", name="Garden Walk-up", archetype="apartment_walkup_3f", folder="residential", floors=3,
         lot=(34, 36), lot_type="Stucco walk-up with stacked balconies, side parking",
         body=(-15, 9, -28, -8), height=9.4, parapet=0.6, wall="stucco_beige", base="cmu_tan",
         bands=[(9.1, 9.4, "trim_white")],
         doors=[dict(side="front", at=-3, w=1.8, h=2.6, kind="glass")],
         upper=[dict(side="front", y0=1.2 + 3.0 * f, h=1.6, w=1.3, at=[-12.5, -9.5, 0.5, 6.5]) for f in range(3)] +
               [dict(side="front", y0=1.0 + 3.0 * f, h=2.3, w=1.0, at=[-6.5, 3.5], trim="trim_white")
                for f in (1, 2)] +
               APT_ROWS("left", [-25, -21, -15, -11]) + APT_ROWS("right", [-25, -21, -15, -11]) +
               APT_ROWS("back", [-12, -8, -4, 0, 4]),
         extras=[dict(side="front", a0=a - 1.5, a1=a + 1.5, y0=3.25 + 3.0 * k, y1=3.4 + 3.0 * k, d0=0, d1=1.4,
                      mat="concrete", name="Balcony") for a in (-6.5, 3.5) for k in (0, 1)] +
                [dict(side="front", a0=a - 1.5, a1=a + 1.5, y0=3.4 + 3.0 * k, y1=4.4 + 3.0 * k, d0=1.32, d1=1.4,
                      mat="metal_dark", name="BalconyRail") for a in (-6.5, 3.5) for k in (0, 1)],
         awnings=[dict(side="front", a0=-4.6, a1=-1.4, y=3.0, d=1.2, style="box", mat="awning_teal")],
         signs=[dict(side="front", a0=-6, a1=0, y0=8.3, y1=8.9, mat="trim_white", text="PALM COURT", color="black",
                     d=0.06)],
         paving=[(-17, 9, -8, 0, "concrete"), (9, 17, -36, 0, "asphalt"), (-17, 9, -36, -28, "asphalt")],
         stalls=[dict(axis="z", a0=-34.8, n=8, b0=11.8, b1=17), dict(a0=-15.6, n=8, b0=-36, b1=-31)],
         trees=[(-12, -3, 1.1), (5, -3, 0.9)], hedges=[(-15, -8.5, -8.6, -7.6), (-1.5, 9, -8.6, -7.6)],
         rtu=[(-9, -18), (3, -20)], lamps=[(16.4, -18)], dumpsters=[(15.6, -34.5)],
         cars=[(14.5, -24.5, 90), (14.5, -13.7, 90)]),
]


# --- special: hospital and safehouses ------------------------------------------------------
def _ribbons(side, a0, a1, y_first, storeys, step=3.6, h=1.9, mass=0):
    return [dict(side=side, a0=a0, a1=a1, sill=y_first + step * i, top=y_first + step * i + h, mull=2.4,
                 kind="glass", mass=mass) for i in range(storeys)]


HOSPITAL = dict(
    id="H-01", name="Grove General Hospital", archetype="grove_general_hospital", folder="special", floors=7,
    lot=(110, 110), lot_type="Hospital campus: 2-storey podium, 7-storey tower, ER canopy, rooftop helipad",
    body=(-50, 50, -103, -7), height=8.0, parapet=1.0, wall="tilt_up", base="cmu_grey",
    bands=[(3.8, 4.1, "tilt_up_band"), (7.6, 8.0, "tilt_up_band")],
    masses=[dict(rect=(-35, 35, -80, -35), y0=7.0, height=26.0, parapet=1.2, wall="stucco_white",
                 bands=[(25.4, 26.0, "tilt_up_band")])],
    fronts=_ribbons("front", -46, -12, 1.0, 1, h=2.2) + _ribbons("front", 12, 46, 1.0, 1, h=2.2) +
           _ribbons("front", -46, 46, 4.7, 1, h=2.0) +
           _ribbons("left", -98, -12, 1.0, 2, step=3.7, h=2.0) + _ribbons("right", -98, -12, 1.0, 2, step=3.7, h=2.0) +
           _ribbons("front", -32, 32, 9.2, 5, mass=1) + _ribbons("back", -32, 32, 9.2, 5, mass=1) +
           _ribbons("left", -77, -38, 9.2, 5, mass=1) + _ribbons("right", -77, -38, 9.2, 5, mass=1),
    doors=[dict(side="front", at=-4, w=2.4, h=3.0), dict(side="front", at=0, w=2.4, h=3.0),
           dict(side="front", at=4, w=2.4, h=3.0), dict(side="front", at=-34, w=3.0, h=3.0),
           dict(side="front", at=-38, w=3.0, h=3.0), dict(side="left", at=-60, w=1.2, h=2.4, kind="steel")],
    bays=[dict(side="right", at=a, w=3.6, h=4.0) for a in (-60, -66)],
    canopies=[dict(rect=(-9, 9, -7, -1.2), y=4.4, t=0.8, fascia="paint_white", cols=[(-8.2, -1.8), (8.2, -1.8)],
                   text="MAIN ENTRANCE", color="Color(0.1, 0.3, 0.75, 1)"),
              dict(rect=(-42, -30, -7, -0.6), y=4.6, t=0.9, fascia="sign_red", stripe="sign_white",
                   cols=[(-41.4, -1.2), (-30.6, -1.2)], text="EMERGENCY", color="white")],
    signs=[dict(side="front", a0=-22, a1=22, y0=20.6, y1=23.4, mat="paint_white", mass=1,
                text="GROVE GENERAL HOSPITAL", color="Color(0.1, 0.3, 0.75, 1)", d=0.08)],
    extras=[dict(side="front", a0=-1.6, a1=1.6, y0=23.5, y1=24.5, d0=0, d1=0.15, mat="sign_red", name="CrossH", mass=1),
            dict(side="front", a0=-0.5, a1=0.5, y0=22.4, y1=25.6, d0=0, d1=0.15, mat="sign_red", name="CrossV", mass=1)],
    blocks=[(-9, 9, 26.0, 26.3, -66, -48, "concrete", "Helipad"),
            (-7.6, 7.6, 26.3, 26.32, -64.6, -49.4, "paint_yellow", "HelipadRing"),
            (-7.3, 7.3, 26.3, 26.33, -64.3, -49.7, "concrete", "HelipadInner"),
            (-3.2, -2.2, 26.33, 26.35, -60, -54, "paint_white", "HelipadH"),
            (2.2, 3.2, 26.33, 26.35, -60, -54, "paint_white", "HelipadH"),
            (-2.2, 2.2, 26.33, 26.35, -57.5, -56.5, "paint_white", "HelipadH"),
            (20, 30, 26.0, 29.0, -76, -68, "metal_grey", "Penthouse")],
    rtu=[(-40, -95), (-25, -95), (25, -95), (40, -95), (-44, -20), (44, -20)],
    paving=[(-55, 55, -7, 0, "asphalt"), (-55, -50, -110, -7, "asphalt"), (50, 55, -110, -7, "asphalt"),
            (-55, 55, -110, -103, "asphalt"), (-10, 10, -7, -5, "concrete")],
    stalls=[dict(axis="z", a0=-100, n=8, b0=50.2, b1=55, mat="paint_blue")],
    lamps=[(-20, -1.2), (20, -1.2), (-52.5, -50), (52.5, -50)], dumpsters=[(52.5, -106), (49, -106)],
    pylon=dict(x=-48, z=-1.5, h=5.0, w=4.0, mat="sign_red", text="EMERGENCY"),
    trees=[(-24, -3.5, 1.2), (24, -3.5, 1.2), (-48, -3.5, 1.0), (48, -3.5, 1.0)],
    cars=[(-36, -3.5, 90), (52.6, -88, 0)])


SAFEHOUSES = [
    dict(id="SH-01", name="Tamarack Row Safehouse", archetype="safehouse_duplex", folder="special", floors=2,
         beds=4, baths=2, lot=(24, 26), lot_type="Boarded-up duplex: two front doors, side drive (safehouse)",
         wall="siding_grey", roof="charcoal", door="door_white", trim="trim_white", muntins=False,
         wings=[W(-7, 14, 7, 12, roof={"t": "gable", "axis": "x", "pitch": 0.2},
                  win={"front": [-5.5, -1.6, 1.6, 5.5], "back": [-5, -1.5, 1.5, 5], "left": [-10, -15],
                       "right": [-10, -15]})],
         doors=[dict(at=-3.6, canopy="flat"), dict(at=3.6, canopy="flat")],
         blocks=boards("front", -7, [-5.5, 5.5]) + boards("front", -7, [1.6], floor=1) + boards("left", -7, [-15])
                + [(-0.1, 0.1, 0.4, 6.4, -7.05, -6.95, "trim_white", "PartyWallTrim")],
         paving=[(7.6, 11.4, -18, 0, "gravel"), (-4.2, -3.0, -6.2, 0), (3.0, 4.2, -6.2, 0)],
         fences=[("chain", -11.9, -0.3, -4.4, -0.3), ("chain", -2.8, -0.3, 2.8, -0.3), ("chain", 4.4, -0.3, 7.4, -0.3),
                 ("chain", -11.9, -0.3, -11.9, -25.9), ("chain", -11.9, -25.9, 11.9, -25.9),
                 ("chain", 11.9, -25.9, 11.9, -20)],
         shrubs=[(-6, -6.3, 0.5)], trees=[(-9.5, -22, 1.0)], ac=(-7.6, -14)),

    dict(id="SH-02", name="Mangona Safehouse", archetype="safehouse_warehouse", folder="special", floors=2,
         lot=(30, 34), lot_type="Converted 2-storey brick warehouse in a fenced gravel yard (safehouse)",
         body=(-11, 11, -26, -12), height=7.0, parapet=0.7, wall="brick_red", base="cmu_grey",
         bands=[(6.6, 6.8, "trim_cream")],
         bays=[dict(side="front", at=-5, w=4.0, h=4.0)],
         doors=[dict(side="front", at=2.0, w=1.2, h=2.4, kind="steel")],
         fronts=[dict(side="front", a0=4.5, a1=9.5, sill=1.4, top=2.8, kind="barred")],
         upper=[dict(side="front", y0=4.4, h=1.6, w=1.4, at=[-8.5, -5, -1.5, 2, 5.5, 8.5], trim="cmu_grey"),
                dict(side="left", y0=4.4, h=1.6, w=1.4, at=[-23, -19, -15]),
                dict(side="right", y0=4.4, h=1.6, w=1.4, at=[-23, -19, -15])],
         signs=[dict(side="front", a0=-8, a1=8, y0=5.9, y1=6.5, mat="brick_brown", text="MANGONA MACHINE WORKS",
                     color="Color(0.85, 0.82, 0.7, 1)", d=0.03)],
         extras=[dict(side="right", a0=-25, a1=-23.5, y0=0, y1=7.6, d0=0, d1=0.4, mat="metal_grey", name="FireStairRail")],
         blocks=stairs(11.1, 12.3, -14.4, -22.4, 0, 3.4, mat="metal_grey", solid=False)
                + [(11.1, 13.0, 3.15, 3.4, -24.6, -22.4, "metal_grey", "Landing")],
         paving=[(-15, 15, -34, 0, "gravel"), (-8, -2, -12, 0, "concrete")],
         fences=lot_fence("chain", 15, 34, gaps=[(-9, -1)]),
         lamps=[(-13.5, -8)], dumpsters=[(-13, -30)], cars=[(9, -6, 0)]),

    dict(id="SH-03", name="Northgrove Safehouse", archetype="safehouse_greybox", folder="special", floors=1,
         beds=1, baths=1, lot=(24, 26), lot_type="Small block house behind a chain-link gate (safehouse)",
         wall="cmu_grey", roof="charcoal", door="door_black", trim="trim_dark", muntins=False,
         wings=[W(-6, 10, 9, 10, roof=FLAT, win={"front": [-3.5, 2.6], "back": [-3, 3], "left": [-14], "right": [-14]})],
         doors=[dict(at=0, canopy="flat", mat="door_black")],
         blocks=bars("front", -9, [-3.5, 2.6]) + bars("left", -6, [-14]) + bars("right", 4, [-14]),
         paving=[(5.4, 9.6, -19, 0, "gravel"), (-0.6, 0.6, -7.7, 0)],
         fences=lot_fence("chain", 12, 26, gaps=[(-1.0, 1.0), (5.2, 9.8)]),
         trees=[(-9, -21, 1.0)], ac=(4.7, -16)),
]


# --- locations: hit / trap / stick-up targets -------------------------------------------
LOCATIONS = [
    # Trap takeover T1 driver (trap_house_builder.gd): 18 x 14 m, 2 storeys + basement, flat roof,
    # 44 x 35 fenced lot. Driver coords are footprint-centred with +z to the street: kit z = driver z - 15.
    dict(id="L-01", name="The Spot", archetype="trap_house_the_spot", folder="locations", floors=2, beds=4, baths=2,
         lot=(44, 35), lot_type="Viper trap house: 2 storeys + basement, flat roof, boarded + barred, "
                                "fenced lot (trap T1, matches trap_house_builder)",
         wall="stucco_grey", roof="charcoal", door="door_black", trim="trim_dark", muntins=False,
         wings=[W(-9, 18, 8, 14, roof={"t": "flat", "parapet": 0.6},
                  win={"front": [-5.5, 0.5, 6.0], "back": [-5.5, 0.5, 6.0],
                       "left": [-11.5, -18.5], "right": [-11.5, -18.5]})],
         doors=[dict(at=0.5, w=1.6, stoop=False, mat="door_black"),
                dict(at=-11.5, side="right", stoop=False, mat="door_black"),
                dict(at=0.5, side="back", stoop=False, mat="door_black")],
         porches=[dict(rect=(-3.5, 4.5, -8, -6.4), roof="shed", hi=3.2, lo=2.9, rail=False, deck="concrete")],
         blocks=boards("front", -8, [-5.5]) + bars("front", -8, [6.0]) + boards("front", -8, [-5.5, 0.5, 6.0], floor=1)
                + boards("left", -9, [-11.5, -18.5]) + bars("left", -9, [-11.5, -18.5], floor=1)
                + bars("right", 9, [-18.5]) + boards("back", -22, [-5.5, 6.0]) + boards("back", -22, [0.5], floor=1)
                + [(-8.2, -7.6, 5.2, 5.6, -7.75, -7.5, "metal_dark", "Floodlight"),
                   (7.6, 8.2, 5.2, 5.6, -7.75, -7.5, "metal_dark", "Floodlight"),
                   (-3.4, -2.6, 0.4, 2.6, -6.6, -6.2, "plywood", "PorchScreen")],
         paving=[(10.5, 13.5, -8, 0, "gravel"), (0.1, 1.3, -6.4, 0, "concrete")],
         fences=lot_fence("chain", 22, 35, gaps=[(-0.5, 2.5), (10.5, 13.5)]),
         trees=[(-16, -30, 1.1), (17, -29, 1.0)], ac=(-9.6, -15)),

    dict(id="L-02", name="Viper Stash House", archetype="stash_house_viper", folder="locations", floors=2,
         beds=4, baths=2, lot=(26, 30), lot_type="Viper stash: privacy-fenced 2-storey, barred ground floor (raid)",
         wall="siding_grey", roof="charcoal", door="door_green", trim="trim_dark", shutters=True,
         shutter_mat="shutter_dark", roof_shape={"t": "hip", "pitch": 0.35},
         wings=[W(-9.8, 19.6, 8, 14, win={"front": [-7.3, -3.6, 3.6, 7.3], "left": [-11, -16], "right": [-11, -16]})],
         doors=[dict(at=0, canopy="flat", mat="door_green")],
         blocks=bars("front", -8, [-7.3, -3.6, 3.6, 7.3]) + bars("left", -9.8, [-11, -16]) + bars("right", 9.8, [-11, -16])
                + [(9.85, 10.15, 5.6, 5.9, -8.4, -8.0, "metal_dark", "Camera"),
                   (-10.15, -9.85, 5.6, 5.9, -8.4, -8.0, "metal_dark", "Camera")],
         paving=[(10.2, 12.8, -20, 0), (-0.6, 0.6, -6.7, 0)],
         fences=[("privacy", -12.9, -0.3, -1.0, -0.3), ("privacy", 1.0, -0.3, 10.0, -0.3),
                 ("privacy", -12.9, -0.3, -12.9, -29.9), ("privacy", -12.9, -29.9, 12.9, -29.9),
                 ("privacy", 12.9, -29.9, 12.9, -21)],
         trees=[(-10, -26, 1.1)], mailbox=(1.6, -0.6), ac=(-10.6, -18)),

    dict(id="L-03", name="Grove Stash House", archetype="stash_house_grove", folder="locations", floors=2,
         beds=4, baths=2, lot=(26, 30), lot_type="Grove stash + drug lab: boarded upstairs, roof vents (trap T2)",
         wall="brick_brown", roof="brown", door="door_black", trim="trim_cream",
         wings=[W(-9.8, 13, 8, 14, roof={"t": "gable", "axis": "x", "pitch": 0.5},
                  win={"front": [-7, -3.2, 0.8], "left": [-11, -17], "right": [-17]}),
                W(3.2, 6.6, 10, 10, floors=1, roof={"t": "shed", "high": "back", "pitch": 0.2},
                  win={"front": [6.5], "right": [-13, -17]})],
         doors=[dict(at=-1.2, canopy="gable")],
         blocks=boards("front", -8, [-7, -3.2, 0.8], floor=1) + boards("left", -9.8, [-11, -17], floor=1)
                + boards("right", 9.8, [-13]) + bars("front", -8, [-7, -3.2])
                + [(-6.2, -5.8, 6.4, 9.0, -17, -16.6, "metal_grey", "LabVent"),
                   (-2.2, -1.8, 6.4, 8.6, -17, -16.6, "metal_grey", "LabVent"),
                   (-6.6, -5.4, 8.9, 9.1, -17.4, -16.2, "metal_dark", "VentCap")],
         paving=[(10.4, 12.8, -24, 0, "gravel"), (-1.8, -0.6, -6.4, 0)],
         fences=lot_fence("chain", 13, 30, gaps=[(-2.0, 0.0), (10.2, 12.9)]),
         trees=[(-10, -25, 1.0)], ac=(-10.6, -16)),

    dict(id="L-04", name="Lakeside Trailer", archetype="trap_trailer_lakeside", folder="locations", floors=1,
         beds=2, baths=1, lot=(14, 24), lot_type="Trailer trap house: tarps, boarded windows, cook vents (trap T3)",
         wall="siding_cream", roof="green", door="door_white", trim="trim_dark", muntins=False,
         wings=[W(-5.5, 4.5, 4, 16, roof=LOWGZ, win={"front": [-3.25], "back": [-3.25],
                                                     "right": [-6.5, -14, -17.5], "left": [-7, -12, -17]})],
         doors=[dict(side="right", at=-10.2, stoop=False, mat="door_white")],
         porches=[dict(rect=(-1, 1.8, -11.6, -8.8), out="right", roof=None, rail=False, steps=[("right", -10.2)])],
         blocks=trailer_bits(-5.5, -1, -4, -20) + boards("front", -4, [-3.25]) + boards("right", -1, [-6.5, -17.5])
                + boards("left", -5.5, [-7, -12, -17])
                + [(-4.2, -3.8, 3.4, 4.6, -16.2, -15.8, "metal_grey", "CookVent"),
                   (-2.6, -2.2, 3.4, 4.2, -13.2, -12.8, "metal_grey", "CookVent"),
                   (-1, 3.0, 2.9, 3.0, -16, -12.4, "awning_blue", "Tarp"),
                   (2.9, 3.0, 0, 2.9, -16, -15.9, "metal_dark", "TarpPole"),
                   (2.9, 3.0, 0, 2.9, -12.5, -12.4, "metal_dark", "TarpPole"),
                   (3.4, 4.6, 0, 1.0, -21.5, -20.3, "metal_grey", "Drum"),
                   (4.8, 6.0, 0, 1.0, -21.5, -20.3, "metal_grey", "Drum")],
         paving=[(2.6, 5.8, -11, 0, "gravel")],
         fences=lot_fence("chain", 7, 24, gaps=[(2.4, 6.0)]),
         trees=[(-5, -22.5, 1.2), (5, -6, 0.9)]),

    dict(id="L-05", name="Viper Garage", archetype="viper_garage", folder="locations", floors=1,
         lot=(36, 48), lot_type="Viper HQ: big metal garage + office behind a gated, fenced yard",
         body=(-17, 17, -47, -23), height=6.5, roof="gable", ridge="x", pitch=0.12, wall="metal_wall_grey",
         bands=[(0, 1.2, "cmu_grey")],
         masses=[dict(rect=(-17, -6, -23, -15), height=3.6, parapet=0.5, wall="cmu_green", base="cmu_grey")],
         bays=[dict(side="front", at=a, w=4.2, h=4.6) for a in (-2, 4.5, 11)],
         doors=[dict(side="front", at=-11.5, w=1.2, h=2.4, kind="steel", mass=1)],
         fronts=[dict(side="front", a0=-16, a1=-13, sill=1.1, top=2.5, kind="barred", mass=1),
                 dict(side="right", a0=-21, a1=-17, sill=1.1, top=2.5, kind="barred", mass=1)],
         signs=[dict(side="front", a0=-1, a1=14, y0=5.4, y1=6.3, mat="sign_green", text="VIPER GARAGE", color="black")],
         extras=[dict(side="front", a0=-16.6, a1=-6.4, y0=3.0, y1=3.5, d0=0, d1=0.06, mat="sign_green",
                      name="OfficeStripe", mass=1)],
         paving=[(-18, 18, -48, 0, "gravel"), (-8, 16, -23, -2, "concrete")],
         fences=lot_fence("chain", 18, 48, gaps=[(-6, 6)]),
         blocks=[(-6.2, -5.8, 0, 2.6, -0.5, -0.1, "metal_dark", "GatePost"),
                 (5.8, 6.2, 0, 2.6, -0.5, -0.1, "metal_dark", "GatePost")],
         lamps=[(-16.5, -12), (16.5, -12)], dumpsters=[(15.5, -21)],
         cars=[(-2, -16, 0), (4.5, -12, 0), (-12, -6, 90)]),

    # Gas-N-Go placement: 24 x 36 lot, 21 x 32 building box at Okee Blvd / 8th St (census 3998db9).
    dict(id="L-06", name="Gas-N-Go", archetype="gas_station", folder="locations", shop_type="gas_station",
         enterable=True, lot=(24, 36), footprint=(21, 32),
         lot_type="Gas station: pay kiosk at the back, 2 pump islands under a canopy (stick-up / burglary)",
         body=(-8, 8, -34, -22), height=4.4, parapet=0.8, wall="cmu_white", base="cmu_grey",
         bands=[(3.6, 4.4, "sign_red")], interior_h=3.6, counter=(-4.5, -30.5, 3.5),
         fronts=[dict(side="front", a0=-7.4, a1=-1.4, sill=0.5, top=2.9, housing=True),
                 dict(side="front", a0=1.4, a1=7.4, sill=0.5, top=2.9, housing=True)],
         doors=[dict(side="front", at=0, w=2.4, h=2.7, open=True), dict(side="back", at=6, w=1.2, h=2.4, kind="steel")],
         signs=[dict(side="front", a0=-6, a1=6, y0=3.7, y1=4.35, mat="sign_red", text="GAS-N-GO  FOOD MART", d=0.04)],
         canopies=[dict(rect=(-10.5, 10.5, -18.5, -6.5), y=4.8, t=0.8, fascia="sign_white", stripe="sign_red",
                        cols=[(-4, -17.2), (-4, -7.8), (4, -17.2), (4, -7.8)], text="GAS-N-GO", color="red")],
         pumps=[(-4, -12.5), (4, -12.5)],
         blocks=[(8.3, 9.9, 0, 1.6, -27, -25.6, "paint_white", "IceBox"),
                 (8.3, 9.3, 0, 1.4, -24.5, -23.5, "sign_blue", "AirPump")],
         paving=[(-12, 12, -36, 0, "concrete"), (-12, 12, -21.5, -19.5, "asphalt")],
         stalls=[dict(a0=-11.4, n=1, b0=-22, b1=-19), dict(a0=-8.0, n=2, w=2.7, b0=-21.5, b1=-19.5, mat="paint_yellow")],
         pylon=dict(x=10.4, z=-1.5, h=6.2, w=2.6, mat="sign_red", text="GAS-N-GO"),
         lamps=[(-11.4, -28), (11.4, -30)], dumpsters=[(-10.4, -34.4)],
         cars=[(-6.2, -12.5, 0), (6.2, -11.5, 180)]),

    dict(id="L-07", name="Wired Electronics", archetype="electronics_store", folder="locations",
         shop_type="electronics", enterable=True, lot=(24, 30),
         lot_type="Electronics store in its own strip unit, front parking (stick-up)",
         body=(-10, 10, -28, -12), height=4.6, parapet=1.2, wall="tilt_up", base="cmu_grey",
         bands=[(4.0, 4.3, "sign_blue")],
         fronts=[dict(side="front", a0=-9.4, a1=-1.4, sill=0.4, transom=True, top=3.2),
                 dict(side="front", a0=1.4, a1=9.4, sill=0.4, transom=True, top=3.2)],
         doors=[dict(side="front", at=0, w=2.0, h=2.7, open=True), dict(side="back", at=7, w=1.2, h=2.4, kind="steel")],
         awnings=[dict(side="front", a0=-10, a1=10, y=3.45, d=1.6, style="box", mat="awning_black")],
         signs=[dict(side="front", a0=-8, a1=8, y0=4.4, y1=5.6, mat="sign_blue", text="WIRED ELECTRONICS",
                     color="Color(0.4, 0.95, 1, 1)")],
         extras=[dict(side="front", a0=-9.6, a1=-6.4, y0=0.55, y1=2.6, d0=-0.14, d1=-0.1, mat="glass_lit",
                      name="TVWall")],
         paving=[(-12, 12, -12, -10.5, "concrete"), (-12, 12, -10.5, 0, "asphalt"), (-12, 12, -30, -28, "asphalt")],
         stalls=[dict(a0=-10.8, n=8, b0=-10.5, b1=-5.5)], lamps=[(-11.4, -2), (11.4, -2)], rtu=[(-4, -20), (5, -22)],
         cars=[(-6.75, -8, 0), (4.05, -8, 0)]),

    dict(id="L-08", name="The Gallery", archetype="bar_the_gallery", folder="locations", shop_type="bar",
         enterable=True, floors=2, lot=(24, 30), lot_type="2-storey corner bar with neon, rear lot",
         body=(-10, 10, -17, -1), height=7.4, parapet=0.9, wall="brick_red", base="cmu_grey",
         bands=[(3.65, 3.85, "trim_dark")], interior_h=3.6,
         fronts=[dict(side="front", a0=-9.2, a1=-2.0, sill=0.9, top=2.9, glass="glass_lit"),
                 dict(side="front", a0=2.0, a1=9.2, sill=0.9, top=2.9, glass="glass_lit"),
                 dict(side="right", a0=-15, a1=-9, sill=0.9, top=2.9, glass="glass_lit")],
         doors=[dict(side="front", at=0, w=1.8, h=2.6, open=True)],
         upper=[dict(side="front", y0=4.6, h=1.8, w=1.4, at=[-8, -5, -2, 2, 5, 8], trim="trim_dark"),
                dict(side="right", y0=4.6, h=1.8, w=1.4, at=[-14, -10, -6], trim="trim_dark")],
         awnings=[dict(side="front", a0=-1.4, a1=1.4, y=2.95, d=1.0, style="box", mat="awning_black")],
         signs=[dict(side="front", a0=-8, a1=8, y0=3.0, y1=3.6, mat="sign_black", text="THE GALLERY",
                     color="Color(1, 0.3, 0.8, 1)"),
                dict(side="right", a0=-8, a1=-2, y0=4.3, y1=6.6, mat="sign_black", text="BAR",
                     color="Color(1, 0.3, 0.8, 1)", d=0.4)],
         paving=[(-12, 12, -1, 0, "concrete"), (-12, 12, -30, -17, "asphalt"), (10, 12, -17, -1, "concrete")],
         stalls=[dict(a0=-10.8, n=8, b0=-30, b1=-25)], dumpsters=[(10.4, -20)], lamps=[(-11.4, -20)],
         cars=[(-6.75, -27.5, 0)]),

    dict(id="L-09", name="Informant's Flat", archetype="informant_flat", folder="locations", floors=2,
         beds=2, baths=2, lot=(18, 22), lot_type="Up-and-down duplex: informant's flat upstairs via an outside stair",
         wall="siding_white", roof="charcoal", door="door_blue", trim="trim_white",
         wings=[W(-7, 11.6, 5, 11.2, roof={"t": "gable", "axis": "x", "pitch": 0.45},
                  win={"front": [-5, -1.6, 2.4], "right": [-7.6, -11], "left": [-8, -13]})],
         doors=[dict(at=0.4, canopy="flat"), dict(side="right", at=-14.6, y=3.4, stoop=False, mat="door_red")],
         blocks=stairs(4.7, 5.9, -5.6, -12.6, 0, 3.4, mat="wood_deck")
                + [(4.6, 6.6, 3.15, 3.4, -16.2, -12.6, "wood_deck", "Landing"),
                   (6.5, 6.6, 3.4, 4.4, -16.2, -12.6, "trim_white", "LandingRail"),
                   (4.6, 6.6, 3.4, 4.4, -16.3, -16.2, "trim_white", "LandingRail"),
                   (5.9, 6.0, 0.0, 4.4, -12.6, -5.6, "trim_white", "StairRail")]
                + [(4.6, 4.8, 0, 3.15, z - 0.1, z + 0.1, "wood_deck", "LandingPost") for z in (-12.7, -16.1)]
                + [(6.4, 6.6, 0, 3.15, z - 0.1, z + 0.1, "wood_deck", "LandingPost") for z in (-12.7, -16.1)],
         paving=[(-0.2, 1.0, -3.7, 0), (6.8, 8.8, -18, 0, "concrete")],
         fences=[("picket", -8.9, -0.3, -0.4, -0.3), ("picket", 1.4, -0.3, 6.6, -0.3)],
         shrubs=[(-6, -4.3, 0.5), (-3.2, -4.3, 0.5)], trees=[(-6, -18, 1.0)], mailbox=(2.0, -0.6), ac=(-7.6, -12)),

    dict(id="L-10", name="Grove Apartments", archetype="grove_apartments", folder="locations", floors=3,
         lot=(34, 36), lot_type="Motel-style walk-up: open galleries, end stairs, 12 units (4 burglary units)",
         body=(-14, 14, -28, -10.4), height=9.4, parapet=0.6, wall="stucco_peach", base="cmu_grey",
         bands=[(9.1, 9.4, "trim_brown")], footprint=(28, 20),
         doors=[dict(side="front", at=a, w=1.2, h=y + 2.4, y0=y, kind="steel")
                for y in (0.4, 3.4, 6.4) for a in (-10.5, -3.5, 3.5, 10.5)],
         upper=[dict(side="front", y0=y + 0.9, h=1.3, w=1.6, at=[a + s for a in (-10.5, -3.5, 3.5, 10.5) for s in (1.9,)],
                     trim="trim_brown") for y in (0.4, 3.4, 6.4)] +
               APT_ROWS("back", [-11, -7, -3.5, 3.5, 7, 11]) + APT_ROWS("left", [-24, -16]) +
               APT_ROWS("right", [-24, -16]),
         signs=[dict(side="right", a0=-26, a1=-13, y0=7.6, y1=8.8, mat="sign_white", text="GROVE APARTMENTS",
                     color="Color(0.1, 0.45, 0.25, 1)")],
         blocks=[(-14, 14, 3.2, 3.4, -10.4, -8.0, "concrete", "Gallery"),
                 (-14, 14, 6.2, 6.4, -10.4, -8.0, "concrete", "Gallery"),
                 (-14, 14, 9.4, 9.6, -10.6, -7.8, "trim_brown", "GalleryRoof"),
                 (-14, 14, 3.4, 4.4, -8.1, -8.0, "metal_dark", "GalleryRail"),
                 (-14, 14, 6.4, 7.4, -8.1, -8.0, "metal_dark", "GalleryRail")]
                + [(x - 0.12, x + 0.12, 0, 9.4, -8.3, -8.06, "trim_brown", "GalleryPost") for x in (-13.8, -7, 0, 7, 13.8)]
                # east end: ground -> level 2, rising toward the gallery
                + stairs(14.2, 16.6, -17.2, -10.4, 0, 3.4) + [(14.0, 16.6, 3.2, 3.4, -10.4, -8.0, "concrete", "Landing")]
                # west end: level 2 -> level 3 switchback
                + [(-16.9, -14.0, 3.2, 3.4, -10.4, -8.0, "concrete", "Landing")]
                + stairs(-16.9, -15.7, -10.4, -15.4, 3.4, 4.9, solid=False)
                + [(-16.9, -14.2, 4.7, 4.9, -17.6, -15.4, "concrete", "Landing")]
                + stairs(-15.4, -14.2, -15.4, -10.4, 4.9, 6.4, solid=False)
                + [(-16.9, -14.0, 6.2, 6.4, -10.4, -8.0, "concrete", "Landing")],
         paving=[(-17, 17, -8, 0, "asphalt"), (-17, 17, -36, -28, "asphalt"), (-17, -14, -28, -8, "concrete"),
                 (14, 17, -28, -8, "concrete")],
         stalls=[dict(a0=-13.5, n=10, b0=-7.5, b1=-2.5)], lamps=[(-16.4, -1), (16.4, -1)], dumpsters=[(15.4, -33)],
         rtu=[(-8, -20), (0, -20), (8, -20)], cars=[(-12.15, -5, 0), (-1.35, -5, 0), (6.75, -5, 0)]),

    dict(id="L-11", name="El Primo's Warehouse", archetype="coke_plug_house", folder="locations", floors=1,
         lot=(18, 30), lot_type="Coke plug: small block warehouse in a fenced gravel yard",
         body=(-7, 7, -26, -14.8), height=5.0, parapet=0.6, wall="cmu_tan", base="cmu_grey",
         bands=[(4.4, 4.6, "trim_brown")],
         bays=[dict(side="front", at=-2.6, w=3.6, h=3.6)],
         doors=[dict(side="front", at=3.2, w=1.2, h=2.4, kind="steel")],
         fronts=[dict(side="front", a0=4.6, a1=6.4, sill=1.3, top=2.5, kind="barred")],
         signs=[dict(side="front", a0=-6, a1=1, y0=4.0, y1=4.4, mat="sign_white", text="PRIMO IMPORTS",
                     color="black", d=0.05)],
         extras=[dict(side="front", a0=6.2, a1=6.6, y0=4.4, y1=4.7, d0=0, d1=0.35, mat="metal_dark", name="Camera")],
         paving=[(-9, 9, -30, 0, "gravel"), (-5, 0, -14.8, 0, "concrete")],
         fences=lot_fence("chain", 9, 30, gaps=[(-5.4, 0.4)]),
         blocks=[(-5.6, -5.3, 0, 2.4, -0.45, -0.15, "metal_dark", "GatePost"),
                 (0.5, 0.8, 0, 2.4, -0.45, -0.15, "metal_dark", "GatePost")],
         lamps=[(7.6, -12)], dumpsters=[(-7.4, -28)], cars=[(-2.6, -8, 0)]),

    dict(id="L-12", name="Northgrove Savings", archetype="bank_branch", folder="locations", shop_type="bank",
         enterable=True, floors=2, lot=(32, 36),
         lot_type="Bank branch: columned portico, drive-thru lane, side parking (heist target)",
         body=(-12, 12, -28, -8), height=8.0, parapet=0.9, wall="stucco_white", base="cmu_grey",
         bands=[(7.2, 7.6, "trim_cream")], interior_h=6.0, counter=(0, -24.5, 8.0),
         fronts=[dict(side="front", a0=-10.6, a1=-4.6, sill=0.8, top=6.4, mull=1.2),
                 dict(side="front", a0=4.6, a1=10.6, sill=0.8, top=6.4, mull=1.2),
                 dict(side="left", a0=-24, a1=-12, sill=0.8, top=6.4, mull=1.5)],
         doors=[dict(side="front", at=0, w=2.4, h=3.0, open=True), dict(side="back", at=-8, w=1.2, h=2.4, kind="steel")],
         canopies=[dict(rect=(-4.2, 4.2, -8, -5.2), y=6.6, t=1.0, fascia="trim_cream", soffit="trim_cream",
                        text="NORTHGROVE SAVINGS", color="Color(0.1, 0.2, 0.45, 1)"),
                   dict(rect=(12, 15.6, -24, -14), y=4.0, t=0.6, fascia="trim_cream", cols=[(15.2, -23.6), (15.2, -14.4)])],
         columns=[(-3.4, -5.8, 6.6, 0.32, "trim_cream"), (-1.15, -5.8, 6.6, 0.32, "trim_cream"),
                  (1.15, -5.8, 6.6, 0.32, "trim_cream"), (3.4, -5.8, 6.6, 0.32, "trim_cream")],
         extras=[dict(side="front", a0=-3.6, a1=-2.6, y0=0.9, y1=2.0, d0=-0.05, d1=0.2, mat="metal_grey", name="ATM"),
                 dict(side="right", a0=-20, a1=-18, y0=1.0, y1=2.2, d0=0, d1=0.3, mat="glass", name="TellerWindow")],
         blocks=[(-4.6, 4.6, 0, 0.3, -8, -5.0, "concrete", "PorticoStep")],
         paving=[(-16, 16, -8, 0, "concrete"), (12, 16, -36, -8, "asphalt"), (-16, -12, -36, -8, "asphalt"),
                 (-16, 16, -36, -28, "asphalt")],
         stalls=[dict(axis="z", a0=-27, n=6, b0=-16, b1=-12.2)], lamps=[(-15.4, -10), (15.6, -30)],
         trees=[(-9, -3, 1.1), (9, -3, 1.1)], shrubs=[(-7, -7.4), (7, -7.4)], rtu=[(-6, -20), (6, -20)],
         cars=[(-14.1, -21.7, 90), (13.8, -19, 180)]),
]


# --- purchasable businesses (all enterable, all stick-up targets) -------------------------
def _parking(a0, n, b0, b1, **kw):
    return dict(a0=a0, n=n, b0=b0, b1=b1, **kw)


PURCHASABLE = [
    dict(id="P-01", name="Tamarack Corner Store", archetype="bodega", folder="purchasable", shop_type="corner_store",
         enterable=True, lot=(18, 24), lot_type="Corner bodega built to two sidewalks (purchasable, stick-up)",
         body=(-7, 7, -14, -2), height=4.4, parapet=0.9, wall="brick_red", base="cmu_grey",
         bands=[(3.3, 3.5, "trim_cream")], interior_h=4.0, counter=(-3.5, -11.5, 3.5),
         fronts=[dict(side="front", a0=-6.4, a1=-1.6, sill=0.5, top=2.8, housing=True),
                 dict(side="front", a0=1.6, a1=5.2, sill=0.5, top=2.8, housing=True),
                 dict(side="right", a0=-12.8, a1=-3.2, sill=0.5, top=2.8, housing=True)],
         doors=[dict(side="front", at=0, w=2.4, h=2.7, open=True)],
         awnings=[dict(side="front", a0=-7, a1=7, y=2.95, d=1.3, mat="awning_red"),
                  dict(side="right", a0=-14, a1=-2, y=2.95, d=1.3, mat="awning_red")],
         signs=[dict(side="front", a0=-6.5, a1=6.5, y0=3.6, y1=4.6, mat="sign_white", text="TAMARACK CORNER STORE",
                     color="red"),
                dict(side="right", a0=-13, a1=-3, y0=3.6, y1=4.6, mat="sign_white", text="GROCERY  DELI  ATM",
                     color="red")],
         blocks=[(-8.6, -7.2, 0, 1.6, -5.4, -3.6, "paint_white", "IceBox")],
         paving=[(-9, 9, -2, 0, "concrete"), (7, 9, -24, -2, "concrete"), (-9, 7, -24, -14, "asphalt"),
                 (-9, -7, -14, -2, "concrete")],
         stalls=[_parking(-6.6, 4, -24, -19)], dumpsters=[(-7.6, -22)], cars=[(-5.25, -21.5, 0)]),

    dict(id="P-02", name="Tamarack Liquor", archetype="liquor_store", folder="purchasable", shop_type="liquor_store",
         enterable=True, lot=(20, 26), lot_type="Liquor store behind a short front lot, grates rolled up",
         body=(-8, 8, -24, -12), height=4.4, parapet=1.0, wall="stucco_pink", base="cmu_grey",
         interior_h=4.0, counter=(4.5, -21.0, 3.5),
         fronts=[dict(side="front", a0=-7.4, a1=-1.5, sill=0.6, top=2.8, housing=True, kind="barred"),
                 dict(side="front", a0=1.5, a1=7.4, sill=0.6, top=2.8, housing=True, kind="barred")],
         doors=[dict(side="front", at=0, w=2.4, h=2.7, open=True)],
         signs=[dict(side="front", a0=-7.5, a1=7.5, y0=3.5, y1=5.0, mat="sign_blue", text="TAMARACK LIQUOR",
                     color="yellow"),
                dict(side="front", a0=-7, a1=-2, y0=0.75, y1=1.15, mat="sign_yellow", text="COLD BEER", color="red",
                     d=0.02)],
         paving=[(-10, 10, -12, -10.6, "concrete"), (-10, 10, -10.6, 0, "asphalt"), (-10, 10, -26, -24, "asphalt")],
         stalls=[_parking(-9.45, 7, -10.6, -5.6)], lamps=[(9.4, -2)], cars=[(-6.75, -8, 0), (6.75, -8, 0)]),

    dict(id="P-03", name="Tamarack Cutz", archetype="barbershop", folder="purchasable", shop_type="barbershop",
         enterable=True, lot=(16, 22), lot_type="Small barbershop with a pole, side gravel parking",
         body=(-7, 5, -14, -4), height=4.2, parapet=0.8, wall="cmu_white", base="cmu_grey",
         bands=[(3.3, 3.5, "awning_red"), (3.5, 3.7, "awning_white"), (3.7, 3.9, "awning_blue")],
         fronts=[dict(side="front", a0=-6.5, a1=-2.0, sill=0.6, top=2.9), dict(side="front", a0=1.0, a1=4.5, sill=0.6, top=2.9)],
         doors=[dict(side="front", at=-0.5, w=1.8, h=2.6, open=True)],
         signs=[dict(side="front", a0=-6, a1=4, y0=3.9, y1=4.75, mat="sign_black", text="TAMARACK CUTZ", color="white")],
         pole=("front", 4.8, 1.3),
         paving=[(-8, 5, -4, 0, "concrete"), (5, 8, -22, 0, "gravel"), (-8, 5, -22, -14, "gravel")],
         stalls=[], cars=[(6.5, -10, 0)]),

    dict(id="P-04", name="Northgrove Pawn & Loan", archetype="pawn_shop", folder="purchasable", shop_type="pawn_shop",
         enterable=True, lot=(20, 28), lot_type="Standalone pawn shop, barred glass, front lot",
         body=(-8, 8, -26, -12), height=4.4, parapet=1.0, wall="brick_tan", base="cmu_grey",
         bands=[(3.6, 3.8, "sign_yellow")],
         fronts=[dict(side="front", a0=-7.4, a1=-1.4, sill=0.7, top=2.8, kind="barred"),
                 dict(side="front", a0=1.4, a1=7.4, sill=0.7, top=2.8, kind="barred")],
         doors=[dict(side="front", at=0, w=1.8, h=2.6, open=True)],
         signs=[dict(side="front", a0=-7.5, a1=7.5, y0=4.0, y1=5.2, mat="sign_black", text="PAWN & LOAN", color="yellow"),
                dict(side="front", a0=-7, a1=7, y0=3.0, y1=3.5, mat="sign_yellow", text="GOLD  GUNS  TOOLS  TVS",
                     color="black", d=0.05)],
         pylon=dict(x=8.4, z=-1.6, h=5.0, w=2.4, mat="sign_yellow", text="PAWN", color="black"),
         paving=[(-10, 10, -12, -10.6, "concrete"), (-10, 10, -10.6, 0, "asphalt")],
         stalls=[_parking(-9.45, 6, -10.6, -5.6)], cars=[(-4.05, -8, 0)]),

    dict(id="P-05", name="Northgrove Pharmacy", archetype="pharmacy", folder="purchasable", shop_type="pharmacy",
         enterable=True, lot=(26, 32), lot_type="Chain-style pharmacy, front lot, side drive-thru window",
         body=(-11, 9, -30, -14), height=5.0, parapet=1.4, wall="stucco_white", base="cmu_grey",
         bands=[(4.0, 4.3, "sign_green")], interior_h=4.0,
         fronts=[dict(side="front", a0=-10.2, a1=-1.8, sill=0.4, top=3.2, transom=True),
                 dict(side="front", a0=1.8, a1=8.2, sill=0.4, top=3.2, transom=True)],
         doors=[dict(side="front", at=0, w=2.4, h=2.7, open=True)],
         awnings=[dict(side="front", a0=-2.2, a1=2.2, y=3.5, d=1.8, style="box", mat="awning_green")],
         signs=[dict(side="front", a0=-9, a1=5, y0=4.6, y1=6.0, mat="sign_white", text="NORTHGROVE PHARMACY",
                     color="Color(0.1, 0.5, 0.25, 1)")],
         extras=[dict(side="front", a0=5.9, a1=7.9, y0=5.0, y1=5.6, d0=0, d1=0.2, mat="sign_green", name="CrossH"),
                 dict(side="front", a0=6.6, a1=7.2, y0=4.3, y1=6.3, d0=0, d1=0.2, mat="sign_green", name="CrossV"),
                 dict(side="right", a0=-26, a1=-24.4, y0=1.0, y1=2.2, d0=0, d1=0.3, mat="glass", name="DriveThru")],
         canopies=[dict(rect=(9, 12.4, -27.4, -23.0), y=3.6, t=0.5, fascia="sign_green", cols=[(12.0, -27.0), (12.0, -23.4)])],
         paving=[(-13, 13, -14, -12.5, "concrete"), (-13, 13, -12.5, 0, "asphalt"), (9, 13, -32, -12.5, "asphalt")],
         stalls=[_parking(-12.15, 8, -12.5, -7.5)], lamps=[(-12.4, -2), (12.4, -2)], rtu=[(-5, -22), (4, -24)],
         cars=[(-9.45, -10, 0), (-1.35, -10, 0)]),

    dict(id="P-06", name="Northgrove Ink", archetype="tattoo_parlor", folder="purchasable", shop_type="tattoo_parlor",
         enterable=True, lot=(16, 22), lot_type="Narrow tattoo shop, neon window, side lot",
         body=(-6, 6, -14, -4), height=4.4, parapet=1.4, wall="stucco_grey", base="cmu_grey",
         bands=[(3.2, 3.35, "sign_purple")],
         fronts=[dict(side="front", a0=-5.4, a1=-1.4, sill=0.5, glass="glass_lit"),
                 dict(side="front", a0=1.4, a1=5.4, sill=0.5, glass="glass_lit")],
         doors=[dict(side="front", at=0, w=1.8, h=2.6, open=True)],
         awnings=[dict(side="front", a0=-6, a1=6, y=3.0, d=1.0, style="box", mat="awning_purple")],
         signs=[dict(side="front", a0=-5.5, a1=5.5, y0=3.7, y1=5.1, mat="sign_black", text="NORTHGROVE INK",
                     color="Color(0.75, 0.4, 1, 1)")],
         paving=[(-8, 8, -4, 0, "concrete"), (6, 8, -22, -4, "asphalt"), (-8, 6, -22, -14, "asphalt")],
         stalls=[_parking(-5.4, 4, -22, -17)], shrubs=[(-7.2, -3.4, 0.4)], cars=[(-4.05, -19.5, 0)]),

    dict(id="P-07", name="Mangona Auto Parts", archetype="chop_shop", folder="purchasable", shop_type="chop_shop",
         enterable=True, lot=(36, 48), lot_type="Auto parts + 3-bay garage, fenced salvage yard out back",
         body=(-15, 15, -34, -10), height=6.0, roof="gable", ridge="x", pitch=0.12, wall="metal_wall_red",
         bands=[(0, 1.2, "cmu_grey")], interior_h=4.8, counter=(10.5, -13.5, 4.0),
         bays=[dict(side="front", at=-10, w=4.0, h=4.2), dict(side="front", at=-4.5, w=4.0, h=4.2, open=True),
               dict(side="front", at=1, w=4.0, h=4.2)],
         doors=[dict(side="front", at=6.5, w=1.6, h=2.6, open=True)],
         fronts=[dict(side="front", a0=8.4, a1=14.2, sill=0.7, top=2.8)],
         signs=[dict(side="front", a0=-13, a1=13, y0=4.9, y1=5.8, mat="sign_white", text="MANGONA AUTO PARTS",
                     color="red")],
         paving=[(-18, 18, -10, 0, "concrete"), (-18, 18, -48, -34, "gravel"), (-18, -15, -34, -10, "gravel"),
                 (15, 18, -34, -10, "gravel")],
         fences=[("chain", -17.9, -34, -17.9, -47.9), ("chain", -17.9, -47.9, 17.9, -47.9),
                 ("chain", 17.9, -47.9, 17.9, -34)],
         blocks=[(-14, -9, 0, 1.4, -44, -40, "metal_grey", "SalvageCar"), (-6, -1.5, 0, 1.4, -45, -41, "metal_dark",
                                                                         "SalvageCar"),
                 (3, 7, 0, 1.2, -46, -42, "awning_red", "SalvageCar"), (10, 15, 0, 2.2, -46, -40, "metal_grey",
                                                                       "PartsRack")],
         lamps=[(-17, -4), (17, -4)], dumpsters=[(16.4, -36)], cars=[(-4.5, -4, 0), (12, -4.5, 0)]),

    dict(id="P-08", name="Mangona Guns & Ammo", archetype="gun_store", folder="purchasable", shop_type="gun_store",
         enterable=True, lot=(24, 30), footprint=(18, 27),
         lot_type="Block gun store with an indoor-range annex behind it",
         body=(-9, 9, -16, -2), height=4.6, parapet=0.8, wall="cmu_grey", base="cmu_grey",
         bands=[(3.6, 3.9, "awning_red")], interior_h=4.0, counter=(0, -13.5, 6.0),
         masses=[dict(rect=(-8, 8, -29, -16), height=4.2, parapet=0.4, wall="cmu_tan",
                      bands=[(3.6, 3.9, "awning_red")])],
         fronts=[dict(side="front", a0=-8.2, a1=-2.0, sill=0.9, top=2.7, kind="barred"),
                 dict(side="front", a0=2.0, a1=8.2, sill=0.9, top=2.7, kind="barred")],
         doors=[dict(side="front", at=0, w=2.0, h=2.6, open=True),
                dict(side="right", at=-26, w=1.2, h=2.4, kind="steel", mass=1)],
         signs=[dict(side="front", a0=-8.5, a1=8.5, y0=4.0, y1=5.2, mat="sign_black", text="MANGONA GUNS & AMMO",
                     color="red"),
                dict(side="left", a0=-27, a1=-18, y0=2.6, y1=3.4, mat="sign_red", text="INDOOR RANGE", mass=1,
                     color="white")],
         paving=[(-12, 12, -2, 0, "concrete"), (9, 12, -30, -2, "asphalt"), (-12, -9, -30, -2, "asphalt")],
         stalls=[dict(axis="z", a0=-28, n=8, b0=9.2, b1=12)], lamps=[(11.4, -1)], rtu=[(0, -22)],
         cars=[(10.6, -12.5, 90)]),

    dict(id="P-09", name="Mangona Hardware", archetype="hardware_store", folder="purchasable",
         shop_type="hardware_store", enterable=True, lot=(30, 34), footprint=(30, 18),
         lot_type="Hardware store with a fenced lumber yard and front lot",
         body=(-14.9, 9, -33.9, -16), height=5.6, parapet=1.2, wall="metal_wall_tan", base="cmu_grey",
         bands=[(4.6, 5.0, "sign_orange")], interior_h=4.6,
         fronts=[dict(side="front", a0=-14, a1=-4, sill=0.4, top=3.2), dict(side="front", a0=-0.4, a1=8, sill=0.4, top=3.2)],
         doors=[dict(side="front", at=-2.2, w=2.4, h=2.8, open=True),
                dict(side="right", at=-22, w=3.6, h=3.6, kind="steel")],
         awnings=[dict(side="front", a0=-14.9, a1=9, y=3.5, d=2.0, style="box", mat="awning_orange")],
         signs=[dict(side="front", a0=-13, a1=7, y0=5.2, y1=6.5, mat="sign_white", text="MANGONA HARDWARE",
                     color="Color(0.85, 0.35, 0.05, 1)")],
         blocks=[(10, 14.6, 0, 1.8, -32, -29, "wood_deck", "LumberStack"), (10, 14.6, 0, 1.2, -27, -24, "wood_deck",
                                                                           "LumberStack"),
                 (10, 14.6, 0, 2.2, -22, -19, "wood_deck", "LumberStack"), (9.5, 15, 3.6, 3.8, -33, -18, "metal_roof_x",
                                                                            "LumberShed"),
                 (14.6, 14.8, 0, 3.6, -33, -32.8, "metal_dark", "ShedPost"),
                 (14.6, 14.8, 0, 3.6, -18.2, -18, "metal_dark", "ShedPost")],
         fences=[("chain", 9.1, -16, 14.9, -16), ("chain", 14.9, -16, 14.9, -33.9), ("chain", 9.1, -33.9, 14.9, -33.9)],
         paving=[(-15, 15, -16, -14, "concrete"), (-15, 15, -14, 0, "asphalt"), (9, 15, -34, -16, "gravel")],
         stalls=[_parking(-14.3, 9, -14, -9)], lamps=[(-14.4, -2), (14.4, -2)], rtu=[(-8, -25), (2, -25)],
         cars=[(-10.55, -11.5, 0), (2.95, -11.5, 0)]),
]

# The enterable shop-below / flat-above stand-in (standin_shopfront_2f, shop_type food).
FOOD_SHOP = dict(
    id="S-09", name="Golden Wok", shop_type="food", archetype="standin_shopfront_2f", floors=2, enterable=True,
    lot=(24, 28), lot_type="Takeout below, flat above; built to the sidewalk, rear lot",
    body=(-11, 11, -17, -1), height=7.2, parapet=0.8, wall="brick_tan", base="cmu_grey",
    bands=[(3.55, 3.75, "trim_brown")], interior_h=3.4, counter=(0, -14.0, 5.0),
    fronts=[dict(side="front", a0=-10.2, a1=-1.6, sill=0.6, top=2.7, glass="glass_lit"),
            dict(side="front", a0=4.6, a1=10.2, sill=0.6, top=2.7, kind="grate")],
    doors=[dict(side="front", at=0, w=1.8, h=2.6, open=True), dict(side="front", at=3.0, w=1.2, h=2.5, kind="steel")],
    awnings=[dict(side="front", a0=-10.6, a1=1.2, y=2.95, d=1.0, mat="awning_red")],
    signs=[dict(side="front", a0=-10, a1=1, y0=3.0, y1=3.5, mat="sign_red", text="GOLDEN WOK", color="yellow", d=0.06),
           dict(side="front", a0=4.6, a1=10.2, y0=2.9, y1=3.45, mat="sign_white", text="SHOE REPAIR", color="black")],
    upper=[dict(side="front", y0=4.6, h=1.6, w=1.3, at=[-9, -6, -3, 3, 6, 9]),
           dict(side="right", y0=4.6, h=1.6, w=1.3, at=[-14, -10, -6, -3]),
           dict(side="left", y0=4.6, h=1.6, w=1.3, at=[-14, -10, -6, -3])],
    paving=[(-12, 12, -1, 0, "concrete"), (-12, 12, -28, -17, "asphalt")],
    stalls=[dict(a0=-10.8, n=8, b0=-28, b1=-23)], dumpsters=[(10.4, -19)], cars=[(1.35, -25.5, 0)])

# Census storeys for the shop below / flat above archetype are 2.

BUSINESS_LIKE = WALKUPS + [HOSPITAL, SAFEHOUSES[1]] + [s for s in LOCATIONS if "body" in s] + PURCHASABLE
HOUSE_LIKE = RESIDENTIAL + [SAFEHOUSES[0], SAFEHOUSES[2]] + [s for s in LOCATIONS if "body" not in s]

STREET2_NORTH = [HOSPITAL] + WALKUPS + RESIDENTIAL + SAFEHOUSES + \
    [s for s in LOCATIONS if s["id"] in ("L-01", "L-02", "L-03", "L-04", "L-05", "L-09", "L-10", "L-11")]
STREET2_SOUTH = [s for s in LOCATIONS if s["id"] in ("L-06", "L-07", "L-08", "L-12")] + PURCHASABLE + [FOOD_SHOP]
EXTRA = STREET2_NORTH + STREET2_SOUTH
