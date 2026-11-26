class_name NorthEndCensus
extends RefCounted
## Building census of the North End: every building box the greybox builds, with its category,
## gameplay roles and the design archetype it needs (docs/design/NORTH_END_BUILDINGS.md).
## [method build] derives the census from the running main scene; tools/north_end_census.tscn writes
## it to [constant PATH]; tests check [method coverage] so no scene building goes unlisted.
## CityGenerator tags every building body with [constant GROUP] and meta rect_px / census_kind.

const GROUP := &"census_buildings"
const PATH := "res://data/areas/north_end_buildings.json"
const VERSION := 1
## Archetypes are classified on the lot sizes at the authoring scale (1.2 m/px), so the 2.0 m/px
## rescale kept every lot's class; footprints and heights come from the placed kit buildings.
const CLASSIFY_METERS_PER_PX := 1.2
const DOOR_SLACK := 2.0
const CATEGORIES := [&"house_1f", &"house_2f", &"large_building", &"special_building", &"specialized_location", &"purchasable_business", &"standin_business"]
const DISTRICT_CODES := {&"tamarack_row": "tr", &"northgrove": "ng", &"mangona": "mg", &"": "xx"}
## Target (designed) sizes in meters: footprint [w, d], lot [frontage, depth]. Houses follow the
## SCALE targets (low ~14x11.2, medium ~19.6x14, high ~28x19.6). one_off = designed for one building.
const ARCHETYPES := {
	# Shared house designs (the 15 one-floor + 10 two-floor house exterior set picks from these).
	"house_1f_small_yard": {"category": "house_1f", "storeys": 1, "footprint_m": [14.0, 11.2], "lot_m": [18.0, 22.0], "tier": "low", "label": "1-storey house, small yard"},
	"house_1f_big_yard": {"category": "house_1f", "storeys": 1, "footprint_m": [19.6, 14.0], "lot_m": [26.0, 30.0], "tier": "medium", "label": "1-storey house, big yard"},
	"house_1f_deep_lot": {"category": "house_1f", "storeys": 1, "footprint_m": [14.0, 11.2], "lot_m": [18.0, 40.0], "tier": "low", "label": "1-storey house, deep lot with long driveway"},
	"house_2f_small_yard": {"category": "house_2f", "storeys": 2, "footprint_m": [14.0, 11.2], "lot_m": [18.0, 22.0], "tier": "medium", "label": "2-storey house, small yard"},
	"house_2f_big_yard": {"category": "house_2f", "storeys": 2, "footprint_m": [19.6, 14.0], "lot_m": [26.0, 30.0], "tier": "high", "label": "2-storey house, big yard"},
	"house_2f_deep_lot": {"category": "house_2f", "storeys": 2, "footprint_m": [19.6, 14.0], "lot_m": [24.0, 42.0], "tier": "medium", "label": "2-storey house, deep lot with long driveway"},
	"duplex_2f": {"category": "house_2f", "storeys": 2, "footprint_m": [19.6, 14.0], "lot_m": [24.0, 26.0], "tier": "medium", "label": "2-storey side-by-side duplex (2 units)"},
	"trailer_1f": {"category": "house_1f", "storeys": 1, "footprint_m": [16.0, 4.5], "lot_m": [14.0, 24.0], "tier": "low", "label": "Single-wide trailer / shack"},
	# Shared bigger buildings.
	"storefront_1f": {"category": "large_building", "storeys": 1, "footprint_m": [20.0, 16.0], "lot_m": [24.0, 30.0], "label": "1-storey strip storefront (generic shop)"},
	"mixed_use_2f": {"category": "large_building", "storeys": 2, "footprint_m": [22.0, 16.0], "lot_m": [24.0, 28.0], "label": "Shop below, flat above (arterial frontage)"},
	"apartment_walkup_3f": {"category": "large_building", "storeys": 3, "footprint_m": [28.0, 20.0], "lot_m": [34.0, 36.0], "label": "3-storey walk-up apartments"},
	"industrial_shed": {"category": "large_building", "storeys": 1, "footprint_m": [24.0, 18.0], "lot_m": [30.0, 32.0], "label": "Workshop / small industrial shed (6 m eaves)"},
	"warehouse": {"category": "large_building", "storeys": 1, "footprint_m": [40.0, 30.0], "lot_m": [50.0, 48.0], "label": "Warehouse with loading dock (8 m eaves)"},
	# Special buildings (one-offs).
	"grove_general_hospital": {"category": "special_building", "storeys": 7, "footprint_m": [100.0, 96.0], "lot_m": [110.0, 110.0], "one_off": true, "label": "Grove General Hospital"},
	"safehouse_duplex": {"category": "special_building", "storeys": 2, "footprint_m": [14.0, 12.0], "lot_m": [24.0, 26.0], "one_off": true, "label": "Player safehouse: duplex"},
	"safehouse_warehouse": {"category": "special_building", "storeys": 2, "footprint_m": [22.0, 14.0], "lot_m": [30.0, 34.0], "one_off": true, "label": "Player safehouse: warehouse"},
	"safehouse_greybox": {"category": "special_building", "storeys": 1, "footprint_m": [10.0, 10.0], "lot_m": [24.0, 26.0], "one_off": true, "label": "Player safehouse: generic"},
	# Specialized locations (one-offs; see NORTH_END_HITS.md / TRAP_HOUSES_OPERATIONS.md).
	"trap_house_the_spot": {"category": "specialized_location", "storeys": 1, "footprint_m": [14.0, 11.2], "lot_m": [18.0, 30.0], "one_off": true, "label": "The Spot: fortified shotgun trap house"},
	"stash_house_viper": {"category": "specialized_location", "storeys": 2, "footprint_m": [19.6, 14.0], "lot_m": [26.0, 30.0], "one_off": true, "label": "Viper stash house (fortified)"},
	"stash_house_grove": {"category": "specialized_location", "storeys": 2, "footprint_m": [19.6, 14.0], "lot_m": [26.0, 30.0], "one_off": true, "label": "Grove stash house (trap house T2, lab)"},
	"trap_trailer_lakeside": {"category": "specialized_location", "storeys": 1, "footprint_m": [16.0, 4.5], "lot_m": [14.0, 24.0], "one_off": true, "label": "Lakeside trailer trap house (T3)"},
	"viper_garage": {"category": "specialized_location", "storeys": 1, "footprint_m": [34.0, 46.0], "lot_m": [36.0, 48.0], "one_off": true, "label": "Viper Garage (rival front, garage + yard)"},
	"gas_station": {"category": "specialized_location", "storeys": 1, "footprint_m": [16.0, 12.0], "lot_m": [40.0, 34.0], "one_off": true, "label": "Gas-N-Go: kiosk + canopy + pumps"},
	"electronics_store": {"category": "specialized_location", "storeys": 1, "footprint_m": [20.0, 16.0], "lot_m": [24.0, 30.0], "one_off": true, "label": "Wired Electronics (stick-up, non-buyable)"},
	"bank_branch": {"category": "specialized_location", "storeys": 2, "footprint_m": [24.0, 20.0], "lot_m": [32.0, 36.0], "one_off": true, "label": "Northgrove Savings bank branch"},
	"bar_the_gallery": {"category": "specialized_location", "storeys": 2, "footprint_m": [20.0, 16.0], "lot_m": [24.0, 30.0], "one_off": true, "label": "The Gallery bar (arts strip)"},
	"informant_flat": {"category": "specialized_location", "storeys": 2, "footprint_m": [14.0, 11.2], "lot_m": [18.0, 22.0], "one_off": true, "label": "Informant's flat (upstairs unit)"},
	"grove_apartments": {"category": "specialized_location", "storeys": 3, "footprint_m": [28.0, 20.0], "lot_m": [34.0, 36.0], "one_off": true, "label": "Grove Apartments (4 robbable units)"},
	"coke_plug_house": {"category": "specialized_location", "storeys": 1, "footprint_m": [14.0, 11.2], "lot_m": [18.0, 30.0], "one_off": true, "label": "Coke plug meet house"},
	# Purchasable businesses (one-offs, BUSINESSES_PLAN.md).
	"bodega": {"category": "purchasable_business", "storeys": 1, "footprint_m": [14.0, 12.0], "lot_m": [18.0, 24.0], "one_off": true, "label": "Tamarack Bodega"},
	"liquor_store": {"category": "purchasable_business", "storeys": 1, "footprint_m": [16.0, 12.0], "lot_m": [20.0, 26.0], "one_off": true, "label": "Row Liquors"},
	"barbershop": {"category": "purchasable_business", "storeys": 1, "footprint_m": [12.0, 10.0], "lot_m": [16.0, 22.0], "one_off": true, "label": "Fresh Cutz Barbershop (recruiting spot)"},
	"pawn_shop": {"category": "purchasable_business", "storeys": 1, "footprint_m": [16.0, 14.0], "lot_m": [20.0, 28.0], "one_off": true, "label": "Northgrove Pawn (fence)"},
	"pharmacy": {"category": "purchasable_business", "storeys": 1, "footprint_m": [20.0, 16.0], "lot_m": [26.0, 32.0], "one_off": true, "label": "Grove Pharmacy"},
	"tattoo_parlor": {"category": "purchasable_business", "storeys": 1, "footprint_m": [12.0, 10.0], "lot_m": [16.0, 22.0], "one_off": true, "label": "Ink Lab Tattoo"},
	"gun_store": {"category": "purchasable_business", "storeys": 1, "footprint_m": [18.0, 14.0], "lot_m": [24.0, 30.0], "one_off": true, "label": "Mangona Guns & Ammo (+ back range)"},
	"hardware_store": {"category": "purchasable_business", "storeys": 1, "footprint_m": [24.0, 18.0], "lot_m": [30.0, 34.0], "one_off": true, "label": "Mangona Hardware (+ yard)"},
	"chop_shop": {"category": "purchasable_business", "storeys": 1, "footprint_m": [30.0, 24.0], "lot_m": [36.0, 48.0], "one_off": true, "label": "Lakeside Chop Shop (bays + car drop-off)"},
	# Stand-in businesses: shop fronts that are closed (scenery) or open for buying (no ownership, no hits).
	"standin_strip_unit": {"category": "standin_business", "storeys": 1, "footprint_m": [20.0, 16.0], "lot_m": [24.0, 30.0], "label": "Stand-in strip-mall unit (glass front, signboard, roll-down shutter)"},
	"standin_shopfront_2f": {"category": "standin_business", "storeys": 2, "footprint_m": [22.0, 16.0], "lot_m": [24.0, 28.0], "label": "Stand-in shop below, flat above (arterial)"},
	"standin_standalone_shop": {"category": "standin_business", "storeys": 1, "footprint_m": [16.0, 14.0], "lot_m": [20.0, 28.0], "label": "Stand-in standalone shop (own lot, front parking)"},
	"standin_corner_store": {"category": "standin_business", "storeys": 1, "footprint_m": [14.0, 12.0], "lot_m": [18.0, 24.0], "label": "Stand-in corner shop on a residential corner lot"},
	"standin_garage_bays": {"category": "standin_business", "storeys": 1, "footprint_m": [24.0, 18.0], "lot_m": [30.0, 36.0], "label": "Stand-in auto shop: 3 roll-up bays + forecourt"},
	# Outside the North End: hatched neighbour blocks, not designed in this pass.
	"neighbour_filler": {"category": "", "storeys": 0, "footprint_m": [0.0, 0.0], "lot_m": [0.0, 0.0], "label": "Neighbouring-district filler block"},
}
## Roster spots that make a building their own (NorthEndSpots key -> category, archetype, roles).
## Keys: location instance, business site id, or "marker:<roster>".
const ROSTER := {
	"bottoms_trap_house": {"category": "specialized_location", "archetype": "trap_house_the_spot", "tags": ["house_1f"], "roles": [{"role": "raid", "target": "rival_trap"}, {"role": "trap_house", "tier": "T1", "owner": "vipers"}]},
	"rival_front_stash_house": {"category": "specialized_location", "archetype": "stash_house_viper", "tags": ["house_2f"], "roles": [{"role": "raid", "target": "rival_stash"}, {"role": "targeted_theft", "item": "viper_ledger"}]},
	"riverside_lab": {"category": "specialized_location", "archetype": "stash_house_grove", "tags": ["house_2f"], "roles": [{"role": "trap_house", "tier": "T2"}, {"role": "drug_lab"}]},
	"rival_front_viper_garage": {"category": "specialized_location", "archetype": "viper_garage", "tags": ["large_building"], "roles": [{"role": "raid", "target": "rival_front"}]},
	"corner_store_gas_n_go": {"category": "specialized_location", "archetype": "gas_station", "tags": ["business"], "roles": [{"role": "stick_up"}, {"role": "burglary"}, {"role": "business", "type": "gas_station", "purchasable": false}]},
	"corner_store_wired": {"category": "specialized_location", "archetype": "electronics_store", "tags": ["business"], "roles": [{"role": "stick_up"}, {"role": "burglary"}, {"role": "targeted_theft", "item": "prototype_phones"}, {"role": "business", "type": "electronics", "purchasable": false}]},
	"bar_grove_rd": {"category": "specialized_location", "archetype": "bar_the_gallery", "tags": ["business"], "roles": [{"role": "business", "type": "bar", "purchasable": false}, {"role": "tip_source"}]},
	"informant_flat": {"category": "specialized_location", "archetype": "informant_flat", "tags": ["house_2f"], "roles": [{"role": "informant"}, {"role": "tip_source"}]},
	"coke_plug_meet": {"category": "specialized_location", "archetype": "coke_plug_house", "tags": ["house_1f"], "roles": [{"role": "plug_meet", "plug": "coke_plug"}]},
	"marker:10": {"category": "specialized_location", "archetype": "grove_apartments", "tags": ["large_building"], "roles": [{"role": "robbery", "event": "burglary", "tier": "low", "units": 4}]},
	"marker:15": {"category": "specialized_location", "archetype": "bank_branch", "tags": ["large_building"], "roles": [{"role": "stick_up", "target": "bank_teller"}, {"role": "bank_vault", "locked_until": "#42"}]},
	"marker:T3": {"category": "specialized_location", "archetype": "trap_trailer_lakeside", "tags": ["house_1f"], "roles": [{"role": "trap_house", "tier": "T3", "buy_price": 2000}]},
}
## Business site id -> archetype (all are purchasable_business).
const SITE_ARCHETYPES := {
	"tamarack_corner_store": "bodega", "tamarack_liquor_store": "liquor_store", "tamarack_barbershop": "barbershop",
	"northgrove_pawn_shop": "pawn_shop", "northgrove_pharmacy": "pharmacy", "northgrove_tattoo_parlor": "tattoo_parlor",
	"mangona_gun_store": "gun_store", "mangona_hardware_store": "hardware_store", "mangona_chop_shop": "chop_shop",
}
## Stand-in shop types (enterable, buy goods only) every zone needs within reach, in placement order
## (most constrained first). Purchasable businesses of the same trade already serve their zone.
const STANDIN_SHOP_TYPES := ["auto_mod", "ammo", "clothing", "food", "tattoo", "barber", "corner_store", "liquor", "pawn"]
const STANDIN_ZONE_NEEDS := {
	"tamarack_row": ["auto_mod", "ammo", "clothing", "food", "food", "tattoo", "barber", "corner_store", "liquor", "pawn"],
	"northgrove": ["auto_mod", "ammo", "clothing", "food", "food", "tattoo", "barber", "corner_store", "liquor", "pawn"],
	"mangona": ["auto_mod", "ammo", "food"],
}
## Purchasable business type -> the stand-in shop type it already covers in its zone.
const BUSINESS_SHOP_TYPES := {"corner_store": "corner_store", "liquor_store": "liquor", "barbershop": "barber", "tattoo_parlor": "tattoo", "pawn_shop": "pawn", "gun_store": "ammo"}
## Business types the HITS roster lets the player hold up before buying.
const STICK_UP_TYPES := [&"corner_store", &"liquor_store", &"barbershop", &"pawn_shop", &"pharmacy", &"tattoo_parlor", &"gun_store", &"hardware_store", &"chop_shop"]


static func load_census() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}


static func rect_key(rect: Rect2) -> String:
	return "%.1f,%.1f,%.1f,%.1f" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## Every building in the scene under [param root]: key -> {kind, rect_px?, node}.
static func scene_buildings(root: Node) -> Dictionary:
	var out := {}
	for node in root.get_tree().get_nodes_in_group(GROUP):
		if not root.is_ancestor_of(node):
			continue
		var rect: Rect2 = node.get_meta(&"rect_px")
		out[rect_key(rect)] = {"kind": node.get_meta(&"census_kind"), "rect_px": rect, "node": node}
	for node in root.get_tree().get_nodes_in_group(&"safehouses"):
		if root.is_ancestor_of(node) and node is Safehouse and node.district != null:
			out["safehouse:%s" % node.district.district_id] = {"kind": &"safehouse", "node": node}
	return out


## Scene buildings missing from [param census] (unlisted), census entries with no scene building
## (missing) and census keys listed twice (duplicates).
static func coverage(root: Node, census: Dictionary) -> Dictionary:
	var scene := scene_buildings(root)
	var listed := {}
	var duplicates: Array[String] = []
	for list_name: String in ["buildings", "out_of_area"]:
		for entry: Dictionary in census.get(list_name, []):
			var key: String = entry.get("key", "")
			if listed.has(key):
				duplicates.append(key)
			listed[key] = true
	var unlisted: Array[String] = []
	for key: String in scene:
		if not listed.has(key):
			unlisted.append(key)
	var missing: Array[String] = []
	for key: String in listed:
		if not scene.has(key):
			missing.append(key)
	return {"unlisted": unlisted, "missing": missing, "duplicates": duplicates, "scene_count": scene.size(), "census_count": listed.size()}


## Builds the census from the running main scene (CityGenerator child "City", roster already placed).
static func build(main: Node) -> Dictionary:
	var city: CityGenerator = main.get_node("City")
	var scene := scene_buildings(main)
	var lots_by_key := {}
	for lot: Dictionary in city.building_lots:
		lots_by_key[rect_key(lot["rect_px"])] = lot
	var spots_by_lot := spots_by_lot(city)
	var locations_by_lot := _locations_by_lot(city)
	var streets := _street_names()
	var buildings: Array[Dictionary] = []
	var out_of_area: Array[Dictionary] = []
	for key: String in scene:
		var info: Dictionary = scene[key]
		match info["kind"]:
			&"filler":
				out_of_area.append(_filler_entry(key, info))
			&"safehouse":
				buildings.append(_safehouse_entry(key, info["node"], streets))
			&"landmark":
				buildings.append(_hospital_entry(key, info, streets))
			_:
				var lot: Dictionary = lots_by_key[key]
				buildings.append(_lot_entry(key, lot, spots_by_lot.get(lot["index"], {}), locations_by_lot.get(lot["index"], []), streets))
	var unbuilt := _unbuilt(spots_by_lot, locations_by_lot, streets)
	_assign_ids(buildings)
	_assign_ids(out_of_area)
	_plan_standins(buildings, unbuilt)
	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	out_of_area.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	var counts := {}
	for category: StringName in CATEGORIES:
		counts[String(category)] = 0
	var used_archetypes := {}
	for entry in buildings:
		counts[entry["category"]] += 1
		used_archetypes[entry["design_archetype"]] = used_archetypes.get(entry["design_archetype"], 0) + 1
	var archetypes := {}
	for name: String in ARCHETYPES:
		if used_archetypes.has(name):
			archetypes[name] = (ARCHETYPES[name] as Dictionary).merged({"count": used_archetypes[name]})
	return {
		"version": VERSION,
		"generated_by": "tools/north_end_census.tscn (NorthEndCensus.build); do not hand-edit",
		"meters_per_px": CityGenerator.METERS_PER_PX,
		"counts": counts,
		"archetypes": archetypes,
		"buildings": buildings,
		"out_of_area": out_of_area,
		"unbuilt": unbuilt,
	}


## Roster places that have no building box yet (the spot found no lot): they need a building when
## the area is repopulated. Street-only markers (corners, events, plugs) and free spots are skipped.
static func _unbuilt(spots_by_lot: Dictionary, locations_by_lot: Dictionary, streets: Array) -> Array[Dictionary]:
	var on_lot := {}
	for list: Array in locations_by_lot.values():
		for location: Location in list:
			on_lot[location] = true
	var mapped := {}
	for spot: Dictionary in spots_by_lot.values():
		mapped[spot_key(spot)] = true
	var out: Array[Dictionary] = []
	for spot: Dictionary in NorthEndSpots.SPOTS:
		var key := spot_key(spot)
		if mapped.has(key) or spot.get("free", false):
			continue
		if spot["kind"] == &"marker" and not ROSTER.has(key):
			continue
		var location: Location = Locations.get_location(spot.get("instance", spot.get("id", &"")))
		if location != null and on_lot.has(location):
			continue
		var px: Vector2 = spot["px"]
		var district := CityGenerator.district_for_px(px)
		var entry := {
			"id": "ne_%s_unbuilt_%s" % [DISTRICT_CODES.get(district, "xx"), key.replace("marker:", "roster_").to_lower()],
			"key": key, "source": "roster_spot", "district": String(district), "street": _street_at(px, streets)["name"],
			"position_m": _v2(Vector2(CityGenerator.px_to_world(px).x, CityGenerator.px_to_world(px).z)), "rect_px": [px.x, px.y, 0.0, 0.0],
			"category": "", "tags": [], "roles": [], "design_archetype": "", "name": spot["name"],
			"roster": [{"roster": spot["roster"], "name": spot["name"], "kind": String(spot["kind"]), "style": String(spot.get("style", ""))}],
			"note": "No lot within 40 px of the roster spot: the door stands on open ground with no building box.",
		}
		if ROSTER.has(key):
			var rule: Dictionary = ROSTER[key]
			entry["category"] = rule["category"]
			entry["design_archetype"] = rule["archetype"]
			entry["roles"] = (rule["roles"] as Array).duplicate(true)
		elif spot["kind"] == &"site":
			_business(entry, spot["id"])
		out.append(entry)
	return out


## Lot index -> NorthEndSpots spot, mirroring main.gd's placement order.
static func spots_by_lot(city: CityGenerator) -> Dictionary:
	var used := {}
	var out := {}
	for spot: Dictionary in NorthEndSpots.SPOTS:
		if spot.get("free", false):
			continue
		var px: Vector2 = spot["px"]
		var lot := city.lot_near(px, 40.0, used, CityGenerator.district_for_px(px))
		if lot.is_empty():
			continue
		used[lot["index"]] = true
		out[lot["index"]] = spot
	return out


## Lot index -> Locations whose door sits on that lot (its wireframe rect) or within
## [constant DOOR_SLACK] m of it (kit doors sit on the property line, nudged toward the street).
static func _locations_by_lot(city: CityGenerator) -> Dictionary:
	var out := {}
	for location: Location in Locations.all():
		var at := Vector2(location.global_position.x, location.global_position.z)
		var best := -1
		var best_gap := DOOR_SLACK
		# A location sits on the door of the lot it was placed for; a kit door on the sidewalk can
		# fall inside a neighbour's rect.
		for lot: Dictionary in city.building_lots:
			if lot.has("door") and (lot["door"] as Transform3D).origin.distance_to(Vector3(at.x, 0.0, at.y)) < 0.05:
				best = lot["index"]
				best_gap = 0.0
				break
		for lot: Dictionary in city.building_lots if best < 0 else []:
			var rect: Rect2 = lot["rect_px"]
			var corner := CityGenerator.px_to_world(rect.position)
			var area := Rect2(corner.x, corner.z, rect.size.x * CityGenerator.METERS_PER_PX, rect.size.y * CityGenerator.METERS_PER_PX)
			var gap := Vector2(maxf(0.0, maxf(area.position.x - at.x, at.x - area.end.x)), maxf(0.0, maxf(area.position.y - at.y, at.y - area.end.y))).length()
			if gap < best_gap:
				best_gap = gap
				best = lot["index"]
				if gap == 0.0:
					break
		if best >= 0:
			if not out.has(best):
				out[best] = []
			(out[best] as Array).append(location)
	return out

## One name per drivable road (index into NorthEndLayout.ROADS), from the nearest street label.
static func _street_names() -> Array:
	var roads: Array = NorthEndLayout.ROADS
	var names := []
	names.resize(roads.size())
	names.fill("")
	var best := []
	best.resize(roads.size())
	best.fill(INF)
	for label: Dictionary in NorthEndLayout.STREET_LABELS:
		var pos: Vector2 = label["pos"]
		var hit := -1
		var hit_d := 14.0
		for i in roads.size():
			if not (roads[i]["kind"] in [&"loc", &"ave", &"art"]):
				continue
			var d := _poly_distance(pos, roads[i]["pts"])
			if d < hit_d and _aligned(roads[i]["pts"], label["rot"]):
				hit_d = d
				hit = i
		if hit >= 0 and hit_d < best[hit]:
			best[hit] = hit_d
			names[hit] = label["text"]
	# Unlabelled runs (clipped pieces, connectors) borrow the nearest aligned label.
	for i in roads.size():
		if names[i] != "" or not (roads[i]["kind"] in [&"loc", &"ave", &"art"]):
			continue
		var nearest := ""
		var nearest_d := 80.0
		for label: Dictionary in NorthEndLayout.STREET_LABELS:
			if not _aligned(roads[i]["pts"], label["rot"]):
				continue
			var d := _poly_distance(label["pos"], roads[i]["pts"])
			if d < nearest_d:
				nearest_d = d
				nearest = label["text"]
		names[i] = nearest if nearest != "" else "Unnamed St"
	return names


static func _aligned(pts: Array, rot: float) -> bool:
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[pts.size() - 1]
	if a.distance_to(b) < 1.0:
		return true  # loops (lake drives) take any label
	var horizontal := absf(b.x - a.x) >= absf(b.y - a.y)
	var label_horizontal := absf(sin(deg_to_rad(rot))) < 0.7
	return horizontal == label_horizontal


static func _poly_distance(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


## Nearest drivable street to [param px]: {name, kind}.
static func _street_at(px: Vector2, names: Array) -> Dictionary:
	var roads: Array = NorthEndLayout.ROADS
	var best := {"name": "Unnamed St", "kind": "loc"}
	var best_d := INF
	var named := {}
	var named_d := INF
	for i in roads.size():
		if not (roads[i]["kind"] in [&"loc", &"ave", &"art"]):
			continue
		var d := _poly_distance(px, roads[i]["pts"])
		if d < best_d:
			best_d = d
			best = {"name": names[i], "kind": String(roads[i]["kind"])}
		if names[i] != "Unnamed St" and d < named_d:
			named_d = d
			named = {"name": names[i], "kind": String(roads[i]["kind"])}
	# A short unnamed connector beside a named street loses to the named one.
	return named if not named.is_empty() and named_d <= best_d + 16.0 else best


static func _yaw_deg(basis: Basis) -> float:
	var out := basis.z  # Locations and door_transform face local +Z toward the street
	return snappedf(rad_to_deg(atan2(out.x, out.z)), 1.0)


static func _v2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


static func _rect(r: Rect2) -> Array:
	return [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]


static func _base(key: String, source: String, district: StringName, rect_px: Rect2, center: Vector3, door: Transform3D, footprint: Vector2, height: float, block: int, streets: Array) -> Dictionary:
	var street := _street_at(CityGenerator.world_to_px(door.origin), streets)
	var lot_m := rect_px.size * CityGenerator.METERS_PER_PX
	return {
		"id": "", "key": key, "source": source, "district": String(district), "street": street["name"],
		"street_kind": street["kind"], "block": block, "rect_px": _rect(rect_px),
		"position_m": _v2(Vector2(center.x, center.z)), "yaw_deg": _yaw_deg(door.basis),
		"footprint_m": _v2(footprint), "height_m": snappedf(height, 0.01),
		"current_storeys": maxi(1, roundi(height / 3.2)), "lot_m": _v2(lot_m),
		"lot_frontage_depth_m": _v2(Vector2(lot_m.y, lot_m.x) if absf(door.basis.z.x) > absf(door.basis.z.z) else lot_m),
		"category": "", "tags": [], "roles": [], "design_archetype": "", "name": "", "roster": [],
	}


static func _lot_entry(key: String, lot: Dictionary, spot: Dictionary, locations: Array, streets: Array) -> Dictionary:
	# Street, side and order come from the wireframe lot's door, not the placed kit building's.
	var wireframe_lot := lot.duplicate()
	wireframe_lot.erase("door")
	var door := LocationPlacer.door_transform(wireframe_lot)
	if lot.has("street"):
		# Prefer the lot's street frontage (the populator's facing) over the block-centre guess.
		var outward: Vector3 = lot["street"]["outward"]
		var footprint: Vector2 = lot["footprint"]
		var half := footprint.x * 0.5 if outward.x != 0.0 else footprint.y * 0.5
		var center: Vector3 = lot["center"]
		door = Transform3D(Basis.looking_at(-outward), Vector3(center.x, 0.0, center.z) + outward * (half + 0.15))
	var named: Location = null
	for location: Location in locations:
		named = location
		door = location.global_transform
		break
	var district: StringName = lot["district"]
	var rect: Rect2 = lot["rect_px"]
	var block: Vector2i = lot["block"]
	var entry := _base(key, "landmark" if block.x < 0 else "lot", district, rect, lot["center"], door, lot.get("kit_footprint", lot["footprint"]), lot.get("kit_height", lot["height"]), block.x, streets)
	var roster_key := spot_key(spot)
	if ROSTER.has(roster_key):
		var rule: Dictionary = ROSTER[roster_key]
		entry["category"] = rule["category"]
		entry["design_archetype"] = rule["archetype"]
		entry["tags"] = (rule["tags"] as Array).duplicate()
		entry["roles"] = (rule["roles"] as Array).duplicate(true)
	elif spot.get("kind") == &"site":
		_business(entry, spot["id"])
	elif named != null and Businesses.site(named.instance_id) != null:
		_business(entry, named.instance_id)
	else:
		_generic(entry, lot, rect, door)
		if named != null and named.def.id == &"house":
			var tier: String = (ARCHETYPES[entry["design_archetype"]] as Dictionary).get("tier", "low")
			entry["roles"].append({"role": "robbery", "event": "burglary", "tier": tier})
			entry["tags"].append("specialized_location")
	if named != null:
		entry["name"] = named.label()
		entry["location"] = {"def": String(named.def.id), "instance": String(named.instance_id)}
	if not spot.is_empty():
		entry["roster"].append({"roster": spot["roster"], "name": spot["name"], "kind": String(spot["kind"]), "style": String(spot.get("style", ""))})
		if entry["name"] == "":
			entry["name"] = spot["name"]
		if spot["kind"] == &"marker" and not ROSTER.has(roster_key):
			entry["roles"].append({"role": "street_marker", "roster": spot["roster"], "style": String(spot.get("style", ""))})
	entry["tags"].append(String(district) if district != &"" else "unzoned")
	return entry


static func spot_key(spot: Dictionary) -> String:
	if spot.is_empty():
		return ""
	match spot["kind"]:
		&"location":
			return String(spot["instance"])
		&"site":
			return String(spot["id"])
	return "marker:%s" % spot["roster"]


static func _business(entry: Dictionary, site_id: StringName) -> void:
	var site := Businesses.site(site_id)
	entry["category"] = "purchasable_business"
	entry["design_archetype"] = SITE_ARCHETYPES.get(String(site_id), "storefront_1f")
	entry["tags"] = ["business"]
	var business := {"role": "business", "type": String(site.type_id), "purchasable": true, "site": String(site_id), "price": site.base_price(), "income": site.base_income()}
	entry["roles"] = [business]
	if site.type_id in STICK_UP_TYPES:
		entry["roles"].append({"role": "stick_up"})
	entry["name"] = site.label()


## Generic lots: houses by district, frontage and current height; bigger buildings on arterials and in Mangona.
static func _generic(entry: Dictionary, lot: Dictionary, rect: Rect2, door: Transform3D) -> void:
	var district: StringName = lot["district"]
	var height: float = lot["height"]
	var footprint: Vector2 = lot.get("classify_footprint", lot["footprint"])
	var area := footprint.x * footprint.y
	if lot.has("archetype") and ARCHETYPES.has(lot["archetype"]):
		entry["category"] = ARCHETYPES[lot["archetype"]]["category"]
		entry["design_archetype"] = lot["archetype"]
		entry["tags"] = ["residential"] if String(entry["category"]).begins_with("house") else ["commercial"]
		return
	if (lot["block"] as Vector2i).x < 0:
		entry["category"] = "house_1f"
		entry["design_archetype"] = "trailer_1f"
		return
	if district == &"mangona":
		entry["category"] = "large_building"
		entry["design_archetype"] = "warehouse" if area >= 900.0 else "industrial_shed"
		entry["tags"] = ["industrial"]
		return
	var arterial: bool = entry["street_kind"] == "art"
	if district == &"northgrove" and (arterial or height >= 12.5):
		entry["category"] = "large_building"
		entry["design_archetype"] = "mixed_use_2f" if arterial else "apartment_walkup_3f"
		entry["tags"] = ["commercial"] if arterial else ["residential"]
		return
	if arterial:
		entry["category"] = "large_building"
		entry["design_archetype"] = "storefront_1f"
		entry["tags"] = ["commercial"]
		return
	var two_floor := height >= (8.5 if district == &"northgrove" else 5.6)
	entry["category"] = "house_2f" if two_floor else "house_1f"
	entry["design_archetype"] = "%s_%s" % [entry["category"], _lot_type(rect, door)]
	entry["tags"] = ["residential"]


## small_yard / big_yard / deep_lot from the lot's frontage (along the street) and depth.
static func _lot_type(rect: Rect2, door: Transform3D) -> String:
	var size := rect.size * CLASSIFY_METERS_PER_PX
	var faces_x := absf(door.basis.z.x) > absf(door.basis.z.z)
	var frontage := size.y if faces_x else size.x
	var depth := size.x if faces_x else size.y
	if depth >= frontage * 1.5 and depth >= 20.0:
		return "deep_lot"
	if size.x * size.y >= 420.0:
		return "big_yard"
	return "small_yard"


static func _safehouse_entry(key: String, node: Safehouse, streets: Array) -> Dictionary:
	var district: StringName = node.district.district_id
	var center := node.global_position
	var at_px := CityGenerator.world_to_px(center)
	var size_m: Vector2 = node.data.footprint
	if absf(node.global_basis.x.x) < 0.5:
		size_m = Vector2(size_m.y, size_m.x)  # turned a quarter: the footprint lies the other way on the map
	var rect := Rect2(at_px - size_m / CityGenerator.METERS_PER_PX * 0.5, size_m / CityGenerator.METERS_PER_PX)
	var door := node.global_transform.translated_local(Vector3(0.0, 0.0, node.data.footprint.y * 0.5))
	var entry := _base(key, "safehouse", district, rect, center, door, node.data.footprint, node.data.height, -1, streets)
	var kind := String(node.data.resource_path.get_file().get_basename())
	entry["category"] = "special_building"
	entry["design_archetype"] = "safehouse_%s" % kind if ARCHETYPES.has("safehouse_%s" % kind) else "safehouse_greybox"
	entry["tags"] = ["safehouse", String(district)]
	entry["roles"] = [{"role": "safehouse"}, {"role": "turf_point", "district": String(district)}]
	entry["name"] = "%s safehouse" % node.district.display_name
	return entry


static func _hospital_entry(key: String, info: Dictionary, streets: Array) -> Dictionary:
	var rect: Rect2 = info["rect_px"]
	var node: Node3D = info["node"]
	var size := _box_size(node)
	var center := CityGenerator.px_to_world(rect.get_center())
	var door := Transform3D(Basis.looking_at(Vector3.FORWARD), center + Vector3(0.0, 0.0, size.z * 0.5))
	var district := CityGenerator.district_for_px(rect.get_center())
	var entry := _base(key, "landmark", district, rect, center, door, Vector2(size.x, size.z), size.y, -1, streets)
	entry["name"] = node.get_meta(&"landmark", "Landmark")
	entry["category"] = "special_building"
	entry["design_archetype"] = "grove_general_hospital"
	entry["tags"] = ["landmark", String(district)]
	entry["roles"] = [{"role": "landmark"}, {"role": "plug_contact", "roster": "P2"}]
	return entry


static func _filler_entry(key: String, info: Dictionary) -> Dictionary:
	var rect: Rect2 = info["rect_px"]
	var node: Node3D = info["node"]
	var size := _box_size(node)
	var center := CityGenerator.px_to_world(rect.get_center())
	return {
		"id": "", "key": key, "source": "filler", "district": "", "rect_px": _rect(rect),
		"position_m": _v2(Vector2(center.x, center.z)), "footprint_m": _v2(Vector2(size.x, size.z)),
		"height_m": snappedf(size.y, 0.01), "category": "out_of_area", "design_archetype": "neighbour_filler",
		"neighbourhood": "riviera" if rect.position.y < 400.0 else "clement",
	}


## Stable ids: ne_<district>_<street>_<nn>, numbered west->east, north->south along each street.
static func _assign_ids(entries: Array[Dictionary]) -> void:
	var groups := {}
	for entry in entries:
		var prefix: String
		if entry["source"] == "filler":
			prefix = "ne_out_%s" % entry["neighbourhood"]
		else:
			var slug: String = String(entry["street"]).to_lower().replace("&", "and")
			var clean := ""
			for c in slug:
				clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
			while clean.contains("__"):
				clean = clean.replace("__", "_")
			prefix = "ne_%s_%s" % [DISTRICT_CODES.get(StringName(entry["district"]), "xx"), clean.trim_suffix("_")]
		if not groups.has(prefix):
			groups[prefix] = []
		(groups[prefix] as Array).append(entry)
	for prefix: String in groups:
		var list: Array = groups[prefix]
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ra: Array = a["rect_px"]
			var rb: Array = b["rect_px"]
			return ra[1] < rb[1] if not is_equal_approx(ra[1], rb[1]) else ra[0] < rb[0])
		for i in list.size():
			list[i]["id"] = "%s_%02d" % [prefix, i + 1]


## Stand-in businesses. Generic buildings only (no roster place, hit, Location or purchasable site):
## 1. Open shops: for each zone, every needed shop type not already served by a purchasable business of
##    that trade gets one stand-in shop. Candidates are commercial frontages (storefront, mixed-use, and
##    Mangona sheds for auto shops) and residential corner lots. The pick scores the candidate kind plus
##    the distance to shops already placed (farthest wins), so shops spread out.
## 2. Every remaining storefront / mixed-use unit and arterial corner lot becomes a closed stand-in, so
##    arterials read as commercial streets.
static func _plan_standins(buildings: Array[Dictionary], unbuilt: Array[Dictionary]) -> void:
	var drivable := []
	for road: Dictionary in NorthEndLayout.ROADS:
		if road["kind"] in [&"loc", &"ave", &"art"]:
			drivable.append(road["pts"])
	var served := {}
	for entry in buildings + unbuilt:
		for role: Dictionary in entry["roles"]:
			if role.get("role") == "business" and role.get("purchasable", false) and BUSINESS_SHOP_TYPES.has(role["type"]):
				served["%s/%s" % [entry["district"], BUSINESS_SHOP_TYPES[role["type"]]]] = true
	var candidates: Array[Dictionary] = []
	for entry in buildings:
		if entry["source"] != "lot" or not entry["roles"].is_empty() or not entry["roster"].is_empty() or entry.has("location"):
			continue
		var kind := _standin_kind(entry, drivable)
		if kind != "":
			entry["_standin_kind"] = kind
			candidates.append(entry)
	var placed: Array[Dictionary] = []
	for zone: String in STANDIN_ZONE_NEEDS:
		var zone_placed: Array[Dictionary] = []
		for shop_type: String in STANDIN_ZONE_NEEDS[zone]:
			if served.has("%s/%s" % [zone, shop_type]) and shop_type != "food":
				continue
			var best: Dictionary = {}
			var best_score := -INF
			for entry in candidates:
				if entry["district"] != zone or entry.has("standin"):
					continue
				var score := _standin_score(entry, shop_type, zone_placed + placed)
				if score > best_score:
					best_score = score
					best = entry
			if best.is_empty():
				push_warning("census: no stand-in candidate for %s in %s" % [shop_type, zone])
				continue
			_make_standin(best, "standin_shop", shop_type)
			zone_placed.append(best)
		placed.append_array(zone_placed)
	for entry in candidates:
		var arterial_corner: bool = entry["_standin_kind"] == "corner_art" and entry["street_kind"] == "art"
		if not entry.has("standin") and (entry["_standin_kind"] in ["storefront", "mixed_use"] or arterial_corner):
			_make_standin(entry, "standin_closed", "")
	for entry in candidates:
		entry.erase("_standin_kind")


## storefront / mixed_use / shed (commercial or industrial frontage), corner_art / corner (residential
## corner lot, on an arterial or avenue / on a local street), or "" when not a candidate.
static func _standin_kind(entry: Dictionary, drivable: Array) -> String:
	match entry["design_archetype"]:
		"storefront_1f":
			return "storefront"
		"mixed_use_2f":
			return "mixed_use"
		"industrial_shed":
			return "shed"
	if not String(entry["category"]).begins_with("house_"):
		return ""
	var r: Array = entry["rect_px"]
	var rect := Rect2(r[0], r[1], r[2], r[3]).grow(10.0)
	var horizontal := false
	var vertical := false
	for pts: Array in drivable:
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if not _segment_hits_rect(a, b, rect):
				continue
			if absf(b.x - a.x) >= absf(b.y - a.y):
				horizontal = true
			else:
				vertical = true
	if not (horizontal and vertical):
		return ""
	return "corner_art" if entry["street_kind"] in ["art", "ave"] else "corner"


static func _segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 3.0))
	for s in steps + 1:
		if rect.has_point(a.lerp(b, float(s) / steps)):
			return true
	return false


static func _standin_score(entry: Dictionary, shop_type: String, placed: Array) -> float:
	var kind: String = entry["_standin_kind"]
	var bonus: float
	if shop_type == "auto_mod":
		bonus = {"shed": 300.0, "storefront": 120.0, "corner_art": 100.0}.get(kind, 0.0)
	elif shop_type == "corner_store":
		bonus = {"corner": 160.0, "corner_art": 140.0, "storefront": 60.0}.get(kind, 0.0)
	else:
		bonus = {"storefront": 160.0, "mixed_use": 150.0, "corner_art": 120.0, "corner": 40.0}.get(kind, -200.0)
	var center := _rect_center(entry)
	var nearest := 400.0
	for other: Dictionary in placed:
		nearest = minf(nearest, center.distance_to(_rect_center(other)))
	return bonus + nearest * 1.5


static func _rect_center(entry: Dictionary) -> Vector2:
	var r: Array = entry["rect_px"]
	return Vector2(r[0] + r[2] * 0.5, r[1] + r[3] * 0.5)


const STANDIN_SHOP_LABELS := {
	"auto_mod": "Auto mod shop", "ammo": "Ammo & gun counter", "clothing": "Clothing store", "food": "Food (diner / takeout)",
	"tattoo": "Tattoo shop", "barber": "Barber", "corner_store": "Corner store", "liquor": "Liquor store", "pawn": "Pawn shop",
}


static func _make_standin(entry: Dictionary, subtype: String, shop_type: String) -> void:
	var kind: String = entry["_standin_kind"]
	var was: String = entry["category"]
	var archetype: String
	if shop_type == "auto_mod":
		archetype = "standin_garage_bays"
	elif kind == "storefront":
		archetype = "standin_strip_unit"
	elif kind == "mixed_use":
		archetype = "standin_shopfront_2f"
	elif shop_type == "corner_store" or kind == "corner":
		archetype = "standin_corner_store"
	else:
		archetype = "standin_standalone_shop"
	entry["category"] = "standin_business"
	entry["design_archetype"] = archetype
	entry["tags"] = [subtype, was] + (entry["tags"] as Array).filter(func(tag: String) -> bool: return tag not in ["residential", "commercial", "industrial"]) + ["commercial"]
	entry["standin"] = {"subtype": subtype, "enterable": subtype == "standin_shop", "shop_type": shop_type, "replaces": kind}
	if subtype == "standin_shop":
		entry["roles"] = [{"role": "shop", "shop_type": shop_type, "enterable": true, "purchasable": false}]
		entry["name"] = STANDIN_SHOP_LABELS[shop_type]
	else:
		entry["roles"] = [{"role": "storefront", "enterable": false}]
		entry["name"] = "Closed storefront"


## Footprint x height x depth of a census node: its kit building (meta footprint_m / height_m) or
## its greybox box.
static func _box_size(node: Node3D) -> Vector3:
	if node.has_meta(&"footprint_m"):
		var footprint: Vector2 = node.get_meta(&"footprint_m")
		return Vector3(footprint.x, node.get_meta(&"height_m"), footprint.y)
	var shape := (node.get_child(0) as CollisionShape3D).shape as BoxShape3D
	return shape.size
