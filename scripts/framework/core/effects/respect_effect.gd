class_name RespectEffect
extends Effect
## Gives (or takes) respect.

@export var amount := 0


func _apply(_ctx: ActionContext) -> void:
	GameState.add_respect(amount)


func _describe(_ctx: ActionContext) -> String:
	return "%+d respect" % amount
