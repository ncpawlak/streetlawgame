class_name DefenderConfig
extends Resource
## Who defends a district while a rival gang holds it.

## Spawned at the safehouse. The safehouse can't be claimed while any are alive.
@export var guard_count := 4
## Spawned around the district. Ambient threat only.
@export var patrol_count := 2
## Weapon ids to roll from. Empty uses the gang's arsenal.
@export var weapon_ids: Array[StringName] = []
