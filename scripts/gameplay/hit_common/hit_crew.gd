class_name HitCrew
extends Node3D
## The homies on a hit, one [CrewSlot] per [enum CrewSlot.Role]. [HitSession] owns one as
## [member HitSession.crew] and applies its bonuses (countdown, escape, payout cut).

signal warning(text: String)
signal changed

## Where the lookout stands (global).
var lookout_post := Vector3.ZERO
## The getaway car the driver waits in.
var getaway: Node3D
## Where the driver waits if there's no car (global).
var getaway_spot := Transform3D.IDENTITY

var slots: Dictionary = {}
var police_call: PoliceCall
var police_response: PoliceResponse


## Hooks the lookout's warnings up to a hit's police.
func bind(call: PoliceCall, response: PoliceResponse) -> void:
	police_call = call
	police_response = response
	call.countdown_started.connect(_on_countdown_started)
	call.police_called.connect(func(_why: StringName) -> void:
		if has_role(CrewSlot.Role.LOOKOUT):
			warn("Lookout: 'They called it in - cops on the way!'"))
	response.cops_arrived.connect(func(count: int) -> void:
		if has_role(CrewSlot.Role.LOOKOUT):
			warn("Lookout: '%d cops just rolled up!'" % count)
		if has_role(CrewSlot.Role.DRIVER):
			warn("Driver: 'Engine's running - get in!'"))


## Fills [param role] with a new member (or returns the existing one).
func assign(role: CrewSlot.Role) -> CrewMember:
	if has_role(role):
		return (slots[role] as CrewSlot).member
	var member := CrewMember.new()
	member.name = CrewSlot.ROLE_NAMES[role]
	member.crew_role = role
	member.crew = self
	add_child(member)
	slots[role] = CrewSlot.create(role, member)
	member.place()
	changed.emit()
	return member


func dismiss(role: CrewSlot.Role) -> void:
	var slot := slots.get(role) as CrewSlot
	if slot == null:
		return
	slots.erase(role)
	if slot.member != null and is_instance_valid(slot.member):
		slot.member.queue_free()
	changed.emit()


## Assigns or dismisses [param role]; returns true if it's now filled.
func toggle(role: CrewSlot.Role) -> bool:
	if has_role(role):
		dismiss(role)
		return false
	assign(role)
	return true


func has_role(role: CrewSlot.Role) -> bool:
	var slot := slots.get(role) as CrewSlot
	return slot != null and slot.is_filled()


func clear() -> void:
	for role in slots.keys():
		dismiss(role)


func members() -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for slot in slots.values():
		if (slot as CrewSlot).is_filled():
			out.append((slot as CrewSlot).member)
	return out


## Everyone back to their posts (start of a hit).
func place() -> void:
	for member in members():
		member.place()


## Multiplies the police countdown (a lookout buys time).
func countdown_multiplier() -> float:
	return CrewSlot.LOOKOUT_TIME if has_role(CrewSlot.Role.LOOKOUT) else 1.0


## Multiplies how fast the player loses the cops (the driver's in the getaway car).
func escape_rate() -> float:
	var player := GameState.player
	if has_role(CrewSlot.Role.DRIVER) and player != null and getaway != null and player.current_vehicle == getaway:
		return CrewSlot.DRIVER_ESCAPE
	return 1.0


## Share of the payout the crew takes.
func payout_cut() -> float:
	return CrewSlot.CUT * members().size()


func warn(text: String) -> void:
	EventBus.notify.emit(text)
	warning.emit(text)


func summary() -> String:
	var names: Array[String] = []
	for member in members():
		names.append(CrewSlot.ROLE_NAMES[member.crew_role])
	return "Crew: " + (", ".join(names) if not names.is_empty() else "none")


func _on_countdown_started(seconds: float, _why: StringName) -> void:
	if not has_role(CrewSlot.Role.LOOKOUT):
		return
	if police_call != null and police_call.hidden:
		police_call.reveal()
		warn("Lookout: 'Silent alarm! Cops in %d s'" % ceili(police_call.time_left))
	else:
		warn("Lookout: 'Someone's calling it in - %d s'" % ceili(seconds))
