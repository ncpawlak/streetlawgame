class_name LocationDef
extends ContentDef
## A kind of place in the city: corner store, house, rival front, trap house, safehouse...
## Lives in data/locations/<id>.tres. Placed by LocationPlacer (or by the owning system via
## Locations.spawn) and turned into a Location node at runtime.

const TYPE := &"locations"

## &"business", &"home", &"front", &"trap_house" (#27), &"safehouse" (#24, placed by Turf)...
@export var kind: StringName = &"business"
@export_group("Visuals")
## Door/facade prop at the entrance. Null = greybox door.
@export var exterior: VisualSpec
## Color of the door greybox and the map marker.
@export var color := Color(0.75, 0.6, 0.3)
@export_group("Inside")
## How "inside" works. Null = not enterable (door-only; occupants are talked to through the door).
@export var interior: InteriorStrategy
## Actions offered at the door (outside).
@export var door_actions: Array[InteractionAction] = []
## Shared door actions by id (data/actions/<id>.tres).
@export var door_action_ids: Array[StringName] = []
## People inside: clerk, resident, guards...
@export var occupants: Array[OccupantDef] = []
## Shared occupants by id (data/occupants/<id>.tres).
@export var occupant_ids: Array[StringName] = []
## Applied once when the location is taken out (all hostiles dead, or a TakeOutEffect).
@export var cleared_effects: Array[Effect] = []
@export_group("Economy")
## Gang that runs it: a gang id, &"none", or &"district_owner" (resolved at spawn).
@export var default_owner: StringName = &"none"
## Cash in the register/safe when full.
@export var cash_capacity := 0
@export var cash_regen_per_minute := 0.0
@export_group("Placement")
## Placed automatically by LocationPlacer. Turn off for locations a system spawns itself.
@export var auto_place := true
## Exactly one instance, whose instance_id equals this def's id.
@export var unique := false
## The placer guarantees at least this many (if there are enough lots).
@export var min_count := 0
## Hard cap on instances (-1 = unlimited).
@export var max_count := -1
## Relative chance when filling free lots.
@export var spawn_weight := 1.0
@export var max_per_district := -1
## Only place in these district ids (snake_case, e.g. &"tamarack_row"). Empty = anywhere.
@export var district_ids: Array[StringName] = []
@export_group("")
## Free-form data for other systems (#27: production slots, #24: safehouse config...).
@export var extra: Dictionary = {}


func is_enterable() -> bool:
	return interior != null and interior.is_enterable()


func all_door_actions() -> Array[InteractionAction]:
	var result: Array[InteractionAction] = door_actions.duplicate()
	for action_id in door_action_ids:
		var action := ContentDB.find_def(InteractionAction.TYPE, action_id) as InteractionAction
		if action != null:
			result.append(action)
	return result


func all_occupants() -> Array[OccupantDef]:
	var result: Array[OccupantDef] = occupants.duplicate()
	for occupant_id in occupant_ids:
		var occupant := ContentDB.find_def(OccupantDef.TYPE, occupant_id) as OccupantDef
		if occupant != null:
			result.append(occupant)
	return result


## Resolves default_owner for a location in [param district_owner]'s district.
func resolve_owner(district_owner: StringName) -> StringName:
	if default_owner == &"district_owner":
		return district_owner if district_owner != &"" else GameState.NO_GANG
	return default_owner


func validate() -> PackedStringArray:
	var issues := super()
	if kind == &"":
		issues.append("location has no kind")
	if unique and min_count > 1:
		issues.append("unique location can't have min_count > 1")
	if max_count >= 0 and min_count > max_count:
		issues.append("min_count is larger than max_count")
	for action_id in door_action_ids:
		if not ContentDB.has_def(InteractionAction.TYPE, action_id):
			issues.append("unknown door action '%s'" % action_id)
	for occupant_id in occupant_ids:
		if not ContentDB.has_def(OccupantDef.TYPE, occupant_id):
			issues.append("unknown occupant '%s'" % occupant_id)
	if door_actions.has(null) or occupants.has(null) or cleared_effects.has(null):
		issues.append("location has an empty action/occupant/effect slot")
	return issues
