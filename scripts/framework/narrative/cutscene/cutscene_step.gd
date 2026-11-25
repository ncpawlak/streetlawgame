class_name CutsceneStep
extends Resource
## One beat of a CutsceneDef. Steps are shared Resources, so runtime data lives in the [param state]
## Dictionary the director passes in (one per playback).
## Template: [method begin] once, [method tick] every frame until it returns true, and [method skip]
## when the scene is skipped. [method skip] must leave the end state the step would have produced;
## its state is empty when the step never began.

## False = run in the background while the following steps continue (the scene waits for it at the end).
@export var wait := true
## Authoring note (ignored at runtime).
@export var note := ""


func begin(_director: CutsceneDirector, _state: Dictionary) -> void:
	pass


## Returns true when finished.
func tick(_director: CutsceneDirector, _state: Dictionary, _delta: float) -> bool:
	return true


func skip(_director: CutsceneDirector, _state: Dictionary) -> void:
	pass


func validate() -> PackedStringArray:
	return PackedStringArray()


func kind() -> String:
	var script: Script = get_script()
	return script.get_global_name() if script != null else "CutsceneStep"
