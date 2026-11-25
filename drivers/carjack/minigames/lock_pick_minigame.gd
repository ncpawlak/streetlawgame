class_name LockPickMinigame
extends CarjackMinigame
## Prototype (a): "bang bang bang" lock pick for parked cars. A needle bounces wall to wall; press
## E/Space while it is inside the green zone to set a pin. Pins must be set back to back: if the needle
## reaches the next wall without a pin set on that pass, or you press outside the zone, the streak
## resets to zero. Each pin speeds the needle up and shrinks the zone. Too many mis-presses snap the
## pick and set the car alarm off.

@export var pins_needed := 3
@export var max_misses := 3
## Sweeps per second (bar widths) at difficulty 1.0 for the first pin.
@export var base_speed := 0.7
## Zone width (fraction of the bar) at difficulty 1.0 for the first pin.
@export var base_zone := 0.24

const BAR_WIDTH := 500.0

var needle := 0.0
var direction := 1.0
var zone_center := 0.5
var zone_width := 0.24
var pins_set := 0
var misses := 0
## Pins dropped because the needle reached a wall (or a mis-press) before the next pin.
var resets := 0
## True once a pin has been set since the needle last touched a wall.
var hit_this_pass := false

var _rng := RandomNumberGenerator.new()
var _status_hold := 0.0
var _zone_rect: ColorRect
var _needle_rect: ColorRect
var _pins: Array[ColorRect] = []


func _init() -> void:
	kind = KIND_LOCK_PICK


func _setup() -> void:
	_rng.randomize()
	needle = 0.0
	direction = 1.0
	pins_set = 0
	misses = 0
	resets = 0
	hit_this_pass = false
	_new_zone()


func speed() -> float:
	return base_speed * difficulty * (1.0 + 0.3 * pins_set)


func in_zone() -> bool:
	return absf(needle - zone_center) <= zone_width * 0.5


func _tick(delta: float) -> void:
	needle += direction * speed() * delta
	var bounced := false
	if needle >= 1.0:
		needle = 2.0 - needle
		direction = -1.0
		bounced = true
	elif needle <= 0.0:
		needle = -needle
		direction = 1.0
		bounced = true
	needle = clampf(needle, 0.0, 1.0)
	if bounced:
		if pins_set > 0 and not hit_this_pass:
			_reset_streak("Hit the wall - the pins dropped. Start again.")
		hit_this_pass = false


func _primary() -> void:
	if in_zone():
		pins_set += 1
		hit_this_pass = true
		if pins_set >= pins_needed:
			_succeed("Click. The door's open.")
			return
		_new_zone()
	else:
		misses += 1
		if misses >= max_misses:
			_fail("The pick snapped - CAR ALARM!")
			return
		if pins_set > 0:
			_reset_streak("Slipped - the pins dropped. Start again.")


func _reset_streak(message: String) -> void:
	pins_set = 0
	resets += 1
	_new_zone()
	_set_status(message, Color(1.0, 0.55, 0.3))
	_status_hold = 0.8


func _new_zone() -> void:
	zone_width = clampf(base_zone / difficulty * (1.0 - 0.2 * pins_set), 0.05, 0.6)
	var half := zone_width * 0.5
	var center := _rng.randf_range(half, 1.0 - half)
	# Keep the new zone away from the needle so a pin can't be set by spamming.
	if absf(center - needle) < zone_width:
		center = clampf(1.0 - center, half, 1.0 - half)
	zone_center = center


func _body_height() -> float:
	return 90.0


func _build_body(parent: Control) -> void:
	_rect(parent, Color(0.18, 0.18, 0.2), Vector2(10.0, 10.0), Vector2(BAR_WIDTH, 34.0))
	_zone_rect = _rect(parent, Color(0.2, 0.8, 0.35, 0.85), Vector2(10.0, 10.0), Vector2(10.0, 34.0))
	_needle_rect = _rect(parent, Color(1.0, 0.95, 0.85), Vector2(10.0, 4.0), Vector2(5.0, 46.0))
	for i in pins_needed:
		_pins.append(_rect(parent, Color(0.3, 0.3, 0.32), Vector2(10.0 + i * 40.0, 62.0), Vector2(30.0, 20.0)))


func _refresh() -> void:
	if _zone_rect == null:
		return
	_zone_rect.position.x = 10.0 + (zone_center - zone_width * 0.5) * BAR_WIDTH
	_zone_rect.size.x = zone_width * BAR_WIDTH
	_needle_rect.position.x = 10.0 + needle * BAR_WIDTH - 2.5
	for i in _pins.size():
		_pins[i].color = Color(0.95, 0.8, 0.2) if i < pins_set else Color(0.3, 0.3, 0.32)
	_status_hold = maxf(0.0, _status_hold - get_process_delta_time())
	if not done and _status_hold <= 0.0:
		_set_status("Streak %d/%d   -   Misses %d/%d" % [pins_set, pins_needed, misses, max_misses])
	_set_hint("[E]/[Space] in the green - set a pin every pass, back to back, or they drop   [Esc] walk away")
