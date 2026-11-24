class_name StartDialogueEffect
extends Effect
## Asks the dialogue UI to open a conversation (EventBus.dialogue_requested). Empty [member dialogue_id]
## uses the occupant's OccupantDef.dialogue_id.

@export var dialogue_id: StringName = &""


func _apply(ctx: ActionContext) -> void:
	var def := resolve(ctx)
	if def != null:
		EventBus.dialogue_requested.emit(def, ctx)


func resolve(ctx: ActionContext) -> DialogueDef:
	var id := dialogue_id
	if id == &"":
		var occupant := ctx.occupant as Occupant
		id = occupant.def.dialogue_id if occupant != null else &""
	return ContentDB.find_def(DialogueDef.TYPE, id) as DialogueDef if id != &"" else null


func _describe(_ctx: ActionContext) -> String:
	return "Talk"