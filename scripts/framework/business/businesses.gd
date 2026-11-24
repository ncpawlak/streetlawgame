extends Node
## Autoload: business ownership (#36). Businesses are types (data/business_types) placed as many
## sites (data/business_sites). Buying a site needs the player gang to control its district (plus
## any per-site purchase_conditions, e.g. a CloutCondition) and costs cash. Every owned site pays
## income each GameState income cycle, adds its type's clout to its district (see Clout) and has a
## hangout crew out front. A site's shop sells at half price, but only to the site's owner.
## Sites can be lost again with [method lose_site] (rival raids, #8).

const LOCATION_ID := &"business"
const BUY_ACTION := &"buy_business"
const SHOP_ACTION := &"open_shop"
## Shop discount at a site the player owns (only that site, not the whole chain).
const OWNER_DISCOUNT := 0.5
## Price/income multiplier by area tier (AreaData.tier).
const TIER_MULTIPLIERS := {1: 1.0, 2: 2.5, 3: 5.0, 4: 15.0, 5: 30.0}

var _owned := {}            # site_id -> true
var _crew := {}             # site_id -> Array[HangoutCrewMember]
var _purchase_actions := {} # site_id -> InteractionAction
var _shop_panel: ShopPanel


func site(site_id: StringName) -> BusinessSiteDef:
	return ContentDB.find_def(BusinessSiteDef.TYPE, site_id) as BusinessSiteDef


func type_of(site_id: StringName) -> BusinessTypeDef:
	var business_site := site(site_id)
	return business_site.type_def() if business_site != null else null


func all_sites() -> Array[BusinessSiteDef]:
	var result: Array[BusinessSiteDef] = []
	for resource in ContentDB.all(BusinessSiteDef.TYPE):
		result.append(resource as BusinessSiteDef)
	return result


func sites_in(district_id: StringName) -> Array[BusinessSiteDef]:
	return all_sites().filter(func(business_site: BusinessSiteDef) -> bool: return business_site.district_id == district_id)


func is_owned(site_id: StringName) -> bool:
	return _owned.has(site_id)


func owned_sites() -> Array[StringName]:
	var result: Array[StringName] = []
	for site_id: StringName in _owned:
		result.append(site_id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


# --- Pricing -------------------------------------------------------------------------------------

func tier_of(site_id: StringName) -> int:
	var business_site := site(site_id)
	if business_site == null:
		return 1
	var area := Turf.area_data(Turf.area_of(business_site.district_id))
	return area.tier if area != null else 1


func tier_multiplier(site_id: StringName) -> float:
	return float(TIER_MULTIPLIERS.get(tier_of(site_id), 1.0))


func price_of(site_id: StringName) -> int:
	var business_site := site(site_id)
	return roundi(business_site.base_price() * tier_multiplier(site_id)) if business_site != null else 0


func income_of(site_id: StringName) -> int:
	var business_site := site(site_id)
	return roundi(business_site.base_income() * tier_multiplier(site_id)) if business_site != null else 0


## Income per cycle from every owned site (paid by GameState.pay_income).
func total_income() -> int:
	var total := 0
	for site_id: StringName in _owned:
		total += income_of(site_id)
	return total


# --- Buying / losing sites -----------------------------------------------------------------------

## The door action that buys [param site_id]: not owned + turf control + the site's
## purchase_conditions, costs its price, applies BuyBusinessEffect.
func purchase_action(site_id: StringName) -> InteractionAction:
	if _purchase_actions.has(site_id):
		return _purchase_actions[site_id]
	var business_site := site(site_id)
	var not_owned := BusinessOwnedCondition.new()
	not_owned.invert = true
	not_owned.hide_when_unmet = true
	var conditions: Array[Condition] = [not_owned, TurfControlCondition.new()]
	if business_site != null:
		conditions.append_array(business_site.purchase_conditions)
	var effects: Array[Effect] = [BuyBusinessEffect.new()]
	var action := InteractionAction.create(BUY_ACTION, "Buy business", effects, conditions)
	action.priority = 10
	var price := BusinessPriceCost.new()
	price.site_id = site_id
	action.costs = [price]
	_purchase_actions[site_id] = action
	return action


func context(site_id: StringName, actor: Node = null) -> ActionContext:
	var ctx := ActionContext.new(actor if actor != null else GameState.player)
	ctx.vars[BusinessSiteDef.CONTEXT_KEY] = site_id
	var business_site := site(site_id)
	if business_site != null:
		ctx.vars["district_id"] = business_site.district_id
	ctx.location = Locations.get_location(site_id)
	return ctx


## Why the player can't buy [param site_id] right now, or "" if they can.
func purchase_block_reason(site_id: StringName, actor: Node = null) -> String:
	if site(site_id) == null:
		return "Unknown business"
	if is_owned(site_id):
		return "Already yours"
	return purchase_action(site_id).unavailable_reason(context(site_id, actor))


## Buys a site through the same action as its door: checks conditions, pays, acquires.
func purchase(site_id: StringName, actor: Node = null) -> bool:
	if site(site_id) == null or is_owned(site_id):
		return false
	return purchase_action(site_id).execute(context(site_id, actor))


## Gives the player a site without paying (purchase effect, scripts, story). Grants its clout.
func acquire(site_id: StringName, reason: StringName = &"script") -> bool:
	var business_site := site(site_id)
	if business_site == null or is_owned(site_id):
		return false
	_owned[site_id] = true
	var business_type := business_site.type_def()
	if business_type != null:
		Clout.add(business_site.district_id, business_type.clout_value)
	_on_owner_changed(site_id)
	EventBus.business_acquired.emit(site_id, reason)
	return true


## Takes a site away (rival raid #8, script). Removes its clout and hangout crew.
func lose_site(site_id: StringName, reason: StringName = &"script") -> bool:
	if not is_owned(site_id):
		return false
	_owned.erase(site_id)
	var business_site := site(site_id)
	var business_type := business_site.type_def() if business_site != null else null
	if business_type != null:
		Clout.add(business_site.district_id, -business_type.clout_value)
	_on_owner_changed(site_id)
	EventBus.business_lost.emit(site_id, reason)
	return true


# --- Shops ---------------------------------------------------------------------------------------

func shop_items(site_id: StringName) -> Array[ShopItemDef]:
	var result: Array[ShopItemDef] = []
	var business_type := type_of(site_id)
	if business_type == null:
		return result
	for item_id in business_type.shop_item_ids:
		var item := ContentDB.find_def(ShopItemDef.TYPE, item_id) as ShopItemDef
		if item != null:
			result.append(item)
	return result


func sells(site_id: StringName, item_id: StringName) -> bool:
	var business_type := type_of(site_id)
	return business_type != null and business_type.shop_item_ids.has(item_id)


## What [param item_id] costs at [param site_id]: base x tier, halved if the player owns this site.
func shop_price(site_id: StringName, item_id: StringName) -> int:
	var item := ContentDB.find_def(ShopItemDef.TYPE, item_id) as ShopItemDef
	if item == null:
		return 0
	var price := item.base_price * tier_multiplier(site_id)
	if is_owned(site_id):
		price *= OWNER_DISCOUNT
	return roundi(price)


## Buys one [param item_id] at [param site_id]. Returns "" on success, otherwise why not.
func buy_item(site_id: StringName, item_id: StringName, actor: Node = null) -> String:
	if not sells(site_id, item_id):
		return "Not sold here"
	var item := ContentDB.find_def(ShopItemDef.TYPE, item_id) as ShopItemDef
	var cost := CashCost.new()
	cost.amount = shop_price(site_id, item_id)
	var action := InteractionAction.create(StringName("buy_%s" % item_id), item.label(), item.effects)
	action.costs = [cost]
	var ctx := context(site_id, actor)
	var reason := action.unavailable_reason(ctx)
	if reason != "":
		return reason
	action.execute(ctx)
	EventBus.shop_purchase.emit(site_id, item_id, cost.amount)
	return ""


func open_shop(site_id: StringName, actor: Node = null) -> void:
	if shop_items(site_id).is_empty():
		return
	if _shop_panel == null:
		_shop_panel = ShopPanel.new()
		add_child(_shop_panel)
	_shop_panel.open(site_id, actor)


func shop_panel() -> ShopPanel:
	return _shop_panel


# --- World ---------------------------------------------------------------------------------------

## The door LocationDef for a site: data/locations/business.tres named and coloured for the site,
## with the buy action and (if it has stock) a shop action.
func location_def_for(site_id: StringName) -> LocationDef:
	var base := ContentDB.get_def(LocationDef.TYPE, LOCATION_ID) as LocationDef
	var business_site := site(site_id)
	if base == null or business_site == null:
		return null
	var def := base.duplicate() as LocationDef
	def.display_name = business_site.label()
	def.description = business_site.description
	var business_type := business_site.type_def()
	if business_type != null:
		def.color = business_type.color
	var actions: Array[InteractionAction] = base.door_actions.duplicate()
	actions.append(purchase_action(site_id))
	if business_type != null and business_type.has_shop():
		var effects: Array[Effect] = [OpenShopEffect.new()]
		actions.append(InteractionAction.create(SHOP_ACTION, "Shop", effects))
	def.door_actions = actions
	return def


func spawn_site(site_id: StringName, at: Transform3D, parent: Node) -> Location:
	var def := location_def_for(site_id)
	if def == null:
		return null
	var location := Locations.spawn(def, at, parent, site_id)
	_on_owner_changed(site_id)
	return location


## Spawns every business site on a free lot in its district (lots as recorded by
## CityGenerator.building_lots; lots that already have a Location are skipped). Deterministic for
## the same lots. Returns the spawned locations.
func place_sites(lots: Array[Dictionary], parent: Node) -> Array[Location]:
	var taken: Array[Vector3] = []
	for location in Locations.all():
		taken.append(location.global_position)
	var free_by_district := {}
	for lot in lots:
		var at := LocationPlacer.door_transform(lot)
		if taken.any(func(position: Vector3) -> bool: return position.distance_to(at.origin) < 1.0):
			continue
		var district := Locations.resolve_district(at.origin)
		if not free_by_district.has(district):
			free_by_district[district] = []
		(free_by_district[district] as Array).append(at)
	var placed: Array[Location] = []
	for business_site in all_sites():
		if Locations.get_location(business_site.id) != null:
			continue
		var free: Array = free_by_district.get(business_site.district_id, [])
		if free.is_empty():
			push_warning("Businesses: no free lot in %s for %s" % [business_site.district_id, business_site.id])
			continue
		placed.append(spawn_site(business_site.id, free.pop_front(), parent))
	return placed


func crew_at(site_id: StringName) -> Array:
	return (_crew.get(site_id, []) as Array).filter(func(member: Node) -> bool: return is_instance_valid(member))


func _on_owner_changed(site_id: StringName) -> void:
	var location := Locations.get_location(site_id)
	if location != null:
		Locations.set_owner_gang(location, GameState.PLAYER_GANG if is_owned(site_id) else GameState.NO_GANG)
	_refresh_crew(site_id, location)


func _refresh_crew(site_id: StringName, location: Location) -> void:
	for member: Node in crew_at(site_id):
		member.queue_free()
	_crew.erase(site_id)
	var business_type := type_of(site_id)
	if location == null or business_type == null or not is_owned(site_id):
		return
	var members: Array = []
	for i in business_type.hangout_crew_count:
		var spread := (float(i) - (business_type.hangout_crew_count - 1) * 0.5) * 1.6
		var member := HangoutCrewMember.create(GameState.gang_color(GameState.PLAYER_GANG), Vector3(spread, 0.0, 2.5), hash(site_id) + i)
		location.add_child(member)
		members.append(member)
	_crew[site_id] = members


# --- Save ----------------------------------------------------------------------------------------

## Forgets ownership without touching clout (Clout is saved separately).
func clear() -> void:
	for site_id in owned_sites():
		_owned.erase(site_id)
		_on_owner_changed(site_id)


func to_dict() -> Dictionary:
	var sites: Array[String] = []
	for site_id in owned_sites():
		sites.append(String(site_id))
	return {"owned": sites}


## Restores ownership. Doesn't re-grant clout; load Clout from its own save data.
func from_dict(data: Dictionary) -> void:
	clear()
	for site_id: String in data.get("owned", []):
		if site(StringName(site_id)) != null:
			_owned[StringName(site_id)] = true
			_on_owner_changed(StringName(site_id))
