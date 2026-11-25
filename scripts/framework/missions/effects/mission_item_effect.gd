class_name MissionItemEffect
extends Effect
## Adds (or with a negative count removes) mission items, e.g. the note looted from a body.

@export var item_id: StringName
@export var count := 1


func _apply(_ctx: ActionContext) -> void:
	Missions.give_item(item_id, count)
