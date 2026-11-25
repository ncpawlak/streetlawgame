class_name CutsceneDef
extends ContentDef
## An in-engine scripted sequence (data/cutscenes/<id>.tres): an ordered list of CutsceneSteps
## played by the CutsceneDirector (Narrative.play_cutscene). Steps name actors and markers by node
## name; the director resolves them against the bindings, the stage node and the current scene.

const TYPE := &"cutscenes"

@export var steps: Array[CutsceneStep] = []
@export var skippable := true
## Seconds the skip action must be held.
@export var skip_hold := 1.0
@export var lock_input := true
@export var hide_hud := true
## Slide letterbox bars in for the whole scene.
@export var letterbox := true
## Return to the gameplay camera at the end.
@export var restore_camera := true
## Fade back in at the end if a FadeStep left the screen dark.
@export var clear_fade_on_end := true
## Always applied at the end (watched or skipped). Use it for the guaranteed end state.
@export var on_finish: Array[Effect] = []
## Applied only when skipped, before [member on_finish].
@export var on_skip: Array[Effect] = []


func validate() -> PackedStringArray:
	var issues := super()
	if steps.is_empty():
		issues.append("has no steps")
	for i in steps.size():
		if steps[i] == null:
			issues.append("step %d is empty" % i)
			continue
		for issue in steps[i].validate():
			issues.append("step %d (%s): %s" % [i, steps[i].kind(), issue])
	return issues
