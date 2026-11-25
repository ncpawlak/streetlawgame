class_name LotState
extends RefCounted
## Stub for what stands on a piece of land the player fights over. A rival trap can be taken (and
## kept as the player's trap) or destroyed, leaving an empty lot that can be built on later.
## Construction itself isn't in the game yet: starting a build just reserves the lot for it.

enum State { RIVAL_TRAP, PLAYER_TRAP, EMPTY, CONSTRUCTION }

## What could go on an empty lot. Placeholder costs until construction exists.
const BUILD_OPTIONS := {
	&"trap_house": {"name": "New trap house", "cost": 3000},
	&"stash_house": {"name": "Stash house", "cost": 2000},
	&"front_business": {"name": "Front business", "cost": 6000},
}

var lot_id: StringName
var state := State.RIVAL_TRAP
## Gang that owns what's on the lot.
var owner_gang: StringName = &""
## BUILD_OPTIONS key reserved while in CONSTRUCTION.
var project: StringName = &""


func _init(id: StringName = &"", gang: StringName = &"") -> void:
	lot_id = id
	owner_gang = gang


func state_name() -> String:
	return String(State.keys()[state]).capitalize()


func claim_trap(gang: StringName) -> void:
	state = State.PLAYER_TRAP
	owner_gang = gang
	project = &""


## Whatever stood here is gone; [param gang] now holds the bare land.
func demolish(gang: StringName) -> void:
	state = State.EMPTY
	owner_gang = gang
	project = &""


## "" when [param option] can be started (ignoring cash), otherwise why not.
func build_block_reason(option: StringName) -> String:
	if not BUILD_OPTIONS.has(option):
		return "Unknown build"
	if state != State.EMPTY:
		return "The lot isn't empty"
	return ""


## Pays with [param spend] (func(amount) -> bool) and reserves the lot for [param option].
func start_build(option: StringName, spend: Callable) -> String:
	var reason := build_block_reason(option)
	if reason != "":
		return reason
	var cost: int = BUILD_OPTIONS[option]["cost"]
	if not spend.call(cost):
		return "Not enough cash ($%d)" % cost
	state = State.CONSTRUCTION
	project = option
	return ""


func to_dict() -> Dictionary:
	return {"lot_id": String(lot_id), "state": State.keys()[state], "owner": String(owner_gang), "project": String(project)}


static func from_dict(data: Dictionary) -> LotState:
	var lot := LotState.new(StringName(data.get("lot_id", "")), StringName(data.get("owner", "")))
	lot.state = maxi(0, State.keys().find(data.get("state", "RIVAL_TRAP"))) as State
	lot.project = StringName(data.get("project", ""))
	return lot
