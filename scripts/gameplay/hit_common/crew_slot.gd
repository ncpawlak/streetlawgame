class_name CrewSlot
extends RefCounted
## One seat on a hit crew: a [enum Role] and the [CrewMember] filling it. See [HitCrew].
##
## - LOOKOUT: posted on the street. Stretches the police countdown ([constant LOOKOUT_TIME]),
##   reveals silent alarms and warns when the cops are coming.
## - DRIVER: waits in the getaway car at the getaway spot with the engine running. Losing the cops
##   in that car is [constant DRIVER_ESCAPE] times faster.
## - MUSCLE: follows the player and holds owners / hostages (anything in group "homeowners" or
##   "hostages" with a [code]hold(by)[/code] method) so they can't phone or fight.
## Every member takes [constant CUT] of the payout.

enum Role { LOOKOUT, DRIVER, MUSCLE }

const ROLE_NAMES := {
	Role.LOOKOUT: "Lookout",
	Role.DRIVER: "Driver",
	Role.MUSCLE: "Muscle",
}
## Share of the payout each member takes.
const CUT := 0.1
## Police countdown multiplier with a lookout posted.
const LOOKOUT_TIME := 1.35
## Escape-rate multiplier while the player is in the getaway car with a driver.
const DRIVER_ESCAPE := 1.5
## Muscle holds anyone within this many metres.
const HOLD_RANGE := 7.0

var role: Role
var member: CrewMember


static func create(slot_role: Role, slot_member: CrewMember = null) -> CrewSlot:
	var slot := CrewSlot.new()
	slot.role = slot_role
	slot.member = slot_member
	return slot


func role_name() -> String:
	return ROLE_NAMES.get(role, "Crew")


func is_filled() -> bool:
	return member != null and is_instance_valid(member) and member.is_alive()
