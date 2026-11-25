class_name FollowStep
extends MissionStep
## Follow an NPC (tagged [member npc_tag]). Asks the "follow" hook to drive the NPC (the companion
## system registers it) and completes when that system calls finish_hook("follow", npc_tag), or
## when the NPC is inside [member destination_zone]. Without a handler it falls back to the player
## reaching the destination. Falling more than [member max_distance] behind for
## [member lose_time] seconds fails the step.

@export var npc_tag: StringName
@export var destination_zone: StringName
@export var max_distance := 80.0
@export var lose_time := 10.0
@export var lost_text := "You lost them."

var _behind := 0.0
var _fallback := false


func _begin() -> void:
	_behind = 0.0
	_fallback = false
	Missions.request_hook(MissionService.HOOK_FOLLOW, npc_tag, run.ctx)


func _handle(event: Dictionary) -> void:
	if event["type"] != &"hook_done" or event.get("kind") != MissionService.HOOK_FOLLOW or event.get("hook_id") != npc_tag:
		return
	if event.get("outcome") == &"auto" and destination_zone != &"":
		_fallback = true
	elif event.get("outcome") == &"lost":
		fail(lost_text)
	else:
		complete()


func _tick(delta: float) -> void:
	var zone := Missions.find_zone(destination_zone)
	var npc := Missions.first_tagged(npc_tag) as Node3D
	var player := GameState.player
	if zone != null:
		if npc != null and zone.contains_point(npc.global_position):
			complete()
			return
		if _fallback and player != null and zone.contains_point(player.get_focus_position()):
			complete()
			return
	if npc == null or player == null or _fallback:
		return
	if player.get_focus_position().distance_to(npc.global_position) > max_distance:
		_behind += delta
		if _behind >= lose_time:
			fail(lost_text)
	else:
		_behind = 0.0


func _waypoint() -> Variant:
	if _fallback:
		return Missions.locate(destination_zone)
	var at: Variant = Missions.locate(npc_tag)
	return at if at != null else Missions.locate(destination_zone)
