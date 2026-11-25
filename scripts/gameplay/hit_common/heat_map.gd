class_name HeatMap
extends Node
## Carry-over heat. Every hit warms up the area it happened in (a grid cell of [member cell_size] m,
## or any custom area id). Hot areas get a bigger police response ([method extra_cops]), a shorter
## call-in time ([method countdown_multiplier]) and lower fence payouts ([method payout_multiplier]).
## Heat cools off over time.
##
## Personal heat is the police knowing who you are: it comes from being seen unmasked (see
## [HitIdentity]). It adds cops to every hit, anywhere, and cools off faster when you're disguised.
##
## One shared instance lives under the scene root ([method shared]) so heat carries over between
## hits; tests can make their own with [code]HeatMap.new()[/code].

signal changed

const MAX_HEAT := 100.0
## Typical heat a hit adds to its area, and the extra when the police got called.
const HIT_HEAT := 20.0
const CALLED_HEAT := 15.0
## Personal heat from being seen unmasked (camera footage, a witness, a cop).
const FACE_HEAT := 25.0

static var _shared: HeatMap

@export var cell_size := 120.0
## Heat lost per second in every area.
@export var area_decay := 0.25
## Personal heat lost per second (before the [HitIdentity] disguise multiplier).
@export var personal_decay := 0.2

var areas: Dictionary = {}
var personal_heat := 0.0
## Multiplies personal heat decay, set each frame from the player's [HitIdentity].
var personal_decay_scale := 1.0


## The game-wide heat map (created under the scene root on first use).
static func shared() -> HeatMap:
	if _shared != null and is_instance_valid(_shared):
		return _shared
	_shared = HeatMap.new()
	_shared.name = "HeatMap"
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child.call_deferred(_shared)
	return _shared


func _process(delta: float) -> void:
	var identity := HitIdentity.of(GameState.player, false) if GameState.player != null else null
	personal_decay_scale = identity.decay_multiplier() if identity != null else 1.0
	decay(delta)


## The area id for a world position.
func area_key(at: Vector3) -> StringName:
	return StringName("%d_%d" % [floori(at.x / cell_size), floori(at.z / cell_size)])


func area_heat(area: StringName) -> float:
	return float(areas.get(area, 0.0))


func add_area_heat(area: StringName, amount: float) -> void:
	areas[area] = clampf(area_heat(area) + amount, 0.0, MAX_HEAT)
	if areas[area] <= 0.0:
		areas.erase(area)
	changed.emit()


func add_personal_heat(amount: float) -> void:
	personal_heat = clampf(personal_heat + amount, 0.0, MAX_HEAT)
	changed.emit()


## Cools everything off by [param delta] seconds.
func decay(delta: float) -> void:
	if areas.is_empty() and personal_heat <= 0.0:
		return
	for area: StringName in areas.keys():
		areas[area] = float(areas[area]) - area_decay * delta
		if areas[area] <= 0.0:
			areas.erase(area)
	personal_heat = maxf(0.0, personal_heat - personal_decay * personal_decay_scale * delta)
	changed.emit()


func clear() -> void:
	areas.clear()
	personal_heat = 0.0
	changed.emit()


## 0..1 for [param area] (area plus personal heat).
func level(area: StringName) -> float:
	return clampf((area_heat(area) + personal_heat * 0.5) / MAX_HEAT, 0.0, 1.0)


## Extra cops per wave: one per 25 area heat, one per 34 personal heat.
func extra_cops(area: StringName) -> int:
	return floori(area_heat(area) / 25.0) + floori(personal_heat / 34.0)


## Police countdowns in a hot area run shorter (down to 60%).
func countdown_multiplier(area: StringName) -> float:
	return 1.0 - 0.4 * clampf(area_heat(area) / MAX_HEAT, 0.0, 1.0)


## Fences pay less for goods from a hot area (down to 40%). Loose cash is unaffected.
func payout_multiplier(area: StringName) -> float:
	return 1.0 - 0.6 * clampf(area_heat(area) / MAX_HEAT, 0.0, 1.0)


## One-line HUD text.
func describe(area: StringName) -> String:
	return "Area heat %d  |  personal heat %d" % [roundi(area_heat(area)), roundi(personal_heat)]
