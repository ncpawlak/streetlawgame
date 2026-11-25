"""Generates the vehicle kit: one scene per vehicle, the JSON registry and the showcase lot.

    python tools/vehicles/build_vehicles.py

Writes scenes/vehicles/<class>/<id>.tscn, data/vehicles/vehicles.json and
scenes/vehicles/vehicle_showcase.tscn. Re-run after editing specs.py; the outputs are plain
Godot files and can also be tweaked in the editor (re-running overwrites them)."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import styles  # noqa: E402
from builder import VehicleBuilder  # noqa: E402
from specs import CLASSES, SPECS  # noqa: E402
from tscn import Scene, color, f, hex_rgb, quote, v3, xform  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
G = 9.8


def scene_name(spec):
    return "".join(ch for ch in spec["name"].title() if ch.isalnum())


def res_path(spec):
    return "res://scenes/vehicles/%s/%s.tscn" % (spec["cls"], spec["id"])


def rating(value, lo, hi):
    return max(1, min(10, int(round(1 + 9 * (value - lo) / (hi - lo)))))


def build_vehicle(spec):
    spec["scene_name"] = scene_name(spec)
    b = VehicleBuilder(spec)
    styles.STYLES[spec["style"]](b, spec)
    for extra in spec["extras"]:
        extra(b, spec)
    body = spec["body"]
    cam_dist, cam_h = styles.camera(spec)
    h = spec["handling"]
    traction = max(1, spec.get("traction_wheels", 2))
    spec["engine_force"] = round(spec["accel"] * spec["mass"] / traction, 1)
    spec["brake"] = round(spec["mass"] * 0.06, 1)
    spec["max_speed"] = round(spec["top_kph"] / 3.6, 2)
    com_y = spec["com_y"] if spec["com_y"] is not None else max(0.3, body.get("ride", 0.3) + 0.1)
    if spec["drivable"]:
        props = {
            "collision_layer": "8",
            "collision_mask": "15",
            "mass": f(spec["mass"]),
            "center_of_mass_mode": "1",
            "center_of_mass": v3(0, com_y, 0),
            "script": b.root_props["script"],
            "model_id": "&\"%s\"" % spec["id"],
            "max_engine_force": f(spec["engine_force"]),
            "max_brake_force": f(spec["brake"]),
            "max_steer": f(h["max_steer"]),
            "steer_speed": f(h["steer_speed"]),
            "max_speed": f(spec["max_speed"]),
            "steer_falloff": f(STEER_FALLOFF),
            "upright_assist": f(upright_assist(spec)),
            "max_health": f(spec["health"]),
            "camera_distance": f(cam_dist),
            "camera_height": f(cam_h),
        }
    else:
        props = {"metadata/model_id": quote(spec["id"])}
    out = os.path.join(ROOT, "scenes", "vehicles", spec["cls"], spec["id"] + ".tscn")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    b.save(out, props)
    return b


# Arcade stabilisers (see vehicle.gd): steering lock halves by ~30 m/s, and the roll assist is
# stronger for tall or narrow vehicles that would otherwise tip over in a full-lock turn.
STEER_FALLOFF = 0.035
UPRIGHT = {"bike": 30.0, "sports": 10.0, "muscle": 8.0, "police": 10.0, "suv": 10.0,
           "van": 12.0, "emergency": 14.0, "service": 12.0, "lowrider": 10.0}


def upright_assist(spec):
    return UPRIGHT.get(spec["cls"], 6.0)


def registry_entry(spec):
    body = spec["body"]
    h = spec["handling"]
    return {
        "id": spec["id"],
        "name": spec["name"],
        "class": spec["cls"],
        "class_name": CLASSES[spec["cls"]][0],
        "scene": res_path(spec),
        "drivable": spec["drivable"],
        "mass": spec["mass"],
        "top_speed_kph": spec["top_kph"],
        "max_speed": spec["max_speed"],
        "engine_force": spec["engine_force"],
        "brake_force": spec["brake"],
        "acceleration": spec["accel"],
        "acceleration_rating": rating(spec["accel"], 1.3, 7.5) if spec["drivable"] else 0,
        "handling_rating": spec["handling_rating"],
        "handling": {k: h[k] for k in ("grip", "rear_grip", "max_steer", "steer_speed", "stiffness", "roll")
                     if k in h},
        "health": spec["health"],
        "seats": spec["seats"],
        "spawn_zones": spec["spawn_zones"],
        "income_tier": spec["income_tier"],
        "stealable": spec["stealable"],
        "palette": spec["palette"],
        "trim_palette": spec["trim_palette"],
        "size_m": [body.get("W", 0.7), max(body.get("roof", 0), body.get("belt", 0)), body["L"]],
        "wheels": spec.get("wheel_count", 0),
        "description": spec["description"],
    }


# --- showcase ------------------------------------------------------------------------------------------

AISLE = 7.0  # half width of the central aisle (z = 0)
PAD_DEPTH = 13.0
LOOP_X, LOOP_Z, LOOP_W = 75.0, 42.0, 14.0
GROUND = {"albedo_color": color((0.3, 0.45, 0.22)), "roughness": "1.0"}
ASPHALT = {"albedo_color": color((0.16, 0.16, 0.17)), "roughness": "0.92"}
CONCRETE = {"albedo_color": color((0.55, 0.55, 0.53)), "roughness": "0.9"}
LINE = {"albedo_color": color((0.95, 0.85, 0.3)), "roughness": "0.7"}
WHITE = {"albedo_color": color((0.92, 0.92, 0.9)), "roughness": "0.7"}
CURB = {"albedo_color": color((0.8, 0.15, 0.12)), "roughness": "0.7"}
POST = {"albedo_color": color((0.2, 0.2, 0.22)), "metallic": "0.6", "roughness": "0.4"}
BOARD = {"albedo_color": color((0.08, 0.09, 0.11)), "roughness": "0.8"}


def layout(specs):
    """Splits the line-up into two facing rows (class order kept, never splitting a class across
    rows, as evenly as possible) and returns pad placements."""
    widths = [max(4.4, s["body"].get("W", 1.0) + 2.6) for s in specs]
    total = sum(widths) + 1.2 * (len(widths) - 1)
    half, acc, split, best = total / 2, 0.0, len(specs), float("inf")
    for i, w in enumerate(widths[:-1]):
        acc += w + 1.2
        if specs[i]["cls"] != specs[i + 1]["cls"] and abs(acc - half) < best:
            split, best = i + 1, abs(acc - half)
    pads = []
    for row, (chunk, cw) in enumerate(((specs[:split], widths[:split]), (specs[split:], widths[split:]))):
        length = sum(cw) + 1.2 * (len(cw) - 1)
        x = -length / 2
        side = 1 if row == 0 else -1
        for s, w in zip(chunk, cw):
            pads.append((s, x + w / 2, side * (AISLE + PAD_DEPTH / 2), side, w))
            x += w + 1.2
    return pads


def build_showcase(specs):
    sc = Scene()
    sc.node("VehicleShowcase", "Node3D", None, {"script": sc.res("res://scripts/vehicles/vehicle_showcase.gd", "Script")})
    mats = {k: sc.sub("StandardMaterial3D", v) for k, v in
            {"ground": GROUND, "asphalt": ASPHALT, "concrete": CONCRETE, "line": LINE, "white": WHITE, "curb": CURB,
             "post": POST, "board": BOARD}.items()}

    def box(name, parent, size, pos, mat, rot=(0, 0, 0)):
        mesh = sc.sub("BoxMesh", {"material": mats[mat], "size": v3(*size)})
        sc.node(name, "MeshInstance3D", parent, {"transform": xform(pos, rot), "mesh": mesh})

    def solid(name, parent, size, pos, mat, rot=(0, 0, 0)):
        body = sc.node(name, "StaticBody3D", parent, {"transform": xform(pos, rot)})
        box("Mesh", body, size, (0, 0, 0), mat)
        sc.node("Shape", "CollisionShape3D", body, {"shape": sc.sub("BoxShape3D", {"size": v3(*size)})})

    # Ground: one flat collider, the road and lot surfaces are visual only (slightly raised).
    solid("Ground", ".", (420, 1, 300), (0, -0.5, 0), "ground")
    ground_vis = sc.node("Surfaces", "Node3D", ".")
    pads = layout(specs)
    lot_x = max(abs(px) + w / 2 for _, px, _, _, w in pads) + 4
    box("Lot", ground_vis, (lot_x * 2, 0.02, 2 * (AISLE + PAD_DEPTH) + 4), (0, 0.01, 0), "asphalt")
    box("Aisle", ground_vis, (2 * LOOP_X, 0.02, AISLE * 2), (0, 0.012, 0), "asphalt")
    for i in range(int(LOOP_X * 2 / 6)):
        box("AisleDash", ground_vis, (3, 0.01, 0.15), (-LOOP_X + 3 + i * 6, 0.025, 0), "line")
    # Test loop: rectangle around the lot, joined to the aisle at both ends.
    for z in (LOOP_Z, -LOOP_Z):
        box("LoopStraight", ground_vis, (2 * LOOP_X + LOOP_W, 0.02, LOOP_W), (0, 0.011, z), "asphalt")
        box("LoopLine", ground_vis, (2 * LOOP_X - LOOP_W, 0.01, 0.15), (0, 0.025, z), "white")
    for xx in (LOOP_X, -LOOP_X):
        box("LoopSide", ground_vis, (LOOP_W, 0.02, 2 * LOOP_Z + LOOP_W), (xx, 0.011, 0), "asphalt")
        box("LoopLine", ground_vis, (0.15, 0.01, 2 * LOOP_Z - LOOP_W), (xx, 0.025, 0), "white")
        for z in (LOOP_Z + LOOP_W / 2, -LOOP_Z - LOOP_W / 2):
            box("Curb", ground_vis, (LOOP_W, 0.06, 0.4), (xx, 0.03, z), "curb")
    box("StartLine", ground_vis, (1.0, 0.01, LOOP_W), (0, 0.026, -LOOP_Z), "white")
    # A gentle jump ramp on the far straight, in the outer lane only.
    solid("Ramp", ".", (9, 0.6, LOOP_W / 2 - 1), (30, 0.45, -LOOP_Z - LOOP_W / 4), "concrete", rot=(0, 0, 9))
    # Pads, kiosk signs and spawn markers.
    pad_root = sc.node("Pads", "Node3D", ".")
    for s, px, pz, side, w in pads:
        name = scene_name(s)
        pad = sc.node(name, "Node3D", pad_root, {"transform": xform((px, 0, pz))})
        box("Slab", pad, (w, 0.04, PAD_DEPTH - 0.5), (0, 0.02, 0), "concrete")
        front = -side * (PAD_DEPTH / 2 - 0.25)
        line_mat = sc.sub("StandardMaterial3D", {"albedo_color": color(hex_rgb(CLASSES[s["cls"]][1])),
                                                 "roughness": "0.6"})
        mesh = sc.sub("BoxMesh", {"material": line_mat, "size": v3(w, 0.01, 0.35)})
        sc.node("ClassLine", "MeshInstance3D", pad, {"transform": xform((0, 0.045, front)), "mesh": mesh})
        # The vehicle faces the aisle: row +z points -z (yaw 180), row -z points +z.
        yaw = 180 if side > 0 else 0
        sc.node("Spawn", "Marker3D", pad, {"transform": xform((0, 0.05, 0), (0, yaw, 0)),
                                           "metadata/vehicle_id": quote(s["id"])})
        # Kiosk at the aisle-side corner, readable from the aisle.
        kx = w / 2 - 0.45
        kz = front - side * 0.1
        kiosk = sc.node("Kiosk", "Node3D", pad, {"transform": xform((kx, 0, kz), (0, yaw, 0))})
        box("Post", kiosk, (0.1, 1.2, 0.1), (0, 0.6, 0), "post")
        box("Board", kiosk, (1.95, 1.25, 0.06), (0, 1.75, -0.04), "board")
        hmesh = sc.sub("BoxMesh", {"material": line_mat, "size": v3(1.95, 0.3, 0.07)})
        sc.node("Header", "MeshInstance3D", kiosk, {"transform": xform((0, 2.5, -0.04)), "mesh": hmesh})
        sc.node("Name", "Label3D", kiosk, {
            "transform": xform((0, 2.5, 0.0)), "pixel_size": "0.0026", "font_size": "64", "outline_size": "8",
            "text": quote(s["name"].upper()), "double_sided": "false"})
        sc.node("Stats", "Label3D", kiosk, {
            "transform": xform((-0.9, 1.75, 0.0)), "pixel_size": "0.0027", "font_size": "36", "outline_size": "0",
            "horizontal_alignment": "0", "double_sided": "false", "modulate": color((0.92, 0.94, 0.96)),
            "text": quote(kiosk_text(s))})
    sc.node("Vehicles", "Node3D", ".")
    sc.node("Player", None, ".", {"transform": xform((-LOOP_X + 12, 1.2, 0), (0, 90, 0))},
            instance="res://scenes/player/player.tscn")
    sc.node("HUD", "CanvasLayer", ".", {"script": sc.res("res://scripts/ui/hud.gd", "Script")})
    sc.save(os.path.join(ROOT, "scenes", "vehicles", "vehicle_showcase.tscn"))


def kiosk_text(s):
    if not s["drivable"]:
        return "%s\n\nDisplay only\nSeats %d   Mass %d kg\n%s" % (CLASSES[s["cls"]][0], s["seats"], s["mass"],
                                                                 "Zones: " + ", ".join(s["spawn_zones"]))
    stars = lambda n: "#" * n + "-" * (10 - n)  # noqa: E731
    acc = rating(s["accel"], 1.3, 7.5)
    return ("%s\nTop speed  %d km/h\nAccel      %s\nHandling   %s\nHealth %d   Seats %d\nMass %d kg   %s\n%s"
            % (CLASSES[s["cls"]][0], s["top_kph"], stars(acc), stars(s["handling_rating"]), s["health"], s["seats"],
               s["mass"], s["income_tier"].title(), "Stealable" if s["stealable"] else "Not stealable"))


def main():
    registry = []
    for spec in SPECS:
        build_vehicle(spec)
        registry.append(registry_entry(spec))
    out = os.path.join(ROOT, "data", "vehicles", "vehicles.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", newline="\n") as fh:
        json.dump({"version": 1, "classes": {k: {"name": v[0], "color": v[1]} for k, v in CLASSES.items()},
                   "vehicles": registry}, fh, indent=1)
        fh.write("\n")
    build_showcase(SPECS)
    print("Built %d vehicles (%d drivable)." % (len(SPECS), sum(1 for s in SPECS if s["drivable"])))


if __name__ == "__main__":
    main()
