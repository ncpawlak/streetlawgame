class_name LocationState
extends RefCounted
## Serializable runtime state of one location instance. Owned by the Locations autoload so it outlives
## the Location node and its streamed interior. Plain data only (save/load, #19).

var instance_id: StringName
var def_id: StringName
var district_id: StringName
## &"open", &"robbed", &"closed", &"taken_out", &"owned"...
var status: StringName = Location.OPEN
## GameState.play_time when [member status] resets to open (0 = never).
var status_until := 0.0
var owner_gang: StringName = GameState.NO_GANG
## Cash in the register/safe (fractional while it refills).
var cash := 0.0
## Interaction memory ({action_id: {"last", "count"}}), shared by the door and occupants.
var memory: Dictionary = {}
## Occupant role -> {"fear": float, "favor": float}.
var dispositions: Dictionary = {}
## Free-form per-location flags (hostiles_left, intel_given...).
var flags: Dictionary = {}


func disposition(role: StringName) -> Dictionary:
	if not dispositions.has(role):
		dispositions[role] = {"fear": 0.0, "favor": 0.0}
	return dispositions[role]


func to_dict() -> Dictionary:
	return {
		"instance_id": String(instance_id),
		"def_id": String(def_id),
		"district_id": String(district_id),
		"status": String(status),
		"status_until": status_until,
		"owner_gang": String(owner_gang),
		"cash": cash,
		"memory": memory.duplicate(true),
		"dispositions": dispositions.duplicate(true),
		"flags": flags.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	instance_id = StringName(d.get("instance_id", instance_id))
	def_id = StringName(d.get("def_id", def_id))
	district_id = StringName(d.get("district_id", district_id))
	status = StringName(d.get("status", status))
	status_until = float(d.get("status_until", status_until))
	owner_gang = StringName(d.get("owner_gang", owner_gang))
	cash = float(d.get("cash", cash))
	# Merge in place: the door Interactable holds a reference to these dictionaries.
	_replace(memory, d.get("memory", {}))
	_replace(dispositions, d.get("dispositions", {}))
	_replace(flags, d.get("flags", {}))


static func _replace(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	target.merge(source.duplicate(true))
