class_name PlayCutsceneEffect
extends Effect
## Plays a CutsceneDef by id (ctx is passed on, so the scene's effects see the same vars).

@export var cutscene_id: StringName


func _apply(ctx: ActionContext) -> void:
	Narrative.play_cutscene(cutscene_id, null, {}, ctx)


func _describe(_ctx: ActionContext) -> String:
	return "Cutscene"
