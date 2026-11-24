class_name RecruitEffect
extends Effect
## Adds a crew member (named after the occupant unless [member crew_name] is set) to GameState.crew.

@export var crew_name := ""
@export var skill := 1
@export var message := "{occupant} joined your crew"


func _apply(ctx: ActionContext) -> void:
	var member_name := crew_name if crew_name != "" else ActionContext._label_of(ctx.occupant)
	var member := CrewMemberData.create(member_name if member_name != "" else "Recruit")
	member.skill = skill
	GameState.crew.append(member)
	EventBus.crew_recruited.emit(member)
	if message != "":
		EventBus.notify.emit(ctx.format(message))


func _describe(_ctx: ActionContext) -> String:
	return "Recruit"
