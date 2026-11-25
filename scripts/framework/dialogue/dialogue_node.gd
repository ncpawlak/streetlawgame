class_name DialogueNode
extends Resource
## One line of a conversation plus the player's replies. No choices and no [member next] = the
## conversation can only be left; no choices but a [member next] = "Continue" (or auto-advance when
## played timed, see DialoguePlayback).

@export var id: StringName = &"start"
## Who says it: &"npc" (the occupant/target), &"player", or any key of ctx.vars["speakers"]
## (e.g. &"nurse"), which maps to a Node or a display name. See DialogueRunner.speaker_name().
@export var speaker: StringName = &"npc"
## Overrides the displayed speaker name (supports {vars}), e.g. "Mister Lou".
@export var speaker_name := ""
## Supports {vars} (ActionContext.format), e.g. "{occupant} eyes the register."
@export_multiline var text := ""
## Applied when the node is entered.
@export var on_enter: Array[Effect] = []
@export var choices: Array[DialogueChoice] = []
## Node to continue to when there are no visible choices (linear lines, cutscenes, phone calls).
@export var next: StringName = &""
## Recorded as the conversation's outcome when entered (e.g. &"recruited"), for listeners and tests.
@export var outcome: StringName = &""
@export_group("Branching")
## Entry gate. When any condition fails the runner jumps to [member else_next] instead (empty = end).
@export var conditions: Array[Condition] = []
@export var else_next: StringName = &""
@export_group("Timing")
## Seconds the line stays up when played timed (cutscenes, phone calls); 0 = from the word count.
@export var duration := 0.0
## Optional voice line played when the node is entered.
@export var voice: AudioStream


## Display time for timed playback.
func display_time(shown_text: String = "") -> float:
	if duration > 0.0:
		return duration
	return DialogueNode.auto_duration(shown_text if shown_text != "" else text)


static func auto_duration(line: String) -> float:
	var words := line.split(" ", false).size()
	return clampf(1.2 + 0.32 * words, 1.5, 7.0)
