extends Node
## Writes the North End building census (NorthEndCensus.PATH) from the live main scene.
## Run: godot --headless --path . res://tools/north_end_census.tscn
## Then: python tools/render_north_end_buildings.py (as-built building map).


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for i in 30:
		await get_tree().physics_frame
	var census := NorthEndCensus.build(main)
	var path := ProjectSettings.globalize_path(NorthEndCensus.PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(census, "\t", false) + "\n")
	file.close()
	var report := NorthEndCensus.coverage(main, census)
	print("census: %d buildings, %d out of area -> %s" % [census["buildings"].size(), census["out_of_area"].size(), NorthEndCensus.PATH])
	print("counts: %s" % census["counts"])
	print("archetypes: %d" % census["archetypes"].size())
	for name: String in census["archetypes"]:
		print("  %s x%d" % [name, census["archetypes"][name]["count"]])
	print("coverage: scene %d, census %d, unlisted %s, missing %s, duplicates %s" % [report["scene_count"], report["census_count"], report["unlisted"], report["missing"], report["duplicates"]])
	get_tree().quit(0 if report["unlisted"].is_empty() and report["missing"].is_empty() and report["duplicates"].is_empty() else 1)