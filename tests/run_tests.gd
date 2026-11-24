extends Node
## Headless smoke tests for the core gameplay loop.
## Run: godot --headless --path . res://tests/test_runner.tscn

var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _physics_frames(30)

	var game_state: Node = GameState
	var city: CityGenerator = main.get_node("City")
	var player: Player = game_state.player

	_check(game_state.territories.size() == 9, "city generates 9 territories")
	_check(game_state.owned_territories(&"player").size() == 1, "player starts owning one territory")
	_check(player != null and player.is_on_floor(), "player spawns and lands on the ground")
	_check(get_tree().get_nodes_in_group("gang_members").size() == 8 * city.defenders_per_district, "rival districts are defended")

	await _test_territory_capture(game_state, city, player)
	await _test_vehicle(player)
	await _test_weapons(player)
	await _test_weapon_wheel(main, player)
	await _test_ai_combat(main, player)
	await _test_explosives(main, player)
	await _test_vehicle_damage(main, city, player)
	await FrameworkTests.new(self).run(main, player)
	await OperationsTests.new(self).run()
	print("\n%s (%d failure(s))" % ["FAILED" if _failures > 0 else "ALL TESTS PASSED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_territory_capture(game_state: Node, city: CityGenerator, player: Player) -> void:
	var target: Territory = null
	for territory: Territory in game_state.territories:
		if territory.owner_gang != &"player":
			target = territory
			break
	var cash_before: int = game_state.cash
	var respect_before: int = game_state.respect
	for node in get_tree().get_nodes_in_group("gang_members"):
		var member := node as GangMember
		if member.home_territory == target:
			member.take_damage(1000.0, player)
	_check(target.defenders_remaining() == 0, "killing defenders clears the district")
	_check(game_state.cash > cash_before and game_state.respect > respect_before, "kills reward cash and respect")

	# Stand on a road intersection inside the target district.
	var offset := city.block_size * 0.5 + city.road_width * 0.5
	player.global_position = target.global_position + Vector3(offset, 1.0, offset)
	target.capture_time = 0.5
	await _physics_frames(60)
	_check(target.owner_gang == &"player", "holding a cleared district captures it")
	_check(game_state.owned_territories(&"player").size() == 2, "captured district counts as player turf")


func _test_vehicle(player: Player) -> void:
	var vehicle := get_tree().get_nodes_in_group("vehicles")[0] as Vehicle
	await _physics_frames(30)
	player.global_position = vehicle.global_position + Vector3(2.0, 0.0, 0.0)
	vehicle.enter(player)
	_check(not player.is_on_foot() and vehicle.driver == player, "player can enter a vehicle")

	var start := vehicle.global_position
	var forward := vehicle.global_basis.z
	Input.action_press("move_forward")
	await _physics_frames(120)
	Input.action_release("move_forward")
	var travelled := (vehicle.global_position - start).dot(forward)
	_check(travelled > 5.0, "throttle drives the vehicle forward (moved %.1f m)" % travelled)

	vehicle.exit()
	_check(player.is_on_foot() and vehicle.driver == null, "player can exit a vehicle")


func _test_weapons(player: Player) -> void:
	var weapons := player.weapons
	_check(weapons.find(&"fists") != null and weapons.current().data.id == &"pistol", "player starts with fists and an equipped pistol")

	var pistol := weapons.current()
	var magazine := pistol.magazine
	var fired := weapons.try_fire(player, player.global_position + Vector3.UP * 1.4, Vector3.UP)
	_check(fired and pistol.magazine == magazine - 1, "firing consumes a round")
	_check(not weapons.try_fire(player, player.global_position, Vector3.UP), "fire rate limits follow-up shots")

	var reserve := pistol.reserve
	_check(weapons.reload() and weapons.is_reloading, "R starts a reload")
	await _physics_frames(int(pistol.data.reload_time * 60.0) + 5)
	_check(pistol.magazine == pistol.data.magazine_size and pistol.reserve == reserve - 1, "reload moves reserve ammo into the magazine")

	pistol.magazine = 1
	await _physics_frames(30)
	weapons.try_fire(player, player.global_position, Vector3.UP)
	_check(weapons.is_reloading, "an empty magazine reloads automatically")
	await _physics_frames(int(pistol.data.reload_time * 60.0) + 5)

	pistol.magazine = 0
	pistol.reserve = 0
	_check(not weapons.try_fire(player, player.global_position, Vector3.UP) and not weapons.is_reloading, "can't fire or reload with no ammo")

	var smg: WeaponData = GameState.weapon_data(&"smg")
	weapons.add_weapon(smg, 50)
	weapons.add_weapon(smg, 10000)
	_check(weapons.find(&"smg").reserve == smg.max_reserve, "picking up a carried weapon adds ammo up to the cap")
	weapons.select(0)
	weapons.cycle(-1)
	_check(weapons.current_index == weapons.slots.size() - 1, "cycling wraps around the inventory")

	var shotgun: WeaponData = GameState.weapon_data(&"shotgun")
	_check(shotgun.pellets > 1 and not GameState.weapon_data(&"fists").uses_ammo(), "weapon data covers pellets and melee")


func _test_weapon_wheel(main: Node, player: Player) -> void:
	var wheel: WeaponWheel = main.get_node("HUD").weapon_wheel
	var weapons := player.weapons
	weapons.select(0)
	_check(wheel.open() and get_tree().paused, "opening the weapon wheel pauses the game")
	var count := weapons.slots.size()
	var target := 1
	var angle := target * TAU / count
	wheel._move_cursor(Vector2(sin(angle), -cos(angle)) * 100.0)
	_check(wheel.hovered == target, "mouse direction picks a wheel slice")
	var before := player.global_position
	player.velocity = Vector3(5.0, 0.0, 0.0)
	await _physics_frames(10)
	_check(player.global_position.is_equal_approx(before), "the world is frozen while the wheel is open")
	wheel.close(true)
	_check(not get_tree().paused and weapons.current_index == target, "closing the wheel equips the weapon and unpauses")

	wheel.open()
	wheel._move_cursor(Vector2(0.0, 150.0))
	wheel.close(false)
	_check(weapons.current_index == target, "cancelling the wheel keeps the current weapon")


func _test_ai_combat(main: Node, player: Player) -> void:
	player.respawn()
	await _physics_frames(10)
	var shooter := GangMember.new()
	shooter.gang_id = &"vipers"
	shooter.weapon_id = &"pistol"
	shooter.position = player.global_position + Vector3(6.0, 0.0, 0.0)
	main.add_child(shooter)
	var health_before := player.health
	await _physics_frames(240)
	_check(player.health < health_before, "rival AI shoots and damages the player (%.0f -> %.0f hp)" % [health_before, player.health])

	shooter.drop_chance = 1.0
	var pickups_before := get_tree().get_nodes_in_group("pickups").size()
	shooter.take_damage(10.0, player)
	_check(shooter.is_alive() and shooter.health == shooter.max_health - 10.0, "player damage hurts the AI")
	shooter.take_damage(1000.0, player)
	await _physics_frames(2)
	_check(not shooter.is_alive() and get_tree().get_nodes_in_group("pickups").size() == pickups_before + 1, "killed AI drops its weapon")


## A rival that stands still and never shoots back, for blast tests.
func _dummy(main: Node, at: Vector3) -> GangMember:
	var dummy := GangMember.new()
	dummy.gang_id = &"kings"
	dummy.weapon_id = &"pistol"
	dummy.aggro_range = 0.0
	dummy.alerted_range = 0.0
	dummy.max_health = 1000.0
	dummy.move_speed = 0.0
	dummy.position = at
	main.add_child(dummy)
	return dummy


func _spawn_vehicle(main: Node, at: Vector3) -> Vehicle:
	var vehicle := Vehicle.new()
	vehicle.position = at
	main.add_child(vehicle)
	return vehicle


func _test_explosives(main: Node, player: Player) -> void:
	player.respawn()
	await _physics_frames(5)
	var origin := player.global_position + Vector3(15.0, 0.0, 0.0)
	var near := _dummy(main, origin + Vector3(2.0, 0.0, 0.0))
	var far := _dummy(main, origin + Vector3(14.0, 0.0, 0.0))
	await _physics_frames(20)
	Explosion.detonate(player, origin, 6.0, 100.0, 0.0, player)
	_check(near.health < near.max_health and far.health == far.max_health, "explosions damage what's in the blast radius only")

	var grenade: WeaponData = GameState.weapon_data(&"grenade")
	near.health = near.max_health
	var thrown := Projectile.launch(player, grenade, origin + Vector3(1.0, 1.0, 0.0), Vector3.DOWN)
	await _physics_frames(30)
	_check(is_instance_valid(thrown) and near.health == near.max_health, "grenades wait for their fuse")
	await _physics_frames(int(grenade.fuse_time * 60.0))
	_check(not is_instance_valid(thrown) and near.health < near.max_health, "grenades explode when the fuse runs out")

	var car := _spawn_vehicle(main, origin + Vector3(8.0, 0.5, 0.0))
	await _physics_frames(30)
	var car_start := car.global_position
	Projectile.launch(player, GameState.weapon_data(&"rpg"), car.global_position + Vector3(-4.0, 0.9, 0.0), Vector3(1.0, 0.0, 0.0))
	await _physics_frames(30)
	_check(car.health < car.max_health and car.global_position.distance_to(car_start) > 0.3, "rockets explode on impact and throw vehicles (%.0f hp)" % car.health)
	car.queue_free()

	near.health = near.max_health
	Projectile.launch(player, GameState.weapon_data(&"molotov"), origin + Vector3(0.5, 1.0, 0.0), Vector3.DOWN)
	await _physics_frames(20)
	var after_splash := near.health
	await _physics_frames(60)
	_check(not get_tree().get_nodes_in_group("fires").is_empty() and near.health < after_splash, "molotovs leave fire that keeps burning (%d fires, %.0f -> %.0f hp)" % [get_tree().get_nodes_in_group("fires").size(), after_splash, near.health])
	await _physics_frames(int(GameState.weapon_data(&"molotov").fire_duration * 60.0))
	_check(get_tree().get_nodes_in_group("fires").is_empty(), "fire burns out")

	var weapons := player.weapons
	weapons.add_weapon(GameState.weapon_data(&"c4"), 2)
	weapons.select(weapons.slots.find(weapons.find(&"c4")))
	await _physics_frames(30)
	near.health = near.max_health
	var c4_ammo := weapons.current().magazine + weapons.current().reserve
	_check(weapons.try_fire(player, origin + Vector3(0.5, 1.0, 0.0), Vector3.DOWN), "C4 can be placed")
	await _physics_frames(40)
	var charge: Projectile = weapons.placed_charges[0]
	_check(charge.is_stuck and near.health == near.max_health, "C4 sticks and waits for the detonator")
	await _physics_frames(30)
	_check(weapons.current().magazine + weapons.current().reserve == c4_ammo - 1 and weapons.current().ammo_text() == "x%d" % (c4_ammo - 1), "throwables are counted, not reloaded from reserve")
	_check(weapons.detonate_charges() == 1 and near.health < near.max_health and weapons.placed_charges.is_empty(), "the detonator sets off placed C4")
	near.queue_free()
	far.queue_free()
	await _physics_frames(2)


func _test_vehicle_damage(main: Node, city: CityGenerator, player: Player) -> void:
	player.respawn()
	await _physics_frames(5)
	var origin := player.global_position + Vector3(15.0, 0.0, 0.0)
	var car := _spawn_vehicle(main, origin + Vector3(0.0, 0.5, 0.0))
	await _physics_frames(30)
	var weapons := player.weapons
	weapons.add_weapon(GameState.weapon_data(&"rifle"), 90)
	weapons.select(weapons.slots.find(weapons.find(&"rifle")))
	await _physics_frames(30)
	var muzzle := car.global_position + Vector3(-6.0, 1.0, 0.0)
	var exclude: Array[RID] = [player.get_rid()]
	weapons.try_fire(player, muzzle, car.global_position + Vector3(0.0, 0.8, 0.0) - muzzle, exclude)
	_check(car.health < car.max_health, "bullets damage vehicles")

	car.take_damage(car.max_health * 0.4)
	_check(car.damage_state == Vehicle.DamageState.SMOKING, "a damaged vehicle smokes")
	var bystander := _dummy(main, car.global_position + Vector3(0.0, 0.0, 4.0))
	await _physics_frames(10)
	player.global_position = car.global_position + Vector3(2.0, 0.0, 0.0)
	car.enter(player)
	car.burn_damage_per_second = 200.0
	car.take_damage(car.max_health * 0.3, player)
	_check(car.damage_state == Vehicle.DamageState.BURNING, "a badly damaged vehicle catches fire")
	await _physics_frames(60)
	_check(car.is_wrecked() and player.is_on_foot() and not car.can_enter(), "a burning vehicle explodes, throws the driver out and can't be driven")
	_check(bystander.health < bystander.max_health, "a vehicle explosion hurts people nearby")
	bystander.queue_free()

	var wall_x := city.city_size() * 0.5 + 20.0
	var crasher := _spawn_vehicle(main, Vector3(wall_x - 12.0, 1.0, player.spawn_point.z))
	crasher.rotation.y = PI / 2.0
	await _physics_frames(20)
	crasher.linear_velocity = Vector3(30.0, 0.0, 0.0)
	await _physics_frames(60)
	_check(crasher.health < crasher.max_health, "crashing into a wall damages the vehicle (%.0f hp)" % crasher.health)


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures += 1
