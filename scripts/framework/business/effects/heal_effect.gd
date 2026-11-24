class_name HealEffect
extends Effect
## Restores the acting player's health.

@export var amount := 25.0


func _describe(_ctx: ActionContext) -> String:
	return "+%d health" % int(amount)


func _apply(ctx: ActionContext) -> void:
	var player := ctx.actor as Player if ctx.actor is Player else GameState.player
	if player != null:
		player.heal(amount)
