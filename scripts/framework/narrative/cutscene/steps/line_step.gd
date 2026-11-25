class_name LineStep
extends CutsceneStep
## One subtitled line (optionally voiced, optionally also barked over the speaker's head).
## Waits for the line's display time.

## Actor name (resolved like other steps) used for the label, bark and framing; may be empty.
@export var speaker: StringName
## Display name; empty = the speaker node's label or the capitalised [member speaker].
@export var speaker_name := ""
## Supports {vars} from the cutscene ActionContext.
@export_multiline var text := ""
## Seconds on screen; 0 = from the word count.
@export var duration := 0.0
@export var voice: AudioStream
## Also show it as a speech bubble over the speaker.
@export var bark := false
@export var color := NarrativeUI.SPEAKER_COLOR


func begin(director: CutsceneDirector, state: Dictionary) -> void:
	var node := director.resolve_3d(speaker)
	var shown := director.ctx.format(text)
	var seconds := duration if duration > 0.0 else DialogueNode.auto_duration(shown)
	var label := speaker_name
	if label == "":
		label = ActionContext._label_of(node) if node != null and node != GameState.player else String(speaker).capitalize()
		if node != null and node == GameState.player:
			label = "You"
	Narrative.ui.show_line(label, shown, seconds, color)
	Narrative.play_voice(voice)
	if bark and node != null:
		Narrative.bark(node, shown, {"duration": seconds, "force": true})
	director.emit_line(label, shown, seconds)
	state["t"] = 0.0
	state["length"] = seconds


func tick(_director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	state["t"] += delta
	return state["t"] >= state["length"]


func validate() -> PackedStringArray:
	return PackedStringArray() if text != "" else PackedStringArray(["empty line"])
