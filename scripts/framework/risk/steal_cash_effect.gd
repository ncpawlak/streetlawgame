class_name StealCashEffect
extends Effect
## Risk effect: the player loses a random amount of cash (stick-up, shakedown, bribe).

@export var min_amount := 100
@export var max_amount := 500


func _apply(ctx: ActionContext) -> void:
	var model := OperationsModel.from_context(ctx)
	if model == null:
		return
	var amount := ctx.rng.randi_range(min_amount, max_amount) if ctx.rng != null else min_amount
	model.add_income(-amount, StringName(str(ctx.vars.get("site_id", ""))))
