class_name Effect
extends Resource
## Something that happens when an action completes, a dialogue choice is picked, or a rule fires.
## Template method: subclasses override [method _apply] and [method _describe].

## Probability (0-1) that this effect fires; rolled with ctx.rng.
@export_range(0.0, 1.0) var chance := 1.0


func apply(ctx: ActionContext) -> void:
	if chance < 1.0 and ctx.rng.randf() >= chance:
		return
	_apply(ctx)


func describe(ctx: ActionContext = null) -> String:
	return _describe(ctx)


func _apply(_ctx: ActionContext) -> void:
	pass


func _describe(_ctx: ActionContext) -> String:
	return ""


static func apply_all(effects: Array, ctx: ActionContext) -> void:
	for effect: Effect in effects:
		if effect != null:
			effect.apply(ctx)
