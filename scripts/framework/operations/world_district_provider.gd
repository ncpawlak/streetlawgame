class_name WorldDistrictProvider
extends DistrictProvider
## Reads district ownership from the Turf autoload (#24). Falls back to the base DistrictProvider
## (its plain owners dictionary) when Turf isn't loaded.


func owner_of(district_id: StringName) -> StringName:
	var turf := _turf()
	return StringName(turf.call("owner_of", district_id)) if turf != null else super.owner_of(district_id)


func display_name(district_id: StringName) -> String:
	var turf := _turf()
	return String(turf.call("display_name", district_id)) if turf != null else super.display_name(district_id)


func all_districts() -> Array[StringName]:
	var turf := _turf()
	if turf != null:
		var ids: Array[StringName] = []
		ids.assign(turf.call("all_districts"))
		if not ids.is_empty():
			return ids
	return super.all_districts()


func _turf() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Turf") if tree != null else null