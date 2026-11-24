class_name WorldDistrictProvider
extends DistrictProvider
## Reads district ownership from the live game: the Turf autoload (#24) when present, otherwise
## GameState.territories (ids are the snake_case of the territory display name).


func owner_of(district_id: StringName) -> StringName:
	var turf := _turf()
	if turf != null:
		return turf.call("owner_of", district_id)
	var territory := _territory(district_id)
	return territory.get("owner_gang") if territory != null else super.owner_of(district_id)


func display_name(district_id: StringName) -> String:
	var turf := _turf()
	if turf != null:
		return turf.call("display_name", district_id)
	var territory := _territory(district_id)
	return territory.get("display_name") if territory != null else super.display_name(district_id)


func all_districts() -> Array[StringName]:
	var turf := _turf()
	if turf != null and turf.has_method("all_ids"):
		var from_turf: Array[StringName] = []
		from_turf.assign(turf.call("all_ids"))
		return from_turf
	var ids: Array[StringName] = []
	for territory: Node in GameState.territories:
		ids.append(id_for(territory.get("display_name")))
	if ids.is_empty():
		return super.all_districts()
	ids.sort()
	return ids


static func id_for(district_name: String) -> StringName:
	var regex := RegEx.create_from_string("[^a-z0-9]+")
	return StringName(regex.sub(district_name.to_lower(), "_", true).strip_edges().trim_prefix("_").trim_suffix("_"))


func _turf() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Turf") if tree != null else null


func _territory(district_id: StringName) -> Node:
	for territory: Node in GameState.territories:
		if id_for(territory.get("display_name")) == district_id:
			return territory
	return null
