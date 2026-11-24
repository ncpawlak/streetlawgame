class_name OperationsTests
extends RefCounted
## Tests for the Operations framework (#27): items/stash, crew jobs, production, sales, plugs, risk,
## save/load. Hooked from run_tests.gd. Model tests run on isolated OperationsModel instances
## (dict-backed districts, local crew, seeded rng); the autoload test restores what it touches.

const BOTTOMS := &"the_bottoms"
const RIVERSIDE := &"riverside"
const TRAP := &"bottoms_trap_house"
const LAB := &"riverside_lab"

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run() -> void:
	_test_inventory()
	_test_content()
	_test_plug_gating()
	_test_production()
	_test_district_loss_blocks()
	_test_sales_and_saturation()
	_test_assignment_rules()
	_test_risk()
	_test_plug_pricing()
	_test_save_load()
	await _test_autoload()


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "operations: " + description)


## An isolated model on the real content. Sites lose their risks unless keep_risks, so results are exact.
func _model(keep_risks := false, cash := [1000000]) -> OperationsModel:
	var model := OperationsModel.new()
	model.rng.seed = 12345
	model.districts = DistrictProvider.new()
	model.districts.set_owner(BOTTOMS, OperationsModel.PLAYER_GANG, "The Bottoms")
	model.districts.set_owner(RIVERSIDE, &"syndicate", "Riverside")
	model.spend_cash = func(amount: int) -> bool:
		if cash[0] < amount:
			return false
		cash[0] -= amount
		return true
	if not keep_risks:
		for site_def in model.all_of(OperationsModel.TYPE_SITES):
			var quiet := (site_def as SiteData).duplicate() as SiteData
			quiet.risks = []
			model.add_override(OperationsModel.TYPE_SITES, quiet)
		for job_def in model.all_of(OperationsModel.TYPE_JOBS):
			var quiet_job := (job_def as JobData).duplicate() as JobData
			quiet_job.risks = []
			model.add_override(OperationsModel.TYPE_JOBS, quiet_job)
	model.setup()
	model.drain_events()
	return model


func _member(model: OperationsModel, member_name: String, skills: Dictionary) -> CrewMemberData:
	var member := CrewMemberData.create(member_name, skills)
	model.add_crew(member)
	return member


func _unlock_weed(model: OperationsModel) -> void:
	model.meet_plug(&"weed_plug")
	model.establish_plug(&"weed_plug")


func _events_of(events: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if event.type == type:
			result.append(event)
	return result


func _income(events: Array[Dictionary]) -> int:
	var sum := 0
	for event in _events_of(events, &"income"):
		sum += int(event.amount)
	return sum


func _test_inventory() -> void:
	var stash := Inventory.new()
	stash.capacity = 10
	_check(stash.add(&"weed", 7) == 7 and stash.add(&"coke", 5) == 3, "stash add is limited by capacity")
	_check(stash.free_space() == 0 and stash.total() == 10, "stash tracks total and free space")
	_check(not stash.remove(&"weed", 8) and stash.count(&"weed") == 7, "stash remove is all-or-nothing")
	_check(stash.remove(&"coke", 3) and not stash.item_ids().has(&"coke"), "emptied items leave the stash")
	var copy := Inventory.from_dict(stash.to_dict())
	_check(copy.capacity == 10 and copy.count(&"weed") == 7 and copy.total() == 7, "stash round-trips through to_dict")


func _test_content() -> void:
	var model := _model()
	var missing := PackedStringArray()
	for recipe_def in model.all_of(OperationsModel.TYPE_RECIPES):
		var recipe := recipe_def as RecipeData
		for stack in recipe.inputs + recipe.outputs:
			if model.item(stack.item_id) == null:
				missing.append("%s -> %s" % [recipe.id, stack.item_id])
	for site_id in model.site_ids():
		for job_id in model.site(site_id).allowed_jobs:
			if model.job(job_id) == null:
				missing.append("%s -> %s" % [site_id, job_id])
	for plug_id in model.plug_ids():
		for stack in model.plug(plug_id).supplies:
			if model.item(stack.item_id) == null:
				missing.append("%s -> %s" % [plug_id, stack.item_id])
	_check(missing.is_empty(), "content references resolve (%s)" % ", ".join(missing))
	_check(model.site_ids().has(TRAP) and model.site_ids().has(LAB), "sites load from data/sites")
	_check(model.is_site_acquired(TRAP) and not model.is_site_acquired(LAB), "starts_acquired controls initial ownership")
	_check(model.market_for(RIVERSIDE).district_id == RIVERSIDE and model.market_for(&"nowhere").id == OperationsModel.DEFAULT_MARKET, "markets resolve per district with a default fallback")
	_check(ContentDB.all(&"crew").size() >= 1, "starter crew loads from data/crew")
	var issues := ContentDB.validate()
	_check(issues.is_empty(), "ContentDB.validate() passes with operations content (%s)" % "; ".join(issues))


func _test_plug_gating() -> void:
	var cash := [600]
	var model := _model(false, cash)
	_check(model.is_plug_revealed(&"weed_plug") and not model.is_plug_revealed(&"coke_plug"), "only the starter plug is known at first")
	_check(model.available_recipes(TRAP).is_empty(), "nothing can be made before finding a plug")
	_check(not model.can_establish_plug(&"weed_plug").is_empty(), "a plug must be met in person first")
	model.meet_plug(&"weed_plug")
	_check(model.establish_plug(&"weed_plug") == "" and cash[0] == 100, "establishing a plug charges the buy-in")
	_check(model.has_unlock(&"drug:weed"), "the plug grants its unlock")
	var recipes := model.available_recipes(TRAP)
	_check(recipes.size() == 1 and recipes[0].id == &"grow_weed", "the unlocked recipe runs at the trap house; the lab-only one doesn't")
	var events := model.step(0.0)
	_check(model.is_plug_revealed(&"coke_plug") and _events_of(events, &"plug_revealed").size() == 1, "the next plug reveals once its conditions pass")
	_check(model.establish_plug(&"coke_plug") != "", "an unmet plug can't be established")
	model.meet_plug(&"coke_plug")
	_check(model.establish_plug(&"coke_plug") != "" and not model.has_unlock(&"drug:coke"), "a buy-in you can't afford fails without granting")


func _test_production() -> void:
	var model := _model()
	var rookie := _member(model, "Rookie", {&"cooking": 1})
	_check(model.assign(rookie.id, TRAP, &"cook", {"recipe_id": &"grow_weed"}) == null, "can't cook a locked recipe")
	_unlock_weed(model)
	var job := model.assign(rookie.id, TRAP, &"cook", {"recipe_id": &"grow_weed"})
	_check(job != null, "a cook can be assigned to an unlocked recipe")
	model.step(30.0)
	_check(job.status == JobAssignment.Status.STARVED, "production starves without inputs")
	var stash := model.site_stash(TRAP)
	stash.add(&"grow_kit", 3)
	var events := model.step(30.0)
	_check(stash.count(&"weed") == 8 and stash.count(&"grow_kit") == 1, "a waiting cycle completes immediately, then one more per cycle")
	_check(_events_of(events, &"production_completed").size() == 2 and job.status == JobAssignment.Status.ACTIVE, "production completes cycles and recovers from STARVED")
	_check(model.site_heat(TRAP) > 0.0, "production adds heat")
	stash.capacity = stash.total() + 1
	model.step(30.0)
	_check(job.status == JobAssignment.Status.FULL and stash.count(&"grow_kit") == 1, "production stops (keeping inputs) when the stash is full")

	var skilled_model := _model()
	_unlock_weed(skilled_model)
	var pro := _member(skilled_model, "Pro", {&"cooking": 10})
	skilled_model.site_stash(TRAP).add(&"grow_kit", 50)
	skilled_model.assign(pro.id, TRAP, &"cook", {"recipe_id": &"grow_weed"})
	var slow_model := _model()
	_unlock_weed(slow_model)
	var novice := _member(slow_model, "Novice", {&"cooking": 1})
	slow_model.site_stash(TRAP).add(&"grow_kit", 50)
	slow_model.assign(novice.id, TRAP, &"cook", {"recipe_id": &"grow_weed"})
	skilled_model.step(300.0)
	slow_model.step(300.0)
	_check(skilled_model.site_stash(TRAP).count(&"weed") > slow_model.site_stash(TRAP).count(&"weed"), "higher cooking skill produces faster")
	_check(novice.skill_for(&"cooking") > 1 or int(novice.xp.get(&"cooking", 0)) > 0, "work grants crew xp")


func _test_district_loss_blocks() -> void:
	var model := _model()
	_unlock_weed(model)
	var cook := _member(model, "Cook", {&"cooking": 1})
	var job := model.assign(cook.id, TRAP, &"cook", {"recipe_id": &"grow_weed"})
	model.site_stash(TRAP).add(&"grow_kit", 5)
	model.districts.set_owner(BOTTOMS, &"syndicate")
	model.step(60.0)
	_check(job.status == JobAssignment.Status.BLOCKED and job.status_reason.contains("The Bottoms"), "losing the district blocks its sites")
	_check(model.site_stash(TRAP).count(&"weed") == 0, "blocked sites don't produce")
	model.districts.set_owner(BOTTOMS, OperationsModel.PLAYER_GANG)
	model.step(30.0)
	_check(job.status == JobAssignment.Status.ACTIVE and model.site_stash(TRAP).count(&"weed") > 0, "retaking the district resumes work")


func _test_sales_and_saturation() -> void:
	var model := _model()
	var dealer := _member(model, "Dealer", {&"dealing": 1})
	_check(model.assign(dealer.id, TRAP, &"dealer", {"district_id": RIVERSIDE}) == null, "can't deal in a district you don't control")
	var fresh_price := model.quote(BOTTOMS, &"weed")
	var job := model.assign(dealer.id, TRAP, &"dealer", {"district_id": BOTTOMS})
	_check(job != null, "a dealer can work a district you control")
	model.site_stash(TRAP).add(&"weed", 20)
	var events := model.step(60.0)
	var sold := 20 - model.site_stash(TRAP).count(&"weed")
	_check(sold == 6, "a skill-1 dealer sells units_per_minute (sold %d)" % sold)
	_check(_income(events) > 0 and _events_of(events, &"sale_completed").size() >= 1, "sales pay the player")
	_check(model.market_saturation(BOTTOMS, &"weed") > 0.0 and model.quote(BOTTOMS, &"weed") < fresh_price, "selling saturates the market and lowers the price")
	_check(model.quote(RIVERSIDE, &"coke") > model.quote(BOTTOMS, &"coke"), "district demand changes prices")
	model.site_stash(TRAP).remove(&"weed", model.site_stash(TRAP).count(&"weed"))
	model.step(20.0)
	_check(job.status == JobAssignment.Status.STARVED, "dealers starve without product")
	model.unassign(job.id)
	model.step(600.0)
	_check(is_zero_approx(model.market_saturation(BOTTOMS, &"weed")) and model.quote(BOTTOMS, &"weed") == fresh_price, "market saturation recovers over time")


func _test_assignment_rules() -> void:
	var cash := [0]
	var model := _model(false, cash)
	var first := _member(model, "First", {})
	_check(model.assign(first.id, TRAP, &"guard") != null, "a guard can be assigned")
	_check(model.can_assign(first.id, TRAP, &"dealer", {"district_id": BOTTOMS}) != "", "a crew member works one job at a time")
	_check(model.can_assign(first.id, LAB, &"guard") != "", "jobs need a site you own")
	for i in model.site(TRAP).max_workers - 1:
		model.assign(_member(model, "Extra %d" % i, {}).id, TRAP, &"guard")
	_check(model.can_assign(_member(model, "Late", {}).id, TRAP, &"guard") != "", "sites have a worker limit")
	var jailed := _member(model, "Jailed", {})
	jailed.status = CrewMemberData.Status.ARRESTED
	_check(model.can_assign(jailed.id, TRAP, &"guard").contains("arrested"), "unavailable crew can't be assigned")
	_check(model.acquire_site(LAB) != "", "you can't buy a site in a district you don't control")
	model.districts.set_owner(RIVERSIDE, OperationsModel.PLAYER_GANG, "Riverside")
	_check(model.acquire_site(LAB) != "" and not model.is_site_acquired(LAB), "buying a site needs the cash")
	cash[0] = model.site(LAB).acquire_price
	_check(model.acquire_site(LAB) == "" and model.is_site_acquired(LAB) and cash[0] == 0, "buying a site charges its price")
	_check(model.unassign_crew(first.id) and model.assignment_for_crew(first.id) == null, "crew can be pulled off a job")


func _test_risk() -> void:
	var raid := RiskData.new()
	raid.chance_per_minute = 0.1
	raid.heat_multiplier = 0.0
	raid.guard_mitigation = 0.5
	_check(is_equal_approx(raid.chance(0.0, 0.0, 60.0), 0.1), "risk chance scales with time")
	_check(is_equal_approx(raid.chance(0.0, 1.0, 60.0), 0.05), "guards mitigate risk")
	raid.heat_multiplier = 0.01
	_check(raid.chance(50.0, 0.0, 60.0) > 0.1, "heat raises risk")

	var model := _model()
	_unlock_weed(model)
	var certain := RiskData.new()
	certain.id = &"test_bust"
	certain.chance_per_minute = 1000.0
	certain.heat_multiplier = 0.0
	certain.guard_mitigation = 0.0
	var seize := SeizeStockEffect.new()
	seize.fraction = 0.5
	var arrest := ArrestCrewEffect.new()
	arrest.jail_seconds = 30.0
	certain.effects.assign([seize, arrest])
	certain.notify_text = "Bust at {site_name}: {crew_name}"
	var risky := model.site(TRAP).duplicate() as SiteData
	risky.risks.assign([certain])
	model.add_override(OperationsModel.TYPE_SITES, risky)
	var victim := _member(model, "Victim", {})
	model.assign(victim.id, TRAP, &"guard")
	model.site_stash(TRAP).add(&"weed", 10)
	var events := model.step(1.0)
	var risk_events := _events_of(events, &"operation_risk")
	_check(risk_events.size() == 1 and String(risk_events[0].text) == "Bust at Bottoms Trap House: Victim", "risks fire and format their notification")
	_check(model.site_stash(TRAP).count(&"weed") == 5, "a seizure takes stock")
	_check(victim.status == CrewMemberData.Status.ARRESTED and model.assignment_for_crew(victim.id) == null, "an arrest pulls the crew member off the job")
	events = model.step(31.0)
	_check(victim.status == CrewMemberData.Status.ACTIVE and _events_of(events, &"crew_released").size() == 1, "jailed crew are released after their sentence")
	_check(_events_of(model.step(60.0), &"operation_risk").is_empty(), "idle sites aren't at risk")


func _test_plug_pricing() -> void:
	var model := _model()
	_check(model.plug_price(&"weed_plug", &"grow_kit") == -1, "plugs don't sell before the deal")
	_unlock_weed(model)
	var start_price := model.plug_price(&"weed_plug", &"grow_kit")
	_check(start_price > 0 and model.plug_price(&"weed_plug", &"coca_paste") == -1, "plugs sell only their supplies")
	var relationship := model.plug_relationship(&"weed_plug")
	_check(model.buy_supplies(&"weed_plug", &"grow_kit", 5, TRAP) == "" and model.site_stash(TRAP).count(&"grow_kit") == 5, "supplies are dropped at your site")
	_check(model.plug_relationship(&"weed_plug") > relationship, "orders improve the relationship")
	model.change_relationship(&"weed_plug", 100.0)
	_check(model.plug_price(&"weed_plug", &"grow_kit") < start_price, "a better relationship lowers prices")
	model.change_relationship(&"weed_plug", -100.0)
	_check(model.plug_price(&"weed_plug", &"grow_kit") == -1 and model.buy_supplies(&"weed_plug", &"grow_kit", 1, TRAP) != "", "a plug cuts you off below the cutoff")
	_check(model.buy_supplies(&"weed_plug", &"grow_kit", 1, LAB) != "", "drops need a site you own")


## Crew live in GameState (saved separately), so a restored model is given copies of the crew.
func _busy_model(crew_from: OperationsModel = null) -> OperationsModel:
	var model := _model(true)
	_unlock_weed(model)
	if crew_from != null:
		for member in crew_from.all_crew():
			model.add_crew(CrewMemberData.from_dict(member.to_dict()))
		return model
	var cook := CrewMemberData.new()
	cook.id = &"save_cook"
	cook.skills = {&"cooking": 2}
	var dealer := CrewMemberData.new()
	dealer.id = &"save_dealer"
	dealer.skills = {&"dealing": 2}
	model.add_crew(cook)
	model.add_crew(dealer)
	model.site_stash(TRAP).add(&"grow_kit", 40)
	model.assign(cook.id, TRAP, &"cook", {"recipe_id": &"grow_weed"})
	model.assign(dealer.id, TRAP, &"dealer", {"district_id": BOTTOMS})
	return model


func _test_save_load() -> void:
	var original := _busy_model()
	original.step(45.0)
	var saved := original.to_dict()
	_check(JSON.parse_string(JSON.stringify(saved)) is Dictionary, "operations state is JSON-safe")
	var restored := _busy_model(original)
	restored.from_dict(JSON.parse_string(JSON.stringify(saved, "", true, true)))
	_check(var_to_str(restored.to_dict()) == var_to_str(saved), "from_dict(to_dict()) restores the same state")
	for i in 20:
		original.step(3.0)
		restored.step(3.0)
	_check(var_to_str(restored.to_dict()) == var_to_str(original.to_dict()), "a restored model simulates identically (seeded rng)")

	var big := _model()
	var small := _model()
	for model: OperationsModel in [big, small]:
		_unlock_weed(model)
		var cook := _member(model, "Cook", {&"cooking": 3})
		model.site_stash(TRAP).add(&"grow_kit", 20)
		model.assign(cook.id, TRAP, &"cook", {"recipe_id": &"grow_weed"})
	big.step(240.0)
	for i in 240:
		small.step(1.0)
	_check(big.site_stash(TRAP).count(&"weed") == small.site_stash(TRAP).count(&"weed") and big.site_stash(TRAP).count(&"weed") > 0, "one long step matches many short ones (offline catch-up)")


func _test_autoload() -> void:
	var operations: Node = _runner.get_node_or_null("/root/Operations")
	_check(operations != null and operations.get("model") is OperationsModel, "Operations autoload runs a model")
	if operations == null:
		return
	var model: OperationsModel = operations.get("model")
	var saved: Dictionary = operations.call("to_dict")
	var saved_cash: int = GameState.cash
	var saved_crew: Array[CrewMemberData] = GameState.crew.duplicate()
	var starters := 0
	for member in GameState.crew:
		starters += 1 if member.starter else 0
	_check(starters == ContentDB.all(&"crew").size(), "starter crew join the gang")
	_check(model.is_site_acquired(TRAP) and model.is_plug_revealed(&"weed_plug"), "the game starts with a trap house and a known plug")

	model.add_income(250, TRAP)
	operations.call("apply_events")
	_check(GameState.cash == saved_cash + 250, "operations income reaches GameState")

	var tree := _runner.get_tree()
	var was_paused := tree.paused
	operations.call("open_site_panel", TRAP)
	await _runner.get_tree().process_frame
	var panel: OperationsPanel = operations.get("panel")
	_check(panel != null and panel.is_open and tree.paused, "the site panel opens and pauses the game")
	panel.close()
	_check(not panel.is_open and tree.paused == was_paused, "closing the panel restores pause state")

	operations.call("from_dict", saved)
	GameState.cash = saved_cash
	GameState.crew.assign(saved_crew)
