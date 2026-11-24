class_name Condition
extends Resource
## Gate for actions, costs, dialogue choices and simulation rules.
## Template method: subclasses override [method _evaluate] and [method _reason] only. Callers use
## [method is_met] and [method reason], which apply [member invert] and [member failure_text].

## Flip the result (e.g. "flag NOT set").
@export var invert := false
## Overrides the failure text shown to the player. Supports {vars}.
@export var failure_text := ""
## When true and this condition fails, the action is hidden instead of shown greyed out.
@export var hide_when_unmet := false


func is_met(ctx: ActionContext) -> bool:
	return _evaluate(ctx) != invert


## Why the condition isn't met, or "" when it is.
func reason(ctx: ActionContext) -> String:
	if is_met(ctx):
		return ""
	if failure_text != "":
		return ctx.format(failure_text) if ctx != null else failure_text
	if invert:
		return "Not available"
	return _reason(ctx)


## Short editor/debug description.
func describe() -> String:
	return ("NOT " if invert else "") + _describe()


func _evaluate(_ctx: ActionContext) -> bool:
	return true


func _reason(_ctx: ActionContext) -> String:
	return "Not available"


func _describe() -> String:
	return get_script().get_global_name() if get_script() != null else "Condition"


## True when every condition in the list is met.
static func all_met(conditions: Array, ctx: ActionContext) -> bool:
	for condition: Condition in conditions:
		if condition != null and not condition.is_met(ctx):
			return false
	return true


## The first failing condition's reason, or "".
static func first_reason(conditions: Array, ctx: ActionContext) -> String:
	for condition: Condition in conditions:
		if condition != null and not condition.is_met(ctx):
			return condition.reason(ctx)
	return ""


## True when any failing condition asks for the action to be hidden.
static func any_hides(conditions: Array, ctx: ActionContext) -> bool:
	for condition: Condition in conditions:
		if condition != null and condition.hide_when_unmet and not condition.is_met(ctx):
			return true
	return false
