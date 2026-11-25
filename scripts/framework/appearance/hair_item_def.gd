class_name HairItemDef
extends AppearanceItemDef
## A barber service (data/hair/<id>.tres): a hairstyle (slot &"hair", swaps the head mesh from
## [member source_model]), a dye (slot &"hair_color", one variant per colour) or facial hair
## (slot &"facial_hair", a procedural [member attachment]). Hair is never "owned": every change
## at the barber is paid for.

const TYPE := &"hair"

## Model whose head (and therefore hairstyle) is used. &"" keeps the current head.
@export var source_model: StringName = &""
## Materials of that head that are hair (recoloured by the hair_color slot).
@export var hair_materials: Array[StringName] = []
## Shaved: hair materials take the skin tone instead of the hair colour.
@export var shaved := false
## Procedural attachment (facial hair) coloured with the hair colour. &"" = none.
@export var attachment: StringName = &""


func validate() -> PackedStringArray:
	var issues := super()
	if not Appearance.HAIR_SLOTS.has(slot):
		issues.append("hair item must use a hair slot, not '%s'" % slot)
	if attachment != &"" and not AppearanceRig.ATTACHMENTS.has(attachment):
		issues.append("unknown attachment '%s'" % attachment)
	return issues
