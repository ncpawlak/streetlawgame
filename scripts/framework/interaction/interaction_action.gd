class_name InteractionAction
extends ContentDef
## One thing an actor can do to an Interactable: rob, talk, buy, enter, claim...
## Availability = [member conditions] + [member costs]. Costs are paid and [member effects] applied
## when the action completes (after [member duration] seconds for channelled actions).
## Reusable actions live in data/actions/<id>.tres; one-off actions can be built in code.

## Prompt text, e.g. "Rob {target}". Supports {vars}; falls back to display_name.
@export var verb := ""
## Higher sorts first; the first available action is the default for a single E press.
@export var priority := 0
@export var conditions: Array[Condition] = []
@export var costs: Array[Cost] = []
@export var effects: Array[Effect] = []
@export_group("Channelling")
## Seconds the actor must hold still to complete the action (0 = instant).
@export var duration := 0.0
## Text shown on the progress bar; supports {vars}.
@export var progress_text := ""
## Cancel if the actor leaves the interactable's range.
@export var cancel_on_leave := true
## Cancel if the actor takes damage.
@export var cancel_on_damage := true
@export_group("Presentation")
## Hide the action entirely when unavailable (instead of showing it greyed out with the reason).
@export var hide_when_unavailable := false
## Only usable on foot.
@export var on_foot_only := true


static func create(action_id: StringName, label_text: String, action_effects: Array[Effect] = [], action_conditions: Array[Condition] = []) -> InteractionAction:
	var action := InteractionAction.new()
	action.id = action_id
	action.verb = label_text
	action.effects = action_effects
	action.conditions = action_conditions
	return action


func make_label(ctx: ActionContext) -> String:
	var text := verb if verb != "" else label()
	var label_text := ctx.format(text) if ctx != null else text
	var price := Cost.describe_all(costs, ctx)
	return label_text + (" (%s)" % price if price != "" else "")


func is_available(ctx: ActionContext) -> bool:
	return Condition.all_met(conditions, ctx) and Cost.all_payable(costs, ctx)


## Why the action can't run, or "" when it can.
func unavailable_reason(ctx: ActionContext) -> String:
	var reason := Condition.first_reason(conditions, ctx)
	return reason if reason != "" else Cost.first_shortfall(costs, ctx)


## Whether the action should be listed at all.
func is_visible(ctx: ActionContext) -> bool:
	if Condition.any_hides(conditions, ctx):
		return false
	return not (hide_when_unavailable and not is_available(ctx))


## Rechecks availability, pays costs, applies effects and records the use in ctx.memory.
func execute(ctx: ActionContext) -> bool:
	ctx.action = self
	if not is_available(ctx):
		return false
	if not Cost.pay_all(costs, ctx):
		return false
	var entry := ctx.action_memory(id)
	entry["last"] = GameState.play_time
	entry["count"] = int(entry.get("count", 0)) + 1
	Effect.apply_all(effects, ctx)
	return true


func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	if verb == "" and display_name == "":
		issues.append("action has no verb or display_name")
	for list: Array in [conditions, costs, effects]:
		if list.has(null):
			issues.append("action has an empty condition/cost/effect slot")
	return issues
