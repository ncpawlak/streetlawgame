extends Node
## Run state: money, respect, gangs and crew. Territory ownership lives in [Turf], business
## ownership in [Businesses].

const PLAYER_GANG := &"player"
const NO_GANG := &"none"
## Render-layer bit for visuals that only the map cameras should see.
const MAP_LAYER := 2

const GANGS := {
	&"player": {"name": "Street Law", "color": Color(0.62, 0.2, 0.9)},
	&"vipers": {"name": "Red Vipers", "color": Color(0.85, 0.15, 0.15)},
	&"kings": {"name": "Eastside Kings", "color": Color(0.95, 0.8, 0.1)},
	&"syndicate": {"name": "Harbor Syndicate", "color": Color(0.15, 0.45, 0.95)},
}

@export var starting_cash := 500
@export var income_interval := 30.0

var cash := 0
var respect := 0
var crew: Array[CrewMemberData] = []
var player: Player
## Width of the generated city in meters (set by CityGenerator).
var city_extent := 0.0
## Unpaused seconds played; the clock for cooldowns and timed resets.
var play_time := 0.0
## Story/progress flags (see set_flag).
var flags: Dictionary = {}

var _income_timer: Timer


func _ready() -> void:
	cash = starting_cash
	_income_timer = Timer.new()
	_income_timer.wait_time = income_interval
	_income_timer.autostart = true
	_income_timer.timeout.connect(pay_income)
	add_child(_income_timer)


func _process(delta: float) -> void:
	play_time += delta


func gang_name(gang_id: StringName) -> String:
	return GANGS.get(gang_id, {}).get("name", "Unclaimed")


func gang_color(gang_id: StringName) -> Color:
	return GANGS.get(gang_id, {}).get("color", Color(0.5, 0.5, 0.5))


## The weapon definition for [param id] from ContentDB (data/weapons/<id>.tres, overridable by mods).
func weapon_data(id: StringName) -> WeaponData:
	return ContentDB.get_def(&"weapons", id) as WeaponData


## Story/progress flags set by content (SetFlagEffect, dialogue...). Plain data so it can be saved.
func get_flag(flag: StringName, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[flag] = value
	EventBus.flag_changed.emit(flag, value)


func has_flag(flag: StringName) -> bool:
	return flags.has(flag) and flags[flag] != false and flags[flag] != null


func add_cash(amount: int) -> void:
	cash = maxi(0, cash + amount)
	EventBus.cash_changed.emit(cash)


func spend_cash(amount: int) -> bool:
	if amount > cash:
		return false
	add_cash(-amount)
	return true


func add_respect(amount: int) -> void:
	respect += amount
	EventBus.respect_changed.emit(respect)


func pay_income() -> void:
	var total := Turf.income_for(PLAYER_GANG) + Businesses.total_income()
	if total > 0:
		add_cash(total)
		EventBus.notify.emit("Income: +$%d" % total)
