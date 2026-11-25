class_name AppearanceItemDef
extends ContentDef
## Base for anything the player can wear or have done to their look: clothes (ClothingItemDef,
## data/clothing) and hair (HairItemDef, data/hair). One item fills one [member slot] of an
## [Appearance] in one of its colour [member colors] variants.

## Appearance slot this item fills (see Appearance.SLOTS).
@export var slot: StringName = &"top"
## Price before the shop's area tier multiplier / owner discount (see PlayerAppearance.price_of).
@export var base_price := 50
## Colour variants. Empty = the item keeps the model's own colours (one implicit variant).
@export var colors: Array[Color] = []
## Display name per variant ("Yellow", "Black"...), parallel to [member colors].
@export var color_names: PackedStringArray = []
## Colour family per variant (&"yellow", &"white", &"red"...), parallel to [member colors]. Faction
## colour affinity is computed from these (see FactionStyleDef.color_tags).
@export var color_tags: Array[StringName] = []
## Colour family of the parts that don't take the variant colour (e.g. white sneaker soles).
@export var fixed_color_tags: Array[StringName] = []
## Factions this item is associated with regardless of colour (e.g. a gang's patch jacket).
@export var faction_tags: Array[StringName] = []
## Owned from the start (the starting look, basics).
@export var starter := false


func variant_count() -> int:
	return maxi(1, colors.size())


func has_variant(index: int) -> bool:
	return index >= 0 and index < variant_count()


## Variant colour, or null when the item keeps its own colours.
func color_at(index: int) -> Variant:
	return colors[index] if index >= 0 and index < colors.size() else null


func color_name(index: int) -> String:
	if index >= 0 and index < color_names.size():
		return color_names[index]
	return "Default" if colors.is_empty() else "Colour %d" % (index + 1)


## Colour family tags the variant shows (its own plus fixed ones).
func tags_for(index: int) -> Array[StringName]:
	var result: Array[StringName] = fixed_color_tags.duplicate()
	if index >= 0 and index < color_tags.size() and color_tags[index] != &"":
		result.append(color_tags[index])
	return result


## "Name (Colour)" label for UI.
func variant_label(index: int) -> String:
	return label() if variant_count() <= 1 else "%s (%s)" % [label(), color_name(index)]


func validate() -> PackedStringArray:
	var issues := super()
	if not Appearance.SLOTS.has(slot):
		issues.append("unknown appearance slot '%s'" % slot)
	if base_price < 0:
		issues.append("negative base_price")
	if not color_names.is_empty() and color_names.size() != colors.size():
		issues.append("color_names must match colors")
	if not color_tags.is_empty() and color_tags.size() != colors.size():
		issues.append("color_tags must match colors")
	return issues
