class_name NotifyEffect
extends Effect
## Shows a HUD notification. Supports {vars}.

@export var text := ""


func _apply(ctx: ActionContext) -> void:
	EventBus.notify.emit(ctx.format(text))
