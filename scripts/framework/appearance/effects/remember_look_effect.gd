class_name RememberLookEffect
extends Effect
## [member faction] memorises the player's current look (or forgets it with [member forget]).
## e.g. "the Angeles saw you": from now on they recognise this outfit + hair.

@export var faction: StringName
@export var forget := false


func _apply(_ctx: ActionContext) -> void:
	if forget:
		PlayerAppearance.forget_look(faction)
	else:
		PlayerAppearance.remember_look(faction)


func _describe(_ctx: ActionContext) -> String:
	return ("%s forget your look" if forget else "%s remember your look") % GameState.gang_name(faction)
