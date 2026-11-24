class_name HeatEffect
extends Effect
## Raises police/gang heat. There's no wanted system yet; listeners of EventBus.heat_raised own that.

@export var amount := 1


func _apply(ctx: ActionContext) -> void:
	EventBus.heat_raised.emit(amount, ctx.location)


func _describe(_ctx: ActionContext) -> String:
	return "+%d heat" % amount
