"""Generates the exterior-only house kit and stand-in businesses: textures, materials, part
scenes, 25 house scenes, 13 business scenes (5 closed, 8 enterable shops) and the showcase street.

    python tools/houses/build_houses.py            # everything
    python tools/houses/build_houses.py --only 1F-03 2F-05   # just these houses (+ showcase)

WARNING: re-running overwrites the generated .tscn files, including hand edits made in the
Godot editor. Once you start editing a house by hand, leave it out (use --only for the rest).
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import materials  # noqa: E402
from builder import HouseBuilder  # noqa: E402
from business import BusinessBuilder  # noqa: E402
from specs_one import ONE_FLOOR  # noqa: E402
from specs_two import TWO_FLOOR  # noqa: E402
from specs_biz import CLOSED, SHOPS  # noqa: E402
from tscn import Scene, box, combiner, xform  # noqa: E402

PARTS = {
    "house_window": ("house_window.gd", "HouseWindow", "Vector3(1.1, 1.5, 0.24)"),
    "house_door": ("house_door.gd", "HouseDoor", "Vector3(1.2, 2.4, 0.3)"),
    "garage_door": ("garage_door.gd", "GarageDoor", "Vector3(2.7, 2.3, 0.3)"),
}
SHOWCASE = "scenes/houses/house_showcase.tscn"
ROAD_HALF = 4.5
WALK = 2.0
GAP = 1.0
BIZ_GAP = 15.0

for _s in SHOPS:
    _s["enterable"] = True


def house_path(spec):
    folder = "one_floor" if spec["floors"] == 1 else "two_floor"
    return "scenes/houses/%s/house_%s.tscn" % (folder, spec["id"].lower().replace("-", "_"))


def write_parts():
    for name, (script, node, size) in PARTS.items():
        text = "\n".join([
            "[gd_scene load_steps=2 format=3]", "",
            '[ext_resource type="Script" path="res://scripts/world/houses/%s" id="1_s"]' % script, "",
            '[node name="%s" type="CSGBox3D"]' % node,
            "operation = 2", "size = %s" % size, 'script = ExtResource("1_s")', ""])
        with open(os.path.join(ROOT, "scenes/houses/parts", name + ".tscn"), "w", newline="\n") as fh:
            fh.write(text)


def scene_path(spec):
    if "body" in spec:
        kind = "shops" if spec.get("enterable") else "closed"
        prefix = "shop" if spec.get("enterable") else "business"
        return "scenes/businesses/%s/%s_%s.tscn" % (kind, prefix, spec["id"].lower().replace("-", "_"))
    return house_path(spec)


def write_showcase():
    sc = Scene()
    root = sc.node("HouseShowcase", "Node3D", None, {
        "script": sc.res("res://scripts/world/houses/house_showcase.gd", "Script")})
    # North side: one-floor houses then closed stand-ins; south side: two-floor houses then shops.
    rows = [(ONE_FLOOR, CLOSED, -1), (TWO_FLOOR, SHOPS, 1)]

    def row_len(specs):
        return sum(s["lot"][0] for s in specs) + GAP * (len(specs) - 1)

    house_len = max(row_len(h) for h, _, _ in rows)
    total = house_len + BIZ_GAP + max(row_len(b) for _, b, _ in rows)
    length = total + 30
    start = -total / 2
    max_depth = max(s["lot"][1] for h, b, _ in rows for s in h + b)
    edge = ROAD_HALF + WALK
    ground = combiner(sc, root, "Street", collision=True)
    far = edge + max_depth + 10
    box(sc, ground, "Ground", -length / 2, length / 2, -0.6, -0.02, -far, -ROAD_HALF, "ground")
    box(sc, ground, "Ground", -length / 2, length / 2, -0.6, -0.02, ROAD_HALF, far, "ground")
    box(sc, ground, "Road", -length / 2, length / 2, -0.6, -0.08, -ROAD_HALF, ROAD_HALF, "asphalt")
    for sgn in (-1, 1):
        z0, z1 = sorted((sgn * ROAD_HALF, sgn * edge))
        box(sc, ground, "Sidewalk", -length / 2, length / 2, -0.6, 0.06, z0, z1, "sidewalk")
        kz = sgn * (ROAD_HALF + 0.08)
        box(sc, ground, "Kerb", -length / 2, length / 2, -0.6, 0.08, kz - 0.08, kz + 0.08, "concrete")
    x = -length / 2 + 3
    while x < length / 2 - 3:
        box(sc, ground, "Dash", x, x + 3, -0.08, -0.07, -0.08, 0.08, "road_line")
        x += 6
    houses = sc.node("Houses", "Node3D", root)
    businesses = sc.node("Businesses", "Node3D", root)
    cars = sc.node("CarSpots", "Node3D", root)
    first_spot = None

    def place(parent, specs, side, cursor):
        nonlocal first_spot
        for s in specs:
            w, _ = s["lot"]
            cx = cursor + w / 2
            cursor += w + GAP
            yaw = 0 if side < 0 else 180
            sc.node(s["id"].replace("-", "_"), None, parent, {
                "transform": xform((cx, 0, side * edge), yaw), "show_label": "true"},
                instance="res://" + scene_path(s))
            if first_spot is None:
                first_spot = cx

            def car(lx, lz, cyaw):
                wx = cx + (lx if side < 0 else -lx)
                wz = side * (edge - lz)
                sc.node("Car", "Marker3D", cars, {"transform": xform((wx, 0.6, wz), cyaw + yaw)})

            if "cars" in s:
                for lx, lz, cyaw in s["cars"]:
                    car(lx, lz, cyaw)
                continue
            # Houses: park a car on the first paved strip that reaches the street (driveway).
            for pv in s.get("paving", []):
                x0, x1, z0, z1 = pv[:4]
                if z1 >= -0.01 and x1 - x0 >= 2.4 and z1 - z0 >= 5.5:
                    car((x0 + x1) / 2, -3.2, 0)
                    break

    for hs, bs, side in rows:
        place(houses, hs, side, start)
        place(businesses, bs, side, start + house_len + BIZ_GAP)
    sc.node("Player", None, root, {"transform": xform((first_spot, 1.0, -edge + 1.0), 0)},
            instance="res://scenes/player/player.tscn")
    sc.save(os.path.join(ROOT, SHOWCASE))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", help="house / business ids to (re)generate")
    ap.add_argument("--no-textures", action="store_true")
    args = ap.parse_args()
    for d in ("scenes/houses/parts", "scenes/houses/one_floor", "scenes/houses/two_floor",
              "scenes/businesses/closed", "scenes/businesses/shops"):
        os.makedirs(os.path.join(ROOT, d), exist_ok=True)
    if not args.no_textures:
        materials.write_all(ROOT)
    write_parts()
    bad = False
    for spec in ONE_FLOOR + TWO_FLOOR + CLOSED + SHOPS:
        if args.only and spec["id"] not in args.only:
            continue
        b = BusinessBuilder(spec) if "body" in spec else HouseBuilder(spec)
        for p in b.validate():
            print("%s: %s" % (spec["id"], p))
            bad = True
        b.build().save(os.path.join(ROOT, scene_path(spec)))
    write_showcase()
    print("houses: %d one-floor, %d two-floor; businesses: %d closed, %d shops"
          % (len(ONE_FLOOR), len(TWO_FLOOR), len(CLOSED), len(SHOPS)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
