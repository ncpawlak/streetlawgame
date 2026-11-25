"""West Palm Beach style pass over the phase-1 houses: pastel stucco, white metal and barrel-tile
roofs, jalousie windows, hurricane shutters (1 accordion, 2 storm panels, 3 bahama) and security
bars in the poorer designs, CMU block garden walls. Applied by build_houses.py before building, so
the original specs_one / specs_two stay readable as the massing / layout source.

Keys replace the spec value; "wing_walls" maps an old wing wall material to a new one and
"fence_kinds" maps fence kinds (e.g. privacy -> block_wall).
"""

FL_STYLE = {
    "1F-01": {"wall": "stucco_butter", "roof": "white", "jalousie": True, "win_bars": True},
    "1F-02": {"wall": "stucco_mint", "jalousie": True, "storm": 1, "fence_kinds": {"privacy": "block_wall"}},
    "1F-03": {"wall": "stucco_seafoam", "storm": 1, "wing_walls": {"fence_wood": "stucco_white"}},
    "1F-04": {"jalousie": True},
    "1F-05": {"wall": "stucco_coral", "jalousie": True},
    "1F-06": {"wall": "stucco_white", "roof": "white"},
    "1F-09": {"wall": "stucco_salmon", "win_bars": True, "jalousie": True},
    "1F-10": {"roof": "tile_terracotta"},
    "1F-11": {"storm": 3, "jalousie": True, "shutter_mat": "shutter_blue"},
    "1F-12": {"wall": "stucco_white", "roof": "tile_tan", "storm": 3, "shutter_mat": "shutter_dark",
              "shutters": False},
    "1F-13": {"wall": "stucco_sky", "win_bars": True},
    "1F-14": {"wall": "stucco_lavender", "jalousie": True, "storm": 2},
    "1F-15": {"wall": "stucco_beige", "roof": "tile_brown"},
    "2F-01": {"wall": "stucco_sky", "roof": "white", "storm": 3, "shutter_mat": "shutter_dark"},
    "2F-03": {"wall": "stucco_pink", "roof": "tile_terracotta", "wing_walls": {"siding_white": "stucco_white"},
              "shutters": False},
    "2F-05": {"wall": "stucco_butter", "roof": "tile_tan"},
    "2F-07": {"roof": "tile_terracotta"},
    "2F-09": {"wall": "stucco_lavender", "jalousie": True},
}


def apply(specs):
    for s in specs:
        o = FL_STYLE.get(s["id"])
        if not o:
            continue
        for k, v in o.items():
            if k == "wing_walls":
                for w in s["wings"]:
                    if w.get("wall") in v:
                        w["wall"] = v[w["wall"]]
            elif k == "fence_kinds":
                s["fences"] = [(v.get(fc[0], fc[0]),) + tuple(fc[1:]) for fc in s.get("fences", [])]
            else:
                s[k] = v
