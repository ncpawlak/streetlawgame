class_name TurfContent
extends RefCounted
## The territory system's only gateway to content. Uses the ContentDB autoload when it exists, and
## otherwise scans the data folder directly, so territory code never builds resource paths itself.

## Fallback root, used only when no ContentDB autoload is registered.
const FALLBACK_ROOT := "res://data"


## Every resource of [param type] (e.g. &"districts"), sorted by id.
static func all(type: StringName) -> Array[Resource]:
	var db := _content_db()
	var result: Array[Resource] = []
	if db != null:
		for resource: Resource in db.call(&"all", type):
			result.append(resource)
	else:
		result = _scan(type)
	result.sort_custom(func(a: Resource, b: Resource) -> bool: return String(id_of(a)) < String(id_of(b)))
	return result


## The resource of [param type] with [param id], or null.
static func find(type: StringName, id: StringName) -> Resource:
	if id == &"":
		return null
	var db := _content_db()
	if db != null:
		return db.call(&"find_def", type, id) as Resource
	for resource in _scan(type):
		if id_of(resource) == id:
			return resource
	return null


## Loads a visual/asset by path (lets ContentDB apply asset overrides). Null when missing.
static func load_asset(path: String) -> Resource:
	if path.is_empty():
		return null
	var db := _content_db()
	if db != null and db.has_method(&"load_asset"):
		return db.call(&"load_asset", path) as Resource
	return load(path) if ResourceLoader.exists(path) else null


## A resource's id: its [code]id[/code] property, else its file name.
static func id_of(resource: Resource) -> StringName:
	var value: Variant = resource.get(&"id")
	if value is StringName and value != &"":
		return value
	return StringName(resource.resource_path.get_file().get_basename())


static func _content_db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"ContentDB") if tree != null else null


static func _scan(type: StringName) -> Array[Resource]:
	var result: Array[Resource] = []
	var directory := "%s/%s" % [FALLBACK_ROOT, type]
	for file in ResourceLoader.list_directory(directory):
		if file.ends_with(".tres") or file.ends_with(".res"):
			var resource := load("%s/%s" % [directory, file])
			if resource != null:
				result.append(resource)
	return result
