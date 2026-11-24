class_name OperationsModel
extends RefCounted
## Pure, seeded simulation of the player's criminal operations: sites and their stashes, crew job
## assignments, production, street sales, plugs/suppliers, unlocks and risk events.
##
## It never touches the scene tree or autoloads directly (content, crew, cash and districts are
## injected), so it runs headless in tests and can be stepped in big chunks for offline catch-up.
## Side effects for the rest of the game are returned from step() as event Dictionaries
## ({"type": &"sale_completed", ...}); the Operations autoload forwards them to EventBus/GameState.

const PLAYER_GANG := &"player"
const TYPE_ITEMS := &"items"
const TYPE_RECIPES := &"recipes"
const TYPE_JOBS := &"jobs"
const TYPE_SITES := &"sites"
const TYPE_PLUGS := &"plugs"
const TYPE_MARKETS := &"markets"
const DEFAULT_MARKET := &"default"

var rng := RandomNumberGenerator.new()
var districts: DistrictProvider = DistrictProvider.new()
## (type: StringName, id: StringName) -> Resource or null. Defaults to ContentDB.find_def.
var content: Callable
## (type: StringName) -> Array of Resources. Defaults to ContentDB.all.
var content_all: Callable
## () -> Array of CrewMemberData the player can assign. Defaults to members added with add_crew().
var crew_source: Callable
## (amount: int) -> bool. Takes player cash; defaults to always succeeding.
var spend_cash: Callable
## Extra content that wins over `content` (tests, mods, runtime-generated defs): type -> {id: res}.
var overrides := {}

var _sites := {}
var _assignments: Array[JobAssignment] = []
var _unlocks := {}
var _plugs := {}
var _saturation := {}
var _jailed := {}
var _next_assignment_id := 1
var _events: Array[Dictionary] = []
var _local_crew: Array[CrewMemberData] = []
var _market_cache := {}
var _default_pricing := DemandPricingModel.new()


func _init() -> void:
	content = func(type: StringName, id: StringName) -> Resource:
		var db := _content_db()
		return db.call("find_def", type, id) if db != null else null
	content_all = func(type: StringName) -> Array:
		var db := _content_db()
		return db.call("all", type) if db != null else []
	crew_source = func() -> Array: return _local_crew
	spend_cash = func(_amount: int) -> bool: return true


## The ContentDB autoload, looked up at runtime so the model compiles without autoloads (tools, tests).
static func _content_db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("ContentDB") if tree != null else null


## Finds the model for a Condition/Effect context: ctx.vars.model, else the Operations autoload's.
static func from_context(ctx: ActionContext) -> OperationsModel:
	if ctx != null and ctx.vars.get("model") is OperationsModel:
		return ctx.vars["model"]
	var service := service_node()
	return service.get("model") if service != null else null


## The Operations autoload, or null when running without it (tests, tools).
static func service_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Operations") if tree != null else null


## Creates runtime state for every site and evaluates which plugs are revealed. Safe to re-run.
func setup() -> void:
	_market_cache.clear()
	for site_def in all_of(TYPE_SITES):
		var site_data := site_def as SiteData
		if site_data != null and not _sites.has(site_data.id):
			var state := SiteState.new()
			state.acquired = site_data.starts_acquired
			_attach_state(site_data.id, state)
	for plug_def in all_of(TYPE_PLUGS):
		var plug_data := plug_def as PlugData
		if plug_data != null and not _plugs.has(plug_data.id):
			_plugs[plug_data.id] = {"revealed": false, "met": false, "established": false, "relationship": plug_data.starting_relationship}
	refresh_plugs()


#region Content

func def(type: StringName, id: StringName) -> Resource:
	if id.is_empty():
		return null
	var local: Dictionary = overrides.get(type, {})
	if local.has(id):
		return local[id]
	return content.call(type, id)


func all_of(type: StringName) -> Array[Resource]:
	var merged := {}
	for res: Resource in content_all.call(type):
		merged[StringName(str(res.get("id")))] = res
	merged.merge(overrides.get(type, {}), true)
	var ids: Array = merged.keys()
	ids.sort()
	var result: Array[Resource] = []
	for id: StringName in ids:
		result.append(merged[id])
	return result


func add_override(type: StringName, res: ContentDef) -> void:
	if not overrides.has(type):
		overrides[type] = {}
	overrides[type][res.id] = res
	_market_cache.clear()


func item(id: StringName) -> ItemData:
	return def(TYPE_ITEMS, id) as ItemData


func recipe(id: StringName) -> RecipeData:
	return def(TYPE_RECIPES, id) as RecipeData


func job(id: StringName) -> JobData:
	return def(TYPE_JOBS, id) as JobData


func site(id: StringName) -> SiteData:
	return def(TYPE_SITES, id) as SiteData


func plug(id: StringName) -> PlugData:
	return def(TYPE_PLUGS, id) as PlugData

#endregion

#region Crew

func add_crew(member: CrewMemberData) -> void:
	_local_crew.append(member)


func crew(id: StringName) -> CrewMemberData:
	if id.is_empty():
		return null
	for member: CrewMemberData in crew_source.call():
		if member.id == id:
			return member
	return null


func all_crew() -> Array[CrewMemberData]:
	var result: Array[CrewMemberData] = []
	result.assign(crew_source.call())
	return result


func jail_time_left(crew_id: StringName) -> float:
	return _jailed.get(crew_id, 0.0)


func jail(crew_id: StringName, seconds: float) -> void:
	var member := crew(crew_id)
	if member == null:
		return
	member.status = CrewMemberData.Status.ARRESTED
	unassign_crew(crew_id)
	if seconds > 0.0:
		_jailed[crew_id] = seconds
	emit_event(&"crew_arrested", {"crew_id": crew_id, "seconds": seconds})

#endregion

#region Sites

func site_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_sites.keys())
	ids.sort()
	return ids


func site_state(site_id: StringName) -> SiteState:
	return _sites.get(site_id)


func is_site_acquired(site_id: StringName) -> bool:
	return _sites.has(site_id) and site_state(site_id).acquired


func site_stash(site_id: StringName) -> Inventory:
	return site_state(site_id).stash if _sites.has(site_id) else null


func site_heat(site_id: StringName) -> float:
	return site_state(site_id).heat if _sites.has(site_id) else 0.0


## "" when the player can buy the site now, otherwise why not.
func can_acquire_site(site_id: StringName) -> String:
	var site_data := site(site_id)
	if site_data == null or not _sites.has(site_id):
		return "Unknown place"
	if is_site_acquired(site_id):
		return "Already yours"
	var ctx := context(site_id)
	for condition in site_data.acquire_conditions:
		if not condition.is_met(ctx):
			return condition.reason(ctx)
	return ""


## Buys a site (charging acquire_price unless free). Returns "" on success or the failure reason.
func acquire_site(site_id: StringName, free := false) -> String:
	var reason := can_acquire_site(site_id)
	if not reason.is_empty():
		return reason
	var price := site(site_id).acquire_price
	if not free and price > 0 and not spend_cash.call(price):
		return "Not enough cash ($%d)" % price
	site_state(site_id).acquired = true
	emit_event(&"site_acquired", {"site_id": site_id})
	return ""

#endregion

#region Jobs

func assignments() -> Array[JobAssignment]:
	return _assignments.duplicate()


func assignments_at(site_id: StringName) -> Array[JobAssignment]:
	var result: Array[JobAssignment] = []
	for assignment in _assignments:
		if assignment.site_id == site_id:
			result.append(assignment)
	return result


func assignment_for_crew(crew_id: StringName) -> JobAssignment:
	if crew_id.is_empty():
		return null
	for assignment in _assignments:
		if assignment.crew_id == crew_id:
			return assignment
	return null


func get_assignment(assignment_id: int) -> JobAssignment:
	for assignment in _assignments:
		if assignment.id == assignment_id:
			return assignment
	return null


## Jobs that may run at a site, in id order.
func available_jobs(site_id: StringName) -> Array[JobData]:
	var site_data := site(site_id)
	var result: Array[JobData] = []
	if site_data == null:
		return result
	for job_def in all_of(TYPE_JOBS):
		var job_data := job_def as JobData
		if job_data != null and (site_data.allowed_jobs.is_empty() or site_data.allowed_jobs.has(job_data.id)):
			result.append(job_data)
	return result


## Recipes the player can currently run at a site.
func available_recipes(site_id: StringName) -> Array[RecipeData]:
	var site_data := site(site_id)
	var result: Array[RecipeData] = []
	for recipe_def in all_of(TYPE_RECIPES):
		var recipe_data := recipe_def as RecipeData
		if recipe_data != null and site_data != null and recipe_block_reason(recipe_data, site_data).is_empty():
			result.append(recipe_data)
	return result


func recipe_block_reason(recipe_data: RecipeData, site_data: SiteData) -> String:
	for unlock_id in recipe_data.required_unlocks:
		if not has_unlock(unlock_id):
			return "Find a plug for %s first" % recipe_data.display_name
	if not recipe_data.site_tags.is_empty():
		var matched := false
		for tag in recipe_data.site_tags:
			matched = matched or site_data.tags.has(tag)
		if not matched:
			return "Can't make %s here" % recipe_data.display_name
	return ""


func workers_at(site_id: StringName) -> int:
	var workers := 0
	for assignment in assignments_at(site_id):
		var job_data := job(assignment.job_id)
		if job_data != null and job_data.requires_crew:
			workers += 1
	return workers


## "" when the assignment would be accepted, otherwise why not.
func can_assign(crew_id: StringName, site_id: StringName, job_id: StringName, params := {}) -> String:
	var site_data := site(site_id)
	var job_data := job(job_id)
	if site_data == null or job_data == null or job_data.behavior == null:
		return "Unknown job"
	if not is_site_acquired(site_id):
		return "You don't own %s" % site_data.display_name
	if not site_data.allowed_jobs.is_empty() and not site_data.allowed_jobs.has(job_id):
		return "%s can't be done at %s" % [job_data.display_name, site_data.display_name]
	if job_data.requires_crew:
		var member := crew(crew_id)
		if member == null:
			return "Pick a crew member"
		if not member.is_available():
			return "%s is %s" % [member.display_name, String(CrewMemberData.Status.keys()[member.status]).to_lower()]
		var current := assignment_for_crew(crew_id)
		if current != null:
			return "%s is already working at %s" % [member.display_name, site(current.site_id).display_name]
		if workers_at(site_id) >= site_data.max_workers:
			return "%s is fully staffed" % site_data.display_name
	elif not crew_id.is_empty():
		return "%s doesn't need crew" % job_data.display_name
	var preview := JobAssignment.new()
	preview.crew_id = crew_id
	preview.site_id = site_id
	preview.job_id = job_id
	preview.params = params.duplicate()
	return _block_reason(context(site_id, preview))


## Starts a job. Returns the new assignment, or null (see can_assign for why).
func assign(crew_id: StringName, site_id: StringName, job_id: StringName, params := {}) -> JobAssignment:
	if not can_assign(crew_id, site_id, job_id, params).is_empty():
		return null
	var assignment := JobAssignment.new()
	assignment.id = _next_assignment_id
	_next_assignment_id += 1
	assignment.crew_id = crew_id
	assignment.site_id = site_id
	assignment.job_id = job_id
	assignment.params = params.duplicate()
	_assignments.append(assignment)
	emit_event(&"job_assigned", {"assignment_id": assignment.id, "crew_id": crew_id, "site_id": site_id, "job_id": job_id})
	return assignment


func unassign(assignment_id: int) -> bool:
	var assignment := get_assignment(assignment_id)
	if assignment == null:
		return false
	_assignments.erase(assignment)
	emit_event(&"job_unassigned", {"assignment_id": assignment.id, "crew_id": assignment.crew_id, "site_id": assignment.site_id, "job_id": assignment.job_id})
	return true


func unassign_crew(crew_id: StringName) -> bool:
	var assignment := assignment_for_crew(crew_id)
	return assignment != null and unassign(assignment.id)


func set_status(assignment: JobAssignment, status: JobAssignment.Status, reason: String = "") -> void:
	if assignment.status == status and assignment.status_reason == reason:
		return
	assignment.status = status
	assignment.status_reason = reason
	emit_event(&"job_status_changed", {"assignment_id": assignment.id, "site_id": assignment.site_id, "status": status, "reason": reason})


## Status line for the UI.
func describe(assignment: JobAssignment) -> String:
	if assignment.status != JobAssignment.Status.ACTIVE:
		return assignment.status_reason
	var job_data := job(assignment.job_id)
	return job_data.behavior.describe(context(assignment.site_id, assignment)) if job_data != null else ""

#endregion

#region Unlocks and plugs

func has_unlock(unlock_id: StringName) -> bool:
	return _unlocks.has(unlock_id)


func grant_unlock(unlock_id: StringName) -> void:
	if unlock_id.is_empty() or has_unlock(unlock_id):
		return
	_unlocks[unlock_id] = true
	emit_event(&"unlock_granted", {"unlock_id": unlock_id})


func unlocks() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_unlocks.keys())
	ids.sort()
	return ids


## Reveals plugs whose reveal_conditions now pass.
func refresh_plugs() -> void:
	for plug_id: StringName in _plugs:
		if not _plugs[plug_id].revealed:
			var plug_data := plug(plug_id)
			if plug_data != null and _all_met(plug_data.reveal_conditions, context(&"")):
				reveal_plug(plug_id)


func reveal_plug(plug_id: StringName) -> void:
	if _plugs.has(plug_id) and not _plugs[plug_id].revealed:
		_plugs[plug_id].revealed = true
		emit_event(&"plug_revealed", {"plug_id": plug_id, "location_id": plug(plug_id).location_id})


func plug_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_plugs.keys())
	ids.sort()
	return ids


func is_plug_revealed(plug_id: StringName) -> bool:
	return _plugs.has(plug_id) and _plugs[plug_id].revealed


func is_plug_established(plug_id: StringName) -> bool:
	return _plugs.has(plug_id) and _plugs[plug_id].established


## Records an in-person meeting (the MeetPlugEffect on the plug's location).
func meet_plug(plug_id: StringName) -> void:
	if _plugs.has(plug_id):
		reveal_plug(plug_id)
		_plugs[plug_id].met = true


func has_met_plug(plug_id: StringName) -> bool:
	return _plugs.has(plug_id) and _plugs[plug_id].met


## "" when the player can strike the buy-in deal now, otherwise why not.
func can_establish_plug(plug_id: StringName) -> String:
	var plug_data := plug(plug_id)
	if plug_data == null or not _plugs.has(plug_id):
		return "Unknown contact"
	if is_plug_established(plug_id):
		return "Already in business"
	if not is_plug_revealed(plug_id):
		return "You don't know anyone yet"
	if plug_data.requires_meeting and not has_met_plug(plug_id):
		return "Meet %s in person first" % plug_data.display_name
	return ""


## Pays the buy-in and grants the plug's unlocks. Returns "" on success or the failure reason.
func establish_plug(plug_id: StringName) -> String:
	var reason := can_establish_plug(plug_id)
	if not reason.is_empty():
		return reason
	var plug_data := plug(plug_id)
	if plug_data.buy_in_price > 0 and not spend_cash.call(plug_data.buy_in_price):
		return "Not enough cash ($%d)" % plug_data.buy_in_price
	_plugs[plug_id].established = true
	emit_event(&"plug_established", {"plug_id": plug_id})
	for unlock_id in plug_data.grants_unlocks:
		grant_unlock(unlock_id)
	return ""


func plug_relationship(plug_id: StringName) -> float:
	return _plugs[plug_id].relationship if _plugs.has(plug_id) else 0.0


func change_relationship(plug_id: StringName, delta: float) -> void:
	if not _plugs.has(plug_id) or is_zero_approx(delta):
		return
	var value := clampf(plug_relationship(plug_id) + delta, 0.0, 100.0)
	_plugs[plug_id].relationship = value
	emit_event(&"plug_relationship_changed", {"plug_id": plug_id, "relationship": value})


## Unit price the plug charges for an item, or -1 when they won't sell it to you.
func plug_price(plug_id: StringName, item_id: StringName) -> int:
	var plug_data := plug(plug_id)
	var item_data := item(item_id)
	if plug_data == null or item_data == null or not is_plug_established(plug_id):
		return -1
	if plug_relationship(plug_id) < plug_data.cutoff_relationship or not _sells(plug_data, item_id):
		return -1
	var weight := plug_relationship(plug_id) / 100.0
	var factor := lerpf(plug_data.price_at_min_relationship, plug_data.price_at_max_relationship, weight)
	return maxi(1, roundi(item_data.base_value * plug_data.price_multiplier * factor))


## Orders supplies delivered to a site's stash. Returns "" on success or the failure reason.
func buy_supplies(plug_id: StringName, item_id: StringName, amount: int, site_id: StringName) -> String:
	if amount <= 0:
		return "Nothing to buy"
	if not is_site_acquired(site_id):
		return "Pick one of your places for the drop"
	var price := plug_price(plug_id, item_id)
	if price < 0:
		var plug_data := plug(plug_id)
		return "%s won't deal with you" % (plug_data.display_name if plug_data != null else "They")
	var stash := site_stash(site_id)
	if stash.free_space() < amount:
		return "Not enough room in the stash"
	if not spend_cash.call(price * amount):
		return "Not enough cash ($%d)" % (price * amount)
	stash.add(item_id, amount)
	change_relationship(plug_id, plug(plug_id).relationship_per_order)
	emit_event(&"supplies_bought", {"plug_id": plug_id, "item_id": item_id, "amount": amount, "site_id": site_id, "cost": price * amount})
	return ""

#endregion

#region Markets

func market_for(district_id: StringName) -> MarketProfile:
	if _market_cache.has(district_id):
		return _market_cache[district_id]
	var found: MarketProfile = null
	for market_def in all_of(TYPE_MARKETS):
		var market := market_def as MarketProfile
		if market != null and market.district_id == district_id and not district_id.is_empty():
			found = market
	if found == null:
		found = def(TYPE_MARKETS, DEFAULT_MARKET) as MarketProfile
	if found == null:
		found = MarketProfile.new()
	_market_cache[district_id] = found
	return found


func market_saturation(district_id: StringName, item_id: StringName) -> float:
	return _saturation.get(district_id, {}).get(item_id, 0.0)


## What one unit of an item fetches in a district right now.
func quote(district_id: StringName, item_id: StringName, seller_skill := 1, pricing: PricingModel = null) -> int:
	var item_data := item(item_id)
	if item_data == null:
		return 0
	var model := pricing if pricing != null else _default_pricing
	return model.unit_price(item_data, market_for(district_id), market_saturation(district_id, item_id), seller_skill)


func record_sale(district_id: StringName, item_id: StringName, units: int) -> void:
	if not _saturation.has(district_id):
		_saturation[district_id] = {}
	var market := market_for(district_id)
	_saturation[district_id][item_id] = minf(1.0, market_saturation(district_id, item_id) + market.saturation_per_unit * units)

#endregion

#region Simulation

## Player income (negative = loss) produced by operations; applied by the Operations autoload.
func add_income(amount: int, site_id: StringName = &"") -> void:
	if amount != 0:
		emit_event(&"income", {"amount": amount, "site_id": site_id})


func emit_event(type: StringName, data := {}) -> void:
	var event := data.duplicate()
	event["type"] = type
	_events.append(event)


## Events produced since the last drain (also returned by step()).
func drain_events() -> Array[Dictionary]:
	var drained := _events
	_events = []
	return drained


## Advances the simulation. Large steps are fine: progress is fractional and rates are linear.
## Returns (and clears) the events produced since the last drain.
func step(seconds: float) -> Array[Dictionary]:
	seconds = maxf(seconds, 0.0)
	_recover_markets(seconds)
	_release_jailed(seconds)
	refresh_plugs()
	for assignment in _assignments.duplicate():
		if _assignments.has(assignment):
			_run(assignment, seconds)
	for site_id in site_ids():
		var state := site_state(site_id)
		var site_data := site(site_id)
		if state.heat > 0.0 and site_data != null:
			state.heat = maxf(0.0, state.heat - site_data.heat_decay_per_minute * seconds / 60.0)
	if seconds > 0.0:
		_roll_risks(seconds)
	return drain_events()


## Builds the context used by behaviours, conditions and effects for a site (and assignment).
func context(site_id: StringName, assignment: JobAssignment = null) -> JobContext:
	var ctx := JobContext.new()
	ctx.model = self
	ctx.rng = rng
	ctx.site = site(site_id)
	ctx.state = site_state(site_id)
	ctx.assignment = assignment
	ctx.vars["model"] = self
	if ctx.site != null:
		ctx.vars["site_id"] = ctx.site.id
		ctx.vars["site_name"] = ctx.site.display_name
		ctx.vars["district_id"] = ctx.site.district_id
		ctx.vars["district_name"] = districts.display_name(ctx.site.district_id)
	if assignment != null:
		ctx.job = job(assignment.job_id)
		ctx.crew = crew(assignment.crew_id)
		ctx.vars["job_id"] = assignment.job_id
		var district_param: StringName = assignment.param("district_id", &"")
		if not district_param.is_empty():
			ctx.vars["district_id"] = district_param
			ctx.vars["district_name"] = districts.display_name(district_param)
	if ctx.crew != null:
		ctx.vars["crew_id"] = ctx.crew.id
		ctx.vars["crew_name"] = ctx.crew.display_name
	return ctx


func _run(assignment: JobAssignment, seconds: float) -> void:
	var ctx := context(assignment.site_id, assignment)
	if ctx.job == null or ctx.site == null or ctx.job.behavior == null:
		set_status(assignment, JobAssignment.Status.BLOCKED, "Missing content")
		return
	if ctx.job.requires_crew and (ctx.crew == null or not ctx.crew.is_available()):
		set_status(assignment, JobAssignment.Status.BLOCKED, "Crew unavailable")
		return
	var reason := _block_reason(ctx)
	if not reason.is_empty():
		set_status(assignment, JobAssignment.Status.BLOCKED, reason)
		return
	if assignment.status == JobAssignment.Status.BLOCKED:
		set_status(assignment, JobAssignment.Status.ACTIVE)
	ctx.job.behavior.tick(ctx, seconds)


func _block_reason(ctx: JobContext) -> String:
	if not ctx.state.acquired:
		return "You lost %s" % ctx.site.display_name
	for condition in ctx.site.operate_conditions:
		if not condition.is_met(ctx):
			return condition.reason(ctx)
	for condition in ctx.job.conditions:
		if not condition.is_met(ctx):
			return condition.reason(ctx)
	return ctx.job.behavior.validate(ctx)


func _roll_risks(seconds: float) -> void:
	for site_id in site_ids():
		var running: Array[JobAssignment] = []
		for assignment in assignments_at(site_id):
			if assignment.status == JobAssignment.Status.ACTIVE:
				running.append(assignment)
		if running.is_empty():
			continue
		var site_data := site(site_id)
		var mitigation := 0.0
		var risks: Array[RiskData] = []
		risks.append_array(site_data.risks)
		var seen_jobs := {}
		for assignment in running:
			var ctx := context(site_id, assignment)
			mitigation += ctx.job.behavior.risk_mitigation(ctx)
			if not seen_jobs.has(ctx.job.id):
				seen_jobs[ctx.job.id] = true
				risks.append_array(ctx.job.risks)
		for risk in risks:
			if rng.randf() >= risk.chance(site_heat(site_id), mitigation, seconds):
				continue
			var victim := running[rng.randi_range(0, running.size() - 1)]
			var ctx := context(site_id, victim)
			for effect in risk.effects:
				effect.apply(ctx)
			emit_event(&"operation_risk", {"risk_id": risk.id, "site_id": site_id, "crew_id": victim.crew_id, "text": ctx.format(risk.notify_text)})


func _recover_markets(seconds: float) -> void:
	for district_id: StringName in _saturation:
		var recovery := market_for(district_id).saturation_recovery_per_minute * seconds / 60.0
		var items: Dictionary = _saturation[district_id]
		for item_id: StringName in items.keys():
			items[item_id] = maxf(0.0, items[item_id] - recovery)
			if is_zero_approx(items[item_id]):
				items.erase(item_id)


func _release_jailed(seconds: float) -> void:
	for crew_id: StringName in _jailed.keys():
		_jailed[crew_id] -= seconds
		if _jailed[crew_id] <= 0.0:
			_jailed.erase(crew_id)
			var member := crew(crew_id)
			if member != null and member.status == CrewMemberData.Status.ARRESTED:
				member.status = CrewMemberData.Status.ACTIVE
				emit_event(&"crew_released", {"crew_id": crew_id})


func _all_met(conditions: Array[Condition], ctx: ActionContext) -> bool:
	for condition in conditions:
		if not condition.is_met(ctx):
			return false
	return true


func _sells(plug_data: PlugData, item_id: StringName) -> bool:
	for stack in plug_data.supplies:
		if stack.item_id == item_id:
			return true
	return false


func _attach_state(site_id: StringName, state: SiteState) -> void:
	var site_data := site(site_id)
	if site_data != null:
		state.stash.capacity = site_data.stash_capacity
	state.stash.changed.connect(func(item_id: StringName, count: int) -> void:
		emit_event(&"stash_changed", {"site_id": site_id, "item_id": item_id, "count": count}))
	_sites[site_id] = state

#endregion

#region Save / load

func to_dict() -> Dictionary:
	var sites := {}
	for site_id: StringName in _sites:
		sites[String(site_id)] = site_state(site_id).to_dict()
	var stored_assignments: Array = []
	for assignment in _assignments:
		stored_assignments.append(assignment.to_dict())
	var plugs := {}
	for plug_id: StringName in _plugs:
		plugs[String(plug_id)] = _plugs[plug_id].duplicate()
	var saturation := {}
	for district_id: StringName in _saturation:
		var items := {}
		for item_id: StringName in _saturation[district_id]:
			items[String(item_id)] = _saturation[district_id][item_id]
		saturation[String(district_id)] = items
	var jailed := {}
	for crew_id: StringName in _jailed:
		jailed[String(crew_id)] = _jailed[crew_id]
	var stored_unlocks: Array = []
	for unlock_id in unlocks():
		stored_unlocks.append(String(unlock_id))
	return {
		"version": 1, "sites": sites, "assignments": stored_assignments, "unlocks": stored_unlocks,
		"plugs": plugs, "saturation": saturation, "jailed": jailed,
		"next_assignment_id": _next_assignment_id, "rng_seed": str(rng.seed), "rng_state": str(rng.state),
	}


## Restores state saved by to_dict(), then runs setup() so content added since the save appears.
func from_dict(data: Dictionary) -> void:
	_sites.clear()
	_assignments.clear()
	_unlocks.clear()
	_plugs.clear()
	_saturation.clear()
	_jailed.clear()
	_events.clear()
	_market_cache.clear()
	var sites: Dictionary = data.get("sites", {})
	for site_id: String in sites:
		_attach_state(StringName(site_id), SiteState.from_dict(sites[site_id]))
	for stored: Dictionary in data.get("assignments", []):
		_assignments.append(JobAssignment.from_dict(stored))
	for unlock_id: String in data.get("unlocks", []):
		_unlocks[StringName(unlock_id)] = true
	var plugs: Dictionary = data.get("plugs", {})
	for plug_id: String in plugs:
		var stored_plug: Dictionary = plugs[plug_id]
		_plugs[StringName(plug_id)] = {
			"revealed": bool(stored_plug.get("revealed", false)), "met": bool(stored_plug.get("met", false)),
			"established": bool(stored_plug.get("established", false)), "relationship": float(stored_plug.get("relationship", 50.0)),
		}
	var saturation: Dictionary = data.get("saturation", {})
	for district_id: String in saturation:
		var items := {}
		for item_id: String in saturation[district_id]:
			items[StringName(item_id)] = float(saturation[district_id][item_id])
		_saturation[StringName(district_id)] = items
	var jailed: Dictionary = data.get("jailed", {})
	for crew_id: String in jailed:
		_jailed[StringName(crew_id)] = float(jailed[crew_id])
	_next_assignment_id = int(data.get("next_assignment_id", _assignments.size() + 1))
	if data.has("rng_seed"):
		rng.seed = int(str(data["rng_seed"]))
		rng.state = int(str(data["rng_state"]))
	setup()
	_events.clear()

#endregion
