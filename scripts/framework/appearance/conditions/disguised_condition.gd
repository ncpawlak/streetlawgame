class_name DisguisedCondition
extends Condition
## Met while [member faction] would not recognise the player's look (PlayerAppearance.is_disguised_from).
## e.g. a mission step "change your look before approaching the Angeles' block".

@export var faction: StringName
## Only met once the faction has a look to compare against (they've seen the player before).
@export var require_known_look := false


func _evaluate(_ctx: ActionContext) -> bool:
	return PlayerAppearance.is_disguised_from(faction, require_known_look)


func _reason(_ctx: ActionContext) -> String:
	return "The %s would recognise you" % GameState.gang_name(faction)


func _describe() -> String:
	return "is_disguised_from(%s)" % faction
