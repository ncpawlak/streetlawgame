extends Node
## Autoload "PlayerAppearance": the player's current look, the clothes they own and what each
## faction remembers about them.
##
## Disguise model: a faction can hold a "known look" (remember_look, e.g. when its members fight
## the player or a script says they saw them). It recognises the player while the current look is
## at least FactionStyleDef.recognition_threshold similar (Appearance.similarity) to that record;
## changing enough of outfit + hair breaks recognition. reaction_of() combines recognition with
## faction colour affinity into an attitude GangMember acts on.

const ATTITUDES: Array[StringName] = [&"hostile", &"suspicious", &"neutral", &"friendly"]
const HOSTILE := &"hostile"
const SUSPICIOUS := &"suspicious"
const NEUTRAL := &"neutral"
const FRIENDLY := &"friendly"
## Recognition threshold for factions without a FactionStyleDef.
const DEFAULT_RECOGNITION := 0.6
## Clothes / haircuts cost this much more per area tier above 1 (businesses use steeper multipliers).
const TIER_MARKUP := 0.25

var _look: Appearance
var _owned := {}  # "item_id:color" -> true
var _known := {}  # faction -> Appearance
var _panel: AppearancePanel


func _ready() -> void:
	reset()


## New game: default look, starter clothes owned, factions with knows_starting_look know it.
func reset() -> void:
	_look = Appearance.default_look()
	_owned.clear()
	_known.clear()
	for resource in ContentDB.all(ClothingItemDef.TYPE):
		var item := resource as ClothingItemDef
		if item != null and item.starter:
			_owned[_key(item.id, 0)] = true
	for slot in Appearance.CLOTHING_SLOTS:
		if _look.get_item(slot) != &"":
			_owned[_key(_look.get_item(slot), _look.get_color(slot))] = true
	for resource in ContentDB.all(FactionStyleDef.TYPE):
		var style := resource as FactionStyleDef
		if style != null and style.knows_starting_look:
			_known[style.id] = _look.copy()
	_refresh_player()


# --- Current look ----------------------------------------------------------------------------------

## A copy of the current look (edit it and pass it to set_look to change it).
func look() -> Appearance:
	return _look.copy()


func signature() -> String:
	return _look.signature()


## Replaces the whole look (scripts, cutscenes, loading). Doesn't check ownership or charge.
func set_look(new_look: Appearance) -> void:
	_look = new_look.copy()
	_refresh_player()
	EventBus.appearance_changed.emit(_look.copy())


## Applies the current look to [param visual] (the player's body; Player calls this on spawn).
func dress(visual: CharacterVisual) -> void:
	if visual != null:
		visual.apply_appearance(_look)


func _refresh_player() -> void:
	var player := GameState.player
	if player != null and is_instance_valid(player) and player.visual != null:
		dress(player.visual)


# --- Ownership / buying ----------------------------------------------------------------------------

func owns(item_id: StringName, color: int = 0) -> bool:
	return _owned.has(_key(item_id, color))


func grant(item_id: StringName, color: int = 0) -> void:
	_owned[_key(item_id, color)] = true


## Owned clothing variants for a slot: [{"item": ClothingItemDef, "color": int}].
func owned_in(slot: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in Appearance.catalog(slot):
		for color in item.variant_count():
			if owns(item.id, color):
				result.append({"item": item, "color": color})
	return result


## Price at [param site_id]: base, +25% per area tier above 1 (Businesses.tier_of), halved at a
## site the player owns. &"" = base price.
func price_of(item: AppearanceItemDef, site_id: StringName = &"") -> int:
	if item == null:
		return 0
	var price := float(item.base_price)
	if site_id != &"" and Businesses.site(site_id) != null:
		price *= 1.0 + TIER_MARKUP * (Businesses.tier_of(site_id) - 1)
		if Businesses.is_owned(site_id):
			price *= Businesses.OWNER_DISCOUNT
	return roundi(price)


## Puts on an owned clothing variant (wardrobe). Returns "" or why not.
func equip(slot: StringName, item_id: StringName, color: int = 0) -> String:
	var item := Appearance.find_item(slot, item_id)
	if item == null or not item is ClothingItemDef:
		return "Unknown item"
	if not item.has_variant(color):
		return "Unknown colour"
	if not owns(item_id, color):
		return "You don't own that"
	_set_slot(slot, item_id, color)
	return ""


## Takes off a hat or accessory (tops, bottoms and shoes can only be swapped).
func unequip(slot: StringName) -> String:
	if not [&"hat", &"accessory"].has(slot):
		return "Can't go without that"
	_set_slot(slot, &"", 0)
	return ""


## Buys a clothing variant at a store and (optionally) puts it on. Owned items aren't charged again.
func buy(slot: StringName, item_id: StringName, color: int = 0, site_id: StringName = &"", wear := true) -> String:
	var item := Appearance.find_item(slot, item_id)
	if item == null or not item is ClothingItemDef:
		return "Unknown item"
	if not item.has_variant(color):
		return "Unknown colour"
	if not owns(item_id, color):
		var price := price_of(item, site_id)
		if not GameState.spend_cash(price):
			return "Not enough cash ($%d)" % price
		grant(item_id, color)
		_record_purchase(item_id, color, price, site_id)
	return equip(slot, item_id, color) if wear else ""


## Barber service: pays for and applies a hairstyle / dye / facial hair. &"" item removes facial
## hair. No charge if nothing changes.
func get_haircut(slot: StringName, item_id: StringName, color: int = 0, site_id: StringName = &"") -> String:
	if not Appearance.HAIR_SLOTS.has(slot):
		return "Not a barber service"
	if _look.get_item(slot) == item_id and (item_id == &"" or _look.get_color(slot) == color):
		return ""
	if item_id == &"":
		if slot != &"facial_hair":
			return "Can't remove that"
		_set_slot(slot, &"", 0)
		return ""
	var item := Appearance.find_item(slot, item_id)
	if item == null:
		return "Unknown style"
	if not item.has_variant(color):
		return "Unknown colour"
	var price := price_of(item, site_id)
	if not GameState.spend_cash(price):
		return "Not enough cash ($%d)" % price
	_record_purchase(item_id, color, price, site_id)
	_set_slot(slot, item_id, color)
	return ""


func _set_slot(slot: StringName, item_id: StringName, color: int) -> void:
	var updated := _look.copy()
	updated.set_slot(slot, item_id, color)
	set_look(updated)


func _record_purchase(item_id: StringName, color: int, price: int, site_id: StringName) -> void:
	EventBus.appearance_purchase.emit(item_id, color, price, site_id)
	if site_id != &"":
		EventBus.shop_purchase.emit(site_id, item_id, price)


# --- Recognition / disguise ------------------------------------------------------------------------

## [param faction] now knows the current look (they saw the player, a story beat...).
func remember_look(faction: StringName) -> void:
	_known[faction] = _look.copy()
	EventBus.look_remembered.emit(faction)


func forget_look(faction: StringName) -> void:
	_known.erase(faction)


func has_known_look(faction: StringName) -> bool:
	return _known.has(faction)


func known_look(faction: StringName) -> Appearance:
	return (_known[faction] as Appearance).copy() if _known.has(faction) else null


## How closely the current look matches what [param faction] remembers (0 if nothing).
func recognition(faction: StringName) -> float:
	return _look.similarity(_known[faction]) if _known.has(faction) else 0.0


func recognition_threshold(faction: StringName) -> float:
	var style := FactionStyleDef.find(faction)
	return style.recognition_threshold if style != null else DEFAULT_RECOGNITION


func recognised_by(faction: StringName) -> bool:
	return _known.has(faction) and recognition(faction) >= recognition_threshold(faction)


## True when [param faction] wouldn't recognise the player. With [param require_known_look] it's
## only true once they have a look to compare against (a disguise from someone who has seen you).
func is_disguised_from(faction: StringName, require_known_look := false) -> bool:
	if not _known.has(faction):
		return not require_known_look
	return not recognised_by(faction)


## Share (0..1) of the outfit in [param faction]'s colours (or tagged for it).
func faction_affinity(faction: StringName, look_override: Appearance = null) -> float:
	var style := FactionStyleDef.find(faction)
	var subject := look_override if look_override != null else _look
	return subject.affinity(style.color_tags, faction) if style != null else 0.0


## How [param faction] treats the player right now: recognised -> recognised_attitude; wearing a
## rival's colours -> hostile / suspicious; wearing their colours -> own_colors_attitude; otherwise
## default_attitude. Factions without a FactionStyleDef are hostile (classic rival gang).
func reaction_of(faction: StringName) -> StringName:
	var style := FactionStyleDef.find(faction)
	if style == null:
		return HOSTILE
	if recognised_by(faction):
		return style.recognised_attitude
	var rival_affinity := 0.0
	for rival in style.rivals:
		rival_affinity = maxf(rival_affinity, faction_affinity(rival))
	if rival_affinity >= style.rival_hostile_threshold:
		return HOSTILE
	if faction_affinity(faction) >= style.own_colors_threshold:
		return style.own_colors_attitude
	if rival_affinity >= style.rival_suspicious_threshold:
		return _worse(SUSPICIOUS, style.default_attitude)
	return style.default_attitude


static func _worse(a: StringName, b: StringName) -> StringName:
	return a if ATTITUDES.find(a) < ATTITUDES.find(b) else b


# --- UI --------------------------------------------------------------------------------------------

## Opens the wardrobe (owned clothes), a clothing store or the barber. [param mode]: &"wardrobe",
## &"clothing" or &"barber". [param anchor] places the preview / barber-chair camera.
func open_panel(mode: StringName, site_id: StringName = &"", actor: Node = null, anchor: Node3D = null) -> AppearancePanel:
	if _panel == null:
		_panel = AppearancePanel.new()
		add_child(_panel)
	_panel.open(mode, site_id, actor, anchor)
	return _panel


func panel() -> AppearancePanel:
	return _panel


# --- Save / load -----------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var known := {}
	for faction: StringName in _known:
		known[String(faction)] = (_known[faction] as Appearance).to_dict()
	var owned: Array[String] = []
	for key: String in _owned:
		owned.append(key)
	owned.sort()
	return {"look": _look.to_dict(), "owned": owned, "known": known}


func from_dict(data: Dictionary) -> void:
	_look = Appearance.from_dict(data.get("look", Appearance.DEFAULT_LOOK))
	_owned.clear()
	for key in data.get("owned", []):
		_owned[String(key)] = true
	_known.clear()
	var known: Dictionary = data.get("known", {})
	for faction in known:
		_known[StringName(faction)] = Appearance.from_dict(known[faction])
	_refresh_player()
	EventBus.appearance_changed.emit(_look.copy())


static func _key(item_id: StringName, color: int) -> String:
	return "%s:%d" % [item_id, color]
