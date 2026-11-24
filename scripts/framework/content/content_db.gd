extends Node
## Generic content registry (autoload "ContentDB").
##
## Content is stored as <root>/<type>/**/<id>.tres: the folder name is the content type and the file
## basename is the id. Roots are layered by priority, so a mod or override root that ships the same
## (type, id) replaces the base game's version. Runtime/procedural content can be [method register]ed
## and wins over files. Resources load lazily on first lookup and are cached.
##
## Gameplay code asks for (type, id) and never hardcodes res:// content paths.

signal content_reloaded

const DEFAULT_ROOT := "res://data"
## Optional PackedStringArray of extra content roots, read at startup.
const EXTRA_ROOTS_SETTING := "street_law/content/extra_roots"
## Every user://mods/<mod>/data folder is added as an override root automatically.
const MODS_DIR := "user://mods"
const BASE_PRIORITY := 0
const SETTING_PRIORITY := 50
const MOD_PRIORITY := 100
const EXTENSIONS: Array[String] = ["tres", "res"]

## Sorted by ascending priority: {path, priority, asset_base, order}.
var _roots: Array[Dictionary] = []
## type -> {id -> path}
var _index := {}
## type -> {id -> Resource}
var _runtime := {}
## path -> Resource
var _cache := {}
var _indexed := false
var _scan_issues := PackedStringArray()
var _root_order := 0


func _init() -> void:
	add_content_root(DEFAULT_ROOT, BASE_PRIORITY, "res://")
	if ProjectSettings.has_setting(EXTRA_ROOTS_SETTING):
		for path: String in ProjectSettings.get_setting(EXTRA_ROOTS_SETTING):
			add_content_root(path, SETTING_PRIORITY)
	_add_mod_roots()


## The definition for (type, id), or null with an error if it doesn't exist.
func get_def(type: StringName, id: StringName) -> Resource:
	var resource := find_def(type, id)
	if resource == null:
		push_error("ContentDB: unknown %s id '%s'" % [type, id])
	return resource


## The definition for (type, id), or null (silently) if it doesn't exist.
func find_def(type: StringName, id: StringName) -> Resource:
	var runtime: Dictionary = _runtime.get(type, {})
	if runtime.has(id):
		return runtime[id]
	_ensure_index()
	var path: String = _index.get(type, {}).get(id, "")
	return _load(path) if path != "" else null


func has_def(type: StringName, id: StringName) -> bool:
	if _runtime.get(type, {}).has(id):
		return true
	_ensure_index()
	return _index.get(type, {}).has(id)


## All ids of a type, sorted.
func ids(type: StringName) -> Array[StringName]:
	_ensure_index()
	var unique := {}
	for id: StringName in _index.get(type, {}):
		unique[id] = true
	for id: StringName in _runtime.get(type, {}):
		unique[id] = true
	return _sorted_names(unique.keys())


## Every definition of a type, sorted by id.
func all(type: StringName) -> Array[Resource]:
	var result: Array[Resource] = []
	for id in ids(type):
		var resource := find_def(type, id)
		if resource != null:
			result.append(resource)
	return result


func filter(type: StringName, predicate: Callable) -> Array[Resource]:
	var result: Array[Resource] = []
	for resource in all(type):
		if predicate.call(resource):
			result.append(resource)
	return result


## Definitions whose `tags` contain [param tag].
func with_tag(type: StringName, tag: StringName) -> Array[Resource]:
	return filter(type, func(resource: Resource) -> bool:
		return "tags" in resource and (resource.get("tags") as Array).has(tag))


func types() -> Array[StringName]:
	_ensure_index()
	var unique := {}
	for type: StringName in _index:
		unique[type] = true
	for type: StringName in _runtime:
		unique[type] = true
	return _sorted_names(unique.keys())


## Adds runtime or procedural content. It takes priority over files with the same (type, id).
func register(type: StringName, resource: Resource, id: StringName = &"") -> void:
	if id == &"" and "id" in resource:
		id = resource.get("id")
	if id == &"":
		push_error("ContentDB.register: %s content needs an id" % type)
		return
	if not _runtime.has(type):
		_runtime[type] = {}
	_runtime[type][id] = resource


func unregister(type: StringName, id: StringName) -> void:
	if _runtime.has(type):
		(_runtime[type] as Dictionary).erase(id)


## Adds a folder laid out like res://data (<path>/<type>/<id>.tres). Higher priority wins on conflicts.
## [param asset_base] is where [method load_asset] looks for overridden assets; it defaults to the parent
## of [param path] (user://mods/foo/data -> user://mods/foo).
func add_content_root(path: String, priority: int = MOD_PRIORITY, asset_base: String = "") -> void:
	remove_content_root(path)
	_root_order += 1
	_roots.append({
		"path": path,
		"priority": priority,
		"asset_base": asset_base if asset_base != "" else path.get_base_dir(),
		"order": _root_order,
	})
	_roots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.priority < b.priority if a.priority != b.priority else a.order < b.order)
	_indexed = false


func remove_content_root(path: String) -> void:
	for i in range(_roots.size() - 1, -1, -1):
		if _roots[i].path == path:
			_roots.remove_at(i)
			_indexed = false


func content_roots() -> PackedStringArray:
	var result := PackedStringArray()
	for root in _roots:
		result.append(root.path)
	return result


## Rescans every root and drops cached resources.
func reload() -> void:
	_cache.clear()
	_indexed = false
	_ensure_index()
	content_reloaded.emit()


## Loads an asset (scene, mesh, texture...) by its base-game path. The same relative path under a
## higher-priority root's asset base wins, so art can be swapped without touching data or code.
func load_asset(path: String) -> Resource:
	if path == "":
		return null
	if path.begins_with("res://"):
		var relative := path.trim_prefix("res://")
		for i in range(_roots.size() - 1, -1, -1):
			var base: String = _roots[i].asset_base
			if base == "res://" or base == "":
				continue
			var candidate := base.path_join(relative)
			if ResourceLoader.exists(candidate):
				return _load(candidate)
	return _load(path) if ResourceLoader.exists(path) else null


## Problems with the loaded content: load failures, id/basename mismatches, duplicate ids within
## one root, and each ContentDef's own validate().
func validate() -> PackedStringArray:
	_ensure_index()
	var issues := _scan_issues.duplicate()
	for type: StringName in _index:
		for id: StringName in _index[type]:
			var path: String = _index[type][id]
			var resource := _load(path)
			if resource == null:
				issues.append("%s: failed to load" % path)
				continue
			if "id" in resource and resource.get("id") != id:
				issues.append("%s: id '%s' does not match file name '%s'" % [path, resource.get("id"), id])
			if resource is ContentDef:
				for issue in (resource as ContentDef).validate():
					issues.append("%s: %s" % [path, issue])
	return issues


func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	_index.clear()
	_scan_issues.clear()
	for root in _roots:
		var root_path: String = root.path
		var dir := DirAccess.open(root_path)
		if dir == null:
			continue
		for type_name in dir.get_directories():
			if type_name.begins_with("."):
				continue
			var type := StringName(type_name)
			if not _index.has(type):
				_index[type] = {}
			_scan(root_path.path_join(type_name), _index[type], {})


func _scan(dir_path: String, into: Dictionary, seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		var resource_name := file_name.trim_suffix(".remap")
		if not EXTENSIONS.has(resource_name.get_extension()):
			continue
		var id := StringName(resource_name.get_basename())
		var path := dir_path.path_join(resource_name)
		if seen.has(id):
			_scan_issues.append("%s: duplicate id '%s' (also %s)" % [path, id, seen[id]])
		seen[id] = path
		into[id] = path
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_scan(dir_path.path_join(sub), into, seen)


func _load(path: String) -> Resource:
	if _cache.has(path):
		return _cache[path]
	var resource := ResourceLoader.load(path)
	if resource != null:
		_cache[path] = resource
	return resource


func _add_mod_roots() -> void:
	var mods := DirAccess.open(MODS_DIR)
	if mods == null:
		return
	var names := Array(mods.get_directories())
	names.sort()
	for mod_name: String in names:
		var data := MODS_DIR.path_join(mod_name).path_join("data")
		if DirAccess.dir_exists_absolute(data):
			add_content_root(data, MOD_PRIORITY)


static func _sorted_names(keys: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(keys)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result
