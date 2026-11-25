class_name StickUpTests
extends RefCounted
## Tests for the stick-up driver (drivers/stick_up): drawing a gun starts the police countdown,
## aiming at the clerk holds them up, the take goes into the bag, killing someone makes the
## neighbours call the cops, and the liquor store's armed clerk fights back if left uncovered.
## Hooked from run_tests.gd; replaces the current scene with the driver and frees it afterwards.

const DRIVER := "res://drivers/stick_up/stick_up_driver.tscn"
const DriverScript := preload("res://drivers/stick_up/stick_up_driver.gd")

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "stick-up: " + description)


func _tree() -> SceneTree:
	return _runner.get_tree()


func _frames(count: int) -> void:
	for i in count:
		await _tree().physics_frame


func run() -> void:
	var saved_cash := GameState.cash
	await _test_corner_store()
	await _test_panic_button()
	await _test_shelves()
	await _test_armed_clerk()
	Input.action_release("aim")
	Input.action_release("interact")
	DriverScript.selected_shop = &"corner_store"
	GameState.cash = saved_cash


func _load_driver(shop_id: StringName) -> Node:
	var previous := _tree().current_scene
	if previous != null:
		previous.queue_free()
	await _frames(2)
	DriverScript.selected_shop = shop_id
	var driver: Node = load(DRIVER).instantiate()
	_tree().root.add_child(driver)
	_tree().current_scene = driver
	await _frames(20)
	return driver


## Turns the player's camera so the crosshair ray passes through [param point]. Iterates because the
## camera sits on a spring arm offset from the pivot it rotates around.
func _aim_camera_at(player: Player, point: Vector3) -> void:
	var pivot := player.get_node("CameraPivot") as Node3D
	var arm := player.get_node("CameraPivot/SpringArm") as SpringArm3D
	var camera := player.get_node("CameraPivot/SpringArm/Camera") as Camera3D
	for i in 6:
		var to := point - camera.global_position
		pivot.rotation.y += _angle_to_yaw(-camera.global_basis.z, to)
		var flat := Vector2(to.x, to.z).length()
		var forward := -camera.global_basis.z
		arm.rotation.x += atan2(to.y, flat) - atan2(forward.y, Vector2(forward.x, forward.z).length())
		await _frames(2)


func _angle_to_yaw(from: Vector3, to: Vector3) -> float:
	return wrapf(atan2(-to.x, -to.z) - atan2(-from.x, -from.z), -PI, PI)


func _draw(player: Player, id: StringName) -> void:
	player.weapons.select(player.weapons.slots.find(player.weapons.find(id)))


func _test_corner_store() -> void:
	var driver := await _load_driver(&"corner_store")
	var player: Player = driver.get("player")
	var controller: StickUpController = driver.get("controller")
	var session: HitSession = driver.get("session")
	var clerk: StickUpNpc = driver.get("clerk")
	var customers: Array[StickUpNpc] = driver.get("customers")
	var witnesses: Array[StickUpNpc] = driver.get("witnesses")
	var call := session.police_call
	var bag := CarryBag.of(player)
	controller.has_panic_button = false

	_check(GameState.player == player and player.weapons.current().data.id == &"fists", "driver boots with the player's gun holstered")
	_check(clerk != null and customers.size() == 2 and witnesses.size() >= 5 and driver.get("getaway_car") != null and driver.get("stash") != null, "the driver builds a clerk, customers, witnesses, a getaway car and a stash")
	_check(not call.is_active() and controller.register_cash > 0, "no police countdown before the gun comes out")

	_draw(player, &"pistol")
	await _frames(5)
	_check(controller.is_gun_drawn and not controller.robbery_started and not call.is_active(), "a gun drawn outside the shop doesn't start the stick-up")
	_draw(player, &"fists")
	player.global_position = Vector3(0.0, 0.1, -13.0)
	await _frames(10)
	_check(controller.is_player_in_shop() and not call.is_active(), "walking in with the gun holstered is fine")

	_draw(player, &"pistol")
	await _frames(3)
	_check(controller.robbery_started and call.is_counting() and call.time_left > 0.0, "drawing a gun in the shop starts the police countdown (%.0fs)" % call.time_left)
	var all_wary := customers.all(func(npc: StickUpNpc) -> bool: return npc.state == StickUpNpc.State.WARY)
	_check(clerk.state == StickUpNpc.State.WARY and all_wary, "drawing a gun makes the clerk and customers wary")

	var register_before := controller.register_cash
	await _aim_camera_at(player, clerk.global_position + Vector3(0.0, 1.2, 0.0))
	_check(not controller.is_holding_up, "pointing the gun without aiming isn't a hold-up")
	Input.action_press("aim")
	await _frames(5)
	_check(controller.aimed_npc == clerk, "aiming finds the clerk under the crosshair")
	_check(controller.is_holding_up and clerk.state == StickUpNpc.State.HELD_UP, "aiming at the clerk holds them up")
	_check(customers.all(func(npc: StickUpNpc) -> bool: return npc.state == StickUpNpc.State.COWERING), "customers put their hands up during the hold-up")

	await _frames(90)
	_check(bag.cash > 0 and bag.cash == controller.taken and controller.register_cash == register_before - controller.taken, "the clerk bags the register into the carry bag ($%d)" % bag.cash)

	Input.action_release("aim")
	await _frames(5)
	var taken := controller.taken
	await _frames(30)
	_check(clerk.state == StickUpNpc.State.WARY and controller.taken == taken, "the clerk stops bagging when you lower your aim")

	var remaining := controller.register_cash
	_check(not controller.can_grab_register(player), "you can't grab the register while the clerk is alive")
	clerk.take_damage(1000.0, player)
	await _frames(2)
	_check(not clerk.is_alive() and controller.can_grab_register(player), "the clerk can be killed, opening up the register")
	await _frames(1)
	var body := BodyLoot.of(clerk)
	var wallet := GameState.cash
	var on_body := body.cash if body != null else 0
	_check(body != null and on_body > 0 and body.interactable.perform(BodyLoot.ACTION, player) and GameState.cash == wallet + on_body, "searching the clerk's body pays their cash (+$%d)" % on_body)
	_check(not body.interactable.perform(BodyLoot.ACTION, player) and GameState.cash == wallet + on_body, "a body can only be searched once")
	var register_interactable: Interactable = driver.get("register_interactable")
	_check(register_interactable.perform(&"grab_register", player) and controller.register_cash == 0 and bag.cash == taken + remaining, "emptying the register yourself puts the rest in the bag ($%d)" % bag.cash)
	_check(customers.all(func(npc: StickUpNpc) -> bool: return npc.state == StickUpNpc.State.FLEEING), "a killing sends the customers running")

	await _frames(90)
	var calling := witnesses.filter(func(npc: StickUpNpc) -> bool: return npc.state == StickUpNpc.State.CALLING)
	_check(calling.size() >= 3 and not call.is_called(), "a killing makes bystanders and neighbouring shops phone the cops (%d calling)" % calling.size())
	await _frames(int(calling[0].call_duration * 60.0) + 30 if not calling.is_empty() else 1)
	_check(call.is_called() and call.reason == PoliceCall.REASON_WITNESS, "a finished witness call brings the police right away")

	var liquor_def: StickUpShopDef = DriverScript.SHOPS[&"liquor_store"]
	var corner_def: StickUpShopDef = DriverScript.SHOPS[&"corner_store"]
	_check(liquor_def.label() == "Liquor Store" and corner_def.label() == "Corner Store" and liquor_def.clerk_weapon_id != &"" and corner_def.clerk_weapon_id == &"", "shop types come from the business catalogue with their own tuning")


func _test_panic_button() -> void:
	var driver := await _load_driver(&"corner_store")
	var player: Player = driver.get("player")
	var controller: StickUpController = driver.get("controller")
	var clerk: StickUpNpc = driver.get("clerk")
	var call: PoliceCall = (driver.get("session") as HitSession).police_call
	controller.has_panic_button = true
	controller.register_cash = 100000
	player.global_position = Vector3(0.0, 0.1, -13.0)
	await _frames(5)
	_draw(player, &"pistol")
	await _frames(3)
	await _aim_camera_at(player, clerk.global_position + Vector3(0.0, 1.2, 0.0))
	Input.action_press("aim")
	await _frames(int(controller.shop.panic_delay * 60.0) + 30)
	_check(controller.is_holding_up and not controller.panic_tripped, "a covered clerk doesn't reach for the panic button")

	var notes: Array[String] = []
	var on_notify := func(text: String) -> void: notes.append(text)
	EventBus.notify.connect(on_notify)
	var countdown := call.time_left
	Input.action_release("aim")
	await _frames(int(controller.shop.panic_delay * 60.0) + 20)
	EventBus.notify.disconnect(on_notify)
	_check(controller.panic_tripped and controller.silent_alarm_left > 0.0, "leave the clerk uncovered and they press the panic button")
	_check(notes.is_empty() and call.is_counting() and call.reason == PoliceCall.REASON_ALARM and call.time_left < countdown and call.time_left > countdown - controller.shop.panic_delay - 1.0, "the silent alarm gives no warning and leaves the visible countdown alone")
	_check(call.time_left > controller.silent_alarm_left, "the silent alarm beats the visible countdown")
	controller.silent_alarm_left = 0.05
	await _frames(10)
	_check(call.is_called() and call.reason == PoliceCall.REASON_SILENT_ALARM, "the silent alarm brings the police early")
	Input.action_release("aim")


func _test_shelves() -> void:
	var driver := await _load_driver(&"corner_store")
	var player: Player = driver.get("player")
	var stands: Array[ShelfStand] = driver.get("stands")
	var stash: StashDropoff = driver.get("stash")
	var bag := CarryBag.of(player)
	var interactor := player.interactor
	_check(stands.size() == 3 and stands.all(func(s: ShelfStand) -> bool: return s.stock_left == s.stock and s.meter == 1.0), "the shop has three fully stocked stands")

	var smokes := stands[0]
	player.global_position = smokes.global_position + Vector3(0.0, 0.1, 1.2)
	await _frames(5)
	Input.action_press("interact")
	_check(interactor.start(smokes.action, smokes.interactable), "holding E on a stand starts bagging product")
	await _frames(15)
	_check(smokes.meter < 1.0 and smokes.meter > (smokes.stock - 1.0) / smokes.stock and bag.items.is_empty(), "the stock meter drains while you hold (%.2f)" % smokes.meter)
	Input.action_release("interact")
	await _frames(3)
	_check(not interactor.is_channelling() and smokes.stock_left == smokes.stock and smokes.meter == 1.0, "letting go stops bagging and the meter springs back")

	Input.action_press("interact")
	interactor.start(smokes.action, smokes.interactable)
	await _frames(int(smokes.stock * smokes.seconds_per_unit * 60.0) + 40)
	_check(smokes.stock_left == 0 and smokes.meter == 0.0 and bag.used_slots() == smokes.stock, "keeping E held empties the whole stand into the bag (%d items)" % bag.items.size())
	_check(bag.goods_value() == smokes.stock * smokes.unit_value and bag.items[0]["name"] == "Cigarettes", "each unit goes in the bag with its stash value ($%d)" % bag.goods_value())
	_check(not smokes.can_grab(player) and smokes.grab_reason(player) == "Shelf's empty", "an empty stand can't be grabbed from")

	var snacks := stands[1]
	player.global_position = snacks.global_position + Vector3(0.0, 0.1, 1.2)
	await _frames(5)
	interactor.start(snacks.action, snacks.interactable)
	await _frames(int(snacks.stock * snacks.seconds_per_unit * 60.0) + 40)
	_check(bag.is_full() and snacks.stock_left == snacks.stock - (bag.capacity - smokes.stock), "bagging stops when the bag is full (%d/%d), leaving stock on the stand" % [bag.used_slots(), bag.capacity])
	_check(not snacks.can_grab(player) and snacks.grab_reason(player).begins_with("Bag full"), "a full bag blocks more product")
	Input.action_release("interact")

	var wallet := GameState.cash
	var worth := bag.total_value()
	_check(stash.cash_in(player) == worth and GameState.cash == wallet + worth and bag.is_empty(), "the stash pays out the product in the bag (+$%d)" % worth)


func _test_armed_clerk() -> void:
	var driver := await _load_driver(&"liquor_store")
	var player: Player = driver.get("player")
	var controller: StickUpController = driver.get("controller")
	var clerk: StickUpNpc = driver.get("clerk")
	_check((driver.get("shop") as StickUpShopDef).id == &"liquor_store" and clerk.weapons != null and (driver.get("customers") as Array).size() == 3, "the driver can load the liquor store with an armed clerk")
	player.global_position = Vector3(0.0, 0.1, -13.0)
	await _frames(5)
	_draw(player, &"pistol")
	await _frames(int(controller.shop.clerk_nerve * 60.0) + 30)
	_check(controller.robbery_started and clerk.state == StickUpNpc.State.HOSTILE, "an armed clerk left uncovered goes for the shotgun")
	driver.queue_free()
	await _frames(2)
