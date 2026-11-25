class_name InteractStep
extends MissionStep
## Use an [Interactable]: completes when an action runs on an interactable (or its target) tagged
## [member target_tag] (Missions.tag). Empty [member action_id] accepts any action.

@export var target_tag: StringName
@export var action_id: StringName
@export var count := 1

var _done := 0


func _begin() -> void:
	_done = 0


func _handle(event: Dictionary) -> void:
	if event["type"] != &"interaction":
		return
	if action_id != &"" and event.get("action_id") != action_id:
		return
	if target_tag != &"" and not (Missions.has_tag(event.get("interactable"), target_tag) or Missions.has_tag(event.get("target"), target_tag)):
		return
	_done += 1
	notify_changed()
	if _done >= count:
		complete()


func _progress() -> String:
	return "%d/%d" % [_done, count] if count > 1 else ""


func _waypoint() -> Variant:
	return Missions.locate(target_tag) if target_tag != &"" else null
