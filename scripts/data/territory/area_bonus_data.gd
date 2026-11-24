class_name AreaBonusData
extends Resource
## A reward a gang gets while it holds every district of an area.

## Multiplies the base income of the area's districts.
@export var income_multiplier := 1.0
@export var flat_income_per_cycle := 0
## Paid once, when the area is taken.
@export var respect_reward := 0
## Feature flags, queried with [method Turf.has_unlock].
@export var unlocks: Array[StringName] = []
