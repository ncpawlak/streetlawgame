class_name MethodEffect
extends Effect
## Calls [member method] on the node picked by [member on]. Lets any node expose behaviour to data
## without a new Effect class.

@export var method: StringName
@export var args: Array = []
## &"target", &"actor", &"location", &"occupant" or &"interactable".
@export var on: StringName = &"target"
## Pass ctx.actor as the first argument.
@export var pass_actor := false
## Pass the ActionContext (after the actor, if any).
@export var pass_context := false


static func create(method_name: StringName, selector: StringName = &"target", call_args: Array = []) -> MethodEffect:
	var effect := MethodEffect.new()
	effect.method = method_name
	effect.on = selector
	effect.args = call_args
	return effect


func _apply(ctx: ActionContext) -> void:
	ctx.invoke(on, method, args, pass_actor, pass_context)
