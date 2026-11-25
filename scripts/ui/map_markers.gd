class_name MapMarkers
extends RefCounted
## Builds the pause-map markers from live game data: Locations, Businesses, Operations, Turf
## safehouses, the roster markers main.gd places for items without a system yet, and hot cars.
## Each marker is a Dictionary:
## {id, categories: Array[StringName] (first = primary), title, info, position: Vector3, color,
##  glyph, coming_soon: bool, current: bool (the current mission)}.

## Legend order. &"turf" has no markers; it toggles the district ownership colouring.
const CATEGORIES := [
	{"id": &"objective", "label": "Objectives", "color": Color(1.0, 0.82, 0.2), "glyph": "!"},
	{"id": &"hit", "label": "Hit spots", "color": Color(1.0, 0.55, 0.2), "glyph": "$"},
	{"id": &"owned", "label": "Your businesses", "color": Color(0.3, 0.9, 0.45), "glyph": "B"},
	{"id": &"for_sale", "label": "For sale", "color": Color(0.3, 0.8, 0.9), "glyph": "S"},
	{"id": &"rival", "label": "Viper fronts", "color": Color(0.9, 0.2, 0.2), "glyph": "V"},
	{"id": &"plug", "label": "Plugs & corners", "color": Color(0.72, 0.45, 0.95), "glyph": "P"},
	{"id": &"safehouse", "label": "Safehouses", "color": Color(0.95, 0.95, 0.95), "glyph": "H"},
	{"id": &"weapons", "label": "Guns & explosives", "color": Color(0.6, 0.72, 0.85), "glyph": "G"},
	{"id": &"event", "label": "World events", "color": Color(1.0, 0.95, 0.4), "glyph": "*"},
	{"id": &"turf", "label": "Turf", "color": Color(0.6, 0.6, 0.6), "glyph": ""},
]

## Roster marker style (NorthEndSpots) -> map category.
const STYLE_CATEGORY := {
	&"home": &"hit", &"shop": &"hit", &"bank": &"hit", &"raid": &"hit",
	&"event": &"event", &"trap": &"for_sale", &"corner": &"plug", &"plug": &"plug",
}


static func category(id: StringName) -> Dictionary:
	for entry: Dictionary in CATEGORIES:
		if entry["id"] == id:
			return entry
	return {}


static func collect(tree: SceneTree) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	var player_at := GameState.player.get_focus_position() if GameState.player != null else Vector3.ZERO
	_collect_locations(markers)
	_collect_roster(tree, markers)
	_collect_hot_cars(tree, markers)
	_collect_turf(markers, player_at)
	_collect_missions(tree, markers)
	return markers


static func make(categories: Array, title: String, info: String, at: Vector3, color := Color(0, 0, 0, 0)) -> Dictionary:
	var primary := category(categories[0])
	return {
		"id": "%s@%d,%d" % [title, roundi(at.x), roundi(at.z)],
		"categories": categories,
		"title": title,
		"info": info,
		"position": Vector3(at.x, 0.0, at.z),
		"color": color if color.a > 0.0 else primary.get("color", Color.WHITE),
		"glyph": primary.get("glyph", "?"),
		"coming_soon": false,
		"current": false,
	}


static func _collect_locations(markers: Array[Dictionary]) -> void:
	var business_ids := {}
	for site: BusinessSiteDef in Businesses.all_sites():
		business_ids[site.id] = true
	var operation_sites := {}
	var plugs := {}
	var model := Operations.model
	if model != null:
		for site_id in model.site_ids():
			operation_sites[model.site(site_id).location_id] = site_id
		for plug_id in model.plug_ids():
			plugs[model.plug(plug_id).location_id] = plug_id
	for location in Locations.all():
		if not is_instance_valid(location) or not location.is_inside_tree() or location.def == null:
			continue
		var iid := location.instance_id
		var def_id := location.def.id
		var district := Turf.display_name(location.district_id) if location.district_id != &"" else "No man's land"
		var at := location.global_position
		if business_ids.has(iid):
			markers.append(_business_marker(iid, location, district, at))
		elif operation_sites.has(iid) or operation_sites.has(def_id):
			var site_id: StringName = operation_sites.get(iid, operation_sites.get(def_id))
			var site := model.site(site_id)
			if model.is_site_acquired(site_id):
				markers.append(make([&"owned"], site.label(), "Your %s in %s.\nCrew it from the operations menu [O]." % [String(site.kind).replace("_", " "), district], at))
			else:
				var reason := model.can_acquire_site(site_id)
				markers.append(make([&"for_sale"], site.label(), "Operation site in %s.\nAcquire for $%d.%s" % [district, site.acquire_price, ("\nLocked: " + reason) if reason != "" else ""], at))
		elif plugs.has(iid) or plugs.has(def_id):
			var plug_id: StringName = plugs.get(iid, plugs.get(def_id))
			if model.is_plug_revealed(plug_id):
				var plug := model.plug(plug_id)
				var state := "Supplying you" if model.is_plug_established(plug_id) else "Meet them to set up a supply line"
				markers.append(make([&"plug"], "%s (%s)" % [plug.label(), location.label()], "Plug in %s.\n%s." % [district, state], at))
		elif location.kind() == &"front":
			if location.status() != Location.TAKEN_OUT and location.owner_gang() != GameState.PLAYER_GANG:
				var gang := location.owner_gang()
				markers.append(make([&"rival"], location.label(), "%s front in %s.\nTake it out to weaken their hold." % [GameState.gang_name(gang), district], at, GameState.gang_color(gang)))
		elif location.def.has_tag(&"robbable"):
			var robbed := location.status() == Location.ROBBED
			var info := "%s in %s.\n%s" % [String(location.kind()).capitalize(), district, "Robbed - lying low for now." if robbed else "Hit it for cash."]
			var color: Color = category(&"hit")["color"]
			markers.append(make([&"hit"], location.label(), info, at, color.darkened(0.55) if robbed else Color(0, 0, 0, 0)))
		elif location.kind() == &"contact":
			markers.append(make([&"plug"], location.label(), "Contact in %s." % district, at))


static func _business_marker(site_id: StringName, location: Location, district: String, at: Vector3) -> Dictionary:
	var business_type := Businesses.type_of(site_id)
	var type_name := business_type.label() if business_type != null else "Business"
	var categories: Array = []
	var sells: Array[String] = []
	var armory := false
	for item in Businesses.shop_items(site_id):
		sells.append(item.label())
		armory = armory or ContentDB.has_def(&"weapons", item.id)
	if armory:
		categories.append(&"weapons")
	var info := "%s in %s." % [type_name, district]
	if Businesses.is_owned(site_id):
		categories.append(&"owned")
		info += "\nYours - $%d income." % Businesses.income_of(site_id)
	else:
		categories.append(&"for_sale")
		info += "\nFor sale: $%d." % Businesses.price_of(site_id)
		var reason := Businesses.purchase_block_reason(site_id)
		if reason != "":
			info += "\nLocked: %s" % reason
	if not sells.is_empty():
		info += "\nSells: %s" % ", ".join(sells)
	return make(categories, location.label(), info, at)


static func _collect_roster(tree: SceneTree, markers: Array[Dictionary]) -> void:
	for node in tree.get_nodes_in_group(&"roster_markers"):
		var spot: Dictionary = node.get_meta(&"spot", {})
		if spot.is_empty():
			continue
		var style: StringName = spot.get("style", &"event")
		var title := "#%s %s" % [spot["roster"], spot["name"]] if spot["roster"] != "" else String(spot["name"])
		var district := Turf.display_name(CityGenerator.district_for_px(spot["px"]))
		var marker := make([STYLE_CATEGORY.get(style, &"event")], title, "%s - coming soon.\n%s" % [String(style).capitalize(), district if district != "" else "North End"], (node as Node3D).global_position, NorthEndSpots.MARKER_COLORS.get(style, Color.WHITE))
		marker["coming_soon"] = true
		markers.append(marker)


static func _collect_hot_cars(tree: SceneTree, markers: Array[Dictionary]) -> void:
	for node in tree.get_nodes_in_group(&"hot_cars"):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.damage_state == Vehicle.DamageState.WRECKED:
			continue
		if GameState.player != null and GameState.player.current_vehicle == vehicle:
			continue
		markers.append(make([&"event"], "Hot car", "A car worth boosting. Steal it [E] before someone else does.", vehicle.global_position, Color(0.95, 0.45, 0.1)))


## Safehouses, plus objectives: taking over each rival-held district by claiming its safehouse.
## The nearest one is the current mission.
static func _collect_turf(markers: Array[Dictionary], player_at: Vector3) -> void:
	var objectives: Array[Dictionary] = []
	for district_id in Turf.all_districts():
		var safehouse := Turf.safehouse_of(district_id)
		if safehouse == null or not safehouse.is_inside_tree():
			continue
		var holder := Turf.owner_of(district_id)
		var name := Turf.display_name(district_id)
		var at := safehouse.door_position()
		var info := "%s safehouse.\nHeld by %s." % [name, GameState.gang_name(holder)]
		if holder == GameState.PLAYER_GANG:
			info += "\nYours - manage your crew here."
		else:
			var reason := safehouse.claim_block_reason()
			info += "\n%s" % (reason if reason != "" else "Claim it [E] to take the district.")
			var objective := make([&"objective"], "Take over %s" % name, "Clear the %s crew at %s and claim it to take %s." % [GameState.gang_name(holder), safehouse.label(), name], at)
			objective["offset"] = Vector2(0.0, -26.0)
			objectives.append(objective)
		markers.append(make([&"safehouse"], safehouse.label(), info, at, GameState.gang_color(holder)))
	objectives.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["position"] as Vector3).distance_to(player_at) < (b["position"] as Vector3).distance_to(player_at))
	if not objectives.is_empty():
		objectives[0]["current"] = true
		objectives[0]["info"] = "Current mission.\n" + objectives[0]["info"]
	markers.append_array(objectives)


## Mission start markers, unlocked lead markers, player safehouses, and the active mission's
## objective (which becomes the one "current" marker).
static func _collect_missions(tree: SceneTree, markers: Array[Dictionary]) -> void:
	for node in tree.get_nodes_in_group(MissionStartMarker.GROUP):
		var start := node as MissionStartMarker
		if start != null and start.is_inside_tree() and start.is_available():
			var def := Missions.get_mission(start.mission_id)
			var title := def.label() if def != null else String(start.mission_id)
			markers.append(make([&"objective"], title, "Mission. %s" % (def.description if def != null else ""), start.global_position))
	for lead in Missions.journal.leads(MissionJournal.OPEN):
		if Missions.journal.is_marker_visible(lead["id"]):
			markers.append(make([&"objective"], "Lead: %s" % lead["title"], String(lead["note"]), lead["marker"]))
	for safehouse in Missions.safehouses():
		if safehouse.is_unlocked():
			var info := "Your safehouse. Rest, save, store cars, change clothes."
			if safehouse.def != null and safehouse.def.address != "":
				info = "%s\n%s" % [safehouse.def.address, info]
			markers.append(make([&"safehouse"], safehouse.label(), info, safehouse.global_position))
	var run := Missions.active
	var at: Variant = Missions.current_waypoint()
	if run != null and at is Vector3:
		for marker in markers:
			marker["current"] = false
		var lines := run.objective_lines().filter(func(l: Dictionary) -> bool: return not l.get("done") and not l.get("bonus"))
		var objective := make([&"objective"], run.def.label(), String(lines[0]["text"]) if not lines.is_empty() else "", at)
		objective["current"] = true
		markers.append(objective)