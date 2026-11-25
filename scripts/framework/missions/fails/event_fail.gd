class_name EventFail
extends MissionFail
## Fails when a mission event of [member event_type] arrives whose fields match [member event_match]
## (compared as strings), e.g. {type: "flag", flag: "alarm"}.

@export var event_type: StringName
@export var event_match: Dictionary = {}


func _handle(event: Dictionary, _run: MissionRun) -> bool:
	return event["type"] == event_type and WaitStep.matches(event, event_match)
