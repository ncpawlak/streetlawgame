class_name RecipeData
extends ContentDef
## Turns input items into output items over time at a site whose tags match.

@export var inputs: Array[ItemStack] = []
@export var outputs: Array[ItemStack] = []
@export var cycle_seconds := 30.0
## Unlock ids required (granted by plugs), e.g. &"drug:weed".
@export var required_unlocks: Array[StringName] = []
## The site needs at least one of these tags (empty = any site), e.g. &"grow", &"cook".
@export var site_tags: Array[StringName] = []
## Speed bonus per crew skill point above 1.
@export var skill_speed_bonus := 0.08


func validate() -> PackedStringArray:
	var issues := super.validate()
	if outputs.is_empty():
		issues.append("%s: no outputs" % id)
	if cycle_seconds <= 0.0:
		issues.append("%s: cycle_seconds must be positive" % id)
	return issues
