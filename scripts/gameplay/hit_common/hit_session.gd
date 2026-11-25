class_name HitSession
extends Node
## Glue for one hit's aftermath: owns a [PoliceCall], a [PoliceResponse] and a [HitHud], and binds the
## player's [CarryBag]. Drivers add one and call [method setup]; the hit-specific scene (house, shop)
## feeds the police call (neighbours, alarms, cameras) and places [LootItem]s and a [StashDropoff].

signal finished(cash: int)
signal failed(reason: StringName)

enum State { ACTIVE, WANTED, DONE, FAILED }

var police_call: PoliceCall
var police_response: PoliceResponse
var hud: HitHud
var bag: CarryBag
var state := State.ACTIVE


## [param cop_spawn_points] are global positions cops arrive at; [param listen_center] is where the
## neighbours hear gunshots from.
func setup(player: Node, cop_spawn_points: Array[Vector3], listen_center: Node3D = null, countdown := 45.0, with_hud := true) -> void:
	police_call = PoliceCall.new()
	police_call.name = "PoliceCall"
	police_call.countdown_seconds = countdown
	police_call.listen_center = listen_center
	add_child(police_call)
	police_response = PoliceResponse.new()
	police_response.name = "PoliceResponse"
	police_response.police_call = police_call
	police_response.spawn_points = cop_spawn_points
	add_child(police_response)
	bag = CarryBag.of(player)
	if with_hud:
		hud = HitHud.new()
		hud.name = "HitHud"
		add_child(hud)
		hud.bind(bag, police_call, police_response)
	police_response.cops_arrived.connect(func(_count: int) -> void: state = State.WANTED)
	police_response.escaped.connect(func() -> void: state = State.ACTIVE)
	police_response.busted.connect(func() -> void:
		state = State.FAILED
		failed.emit(&"busted"))


## Wires a stash so it is blocked while wanted and ends the session when the bag is cashed in.
func register_stash(stash: StashDropoff) -> void:
	stash.police_response = police_response
	stash.cashed_in.connect(func(amount: int, _actor: Node) -> void:
		state = State.DONE
		finished.emit(amount))


## Back to a clean slate (debug restarts).
func reset() -> void:
	police_response.stand_down()
	police_call.reset()
	state = State.ACTIVE
