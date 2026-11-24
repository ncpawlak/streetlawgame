class_name SiteData
extends ContentDef
## A place where operations run: trap house, lab, business, fence. Placed in the world by a
## unique LocationDef (location_id); ContentDef.tags are matched against RecipeData.site_tags.

## &"trap_house", &"lab", &"business", &"fence"...
@export var kind: StringName
@export var district_id: StringName
## Unique LocationDef id (its instance id equals this) hosting the management action.
@export var location_id: StringName
## Job ids allowed here (empty = any).
@export var allowed_jobs: Array[StringName] = []
## Crew-staffed jobs at once.
@export var max_workers := 3
## Total stash units (0 = unlimited).
@export var stash_capacity := 200
@export var acquire_price := 0
@export var starts_acquired := false
@export var acquire_conditions: Array[Condition] = []
## Jobs here are BLOCKED while these fail (e.g. DistrictOwnedCondition).
@export var operate_conditions: Array[Condition] = []
@export var risks: Array[RiskData] = []
@export var heat_decay_per_minute := 5.0
@export var visual: VisualSpec


func validate() -> PackedStringArray:
	var issues := super.validate()
	if kind.is_empty():
		issues.append("%s: kind is empty" % id)
	if max_workers < 1:
		issues.append("%s: max_workers must be at least 1" % id)
	return issues
