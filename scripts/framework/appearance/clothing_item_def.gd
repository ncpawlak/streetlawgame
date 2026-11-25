class_name ClothingItemDef
extends AppearanceItemDef
## A piece of clothing (data/clothing/<id>.tres). Either swaps a body part mesh in from another
## Quaternius model ([member source_model] + [member part]) or adds a procedural attachment
## ([member attachment], for hats and accessories). Sold at clothing stores, changed at wardrobes.

const TYPE := &"clothing"

## Quaternius model id the part mesh comes from (assets/characters/quaternius/<id>.glb).
@export var source_model: StringName = &""
## Mesh part to take from [member source_model]: &"Body", &"Legs" or &"Feet". Replaces the same part.
@export var part: StringName = &""
## Materials of the part recoloured with the variant colour.
@export var tint_materials: Array[StringName] = []
## Procedural attachment id (see AppearanceRig.ATTACHMENTS) for hats/accessories. &"" = none.
@export var attachment: StringName = &""


func validate() -> PackedStringArray:
	var issues := super()
	if not Appearance.CLOTHING_SLOTS.has(slot):
		issues.append("clothing must use a clothing slot, not '%s'" % slot)
	if part != &"" and not AppearanceRig.PARTS.has(part):
		issues.append("unknown part '%s'" % part)
	if part != &"" and source_model == &"":
		issues.append("part swap needs a source_model")
	if attachment != &"" and not AppearanceRig.ATTACHMENTS.has(attachment):
		issues.append("unknown attachment '%s'" % attachment)
	return issues
