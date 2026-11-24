class_name LocationOwnerCondition
extends Condition
## Met when the location's owner matches. [member owner_gang] may be a gang id, &"player" or
## &"rival" (owned by any gang other than the player).

@export var owner_gang := &"rival"


func _evaluate(ctx: ActionContext) -> bool:
	var location := ctx.location as Location
	if location == null:
		return false
	var owner := location.state.owner_gang
	if owner_gang == &"rival":
		return owner != GameState.PLAYER_GANG and owner != GameState.NO_GANG and owner != &""
	return owner == owner_gang


func _reason(_ctx: ActionContext) -> String:
	return "Wrong crew runs this place"
