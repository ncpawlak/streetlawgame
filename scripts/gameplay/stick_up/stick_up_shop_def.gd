class_name StickUpShopDef
extends Resource
## Tuning for one kind of shop in the stick-up driver (corner store, liquor store...).
## Name and colour come from the matching BusinessTypeDef when [member business_type_id] is set.

@export var id: StringName
@export var display_name := ""
## data/business_types/<id>.tres to borrow the display name and colour from.
@export var business_type_id: StringName
@export var sign_color := Color(0.3, 0.7, 0.4)
@export var interior_color := Color(0.85, 0.82, 0.75)
@export var register_cash_min := 150
@export var register_cash_max := 400
## Dollars a held-up clerk bags per second while you keep aim.
@export var bag_rate := 60.0
## Police countdown that starts when you draw your gun inside.
@export var alarm_seconds := 45.0
@export var customer_count := 2
## Weapon kept under the counter ("" = unarmed clerk).
@export var clerk_weapon_id: StringName = &""
## Seconds an armed clerk waits, unaimed at, before going for the gun.
@export var clerk_nerve := 4.0
## Seconds it takes to empty the register yourself once the clerk is dead.
@export var self_grab_time := 3.0
## Stocked stands: each {"name": String, "value": int (stash value per unit), "stock": int, "color": Color}.
@export var products: Array[Dictionary] = []


func label() -> String:
	if display_name != "":
		return display_name
	var business := ContentDB.get_def(&"business_types", business_type_id)
	return business.display_name if business != null else String(id)


func color() -> Color:
	var business := ContentDB.get_def(&"business_types", business_type_id)
	return business.get("color") if business != null else sign_color
