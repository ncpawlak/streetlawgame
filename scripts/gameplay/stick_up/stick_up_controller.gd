class_name StickUpController
extends Node
## Runs a shop stick-up: watches the player's gun and aim, and drives the shop's NPCs.
##
## - Drawing a gun inside the shop makes everyone in it wary and starts the police countdown.
## - Aiming (RMB) at the clerk holds them up: they empty the register into your [CarryBag] for as long
##   as you keep them covered. Aiming at anyone else makes them put their hands up.
## - Shooting anyone makes the people outside (bystanders, neighbouring shopkeepers) and fleeing
##   customers phone the cops; each finished call brings the police in immediately.
## - The clerk can be killed; then you empty the register yourself (hold E on it).
## - Some clerks have a hidden panic button: leave a held-up clerk uncovered too long and they press it.
##   It's a silent alarm - no warning, the visible countdown doesn't change - and the police turn up
##   early, after the shop's silent_alarm_seconds.
## Everything after that (cops, escape, stash) is hit_common's [HitSession].

signal gun_drawn
signal hold_up_started
signal take_added(amount: int)
signal register_emptied
## Someone was shot; [param npc] is the victim.
signal violence(npc: StickUpNpc)
signal witness_called(npc: StickUpNpc)
## The clerk pressed the hidden panic button. Silent: nothing is shown to the player.
signal panic_button_pressed
## The silent alarm went through and the police were dispatched.
signal silent_alarm_called

const UNARMED_IDS: Array[StringName] = [&"fists"]

## Max distance at which aiming at someone counts.
@export var aim_range := 14.0
## How close (m) the crosshair ray has to pass to someone's chest.
@export var aim_tolerance := 0.8
## Witnesses this far from a shooting hear it and call the cops.
@export var hearing_radius := 45.0
## Seconds a fleeing customer runs before getting their phone out.
@export var flee_call_delay := 3.0

var shop: StickUpShopDef
var player: Player
var clerk: StickUpNpc
## Clerk and customers.
var shop_npcs: Array[StickUpNpc] = []
## Bystanders and neighbouring shopkeepers who phone the cops when there's shooting.
var witnesses: Array[StickUpNpc] = []
## Interior of the shop (world space). Drawing a gun in here starts the stick-up.
var shop_bounds: AABB
var police_call: PoliceCall
var bag: CarryBag

var register_cash := 0
var taken := 0
var is_gun_drawn := false
var is_holding_up := false
var robbery_started := false
## NPC currently under the crosshair while aiming, if any.
var aimed_npc: StickUpNpc
## Seconds since the clerk was last covered (drives an armed clerk's nerve).
var uncovered_time := 0.0
## Rolled from the shop's panic_button_chance at setup.
var has_panic_button := false
var panic_tripped := false
## Seconds until a tripped silent alarm dispatches the police (-1 = not running).
var silent_alarm_left := -1.0

var _bag_progress := 0.0
var _was_held_up := false


func setup(shop_def: StickUpShopDef, the_player: Player, the_clerk: StickUpNpc, customers: Array[StickUpNpc], the_witnesses: Array[StickUpNpc], bounds: AABB, call: PoliceCall) -> void:
	shop = shop_def
	player = the_player
	clerk = the_clerk
	shop_bounds = bounds
	police_call = call
	bag = CarryBag.of(player)
	register_cash = randi_range(shop.register_cash_min, shop.register_cash_max)
	has_panic_button = randf() < shop.panic_button_chance
	shop_npcs = [clerk]
	shop_npcs.append_array(customers)
	witnesses = the_witnesses.duplicate()
	for npc in shop_npcs + witnesses:
		npc.threat = player
		npc.died.connect(_on_npc_shot)
		npc.hurt.connect(_on_npc_shot)
	for npc in shop_npcs + witnesses:
		npc.called_cops.connect(_on_called_cops)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	is_gun_drawn = _player_has_gun_out()
	if is_gun_drawn and not robbery_started and is_player_in_shop():
		_start_robbery()
	aimed_npc = _npc_under_crosshair() if is_gun_drawn and _is_aiming() else null
	if aimed_npc != null and aimed_npc != clerk and aimed_npc.state in [StickUpNpc.State.CALM, StickUpNpc.State.WARY]:
		aimed_npc.set_state(StickUpNpc.State.COWERING)
	if robbery_started:
		_update_clerk(delta)
	_update_silent_alarm(delta)


func is_player_in_shop() -> bool:
	return shop_bounds.has_point(player.global_position + Vector3(0.0, 0.5, 0.0))


func is_clerk_covered() -> bool:
	return aimed_npc != null and aimed_npc == clerk


func register_empty() -> bool:
	return register_cash <= 0


## Register interaction: once the clerk is dead (or has fled the counter), grab what's left yourself.
func can_grab_register(_actor: Node = null) -> bool:
	return register_cash > 0 and not clerk.is_alive()


func grab_register_reason(_actor: Node = null) -> String:
	if register_cash <= 0:
		return "Register's empty"
	return "Hold the clerk up (aim at them)"


func grab_register(actor: Node = null) -> int:
	if not can_grab_register(actor):
		return 0
	return _take(register_cash)


func _start_robbery() -> void:
	robbery_started = true
	for npc in shop_npcs:
		if npc.state == StickUpNpc.State.CALM:
			npc.set_state(StickUpNpc.State.WARY)
	# Before the countdown, so listeners (HitSession.begin_hit) can scale it by heat and crew.
	gun_drawn.emit()
	police_call.start_countdown(PoliceCall.REASON_ALARM, shop.alarm_seconds)
	EventBus.notify.emit("Gun's out. Cops are on the way - aim at the clerk to hold them up.")


func _update_clerk(delta: float) -> void:
	if not clerk.is_alive():
		is_holding_up = false
		return
	if is_clerk_covered() and clerk.state != StickUpNpc.State.HOSTILE:
		uncovered_time = 0.0
		if register_empty():
			clerk.set_state(StickUpNpc.State.COWERING)
			return
		if not is_holding_up:
			is_holding_up = true
			_was_held_up = true
			clerk.set_state(StickUpNpc.State.HELD_UP)
			for npc in shop_npcs:
				if npc != clerk and npc.state in [StickUpNpc.State.CALM, StickUpNpc.State.WARY]:
					npc.set_state(StickUpNpc.State.COWERING)
			EventBus.notify.emit("Empty the register! Keep them covered.")
			hold_up_started.emit()
		clerk.set_state(StickUpNpc.State.HELD_UP)
		_bag_progress += shop.bag_rate * delta
		var chunk := mini(int(_bag_progress), register_cash)
		if chunk > 0:
			_bag_progress -= chunk
			_take(chunk)
		return
	uncovered_time += delta
	if clerk.state == StickUpNpc.State.HELD_UP:
		clerk.set_state(StickUpNpc.State.WARY)
	if _was_held_up and has_panic_button and not panic_tripped and not clerk.is_held() and uncovered_time >= shop.panic_delay:
		press_panic_button()
	if clerk.weapons != null and uncovered_time > shop.clerk_nerve and clerk.state != StickUpNpc.State.HOSTILE and not clerk.is_held():
		clerk.set_state(StickUpNpc.State.HOSTILE)
		EventBus.notify.emit("The clerk's going for the shotgun!")


## The clerk trips the silent alarm: no notification, and the visible police countdown is left as it
## is; the police are dispatched after the shop's silent_alarm_seconds unless they're already coming.
func press_panic_button() -> void:
	if panic_tripped:
		return
	panic_tripped = true
	silent_alarm_left = shop.silent_alarm_seconds
	panic_button_pressed.emit()


## Seconds until the silent alarm brings the police, for a lookout to reveal (-1 = none running).
func silent_alarm_time_left() -> float:
	return silent_alarm_left


func _update_silent_alarm(delta: float) -> void:
	if silent_alarm_left < 0.0:
		return
	silent_alarm_left = maxf(0.0, silent_alarm_left - delta)
	if silent_alarm_left > 0.0:
		return
	silent_alarm_left = -1.0
	if not police_call.is_called():
		police_call.call_now(PoliceCall.REASON_SILENT_ALARM)
	silent_alarm_called.emit()


func _take(amount: int) -> int:
	amount = mini(amount, register_cash)
	if amount <= 0:
		return 0
	register_cash -= amount
	taken += amount
	bag.add_cash(amount)
	take_added.emit(amount)
	if register_cash <= 0:
		is_holding_up = false
		if clerk.is_alive() and clerk.state == StickUpNpc.State.HELD_UP:
			clerk.set_state(StickUpNpc.State.COWERING)
		EventBus.notify.emit("Register's empty ($%d). Get out and get it to the stash." % taken)
		register_emptied.emit()
	return amount


func _on_npc_shot(victim: StickUpNpc, _source: Node) -> void:
	violence.emit(victim)
	if victim == clerk and victim.is_alive() and clerk.weapons != null:
		clerk.set_state(StickUpNpc.State.HOSTILE)
	for npc in shop_npcs:
		if npc == clerk or not npc.is_alive():
			continue
		if npc.state != StickUpNpc.State.FLEEING and npc.state != StickUpNpc.State.CALLING:
			npc.set_state(StickUpNpc.State.FLEEING)
			_call_after(npc, flee_call_delay)
	for npc in witnesses:
		if npc.is_alive() and npc.state in [StickUpNpc.State.CALM, StickUpNpc.State.WARY] and npc.global_position.distance_to(victim.global_position) <= hearing_radius:
			npc.set_state(StickUpNpc.State.WARY)
			_call_after(npc, randf_range(0.3, 1.2))


func _call_after(npc: StickUpNpc, delay: float) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func() -> void:
		if is_instance_valid(npc) and npc.is_alive() and npc.state != StickUpNpc.State.CALLING:
			npc.set_state(StickUpNpc.State.CALLING))


func _on_called_cops(npc: StickUpNpc) -> void:
	EventBus.notify.emit("A %s called the cops!" % npc.label().to_lower())
	police_call.call_now(PoliceCall.REASON_WITNESS)
	witness_called.emit(npc)


func _player_has_gun_out() -> bool:
	if not player.is_on_foot() or player.weapons == null or player.weapons.current() == null:
		return false
	return not UNARMED_IDS.has(player.weapons.current().data.id)


func _is_aiming() -> bool:
	return Input.is_action_pressed("aim")


## The living NPC nearest the crosshair ray, within [member aim_range] and in line of sight.
func _npc_under_crosshair() -> StickUpNpc:
	var camera := player.get_node_or_null("CameraPivot/SpringArm/Camera") as Camera3D
	if camera == null:
		return null
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var best: StickUpNpc = null
	var best_miss := aim_tolerance
	for npc in shop_npcs + witnesses:
		if not is_instance_valid(npc) or not npc.is_alive():
			continue
		var chest := npc.global_position + Vector3(0.0, 1.2, 0.0)
		if player.global_position.distance_to(npc.global_position) > aim_range:
			continue
		var along := (chest - origin).dot(forward)
		if along <= 0.0:
			continue
		var miss := (origin + forward * along).distance_to(chest)
		if miss < best_miss and _has_line_of_sight(chest, npc):
			best = npc
			best_miss = miss
	return best


func _has_line_of_sight(to: Vector3, npc: StickUpNpc) -> bool:
	var from := player.global_position + Vector3(0.0, 1.4, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == npc
