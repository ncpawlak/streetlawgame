class_name LockPickMinigame
extends CarjackMinigame
## Prototype (a): "bang bang bang" lock pick for parked cars. The pin, sweet spots, streak and resets
## come from the shared [TimingMinigame] in scripts/gameplay/hit_common (the same mechanic as house
## safes); this class only adds the carjack frame, the class difficulty and the snapped pick.
## A pin sweeps toward the far wall; press E/Space while it is in the green to set a pin, and the
## next green spot appears further along. Set [member pins_needed] back to back before the pin hits
## the wall. Hitting the wall or a mis-press resets the streak; [member max_misses] mis-presses snap
## the pick and set the car alarm off.

@export var pins_needed := 3
@export var max_misses := 3
## Bar widths per second at difficulty 1.0.
@export var base_speed := 0.5
## Sweet spot width (fraction of the bar) at difficulty 1.0.
@export var base_zone := 0.14

const BAR_WIDTH := 500.0
const MIN_ZONE := 0.05
const MAX_ZONE := 0.2

## The shared mechanic, run headless (no UI, no input, stepped from [method tick]).
var timing: TimingMinigame
var misses := 0
var resets := 0

var _status_hold := 0.0
var _zone_rect: ColorRect
var _needle_rect: ColorRect
var _pins: Array[ColorRect] = []


func _init() -> void:
	kind = KIND_LOCK_PICK
	timing = TimingMinigame.new()
	timing.title = "Pick the lock"
	timing.auto_step = false
	timing.show_ui = false
	timing.max_resets = 0
	timing.succeeded.connect(_on_timing_succeeded)
	timing.reset_happened.connect(_on_timing_reset)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(timing):
		timing.free()


func _setup() -> void:
	misses = 0
	resets = 0
	timing.hits_needed = pins_needed
	timing.speed = base_speed * difficulty
	timing.sweet_width = clampf(base_zone / difficulty, MIN_ZONE, MAX_ZONE)
	timing.start()


## Pins set so far in the current streak.
var pins_set: int:
	get:
		return timing.streak


## The pin's position across the bar, 0 (start) to 1 (far wall).
var needle: float:
	get:
		return timing.pin
	set(value):
		timing.pin = value


func in_zone() -> bool:
	return timing.in_sweet_spot()


func zone_center() -> float:
	return (timing.sweet_start + timing.sweet_end) * 0.5


func _tick(delta: float) -> void:
	timing.step(delta)


func _primary() -> void:
	timing.press()


func _on_timing_succeeded() -> void:
	_succeed("Click. The door's open.")


func _on_timing_reset(reason: StringName) -> void:
	resets += 1
	if reason == &"miss":
		misses += 1
		if misses >= max_misses:
			timing.cancel()
			_fail("The pick snapped - CAR ALARM!")
			return
		_hold_status("Slipped - the pins dropped. Start again.")
	else:
		_hold_status("Hit the wall - the pins dropped. Start again.")


func _hold_status(message: String) -> void:
	_set_status(message, Color(1.0, 0.55, 0.3))
	_status_hold = 0.8


func _body_height() -> float:
	return 90.0


func _build_body(parent: Control) -> void:
	_rect(parent, Color(0.18, 0.18, 0.2), Vector2(10.0, 10.0), Vector2(BAR_WIDTH, 34.0))
	_rect(parent, Color(0.6, 0.2, 0.2), Vector2(10.0 + BAR_WIDTH - 4.0, 6.0), Vector2(4.0, 42.0))
	_zone_rect = _rect(parent, Color(0.2, 0.8, 0.35, 0.85), Vector2(10.0, 10.0), Vector2(10.0, 34.0))
	_needle_rect = _rect(parent, Color(1.0, 0.95, 0.85), Vector2(10.0, 4.0), Vector2(5.0, 46.0))
	for i in pins_needed:
		_pins.append(_rect(parent, Color(0.3, 0.3, 0.32), Vector2(10.0 + i * 40.0, 62.0), Vector2(30.0, 20.0)))


func _refresh() -> void:
	if _zone_rect == null:
		return
	_zone_rect.position.x = 10.0 + timing.sweet_start * BAR_WIDTH
	_zone_rect.size.x = (timing.sweet_end - timing.sweet_start) * BAR_WIDTH
	_needle_rect.position.x = 10.0 + timing.pin * BAR_WIDTH - 2.5
	for i in _pins.size():
		_pins[i].color = Color(0.95, 0.8, 0.2) if i < pins_set else Color(0.3, 0.3, 0.32)
	_status_hold = maxf(0.0, _status_hold - get_process_delta_time())
	if not done and _status_hold <= 0.0:
		_set_status("Streak %d/%d   -   Misses %d/%d" % [pins_set, pins_needed, misses, max_misses])
	_set_hint("[E]/[Space] in the green - bang, bang, bang before the pin hits the wall   [Esc] walk away")