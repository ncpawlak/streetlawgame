class_name BusinessData
extends Resource
## A purchasable business. Owning one pays income and unlocks features (storage, shops, upgrades).

@export var id: StringName
@export var display_name := ""
@export var price := 5000
@export var income_per_cycle := 0
## Feature flags unlocked by owning this business, e.g. &"vehicle_storage", &"weapon_shop".
@export var unlocks: Array[StringName] = []
