class_name PersuadeCheck
extends SkillCheck
## Talking someone round: better with street respect and their favour, worse when they're greedy.

@export var base := 0.35
## Chance per point of respect, capped at [member respect_cap].
@export var per_respect := 0.004
@export var respect_cap := 0.3
@export var favor_weight := 0.3
@export var greed_weight := 0.25


func _chance(ctx: ActionContext) -> float:
	var odds := base + minf(float(GameState.respect) * per_respect, respect_cap)
	odds += float(disposition(ctx).get("favor", 0.0)) * favor_weight
	var def := occupant_def(ctx)
	if def != null:
		odds -= def.greed * greed_weight
	return odds