class_name OccupantDef
extends ContentDef
## Someone inside a location: clerk, resident, informant, guard, boss...
## Friendly occupants offer actions (and a Talk action when they have a dialogue);
## hostile ones spawn as gang members when the interior is entered and must be cleared to take it out.

const TYPE := &"occupants"

## &"clerk", &"resident", &"informant", &"bartender", &"guard", &"boss"...
@export var role: StringName = &"clerk"
## Spawns as a GangMember that fights the player.
@export var hostile := false
## Gang for hostile occupants: a gang id or &"location_owner".
@export var gang_id: StringName = &"location_owner"
## Weapon for hostile occupants (empty = the gang's usual arsenal).
@export var weapon_id: StringName = &""
@export var count := 1
@export var health := 60.0
## DialogueDef id; adds a Talk action.
@export var dialogue_id: StringName = &""
## Extra actions offered by this person.
@export var actions: Array[InteractionAction] = []
@export var action_ids: Array[StringName] = []
## Null = greybox capsule.
@export var visual: VisualSpec
@export var color := Color(0.8, 0.7, 0.55)
## 0-1: resists intimidation.
@export_range(0.0, 1.0) var nerve := 0.5
## 0-1: wants more money, harder to persuade.
@export_range(0.0, 1.0) var greed := 0.5


func all_actions() -> Array[InteractionAction]:
	var result: Array[InteractionAction] = actions.duplicate()
	for action_id in action_ids:
		var action := ContentDB.find_def(InteractionAction.TYPE, action_id) as InteractionAction
		if action != null:
			result.append(action)
	return result


func resolve_gang(location_owner: StringName) -> StringName:
	if gang_id != &"location_owner":
		return gang_id
	if location_owner == GameState.NO_GANG or location_owner == GameState.PLAYER_GANG or location_owner == &"":
		return &"vipers"
	return location_owner


func validate() -> PackedStringArray:
	var issues := super()
	if count < 1:
		issues.append("occupant count must be at least 1")
	for action_id in action_ids:
		if not ContentDB.has_def(InteractionAction.TYPE, action_id):
			issues.append("unknown action '%s'" % action_id)
	if dialogue_id != &"" and not ContentDB.has_def(&"dialogues", dialogue_id):
		issues.append("unknown dialogue '%s'" % dialogue_id)
	return issues
