class_name SaveGame
extends RefCounted
## Minimal save file: GameState basics, mission progress (journal, unlocks, safehouses, items) and
## any other autoload in [constant SYSTEMS] that has to_dict()/from_dict(). Safehouses call
## [method save_game]; the title/pause menu can call [method load_game].

const DEFAULT_PATH := "user://savegame.dat"
const VERSION := 1
## Autoloads saved alongside GameState when present and serialisable.
const SYSTEMS: Array[String] = ["Missions", "Turf", "Locations", "Operations", "Clout", "Businesses"]


static func save_game(path := DEFAULT_PATH) -> bool:
	var data := {"version": VERSION, "time": Time.get_unix_time_from_system(), "game": _game_state()}
	var systems := {}
	for name in SYSTEMS:
		var node := _autoload(name)
		if node != null and node.has_method("to_dict") and node.has_method("from_dict"):
			systems[name] = node.call("to_dict")
	data["systems"] = systems
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveGame: can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(var_to_str(data))
	return true


static func has_save(path := DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


## Restores a save. [param only] limits which systems are loaded (empty = all saved ones).
static func load_game(path := DEFAULT_PATH, only: Array = []) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = str_to_var(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_warning("SaveGame: %s is corrupt" % path)
		return false
	var game: Dictionary = data.get("game", {})
	GameState.cash = int(game.get("cash", GameState.cash))
	GameState.respect = int(game.get("respect", GameState.respect))
	GameState.play_time = float(game.get("play_time", GameState.play_time))
	GameState.flags = (game.get("flags", {}) as Dictionary).duplicate(true)
	EventBus.cash_changed.emit(GameState.cash)
	EventBus.respect_changed.emit(GameState.respect)
	var systems: Dictionary = data.get("systems", {})
	for name: String in systems:
		if not only.is_empty() and not only.has(name):
			continue
		var node := _autoload(name)
		if node != null and node.has_method("from_dict"):
			node.call("from_dict", systems[name])
	return true


static func delete_save(path := DEFAULT_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _game_state() -> Dictionary:
	return {"cash": GameState.cash, "respect": GameState.respect, "play_time": GameState.play_time, "flags": GameState.flags.duplicate(true)}


static func _autoload(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(name) if tree != null else null
