class_name ItemData
extends ContentDef
## A tradable commodity: drugs, precursors, supplies, stolen loot. Stored in an Inventory by id.

## Broad type used by markets and sales jobs, e.g. &"drug", &"precursor", &"loot".
@export var category: StringName
## Dollars per unit before the market's pricing model is applied.
@export var base_value := 0
## Heat added to the site per unit produced or sold.
@export var heat_per_unit := 0.0
## Loaded through ContentDB.load_asset so override roots can swap it.
@export_file var icon_path := ""
## World model (stash props, drops); greybox fallback when empty.
@export var visual: VisualSpec


func validate() -> PackedStringArray:
	var issues := super.validate()
	if category.is_empty():
		issues.append("%s: category is empty" % id)
	if base_value < 0:
		issues.append("%s: negative base_value" % id)
	return issues
