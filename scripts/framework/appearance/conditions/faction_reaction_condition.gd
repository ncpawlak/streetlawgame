class_name FactionReactionCondition
extends Condition
## Met while [member faction]'s attitude to the player's look (PlayerAppearance.reaction_of) is
## one of [member attitudes], e.g. "the Angeles are not hostile".

@export var faction: StringName
@export var attitudes: Array[StringName] = [&"neutral", &"friendly"]


func _evaluate(_ctx: ActionContext) -> bool:
	return attitudes.has(PlayerAppearance.reaction_of(faction))


func _reason(_ctx: ActionContext) -> String:
	return "The %s are %s" % [GameState.gang_name(faction), PlayerAppearance.reaction_of(faction)]


func _describe() -> String:
	return "reaction_of(%s) in %s" % [faction, attitudes]
