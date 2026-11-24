class_name CashEffect
extends Effect
## Gives (or takes) cash: a random amount in [amount, max_amount] when max_amount > amount.
## The amount given is stored in ctx.vars["cash_gained"] for later effects' {cash_gained} text.

@export var amount := 0
@export var max_amount := 0
## Optional notification, e.g. "Took ${cash_gained} from the register".
@export var message := ""


func _apply(ctx: ActionContext) -> void:
	var value := amount
	if max_amount > amount:
		value = ctx.rng.randi_range(amount, max_amount)
	ctx.vars["cash_gained"] = value
	GameState.add_cash(value)
	if message != "":
		EventBus.notify.emit(ctx.format(message))


func _describe(_ctx: ActionContext) -> String:
	if max_amount > amount:
		return "$%d-%d" % [amount, max_amount]
	return "$%d" % amount
