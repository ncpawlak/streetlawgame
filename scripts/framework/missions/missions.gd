class_name MissionService
extends Node
## Autoload "Missions": runs one [MissionRun] at a time and owns the mission-side state:
## [member heat] (HeatTracker), [member journal] (Leads), [member items] (key items), completed and
## unlocked missions, unlocked player safehouses and stored vehicles.
##
## Steps react to mission events: Dictionaries with a "type" key, built from EventBus signals here
## (interaction, dialogue_ended, flag, killed, purchase, heat, player_died, unlock, vehicle_entered,
## vehicle_exited) plus zone_entered/zone_exited from [TriggerZone], item from [member items],
## hook_done from finish_hook() and anything posted with post_event().
##
## Hooks are how missions call systems built elsewhere (cutscenes, phone calls, dialogue, follow /
## companions): request_hook(kind, id) asks the handler registered with register_hook(kind, ...) to
## run it, and that system calls finish_hook(kind, id, outcome) when done. Unhandled hooks finish on
## their own after [member hook_auto_complete_delay] so missions stay playable before the system exists.

signal mission_started(mission_id: StringName)
signal mission_completed(mission_id: StringName, run: MissionRun)
signal mission_failed(mission_id: StringName, reason: String, run: MissionRun)
## Any end: completed, failed or abandoned.
signal mission_ended(mission_id: StringName, run: MissionRun)
signal mission_retried(mission_id: StringName, checkpoint: Dictionary)
signal mission_unlocked(mission_id: StringName)
signal objective_changed
signal step_completed(mission_id: StringName, step_id: StringName)
signal mission_event(event: Dictionary)
## A step wants a cutscene / phone call / dialogue / follow run. See register_hook.
signal hook_requested(kind: StringName, hook_id: StringName, ctx: ActionContext)
signal hook_finished(kind: StringName, hook_id: StringName, outcome: StringName)
signal lead_changed(lead_id: StringName)
signal item_changed(item_id: StringName, count: int)
signal heat_changed(level: float)
signal safehouse_unlocked(safehouse_id: StringName)
signal vehicle_stored(safehouse_id: StringName, record: Dictionary)

const HOOK_DIALOGUE := &"dialogue"
const HOOK_CUTSCENE := &"cutscene"
const HOOK_PHONE_CALL := &"phone_call"
const HOOK_FOLLOW := &"follow"
const TAG_PREFIX := "mission:"
const SAVE_VERSION := 1

var heat := HeatTracker.new()
var journal := MissionJournal.new()
var items := MissionInventory.new()
var active: MissionRun
## The last finished run (for the result screen and retry).
var last_run: MissionRun
## mission_id -> times completed.
var completed: Dictionary = {}
var unlocked_missions: Dictionary = {}
var unlocked_safehouses: Dictionary = {}
## safehouse_id -> Array of vehicle records ({color, health, max_health}).
var stored_vehicles: Dictionary = {}
## Seconds before an unhandled hook finishes itself (0 = next frame).
var hook_auto_complete_delay := 1.5
## On death, respawn at the nearest unlocked safehouse in the scene.
var respawn_at_safehouses := true

var _hooks: Dictionary = {}
var _last_vehicle: Vehicle


func _ready() -> void:
	heat.changed.connect(func(level: float) -> void:
		heat_changed.emit(level)
		post_event(&"heat", {"level": level}))
	journal.lead_changed.connect(lead_changed.emit)
	items.changed.connect(func(item_id: StringName, count: int) -> void:
		item_changed.emit(item_id, count)
		post_event(&"item", {"item_id": item_id, "count": count}))
	EventBus.heat_raised.connect(func(amount: int, location: Node3D) -> void:
		heat.add(amount)
		post_event(&"heat_raised", {"amount": amount, "location": location}))
	EventBus.interaction_performed.connect(func(interactable: Interactable, action_id: StringName, actor: Node) -> void:
		post_event(&"interaction", {"interactable": interactable, "action_id": action_id, "actor": actor, "target": interactable.target if interactable != null else null}))
	EventBus.dialogue_ended.connect(func(dialogue_id: StringName, outcome: StringName) -> void:
		post_event(&"dialogue_ended", {"dialogue_id": dialogue_id, "outcome": outcome}))
	EventBus.flag_changed.connect(func(flag: StringName, value: Variant) -> void:
		post_event(&"flag", {"flag": flag, "value": value}))
	EventBus.gang_member_killed.connect(func(member: GangMember, killer: Node) -> void:
		report_kill(member, killer))
	EventBus.shop_purchase.connect(func(site_id: StringName, item_id: StringName, price: int) -> void:
		post_event(&"purchase", {"site_id": site_id, "item_id": item_id, "price": price}))
	EventBus.unlock_granted.connect(func(unlock_id: StringName) -> void:
		post_event(&"unlock", {"unlock_id": unlock_id}))
	EventBus.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	heat.tick(delta)


func _physics_process(delta: float) -> void:
	_poll_vehicle()
	if active != null:
		active.tick(delta)


# --- Missions -----------------------------------------------------------------------------------

func get_mission(mission_id: StringName) -> MissionDef:
	return ContentDB.find_def(MissionDef.TYPE, mission_id) as MissionDef


func is_active(mission_id: StringName = &"") -> bool:
	return active != null and (mission_id == &"" or active.def.id == mission_id)


func is_completed(mission_id: StringName) -> bool:
	return completed.get(mission_id, 0) > 0


func is_unlocked(mission_id: StringName) -> bool:
	var def := get_mission(mission_id)
	return def != null and (not def.requires_unlock or unlocked_missions.has(mission_id))


func unlock_mission(mission_id: StringName) -> void:
	if unlocked_missions.has(mission_id):
		return
	unlocked_missions[mission_id] = true
	mission_unlocked.emit(mission_id)


## "" when [param mission] can start now, otherwise why not.
func start_block_reason(mission: Variant) -> String:
	var def := _resolve(mission)
	if def == null:
		return "Unknown mission."
	if active != null:
		return "Finish %s first." % active.def.label()
	if def.requires_unlock and not unlocked_missions.has(def.id):
		return "Locked."
	if is_completed(def.id) and not def.repeatable:
		return "Already done."
	var ctx := ActionContext.new(GameState.player)
	if not Condition.all_met(def.start_conditions, ctx):
		return Condition.first_reason(def.start_conditions, ctx)
	return ""


func can_start(mission: Variant) -> bool:
	return start_block_reason(mission) == ""


## Starts a mission by id or [MissionDef]. False (with a notification) when it can't start.
func start_mission(mission: Variant, force := false) -> bool:
	var def := _resolve(mission)
	var reason := start_block_reason(def) if not force else ("" if def != null and active == null else "Can't start.")
	if reason != "":
		EventBus.notify.emit(reason)
		return false
	_begin_run(MissionRun.new(def), 0, {})
	mission_started.emit(def.id)
	EventBus.notify.emit("Mission started: %s" % def.label())
	return true


func abandon() -> void:
	if active != null:
		active.abandon()


## Restarts the last failed (or abandoned) mission from its last checkpoint.
func retry() -> bool:
	if active != null or last_run == null or last_run.state == MissionRun.State.COMPLETED:
		return false
	var previous := last_run
	var cp := previous.checkpoint
	var run := MissionRun.new(previous.def)
	run.attempt = previous.attempt + 1
	if cp.has("items"):
		items.from_dict({"items": cp["items"]})
	var player := GameState.player
	if player != null and cp.get("position") is Vector3:
		if player.current_vehicle != null:
			player.current_vehicle.exit()
		player.global_position = cp["position"]
		player.velocity = Vector3.ZERO
	mission_retried.emit(previous.def.id, cp)
	_begin_run(run, int(cp.get("index", 0)), cp.get("vars", {}))
	return true


func objective_lines() -> Array[Dictionary]:
	return active.objective_lines() if active != null else []


func current_waypoint() -> Variant:
	return active.waypoint_position() if active != null else null


func _resolve(mission: Variant) -> MissionDef:
	if mission is MissionDef:
		return mission
	if mission is String or mission is StringName:
		return get_mission(StringName(mission))
	return null


func _begin_run(run: MissionRun, start_index: int, vars: Dictionary) -> void:
	active = run
	run.objective_changed.connect(objective_changed.emit)
	run.finished.connect(_on_run_finished, CONNECT_ONE_SHOT)
	run.begin(start_index, vars)
	objective_changed.emit()


func _on_run_finished(run: MissionRun) -> void:
	if active == run:
		active = null
	last_run = run
	var mission_id := run.def.id
	if run.state == MissionRun.State.COMPLETED:
		_grant_rewards(run)
		mission_completed.emit(mission_id, run)
	else:
		mission_failed.emit(mission_id, run.fail_reason, run)
	mission_ended.emit(mission_id, run)
	objective_changed.emit()


func _grant_rewards(run: MissionRun) -> void:
	var def := run.def
	completed[def.id] = int(completed.get(def.id, 0)) + 1
	GameState.set_flag(StringName("mission:%s:done" % def.id), true)
	if def.cash_reward != 0:
		GameState.add_cash(def.cash_reward)
	if def.respect_reward != 0:
		GameState.add_respect(def.respect_reward)
	Effect.apply_all(def.rewards, run.ctx)
	for step in run.side:
		if step.is_done():
			Effect.apply_all(step.bonus_rewards, run.ctx)
	for safehouse_id in def.unlock_safehouses:
		unlock_safehouse(safehouse_id)
	for mission_id in def.unlock_missions:
		unlock_mission(mission_id)


# --- Events -------------------------------------------------------------------------------------

## Sends a mission event to the active run (and [signal mission_event] listeners).
func post_event(type: StringName, data: Dictionary = {}) -> void:
	var event := data.duplicate()
	event["type"] = type
	mission_event.emit(event)
	if active != null:
		active.handle(event)


## For deaths that don't go through EventBus.gang_member_killed (civilians, scripted targets...).
func report_kill(node: Node, killer: Node = null) -> void:
	post_event(&"killed", {"node": node, "killer": killer})


func _poll_vehicle() -> void:
	var player := GameState.player
	var vehicle: Vehicle = player.current_vehicle if player != null and is_instance_valid(player) else null
	if vehicle == _last_vehicle:
		return
	if _last_vehicle != null and is_instance_valid(_last_vehicle):
		post_event(&"vehicle_exited", {"vehicle": _last_vehicle})
	_last_vehicle = vehicle
	if vehicle != null:
		post_event(&"vehicle_entered", {"vehicle": vehicle})


func _on_player_died() -> void:
	post_event(&"player_died")
	if not respawn_at_safehouses:
		return
	var player := GameState.player
	var safehouse := nearest_safehouse(player.global_position if player != null else Vector3.ZERO)
	if player != null and safehouse != null:
		player.spawn_point = safehouse.respawn_position()


# --- Tags and locations -------------------------------------------------------------------------

## Marks [param node] as mission target [param tag_id] (KillStep, InteractStep, TalkStep...).
func tag(node: Node, tag_id: StringName) -> void:
	node.add_to_group(TAG_PREFIX + String(tag_id))


func untag(node: Node, tag_id: StringName) -> void:
	node.remove_from_group(TAG_PREFIX + String(tag_id))


func has_tag(node: Node, tag_id: StringName) -> bool:
	return node != null and is_instance_valid(node) and node.is_in_group(TAG_PREFIX + String(tag_id))


func tagged(tag_id: StringName) -> Array[Node]:
	if not is_inside_tree():
		return []
	return get_tree().get_nodes_in_group(TAG_PREFIX + String(tag_id))


func first_tagged(tag_id: StringName) -> Node:
	var nodes := tagged(tag_id)
	return nodes[0] if not nodes.is_empty() else null


func find_zone(zone_id: StringName) -> TriggerZone:
	if zone_id == &"" or not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(TriggerZone.GROUP):
		if (node as TriggerZone).zone_id == zone_id:
			return node
	return null


## World position of a zone id, mission tag, run var holding a Node3D, or safehouse id; else null.
func locate(target_id: StringName) -> Variant:
	var zone := find_zone(target_id)
	if zone != null:
		return zone.global_position
	var node := first_tagged(target_id)
	if node is Node3D:
		return (node as Node3D).global_position
	if active != null and active.ctx.vars.get(target_id) is Node3D:
		var held: Node3D = active.ctx.vars[target_id]
		if is_instance_valid(held):
			return held.global_position
	var safehouse := find_safehouse(target_id)
	if safehouse != null:
		return safehouse.door_position()
	return null


# --- Hooks --------------------------------------------------------------------------------------

## [param handler]: func(hook_id: StringName, ctx: ActionContext) -> bool. Return true when your
## system takes it, then call finish_hook(kind, hook_id, outcome) when it's done.
func register_hook(kind: StringName, handler: Callable) -> void:
	_hooks[kind] = handler


func unregister_hook(kind: StringName) -> void:
	_hooks.erase(kind)


func has_hook(kind: StringName) -> bool:
	return _hooks.has(kind) and (_hooks[kind] as Callable).is_valid()


func request_hook(kind: StringName, hook_id: StringName, ctx: ActionContext = null) -> void:
	if ctx == null:
		ctx = active.ctx if active != null else ActionContext.new(GameState.player)
	hook_requested.emit(kind, hook_id, ctx)
	if has_hook(kind) and bool((_hooks[kind] as Callable).call(hook_id, ctx)):
		return
	if kind == HOOK_DIALOGUE and _open_dialogue(hook_id, ctx):
		return
	_auto_finish(kind, hook_id)


func finish_hook(kind: StringName, hook_id: StringName, outcome: StringName = &"done") -> void:
	hook_finished.emit(kind, hook_id, outcome)
	post_event(&"hook_done", {"kind": kind, "hook_id": hook_id, "outcome": outcome})


## Falls back to the built-in DialogueView when the dialogue exists and a view is listening.
func _open_dialogue(dialogue_id: StringName, ctx: ActionContext) -> bool:
	var def := ContentDB.find_def(DialogueDef.TYPE, dialogue_id) as DialogueDef
	if def == null or EventBus.dialogue_requested.get_connections().is_empty():
		return false
	EventBus.dialogue_requested.emit(def, ctx)
	return true


func _auto_finish(kind: StringName, hook_id: StringName) -> void:
	if kind == HOOK_CUTSCENE or kind == HOOK_PHONE_CALL:
		EventBus.notify.emit("[%s: %s]" % [String(kind).replace("_", " "), hook_id])
	if hook_auto_complete_delay <= 0.0 or not is_inside_tree():
		finish_hook.call_deferred(kind, hook_id, &"auto")
		return
	get_tree().create_timer(hook_auto_complete_delay, false).timeout.connect(finish_hook.bind(kind, hook_id, &"auto"))


# --- Leads and items (thin wrappers so content can call them by name) ---------------------------

func add_lead(lead_id: StringName, title: String, note := "", marker: Variant = null, marker_unlocked := true, mission_id: StringName = &"") -> Dictionary:
	return journal.add_lead(lead_id, title, note, marker, marker_unlocked, mission_id)


func give_item(item_id: StringName, count := 1) -> void:
	items.add(item_id, count)
	if count > 0:
		EventBus.notify.emit("Picked up: %s" % String(item_id).capitalize())


# --- Safehouses ---------------------------------------------------------------------------------

func is_safehouse_unlocked(safehouse_id: StringName) -> bool:
	if unlocked_safehouses.has(safehouse_id):
		return true
	var def := ContentDB.find_def(PlayerSafehouseDef.TYPE, safehouse_id) as PlayerSafehouseDef
	return def != null and def.starts_unlocked


func unlock_safehouse(safehouse_id: StringName, announce := true) -> void:
	if unlocked_safehouses.has(safehouse_id):
		return
	unlocked_safehouses[safehouse_id] = true
	if announce:
		var def := ContentDB.find_def(PlayerSafehouseDef.TYPE, safehouse_id)
		EventBus.notify.emit("Safehouse unlocked: %s" % (def.label() if def != null else String(safehouse_id).capitalize()))
	safehouse_unlocked.emit(safehouse_id)


func safehouses() -> Array[PlayerSafehouse]:
	var out: Array[PlayerSafehouse] = []
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(PlayerSafehouse.GROUP):
			out.append(node as PlayerSafehouse)
	return out


func find_safehouse(safehouse_id: StringName) -> PlayerSafehouse:
	if safehouse_id == &"":
		return null
	for safehouse in safehouses():
		if safehouse.safehouse_id == safehouse_id:
			return safehouse
	return null


## The nearest unlocked safehouse node in the scene, or null.
func nearest_safehouse(from: Vector3) -> PlayerSafehouse:
	var best: PlayerSafehouse
	var best_distance := INF
	for safehouse in safehouses():
		if not safehouse.is_unlocked():
			continue
		var distance := safehouse.global_position.distance_to(from)
		if distance < best_distance:
			best = safehouse
			best_distance = distance
	return best


## Vehicle storage hook: records the vehicle under the safehouse and removes it from the world.
func store_vehicle(safehouse_id: StringName, vehicle: Vehicle) -> Dictionary:
	if vehicle == null or vehicle.is_wrecked():
		return {}
	if vehicle.driver != null:
		vehicle.exit()
	var record := {"color": vehicle.body_color, "health": vehicle.health, "max_health": vehicle.max_health}
	if not stored_vehicles.has(safehouse_id):
		stored_vehicles[safehouse_id] = []
	(stored_vehicles[safehouse_id] as Array).append(record)
	vehicle_stored.emit(safehouse_id, record)
	vehicle.queue_free()
	return record


func stored_count(safehouse_id: StringName) -> int:
	return (stored_vehicles.get(safehouse_id, []) as Array).size()


## Takes stored vehicle [param index] out and spawns it under [param parent] at [param at].
func retrieve_vehicle(safehouse_id: StringName, index: int, parent: Node, at: Transform3D) -> Vehicle:
	var list: Array = stored_vehicles.get(safehouse_id, [])
	if index < 0 or index >= list.size():
		return null
	var record: Dictionary = list.pop_at(index)
	var vehicle := Vehicle.new()
	vehicle.body_color = record.get("color", vehicle.body_color)
	vehicle.max_health = float(record.get("max_health", vehicle.max_health))
	parent.add_child(vehicle)
	vehicle.global_transform = at
	vehicle.health = float(record.get("health", vehicle.max_health))
	return vehicle


# --- Persistence --------------------------------------------------------------------------------

## Mission progress for the save file. The active run isn't saved: it restarts from its marker.
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"completed": completed.duplicate(),
		"unlocked_missions": unlocked_missions.keys(),
		"unlocked_safehouses": unlocked_safehouses.keys(),
		"stored_vehicles": stored_vehicles.duplicate(true),
		"journal": journal.to_dict(),
		"items": items.to_dict(),
		"heat": heat.to_dict(),
	}


func from_dict(data: Dictionary) -> void:
	reset()
	var done: Dictionary = data.get("completed", {})
	for key in done:
		completed[StringName(key)] = int(done[key])
	for key in data.get("unlocked_missions", []):
		unlocked_missions[StringName(key)] = true
	for key in data.get("unlocked_safehouses", []):
		unlocked_safehouses[StringName(key)] = true
	var stored: Dictionary = data.get("stored_vehicles", {})
	for key in stored:
		stored_vehicles[StringName(key)] = (stored[key] as Array).duplicate(true)
	journal.from_dict(data.get("journal", {}))
	items.from_dict(data.get("items", {}))
	heat.from_dict(data.get("heat", {}))
	for safehouse in safehouses():
		safehouse.refresh()
	objective_changed.emit()


## Clears all mission progress (new game, tests). Abandons the active run.
func reset() -> void:
	if active != null:
		active.abandon()
	active = null
	last_run = null
	completed.clear()
	unlocked_missions.clear()
	unlocked_safehouses.clear()
	stored_vehicles.clear()
	journal.clear()
	items.clear()
	heat.clear()
