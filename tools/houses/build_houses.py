"""Generates the exterior-only building kit: textures, materials, part scenes, 25 house scenes,
13 phase-1 stand-in businesses (5 closed, 8 shops), 32 North End census buildings
(scenes/buildings/ + S-09), the two-street showcase and data/buildings/building_kit.json
(census archetype -> scenes). Bake the meshes afterwards with tools/bake_kit.tscn.

    python tools/houses/build_houses.py            # everything
    python tools/houses/build_houses.py --only 1F-03 2F-05   # just these houses (+ showcase)

WARNING: re-running overwrites the generated .tscn files, including hand edits made in the
Godot editor. Once you start editing a house by hand, leave it out (use --only for the rest).
"""
import argparse
import json
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
from specs_extra import EXTRA, STREET2_NORTH, STREET2_SOUTH  # noqa: E402
from census import CENSUS, CENSUS_COMMIT, MD_ONLY  # noqa: E402
from tscn import Scene, box, combiner, f, xform  # noqa: E402
import props as kit_props  # noqa: E402
import specs_fl  # noqa: E402

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
ALL_SPECS = ONE_FLOOR + TWO_FLOOR + CLOSED + SHOPS + EXTRA


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
    if "folder" in spec:
        prefix = "shop" if spec.get("enterable") else "building"
        return "scenes/buildings/%s/%s_%s.tscn" % (spec["folder"], prefix, spec["id"].lower().replace("-", "_"))
    if "body" in spec:
        kind = "shops" if spec.get("enterable") else "closed"
        prefix = "shop" if spec.get("enterable") else "business"
        return "scenes/businesses/%s/%s_%s.tscn" % (kind, prefix, spec["id"].lower().replace("-", "_"))
    return house_path(spec)


STREET2_GAP = 6.0
VARIANTS = [("1F-02", [0, 1, 2, 3]), ("2F-03", [0, 1, 2, 3]), ("1F-07", [0, 1, 2, 3])]
BY_ID = {}


TIER_DEMO = ("1F-06", ["low", "medium", "high"])
PROPS_BUILT = []
GALLERY_NORTH = ["royal_palm", "coconut_palm", "sabal_palm", "banyan", "live_oak", "sea_grape", "sea_grape_hedge",
                 "brush_clump", "weeds_tall", "hibiscus_bed", "bougainvillea", "flower_bed", "sand_patch",
                 "dirt_patch", "fallen_frond", "garden_pond"]
GALLERY_SOUTH = ["chain_fence_3m", "block_wall_3m", "carport_metal", "trash_bin", "recycle_bin", "laundry_line",
                 "above_ground_pool", "pavers_patio", "shopping_cart", "screened_pool_small", "screened_pool",
                 "retention_pond", "overgrown_lot", "mailbox", "mailbox_cluster", "newspaper_boxes", "bus_bench",
                 "bus_shelter", "power_pole", "power_pole_transformer"]
# Wall-mounted props shown on a display wall: (id, x offset, mount height, window w, h or None).
GALLERY_WALL = [("wall_ac", 1.2, 1.4, None), ("satellite_dish", 2.8, 2.6, None), ("rust_streak", 4.2, 2.4, None),
                ("graffiti_tag", 6.0, 1.2, None), ("window_ac", 8.6, 1.2, (1.1, 1.5)),
                ("window_bars", 10.6, 2.05, (1.1, 1.5)), ("storm_panel", 12.6, 2.05, (1.1, 1.5)),
                ("mural", 18.0, 2.0, None)]
GALLERY_WALL_LEN = 22.0
CANAL_LEN = 24.0


def _prop_dims(p):
    if p.cut:
        return p.cut[2] + 2.4, p.cut[3] + 2.4
    if p.id == "overgrown_lot":
        return 12.0, 20.0
    return 2 * p.radius, 2 * p.radius


def _gallery_len():
    by = {p.id: p for p in PROPS_BUILT}
    north = sum(_prop_dims(by[i])[0] + 1.5 for i in GALLERY_NORTH) + GALLERY_WALL_LEN + 3
    south = sum(_prop_dims(by[i])[0] + 1.5 for i in GALLERY_SOUTH)
    return max(north, south)


def write_gallery(sc, root, ground, gx, edge):
    """Florida gallery east of Street 1: every prop labelled, a display wall for the wall / window
    props, a canal behind the north row and the retention pond cut into the ground."""
    by = {p.id: p for p in PROPS_BUILT}
    gal = sc.node("FloridaGallery", "Node3D", root)
    glen = _gallery_len()
    for sgn in (-1, 1):  # lot-grade grass slab both sides (props sit at y = 0)
        z0, z1 = sorted((sgn * edge, sgn * (edge + 32)))
        box(sc, ground, "GalleryGrass", gx - 2, gx + glen + 2, -0.6, 0.0, z0, z1, "grass")
    cuts = []

    def put(pid, cx, cz, yaw):
        p = by[pid]
        sc.node(pid, None, gal, {"transform": xform((cx, 0, cz), yaw), "show_label": "true"},
                instance="res://" + p.path())
        if p.cut:
            x, z, w, d = p.cut
            cuts.append((cx + x, cx + x + w, cz + z, cz + z + d))

    for side, ids in ((-1, GALLERY_NORTH), (1, GALLERY_SOUTH)):
        cursor = gx
        for pid in ids:
            w, d = _prop_dims(by[pid])
            put(pid, cursor + w / 2, side * (edge + d / 2 + 1.0), 0 if side < 0 else 180)
            cursor += w + 1.5
        if side < 0:
            wall_x = cursor
    wz = -(edge + 4.0)
    walls = combiner(sc, gal, "DisplayWall", collision=True)
    box(sc, walls, "Wall", wall_x, wall_x + GALLERY_WALL_LEN, 0.0, 3.4, wz - 0.3, wz, "stucco_mint")
    box(sc, walls, "Cap", wall_x - 0.05, wall_x + GALLERY_WALL_LEN + 0.05, 3.4, 3.55, wz - 0.35, wz + 0.05,
        "trim_white")
    for pid, dx, y, win in GALLERY_WALL:
        p = by[pid]
        x = wall_x + dx
        props = {"transform": xform((x, y, wz + 0.01)), "show_label": "true"}
        if win:
            w, h = win
            box(sc, walls, "Window", x - w / 2, x + w / 2, (y if pid != "window_ac" else y + h / 2) - h / 2,
                (y if pid != "window_ac" else y + h / 2) + h / 2, wz - 0.05, wz + 0.02, "glass")
            if pid != "window_ac":
                props["transform"] = xform((x, y, wz + 0.02), 0, (w, h, 1))
        sc.node(pid, None, gal, props, instance="res://" + p.path())
    cz = -(edge + 20.0)
    x = gx
    while x < gx + glen - CANAL_LEN / 2:
        put("canal_segment", x + CANAL_LEN / 2, cz, 0)
        x += CANAL_LEN
    for n, (x0, x1, z0, z1) in enumerate(cuts):
        box(sc, ground, "WaterCut", x0, x1, -4.0, 0.5, z0, z1, None, op=2)


def write_street_furniture(sc, root, west, length, z2, gap_x, edge):
    """Wooden power poles with sagging lines along both streets, a bus stop, mailboxes and
    newspaper boxes in the gap between the house and business blocks."""
    by = {p.id: p for p in PROPS_BUILT}
    street = sc.node("StreetFurniture", "Node3D", root)
    run_script = sc.res("res://scripts/world/houses/power_line_run.gd", "Script")
    x0, x1 = west + 2 * ROAD_HALF + 4, length / 2 - 4
    n = max(2, int((x1 - x0) // 32) + 1)
    step = (x1 - x0) / (n - 1)
    for name, z in (("PowerLine1", -(ROAD_HALF + 0.6)), ("PowerLine2", z2 + ROAD_HALF + 0.6)):
        pts = ", ".join("%s, 0.06, %s" % (f(x0 + i * step), f(z)) for i in range(n))
        sc.node(name, "Node3D", street, {"script": run_script, "points": "PackedVector3Array(%s)" % pts})
    # (prop, x, y, z, yaw): y 0.06 on the sidewalk, -0.12 on the bare ground between blocks.
    for pid, x, y, z, yaw in (
            ("bus_shelter", gap_x - 2, -0.12, edge + 2.4, 180), ("bus_bench", gap_x + 2.5, 0.06, edge - 0.6, 180),
            ("bus_bench", gap_x, 0.06, -(edge - 0.6), 0), ("newspaper_boxes", gap_x + 4.5, 0.06, -(edge - 0.6), 0),
            ("mailbox_cluster", gap_x - 4, -0.12, -(edge + 1.0), 0),
            ("mailbox_cluster", west + 2 * ROAD_HALF + 8, -0.12, z2 + edge + 1.0, 180)):
        sc.node(pid, None, street, {"transform": xform((x, y, z), yaw)}, instance="res://" + by[pid].path())


def _row_len(specs):
    return sum(s["lot"][0] for s in specs) + GAP * (len(specs) - 1)


def write_showcase():
    """Street 1 (z = 0): houses then the phase-1 stand-ins. Street 2 (z = z2, linked by a cross
    road at the west end): census buildings on the north side, the census shops plus a row of
    seeded KitPlacement variants on the south side."""
    sc = Scene()
    root = sc.node("HouseShowcase", "Node3D", None, {
        "script": sc.res("res://scripts/world/houses/house_showcase.gd", "Script")})
    edge = ROAD_HALF + WALK
    variant_specs = [BY_ID[i] for i, seeds in VARIANTS for _ in seeds] + [BY_ID[TIER_DEMO[0]]] * len(TIER_DEMO[1])
    south2 = STREET2_SOUTH + variant_specs
    rows1 = [(ONE_FLOOR, CLOSED, -1), (TWO_FLOOR, SHOPS, 1)]
    house_len = max(_row_len(h) for h, _, _ in rows1)
    total1 = house_len + BIZ_GAP + max(_row_len(b) for _, b, _ in rows1) + BIZ_GAP + _gallery_len()
    total2 = max(_row_len(STREET2_NORTH), _row_len(south2) + BIZ_GAP)
    length = max(total1, total2) + 30
    d1n = max(s["lot"][1] for s in ONE_FLOOR + CLOSED)
    d1s = max(s["lot"][1] for s in TWO_FLOOR + SHOPS)
    d2s = max(s["lot"][1] for s in south2)
    d2n = max(s["lot"][1] for s in STREET2_NORTH)
    z2 = -(edge + d1n + STREET2_GAP + d2s + edge)
    west = -length / 2

    ground = combiner(sc, root, "Street", collision=True)
    box(sc, ground, "Ground", west - 20, length / 2, -0.6, -0.12, z2 - edge - d2n - 12, edge + d1s + 12, "ground")
    for zc in (0.0, z2):
        box(sc, ground, "Road", west, length / 2, -0.6, -0.08, zc - ROAD_HALF, zc + ROAD_HALF, "asphalt")
        for sgn in (-1, 1):
            z0, z1 = sorted((zc + sgn * ROAD_HALF, zc + sgn * edge))
            box(sc, ground, "Sidewalk", west + 2 * ROAD_HALF, length / 2, -0.6, 0.06, z0, z1, "sidewalk")
            kz = zc + sgn * (ROAD_HALF + 0.08)
            box(sc, ground, "Kerb", west + 2 * ROAD_HALF, length / 2, -0.6, 0.08, kz - 0.08, kz + 0.08, "concrete")
        x = west + 2 * ROAD_HALF + 3
        while x < length / 2 - 3:
            box(sc, ground, "Dash", x, x + 3, -0.08, -0.07, zc - 0.08, zc + 0.08, "road_line")
            x += 6
    box(sc, ground, "CrossRoad", west, west + 2 * ROAD_HALF, -0.6, -0.08, z2 - ROAD_HALF, ROAD_HALF, "asphalt")
    zc = z2 + ROAD_HALF + 3
    while zc < -ROAD_HALF - 3:
        box(sc, ground, "Dash", west + ROAD_HALF - 0.08, west + ROAD_HALF + 0.08, -0.08, -0.07, zc, zc + 3, "road_line")
        zc += 6

    houses = sc.node("Houses", "Node3D", root)
    businesses = sc.node("Businesses", "Node3D", root)
    buildings = sc.node("Buildings", "Node3D", root)
    variants = sc.node("Variants", "Node3D", root)
    cars = sc.node("CarSpots", "Node3D", root)
    placement_script = sc.res("res://scripts/world/houses/kit_placement.gd", "Script")
    first_spot = None
    seeds = [seed for _, ss in VARIANTS for seed in ss] + [0] * len(TIER_DEMO[1])
    tiers = [""] * (len(seeds) - len(TIER_DEMO[1])) + TIER_DEMO[1]
    dress = iter(range(11, 10000, 7))

    def place(parent, specs, street_z, side, cursor, variant=False):
        nonlocal first_spot
        for n, s in enumerate(specs):
            w, _ = s["lot"]
            cx = cursor + w / 2
            cursor += w + GAP
            yaw = 0 if side < 0 else 180
            front = street_z + side * edge
            if variant:
                sc.node("%s_seed%d" % (s["id"].replace("-", "_"), seeds[n]), "Node3D", parent, {
                    "transform": xform((cx, 0, front), yaw), "script": placement_script,
                    "building": '"res://%s"' % scene_path(s), "variant_seed": str(seeds[n]),
                    "dress_seed": str(next(dress)), "dress_tier": '"%s"' % (tiers[n] or "auto"),
                    "show_label": "true"})
                continue
            sc.node(s["id"].replace("-", "_"), None, parent, {
                "transform": xform((cx, 0, front), yaw), "show_label": "true", "dress_seed": str(next(dress))},
                instance="res://" + scene_path(s))
            if first_spot is None:
                first_spot = cx

            def car(lx, lz, cyaw):
                wx = cx + (lx if side < 0 else -lx)
                wz = street_z + side * (edge - lz)
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
        return cursor + BIZ_GAP - GAP

    start1 = west + 2 * ROAD_HALF + 6
    for hs, bs, side in rows1:
        place(houses, hs, 0.0, side, start1)
        place(businesses, bs, 0.0, side, start1 + house_len + BIZ_GAP)
    place(buildings, STREET2_NORTH, z2, -1, start1)
    cursor = place(buildings, STREET2_SOUTH, z2, 1, start1)
    place(variants, variant_specs, z2, 1, cursor, variant=True)
    biz_end = max(_row_len(b) for _, b, _ in rows1)
    write_gallery(sc, root, ground, start1 + house_len + BIZ_GAP + biz_end + BIZ_GAP, edge)
    write_street_furniture(sc, root, west, length, z2, start1 + house_len + BIZ_GAP / 2, edge)
    sc.node("Player", None, root, {"transform": xform((first_spot, 1.0, -edge + 1.0), 0)},
            instance="res://scenes/player/player.tscn")
    sc.save(os.path.join(ROOT, SHOWCASE))


DEEP_LOT_HOUSES = {"1F-04", "1F-09", "1F-13", "2F-05", "2F-09"}  # set back / long drive designs


def _house_archetype(s):
    w, d = s["lot"]
    if s["id"] in DEEP_LOT_HOUSES:
        size = "deep_lot"
    else:
        size = "big_yard" if w >= 19 or w * d >= 500 else "small_yard"
    return "house_%df_%s" % (s["floors"], size)


# Phase-1 stand-ins that also fill census archetypes (beyond their own archetype field).
STANDIN_FILLS = {
    "standin_strip_unit": ["S-01", "B-01"], "standin_shopfront_2f": ["B-03"],
    "standin_standalone_shop": ["S-06", "S-02"], "standin_corner_store": ["S-07"],
    "standin_garage_bays": ["S-03"],
}
# Census shop_type names -> BusinessExterior.shop_type used by the kit scenes.
SHOP_TYPES = {
    "auto_mod": "chop_shop", "ammo": "gun_store", "clothing": "clothing_store", "food": "food",
    "tattoo": "tattoo_parlor", "barber": "barbershop", "corner_store": "corner_store",
    "liquor": "liquor_store", "pawn": "pawn_shop",
}


def write_mapping(footprints, props):
    """data/buildings/building_kit.json: census archetype -> kit scenes (CSG source + baked)."""
    entries = {}
    for s in ALL_SPECS:
        arch = s.get("archetype") or _house_archetype(s)
        archs = [arch] + [a for a, ids in STANDIN_FILLS.items() if s["id"] in ids]
        for a in archs:
            path = "res://" + scene_path(s)
            entries.setdefault(a, []).append({
                "id": s["id"], "name": s.get("name", ""), "scene": path,
                "baked": "res://scenes/baked/" + scene_path(s)[len("scenes/"):-len(".tscn")] + ".scn",
                "floors": s.get("floors", 1), "lot_m": list(s["lot"]),
                "footprint_m": [round(v, 2) for v in footprints[s["id"]]],
                "enterable": bool(s.get("enterable")), "shop_type": s.get("shop_type", ""),
                "dress_tier": s.get("dress_tier", ""),
            })
    archetypes = {}
    for a in sorted(set(CENSUS) | set(MD_ONLY) | set(entries)):
        info = dict(CENSUS.get(a) or MD_ONLY.get(a) or {"label": "kit-only archetype", "kit_only": True})
        info["scenes"] = entries.get(a, [])
        archetypes[a] = info
    data = {
        "comment": "Generated by tools/houses/build_houses.py. Maps North End census archetypes "
                   "(branch npawlakel-north-end-building-census @ %s) to building-kit scenes. "
                   "'scene' is the editable CSG source, 'baked' the mesh + collision version from "
                   "tools/bake_kit.tscn. Pick a scene per placement and give it a KitPlacement "
                   "variant_seed to vary palette / mirroring." % CENSUS_COMMIT,
        "census_commit": CENSUS_COMMIT,
        "shop_types": SHOP_TYPES,
        "palettes": "res://data/buildings/kit_palettes.json",
        "archetypes": archetypes,
        "dressing": "res://" + kit_props.DRESSING_JSON,
        "props": kit_props.mapping_entries(props),
    }
    os.makedirs(os.path.join(ROOT, "data/buildings"), exist_ok=True)
    with open(os.path.join(ROOT, "data/buildings/building_kit.json"), "w", newline="\n") as fh:
        json.dump(data, fh, indent=1)
        fh.write("\n")
    missing = [a for a in CENSUS if not archetypes[a]["scenes"]] + [a for a in MD_ONLY if not archetypes[a]["scenes"]]
    return missing


CIVIC = {"grove_general_hospital", "bank_branch"}
LOW = {"apartment_walkup_3f", "grove_apartments", "trailer_1f", "safehouse_duplex", "safehouse_greybox",
       "safehouse_warehouse", "trap_house_the_spot", "stash_house_grove", "stash_house_viper",
       "trap_trailer_lakeside", "informant_flat", "coke_plug_house"}


def dress_tier(spec):
    """Income tier for the seeded Florida dressing: spec override > census tier > building type."""
    if spec.get("dress_tier"):
        return spec["dress_tier"]
    arch = spec.get("archetype") or _house_archetype(spec)
    if arch in CIVIC:
        return "civic"
    if arch in LOW:
        return "low"
    if (CENSUS.get(arch) or {}).get("tier"):
        return CENSUS[arch]["tier"]
    return "commercial" if "body" in spec else "medium"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", help="house / business ids to (re)generate")
    ap.add_argument("--no-textures", action="store_true")
    args = ap.parse_args()
    for d in ("scenes/houses/parts", "scenes/houses/one_floor", "scenes/houses/two_floor",
              "scenes/businesses/closed", "scenes/businesses/shops"):
        os.makedirs(os.path.join(ROOT, d), exist_ok=True)
    for spec in EXTRA:
        if "folder" in spec:
            os.makedirs(os.path.join(ROOT, "scenes/buildings", spec["folder"]), exist_ok=True)
    if not args.no_textures:
        materials.write_all(ROOT)
    write_parts()
    props = kit_props.build_all(ROOT)
    PROPS_BUILT[:] = props
    specs_fl.apply(ONE_FLOOR + TWO_FLOOR)
    bad = False
    footprints = {}
    for spec in ALL_SPECS:
        BY_ID[spec["id"]] = spec
        if "body" not in spec and not spec.get("archetype"):
            spec["archetype"] = _house_archetype(spec)
        spec["dress_tier"] = dress_tier(spec)
        b = BusinessBuilder(spec) if "body" in spec else HouseBuilder(spec)
        footprints[spec["id"]] = b.footprint()
        if args.only and spec["id"] not in args.only:
            continue
        for p in b.validate():
            print("%s: %s" % (spec["id"], p))
            bad = True
        b.build().save(os.path.join(ROOT, scene_path(spec)))
    write_showcase()
    for a in write_mapping(footprints, props):
        print("archetype without a kit scene: %s" % a)
        bad = True
    print("houses: %d one-floor, %d two-floor; businesses: %d closed, %d shops; census buildings: %d"
          % (len(ONE_FLOOR), len(TWO_FLOOR), len(CLOSED), len(SHOPS), len(EXTRA)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
