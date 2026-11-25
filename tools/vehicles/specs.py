"""The vehicle line-up. Each spec drives one generated scene and one registry entry.

Units: mass kg, accel m/s^2 (full-throttle on flat ground, before drag), top_kph km/h, health hp.
`handling` is a 1-10 rating; the per-class profile (suspension feel) is picked by `feel`.
All names are fictional."""
import extras as x

CLASSES = {
    # id: (display name, sign colour)
    "beater": ("Beater & Compact", "#8a7d6b"),
    "sedan": ("Sedan", "#3d6fb0"),
    "lowrider": ("Lowrider & Donk", "#b03dae"),
    "muscle": ("Muscle", "#c4412b"),
    "sports": ("Sports & Exotic", "#e8a412"),
    "suv": ("SUV & Pickup", "#4f8a3b"),
    "van": ("Van", "#6f6f78"),
    "police": ("Police", "#1f3fa8"),
    "emergency": ("Emergency", "#d02424"),
    "service": ("Service & Commercial", "#1a8f8a"),
    "bike": ("Motorcycle & Scooter", "#222222"),
    "boat": ("Boat (display)", "#2a7fb8"),
}

# Suspension feel per handling family: stiffness, damping (compress / relax), roll influence, rest length.
FEEL = {
    "beater": dict(stiffness=45.0, damp_c=1.2, damp_r=1.8, roll=0.15, rest=0.25),
    "sedan": dict(stiffness=60.0, damp_c=1.6, damp_r=2.2, roll=0.1, rest=0.25),
    "lowrider": dict(stiffness=30.0, damp_c=0.9, damp_r=1.4, roll=0.2, rest=0.2),
    "donk": dict(stiffness=35.0, damp_c=1.0, damp_r=1.5, roll=0.25, rest=0.35),
    "muscle": dict(stiffness=65.0, damp_c=1.7, damp_r=2.4, roll=0.1, rest=0.25, rear_grip=0.85),
    "sports": dict(stiffness=110.0, damp_c=2.4, damp_r=3.4, roll=0.05, rest=0.18),
    "utility": dict(stiffness=55.0, damp_c=1.6, damp_r=2.3, roll=0.2, rest=0.35),
    "truck": dict(stiffness=70.0, damp_c=2.0, damp_r=2.8, roll=0.15, rest=0.35),
    "bike": dict(stiffness=80.0, damp_c=2.0, damp_r=3.0, roll=0.0, rest=0.2),
}


def handling_params(feel, rating, **over):
    h = dict(FEEL[feel])
    h.update(grip=round(2.6 + 0.42 * rating, 2), steer_speed=round(1.3 + 0.22 * rating, 2),
             max_steer=round(0.4 + 0.02 * rating, 3))
    h.update(over)
    return h


SPECS = []


def V(id, name, cls, feel, mass, accel, top_kph, handling, health, seats, zones, tier, palette, body, wheels,
      trim=("#1a1a1c",), style="car", stealable=True, drivable=True, extras=(), desc="", com_y=None, **kw):
    spec = dict(id=id, name=name, cls=cls, feel=feel, mass=mass, accel=accel, top_kph=top_kph,
                handling_rating=handling, health=health, seats=seats, spawn_zones=list(zones), income_tier=tier,
                palette=list(palette), trim_palette=list(trim), style=style, stealable=stealable, drivable=drivable,
                extras=list(extras), description=desc, body=body, wheels=wheels,
                handling=handling_params(feel, handling, **kw.pop("handling_over", {})), com_y=com_y)
    spec.update(kw)
    SPECS.append(spec)
    return spec


def sedan_body(L, W, ride, belt, roof, cf, cr, ws, rear, **kw):
    d = dict(L=L, W=W, ride=ride, belt=belt, roof=roof, cab_front=cf, cab_rear=cr, ws=ws, rear=rear)
    d.update(kw)
    return d


# --- Beater & Compact ----------------------------------------------------------------------------

def _rust(b, s):
    x.side_panel(b, s, -1.9, -1.3, 0.4, 0.62, "rust")
    x.side_panel(b, s, 1.5, 1.95, 0.42, 0.58, "rust")
    b.span("PrimerHood", -0.7, 0.7, 0.9, 0.93, 1.0, 1.95, "primer")
    b.span("Bungee", -0.6, 0.6, 0.86, 0.9, -2.26, -2.22, "orange")


V("rustbucket", "Rustbucket", "beater", "beater", 1150, 2.4, 135, 3, 220, 4,
  ["projects", "residential", "glades"], "poor", ["#7a6a55", "#5d6b73", "#8b3a2e", "#6f7a4a", "#8c8577"],
  sedan_body(4.5, 1.78, 0.32, 0.92, 1.42, 0.95, -1.25, 0.7, 0.45, door_lines=[0.0, -1.0], bumper="steel"),
  dict(wb=2.6, r=0.32, w=0.2, style="steel"), trim=["#8f8f8a"], matte=True, extras=[_rust],
  desc="Twenty-year-old sedan held together by primer and prayer. Cheap to lose.")


V("pipsqueak", "Pipsqueak", "beater", "beater", 850, 2.8, 125, 6, 180, 2,
  ["downtown", "residential", "waterfront"], "working", ["#e94f37", "#3fb8af", "#f6d55c", "#8fd14f", "#f2f2f2"],
  sedan_body(2.7, 1.55, 0.25, 0.85, 1.55, 0.75, -1.1, 0.45, 0.1, nose=0.6, tail=0.8,
             lower=[(-1.35, 0.8), (-1.3, 0.85), (0.75, 0.85), (1.2, 0.62), (1.35, 0.5)],
             door_lines=[-0.2], light_size=(0.22, 0.14), light_spread=0.5, grille_w=0.4),
  dict(wb=1.85, r=0.27, w=0.17, drive="fwd"), trim=["#f2f2f2"],
  desc="Two-seat city bubble. Parks anywhere, loses every fight.")


def _hopper(b, s):
    x.spoiler(b, s, -1.85, 1.43, height=0.02, chord=0.25, width=1.35, material="paint")


V("hopper", "Hopper", "beater", "beater", 1100, 3.0, 150, 6, 230, 4,
  ["residential", "suburbs", "downtown"], "working", ["#c9d1d3", "#2e5266", "#b2393a", "#e2c044", "#3a3a3a"],
  sedan_body(3.9, 1.72, 0.28, 0.9, 1.45, 0.85, -1.75, 0.75, 0.15, tail=0.88, door_lines=[-0.3]),
  dict(wb=2.5, r=0.3, w=0.2, drive="fwd"), extras=[_hopper],
  desc="Hot-hatch on a budget. Zippy, light and easy to throw around.")


# --- Sedan --------------------------------------------------------------------------------------

V("meridian", "Meridian", "sedan", "sedan", 1400, 3.4, 170, 6, 300, 4,
  ["residential", "suburbs", "downtown", "highway"], "middle",
  ["#9aa3ab", "#1d2a3a", "#6b0f1a", "#f0f0ec", "#2f4f3e", "#3b3b3e"],
  sedan_body(4.7, 1.85, 0.3, 0.95, 1.42, 1.1, -1.35, 0.75, 0.55, door_lines=[-0.15]),
  dict(wb=2.75, r=0.34, w=0.24), desc="The commuter car every city is full of. Does everything okay.")


def _regent(b, s):
    x.side_panel(b, s, -2.4, 2.4, 0.62, 0.66, "chrome")
    b.box("Ornament", (0.04, 0.1, 0.08), (0, 1.0, 2.38), "chrome")


V("regent", "Regent", "sedan", "sedan", 1900, 3.8, 195, 5, 360, 4,
  ["waterfront", "suburbs", "downtown"], "rich", ["#0d0d0f", "#c7c9cc", "#f3f1ea", "#2a1a14", "#13233f"],
  sedan_body(5.2, 1.95, 0.3, 1.0, 1.48, 1.3, -1.55, 0.8, 0.6, bumper="chrome", grille="chrome", grille_h=0.24,
             grille_w=0.7, door_lines=[-0.1]),
  dict(wb=3.1, r=0.36, w=0.25, style="chrome"), trim=["#c7c9cc"], extras=[_regent],
  desc="Executive saloon. Soft, heavy and quietly fast.")


def _tradewind(b, s):
    x.side_panel(b, s, -2.3, 1.0, 0.42, 0.86, "wood")
    x.roof_rack(b, s, -2.0, -0.2, 1.47)


V("tradewind", "Tradewind", "sedan", "sedan", 1600, 2.8, 160, 4, 320, 5,
  ["suburbs", "residential"], "middle", ["#7d5a3c", "#d8cfb8", "#3c5a40", "#8c1c13"],
  sedan_body(5.0, 1.9, 0.3, 0.95, 1.45, 1.2, -2.35, 0.75, 0.12, door_lines=[-0.2, -1.3], b_pillars=[-0.25, -1.3]),
  dict(wb=2.95, r=0.34, w=0.23, style="chrome"), extras=[_tradewind],
  desc="Wood-panelled family wagon. Five seats and a roof rack.")


# --- Lowrider & Donk ----------------------------------------------------------------------------

def _boulevard(b, s):
    x.side_panel(b, s, -2.5, 2.3, 0.6, 0.64, "chrome")
    x.spare_tire(b, -2.85, 0.62, r=0.32, w=0.2)
    b.span("Underglow", -0.8, 0.8, 0.12, 0.15, -2.0, 2.0, "neon")


V("boulevard", "Boulevard", "lowrider", "lowrider", 1800, 2.6, 150, 3, 320, 4,
  ["projects", "residential"], "working", ["#7a1fa2", "#b0122b", "#0f6b8a", "#c79a12", "#1d6b2f"],
  sedan_body(5.4, 1.98, 0.18, 0.8, 1.25, 1.0, -1.6, 0.85, 0.75, roof_mat="paint2", bumper="chrome", grille="chrome",
             grille_w=1.2, lower=[(-2.7, 0.88), (-2.4, 0.8), (1.0, 0.8), (2.45, 0.74), (2.7, 0.62)], nose=0.74,
             tail=0.86, door_lines=[-0.3]),
  dict(wb=3.0, r=0.33, w=0.2, style="wire", rim_ratio=0.78), trim=["#f2efe6"], extras=[_boulevard],
  desc="Candy paint, wire wheels and whitewalls. Wallows like a waterbed.")


def _donk_grille(b, s):
    b.box("BigGrille", (1.4, 0.32, 0.04), (0, s["body"]["ride"] + 0.4, s["body"]["L"] / 2 + 0.02), "chrome")


V("swamp_king", "Swamp King", "lowrider", "donk", 2000, 3.0, 160, 2, 380, 4,
  ["projects", "residential", "glades"], "working", ["#5fd02a", "#ff7a12", "#e8d21a", "#1e8fff", "#d62b9b"],
  sedan_body(5.4, 2.0, 0.75, 1.45, 1.95, 1.15, -1.5, 0.65, 0.3, nose=1.41, tail=1.43, bumper="chrome", grille=None,
             door_lines=[-0.2]),
  dict(wb=2.95, r=0.6, w=0.32, style="donk", rim_ratio=0.82), trim=["#f2f2f2"], gold_rims=True,
  extras=[_donk_grille], com_y=0.95,
  desc="Box-body donk on 26-inch gold rims. Turns like a parade float.")


V("bubble", "Bubble", "lowrider", "donk", 1950, 3.2, 170, 3, 360, 4,
  ["projects", "residential"], "working", ["#00a6a6", "#9b1d64", "#f15bb5", "#fee440", "#202020"],
  sedan_body(5.4, 2.0, 0.72, 1.4, 1.95, 1.2, -1.45, 0.85, 0.6, nose=1.28, tail=1.2,
             lower=[(-2.7, 1.2), (-2.45, 1.4), (1.2, 1.4), (2.4, 1.28), (2.7, 1.1)], bumper="paint",
             grille="chrome", door_lines=[-0.15]),
  dict(wb=2.95, r=0.58, w=0.3, style="donk", rim_ratio=0.82), trim=["#ffffff"], com_y=0.92,
  desc="Rounded 90s land yacht on chrome 24s. Candy paint mandatory.")


# --- Muscle ---------------------------------------------------------------------------------------

def _thunderhorse(b, s):
    x.stripe(b, [(2.35, 0.72), (2.2, 0.85), (0.85, 0.9), (0.15, 1.32), (-0.45, 1.32), (-1.75, 0.92), (-2.35, 0.9)])
    b.span("HoodScoop", -0.3, 0.3, 0.9, 1.0, 1.1, 1.7, "black")


V("thunderhorse", "Thunderhorse", "muscle", "muscle", 1550, 4.6, 205, 4, 320, 2,
  ["residential", "suburbs", "highway"], "middle", ["#1a3c8f", "#b31b1b", "#f2a900", "#101010", "#e5e5e5"],
  sedan_body(4.7, 1.9, 0.25, 0.9, 1.32, 0.85, -1.75, 0.7, 1.3,
             lower=[(-2.35, 0.88), (-2.2, 0.9), (0.85, 0.9), (2.2, 0.85), (2.35, 0.72)], nose=0.85, tail=0.88,
             door_lines=[-0.4]),
  dict(wb=2.7, r=0.34, w=0.27, style="black"), trim=["#f5f5f5", "#101010"], extras=[_thunderhorse],
  desc="Classic fastback with twin stripes. Loud, light and tail-happy.")


def _vandal(b, s):
    b.box("Blower", (0.55, 0.3, 0.6), (0, 1.1, 1.3), "chrome")
    b.box("Scoop", (0.5, 0.16, 0.3), (0, 1.32, 1.38), "black")
    x.spoiler(b, s, -2.35, 0.97, height=0.2)
    for side in (1, -1):
        b.cyl("SidePipe", 0.06, 2.2, (side * 1.02, 0.36, 0.0), "chrome", rot=(90, 0, 0), sides=10)


V("vandal", "Vandal", "muscle", "muscle", 1600, 5.2, 215, 3, 330, 2,
  ["projects", "residential", "industrial"], "working", ["#121212", "#e0601a", "#5a5d61", "#7a0f1b"],
  sedan_body(5.0, 1.95, 0.28, 0.95, 1.35, 0.6, -1.4, 0.7, 0.4, door_lines=[-0.3]),
  dict(wb=2.95, r=0.34, w=0.3, style="black"), trim=["#e0601a", "#121212"], extras=[_vandal],
  handling_over=dict(rear_grip=0.8), matte=True,
  desc="Supercharged street brawler. Blower through the hood, grip optional.")


def _marauder(b, s):
    x.spoiler(b, s, -2.35, 1.0, height=0.04, chord=0.2, material="paint")
    x.exhausts(b, s, 0.38, [0.5, 0.38, -0.38, -0.5], radius=0.05)


V("marauder", "Marauder", "muscle", "muscle", 1800, 5.0, 230, 5, 340, 4,
  ["downtown", "suburbs", "highway"], "middle", ["#2b2b2e", "#8a8d91", "#0b3d91", "#a4161a", "#f4f4f4"],
  sedan_body(5.05, 1.95, 0.3, 1.0, 1.45, 1.05, -1.45, 0.85, 0.6, door_lines=[-0.2], grille_h=0.12, grille_w=1.0),
  dict(wb=3.0, r=0.36, w=0.27, style="black"), extras=[_marauder],
  desc="Four-door muscle sedan. Seats the crew and still smokes the tyres.")


# --- Sports & Exotic -------------------------------------------------------------------------------

def _kestrel(b, s):
    x.spoiler(b, s, -2.1, 0.8, height=0.06, chord=0.3, material="paint")


V("kestrel", "Kestrel GT", "sports", "sports", 1350, 5.8, 250, 8, 260, 2,
  ["waterfront", "downtown", "highway"], "upper", ["#c0c0c0", "#d1001f", "#0a0a0a", "#f2b705", "#1c5d99"],
  sedan_body(4.5, 1.92, 0.18, 0.78, 1.22, 0.75, -1.55, 0.7, 1.0, nose=0.6, tail=0.75,
             lower=[(-2.25, 0.75), (-2.0, 0.82), (0.75, 0.8), (2.0, 0.6), (2.25, 0.5)], grille_h=0.1,
             light_size=(0.4, 0.08), door_lines=[-0.45]),
  dict(wb=2.5, r=0.34, w=0.27, style="rim"), extras=[_kestrel],
  desc="Rear-engined GT with a ducktail. Precise and planted.")


def _vortex(b, s):
    x.spoiler(b, s, -2.15, 0.85, height=0.3, chord=0.35, material="black")
    x.side_panel(b, s, -1.2, -0.5, 0.35, 0.65, "black")


V("vortex", "Vortex", "sports", "sports", 1400, 6.8, 290, 9, 240, 2,
  ["waterfront", "highway"], "rich", ["#a6e22e", "#ffb000", "#f25c05", "#f4f4f4", "#7b2cbf"],
  sedan_body(4.6, 2.02, 0.12, 0.7, 1.12, 0.75, -1.1, 1.0, 0.45, nose=0.38, tail=0.8,
             lower=[(-2.3, 0.82), (-1.6, 0.8), (0.75, 0.7), (2.3, 0.38)], light_y=0.42, light_size=(0.45, 0.06),
             grille=None, bumper=None, roof_mat="black", pillar_mat="black"),
  dict(wb=2.7, r=0.35, w=0.3, style="black", drive="awd"), extras=[_vortex],
  desc="Mid-engined wedge. The fastest thing in Palm County with plates.")


def _cabana(b, s):
    d = s["body"]
    b.span("Cockpit", -0.8, 0.8, 0.8, 0.83, -0.95, 0.45, "interior")
    x.seat(b, 0.4, 0.62, -0.25)
    x.seat(b, -0.4, 0.62, -0.25)
    b.strut("Windshield", (0, 0.82, 0.55), (0, 1.22, 0.28), d["W"] - 0.25, "glass", depth=0.03)
    b.strut("WsFrame", (0.78, 0.82, 0.55), (0.78, 1.24, 0.27), 0.05, "chrome", mirror=True)
    b.span("Boot", -0.85, 0.85, 0.8, 0.88, -1.9, -1.0, "paint2")
    b.box("Mirror", (0.08, 0.1, 0.14), (0.95, 0.95, 0.4), "chrome", mirror=True)


V("cabana", "Cabana", "sports", "sports", 1200, 5.0, 225, 8, 230, 2,
  ["waterfront", "downtown"], "upper", ["#ff6b6b", "#4ecdc4", "#f7fff7", "#ffe66d", "#1a535c"],
  sedan_body(4.2, 1.8, 0.2, 0.82, 0.82, 0.5, -1.0, 0.3, 0.0, greenhouse=False, nose=0.68,
             lower=[(-2.1, 0.8), (-1.9, 0.82), (0.5, 0.82), (1.85, 0.66), (2.1, 0.56)], driver_z=-0.25,
             seat_y=0.7),
  dict(wb=2.4, r=0.32, w=0.24, style="chrome"), trim=["#e8dcc4", "#2a2a2a"], extras=[_cabana],
  desc="Two-seat drop-top roadster for A1A cruising.")


# --- SUV & Pickup -------------------------------------------------------------------------------------

def _everglade(b, s):
    x.roof_rack(b, s, -2.2, 0.4, 1.95)
    x.side_panel(b, s, -1.6, 1.4, 0.38, 0.46, "chrome")
    x.spare_tire(b, -2.68, 1.0, r=0.36)


V("everglade", "Everglade", "suv", "utility", 2600, 3.2, 175, 4, 420, 7,
  ["suburbs", "waterfront", "highway"], "upper", ["#0f0f10", "#f2f2f2", "#5a6b5d", "#7b1e1e", "#2c3e50"],
  sedan_body(5.1, 2.0, 0.45, 1.25, 1.9, 1.35, -2.4, 0.7, 0.1, nose=1.2, tail=1.22, door_lines=[0.1, -1.0],
             b_pillars=[0.0, -1.1], grille_w=1.0, grille_h=0.3, grille="chrome", row_gap=0.8),
  dict(wb=3.0, r=0.4, w=0.27, drive="awd", style="chrome"), extras=[_everglade],
  desc="Three-row luxury SUV. Big, safe and thirsty.")


def _palmetto(b, s):
    d = s["body"]
    b.span("Tub", -0.85, 0.85, 1.12, 1.15, -1.8, 0.4, "interior")
    x.seat(b, 0.42, 0.85, -0.15, material="black")
    x.seat(b, -0.42, 0.85, -0.15, material="black")
    b.span("RearBench", -0.8, 0.8, 0.85, 1.0, -1.3, -0.8, "black")
    b.strut("Windshield", (0, 1.15, 0.5), (0, 1.75, 0.38), 1.6, "glass", depth=0.03)
    b.strut("WsFrame", (0.82, 1.15, 0.5), (0.82, 1.77, 0.37), 0.06, "paint", mirror=True)
    for z in (-0.35, -1.75):
        b.span("RollBar", 0.78, 0.84, 1.15, 1.95, z - 0.03, z + 0.03, "black")
        b.span("RollBar", -0.84, -0.78, 1.15, 1.95, z - 0.03, z + 0.03, "black")
        b.span("RollBar", -0.84, 0.84, 1.9, 1.96, z - 0.03, z + 0.03, "black")
    b.span("RollBar", 0.78, 0.84, 1.9, 1.96, -1.75, -0.35, "black")
    b.span("RollBar", -0.84, -0.78, 1.9, 1.96, -1.75, -0.35, "black")
    b.strut("RollBar", (0.81, 1.93, -0.35), (0.81, 1.77, 0.37), 0.05, "black", mirror=True)
    x.spare_tire(b, -2.12, 1.0, r=0.4, w=0.28)
    x.flares(b, s, 0.42)
    b.shape("CageShape", (1.7, 0.8, 1.5), (0, 1.55, -1.05))


V("palmetto", "Palmetto", "suv", "utility", 1700, 3.4, 150, 5, 360, 4,
  ["glades", "waterfront", "residential"], "middle", ["#d9c27a", "#2e6b45", "#c1121f", "#f8f9fa", "#3a86ff"],
  sedan_body(4.0, 1.8, 0.5, 1.15, 1.15, 0.5, -1.9, 0.4, 0.0, greenhouse=False, nose=1.1, tail=1.12,
             lower=[(-2.0, 1.12), (-1.95, 1.15), (0.5, 1.15), (1.9, 1.1), (2.0, 1.0)], grille="black",
             grille_w=0.9, grille_h=0.3, bumper="black", driver_z=-0.15, seat_y=1.0),
  dict(wb=2.45, r=0.42, w=0.3, style="black", drive="awd", wells=False), extras=[_palmetto],
  desc="Doorless open-top 4x4 with a roll cage. Built for the Glades.")


def _workhorse(b, s):
    x.bed(b, s, -2.8, -0.55, 0.85, 1.25)
    x.flares(b, s, 0.38, width=0.06, material="paint")


V("workhorse", "Workhorse", "suv", "utility", 2200, 3.0, 165, 4, 400, 3,
  ["industrial", "suburbs", "glades", "residential"], "working",
  ["#f5f5f5", "#1f3a5f", "#8c1c13", "#4a4a4a", "#c6a15b"],
  sedan_body(5.6, 2.0, 0.5, 1.25, 1.95, 1.2, -0.5, 0.6, 0.0, nose=1.2, tail=0.85,
             lower=[(-2.8, 0.85), (-0.55, 0.85), (-0.55, 1.25), (2.4, 1.2), (2.8, 1.05)], bumper="chrome",
             grille="chrome", grille_w=1.1, grille_h=0.32, per_row=3, door_lines=[0.15]),
  dict(wb=3.4, r=0.38, w=0.26, offset=0.2), extras=[_workhorse],
  desc="Full-size work pickup with a bench seat for three.")


def _mudcat(b, s):
    x.bed(b, s, -2.65, -0.45, 1.2, 1.6, material="paint")
    b.span("RoofLights", -0.7, 0.7, 2.28, 2.36, 0.25, 0.35, "black")
    for i in range(5):
        b.box("RoofLight", (0.14, 0.12, 0.04), (-0.56 + i * 0.28, 2.32, 0.37), "headlight")
    x.flares(b, s, 0.55, width=0.14)
    b.span("Snorkel", 1.02, 1.1, 1.3, 2.2, 0.85, 0.95, "black")


V("mudcat", "Mudcat", "suv", "utility", 2500, 3.4, 160, 3, 450, 2,
  ["glades", "industrial"], "working", ["#3b5323", "#6b4226", "#ff6f00", "#202020", "#8d99ae"],
  sedan_body(5.3, 2.05, 0.85, 1.6, 2.25, 1.0, -0.3, 0.55, 0.0, nose=1.55, tail=1.2,
             lower=[(-2.65, 1.2), (-0.45, 1.2), (-0.45, 1.6), (2.2, 1.55), (2.65, 1.4)], bumper="black",
             bumper_h=0.25, grille="black", grille_w=1.2, grille_h=0.35, door_lines=[0.2]),
  dict(wb=3.2, r=0.55, w=0.38, style="black", drive="awd", offset=0.15, wells=False), extras=[_mudcat], com_y=1.0,
  handling_over=dict(rest=0.4),
  desc="Lifted swamp truck on mud tyres. Climbs anything, corners like a fridge.")


# --- Van ------------------------------------------------------------------------------------------------

def _tradesman(b, s):
    x.ladder(b, -2.5, 1.0, 2.42, width=0.5, material="steel", rungs=8)
    for z in (-2.2, -0.6, 0.8):
        b.span("RackLeg", -0.9, 0.9, 2.36, 2.42, z - 0.03, z + 0.03, "steel")
    b.side_label("Livery", "PALM COAST\nPLUMBING & AC", 1.5, -1.1, 1.0, size=0.0055, col=(0.05, 0.1, 0.3),
                 outline=0)


V("tradesman", "Tradesman", "van", "utility", 2300, 2.4, 140, 3, 380, 2,
  ["industrial", "residential", "suburbs", "downtown"], "working", ["#f4f4f4", "#e8e8e8", "#c9d6df"],
  sedan_body(5.4, 2.0, 0.4, 1.2, 2.35, 1.75, -2.65, 0.8, 0.0, nose=1.05, tail=1.2, panels=[(-2.66, 0.45)],
             b_pillars=[0.5], door_lines=[0.55, -0.5], grille_w=0.9),
  dict(wb=3.3, r=0.36, w=0.24, style="steel", offset=0.15), trim=["#1d3557"], extras=[_tradesman],
  desc="Panel van with a ladder rack. Every contractor in the county drives one.")


def _strongbox(b, s):
    x.cargo_box(b, s, -3.1, 0.85, 1.0, 2.75, material="paint")
    for z in (-2.9, -1.9, -0.9, 0.1):
        x.side_panel(b, s, z, z + 0.04, 1.05, 2.7, "steel")
    b.span("RearDoors", -0.9, 0.9, 1.1, 2.6, -3.14, -3.1, "steel")
    b.span("Gunport", 1.13, 1.17, 1.9, 2.0, -1.6, -1.3, "black")
    b.span("Gunport", -1.17, -1.13, 1.9, 2.0, -1.6, -1.3, "black")
    b.side_label("Livery", "PALM SECURE\nARMORED TRANSPORT", 2.25, -1.1, 1.15, size=0.0065, col=(0.9, 0.75, 0.2))
    x.lightbar(b, s, 0.55, 2.75, width=0.9, colors=("amber", "amber"))


V("strongbox", "Strongbox", "van", "truck", 5200, 1.9, 125, 2, 900, 2,
  ["downtown", "waterfront", "depot"], "service", ["#4b5320", "#5c5f63", "#2f3e46"],
  sedan_body(6.2, 2.3, 0.5, 1.35, 2.55, 2.2, 0.9, 0.5, 0.0, nose=1.3, tail=1.0, glass_w=2.0,
             lower=[(-3.1, 1.0), (0.85, 1.0), (0.85, 1.35), (2.7, 1.3), (3.1, 1.15)], bumper="black",
             bumper_h=0.3, grille="black", grille_w=1.3, grille_h=0.35, b_pillars=[1.4]),
  dict(wb=3.6, r=0.44, w=0.3, style="steel", offset=0.2), trim=["#1a1a1a"], extras=[_strongbox], stealable=False,
  matte=True, desc="Armoured cash-in-transit truck. Only obtainable through the heist.")


# --- Police ---------------------------------------------------------------------------------------------

def _cruiser(b, s):
    x.side_panel(b, s, -1.35, 1.05, 0.45, 0.93, "white")
    x.lightbar(b, s, -0.3, 1.47, width=1.3)
    x.push_bar(b, s, 0.35, 0.95, width=1.2)
    b.side_label("Livery", "PALM COUNTY\nSHERIFF", 0.72, -0.15, 0.95, size=0.0045, col=(0.06, 0.1, 0.3), outline=0)
    b.box("Spotlight", (0.12, 0.12, 0.18), (0.98, 1.05, 0.95), "chrome")


V("cruiser", "Palm County Cruiser", "police", "sedan", 1750, 4.2, 200, 6, 400, 4,
  ["downtown", "residential", "highway", "projects"], "service", ["#101216"],
  sedan_body(5.0, 1.9, 0.3, 1.0, 1.48, 1.15, -1.45, 0.8, 0.6, door_lines=[-0.15], bumper="black"),
  dict(wb=2.95, r=0.35, w=0.24, style="steel"), trim=["#f2f2f0"], stealable=True, extras=[_cruiser],
  desc="Standard sheriff's patrol car. Stealing one gets noticed.")


def _interceptor(b, s):
    x.side_panel(b, s, -1.6, 1.2, 0.6, 1.1, "white")
    x.lightbar(b, s, -0.1, 1.85, width=1.0, depth=0.2)
    x.push_bar(b, s, 0.45, 1.1, width=1.3)
    b.side_label("Livery", "PALM COUNTY\nSHERIFF", 0.86, -0.2, 1.0, size=0.0045, col=(0.06, 0.1, 0.3), outline=0)


V("interceptor", "Interceptor", "police", "utility", 1850, 5.2, 235, 6, 420, 4,
  ["highway", "downtown", "suburbs"], "service", ["#14213d"],
  sedan_body(5.1, 2.0, 0.4, 1.15, 1.8, 1.3, -2.2, 0.75, 0.2, nose=1.08, tail=1.12, door_lines=[0.0, -1.0],
             b_pillars=[-0.05, -1.1], bumper="black"),
  dict(wb=3.0, r=0.38, w=0.26, style="black", drive="awd"), trim=["#f2f2f0"], extras=[_interceptor],
  handling_over=dict(stiffness=75.0, roll=0.12),
  desc="Pursuit-spec police SUV. Fast, heavy and hard to shake.")


def _bulwark(b, s):
    b.span("Ram", -1.1, 1.1, 0.75, 1.15, 3.2, 3.45, "black")
    b.span("Hatch", -0.4, 0.4, 2.85, 3.05, -0.8, 0.0, "black")
    b.cyl("HatchRing", 0.45, 0.06, (0, 3.07, -0.4), "steel", sides=16)
    b.side_label("Livery", "SWAT", 1.7, -1.4, 1.25, size=0.012, col=(0.9, 0.9, 0.9))
    b.label("RearLivery", "SWAT", (0, 2.0, -3.22), (0, 180, 0), size=0.012)
    x.lightbar(b, s, 1.9, 2.86, width=1.4)
    for z in (-2.4, -1.4, -0.4, 0.6):
        b.span("Gunport", 1.24, 1.27, 1.95, 2.05, z, z + 0.25, "black")
        b.span("Gunport", -1.27, -1.24, 1.95, 2.05, z, z + 0.25, "black")


V("bulwark", "Bulwark SWAT", "police", "truck", 7500, 1.8, 130, 2, 1200, 10,
  ["depot", "projects", "downtown"], "service", ["#1b1f24", "#14213d"],
  sedan_body(6.4, 2.5, 0.7, 1.7, 2.85, 2.3, -3.1, 0.45, 0.0, nose=1.65, tail=1.7, glass_w=2.3,
             panels=[(-3.11, 1.6)], bumper="black", bumper_h=0.3, grille="black", grille_w=1.6, grille_h=0.4,
             door_lines=[1.4, -2.9], row_gap=0.6),
  dict(wb=3.8, r=0.55, w=0.4, style="black", drive="awd", offset=0.1), trim=["#c0c0c0"], extras=[_bulwark],
  stealable=False, com_y=1.2, desc="Armoured SWAT truck. Rams through roadblocks; seats a full team.")


# --- Emergency -------------------------------------------------------------------------------------------

def _medic(b, s):
    x.cargo_box(b, s, -3.3, 1.15, 0.85, 2.85, material="white", width=2.3)
    for y0 in (1.55,):
        x.side_panel(b, s, -3.3, 1.15, y0, y0 + 0.2, "red", inset=-0.04)
    b.side_label("Livery", "MEDIC 12", 2.25, -1.1, 1.15, size=0.011, col=(0.8, 0.05, 0.05), outline=0)
    b.label("RearLivery", "AMBULANCE", (0, 2.2, -3.32), (0, 180, 0), size=0.008, col=(0.8, 0.05, 0.05), outline=0)
    for xx in (1.05, -1.05):
        b.box("CornerLight", (0.18, 0.14, 0.22), (xx, 2.88, 1.0), "siren_red")
        b.box("CornerLight", (0.18, 0.14, 0.22), (xx, 2.88, -3.2), "siren_red")
    x.lightbar(b, s, 1.75, 2.22, width=1.2, colors=("siren_red", "white"))


V("medic", "Medic Unit", "emergency", "truck", 4200, 2.4, 150, 3, 500, 4,
  ["downtown", "residential", "highway"], "service", ["#f4f4f2"],
  sedan_body(6.6, 2.15, 0.45, 1.2, 2.2, 2.6, 1.2, 0.75, 0.0, nose=1.05, tail=0.85,
             lower=[(-3.3, 0.85), (1.15, 0.85), (1.15, 1.2), (2.9, 1.15), (3.3, 0.95)], b_pillars=[1.5]),
  dict(wb=3.9, r=0.4, w=0.28, style="steel", offset=0.3), trim=["#c1121f"], extras=[_medic], stealable=True,
  desc="Box ambulance. Carries a full med kit and a defibrillator.")


def _engine9(b, s):
    x.cargo_box(b, s, -4.75, 2.55, 0.6, 2.1, material="paint", width=2.5)
    for z in (-4.0, -2.9, -1.8, -0.7, 0.4, 1.5):
        x.side_panel(b, s, z, z + 0.95, 0.75, 1.95, "steel", inset=-0.005)
    b.span("Deck", -1.2, 1.2, 2.1, 2.2, -4.75, 2.55, "steel")
    x.ladder(b, -4.6, 4.3, 2.55, width=0.75, rungs=22)
    b.strut("LadderBase", (0.3, 2.2, -4.0), (0.3, 2.55, -4.0), 0.12, "steel", mirror=True)
    b.strut("LadderRest", (0.3, 2.2, 2.4), (0.3, 2.55, 2.4), 0.08, "steel", mirror=True)
    b.cyl("Turntable", 0.6, 0.15, (0, 2.27, -3.9), "steel", sides=20)
    x.lightbar(b, s, 3.55, 2.86, width=1.8)
    b.side_label("Livery", "ENGINE 9", 1.65, 3.3, 1.25, size=0.008, col=(1.0, 0.85, 0.2))
    b.side_label("Livery", "PALM COUNTY FIRE RESCUE", 1.42, -1.6, 1.26, size=0.007, col=(1.0, 0.85, 0.2))
    b.box("Siren", (0.3, 0.2, 0.1), (0, 0.85, 4.8), "chrome")


V("engine9", "Engine 9", "emergency", "truck", 12000, 1.6, 120, 2, 900, 6,
  ["downtown", "depot"], "service", ["#b80c09"],
  sedan_body(9.5, 2.5, 0.6, 1.45, 2.85, 4.5, 2.6, 0.5, 0.0, nose=1.4, tail=1.45, glass_w=2.3,
             lower=[(-4.75, 1.0), (2.55, 1.0), (2.55, 1.45), (4.75, 1.45)], bumper="chrome", bumper_h=0.3,
             grille="chrome", grille_w=1.4, grille_h=0.5, b_pillars=[3.55], door_lines=[3.6, 2.7]),
  dict(wb=5.3, r=0.52, w=0.32, style="steel", offset=0.4, tandem=1.35), trim=["#f2f2f2"], extras=[_engine9],
  stealable=True, com_y=1.1, desc="Ladder engine with tandem rear axle. Six crew, one very long turning circle.")


# --- Service & Commercial -------------------------------------------------------------------------------

def _cab(b, s):
    x.sign_box(b, "SUNSHINE", (0, 1.56, -0.25), (0.8, 0.22, 0.24))
    x.side_panel(b, s, -2.3, 2.3, 0.7, 0.78, "black")
    b.side_label("Livery", "SUNSHINE CAB  561-555-0199", 0.55, -0.1, 0.94, size=0.0035, col=(0.05, 0.05, 0.05),
                 outline=0)


V("sunshine_cab", "Sunshine Cab", "service", "sedan", 1450, 3.4, 170, 6, 300, 4,
  ["downtown", "waterfront", "residential", "highway"], "service", ["#f2c200"],
  sedan_body(4.7, 1.85, 0.3, 0.95, 1.42, 1.1, -1.35, 0.75, 0.55, door_lines=[-0.15]),
  dict(wb=2.75, r=0.34, w=0.24, style="steel"), trim=["#101010"], extras=[_cab],
  desc="The city's yellow taxi. Drive a fare, earn a fare.")


def _transit(b, s):
    x.side_panel(b, s, -5.6, 5.6, 1.05, 1.22, "paint2")
    x.sign_box(b, "12  DOWNTOWN", (0, 2.92, 5.77), (1.8, 0.3, 0.06), material="black", text_col=(1.0, 0.6, 0.1))
    b.side_label("Livery", "PALM METRO", 0.72, -2.0, 1.28, size=0.009, col=(0.1, 0.5, 0.5), outline=0)
    b.span("RoofPod", -0.9, 0.9, 3.12, 3.4, -4.6, -2.2, "white")
    for z in (4.0, 0.6):
        b.span("Door", 1.27, 1.3, 0.4, 2.7, z - 0.6, z + 0.6, "glass")


V("transit", "Metro Transit", "service", "truck", 11000, 1.4, 95, 1, 800, 24,
  ["downtown", "projects", "residential", "depot"], "service", ["#ececea"],
  sedan_body(11.5, 2.55, 0.35, 1.25, 3.1, 5.72, -5.72, 0.25, 0.05, nose=1.25, tail=1.25,
             lower=[(-5.75, 1.25), (5.75, 1.25)], b_pillars=[4.6, 3.3, 2.0, 0.6, -0.8, -2.2, -3.6, -5.0],
             bumper="black", bumper_h=0.28, grille=None, light_y=0.85, per_row=4, row_gap=1.45, mirrors=True),
  dict(wb=6.0, r=0.5, w=0.3, style="steel", offset=0.25), trim=["#1a8f8a"], extras=[_transit], com_y=0.9,
  desc="Low-floor city bus. Twenty-four seats, zero acceleration.")


def _haulmaster(b, s):
    x.cargo_box(b, s, -3.9, 2.15, 1.0, 3.4, material="white", width=2.45)
    b.side_label("Livery", "HAULMASTER\nMOVING & STORAGE", 2.3, -0.9, 1.225, size=0.009, col=(0.85, 0.35, 0.05))
    b.span("RollDoor", -1.1, 1.1, 1.05, 3.3, -3.93, -3.9, "steel")
    b.span("LiftGate", -1.15, 1.15, 0.6, 0.68, -4.25, -3.9, "steel")


V("haulmaster", "Haulmaster", "service", "truck", 7000, 1.6, 115, 2, 600, 2,
  ["industrial", "highway", "suburbs", "depot"], "service", ["#f4f4f4", "#d9d9d9", "#1d3557"],
  sedan_body(7.8, 2.3, 0.55, 1.35, 2.55, 3.6, 2.25, 0.55, 0.0, nose=1.3, tail=1.0, glass_w=2.1,
             lower=[(-3.9, 1.0), (2.2, 1.0), (2.2, 1.35), (3.6, 1.35), (3.9, 1.2)], bumper="black", bumper_h=0.3,
             grille="black", grille_w=1.3, grille_h=0.3, b_pillars=[2.75]),
  dict(wb=4.6, r=0.48, w=0.3, style="steel", offset=0.5), trim=["#c1121f"], extras=[_haulmaster],
  desc="Box truck. Slow and wide, with a lot of room in the back.")


def _hook_haul(b, s):
    b.span("Deck", -1.1, 1.1, 0.95, 1.05, -3.3, 0.5, "steel")
    b.span("Mast", -0.35, 0.35, 1.05, 2.4, -0.6, -0.2, "steel")
    b.strut("Boom", (0, 2.2, -0.4), (0, 1.55, -3.2), 0.24, "orange", depth=0.24)
    b.strut("Cable", (0, 1.5, -3.2), (0, 0.85, -3.25), 0.03, "black")
    b.box("Hook", (0.1, 0.18, 0.06), (0, 0.78, -3.25), "steel")
    b.span("WheelLift", -0.9, 0.9, 0.42, 0.52, -3.75, -3.3, "orange")
    b.span("WheelLiftArm", -0.12, 0.12, 0.45, 0.55, -3.5, -2.5, "steel")
    x.lightbar(b, s, 0.35, 2.47, width=1.4, colors=("amber", "amber"))
    b.side_label("Livery", "HOOK & HAUL\nTOWING 24/7", 1.18, 1.25, 1.15, size=0.005, col=(0.95, 0.8, 0.1))


V("hook_haul", "Hook & Haul", "service", "truck", 4500, 2.2, 130, 3, 550, 2,
  ["industrial", "highway", "residential"], "service", ["#f4f4f4", "#1d3557", "#e63946"],
  sedan_body(6.6, 2.25, 0.55, 1.35, 2.45, 2.0, 0.55, 0.55, 0.0, nose=1.3, tail=1.0, glass_w=2.0,
             lower=[(-3.3, 1.0), (0.5, 1.0), (0.5, 1.35), (2.6, 1.3), (3.3, 1.15)], bumper="chrome", bumper_h=0.28,
             grille="chrome", grille_w=1.1, grille_h=0.35, b_pillars=[1.05]),
  dict(wb=3.8, r=0.45, w=0.3, style="steel", offset=0.4), trim=["#ffb703"], extras=[_hook_haul],
  desc="Wrecker with a boom and wheel-lift. Hooks up whatever you park badly.")


def _compactor(b, s):
    x.cargo_box(b, s, -3.9, 3.05, 1.0, 3.3, material="paint", width=2.45)
    b.span("Hopper", -1.25, 1.25, 0.8, 2.9, -4.5, -3.9, "steel")
    b.wedge("HopperTop", -4.5, -3.9, 2.9, 3.4, 2.5, "steel", flip=True)
    for z in (-2.6, -1.2, 0.2, 1.6):
        x.side_panel(b, s, z, z + 0.05, 1.05, 3.25, "paint2", inset=-0.02)
    b.side_label("Livery", "PALM COUNTY\nSANITATION", 2.15, -0.5, 1.245, size=0.009, col=(1, 1, 1))
    b.box("Beacon", (0.2, 0.16, 0.2), (0.9, 3.4, 2.8), "amber")
    b.box("Beacon", (0.2, 0.16, 0.2), (-0.9, 3.4, 2.8), "amber")
    b.span("Step", -1.0, 1.0, 0.55, 0.6, -4.8, -4.5, "steel")


V("compactor", "Compactor", "service", "truck", 13000, 1.3, 95, 1, 850, 3,
  ["residential", "projects", "industrial", "depot"], "service", ["#2d6a4f", "#f4f4f4"],
  sedan_body(9.0, 2.45, 0.55, 1.5, 2.75, 4.48, 3.15, 0.18, 0.0, nose=1.5, tail=1.0, glass_w=2.25,
             lower=[(-4.5, 1.0), (3.1, 1.0), (3.1, 1.5), (4.5, 1.5)], bumper="steel", bumper_h=0.3, grille="steel",
             grille_w=1.4, grille_h=0.4, b_pillars=[3.8], driver_z=4.0, per_row=3),
  dict(wb=4.8, r=0.5, w=0.32, style="steel", offset=0.6, tandem=1.35), trim=["#f4f4f4"], extras=[_compactor],
  com_y=1.1, desc="Rear-loader garbage truck. The heaviest thing on the lot.")


# --- Motorcycle & Scooter -------------------------------------------------------------------------------

V("razorback", "Razorback", "bike", "bike", 220, 7.5, 260, 9, 120, 2,
  ["downtown", "highway", "waterfront"], "middle", ["#d00000", "#0a0a0a", "#ffba08", "#3a86ff", "#f2f2f2"],
  dict(L=2.1, W=0.7, roof=1.1), dict(wb=1.42, r=0.32, w=0.18, style="black"), style="bike", com_y=0.35,
  trim=["#111111", "#f2f2f2"], desc="Superbike. Fastest launch in the game; one bump and you're off.")

V("zippy", "Zippy", "bike", "bike", 110, 3.5, 75, 8, 90, 2,
  ["downtown", "waterfront", "residential"], "poor", ["#90e0ef", "#ffafcc", "#ffd166", "#06d6a0", "#ef476f"],
  dict(L=1.8, W=0.7, roof=1.1, scooter=True), dict(wb=1.25, r=0.22, w=0.12, style="steel"), style="bike",
  com_y=0.3, trim=["#f2f2f2"], desc="49cc scooter with a basket. Slow, cheap and weaves through traffic.")


# --- Boat (display only) --------------------------------------------------------------------------------

V("gladesrunner", "Gladesrunner", "boat", "utility", 900, 0.0, 70, 5, 250, 2,
  ["glades"], "working", ["#2a7fb8", "#2d6a4f", "#e9c46a", "#e76f51"],
  dict(L=5.0, W=2.4, roof=3.0), dict(wb=0.0, r=0.33, w=0.22), style="airboat", drivable=False,
  trim=["#e63946", "#f4f4f4"],
  desc="Everglades airboat on its trailer. Display only until the game has water.")
