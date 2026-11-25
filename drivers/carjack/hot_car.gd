class_name HotCar
extends Vehicle
## A car you can jack. It starts locked: the normal "Steal vehicle" action is hidden and a "Jack"
## action asks the carjack driver to run a minigame instead. Occupied cars have someone behind the
## wheel who gets pulled out (and runs off) on success. A car can carry a [HotCarTracker].

signal jack_requested(car: HotCar, actor: Node)

## Set vehicle_class_id (see [VehicleClass]) for the name, chop value, lock difficulty and handling.
## car_name / car_value override the class when set.
@export var car_name := ""
## Chop shop price for an undamaged car (-1: the class's chop_value).
@export var car_value := -1
@export var occupied := false
## Fitted with a tracker (resolved by the driver's tracker setting when the car is jacked).
@export var has_tracker := false

var locked := true
var stolen := false
var alarm_on := false
var tracker: HotCarTracker

var _occupant: CharacterVisual
var _alarm_lights: Array[OmniLight3D] = []
var _alarm_left := 0.0


func _ready() -> void:
	var data := VehicleClass.find(vehicle_class_id) if vehicle_class_id != &"" else null
	if car_name == "":
		car_name = data.display_name if data != null else "Car"
	if car_value < 0:
		car_value = data.chop_value if data != null else 1500
	super._ready()
	add_to_group("hot_cars")
	if occupied:
		_occupant = CarCrew.seat_driver(self, &"civilian")
		_occupant.name = "Occupant"
		exploded.connect(_occupant.die)
	CarCrew.tint_glass(self)
	for x: float in [-0.8, 0.8]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.1)
		light.omni_range = 4.0
		light.visible = false
		light.position = Vector3(x, 1.0, 2.2)
		add_child(light)
		_alarm_lights.append(light)


func label() -> String:
	return car_name


## Multiplier on the jack minigame's difficulty (the class's lock_difficulty; 1.0 without a class).
func lock_difficulty() -> float:
	return vehicle_class.lock_difficulty if vehicle_class != null else 1.0


func class_label() -> String:
	return vehicle_class.display_name if vehicle_class != null else "Unclassed"


func _build_interactable() -> void:
	super._build_interactable()
	var interactable := get_node("Interactable") as Interactable
	interactable.prompt_name = car_name
	var jack_condition := MethodCondition.create(&"can_jack")
	jack_condition.hide_when_unmet = true
	var jack_effect := MethodEffect.create(&"request_jack")
	jack_effect.pass_actor = true
	var conditions: Array[Condition] = [jack_condition]
	var effects: Array[Effect] = [jack_effect]
	var action := InteractionAction.create(&"jack_car", "Pull the driver out" if occupied else "Break in", effects, conditions)
	action.priority = 10
	interactable.add_action(action)


func can_enter() -> bool:
	return super.can_enter() and not locked


func can_jack() -> bool:
	return locked and driver == null and not is_wrecked()


func request_jack(actor: Node) -> void:
	jack_requested.emit(self, actor)


## Opens the car after a successful minigame; the occupant (if any) bails out and runs.
func unlock() -> void:
	locked = false
	stolen = true
	set_alarm(false)
	if _occupant != null:
		var runner := FleeingDriver.spawn(get_parent(), global_position + global_basis.x * 2.0, global_basis.x, _occupant.variant)
		runner.name = "FleeingDriver"
		_occupant.queue_free()
		_occupant = null
		occupied = false


func has_occupant() -> bool:
	return _occupant != null


## Flashing indicators while the alarm is going off.
func set_alarm(on: bool, seconds := 12.0) -> void:
	alarm_on = on
	_alarm_left = seconds if on else 0.0
	for light in _alarm_lights:
		light.visible = on


func _process(delta: float) -> void:
	super._process(delta)
	if not alarm_on:
		return
	_alarm_left -= delta
	var blink := fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0
	for light in _alarm_lights:
		light.visible = blink
	if _alarm_left <= 0.0:
		set_alarm(false)


## Health as a 0..1 fraction (the chop shop pays less for a beaten-up car).
func condition() -> float:
	return clampf(health / max_health, 0.0, 1.0)
