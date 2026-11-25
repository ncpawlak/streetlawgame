class_name BusinessTests
extends RefCounted
## Tests for businesses (#36): content, site placement, purchase gating by turf and clout, cash,
## per-site shop discount, income, clout grant/removal, hangout crew, tier pricing, shops and
## save/load. Hooked from run_tests.gd; restores everything it touches.

const BOTTOMS := &"tamarack_row"
const RAIL_YARDS := &"northgrove"
const OLD_HARBOR := &"mangona"
const CORNER := &"tamarack_corner_store"
const LIQUOR := &"tamarack_liquor_store"
const PAWN := &"northgrove_pawn_shop"
const GUNS := &"mangona_gun_store"

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "businesses: " + description)


func run() -> void:
	var saved_cash := GameState.cash
	var saved_turf := Turf.to_dict()
	var saved_clout := Clout.to_dict()
	var saved_owned := Businesses.to_dict()
	Businesses.clear()
	Clout.clear()
	_test_content()
	_test_placement()
	_test_turf_gating()
	_test_clout_gating()
	_test_purchase_and_cash()
	_test_discount_and_shop()
	_test_income()
	_test_clout_grant()
	await _test_crew()
	_test_tiers()
	_test_save_load()
	await _test_shop_panel()
	Businesses.clear()
	Businesses.from_dict(saved_owned)
	Clout.from_dict(saved_clout)
	Turf.from_dict(saved_turf)
	GameState.cash = saved_cash


func _test_content() -> void:
	_check(Businesses.all_sites().size() == 9, "9 North End sites load (got %d)" % Businesses.all_sites().size())
	_check(ContentDB.all(BusinessTypeDef.TYPE).size() == 10, "10 business types load")
	for district in [BOTTOMS, RAIL_YARDS, OLD_HARBOR]:
		_check(Businesses.sites_in(district).size() == 3, "3 sites in %s" % district)
	_check(Businesses.type_of(GUNS).id == &"gun_store" and Businesses.type_of(GUNS).has_shop(), "gun store type has a shop")
	_check(not Businesses.type_of(&"tamarack_barbershop").has_shop(), "barbershop has no shop")
	var barber_door := Locations.get_location(&"tamarack_barbershop")
	_check(barber_door != null and barber_door.def.all_door_actions().any(func(action: InteractionAction) -> bool:
		return action.id == Businesses.APPEARANCE_ACTION), "barbershop door offers a haircut")


func _test_placement() -> void:
	for business_site in Businesses.all_sites():
		var location := Locations.get_location(business_site.id)
		_check(location != null, "%s is placed in the world" % business_site.id)
		if location != null:
			_check(location.district_id == business_site.district_id, "%s is in its district" % business_site.id)
			_check(location.def.all_door_actions().any(func(action: InteractionAction) -> bool: return action.id == Businesses.BUY_ACTION), "%s door has a buy action" % business_site.id)


func _test_turf_gating() -> void:
	GameState.cash = 1000000
	Turf.set_district_owner(BOTTOMS, GameState.PLAYER_GANG)
	Turf.set_district_owner(RAIL_YARDS, &"vipers")
	_check(Businesses.purchase_block_reason(CORNER) == "", "a site in player turf is buyable")
	var reason := Businesses.purchase_block_reason(PAWN)
	_check(reason != "", "a site in rival turf is blocked (%s)" % reason)
	_check(not Businesses.purchase(PAWN) and not Businesses.is_owned(PAWN), "purchase in rival turf fails")
	Turf.set_district_owner(RAIL_YARDS, GameState.PLAYER_GANG)
	_check(Businesses.purchase_block_reason(PAWN) == "", "taking the district unlocks its sites")
	Turf.set_district_owner(RAIL_YARDS, &"vipers")


func _test_clout_gating() -> void:
	GameState.cash = 1000000
	Turf.set_district_owner(OLD_HARBOR, GameState.PLAYER_GANG)
	Clout.set_clout(OLD_HARBOR, 0)
	_check(Businesses.purchase_block_reason(GUNS) != "", "gun store needs clout in Mangona")
	Clout.set_clout(OLD_HARBOR, 10)
	_check(Businesses.purchase_block_reason(GUNS) == "", "enough clout unlocks the gun store")
	Clout.set_clout(OLD_HARBOR, 0)
	Turf.set_district_owner(OLD_HARBOR, &"syndicate")


func _test_purchase_and_cash() -> void:
	var price := Businesses.price_of(CORNER)
	_check(price == 8000, "corner store costs its base price at tier 1 ($%d)" % price)
	GameState.cash = price - 1
	_check(Businesses.purchase_block_reason(CORNER) != "", "too little cash blocks purchase")
	_check(not Businesses.purchase(CORNER), "purchase without cash fails")
	GameState.cash = price + 100
	_check(Businesses.purchase(CORNER) and Businesses.is_owned(CORNER), "purchase succeeds in player turf")
	_check(GameState.cash == 100, "purchase deducts the price")
	_check(Businesses.purchase_block_reason(CORNER) == "Already yours" and not Businesses.purchase(CORNER), "can't buy an owned site twice")
	var location := Locations.get_location(CORNER)
	_check(location != null and location.owner_gang() == GameState.PLAYER_GANG, "owned site's location belongs to the player")


func _test_discount_and_shop() -> void:
	# CORNER is owned; the pharmacy (same stock items, different site) is not.
	var full := Businesses.shop_price(&"northgrove_pharmacy", &"first_aid")
	var owner := Businesses.shop_price(CORNER, &"first_aid")
	_check(full == 80 and owner == 40, "owned site sells at half price, others full ($%d vs $%d)" % [owner, full])
	_check(Businesses.shop_price(LIQUOR, &"snack") == 15, "discount is per site, not per owner")
	_check(Businesses.buy_item(CORNER, &"pistol") != "", "a shop only sells its own stock")
	var player := GameState.player
	player.health = 10.0
	GameState.cash = 1000
	_check(Businesses.buy_item(CORNER, &"first_aid", player) == "" and GameState.cash == 960, "buying an item charges the owner price")
	_check(player.health > 10.0, "first aid heals the player")
	GameState.cash = 0
	_check(Businesses.buy_item(CORNER, &"first_aid", player) != "", "can't buy without cash")
	GameState.cash = 10000
	_check(Businesses.buy_item(PAWN, &"rifle", player) == "" and player.weapons.find(&"rifle") != null and GameState.cash == 6500, "pawn shop sells a rifle at full price")


func _test_income() -> void:
	var income := Businesses.total_income()
	_check(income == 160, "owned corner store pays its income ($%d)" % income)
	var before := GameState.cash
	var turf_income := Turf.income_for(GameState.PLAYER_GANG)
	GameState.pay_income()
	_check(GameState.cash == before + turf_income + income, "pay_income includes business income")


func _test_clout_grant() -> void:
	_check(Clout.clout_of(BOTTOMS) == 5, "owning the corner store gives Tamarack its clout (%d)" % Clout.clout_of(BOTTOMS))
	Businesses.acquire(LIQUOR)
	_check(Clout.clout_of(BOTTOMS) == 11, "a second site adds its clout")
	_check(Businesses.lose_site(LIQUOR, &"raid") and not Businesses.is_owned(LIQUOR), "a site can be lost")
	_check(Clout.clout_of(BOTTOMS) == 5, "losing a site removes its clout")
	Clout.set_clout(BOTTOMS, 500)
	_check(Clout.clout_of(BOTTOMS) == Clout.MAX_CLOUT, "clout clamps at 100")
	Clout.add(BOTTOMS, -1000)
	_check(Clout.clout_of(BOTTOMS) == 0, "clout clamps at 0")
	Clout.set_clout(BOTTOMS, 5)


func _test_crew() -> void:
	var crew := Businesses.crew_at(CORNER)
	_check(crew.size() == 2, "owned corner store has its hangout crew (%d)" % crew.size())
	_check(crew.all(func(member: Node) -> bool: return member.is_in_group(&"hangout_crew") and not member.is_in_group(&"gang_members")), "hangout crew aren't combat gang members")
	_check(Businesses.crew_at(LIQUOR).is_empty(), "unowned site has no crew")
	Businesses.lose_site(CORNER)
	await _runner.get_tree().process_frame
	_check(Businesses.crew_at(CORNER).is_empty() and Clout.clout_of(BOTTOMS) == 0, "losing a site sends its crew home and its clout")
	Businesses.acquire(CORNER)


func _test_tiers() -> void:
	var area := Turf.area_data(Turf.area_of(BOTTOMS))
	var saved_tier := area.tier
	area.tier = 2
	_check(Businesses.price_of(LIQUOR) == 30000 and Businesses.income_of(CORNER) == 400, "tier 2 multiplies price and income by 2.5")
	_check(Businesses.shop_price(CORNER, &"first_aid") == 100, "shop prices scale with tier too")
	area.tier = saved_tier


func _test_save_load() -> void:
	var data: Dictionary = JSON.parse_string(JSON.stringify({"b": Businesses.to_dict(), "c": Clout.to_dict()}))
	Businesses.clear()
	Clout.clear()
	_check(not Businesses.is_owned(CORNER) and Clout.clout_of(BOTTOMS) == 0, "clear forgets ownership and clout")
	Businesses.from_dict(data["b"])
	Clout.from_dict(data["c"])
	_check(Businesses.is_owned(CORNER) and Businesses.owned_sites().size() == 1, "ownership round-trips through JSON")
	_check(Clout.clout_of(BOTTOMS) == 5, "clout round-trips through JSON without double-granting")


func _test_shop_panel() -> void:
	var tree := _runner.get_tree()
	var was_paused := tree.paused
	Businesses.open_shop(&"tamarack_barbershop")
	_check(Businesses.shop_panel() == null or not Businesses.shop_panel().is_open, "a site without stock has no shop")
	Businesses.open_shop(CORNER, GameState.player)
	var panel := Businesses.shop_panel()
	_check(panel != null and panel.is_open and panel.site_id == CORNER and tree.paused, "shop opens and pauses")
	GameState.cash = 1000
	_check(panel.buy(&"snack") == "" and GameState.cash == 992, "shop panel buys at the owner price")
	panel.close()
	await tree.process_frame
	_check(not panel.is_open and tree.paused == was_paused, "closing the shop restores pause state")
