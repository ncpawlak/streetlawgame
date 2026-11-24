class_name BusinessSiteDef
extends ContentDef
## One buyable business in the world: a [BusinessTypeDef] placed in a district. A type can have many
## sites (several gun stores across the city). Lives in data/business_sites/<id>.tres; the id is also
## the instance id of its Location.

const TYPE := &"business_sites"
## ActionContext.vars key holding the site id (falls back to ctx.location.instance_id).
const CONTEXT_KEY := &"business_site_id"

@export var type_id: StringName
## District the site sits in (data/districts/<id>.tres). Buying needs the player to control it.
@export var district_id: StringName
## Replaces the type's base_price for this site (-1 = use the type).
@export var price_override := -1
## Replaces the type's base_income for this site (-1 = use the type).
@export var income_override := -1
## Extra purchase gates on top of turf control, e.g. a CloutCondition.
@export var purchase_conditions: Array[Condition] = []


func type_def() -> BusinessTypeDef:
	return ContentDB.find_def(BusinessTypeDef.TYPE, type_id) as BusinessTypeDef


func label() -> String:
	if display_name != "":
		return display_name
	var business_type := type_def()
	return business_type.label() if business_type != null else super()


func base_price() -> int:
	var business_type := type_def()
	return price_override if price_override >= 0 else (business_type.base_price if business_type != null else 0)


func base_income() -> int:
	var business_type := type_def()
	return income_override if income_override >= 0 else (business_type.base_income if business_type != null else 0)


## The business site an action is about: ctx.vars[CONTEXT_KEY], else the Location's instance id.
static func site_id_from(ctx: ActionContext) -> StringName:
	if ctx == null:
		return &""
	if ctx.vars.has(CONTEXT_KEY):
		return StringName(str(ctx.vars[CONTEXT_KEY]))
	if ctx.location is Location:
		return (ctx.location as Location).instance_id
	return &""


func validate() -> PackedStringArray:
	var issues := super()
	if not ContentDB.has_def(BusinessTypeDef.TYPE, type_id):
		issues.append("unknown business type '%s'" % type_id)
	if not ContentDB.has_def(&"districts", district_id):
		issues.append("unknown district '%s'" % district_id)
	if purchase_conditions.has(null):
		issues.append("business site has an empty purchase condition slot")
	return issues
