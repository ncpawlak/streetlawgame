class_name BuyItemStep
extends MissionStep
## Buy something at a shop: [member count] EventBus.shop_purchase events for [member item_id]
## (empty = anything) at [member site_id] (empty = any shop). With [member give_mission_item] the
## purchase is also added to Missions.items so later HaveItemSteps can check it.

@export var item_id: StringName
@export var site_id: StringName
@export var count := 1
@export var give_mission_item := false

var _bought := 0


func _begin() -> void:
	_bought = 0


func _handle(event: Dictionary) -> void:
	if event["type"] != &"purchase":
		return
	if item_id != &"" and event.get("item_id") != item_id:
		return
	if site_id != &"" and event.get("site_id") != site_id:
		return
	_bought += 1
	if give_mission_item:
		Missions.items.add(event.get("item_id"), 1)
	notify_changed()
	if _bought >= count:
		complete()


func _progress() -> String:
	return "%d/%d" % [_bought, count] if count > 1 else ""


func _waypoint() -> Variant:
	if site_id == &"":
		return null
	var location: Location = Locations.get_location(site_id)
	if location == null:
		var matches := Locations.of_def(site_id)
		location = matches[0] if not matches.is_empty() else null
	return location.global_position if location != null and location.is_inside_tree() else null
