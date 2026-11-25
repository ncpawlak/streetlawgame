class_name KillStep
extends MissionStep
## Kill targets: [member count] deaths of nodes tagged [member target_tag] (0 = every tagged target
## alive when the step starts), or of [member gang_id] members when there's no tag.
## [member drop_item_id] spawns a [MissionPickup] on the last body (loot the note).

@export var target_tag: StringName
@export var gang_id: StringName
@export var count := 0
@export var drop_item_id: StringName
@export var drop_prompt := "Search body"

var _required := 0
var _kills := 0


func _begin() -> void:
	_kills = 0
	_required = count
	if _required <= 0 and target_tag != &"":
		for node in Missions.tagged(target_tag):
			if not node.has_method("is_alive") or node.call("is_alive"):
				_required += 1
	_required = maxi(_required, 1)


func _handle(event: Dictionary) -> void:
	if event["type"] != &"killed":
		return
	var node: Node = event.get("node")
	if target_tag != &"":
		if not Missions.has_tag(node, target_tag):
			return
	elif gang_id != &"" and not (node is GangMember and (node as GangMember).gang_id == gang_id):
		return
	_kills += 1
	notify_changed()
	if _kills >= _required:
		if drop_item_id != &"" and node is Node3D and is_instance_valid(node):
			MissionPickup.spawn((node as Node3D).get_parent(), (node as Node3D).global_position, drop_item_id, drop_prompt)
		complete()


func _progress() -> String:
	return "%d/%d" % [_kills, _required] if _required > 1 else ""


func _waypoint() -> Variant:
	if target_tag == &"":
		return null
	for node in Missions.tagged(target_tag):
		if node is Node3D and (not node.has_method("is_alive") or node.call("is_alive")):
			return (node as Node3D).global_position
	return null
