class_name HitCommonTests
extends RefCounted
## Tests for the shared hit pieces: carry-over heat, masks / car swaps, the timing minigame, crew
## slots and the stash's crew cut.

var _runner: Node
var _player: Player


func _init(runner: Node) -> void:
	_runner = runner


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "hit common: " + description)


func run(player: Player) -> void:
	_player = player
	_test_heat()
	_test_mask_and_swap()
	_test_minigame()
	await _test_crew_and_cut()
	var identity := HitIdentity.of(player, false)
	if identity != null:
		identity.set_masked(false)
		identity.end_hit()


func _test_heat() -> void:
	var heat := HeatMap.new()
	var area := heat.area_key(Vector3(10.0, 0.0, 10.0))
	_check(area == heat.area_key(Vector3(50.0, 0.0, 90.0)) and area != heat.area_key(Vector3(500.0, 0.0, 10.0)), "areas are grid cells")
	_check(heat.extra_cops(area) == 0 and is_equal_approx(heat.payout_multiplier(area), 1.0), "a cold area is normal")
	heat.add_area_heat(area, 50.0)
	_check(heat.extra_cops(area) == 2, "a hot area sends extra cops")
	_check(is_equal_approx(heat.payout_multiplier(area), 0.7) and is_equal_approx(heat.countdown_multiplier(area), 0.8), "a hot area pays less and calls faster")
	heat.decay(40.0)
	_check(is_equal_approx(heat.area_heat(area), 40.0), "area heat cools off over time")
	heat.add_area_heat(area, 500.0)
	_check(heat.area_heat(area) == HeatMap.MAX_HEAT, "heat is capped")
	heat.clear()
	_check(heat.area_heat(area) == 0.0 and heat.personal_heat == 0.0, "heat can be cleared")
	heat.free()


func _test_mask_and_swap() -> void:
	var heat := HeatMap.new()
	var identity := HitIdentity.of(_player)
	identity.set_masked(true)
	identity.begin_hit()
	_check(not identity.witness(heat, &"camera") and heat.personal_heat == 0.0, "a masked face adds no personal heat")
	identity.set_masked(false)
	_check(identity.witness(heat, &"camera") and is_equal_approx(heat.personal_heat, HeatMap.FACE_HEAT), "an unmasked face adds personal heat")
	identity.witness(heat, &"camera")
	_check(is_equal_approx(heat.personal_heat, HeatMap.FACE_HEAT), "the same camera only counts once")
	_check(is_equal_approx(identity.erase_evidence(heat, &"camera"), HeatMap.FACE_HEAT) and heat.personal_heat == 0.0 and not identity.face_seen, "erasing the footage takes the heat back")

	# The getaway car is seen; leaving in a different car with the mask off sheds heat fastest.
	identity.begin_hit()
	identity.set_masked(true)
	var seen_car := Vehicle.new()
	var swap_car := Vehicle.new()
	_player.current_vehicle = seen_car
	identity.note_vehicle()
	_check(identity.seen_vehicle == seen_car and identity.decay_multiplier() == HitIdentity.MARKED, "still masked in the seen car: heat sticks")
	_player.current_vehicle = swap_car
	identity.set_masked(false)
	_check(identity.swapped_vehicle() and identity.is_disguised() and identity.decay_multiplier() == HitIdentity.CLEAN_SWAP, "a different car with the mask off sheds heat fastest")
	identity.set_masked(true)
	_check(identity.decay_multiplier() == HitIdentity.HALF_SWAP, "a different car but still masked only half helps")
	identity.set_masked(false)
	heat.add_personal_heat(50.0)
	heat.personal_decay_scale = identity.decay_multiplier()
	heat.decay(10.0)
	_check(is_equal_approx(heat.personal_heat, 50.0 - heat.personal_decay * HitIdentity.CLEAN_SWAP * 10.0), "the clean swap speeds up the heat decay")
	_player.current_vehicle = null
	identity.end_hit()
	seen_car.free()
	swap_car.free()
	heat.free()


func _test_minigame() -> void:
	var game := TimingMinigame.new()
	game.show_ui = false
	game.auto_step = false
	game.hits_needed = 3
	_runner.add_child(game)
	var won := [false]
	var resets: Array[StringName] = []
	game.succeeded.connect(func() -> void: won[0] = true)
	game.reset_happened.connect(func(why: StringName) -> void: resets.append(why))
	game.start(null, 7)
	_hit_sweet(game)
	_check(game.streak == 1, "a hit in the sweet spot counts")
	game.pin = 0.0 if game.sweet_start > 0.05 else 0.99
	_check(not game.press() and game.streak == 0 and resets.has(&"miss"), "a miss resets the streak")
	_hit_sweet(game)
	game.step(10.0)
	_check(game.streak == 0 and resets.has(&"wall"), "letting the pin hit the wall resets")
	for i in 3:
		_hit_sweet(game)
	_check(won[0] and not game.active, "hitting the sweet spot several times in a row wins")
	game.queue_free()


func _hit_sweet(game: TimingMinigame) -> void:
	game.pin = (game.sweet_start + game.sweet_end) * 0.5
	game.press()


func _test_crew_and_cut() -> void:
	var crew := HitCrew.new()
	_runner.add_child(crew)
	_check(is_equal_approx(crew.countdown_multiplier(), 1.0) and crew.payout_cut() == 0.0, "no crew, no changes")
	crew.assign(CrewSlot.Role.LOOKOUT)
	_check(crew.has_role(CrewSlot.Role.LOOKOUT) and is_equal_approx(crew.countdown_multiplier(), CrewSlot.LOOKOUT_TIME), "a lookout buys time on the police countdown")
	var getaway := Vehicle.new()
	crew.getaway = getaway
	crew.assign(CrewSlot.Role.DRIVER)
	_player.current_vehicle = getaway
	_check(is_equal_approx(crew.escape_rate(), CrewSlot.DRIVER_ESCAPE), "the driver helps lose the cops in the getaway car")
	_player.current_vehicle = null
	_check(is_equal_approx(crew.escape_rate(), 1.0), "no driver bonus on foot")
	_check(is_equal_approx(crew.payout_cut(), CrewSlot.CUT * 2.0), "each crew member takes a cut")
	_check(not crew.toggle(CrewSlot.Role.DRIVER) and not crew.has_role(CrewSlot.Role.DRIVER), "crew can be dismissed")

	var holder := Node3D.new()
	_runner.add_child(holder)
	var stash := StashDropoff.new()
	holder.add_child(stash)
	var heat := HeatMap.new()
	heat.add_area_heat(&"test", 50.0)
	stash.heat_map = heat
	stash.heat_area = &"test"
	stash.crew_cut = 0.1
	var bag := CarryBag.of(holder)
	bag.add_item("TV", 200, 2)
	bag.add_cash(100)
	_check(stash.payout(bag) == roundi((200.0 * 0.7 + 100.0) * 0.9), "goods from a hot area pay less and the crew takes its cut")
	await _runner.get_tree().process_frame
	crew.queue_free()
	holder.queue_free()
	getaway.free()
	heat.free()
