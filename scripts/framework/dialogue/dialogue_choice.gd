class_name DialogueChoice
extends Resource
## A player reply: gated by conditions, paid with costs, optionally resolved by a SkillCheck.

## E.g. "[Persuade] Come on, help a neighbour out." Supports {vars}.
@export var text := ""
@export var conditions: Array[Condition] = []
## "Pay" choices use CashCost.
@export var costs: Array[Cost] = []
## Null = always succeeds.
@export var check: SkillCheck
@export var effects: Array[Effect] = []
## Node to go to on success; empty ends the conversation.
@export var next: StringName = &""
@export var fail_effects: Array[Effect] = []
## Node on a failed check; empty ends the conversation.
@export var fail_next: StringName = &""
## Hide instead of greying out when unavailable.
@export var hide_when_unavailable := false


## "" when the choice can be picked, else why not.
func unavailable_reason(ctx: ActionContext) -> String:
	var reason := Condition.first_reason(conditions, ctx)
	if reason != "":
		return reason
	return Cost.first_shortfall(costs, ctx)


func is_visible(ctx: ActionContext) -> bool:
	if Condition.any_hides(conditions, ctx):
		return false
	return not hide_when_unavailable or unavailable_reason(ctx) == ""


## Text with costs and check odds appended, e.g. "Pay up ($100)" / "[Intimidate] Open it. (65%)".
func make_label(ctx: ActionContext) -> String:
	var label := ctx.format(text)
	var cost_text := Cost.describe_all(costs, ctx)
	if cost_text != "":
		label += " (%s)" % cost_text
	if check != null:
		label += " (%d%%)" % roundi(check.chance(ctx) * 100.0)
	return label