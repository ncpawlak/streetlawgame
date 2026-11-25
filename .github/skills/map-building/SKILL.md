---
name: map-building
description: Rules and workflow for building or changing Street Law city map zones (road network, I-59 interchanges, rail crossings, water edges, lots, building census). Use whenever editing tools/extract_north_end_layout.py, scripts/world/north_end_layout.gd, scripts/world/city_generator.gd, scripts/world/north_end_census.gd, data/areas/north_end_buildings.json, or adding a new zone greybox from a wireframe.
---

# Street Law map building

The playable map is generated, not hand-placed:

`docs/map/<zone>_wireframe.svg` → `tools/extract_<zone>_layout.py` → `scripts/world/<zone>_layout.gd` (generated) → `scripts/world/city_generator.gd` (builds 3D) → `data/areas/<zone>_buildings.json` (building census) → `docs/map/<zone>_buildings.png` (as-built map).

**Fix the extractor, never hand-patch the generated layout.** The extractor only rewrites the layout when its `check_network` reports zero problems.

**The wireframe SVG is the source, not the picture of the game.** The extractor's `fix_network` rewrites a lot of the network after reading it:
- I-59 diamond interchanges
- the lake loops
- the rebuilt Riviera / Clement grids
- extended or realigned streets
- connectors
- dropped lots

Don't hand-edit the SVG to match. The as-built picture is `docs/map/<zone>_buildings.png`/`.svg`, rendered by `tools/render_north_end_buildings.py` from the generated layout and the census, with buildings coloured by category. The same script also overlays the census on the wireframe itself. It writes the generated `<!-- census-overlay -->` and `<!-- census-legend -->` blocks (class `cz`, which the extractor ignores) into the SVG and re-rasterises the wireframe PNG with headless Edge/Chrome. Never hand-edit those blocks. Regenerate after every layout or census change.

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
4. Regenerate the building census and the as-built map:
   - `Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/north_end_census.tscn`, then `python tools/render_north_end_buildings.py`.
   - The census dump must print `coverage: ... unlisted [], missing [], duplicates []`.
   - Review the counts it prints, plus the `unbuilt` list (roster places with no lot).
5. Run `res://tests/test_runner.tscn` 3 times. Each run must print `ALL TESTS PASSED` with no `SCRIPT ERROR` or `Parse Error` lines. The network checks live in `tests/location_tests.gd`:
   - `_test_road_network`: connectivity, water, dead ends, lots fronting a street
   - `_test_interchanges`: grade separation and 4 quadrant ramps
6. Boot `res://scenes/main.tscn` headless with `--quit-after 600` and check for runtime errors.
7. Capture top-down screenshots (full map, plus close-ups of anything changed), plus an angled view for elevation. **Show them to the user and wait for approval before committing.**

Keep the current scale (1.2 m per wireframe px) unless the user decides otherwise.

## Building census

Every building box in the scene is listed in `data/areas/north_end_buildings.json`. It is built by `NorthEndCensus.build(main)` in `scripts/world/north_end_census.gd` and documented in `docs/design/NORTH_END_BUILDINGS.md`.

- **Tagging.** `city_generator.gd` tags every building StaticBody3D through `_tag_building`, which sets the group `census_buildings` and the metas `rect_px` and `census_kind` (lot, filler or landmark). Safehouses come from the `safehouses` group. Any new building source must call `_tag_building`; otherwise the coverage test fails.
- **Categories.** Each entry has exactly one primary `category`: `house_1f`, `house_2f`, `large_building`, `special_building`, `specialized_location`, `purchasable_business` or `standin_business`. Neighbour fillers are `out_of_area`. Secondary categories go in `tags`; for example, a trap house in a 2-storey house is `specialized_location` with tag `house_2f`. `roles` carries the gameplay roles (robbery tier, stick_up, trap_house tier, business type/price/income, raid, safehouse, turf_point, ...).
- **Design types.** `design_archetype` is a key into `NorthEndCensus.ARCHETYPES` (category, storeys, target footprint_m, target lot_m [frontage, depth], tier, one_off). There are shared types, such as `house_{1f,2f}_{small_yard,big_yard,deep_lot}`, `trailer_1f`, `storefront_1f`, `mixed_use_2f`, `apartment_walkup_3f`, `industrial_shed` and `warehouse`, plus one-offs for every special or specialized building and every business. New roster places get a rule in `ROSTER` (keyed by location instance or `marker:<n>`) or in `SITE_ARCHETYPES`.
- **Stand-in businesses** (`standin_business`) are businesses that either can't be entered or can be entered to buy things. They must look like shops, not houses. Each one has a `standin` field: `{subtype: standin_shop|standin_closed, enterable, shop_type, replaces}`.
  - Shop types are `auto_mod`, `ammo`, `clothing`, `food`, `tattoo`, `barber`, `corner_store`, `liquor` and `pawn`. On the maps they are lettered A G C F T B S L P.
  - Archetypes: `standin_strip_unit`, `standin_shopfront_2f`, `standin_standalone_shop`, `standin_corner_store`, `standin_garage_bays` (auto mod always).
  - `_plan_standins` converts only generic lots: no roles, roster or `Location`, so hits and purchasable businesses are never touched. The lots it uses are storefront, mixed-use and shed lots, and corner lots (both street axes within 10 px).
  - Placement order: each zone in `STANDIN_ZONE_NEEDS` gets each needed type, unless a purchasable business in that district already sells it (`BUSINESS_SHOP_TYPES`). Food is never skipped.
  - Shops are picked greedily to stay spread out. Leftover storefront and mixed-use lots, and arterial corner lots, become `standin_closed`.
  - To change the plan, edit those constants. Don't hand-edit the JSON.
- **Coverage check.** `tests/census_tests.gd` runs in the test runner. It checks the following:
  - every scene building is in the census, and every entry has a building
  - no duplicates
  - categories and archetypes are valid, and the archetype category matches the category or tags
  - stand-ins have valid shop data and only `shop`/`storefront` roles, and every zone can buy each needed shop type
  - the JSON equals a fresh `build()`, which means a stale census fails the tests
- **Unbuilt.** Roster spots with no lot within 40 px are listed in `unbuilt[]`. They need a lot when the area is repopulated.

## Scale rules for lots and buildings (docs/design/SCALE.md)

- Storeys are 3.0 m (3.5 m for a shop ground floor). Doors are at least 1.2 × 2.4 m.
- House footprints are the robbery floor plans ×1.4:
  - low: about 14 × 11.2 m
  - medium: about 19.6 × 14 m
  - high: about 28 × 19.6 m
- Lots (frontage × depth) must hold the footprint plus a yard:
  - small yard: 18 × 22 m
  - big yard: 26 × 30 m
  - deep lot: 18–24 × 40 m with a long driveway
- The current greybox lots are deep enough in Mangona but too shallow elsewhere:
  - Tamarack: 18 × 11.5 m
  - Northgrove: about 25 × 19 m
- Grow block depth, not frontage, when rescaling; see the rescale notes in NORTH_END_BUILDINGS.md.

## Downstream pipeline

1. **Census.** Done for the North End. Keep it current with the workflow above.
2. **Design the building types.** Design one scene per `design_archetype`, with variants for the shared types. Use the archetype footprint, storeys and lot.
3. **Rescale.** Grow blocks and lots in the extractor (never in the generated layout) until every archetype lot fits. Then rerun the whole workflow. Ids are reassigned, so match buildings by `design_archetype` + `roles`.
4. **Populate.** The city generator places the archetype scene for each census entry instead of a box. Give the `unbuilt` places lots.
5. **Playtest.** Walk and drive every district. Check doors, robbery interiors, stick-ups and business purchases.
