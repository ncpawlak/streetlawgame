class_name TurfCaptureModel
extends RefCounted
## Rules of a block capture, with no scene dependencies so they can be unit tested.
## Flow: GUARDED (kill the guards) -> READY (step into the zone) -> CAPTURING (hold the zone while waves
## arrive; the bar only fills while you're inside on foot and drains when you leave) -> CAPTURED once the bar
## is full and every wave is dead. Dying while capturing -> FAILED.
## A captured block can be counter-attacked: UNDER_ATTACK until the attackers are dead (back to CAPTURED) or
## they've held the zone without you long enough to take it (LOST).
## The rival's strength on the block (see [TurfBlockLedger]) scales hold time, wave size and counter-attacks.

signal state_changed(state: State, previous: State)
## The driver must spawn the wave and report its size with [method add_enemies] before returning.
signal wave_started(index: int, plan: Dictionary)
## Same contract as [signal wave_started]: spawn the attackers and report them with [method add_enemies].
signal counter_attack_started(plan: Dictionary)

enum State { GUARDED, READY, CAPTURING, CAPTURED, FAILED, UNDER_ATTACK, LOST }

const DIFFICULTIES: Array[StringName] = [&"easy", &"normal", &"hard"]
## size: enemies per wave, health / damage: enemy stats, hold: time to fill the bar, crew: per raid car.
const DIFFICULTY_TUNING := {
	&"easy": {"size": 0.7, "health": 0.8, "damage": 0.7, "hold": 0.8, "crew": 2},
	&"normal": {"size": 1.0, "health": 1.0, "damage": 1.0, "hold": 1.0, "crew": 3},
	&"hard": {"size": 1.4, "health": 1.25, "damage": 1.35, "hold": 1.25, "crew": 4},
}
const MAX_APPROACHES := 4

var wave_count := 4
var difficulty: StringName = &"normal"
var guard_count := 4
## Seconds of holding per wave at normal difficulty.
var hold_per_wave := 15.0
## How fast the bar drains while you're outside, relative to how fast it fills.
var decay_ratio := 0.5
## Seconds counter-attackers need to hold your zone (with you out of it) to take the block back.
var takeover_time := 45.0
## Rival strength on this block, [constant TurfBlockLedger.MIN_STRENGTH]..[constant TurfBlockLedger.MAX_STRENGTH].
var strength := TurfBlockLedger.DEFAULT_STRENGTH

var state := State.GUARDED
var progress := 0.0
## Index of the latest wave that has spawned (-1 before the first).
var wave_index := -1
## Guards still alive (part of [member enemies_remaining]).
var guards_alive := 0
## Every hostile still in play: guards, wave members on foot, and crews still riding in raid cars.
var enemies_remaining := 0
## How close a counter-attack is to taking the block back (0..1).
var takeover := 0.0


func configure(waves: int, difficulty_id: StringName, guards: int, strength_value := TurfBlockLedger.DEFAULT_STRENGTH) -> void:
	wave_count = maxi(1, waves)
	strength = clampf(strength_value, TurfBlockLedger.MIN_STRENGTH, TurfBlockLedger.MAX_STRENGTH)
	difficulty = difficulty_id if DIFFICULTY_TUNING.has(difficulty_id) else &"normal"
	guard_count = maxi(0, guards)
	reset()


func reset() -> void:
	progress = 0.0
	takeover = 0.0
	wave_index = -1
	guards_alive = guard_count
	enemies_remaining = guard_count
	_set_state(State.GUARDED if guard_count > 0 else State.READY)


func tuning(key: String) -> Variant:
	return DIFFICULTY_TUNING[difficulty][key]


## Seconds of holding the zone needed to fill the bar.
func hold_time() -> float:
	return hold_per_wave * wave_count * float(tuning("hold")) * strength_hold_scale(strength)


## Hold-time multiplier for a rival this strong (1.0 at [constant TurfBlockLedger.DEFAULT_STRENGTH]).
static func strength_hold_scale(value: float) -> float:
	return 0.6 + 0.2 * value


## Wave-size multiplier for a rival this strong (1.0 at [constant TurfBlockLedger.DEFAULT_STRENGTH]).
static func strength_size_scale(value: float) -> float:
	return 0.7 + 0.15 * value


## Who wave [param index] sends: {on_foot, cars, crew_per_car, approaches, total}. Waves get bigger, bring
## more cars and come from more directions as they go.
func plan_wave(index: int) -> Dictionary:
	var crew: int = tuning("crew")
	var cars := (index + 1) / 2
	var total := maxi(roundi((4 + 3 * index) * float(tuning("size")) * strength_size_scale(strength)), cars * crew + 2)
	return {
		"on_foot": total - cars * crew,
		"cars": cars,
		"crew_per_car": crew,
		"approaches": mini(1 + index, MAX_APPROACHES),
		"total": total,
	}


## Who a counter-attack sends: the same shape as [method plan_wave]. A crew that takes over your zone, plus a
## carload of backup once the rival is strong.
func plan_counter_attack() -> Dictionary:
	var crew: int = tuning("crew")
	var cars := 1 if strength >= 3.0 else 0
	var total := maxi(roundi((3.0 + 1.5 * strength) * float(tuning("size"))), cars * crew + 2)
	return {"on_foot": total - cars * crew, "cars": cars, "crew_per_car": crew, "approaches": 1, "total": total}


## Progress at which wave [param index] arrives. Wave 0 comes as soon as you step in.
func wave_threshold(index: int) -> float:
	return float(index) / wave_count


func is_final_wave_spawned() -> bool:
	return wave_index >= wave_count - 1


func is_active() -> bool:
	return state == State.CAPTURING


## The block is yours (possibly with a counter-attack underway).
func is_held() -> bool:
	return state == State.CAPTURED or state == State.UNDER_ATTACK


## Rivals hit the captured block. Returns false if it isn't held quietly right now.
func start_counter_attack() -> bool:
	if state != State.CAPTURED:
		return false
	takeover = 0.0
	_set_state(State.UNDER_ATTACK)
	counter_attack_started.emit(plan_counter_attack())
	return true


func tick(delta: float, player_inside: bool) -> void:
	match state:
		State.GUARDED:
			if guards_alive <= 0:
				_set_state(State.READY)
		State.READY:
			if player_inside:
				_set_state(State.CAPTURING)
				_spawn_due_waves()
		State.CAPTURING:
			var rate := delta / hold_time()
			progress = clampf(progress + rate if player_inside else progress - rate * decay_ratio, 0.0, 1.0)
			_spawn_due_waves()
			if progress >= 1.0 and is_final_wave_spawned() and enemies_remaining <= 0:
				_set_state(State.CAPTURED)
		State.UNDER_ATTACK:
			if enemies_remaining <= 0:
				_set_state(State.CAPTURED)
				return
			var rate := delta / takeover_time
			takeover = clampf(takeover - rate * decay_ratio if player_inside else takeover + rate, 0.0, 1.0)
			if takeover >= 1.0:
				_set_state(State.LOST)


## Hostiles entered play (a group on foot or a loaded raid car).
func add_enemies(count: int) -> void:
	enemies_remaining += count


## Hostiles left play (killed, or died with their car before getting out).
func remove_enemies(count: int, were_guards := false) -> void:
	enemies_remaining = maxi(0, enemies_remaining - count)
	if were_guards:
		guards_alive = maxi(0, guards_alive - count)


func fail() -> void:
	if state == State.CAPTURING:
		_set_state(State.FAILED)


func status_text() -> String:
	match state:
		State.GUARDED:
			return "Red Vipers are guarding the corner - take out the guards (%d left)" % guards_alive
		State.READY:
			return "The corner's open - step into the zone to start the takeover"
		State.CAPTURING:
			if progress >= 1.0:
				return "Drop the last Vipers to lock it down!"
			return "Hold the zone!"
		State.CAPTURED:
			return "BLOCK CAPTURED"
		State.FAILED:
			return "WASTED - the Vipers kept their block"
		State.UNDER_ATTACK:
			return "COUNTER-ATTACK - get in the zone and drop them before they take it back!"
		State.LOST:
			return "The Vipers took the block back"
	return ""


func _spawn_due_waves() -> void:
	while wave_index + 1 < wave_count and progress >= wave_threshold(wave_index + 1):
		wave_index += 1
		wave_started.emit(wave_index, plan_wave(wave_index))


func _set_state(next: State) -> void:
	var previous := state
	state = next
	state_changed.emit(state, previous)
