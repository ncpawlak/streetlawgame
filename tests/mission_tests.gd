class_name MissionTests
extends RefCounted
## Tests for the mission building blocks: journal/leads, heat, the mission runner and its step
## primitives, trigger zones, clean deliveries, park-with-zero-heat, fail/retry, safehouses, saving
## and the HUD/journal/map hooks. Hooked from run_tests.gd. Restores everything it touches.

const SANDBOX := Vector3(0.0, 2500.0, 0.0)
const SAVE_PATH := "user://mission_tests_save.dat"

var _runner: Node
var _player: Player
var _hud: Node
var _sandbox: Node3D
var _defs: Array[Array] = []
var _flags: Array[StringName] = [&"mt_go", &"mt_zone_flag", &"mt_never"]


func _init(runner: Node) -> void:
	_runner = runner


func run(main: Node, player: Player) -> void:
	_player = player
	_hud = main.get_node("HUD")
	var start := player.global_position
	var spawn := player.spawn_point
	var cash := GameState.cash
	var respect := GameState.respect
	var hook_delay := Missions.hook_auto_complete_delay
	Missions.reset()
	_build_sandbox(main)
	await _frames(5)

	_test_journal()
	_test_heat()
	await _test_runner_and_hooks()
	await _test_trigger_zone()
	await _test_deliver_and_park()
	await _test_fail_and_retry()
	await _test_kill_and_loot()
	await _test_safehouse()
	_test_save_round_trip()

	Missions.reset()
	Missions.hook_auto_complete_delay = hook_delay
	Missions.unregister_hook(MissionService.HOOK_CUTSCENE)
	for entry in _defs:
		ContentDB.unregister(entry[0], entry[1])
	for flag in _flags:
		GameState.flags.erase(flag)
	for def_id: StringName in [&"mt_basic", &"mt_deliver", &"mt_fail", &"mt_kill"]:
		GameState.flags.erase(StringName("mission:%s:done" % def_id))
	GameState.cash = cash
	GameState.respect = respect
	EventBus.cash_changed.emit(cash)
	EventBus.respect_changed.emit(respect)
	if get_tree().paused:
		get_tree().paused = false
	if _player.current_vehicle != null:
		_player.current_vehicle.exit()
	_sandbox.queue_free()
	_player.spawn_point = spawn
	_player.global_position = start
	_player.velocity = Vector3.ZERO
	await _frames(5)


# --- Journal and heat ---------------------------------------------------------------------------

func _test_journal() -> void:
	var lead := Missions.add_lead(&"mt_lead", "Ask about Pedro", "Dre knows a guy.", SANDBOX + Vector3(5, 0, 5), false)
	_check(not lead.is_empty() and Missions.journal.has_lead(&"mt_lead"), "leads can be added to the journal")
	_check(not Missions.journal.is_marker_visible(&"mt_lead"), "a lead's map marker can start locked")
	Missions.journal.unlock_marker(&"mt_lead")
	_check(Missions.journal.is_marker_visible(&"mt_lead"), "a lead's map marker can be unlocked")

	var journal: JournalScreen = _hud.get("journal_screen")
	_check(journal.open(JournalScreen.TAB_LEADS) and get_tree().paused, "the journal opens on the Leads tab and pauses")
	_check(journal.listed_leads().has("Ask about Pedro"), "open leads are listed in the journal")
	journal.close()
	_check(not get_tree().paused, "closing the journal unpauses")

	var copy := MissionJournal.new()
	copy.from_dict(Missions.journal.to_dict())
	_check(copy.has_lead(&"mt_lead") and copy.get_lead(&"mt_lead")["note"] == "Dre knows a guy." and copy.is_marker_visible(&"mt_lead"), "the journal survives a save round-trip")
	Missions.journal.complete(&"mt_lead")
	_check(Missions.journal.leads(MissionJournal.OPEN).is_empty() and Missions.journal.leads(MissionJournal.DONE).size() == 1, "completed leads move off the open list")


func _test_heat() -> void:
	var heat := HeatTracker.new()
	heat.add(30.0)
	_check(heat.is_hot() and heat.stars() == 2 and heat.is_seen(), "heat raises stars and counts as seen")
	heat.tick(heat.unseen_after + 0.5)
	_check(not heat.is_seen() and heat.level() < 30.0, "heat decays once the player is out of sight")
	heat.clear()
	_check(not heat.is_hot() and heat.stars() == 0, "heat can be cleared")
	var external := 42.0
	heat.provider = func() -> float: return external
	_check(heat.level() == 42.0, "an external wanted system can drive heat through provider")

	var items := MissionInventory.new()
	items.add(&"note", 2)
	_check(items.has(&"note", 2) and items.remove(&"note") and items.count_of(&"note") == 1, "mission items can be added and removed")


# --- Runner, hooks, waypoint --------------------------------------------------------------------

func _test_runner_and_hooks() -> void:
	var zone := _zone(&"mt_zone_a", Vector3(10, 0, 0), TriggerZone.Mode.ANY)
	var requested: Array[StringName] = []
	Missions.register_hook(MissionService.HOOK_CUTSCENE, func(hook_id: StringName, _ctx: ActionContext) -> bool:
		requested.append(hook_id)
		return true)

	var wait := WaitStep.new()
	wait.id = &"wait"
	wait.text = "Wait for the word"
	wait.flag = &"mt_go"
	var hook := HookStep.new()
	hook.id = &"intro"
	hook.text = "Watch the intro"
	hook.hook_id = &"mt_intro"
	var reach := EnterZoneStep.new()
	reach.id = &"reach"
	reach.text = "Get to the corner"
	reach.zone_id = &"mt_zone_a"
	var def := _mission(&"mt_basic", [wait, hook, reach])
	def.cash_reward = 100

	var cash := GameState.cash
	_check(Missions.start_mission(&"mt_basic") and Missions.is_active(&"mt_basic"), "a registered mission starts by id")
	_check(not Missions.can_start(&"mt_basic"), "only one mission runs at a time")
	var objective: ObjectiveHud = _hud.get("objective_hud")
	_check(objective.line_texts() == PackedStringArray(["Wait for the word"]), "the HUD shows the current objective (%s)" % ", ".join(objective.line_texts()))
	GameState.set_flag(&"mt_go", true)
	await _frames(3)
	_check(_step_id() == &"intro" and requested == [&"mt_intro"], "a wait step completes on its flag and a hook step calls the registered handler")
	await _frames(10)
	_check(_step_id() == &"intro", "a hook step waits for finish_hook")
	Missions.finish_hook(MissionService.HOOK_CUTSCENE, &"mt_intro", &"seen")
	await _frames(2)
	_check(_step_id() == &"reach" and Missions.active.ctx.vars.get("hook_outcome") == &"seen", "finish_hook advances the mission and stores the outcome")

	var waypoint: Variant = Missions.current_waypoint()
	_check(waypoint is Vector3 and (waypoint as Vector3).distance_to(zone.global_position) < 0.1, "the objective waypoint points at the step's zone")
	var map: MapScreen = _hud.get("map_screen")
	map.refresh_markers()
	var current := map.markers.filter(func(m: Dictionary) -> bool: return m["current"])
	_check(current.size() == 1 and Vector2(current[0]["position"].x, current[0]["position"].z).distance_to(Vector2(zone.global_position.x, zone.global_position.z)) < 0.5, "the map marks the active objective as the current marker")

	_player.global_position = zone.global_position
	await _frames(5)
	_check(not Missions.is_active() and Missions.is_completed(&"mt_basic") and GameState.cash == cash + 100, "entering the zone finishes the mission and pays out")
	var result: MissionResultScreen = _hud.get("mission_result")
	_check(result.is_showing and not result.is_failure, "the result screen shows MISSION COMPLETE")
	result.dismiss()
	_player.global_position = SANDBOX + Vector3(0, 0.1, 0)
	await _frames(3)


# --- Trigger zones ------------------------------------------------------------------------------

func _test_trigger_zone() -> void:
	var foot := _zone(&"mt_foot", Vector3(-10, 0, 0), TriggerZone.Mode.ON_FOOT)
	var effect := SetFlagEffect.new()
	effect.flag = &"mt_zone_flag"
	effect.value = true
	foot.effects = [effect]
	foot.one_shot = true
	var drive_only := _zone(&"mt_drive_only", Vector3(-10, 0, 0), TriggerZone.Mode.IN_VEHICLE)
	var fired := [0]
	foot.triggered.connect(func(_actor: Node) -> void: fired[0] += 1)
	_player.global_position = foot.global_position
	await _frames(4)
	_check(fired[0] == 1 and GameState.get_flag(&"mt_zone_flag") == true, "a standalone trigger zone fires and applies its effects")
	_check(not drive_only.is_satisfied(), "an in-vehicle zone ignores the player on foot")
	_player.global_position = SANDBOX + Vector3(0, 0.1, 0)
	await _frames(3)
	_player.global_position = foot.global_position
	await _frames(3)
	_check(fired[0] == 1, "one-shot zones only fire once")
	_player.global_position = SANDBOX + Vector3(0, 0.1, 0)
	await _frames(3)


# --- Delivery with clean bonus, park with zero heat ---------------------------------------------

func _test_deliver_and_park() -> void:
	var garage := _zone(&"mt_garage", Vector3(0, 0, 25), TriggerZone.Mode.IN_VEHICLE)
	var driveway := _zone(&"mt_driveway", Vector3(25, 0, 25), TriggerZone.Mode.IN_VEHICLE)
	var deliver := DeliverVehicleStep.new()
	deliver.id = &"deliver"
	deliver.text = "Take the car to the garage"
	deliver.zone_id = &"mt_garage"
	deliver.vehicle_tag = &"mt_car"
	deliver.remove_on_delivery = false
	var park := ParkVehicleStep.new()
	park.id = &"park"
	park.text = "Park in the driveway"
	park.zone_id = &"mt_driveway"
	park.vehicle_tag = &"mt_car"
	park.hold_time = 0.2
	var def := _mission(&"mt_deliver", [deliver, park])
	def.repeatable = true
	Missions.heat.decay_rate = 0.0

	var car := _car(Vector3(-20, 0, 25))
	await _frames(20)
	car.enter(_player)
	Missions.start_mission(&"mt_deliver")
	await _frames(3)
	await _drive(car, garage.global_position)
	_check(_step_id() == &"park", "delivering the car to the zone completes the delivery step")
	var bonuses := Missions.active.bonuses if Missions.active != null else []
	_check(bonuses.size() == 1 and bonuses[0]["achieved"], "a delivery with no heat and no damage earns the clean bonus")

	Missions.heat.add(30.0)
	await _drive(car, driveway.global_position)
	var objective: ObjectiveHud = _hud.get("objective_hud")
	_check(Missions.is_active() and ", ".join(objective.line_texts()).contains("lose the heat first"), "parking with heat is blocked and the HUD says to lose it")
	Missions.heat.clear()
	await _frames(30)
	_check(not Missions.is_active() and Missions.is_completed(&"mt_deliver"), "parking with zero heat completes the mission")
	(_hud.get("mission_result") as MissionResultScreen).dismiss()

	# A dirty run: heat while driving loses the bonus.
	await _drive(car, Vector3(-20, 0, 25) + SANDBOX)
	Missions.start_mission(&"mt_deliver")
	Missions.heat.add(10.0)
	await _frames(3)
	await _drive(car, garage.global_position)
	bonuses = Missions.active.bonuses if Missions.active != null else []
	_check(bonuses.size() == 1 and not bonuses[0]["achieved"], "heat during the run loses the clean bonus")
	Missions.abandon()
	Missions.heat.clear()

	var health := car.health
	car.set_meta(DeliverVehicleStep.META_START_HEALTH, car.max_health)
	car.health = car.max_health * 0.5
	var step := DeliverVehicleStep.new()
	step._track(car)
	_check(step.damage_of(car) >= 0.49 and not step.is_clean(car), "damage over the threshold since the theft isn't clean")
	car.remove_meta(DeliverVehicleStep.META_START_HEALTH)
	car.health = health
	car.exit()
	car.queue_free()
	Missions.heat.decay_rate = HeatTracker.new().decay_rate
	_player.global_position = SANDBOX + Vector3(0, 0.1, 0)
	await _frames(3)


# --- Fail, checkpoint, retry --------------------------------------------------------------------

func _test_fail_and_retry() -> void:
	var first := WaitStep.new()
	first.id = &"first"
	first.text = "Wait"
	first.flag = &"mt_go"
	var timed := WaitStep.new()
	timed.id = &"timed"
	timed.text = "Hold on"
	timed.flag = &"mt_never"
	timed.checkpoint = true
	timed.time_limit = 0.3
	_mission(&"mt_fail", [first, timed])
	var failed := [""]
	var on_fail := func(_id: StringName, reason: String, _run: MissionRun) -> void: failed[0] = reason
	Missions.mission_failed.connect(on_fail)
	Missions.start_mission(&"mt_fail")
	await _frames(40)
	var result: MissionResultScreen = _hud.get("mission_result")
	_check(failed[0] == "You ran out of time." and not Missions.is_active(), "a step time limit fails the mission")
	_check(result.is_showing and result.is_failure and get_tree().paused, "the fail screen shows and pauses")
	_check(result.retry() and Missions.is_active(&"mt_fail") and _step_id() == &"timed" and Missions.active.attempt == 1, "retry resumes from the last checkpoint")
	_check(not get_tree().paused and not result.is_showing, "retrying closes the fail screen")
	Missions.abandon()
	_check(not result.is_showing, "abandoning doesn't show the fail screen")
	Missions.mission_failed.disconnect(on_fail)

	Missions.start_mission(&"mt_fail")
	EventBus.player_died.emit()
	_check(not Missions.is_active() and Missions.last_run.state == MissionRun.State.FAILED, "dying fails the mission (%s)" % Missions.last_run.fail_reason)
	result.dismiss()
	await _frames(2)


# --- Kill, loot, have item ----------------------------------------------------------------------

func _test_kill_and_loot() -> void:
	var kill := KillStep.new()
	kill.id = &"kill"
	kill.text = "Take out the lookouts"
	kill.target_tag = &"mt_enemy"
	kill.drop_item_id = &"mt_note"
	var have := HaveItemStep.new()
	have.id = &"loot"
	have.text = "Grab the note"
	have.item_id = &"mt_note"
	_mission(&"mt_kill", [kill, have])
	var enemies: Array[Node3D] = []
	for i in 2:
		var enemy := Node3D.new()
		_sandbox.add_child(enemy)
		enemy.global_position = SANDBOX + Vector3(5 + i, 0, -10)
		Missions.tag(enemy, &"mt_enemy")
		enemies.append(enemy)
	Missions.start_mission(&"mt_kill")
	var objective: ObjectiveHud = _hud.get("objective_hud")
	_check(objective.line_texts() == PackedStringArray(["Take out the lookouts (0/2)"]), "kill steps show progress")
	Missions.report_kill(enemies[0])
	Missions.report_kill(enemies[1])
	await _frames(2)
	var pickup := Missions.first_tagged(MissionPickup.tag_for(&"mt_note")) as MissionPickup
	_check(_step_id() == &"loot" and pickup != null and pickup.global_position.distance_to(enemies[1].global_position) < 1.0, "the last kill drops the note on the body")
	var waypoint: Variant = Missions.current_waypoint()
	_check(waypoint is Vector3 and (waypoint as Vector3).distance_to(pickup.global_position) < 0.1, "the have-item waypoint points at the pickup")
	pickup.collect()
	await _frames(2)
	_check(Missions.items.has(&"mt_note") and Missions.is_completed(&"mt_kill"), "looting the note completes the mission")
	(_hud.get("mission_result") as MissionResultScreen).dismiss()


# --- Safehouses ---------------------------------------------------------------------------------

func _test_safehouse() -> void:
	var def := PlayerSafehouseDef.new()
	def.id = &"mt_house"
	def.display_name = "Test House"
	_register(PlayerSafehouseDef.TYPE, def)
	var house := PlayerSafehouse.new()
	house.safehouse_id = &"mt_house"
	_sandbox.add_child(house)
	house.global_position = SANDBOX + Vector3(-25, 0, -25)
	await _frames(2)
	_check(not house.is_unlocked() and not house.door.enabled, "safehouses start locked")
	var slots := get_tree().get_nodes_in_group(PlayerSafehouse.WARDROBE_GROUP)
	_check(slots.has(house.wardrobe_slot) and house.wardrobe_slot.get_meta(&"safehouse_id") == &"mt_house", "safehouses leave a wardrobe slot for the clothing system")

	Missions.heat.decay_rate = 0.0
	Missions.heat.add(40.0)
	_check(not house.on_arrival() and Missions.heat.is_hot(), "a locked safehouse doesn't clear heat")
	Missions.unlock_safehouse(&"mt_house")
	_check(house.is_unlocked() and house.door.enabled, "unlocking a safehouse opens its door")
	_check(not house.on_arrival() and Missions.heat.is_hot(), "arriving while seen doesn't clear heat")
	var unseen := Missions.heat.unseen_after
	Missions.heat.unseen_after = 0.0
	_check(house.on_arrival() and not Missions.heat.is_hot(), "arriving unseen clears the heat")
	Missions.heat.unseen_after = unseen
	Missions.heat.decay_rate = HeatTracker.new().decay_rate

	EventBus.player_died.emit()
	_check(_player.spawn_point.distance_to(house.respawn_position()) < 0.1, "dying respawns the player at the nearest unlocked safehouse")

	_player.health = 10.0
	house.rest()
	_check(_player.health == _player.max_health, "resting at a safehouse heals")

	var car := _car(Vector3(0, 0, -25))
	await _frames(5)
	car.enter(_player)
	car.global_transform = house.garage_transform()
	_check(house.store_current_vehicle() and Missions.stored_count(&"mt_house") == 1 and _player.current_vehicle == null, "a vehicle can be stored in the safehouse garage")
	var back := Missions.retrieve_vehicle(&"mt_house", 0, _sandbox, house.garage_transform())
	_check(back != null and Missions.stored_count(&"mt_house") == 0, "stored vehicles can be taken back out")
	back.queue_free()
	_player.global_position = SANDBOX + Vector3(0, 0.1, 0)
	await _frames(3)


func _test_save_round_trip() -> void:
	Missions.add_lead(&"mt_saved", "Saved lead")
	Missions.give_item(&"mt_key")
	_check(SaveGame.save_game(SAVE_PATH) and SaveGame.has_save(SAVE_PATH), "the game saves to disk")
	Missions.reset()
	_check(not Missions.is_safehouse_unlocked(&"mt_house") and not Missions.journal.has_lead(&"mt_saved"), "reset clears mission progress")
	_check(SaveGame.load_game(SAVE_PATH, ["Missions"]), "the save loads")
	_check(Missions.is_safehouse_unlocked(&"mt_house") and Missions.journal.has_lead(&"mt_saved") and Missions.items.has(&"mt_key") and Missions.is_completed(&"mt_kill"), "leads, items, unlocks and completed missions persist")
	SaveGame.delete_save(SAVE_PATH)
	_check(not SaveGame.has_save(SAVE_PATH), "the save can be deleted")


# --- Helpers ------------------------------------------------------------------------------------

func _build_sandbox(main: Node) -> void:
	_sandbox = Node3D.new()
	_sandbox.name = "MissionSandbox"
	main.add_child(_sandbox)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	floor_body.add_child(shape)
	_sandbox.add_child(floor_body)
	floor_body.global_position = SANDBOX - Vector3(0.0, 0.5, 0.0)
	_player.global_position = SANDBOX + Vector3(0.0, 0.1, 0.0)
	_player.velocity = Vector3.ZERO


func _zone(zone_id: StringName, offset: Vector3, mode: TriggerZone.Mode) -> TriggerZone:
	var zone := TriggerZone.new()
	zone.zone_id = zone_id
	zone.mode = mode
	zone.size = Vector3(8, 4, 8)
	zone.show_volume = false
	_sandbox.add_child(zone)
	zone.global_position = SANDBOX + offset + Vector3(0, 1.5, 0)
	return zone


func _car(offset: Vector3) -> Vehicle:
	var car := Vehicle.new()
	_sandbox.add_child(car)
	car.global_position = SANDBOX + offset + Vector3(0, 0.6, 0)
	Missions.tag(car, &"mt_car")
	return car


func _drive(car: Vehicle, at: Vector3) -> void:
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(at.x, SANDBOX.y + 0.6, at.z))
	await _frames(40)


func _mission(mission_id: StringName, steps: Array) -> MissionDef:
	var def := MissionDef.new()
	def.id = mission_id
	def.display_name = String(mission_id).capitalize()
	var typed: Array[MissionStep] = []
	for step in steps:
		typed.append(step)
	def.steps = typed
	_register(MissionDef.TYPE, def)
	return def


func _register(type: StringName, def: Resource) -> void:
	ContentDB.register(type, def)
	_defs.append([type, def.get("id")])


func _step_id() -> StringName:
	var step := Missions.active.current_step() if Missions.active != null else null
	return step.id if step != null else &""


func get_tree() -> SceneTree:
	return _runner.get_tree()


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, description)


func _frames(count: int) -> void:
	await _runner.call("_physics_frames", count)
