class_name HitSession
extends Node
## Glue for one hit's aftermath: owns a [PoliceCall], a [PoliceResponse], a [HitHud] and a [HitCrew],
## and binds the player's [CarryBag] and [HitIdentity] to the game-wide [HeatMap]. Drivers add one
## and call [method setup]; the hit-specific scene (house, shop) feeds the police call (neighbours,
## alarms, cameras) and places [LootItem]s and a [StashDropoff].
##
## Heat lifecycle: [method begin_hit] when the hit really starts (break-in, gun drawn), then
## [method end_hit] runs on cash-in, bust or [method reset] and adds this hit's heat to the area.

signal finished(cash: int)
signal failed(reason: StringName)
signal hit_started
signal hit_ended

enum State { ACTIVE, WANTED, DONE, FAILED }

var police_call: PoliceCall
var police_response: PoliceResponse
var hud: HitHud
var bag: CarryBag
var identity: HitIdentity
var crew: HitCrew
var heat_map: HeatMap
## The [HeatMap] area this hit counts towards ([method HeatMap.area_key]).
var heat_area: StringName = &""
var state := State.ACTIVE
## Between [method begin_hit] and [method end_hit].
var in_progress := false

var _stashes: Array[StashDropoff] = []


## [param cop_spawn_points] are global positions cops arrive at; [param listen_center] is where the
## neighbours hear gunshots from (and, unless [member heat_area] is set, which heat area this is).
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
	identity = HitIdentity.of(player)
	crew = HitCrew.new()
	crew.name = "HitCrew"
	add_child(crew)
	crew.bind(police_call, police_response)
	var map := heat_map if heat_map != null else HeatMap.shared()
	if heat_area == &"" and listen_center != null and listen_center.is_inside_tree():
		heat_area = map.area_key(listen_center.global_position)
	set_heat_map(map)
	if with_hud:
		hud = HitHud.new()
		hud.name = "HitHud"
		add_child(hud)
		hud.bind(bag, police_call, police_response)
	police_call.police_called.connect(_on_police_called)
	police_response.cops_arrived.connect(func(_count: int) -> void: state = State.WANTED)
	police_response.escaped.connect(func() -> void: state = State.ACTIVE)
	police_response.busted.connect(func() -> void:
		state = State.FAILED
		end_hit()
		failed.emit(&"busted"))


func set_heat_map(map: HeatMap) -> void:
	heat_map = map
	if police_response != null:
		police_response.heat_map = map
		police_response.heat_area = heat_area
	for stash in _stashes:
		stash.heat_map = map
		stash.heat_area = heat_area


func set_heat_area(area: StringName) -> void:
	heat_area = area
	set_heat_map(heat_map)


## Wires a stash so it is blocked while wanted and ends the session when the bag is cashed in.
func register_stash(stash: StashDropoff) -> void:
	_stashes.append(stash)
	stash.police_response = police_response
	stash.heat_map = heat_map
	stash.heat_area = heat_area
	stash.cashed_in.connect(func(amount: int, _actor: Node) -> void:
		state = State.DONE
		end_hit()
		finished.emit(amount))


## The hit has started for real: identity tracking on, crew to their posts, countdown scaled by heat.
func begin_hit() -> void:
	if in_progress:
		return
	in_progress = true
	if identity != null:
		identity.begin_hit()
	crew.place()
	_apply_modifiers()
	hit_started.emit()


## Adds this hit's heat to the area ([constant HeatMap.HIT_HEAT], plus [constant HeatMap.CALLED_HEAT]
## if the police were called). Heat carries over to the next hit; [method reset] doesn't clear it.
func end_hit() -> void:
	if not in_progress:
		return
	in_progress = false
	if heat_map != null:
		heat_map.add_area_heat(heat_area, HeatMap.HIT_HEAT + (HeatMap.CALLED_HEAT if police_call.is_called() else 0.0))
	if identity != null:
		identity.end_hit()
	hit_ended.emit()


func _process(_delta: float) -> void:
	if police_call == null:
		return
	_apply_modifiers()


func _apply_modifiers() -> void:
	if not police_call.is_active():
		var scale := crew.countdown_multiplier()
		if heat_map != null:
			scale *= heat_map.countdown_multiplier(heat_area)
		police_call.countdown_scale = scale
	police_response.escape_rate = crew.escape_rate()
	var cut := crew.payout_cut()
	for stash in _stashes:
		stash.crew_cut = cut


func _on_police_called(why: StringName) -> void:
	if identity == null:
		return
	identity.note_vehicle()
	if why == PoliceCall.REASON_CAMERA or why == PoliceCall.REASON_WITNESS:
		identity.witness(heat_map, why)


## Back to a clean slate (debug restarts). Ends the current hit, so its heat carries over.
func reset() -> void:
	end_hit()
	police_response.stand_down()
	police_call.reset()
	police_call.countdown_scale = 1.0
	state = State.ACTIVE
