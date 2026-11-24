class_name Cost
extends Resource
## Something an action consumes (cash, respect, items...). Checked before an action runs, paid when it
## completes. Template method: subclasses override [method _can_pay], [method _pay] and [method _describe].


func can_pay(ctx: ActionContext) -> bool:
	return _can_pay(ctx)


## Pays the cost. Returns false (and pays nothing) when it can't be paid.
func pay(ctx: ActionContext) -> bool:
	if not can_pay(ctx):
		return false
	_pay(ctx)
	return true


## Player-facing text, e.g. "$200".
func describe(ctx: ActionContext = null) -> String:
	return _describe(ctx)


## Shown when the cost can't be paid.
func shortfall(ctx: ActionContext = null) -> String:
	return "Need " + describe(ctx)


func _can_pay(_ctx: ActionContext) -> bool:
	return true


func _pay(_ctx: ActionContext) -> void:
	pass


func _describe(_ctx: ActionContext) -> String:
	return ""


static func all_payable(costs: Array, ctx: ActionContext) -> bool:
	for cost: Cost in costs:
		if cost != null and not cost.can_pay(ctx):
			return false
	return true


## Pays every cost, or none if any can't be paid.
static func pay_all(costs: Array, ctx: ActionContext) -> bool:
	if not all_payable(costs, ctx):
		return false
	for cost: Cost in costs:
		if cost != null:
			cost.pay(ctx)
	return true


static func first_shortfall(costs: Array, ctx: ActionContext) -> String:
	for cost: Cost in costs:
		if cost != null and not cost.can_pay(ctx):
			return cost.shortfall(ctx)
	return ""


static func describe_all(costs: Array, ctx: ActionContext = null) -> String:
	var parts := PackedStringArray()
	for cost: Cost in costs:
		if cost != null and cost.describe(ctx) != "":
			parts.append(cost.describe(ctx))
	return ", ".join(parts)
