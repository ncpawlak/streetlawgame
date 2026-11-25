class_name WearingCondition
extends Condition
## Met while the player wears [member item_id] (any colour, or [member color] when >= 0), or, with
## [member color_tag] set instead, while at least [member min_share] of the outfit is that colour.

@export var item_id: StringName
@export var color := -1
@export var color_tag: StringName
@export_range(0.0, 1.0) var min_share := 0.3


func _evaluate(_ctx: ActionContext) -> bool:
	var look := PlayerAppearance.look()
	if item_id != &"":
		return look.is_wearing(item_id, color)
	if color_tag != &"":
		return float(look.color_weights().get(color_tag, 0.0)) >= min_share
	return true


func _reason(_ctx: ActionContext) -> String:
	if item_id != &"":
		return "You need to wear %s" % String(item_id).capitalize()
	return "You need to wear more %s" % color_tag
