class_name StruggleMinigame
extends CarjackMinigame
## Prototype (c): pull an occupied car's driver out. Mash E/Space to drag the grip meter to the top
## while the driver fights back in surges. Let it hit zero, or run out of time, and the driver
## shoves you off and calls the cops.

@export var start_grip := 0.35
## Grip added per press.
@export var pull_strength := 0.06
## Grip the driver claws back per second at difficulty 1.0 (surges up to +60%).
@export var resist := 0.22
@export var time_limit := 8.0

var grip := 0.35

var _meter_rect: ColorRect
var _time_rect: ColorRect


func _init() -> void:
	kind = KIND_STRUGGLE


func _setup() -> void:
	grip = start_grip


## The driver's current pull (deterministic surges so it can be learned and tested).
func current_resist() -> float:
	return resist * difficulty * (1.0 + 0.6 * maxf(0.0, sin(elapsed * 2.5)))


func _tick(delta: float) -> void:
	grip -= current_resist() * delta
	if grip <= 0.0:
		grip = 0.0
		_fail("The driver shoved you off - he's calling the cops!")
	elif elapsed >= time_limit:
		_fail("Took too long - the driver floored it and is calling the cops!")


func _primary() -> void:
	grip = minf(1.0, grip + pull_strength)
	if grip >= 1.0:
		_succeed("You yanked the driver out!")


func _body_height() -> float:
	return 70.0


func _build_body(parent: Control) -> void:
	_rect(parent, Color(0.18, 0.18, 0.2), Vector2(10.0, 10.0), Vector2(500.0, 30.0))
	_meter_rect = _rect(parent, Color(0.9, 0.35, 0.2), Vector2(10.0, 10.0), Vector2(0.0, 30.0))
	_rect(parent, Color(0.18, 0.18, 0.2), Vector2(10.0, 52.0), Vector2(500.0, 8.0))
	_time_rect = _rect(parent, Color(0.95, 0.75, 0.2), Vector2(10.0, 52.0), Vector2(500.0, 8.0))


func _refresh() -> void:
	if _meter_rect == null:
		return
	_meter_rect.size.x = 500.0 * grip
	_meter_rect.color = Color(0.9, 0.35, 0.2).lerp(Color(0.3, 0.95, 0.4), grip)
	_time_rect.size.x = 500.0 * clampf(1.0 - elapsed / time_limit, 0.0, 1.0)
	if not done:
		_set_status("Grip %d%%" % int(grip * 100.0))
	_set_hint("Mash [E] / [Space] to drag the driver out   [Esc] back off")
