class_name TurfContent
extends RefCounted
## The territory system's gateway to content (ContentDB), so territory code never builds resource paths.


## Every definition of [param type] (e.g. &"districts"), sorted by id.
static func all(type: StringName) -> Array[Resource]:
	return ContentDB.all(type)


## The definition of [param type] with [param id], or null.
static func find(type: StringName, id: StringName) -> Resource:
	return ContentDB.find_def(type, id) if id != &"" else null


## A content id: [member ContentDef.id], else the resource's file name.
static func id_of(resource: Resource) -> StringName:
	if resource is ContentDef and (resource as ContentDef).id != &"":
		return (resource as ContentDef).id
	return StringName(resource.resource_path.get_file().get_basename())
