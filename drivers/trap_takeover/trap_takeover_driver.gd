class_name TrapTakeoverDriver
extends Node3D
## Standalone gameplay driver: assault "The Spot", a Red Vipers trap house, clear every rival on
## every floor, then hold the basement stash room to claim it. Not wired into the city map.
##
## Entry: go in LOUD (kick in the locked front door: the whole house is alerted) or QUIET (back
## door, kitchen side door or climb through the back laundry window) and take rivals out one by one
## with silent takedowns. A rival who spots you raises the alarm after ALARM_DELAY unless dropped.
## Afterwards: KEEP the trap (upgrade it, build rooms, pick the product, put crew on it; registered
## as an Operations site) or DESTROY it for a one-time payout, leaving an empty lot to build on.
##
## Launch: godot --path . res://drivers/trap_takeover/trap_takeover_driver.tscn
##   -- --difficulty=easy|normal|hard --enemies=N --seed=N --claim-time=S --screenshots=DIR
## Keys: E interact (breach, window, takedown, keep/destroy menu), K keep, X destroy, T manage trap.
## Debug keys: F1 panel, F2 difficulty, F3/F4 enemies -/+, F5 re-roll, F6 restart, F7 kill all,
## F8 floor view, F9 god mode.

signal phase_changed(phase: Phase)
signal takeover_completed
signal alarm_raised_signal(reason: String)
signal outcome_chosen(outcome: Outcome)

enum Phase { ASSAULT, CLEARED, CLAIMING, COMPLETE }
enum Difficulty { EASY, NORMAL, HARD }
enum Entry { NONE, LOUD, QUIET }
enum Outcome { NONE, PENDING, KEPT, DESTROYED }

const DIFFICULTIES := {
	Difficulty.EASY: {"name": "Easy", "count": 8, "health": 0.8, "damage": 0.2, "reaction": 0.7, "weapons": [&"pistol", &"pistol", &"smg"], "reinforcements": 0},
	Difficulty.NORMAL: {"name": "Normal", "count": 12, "health": 1.0, "damage": 0.3, "reaction": 0.45, "weapons": [&"pistol", &"smg", &"shotgun"], "reinforcements": 2},
	Difficulty.HARD: {"name": "Hard", "count": 18, "health": 1.4, "damage": 0.4, "reaction": 0.3, "weapons": [&"smg", &"shotgun", &"rifle"], "reinforcements": 4},
}
const AREAS := ["Yard", "Ground", "Upper", "Basement"]
const ALERT_SHARE_RADIUS := 12.0
const GUNFIRE_HEARING_RADIUS := 22.0
const REWARD_CASH := 1000
const REWARD_RESPECT := 100
const CLAIM_FLAG := &"trap_takeover_the_spot"
## Seconds a rival who has spotted you needs to raise the alarm.
const ALARM_DELAY := 3.0
## Rival sight range while unaware (they're not looking for trouble); OVERWATCH gets the long one.
const UNAWARE_SIGHT := 11.0
const UNAWARE_SIGHT_OVERWATCH := 16.0
const TAKEDOWN_RADIUS := 1.4
const GHOST_BONUS_CASH := 500
const LOUD_RESPECT_BONUS := 50
const DESTROY_PAYOUT := 2500
const SITE_ID := &"the_spot"
const TRAP_FLAG := &"trap_the_spot"
const LOT_FLAG := &"lot_the_spot"
const BREACH_POINT := Vector3(1.3, 1.0, 7.8)
const WINDOW_OUTSIDE := Vector3(6.0, 0.1, -8.3)
const WINDOW_INSIDE := Vector3(6.0, 0.1, -5.8)
## Floor view cycle: -99 = off, then basement, ground, upper, roof.
const FLOOR_VIEWS := [-99, -1, 0, 1, 2]

@export var difficulty: Difficulty = Difficulty.NORMAL
## Rivals placed at the start (-1 = the difficulty's default).
@export var enemy_count := -1
## Placement seed (0 = random each run).
@export var rng_seed := 0
## Seconds the stash room must be held, uncontested.
@export var claim_time := 20.0
## Rivals that roll up from the street once the claim starts (-1 = the difficulty's default).
@export var reinforcement_count := -1
## Read the "--key=value" user args after "--" (tests turn this off).
@export var parse_cmdline := true

var builder: TrapHouseBuilder
var phase := Phase.ASSAULT
var claim_progress := 0.0
## The rivals placed at the start; all of them must die before the claim opens.
var enemies: Array[IndoorGangMember] = []
var reinforcements: Array[IndoorGangMember] = []
## Slot ids used by the current placement, in spawn order.
var placement: Array[StringName] = []
var current_seed := 0
var god_mode := false
var floor_view := -99
var entry := Entry.NONE
## How the player got in ("front door", "back window", ...).
var entry_route := ""
var alarm_raised := false
var alarm_reason := ""
var takedowns := 0
## Rival currently counting down to the alarm (null = nobody has eyes on you).
var spotter: IndoorGangMember
var spotted_time := 0.0
var last_reward_cash := 0
var last_reward_respect := 0
var outcome := Outcome.NONE
var customization: TrapCustomization
var lot: LotState
var manage_panel: TrapManagePanel

var _rivals: Node3D
var _claim_marker: Node3D
var _overlay: TakeoverOverlay
var _show_debug := true
var _reinforcements_sent := false
var _floor_camera: Camera3D
var _previous_camera: Camera3D
var _last_ammo := {}
var _screenshot_dir := ""
var _entry_points: Array[Interactable] = []
var _outcome_menu: Interactable
var _lot_visual: StaticBody3D
var _lot_sign: Node3D

@onready var player: Player = $Player


func _ready() -> void:
	if parse_cmdline:
		_parse_cmdline()
	_build_environment()
	builder = TrapHouseBuilder.new()
	builder.build(self)
	builder.bake()
	_rivals = Node3D.new()
	_rivals.name = "Rivals"
	add_child(_rivals)
	_build_claim_marker()
	_overlay = TakeoverOverlay.new()
	_overlay.name = "TakeoverOverlay"
	add_child(_overlay)
	_floor_camera = Camera3D.new()
	_floor_camera.name = "FloorViewCamera"
	_floor_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_floor_camera.size = 19.0
	_floor_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(_floor_camera)
	_spawn_loadout()
	_build_entry_points()
	manage_panel = TrapManagePanel.new()
	manage_panel.name = "TrapManagePanel"
	manage_panel.driver = self
	add_child(manage_panel)
	player.weapons.changed.connect(_on_player_weapons_changed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.gang_member_killed.connect(_on_member_killed)
	start(current_seed if current_seed != 0 else rng_seed)
	if _screenshot_dir.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		EventBus.notify.emit.call_deferred("The Vipers run a trap out of that house. Clear it out and claim it.")
	else:
		_take_screenshots.call_deferred()


## (Re)starts the takeover: player back on the street, fresh rivals placed with [param seed_value]
## (0 = random seed).
func start(seed_value := 0) -> void:
	current_seed = seed_value if seed_value != 0 else randi_range(1, 999999)
	for member: Variant in enemies + reinforcements:
		if is_instance_valid(member) and (member as Node).get_parent() == _rivals:
			_rivals.remove_child(member)
			member.queue_free()
	enemies.clear()
	reinforcements.clear()
	placement.clear()
	_reinforcements_sent = false
	claim_progress = 0.0
	_claim_marker.visible = false
	_overlay.show_banner("")
	_reset_outcome()
	entry = Entry.NONE
	entry_route = ""
	alarm_raised = false
	alarm_reason = ""
	takedowns = 0
	spotter = null
	spotted_time = 0.0
	last_reward_cash = 0
	last_reward_respect = 0
	builder.doors[0].reset(true)
	for door in builder.doors.slice(1):
		door.reset(false)
	for point in _entry_points:
		point.enabled = true
	if player.current_vehicle:
		player.current_vehicle.exit()
	player.spawn_point = TrapHouseBuilder.PLAYER_SPAWN
	player.respawn()
	player.rotation.y = 0.0
	_place_rivals()
	_set_phase(Phase.ASSAULT)


func config() -> Dictionary:
	return DIFFICULTIES[difficulty]


func target_enemy_count() -> int:
	return clampi(enemy_count if enemy_count >= 0 else config()["count"], 0, TrapHouseBuilder.SLOTS.size())


func alive_enemies() -> Array[IndoorGangMember]:
	return _living(enemies)


func alive_rivals() -> Array[IndoorGangMember]:
	var living := _living(enemies)
	living.append_array(_living(reinforcements))
	return living


func alive_by_area() -> Dictionary:
	var counts := {}
	for area in AREAS:
		counts[area] = 0
	for member in alive_rivals():
		counts[TrapHouseBuilder.area_of(member.global_position)] += 1
	return counts


func is_claimable() -> bool:
	return phase == Phase.CLEARED or phase == Phase.CLAIMING


func player_in_claim_zone() -> bool:
	if not player.is_on_foot() or player.health <= 0.0:
		return false
	var offset := player.global_position - TrapHouseBuilder.CLAIM_POINT
	return Vector2(offset.x, offset.z).length() <= TrapHouseBuilder.CLAIM_RADIUS and absf(offset.y) < 1.5


func is_contested() -> bool:
	for member in alive_rivals():
		if TrapHouseBuilder.is_inside(member.global_position):
			return true
	return false


func kill_all() -> void:
	for member in alive_rivals():
		member.take_damage(member.health + 1000.0, player)


func _physics_process(delta: float) -> void:
	if god_mode and player.health < player.max_health:
		player.heal(player.max_health)
	match phase:
		Phase.ASSAULT:
			_update_entry()
			_update_alarm(delta)
			if alive_enemies().is_empty():
				_set_phase(Phase.CLEARED)
		Phase.CLEARED, Phase.CLAIMING:
			_update_claim(delta)
	_update_overlay()


func _update_claim(delta: float) -> void:
	var inside := player_in_claim_zone()
	if inside and phase == Phase.CLEARED:
		_set_phase(Phase.CLAIMING)
		_send_reinforcements()
	if phase != Phase.CLAIMING:
		return
	if inside and not is_contested():
		claim_progress += delta / maxf(claim_time, 0.01)
	elif not inside:
		claim_progress -= delta / maxf(claim_time, 0.01) * 0.5
	claim_progress = clampf(claim_progress, 0.0, 1.0)
	if claim_progress >= 1.0:
		_complete()


func _complete() -> void:
	_set_phase(Phase.COMPLETE)
	_claim_marker.visible = false
	var scattered := 0
	for member in alive_rivals():
		member.queue_free()
		scattered += 1
	reinforcements.clear()
	last_reward_cash = REWARD_CASH + (GHOST_BONUS_CASH if not alarm_raised else 0)
	last_reward_respect = REWARD_RESPECT + (LOUD_RESPECT_BONUS if entry == Entry.LOUD else 0)
	GameState.add_cash(last_reward_cash)
	GameState.add_respect(last_reward_respect)
	GameState.set_flag(CLAIM_FLAG)
	lot.claim_trap(&"player")
	GameState.set_flag(LOT_FLAG, lot.to_dict())
	outcome = Outcome.PENDING
	_build_outcome_menu()
	EventBus.notify.emit("The Spot is yours. +$%d, +%d respect." % [last_reward_cash, last_reward_respect])
	var style := "Ghost - never raised the alarm (+$%d)" % GHOST_BONUS_CASH if not alarm_raised else (
		"Went in loud (+%d respect)" % LOUD_RESPECT_BONUS if entry == Entry.LOUD else "Alarm raised: %s" % alarm_reason)
	_overlay.show_banner("TRAP HOUSE CLAIMED\nIn via %s, %d silent takedown%s. %s\n+$%d   +%d respect%s\n\n[K] KEEP IT - run it as your trap\n[X] DESTROY IT - strip it for $%d\n\n[F6] restart   [F5] re-roll" % [
		entry_route if entry_route != "" else "unknown", takedowns, "" if takedowns == 1 else "s", style,
		last_reward_cash, last_reward_respect, "\n(%d stragglers scattered)" % scattered if scattered > 0 else "", DESTROY_PAYOUT])
	takeover_completed.emit()


func _set_phase(value: Phase) -> void:
	if phase == value and value != Phase.ASSAULT:
		return
	phase = value
	if value == Phase.CLEARED:
		_claim_marker.visible = true
		EventBus.notify.emit("House is clear. Get down to the stash room and hold it.")
	phase_changed.emit(value)


# --- Entry & alarm ------------------------------------------------------------------------------

## Loud entry: kicks the locked front door in. Everyone inside hears it.
func breach_front_door() -> void:
	if phase != Phase.ASSAULT or builder.doors.is_empty() or builder.doors[0].jammed:
		return
	builder.doors[0].kick_in()
	_set_entry(Entry.LOUD, "front door")
	sound_alarm("front door kicked in")


## Climbs through the back laundry window ([param inward] false climbs back out).
func climb_window(inward := true) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = WINDOW_INSIDE if inward else WINDOW_OUTSIDE
	player.rotation.y = 0.0 if inward else PI
	if inward:
		_set_entry(Entry.QUIET, "back window")


## Kills an unaware rival without a sound. Returns false if he's already onto you.
func silent_takedown(member: IndoorGangMember) -> bool:
	if not is_instance_valid(member) or not member.is_unaware():
		return false
	member.take_damage(member.health + 1000.0, null)
	takedowns += 1
	if spotter == member:
		spotter = null
		spotted_time = 0.0
	return true


## The whole house goes on alert: every living rival comes for the player.
func sound_alarm(reason: String) -> void:
	if alarm_raised:
		return
	alarm_raised = true
	alarm_reason = reason
	spotter = null
	for member in alive_rivals():
		if member.state == IndoorGangMember.State.IDLE:
			member.alert(player.global_position)
	if entry == Entry.NONE:
		_set_entry(Entry.LOUD, "the street")
	EventBus.notify.emit("ALARM! The Vipers know you're here (%s)." % reason)
	alarm_raised_signal.emit(reason)


func _set_entry(value: Entry, route: String) -> void:
	if entry != Entry.NONE:
		return
	entry = value
	entry_route = route
	if value == Entry.QUIET and not alarm_raised:
		EventBus.notify.emit("You're in quiet (%s). Take them out one by one before anyone raises the alarm." % route)


## First time the player is inside without breaching, classify how they got in.
func _update_entry() -> void:
	if entry != Entry.NONE or not TrapHouseBuilder.is_inside(player.global_position):
		return
	var at := player.global_position
	var route := "snuck in"
	if at.z < -5.0:
		route = "back door"
	elif at.x > 7.0:
		route = "side door"
	elif at.z > 5.0:
		route = "front door"
	_set_entry(Entry.QUIET, route)


## A rival who's onto the player raises the alarm after ALARM_DELAY unless he's dropped first.
func _update_alarm(delta: float) -> void:
	if alarm_raised:
		return
	if spotter != null and (not is_instance_valid(spotter) or not spotter.is_alive() or spotter.is_unaware()):
		spotter = null
	if spotter == null:
		spotted_time = 0.0
		for member in alive_rivals():
			if not member.is_unaware():
				spotter = member
				break
	if spotter == null:
		return
	spotted_time += delta
	if spotted_time >= ALARM_DELAY:
		sound_alarm("%s raised the alarm" % String(spotter.name).trim_prefix("Viper_"))


func _build_entry_points() -> void:
	var breach := _interactable("BreachFrontDoor", BREACH_POINT, 1.3, "Front door")
	breach.add_action(_action(&"breach", "Kick in the door (loud)", &"can_breach"))
	breach.action_performed.connect(func(_id: StringName, _actor: Node, _ctx: ActionContext) -> void: breach_front_door())
	var window_out := _interactable("WindowOutside", Vector3(6.0, 1.0, -7.9), 1.0, "Laundry window")
	window_out.add_action(_action(&"climb_in", "Climb in (quiet)"))
	window_out.action_performed.connect(func(_id: StringName, _actor: Node, _ctx: ActionContext) -> void: climb_window(true))
	var window_in := _interactable("WindowInside", Vector3(6.0, 1.0, -6.1), 1.0, "Laundry window")
	window_in.add_action(_action(&"climb_out", "Climb out"))
	window_in.action_performed.connect(func(_id: StringName, _actor: Node, _ctx: ActionContext) -> void: climb_window(false))
	_entry_points.assign([breach, window_out, window_in])


func can_breach() -> bool:
	return phase == Phase.ASSAULT and not builder.doors.is_empty() and not builder.doors[0].jammed


## A driver-owned Interactable (target = this driver, so method conditions call driver methods).
func _interactable(node_name: String, at: Vector3, radius: float, prompt: String, parent: Node = self) -> Interactable:
	var interactable := Interactable.new()
	interactable.name = node_name
	interactable.radius = radius
	interactable.prompt_name = prompt
	interactable.target = self
	parent.add_child(interactable)
	interactable.global_position = at
	return interactable


## An action that only shows while [param condition] (a method on the target) returns true.
func _action(id: StringName, verb: String, condition: StringName = &"") -> InteractionAction:
	var conditions: Array[Condition] = []
	if condition != &"":
		conditions.append(MethodCondition.create(condition))
	var action := InteractionAction.create(id, verb, [], conditions)
	action.hide_when_unavailable = true
	return action


# --- After the takeover: keep or destroy --------------------------------------------------------

func outcome_pending() -> bool:
	return outcome == Outcome.PENDING


func is_kept() -> bool:
	return outcome == Outcome.KEPT


func lot_is_empty() -> bool:
	return lot != null and lot.state == LotState.State.EMPTY


## Keeps the trap as the player's: a Lv 2 House with the Vipers' grow room, registered as an
## Operations site so crew can work it. Returns "" or why it can't.
func keep_trap() -> String:
	if outcome != Outcome.PENDING:
		return "Nothing to keep right now"
	customization = TrapCustomization.from_takeover()
	_register_site()
	outcome = Outcome.KEPT
	_save_trap()
	_build_outcome_menu()
	EventBus.notify.emit("The Spot is your trap now. [T] to manage it.")
	_overlay.show_banner("THE SPOT - YOUR TRAP\n%s\n\n[T] manage: upgrade, rooms, product, crew\n\n[F6] restart   [F5] re-roll" % _trap_summary())
	outcome_chosen.emit(outcome)
	return ""


## Strips the trap for a one-time payout and knocks it down, leaving an empty lot to build on.
func destroy_trap() -> String:
	if outcome != Outcome.PENDING:
		return "Nothing to destroy right now"
	GameState.add_cash(DESTROY_PAYOUT)
	manage_panel.close()
	if TrapHouseBuilder.is_inside(player.global_position) or player.global_position.y < -0.5:
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(0.0, 0.2, 10.0)
	_claim_marker.visible = false
	_lot_visual = builder.demolish()
	_build_lot_sign()
	for point in _entry_points:
		point.enabled = false
	lot.demolish(&"player")
	GameState.set_flag(LOT_FLAG, lot.to_dict())
	outcome = Outcome.DESTROYED
	_build_outcome_menu()
	EventBus.notify.emit("Stripped The Spot for $%d and tore it down. The Vipers lost their trap." % DESTROY_PAYOUT)
	_overlay.show_banner("THE SPOT IS GONE\nStripped for +$%d. The Vipers lost their trap.\nThe lot is empty - check the sign out front to build on it.\n\n[F6] restart   [F5] re-roll" % DESTROY_PAYOUT)
	outcome_chosen.emit(outcome)
	return ""


## Reserves the empty lot for [param option] (a LotState.BUILD_OPTIONS key). Returns "" or why not.
func start_lot_build(option: StringName) -> String:
	var reason := lot.start_build(option, GameState.spend_cash)
	if reason == "":
		GameState.set_flag(LOT_FLAG, lot.to_dict())
		EventBus.notify.emit("Lot reserved: %s. Construction isn't in yet." % LotState.BUILD_OPTIONS[option]["name"])
		_overlay.show_banner("")
	else:
		EventBus.notify.emit(reason)
	return reason


func upgrade_trap() -> String:
	return _customize(func() -> String: return customization.upgrade(GameState.spend_cash))


func buy_room(room_id: StringName) -> String:
	return _customize(func() -> String: return customization.buy_room(room_id, GameState.spend_cash))


func set_product(room_id: StringName) -> String:
	var reason := _customize(func() -> String: return customization.set_product(room_id))
	if reason == "" and customization.product_recipe() == &"":
		return "%s isn't in the game yet - cooks will idle." % customization.product_name()
	return reason


## Crew who could work the trap.
func crew_members() -> Array[CrewMemberData]:
	var model := _ops_model()
	if model == null:
		return []
	return model.all_crew()


func site_workers() -> int:
	var model := _ops_model()
	return model.assignments_at(SITE_ID).size() if model != null else 0


func crew_job_text(crew_id: StringName) -> String:
	var model := _ops_model()
	if model == null:
		return "free"
	var assignment := model.assignment_for_crew(crew_id)
	if assignment == null:
		return "free"
	var where := "here" if assignment.site_id == SITE_ID else String(assignment.site_id).capitalize()
	return "%s (%s)" % [String(assignment.job_id).capitalize(), where]


## Puts [param crew_id] on [param job_id] at The Spot (moving them off any other job).
func assign_crew(crew_id: StringName, job_id: StringName) -> String:
	var model := _ops_model()
	if model == null or outcome != Outcome.KEPT:
		return "You don't run The Spot"
	var params := {}
	match job_id:
		&"cook":
			if customization.product_recipe() == &"":
				return "Nothing to cook: %s isn't in the game yet" % customization.product_name()
			params = {"recipe_id": customization.product_recipe()}
		&"dealer":
			params = {"district_id": model.site(SITE_ID).district_id}
	var current := model.assignment_for_crew(crew_id)
	var previous := {}
	if current != null:
		previous = {"site": current.site_id, "job": current.job_id, "params": current.params}
		model.unassign(current.id)
	var reason := model.can_assign(crew_id, SITE_ID, job_id, params)
	if reason == "" and model.assign(crew_id, SITE_ID, job_id, params) != null:
		_apply_ops()
		return ""
	if not previous.is_empty():
		model.assign(crew_id, previous["site"], previous["job"], previous["params"])
	return reason if reason != "" else "Couldn't assign"


func unassign_crew(crew_id: StringName) -> String:
	var model := _ops_model()
	if model == null:
		return ""
	model.unassign_crew(crew_id)
	_apply_ops()
	return ""


func open_manage_panel(pause := true) -> void:
	if outcome == Outcome.KEPT:
		_overlay.show_banner("")
		manage_panel.open(pause)


func open_operations() -> void:
	var service := get_node_or_null(^"/root/Operations")
	if service != null:
		service.open_site_panel(SITE_ID)


func _customize(change: Callable) -> String:
	if customization == null or outcome != Outcome.KEPT:
		return "You don't run The Spot"
	var reason: String = change.call()
	if reason == "":
		var model := _ops_model()
		if model != null:
			customization.apply_to(model.site(SITE_ID))
		_save_trap()
	return reason


func _trap_summary() -> String:
	var rooms: Array[String] = []
	for room_id in customization.rooms:
		rooms.append(TrapCustomization.ROOMS[room_id]["name"])
	return "Lv %d %s   Rooms: %s   Product: %s" % [customization.level + 1, customization.level_info()["name"],
		", ".join(rooms) if not rooms.is_empty() else "none", customization.product_name()]


func _save_trap() -> void:
	GameState.set_flag(TRAP_FLAG, customization.to_dict())
	GameState.set_flag(LOT_FLAG, lot.to_dict())


func _ops_model() -> OperationsModel:
	var service := get_node_or_null(^"/root/Operations")
	return service.model if service != null else null


func _apply_ops() -> void:
	var service := get_node_or_null(^"/root/Operations")
	if service != null:
		service.apply_events()


func _register_site() -> void:
	var model := _ops_model()
	if model == null:
		return
	var site := model.site(SITE_ID)
	if site == null:
		site = SiteData.new()
		site.id = SITE_ID
		site.display_name = "The Spot"
		site.description = "Taken from the Red Vipers."
		site.kind = &"trap_house"
		site.district_id = &"the_bottoms"
		site.allowed_jobs.assign([&"cook", &"dealer", &"guard"])
		model.add_override(OperationsModel.TYPE_SITES, site)
		model.setup()
	customization.apply_to(site)
	if not model.site_state(SITE_ID).acquired:
		model.acquire_site(SITE_ID, true)
	_apply_ops()


## Undoes the last outcome so the takeover can be replayed: un-registers a kept trap and rebuilds
## a destroyed house.
func _reset_outcome() -> void:
	if manage_panel != null:
		manage_panel.close()
	if is_instance_valid(_outcome_menu):
		_outcome_menu.queue_free()
	_outcome_menu = null
	if outcome == Outcome.KEPT:
		var model := _ops_model()
		if model != null:
			for assignment in model.assignments_at(SITE_ID):
				model.unassign(assignment.id)
			model.site_state(SITE_ID).acquired = false
			_apply_ops()
		GameState.set_flag(TRAP_FLAG, false)
	if outcome == Outcome.DESTROYED:
		if is_instance_valid(_lot_sign):
			_lot_sign.queue_free()
		_lot_sign = null
		_lot_visual = null
		var old_region := builder.region
		remove_child(old_region)
		old_region.queue_free()
		builder = TrapHouseBuilder.new()
		builder.build(self)
		builder.bake()
		set_floor_view(-99)
	outcome = Outcome.NONE
	customization = null
	lot = LotState.new(SITE_ID, &"vipers")


## The keep/destroy/manage menu at the claim point.
func _build_outcome_menu() -> void:
	if is_instance_valid(_outcome_menu):
		_outcome_menu.queue_free()
	_outcome_menu = _interactable("OutcomeMenu", TrapHouseBuilder.CLAIM_POINT + Vector3(0.0, 1.0, 0.0), TrapHouseBuilder.CLAIM_RADIUS + 0.5, "The Spot")
	_outcome_menu.add_action(_action(&"keep", "Keep it - run it as your trap", &"outcome_pending"))
	_outcome_menu.add_action(_action(&"destroy", "Destroy it - strip it for $%d" % DESTROY_PAYOUT, &"outcome_pending"))
	_outcome_menu.add_action(_action(&"manage", "Manage The Spot", &"is_kept"))
	_outcome_menu.action_performed.connect(_on_outcome_action)


func _on_outcome_action(id: StringName, _actor: Node, _ctx: ActionContext) -> void:
	match id:
		&"keep":
			keep_trap()
		&"destroy":
			destroy_trap()
		&"manage":
			open_manage_panel()


## "For sale"-style sign on the empty lot; interact to pick what to build.
func _build_lot_sign() -> void:
	_lot_sign = Node3D.new()
	_lot_sign.name = "LotSign"
	add_child(_lot_sign)
	_lot_sign.position = Vector3(-3.0, 0.0, 8.6)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.36, 0.2)
	for x: float in [-0.7, 0.7]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.12, 1.8, 0.12)
		post_mesh.material = wood
		post.mesh = post_mesh
		post.position = Vector3(x, 0.9, 0.0)
		_lot_sign.add_child(post)
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(1.8, 0.9, 0.08)
	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = Color(0.92, 0.9, 0.82)
	board_mesh.material = board_material
	board.mesh = board_mesh
	board.position = Vector3(0.0, 1.45, 0.0)
	_lot_sign.add_child(board)
	var text := Label3D.new()
	text.text = "EMPTY LOT\nBuild something"
	text.font_size = 40
	text.modulate = Color(0.1, 0.1, 0.1)
	text.position = Vector3(0.0, 1.45, 0.05)
	_lot_sign.add_child(text)
	var menu := _interactable("BuildMenu", _lot_sign.position + Vector3(0.0, 1.0, 0.0), 1.8, "Empty lot", _lot_sign)
	for option: StringName in LotState.BUILD_OPTIONS:
		var info: Dictionary = LotState.BUILD_OPTIONS[option]
		menu.add_action(_action(option, "Build %s ($%d)" % [info["name"], info["cost"]], &"lot_is_empty"))
	menu.action_performed.connect(func(id: StringName, _actor: Node, _ctx: ActionContext) -> void: start_lot_build(id))


# --- Rivals -------------------------------------------------------------------------------------

func _place_rivals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = current_seed
	var count := target_enemy_count()
	var pool: Array = TrapHouseBuilder.SLOTS.duplicate()
	_shuffle(pool, rng)
	var chosen: Array = []
	if count >= 5 and difficulty != Difficulty.EASY:
		for slot: Dictionary in pool:
			if slot.get("boss", false):
				chosen.append(slot)
		pool = pool.filter(func(slot: Dictionary) -> bool: return not slot.get("boss", false))
	# Spread rivals over every area before doubling up.
	for area in AREAS:
		if chosen.size() >= count:
			break
		if chosen.any(func(slot: Dictionary) -> bool: return slot["area"] == area):
			continue
		for slot: Dictionary in pool:
			if slot["area"] == area:
				chosen.append(slot)
				pool.erase(slot)
				break
	while chosen.size() < count and not pool.is_empty():
		chosen.append(pool.pop_back())
	for slot: Dictionary in chosen:
		enemies.append(_spawn_rival(slot, rng))
		placement.append(slot["id"])


func _spawn_rival(slot: Dictionary, rng: RandomNumberGenerator) -> IndoorGangMember:
	var settings := config()
	var member := IndoorGangMember.new()
	member.gang_id = &"vipers"
	member.name = "Viper_%s" % slot["id"]
	member.post = IndoorGangMember.Post[String(slot["post"])]
	member.post_yaw = TrapHouseBuilder.slot_yaw(slot)
	var patrol: Array[Vector3] = []
	for point: Vector3 in slot.get("patrol", []):
		patrol.append(point + Vector3(0.0, 0.05, 0.0))
	member.patrol_points = patrol
	member.max_health = 60.0 * settings["health"]
	member.damage_scale = settings["damage"]
	member.reaction_time = settings["reaction"]
	var weapons: Array = settings["weapons"]
	member.weapon_id = weapons[rng.randi() % weapons.size()]
	if member.post == IndoorGangMember.Post.OVERWATCH and difficulty != Difficulty.EASY:
		member.weapon_id = &"rifle"
	if slot.get("boss", false):
		member.max_health *= 2.5
		member.weapon_id = &"shotgun"
		member.name = "Viper_boss"
	var jitter := Vector3(rng.randf_range(-0.25, 0.25), 0.05, rng.randf_range(-0.25, 0.25))
	member.position = slot["pos"] + jitter
	_rivals.add_child(member)
	member.unaware_sight_range = UNAWARE_SIGHT_OVERWATCH if member.post == IndoorGangMember.Post.OVERWATCH else UNAWARE_SIGHT
	member.alerted.connect(_on_member_alerted)
	var takedown := Interactable.new()
	takedown.name = "Takedown"
	takedown.radius = TAKEDOWN_RADIUS
	takedown.prompt_name = "Viper"
	takedown.focus_priority = 5
	takedown.position.y = 1.0
	var unaware: Array[Condition] = [MethodCondition.create(&"is_unaware")]
	var action := InteractionAction.create(&"takedown", "Take out quietly", [], unaware)
	action.hide_when_unavailable = true
	takedown.add_action(action)
	takedown.action_performed.connect(func(_id: StringName, _actor: Node, _ctx: ActionContext) -> void: silent_takedown(member))
	member.add_child(takedown)
	if _screenshot_dir != "":
		member.process_mode = Node.PROCESS_MODE_DISABLED
	return member


func _send_reinforcements() -> void:
	if _reinforcements_sent:
		return
	_reinforcements_sent = true
	var count: int = reinforcement_count if reinforcement_count >= 0 else config()["reinforcements"]
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = current_seed + 7
	for i in count:
		var spawn: Vector3 = TrapHouseBuilder.REINFORCEMENT_SPAWNS[i % TrapHouseBuilder.REINFORCEMENT_SPAWNS.size()]
		var member := _spawn_rival({"id": StringName("backup_%d" % i), "pos": spawn, "look": Vector3(0.5, 0.0, 0.0), "post": &"GUARD"}, rng)
		reinforcements.append(member)
		member.alert.call_deferred(player.global_position)
	EventBus.notify.emit("Viper backup rolling up from the street!")


func _on_member_alerted(member: IndoorGangMember) -> void:
	for other in alive_rivals():
		if other != member and other.state == IndoorGangMember.State.IDLE and other.global_position.distance_to(member.global_position) <= ALERT_SHARE_RADIUS:
			other.alert(member.last_known_position)


func _on_player_weapons_changed() -> void:
	var slot := player.weapons.current()
	if slot == null:
		return
	var key := player.weapons.current_index
	var fired: bool = _last_ammo.get(key, -1) > slot.magazine and slot.data.uses_ammo()
	_last_ammo.clear()
	_last_ammo[key] = slot.magazine
	if not fired:
		return
	for member in alive_rivals():
		if member.global_position.distance_to(player.global_position) <= GUNFIRE_HEARING_RADIUS:
			member.alert(player.global_position)


func _on_player_died() -> void:
	for member in alive_rivals():
		member.stand_down()


func _on_member_killed(member: GangMember, _killer: Node) -> void:
	if member in enemies and phase == Phase.ASSAULT:
		var left := alive_enemies().size()
		if left > 0 and left <= 3:
			EventBus.notify.emit("%d Viper%s left." % [left, "" if left == 1 else "s"])


static func _living(members: Array[IndoorGangMember]) -> Array[IndoorGangMember]:
	var living: Array[IndoorGangMember] = []
	for member in members:
		if is_instance_valid(member) and member.is_alive():
			living.append(member)
	return living


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap


# --- World --------------------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.42, 0.65)
	sky_material.sky_horizon_color = Color(0.85, 0.6, 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_density = 0.004
	environment.fog_light_color = Color(0.75, 0.62, 0.55)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _build_claim_marker() -> void:
	_claim_marker = Node3D.new()
	_claim_marker.name = "ClaimMarker"
	_claim_marker.position = TrapHouseBuilder.CLAIM_POINT
	add_child(_claim_marker)
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.3, 1.0, 0.4, 0.45)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = TrapHouseBuilder.CLAIM_RADIUS
	disc.bottom_radius = TrapHouseBuilder.CLAIM_RADIUS
	disc.height = 0.04
	disc.material = ring_material
	ring.mesh = disc
	ring.position.y = 0.03
	_claim_marker.add_child(ring)
	# Beacon drawn over everything so the claim spot can be found from the yard.
	var beacon_material := StandardMaterial3D.new()
	beacon_material.albedo_color = Color(0.3, 1.0, 0.4, 0.35)
	beacon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_material.no_depth_test = true
	var beacon := MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 0.15
	column.bottom_radius = 0.15
	column.height = 12.0
	column.material = beacon_material
	beacon.mesh = column
	beacon.position.y = 6.0
	_claim_marker.add_child(beacon)
	var label := Label3D.new()
	label.text = "CLAIM"
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.5, 1.0, 0.55)
	label.position.y = 2.2
	_claim_marker.add_child(label)


func _spawn_loadout() -> void:
	for id: StringName in [&"smg", &"shotgun", &"rifle", &"grenade", &"molotov"]:
		var weapon := GameState.weapon_data(id)
		if weapon != null and player.weapons.find(id) == null:
			player.weapons.add_weapon(weapon, weapon.magazine_size * (4 if weapon.thrown else 5))
	var stash := {&"rifle": Vector3(-3.0, 0.0, -3.0), &"shotgun": Vector3(-1.5, 0.0, -3.0), &"grenade": Vector3(1.5, 0.0, -3.0), &"molotov": Vector3(3.0, 0.0, -3.0)}
	for id: StringName in stash:
		var weapon := GameState.weapon_data(id)
		if weapon != null:
			add_child(WeaponPickup.create(weapon, weapon.magazine_size * (4 if weapon.thrown else 3), TrapHouseBuilder.PLAYER_SPAWN + stash[id]))
	var car := Vehicle.new()
	car.name = "GetawayCar"
	car.body_color = Color(0.45, 0.15, 0.6)
	car.position = Vector3(-7.0, 0.8, 24.0)
	car.rotation.y = PI / 2.0
	add_child(car)


# --- Debug --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _screenshot_dir.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			_show_debug = not _show_debug
		KEY_F2:
			difficulty = ((difficulty + 1) % Difficulty.size()) as Difficulty
			enemy_count = -1
			start(current_seed)
			EventBus.notify.emit("Difficulty: %s" % config()["name"])
		KEY_F3:
			enemy_count = maxi(0, target_enemy_count() - 1)
			start(current_seed)
		KEY_F4:
			enemy_count = mini(TrapHouseBuilder.SLOTS.size(), target_enemy_count() + 1)
			start(current_seed)
		KEY_F5:
			start(0)
			EventBus.notify.emit("Re-rolled placement (seed %d)." % current_seed)
		KEY_F6:
			start(current_seed)
		KEY_F7:
			kill_all()
		KEY_F8:
			set_floor_view(FLOOR_VIEWS[(FLOOR_VIEWS.find(floor_view) + 1) % FLOOR_VIEWS.size()])
		KEY_F9:
			god_mode = not god_mode
			EventBus.notify.emit("God mode %s" % ("ON" if god_mode else "OFF"))
		KEY_K:
			if outcome != Outcome.PENDING:
				return
			keep_trap()
		KEY_X:
			if outcome != Outcome.PENDING:
				return
			destroy_trap()
		KEY_T:
			if outcome != Outcome.KEPT:
				return
			open_manage_panel()
		_:
			return
	get_viewport().set_input_as_handled()


## Top-down cutaway of one level (-1 basement .. 2 roof); [code]-99[/code] goes back to the player camera.
func set_floor_view(level: int) -> void:
	floor_view = level
	var on := level != -99
	for index: int in builder.levels:
		(builder.levels[index] as Node3D).visible = not on or index <= level
	for label in builder.room_labels:
		label.visible = on and is_equal_approx(label.global_position.y - 0.05, TrapHouseBuilder.level_y(level))
	for member in alive_rivals():
		member.visible = not on or TrapHouseBuilder.level_of(member.global_position) <= level
	player.visible = not on or TrapHouseBuilder.level_of(player.global_position) <= level
	if on:
		if not _floor_camera.current:
			_previous_camera = get_viewport().get_camera_3d()
		_floor_camera.position = Vector3(0.0, TrapHouseBuilder.level_y(level) + 30.0, 0.5)
		_floor_camera.make_current()
	elif _floor_camera.current:
		if is_instance_valid(_previous_camera):
			_previous_camera.make_current()
		_floor_camera.current = false


func _update_overlay() -> void:
	match phase:
		Phase.ASSAULT:
			var counts := alive_by_area()
			_overlay.set_objective("TAKE THE SPOT - clear out the Red Vipers (%d left)\nYard %d   Ground %d   Upper %d   Basement %d\n%s" % [
				alive_enemies().size(), counts["Yard"], counts["Ground"], counts["Upper"], counts["Basement"], entry_status()])
		Phase.CLEARED:
			_overlay.set_objective("House is clear. Hold the stash room in the basement to claim it.")
		Phase.CLAIMING:
			_overlay.set_objective("Hold the stash room until the house is yours." if player_in_claim_zone() else "Get back in the stash room - the claim is slipping!")
		Phase.COMPLETE:
			match outcome:
				Outcome.PENDING:
					_overlay.set_objective("The Spot is yours. Keep it [K] or destroy it for $%d [X]." % DESTROY_PAYOUT)
				Outcome.KEPT:
					_overlay.set_objective("Your trap: %s   [T] manage" % _trap_summary())
				Outcome.DESTROYED:
					if lot.state == LotState.State.CONSTRUCTION:
						_overlay.set_objective("Lot reserved: %s (construction coming soon)." % LotState.BUILD_OPTIONS[lot.project]["name"])
					else:
						_overlay.set_objective("Empty lot. Check the sign out front to build on it.")
				_:
					_overlay.set_objective("The Spot is yours.")
	_overlay.set_progress(claim_progress, phase == Phase.CLAIMING, is_contested() and player_in_claim_zone())
	var counts := alive_by_area()
	_overlay.set_debug("TRAP TAKEOVER DRIVER\nPhase: %s   Outcome: %s\nDifficulty: %s\nEnemies: %d placed / %d alive\nSeed: %d\nPlayer: %s\nRivals by area: Y%d G%d U%d B%d\nEntry: %s (%s)  Alarm: %s\nTakedowns: %d\nGod mode: %s   View: %s\n\nE breach / window / takedown\nK keep  X destroy  T manage\nF1 panel  F2 difficulty\nF3/F4 enemies -/+  F5 re-roll\nF6 restart  F7 kill all\nF8 floor view  F9 god mode" % [
		Phase.keys()[phase], Outcome.keys()[outcome], config()["name"], enemies.size(), alive_enemies().size(), current_seed,
		TrapHouseBuilder.room_at(player.global_position), counts["Yard"], counts["Ground"], counts["Upper"], counts["Basement"],
		Entry.keys()[entry], entry_route if entry_route != "" else "-", "RAISED" if alarm_raised else "quiet", takedowns,
		"on" if god_mode else "off", "player" if floor_view == -99 else TrapHouseBuilder.LEVEL_NAMES[floor_view]], _show_debug)


## One-line entry/alarm status for the HUD.
func entry_status() -> String:
	if alarm_raised:
		return "ALARM RAISED - the whole house is on you"
	if spotter != null:
		return "SPOTTED - drop him before he raises the alarm (%.1fs)" % maxf(0.0, ALARM_DELAY - spotted_time)
	if entry == Entry.QUIET:
		return "Quiet so far (%s) - [E] behind an unaware Viper to take him out" % entry_route
	return "Loud: [E] kick in the front door.   Quiet: back door, side door or the back laundry window."
	_overlay.set_progress(claim_progress, phase == Phase.CLAIMING, is_contested() and player_in_claim_zone())
	var counts := alive_by_area()
	_overlay.set_debug("TRAP TAKEOVER DRIVER\nPhase: %s\nDifficulty: %s\nEnemies: %d placed / %d alive\nSeed: %d\nPlayer: %s\nRivals by area: Y%d G%d U%d B%d\nGod mode: %s   View: %s\n\nF1 panel  F2 difficulty\nF3/F4 enemies -/+  F5 re-roll\nF6 restart  F7 kill all\nF8 floor view  F9 god mode" % [
		Phase.keys()[phase], config()["name"], enemies.size(), alive_enemies().size(), current_seed,
		TrapHouseBuilder.room_at(player.global_position), counts["Yard"], counts["Ground"], counts["Upper"], counts["Basement"],
		"on" if god_mode else "off", "player" if floor_view == -99 else TrapHouseBuilder.LEVEL_NAMES[floor_view]], _show_debug)


func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"difficulty":
				match value.to_lower():
					"easy":
						difficulty = Difficulty.EASY
					"hard":
						difficulty = Difficulty.HARD
					_:
						difficulty = Difficulty.NORMAL
			"enemies":
				enemy_count = value.to_int()
			"seed":
				rng_seed = value.to_int()
			"claim-time":
				claim_time = value.to_float()
			"screenshots":
				_screenshot_dir = value


## Saves a cutaway of every floor plus an exterior shot to [member _screenshot_dir], then quits.
func _take_screenshots() -> void:
	DirAccess.make_dir_recursive_absolute(_screenshot_dir)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_show_debug = false
	_claim_marker.visible = true
	for i in 30:
		await get_tree().process_frame
	var shots := {-1: "1_basement", 0: "2_ground", 1: "3_upper", 2: "4_roof"}
	for level: int in shots:
		set_floor_view(level)
		for i in 8:
			await get_tree().process_frame
		_save_shot(shots[level])
	set_floor_view(-99)
	var exterior := Camera3D.new()
	add_child(exterior)
	exterior.look_at_from_position(Vector3(24.0, 16.0, 30.0), Vector3(0.0, 1.5, 0.0))
	exterior.make_current()
	for i in 8:
		await get_tree().process_frame
	_save_shot("0_exterior")
	exterior.look_at_from_position(Vector3(-20.0, 14.0, -26.0), Vector3(0.0, 1.5, 0.0))
	for i in 8:
		await get_tree().process_frame
	_save_shot("5_back_yard")
	# Outcomes: the manage panel for a kept trap, then the empty lot after destroying it.
	exterior.look_at_from_position(Vector3(14.0, 9.0, 20.0), Vector3(0.0, 1.0, 2.0))
	kill_all()
	_complete()
	keep_trap()
	GameState.add_cash(5000)
	buy_room(&"security")
	open_manage_panel(false)
	for i in 8:
		await get_tree().process_frame
	_save_shot("6_keep_manage_panel")
	manage_panel.close()
	start(current_seed)
	kill_all()
	_complete()
	destroy_trap()
	exterior.make_current()
	for i in 8:
		await get_tree().process_frame
	_save_shot("7_destroyed_lot")
	get_tree().quit()


func _save_shot(shot_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _screenshot_dir.path_join("trap_takeover_%s.png" % shot_name)
	image.save_png(path)
	print("Saved ", path)
