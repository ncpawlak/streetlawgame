class_name Appearance
extends Resource
## A character's look: one (item id, colour variant) per slot plus a skin tone. Applied to a
## [CharacterVisual] with [method CharacterVisual.apply_appearance]; saved with [method to_dict].
## [method signature] / [method similarity] are what factions use to recognise a look (see
## PlayerAppearance), [method color_weights] what they use for colour affinity.

const CLOTHING_SLOTS: Array[StringName] = [&"top", &"bottom", &"shoes", &"hat", &"accessory"]
const HAIR_SLOTS: Array[StringName] = [&"hair", &"hair_color", &"facial_hair"]
const SLOTS: Array[StringName] = [&"top", &"bottom", &"shoes", &"hat", &"accessory", &"hair", &"hair_color", &"facial_hair"]
const SLOT_NAMES := {
	&"top": "Tops", &"bottom": "Bottoms", &"shoes": "Shoes", &"hat": "Hats", &"accessory": "Accessories",
	&"hair": "Hairstyle", &"hair_color": "Hair colour", &"facial_hair": "Facial hair",
}
## How much each slot counts when someone tries to recognise you (sums to 14).
const RECOGNITION_WEIGHTS := {
	&"top": 3.0, &"bottom": 1.5, &"shoes": 0.5, &"hat": 2.0, &"accessory": 1.0,
	&"hair": 2.5, &"hair_color": 2.0, &"facial_hair": 1.5,
}
## How visible each slot's colour is from a distance (for faction colour affinity).
const COLOR_WEIGHTS := {
	&"top": 3.0, &"bottom": 2.0, &"shoes": 0.5, &"hat": 1.5, &"accessory": 0.5, &"hair_color": 1.0,
}
## Same item in a different colour still counts this much towards recognition.
const SAME_ITEM_OTHER_COLOR := 0.4
## Skin tones NPC uniforms pick from.
const SKIN_TONES: Array[Color] = [Color("ba9c79"), Color("8d6748"), Color("5e4030"), Color("d9b896"), Color("a9774f"), Color("3f2a20")]
## The player's starting look (not customisable until a clothing store / barber).
const DEFAULT_LOOK := {
	"slots": {
		"top": {"item": "hoodie", "color": 0},
		"bottom": {"item": "jeans", "color": 0},
		"shoes": {"item": "sneakers", "color": 0},
		"hair": {"item": "short_crop", "color": 0},
		"hair_color": {"item": "hair_dye", "color": 1},
	},
	"skin": "ba9c79",
}

## slot -> {"item": StringName, "color": int}. Missing slot = nothing / the base model's part.
@export var slots: Dictionary = {}
@export var skin_tone := Color("ba9c79")


static func default_look() -> Appearance:
	return from_dict(DEFAULT_LOOK)


static func from_dict(data: Dictionary) -> Appearance:
	var look := Appearance.new()
	var stored: Dictionary = data.get("slots", {})
	for slot_name in stored:
		var slot := StringName(slot_name)
		var entry: Dictionary = stored[slot_name]
		if SLOTS.has(slot) and String(entry.get("item", "")) != "":
			look.set_slot(slot, StringName(entry["item"]), int(entry.get("color", 0)))
	if data.has("skin"):
		look.skin_tone = Color.html(String(data["skin"]))
	return look


func to_dict() -> Dictionary:
	var stored := {}
	for slot: StringName in SLOTS:
		if slots.has(slot):
			stored[String(slot)] = {"item": String(get_item(slot)), "color": get_color(slot)}
	return {"slots": stored, "skin": skin_tone.to_html(false)}


func copy() -> Appearance:
	return from_dict(to_dict())


## The definition type (ClothingItemDef.TYPE or HairItemDef.TYPE) for a slot.
static func type_for(slot: StringName) -> StringName:
	return &"hair" if HAIR_SLOTS.has(slot) else &"clothing"


static func find_item(slot: StringName, item_id: StringName) -> AppearanceItemDef:
	var def := ContentDB.find_def(type_for(slot), item_id) as AppearanceItemDef
	return def if def != null and def.slot == slot else null


## Every catalog item for a slot, sorted by price then id.
static func catalog(slot: StringName) -> Array[AppearanceItemDef]:
	var result: Array[AppearanceItemDef] = []
	for resource in ContentDB.all(type_for(slot)):
		var item := resource as AppearanceItemDef
		if item != null and item.slot == slot:
			result.append(item)
	result.sort_custom(func(a: AppearanceItemDef, b: AppearanceItemDef) -> bool:
		return a.base_price < b.base_price or (a.base_price == b.base_price and String(a.id) < String(b.id)))
	return result


func set_slot(slot: StringName, item_id: StringName, color: int = 0) -> void:
	if item_id == &"":
		slots.erase(slot)
	else:
		slots[slot] = {"item": item_id, "color": color}
	emit_changed()


func clear_slot(slot: StringName) -> void:
	set_slot(slot, &"")


func get_item(slot: StringName) -> StringName:
	return StringName((slots.get(slot, {}) as Dictionary).get("item", &""))


func get_color(slot: StringName) -> int:
	return int((slots.get(slot, {}) as Dictionary).get("color", 0))


func item_def(slot: StringName) -> AppearanceItemDef:
	var item_id := get_item(slot)
	return find_item(slot, item_id) if item_id != &"" else null


func is_wearing(item_id: StringName, color: int = -1) -> bool:
	for slot: StringName in slots:
		if get_item(slot) == item_id and (color < 0 or get_color(slot) == color):
			return true
	return false


## Stable string identifying the look, e.g. "top=hoodie:0|bottom=jeans:0|...".
func signature() -> String:
	var parts := PackedStringArray()
	for slot: StringName in SLOTS:
		parts.append("%s=%s:%d" % [slot, get_item(slot), get_color(slot)] if slots.has(slot) else "%s=-" % slot)
	return "|".join(parts)


## 0 (nothing in common) to 1 (identical), weighted by [constant RECOGNITION_WEIGHTS].
func similarity(other: Appearance) -> float:
	if other == null:
		return 0.0
	var total := 0.0
	var matched := 0.0
	for slot: StringName in SLOTS:
		var weight: float = RECOGNITION_WEIGHTS[slot]
		total += weight
		if get_item(slot) != other.get_item(slot):
			continue
		matched += weight if get_color(slot) == other.get_color(slot) else weight * SAME_ITEM_OTHER_COLOR
	return matched / total if total > 0.0 else 1.0


## Colour family -> share (0..1) of the visible outfit in that colour.
func color_weights() -> Dictionary:
	var result := {}
	var total := 0.0
	for slot: StringName in COLOR_WEIGHTS:
		var weight: float = COLOR_WEIGHTS[slot]
		total += weight
		var item := item_def(slot)
		if item == null:
			continue
		var tags := item.tags_for(get_color(slot))
		for tag in tags:
			result[tag] = float(result.get(tag, 0.0)) + weight / tags.size()
	for tag: StringName in result:
		result[tag] = result[tag] / total
	return result


## Share (0..1) of the visible outfit in any of [param colors], plus items tagged for [param faction].
func affinity(colors: Array[StringName], faction: StringName = &"") -> float:
	var weights := color_weights()
	var score := 0.0
	for tag in colors:
		score += float(weights.get(tag, 0.0))
	if faction != &"":
		var total := 0.0
		for slot: StringName in COLOR_WEIGHTS:
			total += COLOR_WEIGHTS[slot]
		for slot: StringName in COLOR_WEIGHTS:
			var item := item_def(slot)
			if item != null and item.faction_tags.has(faction):
				score += COLOR_WEIGHTS[slot] / total
	return clampf(score, 0.0, 1.0)


## Clothing ids worn (for "owned" checks and debugging).
func worn_clothing() -> Array[StringName]:
	var result: Array[StringName] = []
	for slot in CLOTHING_SLOTS:
		if slots.has(slot):
			result.append(get_item(slot))
	return result
