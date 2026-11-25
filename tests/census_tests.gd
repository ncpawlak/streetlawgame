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
	var fresh: Dictionary = JSON.parse_string(JSON.stringify(NorthEndCensus.build(main)))
	_runner._check(JSON.stringify(fresh["buildings"]) == JSON.stringify(census["buildings"]) and JSON.stringify(fresh["unbuilt"]) == JSON.stringify(census["unbuilt"]),
		"census: %s matches the scene (regenerate with res://tools/north_end_census.tscn)" % NorthEndCensus.PATH)