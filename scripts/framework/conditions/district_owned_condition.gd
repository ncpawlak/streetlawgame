class_name DistrictOwnedCondition
extends Condition
## True when a gang (default: the player) owns a district. district_id empty = ctx.vars.district_id.

@export var district_id: StringName
@export var gang_id: StringName = &"player"


func _evaluate(ctx: ActionContext) -> bool:
	var model := OperationsModel.from_context(ctx)
	return model != null and model.districts.owner_of(_district(ctx)) == gang_id


func _reason(ctx: ActionContext) -> String:
	var model := OperationsModel.from_context(ctx)
	var district_name := model.districts.display_name(_district(ctx)) if model != null else String(_district(ctx))
	return "You don't control %s" % district_name


func _district(ctx: ActionContext) -> StringName:
	return district_id if not district_id.is_empty() else StringName(str(ctx.vars.get("district_id", "")))
