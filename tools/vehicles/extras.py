"""Accessories bolted onto a body style: light bars, signs, spoilers, cargo boxes, ladders, decals.
Every function takes the VehicleBuilder `b` and the spec `s` first."""
import math


def hl(s):
    return s["body"]["L"] / 2


def half_w(s):
    return s["body"]["W"] / 2


def side_panel(b, s, z0, z1, y0, y1, material, inset=0.0):
    """A thin coloured panel on both flanks (two-tone doors, stripes, wood trim, rust)."""
    x = half_w(s) + 0.006 - inset
    b.span("SidePanel", x - 0.01, x + 0.008, y0, y1, z0, z1, material)
    b.span("SidePanel", -x - 0.008, -x + 0.01, y0, y1, z0, z1, material)


def stripe(b, pts, material="paint2", x=0.17, w=0.2, step=0.04):
    """Racing stripes following a top outline [(z, y), ...]; drawn twice at +-x. The stripe is cut
    into runs that skip every window (windshield, rear glass), so it never paints over glass."""
    lift = 0.012
    for sx in (x, -x):
        run = []

        def flush():
            if len(run) >= 2:
                b.strut("Stripe", run[0], run[-1], w, material, depth=0.012)
            run.clear()

        for (za, ya), (zb, yb) in zip(pts, pts[1:]):
            n = max(1, int(math.ceil(math.hypot(zb - za, yb - ya) / step)))
            flush()
            for i in range(n):
                t0, t1 = i / n, (i + 1) / n
                p0 = (sx, ya + (yb - ya) * t0 + lift, za + (zb - za) * t0)
                p1 = (sx, ya + (yb - ya) * t1 + lift, za + (zb - za) * t1)
                # Test the piece's two ends and middle, across the stripe's full width.
                blocked = any(b.over_glass((sx + dx, p[1], p[2])) for dx in (-w / 2, 0.0, w / 2)
                              for p in (p0, p1, tuple((p0[i] + p1[i]) / 2 for i in range(3))))
                if blocked:
                    flush()
                    continue
                if not run:
                    run.append(p0)
                run.append(p1)
        flush()


def lightbar(b, s, z, y, width=1.2, colors=("siren_red", "siren_blue"), depth=0.28):
    b.span("LightbarBase", -width / 2, width / 2, y, y + 0.06, z - depth / 2, z + depth / 2, "black")
    b.span("LightbarL", 0.04, width / 2 - 0.02, y + 0.06, y + 0.16, z - depth / 2 + 0.02, z + depth / 2 - 0.02, colors[1])
    b.span("LightbarR", -width / 2 + 0.02, -0.04, y + 0.06, y + 0.16, z - depth / 2 + 0.02, z + depth / 2 - 0.02, colors[0])


def push_bar(b, s, y0, y1, width=1.3):
    z = hl(s) + 0.12
    for x in (width / 2 - 0.05, -width / 2 + 0.05):
        b.span("PushBar", x - 0.04, x + 0.04, y0, y1, z - 0.05, z + 0.05, "black")
    b.span("PushBar", -width / 2, width / 2, y1 - 0.07, y1, z - 0.04, z + 0.04, "black")
    b.span("PushBar", -width / 2, width / 2, y0 + 0.1, y0 + 0.17, z - 0.04, z + 0.04, "black")


def spoiler(b, s, z, y, width=None, height=0.22, chord=0.28, material="paint2"):
    w = width or s["body"]["W"] - 0.2
    for x in (w / 2 - 0.15, -w / 2 + 0.15):
        b.span("SpoilerPost", x - 0.03, x + 0.03, y, y + height, z - 0.05, z + 0.05, "black")
    b.span("SpoilerWing", -w / 2, w / 2, y + height, y + height + 0.04, z - chord / 2, z + chord / 2, material)


def roof_rack(b, s, z0, z1, y, width=None):
    w = width or s["body"]["W"] - 0.3
    b.span("RackRail", w / 2 - 0.04, w / 2, y, y + 0.08, z0, z1, "chrome")
    b.span("RackRail", -w / 2, -w / 2 + 0.04, y, y + 0.08, z0, z1, "chrome")
    for z in (z0 + 0.15, (z0 + z1) / 2, z1 - 0.15):
        b.span("RackBar", -w / 2, w / 2, y + 0.06, y + 0.1, z - 0.025, z + 0.025, "black")


def ladder(b, z0, z1, y, width=0.6, material="chrome", rungs=None):
    b.span("LadderRail", width / 2 - 0.05, width / 2, y, y + 0.08, z0, z1, material)
    b.span("LadderRail", -width / 2, -width / 2 + 0.05, y, y + 0.08, z0, z1, material)
    n = rungs or int((z1 - z0) / 0.4)
    for i in range(n + 1):
        z = z0 + (z1 - z0) * i / n
        b.span("LadderRung", -width / 2, width / 2, y + 0.02, y + 0.06, z - 0.02, z + 0.02, material)


def cargo_box(b, s, z0, z1, y0, y1, material="paint", width=None, shape=True, name="CargoBox"):
    w = width or s["body"]["W"]
    b.span(name, -w / 2, w / 2, y0, y1, z0, z1, material)
    if shape:
        b.shape(name + "Shape", (w, y1 - y0, z1 - z0), (0, (y0 + y1) / 2, (z0 + z1) / 2))


def bed(b, s, z0, z1, floor, top, wall=0.07, material="paint"):
    """Open pickup bed: floor, two sides and a tailgate, with its own collision."""
    w = half_w(s)
    b.span("BedFloor", -w, w, floor - 0.04, floor, z0, z1, "black")
    b.span("BedSide", w - wall, w, floor, top, z0, z1, material)
    b.span("BedSide", -w, -w + wall, floor, top, z0, z1, material)
    b.span("Tailgate", -w, w, floor, top, z0, z0 + wall, material)
    b.span("BedFront", -w, w, floor, top, z1 - wall, z1, material)
    b.shape("BedShape", (w * 2, top - floor + 0.04, z1 - z0), (0, (floor + top) / 2 - 0.02, (z0 + z1) / 2))


def sign_box(b, text, pos, size, material="sign", text_col=(0.05, 0.05, 0.05), font=48, pixel=0.004):
    """Lit box (taxi roof sign, bus destination board) with the text on its front and back."""
    b.box("Sign", size, pos, material)
    x, y, z = pos
    b.label("SignText", text, (x, y, z + size[2] / 2 + 0.006), size=pixel, col=text_col, font=font, outline=0)
    b.label("SignText", text, (x, y, z - size[2] / 2 - 0.006), (0, 180, 0), size=pixel, col=text_col, font=font,
            outline=0)


def exhausts(b, s, y, xs, length=0.3, radius=0.045):
    for x in xs:
        b.cyl("Exhaust", radius, length, (x, y, -hl(s) - length / 2 + 0.1), "chrome", rot=(90, 0, 0), sides=10)


def flares(b, s, radius, width=0.16, material="plastic"):
    """Boxy fender flares over each axle on both sides."""
    wd = s["wheels"]
    zs = [wd["wb"] / 2 + wd.get("offset", 0.0), -wd["wb"] / 2 + wd.get("offset", 0.0)]
    for z in zs:
        b.span("Flare", half_w(s) - 0.02, half_w(s) + width, radius * 2 + 0.02, radius * 2 + 0.1, z - radius - 0.15,
               z + radius + 0.15, material)
        b.span("Flare", -half_w(s) - width, -half_w(s) + 0.02, radius * 2 + 0.02, radius * 2 + 0.1, z - radius - 0.15,
               z + radius + 0.15, material)


def seat(b, x, y, z, w=0.5, material="leather", back=0.55):
    b.span("Seat", x - w / 2, x + w / 2, y, y + 0.14, z - 0.25, z + 0.25, material)
    b.span("SeatBack", x - w / 2, x + w / 2, y + 0.14, y + 0.14 + back, z - 0.3, z - 0.2, material)


def spare_tire(b, z, y, r=0.36, w=0.24, x=0.0):
    b.cyl("SpareTire", r, w, (x, y, z), "tire", rot=(90, 0, 0), sides=20)
    b.cyl("SpareRim", r * 0.6, w + 0.02, (x, y, z), "steel", rot=(90, 0, 0), sides=12)
