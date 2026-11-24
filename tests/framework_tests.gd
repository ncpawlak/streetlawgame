class_name FrameworkTests
extends RefCounted
## Tests for the shared framework (ContentDB, core vocabulary, interaction). Hooked from run_tests.gd.
## Every test restores the global state it touches so the suite is stable across runs.

## Isolated test area high above the city, so nothing else is in interaction range.
const SANDBOX := Vector3(0.0, 2000.0, 0.0)

var _runner: Node
var _player: Player
var _sandbox: Node3D


func _init(runner: Node) -> void:
	_runner = runner


func run(main: Node, player: Player) -> void:
	_player = player
	_test_content_db()
	_test_content_override_root()
	_test_core_vocabulary()
	await _with_sandbox(main, _test_interactable_perform)
	await _with_sandbox(main, _test_interactor_focus_and_channel)
	await _test_vehicle_entry_via_interactor(player)
	await LocationTests.new(self).run(main, player)


func check(condition: bool, description: String) -> void:
	_check(condition, description)


func frames(count: int) -> void:
	await _frames(count)


## The current sandbox node (valid inside [method with_sandbox]).
func sandbox() -> Node3D:
	return _sandbox


func with_sandbox(main: Node, test: Callable) -> void:
	await _with_sandbox(main, test)


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, description)


func _frames(count: int) -> void:
	await _runner.call("_physics_frames", count)


func _test_content_db() -> void:
	var weapon_ids := ContentDB.ids(&"weapons")
	_check(weapon_ids.has(&"pistol") and weapon_ids.has(&"fists"), "ContentDB indexes data/weapons")
	var sorted := weapon_ids.duplicate()
	sorted.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_check(weapon_ids == sorted and ContentDB.all(&"weapons").size() == weapon_ids.size(), "ContentDB.ids/all are sorted by id")
	_check(GameState.weapon_data(&"pistol") == ContentDB.get_def(&"weapons", &"pistol"), "GameState.weapon_data goes through ContentDB")
	_check(ContentDB.find_def(&"weapons", &"no_such_weapon") == null and not ContentDB.has_def(&"weapons", &"no_such_weapon"), "missing content returns null")
	var issues := ContentDB.validate()
	_check(issues.is_empty(), "all content validates (%s)" % "; ".join(issues))

	var custom := WeaponData.new()
	custom.id = &"pistol"
	custom.display_name = "Registered Pistol"
	ContentDB.register(&"weapons", custom)
	_check(GameState.weapon_data(&"pistol").display_name == "Registered Pistol", "registered content overrides files")
	ContentDB.unregister(&"weapons", &"pistol")
	_check(GameState.weapon_data(&"pistol").display_name == "Pistol", "unregister restores the file version")


func _test_content_override_root() -> void:
	var root := "user://framework_test_mod/data"
	DirAccess.make_dir_recursive_absolute(root.path_join("weapons"))
	var modded := (ContentDB.get_def(&"weapons", &"smg") as WeaponData).duplicate() as WeaponData
	modded.display_name = "Modded SMG"
	ResourceSaver.save(modded, root.path_join("weapons/smg.tres"))
	ContentDB.add_content_root(root, ContentDB.MOD_PRIORITY)
	ContentDB.reload()
	_check((ContentDB.get_def(&"weapons", &"smg") as WeaponData).display_name == "Modded SMG", "a mod content root overrides base content")
	_check(ContentDB.ids(&"weapons").count(&"smg") == 1, "overridden ids are not duplicated")
	ContentDB.remove_content_root(root)
	ContentDB.reload()
	DirAccess.remove_absolute(root.path_join("weapons/smg.tres"))
	DirAccess.remove_absolute(root.path_join("weapons"))
	DirAccess.remove_absolute(root)
	DirAccess.remove_absolute(root.get_base_dir())
	_check((ContentDB.get_def(&"weapons", &"smg") as WeaponData).display_name != "Modded SMG", "removing the root restores base content")


func _test_core_vocabulary() -> void:
	var cash_before := GameState.cash
	var ctx := ActionContext.new()
	ctx.vars["who"] = "Tony"
	_check(ctx.format("Hi {who}, you have ${cash}") == "Hi Tony, you have $%d" % GameState.cash, "ActionContext.format fills vars and built-ins")

	var rich := CashCondition.new()
	rich.amount = GameState.cash + 1
	_check(not rich.is_met(ctx) and rich.reason(ctx) == "Need $%d" % rich.amount, "unmet condition reports its reason")
	rich.invert = true
	_check(rich.is_met(ctx) and rich.reason(ctx) == "", "inverted condition passes with no reason")

	GameState.set_flag(&"framework_test", true)
	var flag := FlagCondition.new()
	flag.flag = &"framework_test"
	_check(flag.is_met(ctx), "FlagCondition reads GameState flags")
	GameState.flags.erase(&"framework_test")
	_check(not flag.is_met(ctx), "FlagCondition fails once the flag is cleared")

	var cost := CashCost.new()
	cost.amount = 10
	GameState.add_cash(20)
	_check(cost.pay(ctx) and GameState.cash == cash_before + 10, "CashCost spends cash")
	cost.amount = GameState.cash + 1
	_check(not cost.pay(ctx) and GameState.cash == cash_before + 10, "unaffordable cost spends nothing")

	var never := CashEffect.new()
	never.amount = 1000
	never.chance = 0.0
	never.apply(ctx)
	_check(GameState.cash == cash_before + 10, "an effect with chance 0 never fires")
	GameState.cash = cash_before
	EventBus.cash_changed.emit(GameState.cash)


func _test_interactable_perform() -> void:
	var cash_before := GameState.cash
	var target := Node3D.new()
	target.name = "TestTarget"
	_sandbox.add_child(target)
	target.global_position = SANDBOX + Vector3(0.0, 1.0, 1.0)
	var interactable := Interactable.new()
	target.add_child(interactable)

	var reward := CashEffect.new()
	reward.amount = 25
	var cooldown := CooldownCondition.new()
	cooldown.seconds = 9999.0
	var effects: Array[Effect] = [reward]
	var conditions: Array[Condition] = [cooldown]
	var action := InteractionAction.create(&"test_rob", "Rob {target}", effects, conditions)
	var fee := CashCost.new()
	fee.amount = 5
	action.costs = [fee]
	interactable.add_action(action)

	var performed: Array[StringName] = []
	interactable.action_performed.connect(func(action_id: StringName, _actor: Node, _ctx: ActionContext) -> void: performed.append(action_id))
	_check(interactable.target == target, "Interactable targets its parent")
	_check(action.make_label(interactable.make_context(_player, action)) == "Rob TestTarget ($5)", "action labels format vars and costs")
	_check(interactable.perform(&"test_rob", _player) and GameState.cash == cash_before + 20, "perform pays costs and applies effects")
	_check(performed == [&"test_rob"] and int(interactable.memory[&"test_rob"].count) == 1, "perform emits action_performed and records memory")
	_check(not interactable.perform(&"test_rob", _player) and GameState.cash == cash_before + 20, "cooldown blocks a repeat")
	GameState.cash = cash_before
	EventBus.cash_changed.emit(GameState.cash)


func _test_interactor_focus_and_channel() -> void:
	var respect_before := GameState.respect
	var target := Node3D.new()
	target.name = "Stash"
	_sandbox.add_child(target)
	target.global_position = SANDBOX + Vector3(0.0, 1.0, 1.0)
	var interactable := Interactable.new()
	target.add_child(interactable)
	var reward := RespectEffect.new()
	reward.amount = 3
	var effects: Array[Effect] = [reward]
	var action := InteractionAction.create(&"test_search", "Search", effects)
	action.duration = 0.2
	interactable.add_action(action)

	await _frames(10)
	_check(_player.interactor.focused == interactable, "Interactor focuses the interactable in range")
	_check(_player.interactor.try_interact() and _player.interactor.is_channelling(), "a channelled action starts on interact")
	await _frames(30)
	_check(not _player.interactor.is_channelling() and GameState.respect == respect_before + 3, "the channel completes and applies effects")

	_check(_player.interactor.start(action), "the channel can be restarted")
	_player.take_damage(1.0)
	_check(not _player.interactor.is_channelling(), "taking damage cancels the channel")
	await _frames(30)
	_check(GameState.respect == respect_before + 3, "a cancelled channel applies nothing")

	interactable.enabled = false
	await _frames(10)
	_check(_player.interactor.focused == null, "disabled interactables lose focus")
	GameState.respect = respect_before
	EventBus.respect_changed.emit(GameState.respect)
	_player.health = _player.max_health


func _test_vehicle_entry_via_interactor(player: Player) -> void:
	var vehicle: Vehicle = null
	for node in player.get_tree().get_nodes_in_group("vehicles"):
		var candidate := node as Vehicle
		if candidate.can_enter():
			vehicle = candidate
			break
	if vehicle == null:
		_check(false, "a free vehicle exists for the interaction test")
		return
	var start := player.global_position
	player.global_position = vehicle.global_position + vehicle.global_basis.x * 2.2
	await _frames(10)
	var focused := player.interactor.focused
	var focused_vehicle := focused.target as Vehicle if focused != null else null
	_check(focused_vehicle != null, "vehicles are focused through the interaction system")
	_check(player.interactor.try_interact() and focused_vehicle != null and player.current_vehicle == focused_vehicle, "E on a vehicle enters it")
	await _frames(ceili(player.interactor.refresh_interval * Engine.physics_ticks_per_second) + 2)
	_check(player.interactor.focused == null, "nothing is focused while driving")
	if player.current_vehicle != null:
		player.current_vehicle.exit()
	player.global_position = start
	await _frames(5)


## Runs [param test] with the player standing on a temporary floor high above the city.
func _with_sandbox(main: Node, test: Callable) -> void:
	var start := _player.global_position
	_sandbox = Node3D.new()
	_sandbox.name = "FrameworkSandbox"
	main.add_child(_sandbox)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 1.0, 30.0)
	shape.shape = box
	floor_body.add_child(shape)
	_sandbox.add_child(floor_body)
	floor_body.global_position = SANDBOX - Vector3(0.0, 0.5, 0.0)
	_player.global_position = SANDBOX + Vector3(0.0, 0.1, 0.0)
	_player.velocity = Vector3.ZERO
	await _frames(5)
	await test.call()
	_sandbox.queue_free()
	_sandbox = null
	_player.global_position = start
	_player.velocity = Vector3.ZERO
	await _frames(5)
