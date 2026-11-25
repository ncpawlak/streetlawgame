class_name CashVanIntel
extends RefCounted
## What the crew knows about the cash van before the hit (HIT_LOOP "Approach: scout"). With intel you
## know the route, the schedule (where and when it leaves), the guards and the cargo. Without it the
## van leaves from somewhere on I-59 at some point, and the rest is a surprise.

## Seconds of unknown wait without intel.
const UNKNOWN_DELAY_RANGE := Vector2(8.0, 25.0)
## Metres ahead of the player's start a van with unknown timing can join the road.
const UNKNOWN_START_RANGE := Vector2(180.0, 520.0)

var known := true
## Metres along the route where the van joins the highway.
var start_distance := 0.0
## Seconds after the briefing until the van leaves.
var departure_delay := 0.0
var route_length := 0.0
var cruise_speed := 0.0
var guard_count := 0
var guard_loadout: PackedStringArray = []
var cargo: Array = []
var cargo_value := 0
var cargo_slots := 0


## [param known_start] and [param known_delay] are the scheduled values. Without intel they're
## replaced by random ones (from [param rng]) the player can't see.
static func gather(known_intel: bool, route: HighwayRoute, known_start: float, known_delay: float, player_start: float, rng: RandomNumberGenerator, speed := 17.0, guards := 3) -> CashVanIntel:
	var intel := CashVanIntel.new()
	intel.known = known_intel
	intel.route_length = route.length()
	intel.cruise_speed = speed
	if known_intel:
		intel.start_distance = known_start
		intel.departure_delay = known_delay
	else:
		intel.start_distance = fposmod(player_start + rng.randf_range(UNKNOWN_START_RANGE.x, UNKNOWN_START_RANGE.y), intel.route_length)
		intel.departure_delay = rng.randf_range(UNKNOWN_DELAY_RANGE.x, UNKNOWN_DELAY_RANGE.y)
	intel.guard_count = guards
	for i in intel.guard_count:
		intel.guard_loadout.append(_weapon_label(VanGuard.WEAPONS[i % VanGuard.WEAPONS.size()]))
	for entry in ArmoredVan.CARGO:
		intel.cargo.append(entry)
		intel.cargo_value += int(entry[1]) * int(entry[3])
		intel.cargo_slots += int(entry[2]) * int(entry[3])
	return intel


func lap_seconds() -> float:
	return route_length / maxf(cruise_speed, 0.1)


func route_line() -> String:
	if not known:
		return "Route: UNKNOWN - somewhere on I-59"
	return "Route: I-59 loop, %.1f km one way, right lane at ~%d km/h" % [route_length / 1000.0, roundi(cruise_speed * 3.6)]


func schedule_line() -> String:
	if not known:
		return "Schedule: UNKNOWN - could leave any time"
	return "Schedule: leaves the on-ramp in %ds, a lap every %ds" % [ceili(departure_delay), roundi(lap_seconds())]


func guards_line() -> String:
	if not known:
		return "Guards: UNKNOWN"
	return "Guards: %d - %s. Panic button: yes (cops in 20s)" % [guard_count, ", ".join(guard_loadout)]


func cargo_line() -> String:
	if not known:
		return "Cargo: UNKNOWN"
	var parts: PackedStringArray = []
	for entry in cargo:
		parts.append("%dx %s $%d (%d slot%s)" % [int(entry[3]), entry[0], int(entry[1]), int(entry[2]), "" if int(entry[2]) == 1 else "s"])
	return "Cargo: ~$%d in %d slots - %s" % [cargo_value, cargo_slots, ", ".join(parts)]


func lines() -> PackedStringArray:
	return PackedStringArray([route_line(), schedule_line(), guards_line(), cargo_line()])


static func _weapon_label(weapon_id: StringName) -> String:
	var data := GameState.weapon_data(weapon_id)
	return data.display_name if data != null and data.display_name != "" else String(weapon_id).capitalize()
