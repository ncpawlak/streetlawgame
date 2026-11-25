---
name: map-building
description: Rules and workflow for building or changing Street Law city map zones (road network, I-59 interchanges, rail crossings, water edges, lots). Use whenever editing tools/extract_north_end_layout.py, scripts/world/north_end_layout.gd, scripts/world/city_generator.gd, or adding a new zone greybox from a wireframe.
---

# Street Law map building

The playable map is generated, not hand-placed:

`docs/map/<zone>_wireframe.svg` → `tools/extract_<zone>_layout.py` → `scripts/world/<zone>_layout.gd` (generated) → `scripts/world/city_generator.gd` (builds 3D).

**Fix the extractor, never hand-patch the generated layout.** The extractor only rewrites the layout when its `check_network` reports zero problems.

## Road network rules (all enforced)

1. **One cohesive town.** The drivable network (loc, ave, art, ramp, highway) is a single connected component. District borders, rail lines and the highway never split the grid.
2. **No dead ends.** Every street joins another street at both ends. Use a cul-de-sac or turnaround only deliberately, and rarely. `prune_dead_ends` cuts loose stubs back to their last junction.
3. **Water.** No road ends in or at water. Each lake gets a shore drive that loops the lake, or partly loops it, and side streets T into that drive. Road endpoints must never lie inside a lake polygon.
4. **Rail.** Streets cross the tracks at grade. Each crossing gets a crossing pad and crossbucks, generated from `RAIL_CROSSINGS`. Grids on both sides of the tracks join through these crossings.
5. **Highway (I-59) is grade-separated.**
   - The deck is elevated (`DECK_HEIGHT`). Only arterials (`art`) pass under it.
   - No local street or avenue may touch the deck or a ramp. Clip such streets with `highway_clear`.
   - Every arterial crossing gets a full **diamond interchange** with 4 ramps, one per quadrant. Traffic is right-hand:
     - **NB** (east carriageway): off-ramp south of the arterial, on-ramp north of it.
     - **SB** (west carriageway): off-ramp north of the arterial, on-ramp south of it.
   - Ramps leave the deck edge with a taper and slope down to a terminal on the arterial. The terminal sits about 40 px from the highway, and paired N/S ramps share it.
   - Each ramp's points are listed deck end first. The generator relies on this order.
   - Every ramp gets a sign: exits say `EXIT <street>`, entrances say `I-59 NORTH/SOUTH ENTRANCE`.
6. **Alignment.** An avenue continues in a straight line across arterials and district borders. Offset jogs at an intersection count as bugs.
7. **Connections.** Ramps join only the highway or an arterial. Nothing else joins the highway, and rail never joins a road. These rules live in `connects()` in the extractor and `_may_join()` in the tests.
8. **Lots.** Drop any building lot that sits under a road, ramp or deck. Shrink the block pad to the lots that remain. Every lot must front a drivable street (loc/ave/art) within 24 px, and no ramp or highway may be closer to it than a street. The extractor's `fronts_street` drops lots that fail this, and a block that loses every lot is removed. Never leave a house row stranded: when a street is removed or cut back, reroute or add a connector so the row's frontage street still joins the network at both ends.

## Workflow

1. Edit the extractor (`fix_network` for layout fixes, constants such as `INTERCHANGE` for geometry).
2. Run `python tools/extract_north_end_layout.py`. The run must report 0 problems.
3. Run `Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`.
4. Run `res://tests/test_runner.tscn` 3 times. Each run must print `ALL TESTS PASSED` with no `SCRIPT ERROR` or `Parse Error` lines. The network checks live in `tests/location_tests.gd`:
   - `_test_road_network`: connectivity, water, dead ends, lots fronting a street
   - `_test_interchanges`: grade separation and 4 quadrant ramps
5. Boot `res://scenes/main.tscn` headless with `--quit-after 600` and check for runtime errors.
6. Capture top-down screenshots (full map, plus close-ups of anything changed), plus an angled view for elevation. **Show them to the user and wait for approval before committing.**

Keep the current scale (1.2 m per wireframe px) unless the user decides otherwise.
