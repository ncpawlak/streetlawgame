class_name TurfControlCondition
extends Condition
## True when a gang (default: the player) controls a district in [Turf]. district_id empty = the
## business site's district (BusinessSiteDef.site_id_from), else ctx.vars.district_id.

@export var district_id: StringName
@export var gang_id: StringName = &"player"


func _evaluate(ctx: ActionContext) -> bool:
	var district := resolve_district(district_id, ctx)
	return district != &"" and Turf.owner_of(district) == gang_id


func _reason(ctx: ActionContext) -> String:
	return "You don't control %s" % Turf.display_name(resolve_district(district_id, ctx))


## [param explicit], else the business site's district, else ctx.vars.district_id.
static func resolve_district(explicit: StringName, ctx: ActionContext) -> StringName:
	if explicit != &"":
		return explicit
	var site := ContentDB.find_def(BusinessSiteDef.TYPE, BusinessSiteDef.site_id_from(ctx)) as BusinessSiteDef
	if site != null:
		return site.district_id
	return StringName(str(ctx.vars.get("district_id", ""))) if ctx != null else &""
