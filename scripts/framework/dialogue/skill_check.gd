class_name SkillCheck
extends Resource
## Strategy that resolves a risky dialogue choice. Subclasses override [method _chance]. The odds are
## shown to the player, so keep them deterministic for a given context; [method roll] adds the dice.

## Added to the computed chance (content tuning knob).
@export var bonus := 0.0
@export_range(0.0, 1.0) var min_chance := 0.05
@export_range(0.0, 1.0) var max_chance := 0.95


func chance(ctx: ActionContext) -> float:
	return clampf(_chance(ctx) + bonus, min_chance, max_chance)


func roll(ctx: ActionContext) -> bool:
	var odds := chance(ctx)
	ctx.vars["check_chance"] = odds
	var passed := ctx.rng.randf() < odds
	ctx.vars["check_passed"] = passed
	return passed


func _chance(_ctx: ActionContext) -> float:
	return 0.5


## The occupant's def (nerve/greed), or null.
static func occupant_def(ctx: ActionContext) -> OccupantDef:
	var occupant := ctx.occupant as Occupant
	return occupant.def if occupant != null else null


## The occupant's {"fear", "favor"} at its location, or zeros.
static func disposition(ctx: ActionContext) -> Dictionary:
	var occupant := ctx.occupant as Occupant
	if occupant == null or occupant.location == null:
		return {"fear": 0.0, "favor": 0.0}
	return occupant.location.state.disposition(occupant.role())