class_name TrapCustomization
extends RefCounted
## How the player has built out a trap house they kept: level, rooms and the product it pushes.
## Numbers follow docs/design/TRAP_HOUSES_OPERATIONS.md (tier-1 costs). Crew are assigned through
## the Operations model; [method apply_to] pushes worker slots, stash size and room tags (which
## unlock recipes) into the site's SiteData.

const LEVELS := [
	{"name": "Spot", "cost": 0, "room_slots": 1, "workers": 2, "stash": 50, "safe": 2000},
	{"name": "House", "cost": 3000, "room_slots": 2, "workers": 4, "stash": 150, "safe": 6000},
	{"name": "Compound", "cost": 10000, "room_slots": 3, "workers": 6, "stash": 400, "safe": 20000},
]
## Rooms in shop order. product: what a cook makes there; recipe: OperationsModel recipe id when
## the game has one (empty = product not in the game yet); tag: SiteData tag the recipe needs.
const ROOMS := {
	&"grow_room": {"name": "Grow room", "cost": 1000, "product": "Weed", "recipe": &"grow_weed", "tag": &"grow"},
	&"pill_press": {"name": "Pill press", "cost": 3000, "product": "Pills", "recipe": &"", "tag": &"pills"},
	&"cut_and_bag": {"name": "Cut & bag", "cost": 8000, "product": "Coke", "recipe": &"cook_coke", "tag": &"lab"},
	&"meth_lab": {"name": "Meth lab", "cost": 12000, "product": "Meth", "recipe": &"", "tag": &"meth"},
	&"heroin_cutting": {"name": "Heroin cutting", "cost": 25000, "product": "Heroin", "recipe": &"", "tag": &"heroin"},
	&"security": {"name": "Security", "cost": 2000, "product": "", "recipe": &"", "tag": &"security"},
	&"counting_room": {"name": "Counting room", "cost": 4000, "product": "", "recipe": &"", "tag": &"counting"},
}

## 0-based index into LEVELS.
var level := 0
var rooms: Array[StringName] = []
## Room id whose product the cooks run (must be an owned production room), or &"".
var product: StringName = &""


## A trap taken from a rival: already a House (Lv 2) with the grow room they were running.
static func from_takeover() -> TrapCustomization:
	var custom := TrapCustomization.new()
	custom.level = 1
	custom.rooms.append(&"grow_room")
	custom.product = &"grow_room"
	return custom


func level_info() -> Dictionary:
	return LEVELS[level]


func room_slots_free() -> int:
	return level_info()["room_slots"] - rooms.size()


func next_level_cost() -> int:
	return LEVELS[level + 1]["cost"] if level + 1 < LEVELS.size() else -1


static func is_production(room_id: StringName) -> bool:
	return ROOMS.has(room_id) and ROOMS[room_id]["product"] != ""


## Rooms you own that make something, i.e. the product choices.
func product_rooms() -> Array[StringName]:
	var result: Array[StringName] = []
	for room_id in rooms:
		if is_production(room_id):
			result.append(room_id)
	return result


## "" when the room could be bought now (ignoring cash), otherwise why not.
func room_block_reason(room_id: StringName) -> String:
	if not ROOMS.has(room_id):
		return "Unknown room"
	if rooms.has(room_id):
		return "Already built"
	if room_slots_free() <= 0:
		return "No free room slots - upgrade the house"
	return ""


## Buys a room, paying with [param spend] (func(amount) -> bool). Returns "" or the reason it failed.
func buy_room(room_id: StringName, spend: Callable) -> String:
	var reason := room_block_reason(room_id)
	if reason != "":
		return reason
	var cost: int = ROOMS[room_id]["cost"]
	if not spend.call(cost):
		return "Not enough cash ($%d)" % cost
	rooms.append(room_id)
	if product == &"" and is_production(room_id):
		product = room_id
	return ""


func upgrade(spend: Callable) -> String:
	var cost := next_level_cost()
	if cost < 0:
		return "Already a %s" % level_info()["name"]
	if not spend.call(cost):
		return "Not enough cash ($%d)" % cost
	level += 1
	return ""


func set_product(room_id: StringName) -> String:
	if not product_rooms().has(room_id):
		return "Build a %s first" % (ROOMS[room_id]["name"] if ROOMS.has(room_id) else "production room")
	product = room_id
	return ""


func product_name() -> String:
	return ROOMS[product]["product"] if ROOMS.has(product) else "Nothing"


## Recipe id for the current product, or &"" when the game doesn't have that product yet.
func product_recipe() -> StringName:
	return ROOMS[product]["recipe"] if ROOMS.has(product) else &""


## Pushes slots, stash size and room tags into the site definition.
func apply_to(site: SiteData) -> void:
	site.max_workers = level_info()["workers"]
	site.stash_capacity = level_info()["stash"]
	var tags: Array[StringName] = [&"stash"]
	for room_id in rooms:
		tags.append(ROOMS[room_id]["tag"])
	site.tags = tags


func to_dict() -> Dictionary:
	var room_names: Array[String] = []
	for room_id in rooms:
		room_names.append(String(room_id))
	return {"level": level, "rooms": room_names, "product": String(product)}


static func from_dict(data: Dictionary) -> TrapCustomization:
	var custom := TrapCustomization.new()
	custom.level = clampi(int(data.get("level", 0)), 0, LEVELS.size() - 1)
	for room_id: String in data.get("rooms", []):
		custom.rooms.append(StringName(room_id))
	custom.product = StringName(data.get("product", ""))
	return custom
