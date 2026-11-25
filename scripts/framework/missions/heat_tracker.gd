class_name HeatTracker
extends RefCounted
## Police heat for missions and safehouses. Main has no wanted system yet, so this keeps a simple
## level that rises on [signal EventBus.heat_raised], counts as "seen" for [member unseen_after]
## seconds after the last raise and then decays. A real wanted system plugs in by setting
## [member provider] (func() -> float) and optionally [member clear_handler] (func(amount: float)),
## after which every mission step and safehouse uses it unchanged.

signal changed(level: float)

const STAR_SIZE := 20.0
const MAX_LEVEL := 100.0

## Seconds without new heat before the player counts as unseen and heat starts to decay.
var unseen_after := 8.0
## Heat lost per second while unseen. 0 means heat only drops through clear()/reduce().
var decay_rate := 6.0
## Optional override: func() -> float returning the external wanted level.
var provider: Callable
## Optional override: func(amount: float) where amount < 0 means clear everything.
var clear_handler: Callable

var _level := 0.0
var _since_raise := INF


func level() -> float:
	if provider.is_valid():
		return float(provider.call())
	return _level


## 0-5 stars for the HUD.
func stars() -> int:
	return clampi(ceili(level() / STAR_SIZE), 0, 5)


func is_hot() -> bool:
	return level() > 0.0


## True while the police still have eyes on the player (recent heat).
func is_seen() -> bool:
	return is_hot() and _since_raise < unseen_after


func add(amount: float) -> void:
	if amount <= 0.0:
		return
	_since_raise = 0.0
	_set_level(minf(_level + amount, MAX_LEVEL))


func reduce(amount: float) -> void:
	if clear_handler.is_valid():
		clear_handler.call(amount)
		changed.emit(level())
		return
	_set_level(maxf(_level - amount, 0.0))


func clear() -> void:
	if clear_handler.is_valid():
		clear_handler.call(-1.0)
		changed.emit(level())
		return
	_since_raise = INF
	_set_level(0.0)


func tick(delta: float) -> void:
	_since_raise += delta
	if provider.is_valid() or _level <= 0.0 or decay_rate <= 0.0 or _since_raise < unseen_after:
		return
	_set_level(maxf(_level - decay_rate * delta, 0.0))


func to_dict() -> Dictionary:
	return {"level": _level}


func from_dict(data: Dictionary) -> void:
	_since_raise = INF
	_set_level(float(data.get("level", 0.0)))


func _set_level(value: float) -> void:
	if is_equal_approx(value, _level):
		_level = value
		return
	_level = value
	changed.emit(level())
