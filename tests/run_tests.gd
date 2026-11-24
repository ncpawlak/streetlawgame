extends Node
## Headless smoke tests for the core gameplay loop.
## Run: godot --headless --path . res://tests/test_runner.tscn

var _failures := 0


func _ready() -> void:
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


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures += 1
