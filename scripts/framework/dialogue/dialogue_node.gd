class_name DialogueNode
extends Resource
## One line of a conversation plus the player's replies. No choices = the conversation can only be left.

@export var id: StringName = &"start"
## &"npc" or &"player"; the view shows the occupant's name for &"npc".
@export var speaker: StringName = &"npc"
## Supports {vars} (ActionContext.format), e.g. "{occupant} eyes the register."
@export_multiline var text := ""
## Applied when the node is entered.
@export var on_enter: Array[Effect] = []
@export var choices: Array[DialogueChoice] = []
## Recorded as the conversation's outcome when entered (e.g. &"recruited"), for listeners and tests.
@export var outcome: StringName = &""