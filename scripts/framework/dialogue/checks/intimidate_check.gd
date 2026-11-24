class_name IntimidateCheck
extends SkillCheck
## Leaning on someone: needs a drawn weapon (0% otherwise); bigger guns, your own turf and their fear
## help, their nerve hurts.

@export var base := 0.3
@export var per_damage := 0.006
@export var own_turf_bonus := 0.15
@export var fear_weight := 0.3
@export var nerve_weight := 0.35
@export var drawn := WeaponDrawnCondition.new()


func _chance(ctx: ActionContext) -> float:
	if drawn != null and not drawn.is_met(ctx):
		return 0.0
	var odds := base
	var inventory := ctx.actor.get("weapons") as WeaponInventory if ctx.actor != null and "weapons" in ctx.actor else null
	if inventory != null and inventory.current() != null:
		odds += inventory.current().data.damage * per_damage
	var location := ctx.location as Location
	if location != null and location.state.owner_gang == GameState.PLAYER_GANG:
		odds += own_turf_bonus
	odds += float(disposition(ctx).get("fear", 0.0)) * fear_weight
	var def := occupant_def(ctx)
	if def != null:
		odds -= def.nerve * nerve_weight
	return odds


func chance(ctx: ActionContext) -> float:
	if drawn != null and not drawn.is_met(ctx):
		return 0.0
	return super(ctx)