class_name PlayerDiedFail
extends MissionFail
## Fails the mission when the player dies (added automatically when MissionDef.fail_on_death).


func _init() -> void:
	reason = "You died."


func _handle(event: Dictionary, _run: MissionRun) -> bool:
	return event["type"] == &"player_died"
