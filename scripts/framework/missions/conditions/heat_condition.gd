class_name HeatCondition
extends Condition
## True when the heat (Missions.heat stars) is within [[member min_stars], [member max_stars]].
## Defaults mean "no heat at all" (any heat, even below one star, fails).

@export var min_stars := 0
@export var max_stars := 0


func _evaluate(_ctx: ActionContext) -> bool:
	if max_stars <= 0:
		return not Missions.heat.is_hot()
	var stars := Missions.heat.stars()
	return stars >= min_stars and stars <= max_stars


func _reason(_ctx: ActionContext) -> String:
	return "Lose the heat first" if Missions.heat.stars() > max_stars or (max_stars <= 0 and Missions.heat.is_hot()) else "Not enough heat"
