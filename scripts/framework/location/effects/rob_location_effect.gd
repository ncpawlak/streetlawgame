class_name RobLocationEffect
extends Effect
## Takes [member fraction] of the location's register (plus a random bonus) and gives it to the player.
## Stores the amount in ctx.vars["cash_gained"]; emits EventBus.location_robbed.

@export_range(0.0, 1.0) var fraction := 1.0
@export var bonus_min := 0
@export var bonus_max := 0
@export var message := "Took ${cash_gained} from {location}"


func _apply(ctx: ActionContext) -> void:
	var location := ctx.location as Location
	if location == null:
		return
	var taken := int(location.state.cash * fraction)
	location.state.cash -= float(taken)
	if bonus_max > bonus_min:
		taken += ctx.rng.randi_range(bonus_min, bonus_max)
	else:
		taken += bonus_min
	ctx.vars["cash_gained"] = taken
	GameState.add_cash(taken)
	EventBus.location_robbed.emit(location, taken)
	if message != "":
		EventBus.notify.emit(ctx.format(message))


func _describe(_ctx: ActionContext) -> String:
	return "Rob %d%% of the register" % int(fraction * 100.0)
