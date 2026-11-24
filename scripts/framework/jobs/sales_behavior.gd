class_name SalesBehavior
extends JobBehavior
## Sells stock from the site stash into a district (params.district_id), optionally a single item
## (params.item_id). Price comes from the pluggable PricingModel and the district's market.

@export var pricing: PricingModel
@export var units_per_minute := 6.0
## Extra sales rate per skill point above 1.
@export var skill_rate_bonus := 0.1
## Item categories this job will sell when params.item_id is empty.
@export var categories: Array[StringName] = [&"drug"]
@export var require_owned_district := true


func validate(ctx: JobContext) -> String:
	var district_id: StringName = ctx.param("district_id", &"")
	if district_id.is_empty():
		return "Pick a district to work"
	if require_owned_district and ctx.model.districts.owner_of(district_id) != OperationsModel.PLAYER_GANG:
		return "You don't control %s" % ctx.model.districts.display_name(district_id)
	return ""


func tick(ctx: JobContext, seconds: float) -> void:
	var assignment := ctx.assignment
	var rate := units_per_minute * (1.0 + (ctx.skill() - 1) * skill_rate_bonus)
	assignment.progress += seconds * rate / 60.0
	var units := floori(assignment.progress + EPSILON)
	if units <= 0:
		return
	var item_id := _pick_item(ctx)
	if item_id.is_empty():
		assignment.progress = minf(assignment.progress, 1.0)
		ctx.set_status(JobAssignment.Status.STARVED, "Nothing to sell")
		return
	assignment.progress = maxf(0.0, assignment.progress - units)
	var district_id: StringName = ctx.param("district_id", &"")
	var sold := mini(units, ctx.stash().count(item_id))
	var revenue := 0
	for i in sold:
		revenue += ctx.model.quote(district_id, item_id, ctx.skill(), pricing)
		ctx.model.record_sale(district_id, item_id, 1)
	ctx.take(item_id, sold)
	ctx.pay(revenue)
	var item := ctx.model.item(item_id)
	ctx.add_heat(item.heat_per_unit * sold if item != null else 0.0)
	ctx.complete_cycle()
	ctx.model.emit_event(&"sale_completed", {"district_id": district_id, "item_id": item_id, "units": sold, "revenue": revenue, "site_id": ctx.site.id})
	ctx.set_status(JobAssignment.Status.ACTIVE)


func describe(ctx: JobContext) -> String:
	return "Selling in %s" % ctx.model.districts.display_name(ctx.param("district_id", &""))


func param_options(model: OperationsModel, _site_id: StringName) -> Dictionary:
	var options: Array = []
	for district_id in model.districts.owned_districts(OperationsModel.PLAYER_GANG):
		options.append([district_id, model.districts.display_name(district_id)])
	return {"district_id": options}


func _pick_item(ctx: JobContext) -> StringName:
	var wanted: StringName = ctx.param("item_id", &"")
	if not wanted.is_empty():
		return wanted if ctx.stash().count(wanted) > 0 else &""
	for item_id in ctx.stash().item_ids():
		var item := ctx.model.item(item_id)
		if item != null and categories.has(item.category):
			return item_id
	return &""
