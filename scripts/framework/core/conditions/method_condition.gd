class_name MethodCondition
extends Condition
## Calls [member method] on the node picked by [member on] and treats the result as a bool. Lets any
## node expose gating logic to data without a new Condition class.

@export var method: StringName
@export var args: Array = []
## &"target", &"actor", &"location", &"occupant" or &"interactable".
@export var on: StringName = &"target"
## Pass ctx.actor as the first argument.
@export var pass_actor := false
## Pass the ActionContext (after the actor, if any).
@export var pass_context := false
## Optional method on the same node returning the failure text.
@export var reason_method: StringName
@export var reason_text := "Not available"


static func create(method_name: StringName, selector: StringName = &"target", call_args: Array = []) -> MethodCondition:
	var condition := MethodCondition.new()
	condition.method = method_name
	condition.on = selector
	condition.args = call_args
	return condition


func _evaluate(ctx: ActionContext) -> bool:
	return bool(ctx.invoke(on, method, args, pass_actor, pass_context))


func _reason(ctx: ActionContext) -> String:
	if reason_method != &"":
		var text: Variant = ctx.invoke(on, reason_method, args, pass_actor, pass_context)
		if text is String and text != "":
			return text
	return ctx.format(reason_text)
