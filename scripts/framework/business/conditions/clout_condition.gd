class_name CloutCondition
extends Condition
## True when the player's clout in a district is at least [member min_clout]. district_id empty =
## the business site's district, else ctx.vars.district_id.

@export var district_id: StringName
@export_range(0, 100) var min_clout := 10


func _evaluate(ctx: ActionContext) -> bool:
	return Clout.clout_of(TurfControlCondition.resolve_district(district_id, ctx)) >= min_clout


func _reason(ctx: ActionContext) -> String:
	var district := TurfControlCondition.resolve_district(district_id, ctx)
	return "Need %d clout in %s (have %d)" % [min_clout, Turf.display_name(district), Clout.clout_of(district)]


func _describe() -> String:
	return "Clout >= %d" % min_clout
