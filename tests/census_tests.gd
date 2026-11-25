extends RefCounted
## North End building census (NorthEndCensus): every building box in the scene is listed in
## data/areas/north_end_buildings.json and every entry has a box; the file is current.

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run(main: Node) -> void:
	var census := NorthEndCensus.load_census()
	_runner._check(not census.is_empty(), "census: %s loads (regenerate with res://tools/north_end_census.tscn)" % NorthEndCensus.PATH)
	if census.is_empty():
		return
	var report := NorthEndCensus.coverage(main, census)
	_runner._check(report["unlisted"].is_empty(), "census: no scene building missing from the census (unlisted: %s)" % [report["unlisted"]])
	_runner._check(report["missing"].is_empty(), "census: every census entry has a scene building (missing: %s)" % [report["missing"]])
	_runner._check(report["duplicates"].is_empty(), "census: no building listed twice (%s)" % [report["duplicates"]])
	var bad: Array[String] = []
	var ids := {}
	for entry: Dictionary in census["buildings"]:
		var archetype: Dictionary = NorthEndCensus.ARCHETYPES.get(entry["design_archetype"], {})
		var category: String = entry["category"]
		if ids.has(entry["id"]) or not (StringName(category) in NorthEndCensus.CATEGORIES) or archetype.is_empty() \
				or not (archetype["category"] == category or archetype["category"] in entry["tags"]):
			bad.append(entry["id"])
		ids[entry["id"]] = true
	_runner._check(bad.is_empty(), "census: unique ids, valid category and matching design archetype (%s)" % [bad])
	_test_standins(census)
	var fresh: Dictionary = JSON.parse_string(JSON.stringify(NorthEndCensus.build(main)))
	_runner._check(JSON.stringify(fresh["buildings"]) == JSON.stringify(census["buildings"]) and JSON.stringify(fresh["unbuilt"]) == JSON.stringify(census["unbuilt"]),
		"census: %s matches the scene (regenerate with res://tools/north_end_census.tscn)" % NorthEndCensus.PATH)


## Stand-in businesses: valid shop data, never on a hit/roster/location building, and every zone in
## STANDIN_ZONE_NEEDS can buy each needed shop type (stand-in shop or purchasable business there).
func _test_standins(census: Dictionary) -> void:
	var bad: Array[String] = []
	var served := {}
	for entry: Dictionary in census["buildings"] + census.get("unbuilt", []):
		for role: Dictionary in entry["roles"]:
			if role.get("role") == "business" and role.get("purchasable", false) and NorthEndCensus.BUSINESS_SHOP_TYPES.has(role["type"]):
				served["%s/%s" % [entry["district"], NorthEndCensus.BUSINESS_SHOP_TYPES[role["type"]]]] = true
		if entry["category"] != "standin_business":
			continue
		var standin: Dictionary = entry.get("standin", {})
		var shop: bool = standin.get("subtype", "") == "standin_shop"
		if standin.is_empty() or not (standin["subtype"] in ["standin_shop", "standin_closed"]) \
				or (shop and not (standin.get("shop_type", "") in NorthEndCensus.STANDIN_SHOP_TYPES)) \
				or standin.get("enterable", false) != shop or not entry["roster"].is_empty() or entry.has("location") \
				or entry["roles"].any(func(r: Dictionary) -> bool: return not (r.get("role") in ["shop", "storefront"])):
			bad.append(entry["id"])
		elif shop:
			served["%s/%s" % [entry["district"], standin["shop_type"]]] = true
	_runner._check(bad.is_empty(), "census: stand-ins have valid shop data and only shop/storefront roles (%s)" % [bad])
	var gaps: Array[String] = []
	for zone: String in NorthEndCensus.STANDIN_ZONE_NEEDS:
		for shop_type: String in NorthEndCensus.STANDIN_ZONE_NEEDS[zone]:
			if not served.has("%s/%s" % [zone, shop_type]):
				gaps.append("%s/%s" % [zone, shop_type])
	_runner._check(gaps.is_empty(), "census: every zone can buy each needed shop type (gaps: %s)" % [gaps])