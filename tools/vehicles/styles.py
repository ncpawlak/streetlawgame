"""Body styles and accessories. Each style turns a spec's `body` dict into geometry, collision
shapes, wheels and the gameplay markers (Seats/Driver, Exit, EngineSmoke) on a VehicleBuilder."""
import math

G = 9.8


# --- shared pieces ---------------------------------------------------------------------------------

def wheels(b, s):
    """Axles from spec['wheels']: wb (wheelbase), offset (axle centre z), r, w (tyre width), style,
    drive ('rwd' / 'fwd' / 'awd'), tandem (extra rear axle spacing), track (wheel centre |x|)."""
    wd = s["wheels"]
    body = s["body"]
    r, w = wd["r"], wd["w"]
    track = wd.get("track", body["W"] / 2 + 0.04 - w / 2)
    zf = wd["wb"] / 2 + wd.get("offset", 0.0)
    zr = -wd["wb"] / 2 + wd.get("offset", 0.0)
    drive = wd.get("drive", "rwd")
    axles = [(zf, True, drive in ("fwd", "awd"))]
    axles.append((zr, False, drive in ("rwd", "awd")))
    if "tandem" in wd:
        axles.append((zr - wd["tandem"], False, drive in ("rwd", "awd")))
    s["wheel_count"] = len(axles) * 2
    h = s["handling"]
    rest = h["rest"]
    # Suspension force is stiffness * compression * mass per wheel, so at rest each wheel is
    # compressed by g / (wheel_count * stiffness). Hang the wheel so the tyre then touches y = 0.
    sag = G / (s["wheel_count"] * h["stiffness"])
    for z, steer, traction in axles:
        tag = "F" if steer else ("R" if z == zr else "T")
        for side, label in ((1, "L"), (-1, "R")):
            b.wheel("Wheel%s%s" % (tag, label), side * track, z, r, w, steer, traction, style=wd.get("style", "rim"),
                    rest=rest, sag=sag, travel=h.get("travel", rest), rim_ratio=wd.get("rim_ratio", 0.62))
            if wd.get("wells", True):
                b.wheel_well(side * (body["W"] / 2 + 0.006), z, r, 0)
    s["traction_wheels"] = sum(2 for _, _, t in axles if t)


def markers(b, s, driver_z, seat_y, per_row=2, row_gap=0.85, width=None):
    """Seats/Driver + Seats/PassengerN, the driver-side Exit and the EngineSmoke emitter."""
    body = s["body"]
    W = width or body["W"]
    seats = b.sc.node("Seats", "Node3D", ".")
    n = s["seats"]
    xs = [W * 0.22, -W * 0.22] if per_row == 2 else [W * (0.36 - 0.24 * i) for i in range(per_row)]
    for i in range(n):
        row, col = divmod(i, per_row)
        b.marker("Driver" if i == 0 else "Passenger%d" % i, (xs[col], seat_y, driver_z - row * row_gap), seats)
    b.marker("Exit", (W / 2 + 0.9, 0.2, driver_z))
    b.marker("EngineSmoke", body.get("smoke", (0, body.get("belt", 1.0) + 0.1, body["L"] / 2 - 0.8)))


def lights(b, s, front_y, rear_y, front_z=None, rear_z=None, spread=None, size=(0.34, 0.12)):
    body = s["body"]
    W, hl = body["W"], body["L"] / 2
    sx = spread if spread is not None else W / 2 - 0.25
    fz = front_z if front_z is not None else hl
    rz = rear_z if rear_z is not None else -hl
    b.box("Headlight", (size[0], size[1], 0.04), (sx, front_y, fz + 0.01), "headlight", mirror=True)
    b.box("Taillight", (size[0], size[1] * 0.9, 0.04), (sx, rear_y, rz - 0.01), "taillight", mirror=True)


def bumpers(b, s, material, y, front_z=None, rear_z=None, h=0.2, d=0.18):
    body = s["body"]
    W, hl = body["W"], body["L"] / 2
    if material is None:
        return
    b.box("FrontBumper", (W + 0.04, h, d), (0, y, (front_z if front_z is not None else hl) + d / 2 - 0.04), material)
    b.box("RearBumper", (W + 0.04, h, d), (0, y, (rear_z if rear_z is not None else -hl) - d / 2 + 0.04), material)


def mirrors(b, x, y, z):
    b.box("Mirror", (0.08, 0.11, 0.16), (x + 0.04, y, z), "plastic", mirror=True)


def camera(s):
    body = s["body"]
    top = body.get("roof", 1.4)
    return max(6.5, body["L"] * 1.15 + 1.5), max(1.8, top * 0.85 + 0.7)


# --- styles -------------------------------------------------------------------------------------------

def car(b, s):
    """Cars, vans, pickups, trucks and buses: a lower-body side profile, an optional greenhouse
    (glass with a painted roof and pillars), bumpers, lights, wheels and markers."""
    d = s["body"]
    L, W = d["L"], d["W"]
    hl = L / 2
    ride, belt, roof = d["ride"], d["belt"], d.get("roof", 0)
    cf, cr = d.get("cab_front", 0), d.get("cab_rear", 0)
    ws, rr = d.get("ws", 0.75), d.get("rear", 0.5)
    inset = d.get("inset", 0.1)
    gw = d.get("glass_w", W - 2 * inset)
    nose = d.get("nose", belt - 0.12)
    tail = d.get("tail", belt - 0.04)
    lower = d.get("lower") or [(-hl, tail), (-hl + 0.3, belt), (cf, belt), (hl - 0.25, nose), (hl, nose - 0.1)]
    b.profile("Body", lower, ride, W, d.get("body_mat", "paint"))
    b.shape("LowerShape", (W, belt - ride, L), (0, (ride + belt) / 2, 0))

    if d.get("greenhouse", True):
        top_r, top_f = cr + rr, cf - ws
        b.profile("Glass", [(cr, belt), (top_r, roof), (top_f, roof), (cf, belt)], belt, gw, "glass")
        roof_mat = d.get("roof_mat", "paint")
        b.span("Roof", -gw / 2 - 0.015, gw / 2 + 0.015, roof, roof + 0.05, top_r - 0.02, top_f + 0.02, roof_mat)
        pm = d.get("pillar_mat", roof_mat)
        px = gw / 2 + 0.006
        b.strut("APillar", (px, belt, cf), (px, roof + 0.02, top_f), 0.06, pm, mirror=True, depth=0.08)
        if rr > 0.05:
            b.strut("CPillar", (px, belt, cr), (px, roof + 0.02, top_r), 0.06, pm, mirror=True, depth=0.16)
        else:
            b.span("CPillar", -px - 0.006, px + 0.006, belt, roof, cr - 0.005, cr + 0.12, pm)
        for z in d.get("b_pillars", [(top_r + top_f) / 2]):
            b.span("BPillar", px - 0.03, px + 0.006, belt, roof, z - 0.05, z + 0.05, pm)
            b.span("BPillar", -px - 0.006, -px + 0.03, belt, roof, z - 0.05, z + 0.05, pm)
        for z0, z1 in d.get("panels", []):
            b.span("Panel", -gw / 2 - 0.012, gw / 2 + 0.012, belt - 0.01, roof + 0.01, z0, z1, d.get("panel_mat", roof_mat))
        b.shape("CabinShape", (gw, roof - belt, top_f - top_r + (ws + rr) * 0.6),
                (0, (belt + roof) / 2, (top_r + top_f) / 2 + (ws - rr) * 0.15))
        if d.get("mirrors", True):
            mirrors(b, W / 2, belt + 0.12, cf - 0.15)

    bumpers(b, s, d.get("bumper", "plastic"), ride + d.get("bumper_y", 0.12), h=d.get("bumper_h", 0.2))
    fy = d.get("light_y", (ride + nose) / 2 + 0.06)
    ry = d.get("tail_light_y", (ride + tail) / 2 + 0.1)
    lights(b, s, fy, ry, spread=d.get("light_spread"), size=d.get("light_size", (0.34, 0.12)))
    if d.get("grille", "black"):
        b.box("Grille", (d.get("grille_w", W * 0.42), d.get("grille_h", 0.16), 0.03), (0, fy - 0.02, hl + 0.012), d.get("grille", "black"))
    for z in d.get("door_lines", []):
        b.span("DoorLine", W / 2 - 0.01, W / 2 + 0.006, ride + 0.12, belt - 0.03, z - 0.008, z + 0.008, "black")
        b.span("DoorLine", -W / 2 - 0.006, -W / 2 + 0.01, ride + 0.12, belt - 0.03, z - 0.008, z + 0.008, "black")
    wheels(b, s)
    top_f = cf - ws
    markers(b, s, d.get("driver_z", top_f - 0.35), d.get("seat_y", belt - 0.2), per_row=d.get("per_row", 2),
            row_gap=d.get("row_gap", 0.85))


def bike(b, s):
    """Two visible wheels on the centre line. The controller is a four-wheel VehicleBody3D, so each
    axle has two physics wheels 0.36 m apart (only one is drawn) and zero roll influence keeps it
    upright: a training-wheel trick until the bike gets its own lean controller."""
    d = s["body"]
    L, r = d["L"], s["wheels"]["r"]
    hl = L / 2
    scooter = d.get("scooter", False)
    wz = s["wheels"]["wb"] / 2
    if scooter:
        b.profile("Body", [(-hl + 0.1, 0.62), (-0.1, 0.72), (0.25, 0.42), (hl - 0.35, 0.42)], 0.28, 0.42, "paint")
        b.span("Floorboard", -0.2, 0.2, 0.28, 0.34, -0.05, hl - 0.3, "plastic")
        b.strut("Column", (0, 0.4, hl - 0.38), (0, 1.0, hl - 0.48), 0.22, "paint", depth=0.12)
        b.box("Shield", (0.42, 0.55, 0.08), (0, 0.66, hl - 0.33), "paint", rot=(-12, 0, 0))
        b.box("Seat", (0.3, 0.1, 0.62), (0, 0.78, -0.25), "leather")
        b.box("Bars", (0.7, 0.04, 0.04), (0, 1.02, hl - 0.48), "chrome")
        b.box("Headlight", (0.16, 0.1, 0.04), (0, 0.9, hl - 0.42), "headlight")
        b.box("Taillight", (0.14, 0.06, 0.04), (0, 0.66, -hl + 0.08), "taillight")
        b.box("Basket", (0.34, 0.2, 0.3), (0, 0.98, hl - 0.25), "steel")
    else:
        b.box("Engine", (0.38, 0.4, 0.55), (0, 0.48, 0.05), "black")
        b.profile("Fairing", [(0.2, 0.95), (hl - 0.25, 0.92), (hl - 0.05, 0.62)], 0.5, 0.46, "paint")
        b.box("Tank", (0.4, 0.22, 0.5), (0, 0.98, 0.0), "paint")
        b.box("Seat", (0.3, 0.1, 0.55), (0, 0.96, -0.45), "black")
        b.profile("Tail", [(-hl + 0.05, 1.08), (-0.55, 0.98)], 0.82, 0.26, "paint2")
        b.box("Screen", (0.3, 0.3, 0.03), (0, 1.08, hl - 0.28), "glass", rot=(-35, 0, 0))
        b.strut("Fork", (0.1, 0.45, wz), (0.1, 1.0, hl - 0.35), 0.05, "chrome", mirror=True)
        b.strut("Swingarm", (0.12, 0.42, -0.2), (0.12, r, -wz), 0.05, "steel", mirror=True)
        b.box("Bars", (0.62, 0.04, 0.04), (0, 1.02, hl - 0.42), "black")
        b.box("Headlight", (0.2, 0.1, 0.04), (0, 0.82, hl - 0.06), "headlight")
        b.box("Taillight", (0.14, 0.05, 0.04), (0, 1.02, -hl + 0.06), "taillight")
        b.cyl("Exhaust", 0.05, 0.6, (-0.18, 0.5, -0.5), "chrome", rot=(80, 0, 0))
    b.shape("FrameShape", (0.5, 0.75, L * 0.9), (0, 0.7, 0))
    wd = s["wheels"]
    h = s["handling"]
    sag = G / (4 * h["stiffness"])
    s["wheel_count"] = 4
    s["traction_wheels"] = 2
    for z, steer in ((wz, True), (-wz, False)):
        tag = "F" if steer else "R"
        b.wheel("Wheel%sL" % tag, 0.18, z, r, wd["w"], steer, not steer, style=wd.get("style", "rim"), rest=h["rest"],
                sag=sag, travel=h["rest"], rim_ratio=wd.get("rim_ratio", 0.62), visual_x=0.0)
        b.wheel("Wheel%sR" % tag, -0.18, z, r, wd["w"], steer, not steer, rest=h["rest"], sag=sag, travel=h["rest"],
                hidden=True)
    markers(b, s, -0.3, 0.95, per_row=1, row_gap=0.45, width=0.0)


def airboat(b, s):
    """Display-only Everglades airboat sitting on a trailer."""
    d = s["body"]
    L, W = d["L"], d["W"]
    hl = L / 2
    deck = 0.95
    b.profile("Hull", [(-hl, deck), (hl - 1.0, deck), (hl, deck + 0.25)], 0.55, W, "paint")
    b.wedge("Bow", hl - 1.0, hl, 0.55, deck - 0.05, W, "paint", flip=True)
    b.span("Deck", -W / 2 + 0.05, W / 2 - 0.05, deck, deck + 0.03, -hl + 0.1, hl - 0.6, "steel")
    b.span("Rail", W / 2 - 0.05, W / 2, deck, deck + 0.35, -hl, hl - 0.8, "steel")
    b.span("Rail", -W / 2, -W / 2 + 0.05, deck, deck + 0.35, -hl, hl - 0.8, "steel")
    # Raised driver seat and the big caged fan at the back.
    b.strut("SeatLeg", (0.35, deck, -0.3), (0.35, deck + 1.4, -0.3), 0.06, "steel", mirror=True)
    b.span("HighSeat", -0.45, 0.45, deck + 1.4, deck + 1.5, -0.6, 0.0, "black")
    b.span("Bench", -0.8, 0.8, deck, deck + 0.45, 0.6, 1.2, "white")
    b.box("Engine", (0.7, 0.6, 0.8), (0, deck + 0.4, -1.3), "black")
    b.cyl("Shroud", 1.15, 0.12, (0, deck + 1.3, -1.9), "steel", rot=(90, 0, 0), sides=24)
    b.cyl("Prop", 1.05, 0.06, (0, deck + 1.3, -1.8), "wood", rot=(90, 0, 0), sides=6, top=0.1)
    for i in range(4):
        b.box("Cage", (0.03, 2.3, 0.03), (0, deck + 1.3, -2.0), "chrome", rot=(0, 0, i * 45))
    b.span("Rudder", -0.03, 0.03, deck + 0.4, deck + 2.0, -hl - 0.4, -hl, "paint2")
    b.span("Rudder", 0.37, 0.43, deck + 0.4, deck + 2.0, -hl - 0.4, -hl, "paint2")
    b.span("Rudder", -0.43, -0.37, deck + 0.4, deck + 2.0, -hl - 0.4, -hl, "paint2")
    # Trailer.
    b.span("TrailerFrame", 0.5, 0.65, 0.35, 0.5, -hl, hl + 1.5, "steel")
    b.span("TrailerFrame", -0.65, -0.5, 0.35, 0.5, -hl, hl + 1.5, "steel")
    b.strut("Tongue", (0.55, 0.42, hl + 1.5), (0, 0.42, hl + 2.4), 0.1, "steel", mirror=True)
    for z in (-0.5, 0.5):
        for x in (1.0, -1.0):
            b.cyl("TrailerTire", 0.33, 0.22, (x, 0.33, z * 1.1 - 0.5), "tire", rot=(0, 0, 90), sides=20)
            b.cyl("TrailerRim", 0.2, 0.24, (x, 0.33, z * 1.1 - 0.5), "rim", rot=(0, 0, 90), sides=12)
    b.span("Fender", 0.85, 1.15, 0.72, 0.76, -1.6, 0.6, "black")
    b.span("Fender", -1.15, -0.85, 0.72, 0.76, -1.6, 0.6, "black")
    b.shape("HullShape", (W, deck + 0.3 - 0.35, L + 2.4), (0, (deck + 0.3 + 0.35) / 2, 1.2))
    b.shape("FanShape", (2.4, 2.4, 0.5), (0, deck + 1.3, -1.9))
    s["wheel_count"] = 0
    s["traction_wheels"] = 0
    markers(b, s, -0.3, deck + 1.5, per_row=2)


STYLES = {"car": car, "bike": bike, "airboat": airboat}
