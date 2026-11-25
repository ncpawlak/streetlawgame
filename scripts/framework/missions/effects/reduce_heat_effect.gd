class_name ReduceHeatEffect
extends Effect
## Lowers Missions.heat by [member amount]; a negative amount clears it.

@export var amount := -1.0


func _apply(_ctx: ActionContext) -> void:
	if amount < 0.0:
		Missions.heat.clear()
	else:
		Missions.heat.reduce(amount)
