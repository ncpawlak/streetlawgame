class_name TalkStep
extends MissionStep
## Talk to an NPC. Runs dialogue [member dialogue_id] through the "dialogue" hook (the dialogue
## system, or the built-in DialogueView as a fallback) and completes when it ends.
## Starts the conversation immediately when [member auto_start], otherwise when the player uses
## the [member talk_action] on the NPC tagged [member npc_tag] (or any other system ends the same
## dialogue, e.g. an NPC with its own StartDialogueEffect).

@export var npc_tag: StringName
@export var dialogue_id: StringName
## Required dialogue outcome; empty accepts any. Auto-finished (unhandled) hooks always count.
@export var outcome: StringName
@export var auto_start := false
@export var talk_action: StringName = &"talk"
## The outcome is stored in run vars under this name.
@export var store_outcome_as: StringName = &"dialogue_outcome"

var _requested := false


func _begin() -> void:
	_requested = false
	if auto_start:
		_request()


func _handle(event: Dictionary) -> void:
	match event["type"]:
		&"interaction":
			if not _requested and npc_tag != &"" and event.get("action_id") == talk_action \
					and (Missions.has_tag(event.get("target"), npc_tag) or Missions.has_tag(event.get("interactable"), npc_tag)):
				_request()
		&"dialogue_ended":
			_finish(event.get("dialogue_id"), event.get("outcome", &""))
		&"hook_done":
			if event.get("kind") == MissionService.HOOK_DIALOGUE:
				_finish(event.get("hook_id"), event.get("outcome", &""))


func _request() -> void:
	_requested = true
	Missions.request_hook(MissionService.HOOK_DIALOGUE, dialogue_id, run.ctx)


func _finish(finished_id: Variant, finished_outcome: Variant) -> void:
	if StringName(str(finished_id)) != dialogue_id or state != State.ACTIVE:
		return
	var result := StringName(str(finished_outcome))
	if outcome != &"" and result != outcome and result != &"auto":
		return
	run.ctx.vars[store_outcome_as] = result
	complete()


func _waypoint() -> Variant:
	return Missions.locate(npc_tag) if npc_tag != &"" else null
