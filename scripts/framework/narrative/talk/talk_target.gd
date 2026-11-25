class_name TalkTarget
extends Node3D
## Drop under any NPC to make it talkable: adds a "Talk" interaction that runs the talk-to-NPC flow
## (Narrative.talk: both turn to face each other, camera frames the speaker, DialogueView opens).
## The NPC is the parent node unless [member npc_path] is set.

signal talked(dialogue_id: StringName)

## Speaker name for the prompt and subtitles; empty = the NPC's own label / node name.
@export var display_name := ""
@export var dialogue: DialogueDef
## Used when [member dialogue] is empty.
@export var dialogue_id: StringName
@export var npc_path: NodePath
@export var verb := "Talk to {target}"
@export var radius := 2.2
@export var frame_camera := true
@export var face_player := true
## Pause the world while talking (classic menu conversation). False = world keeps running but
## player input is locked.
@export var pause_world := true
## Gate the Talk action (e.g. FlagCondition "met_nurse" inverted).
@export var conditions: Array[Condition] = []
## Extra DialogueNode.speaker ids -> NodePath (relative to this node) or display name, for group
## conversations (e.g. {&"cop": "../../Officer"}).
@export var speakers: Dictionary = {}

var interactable: Interactable


func _ready() -> void:
	interactable = Interactable.new()
	interactable.name = "TalkInteractable"
	interactable.radius = radius
	interactable.target = self
	interactable.add_action(InteractionAction.create(&"talk", verb, [MethodEffect.create(&"talk", &"target")], conditions))
	add_child(interactable)


func npc() -> Node3D:
	var node := get_node_or_null(npc_path) if not npc_path.is_empty() else get_parent()
	return node as Node3D


func label() -> String:
	return display_name if display_name != "" else ActionContext._label_of(npc())


func resolve_dialogue() -> DialogueDef:
	if dialogue != null:
		return dialogue
	return ContentDB.find_def(DialogueDef.TYPE, dialogue_id) as DialogueDef if dialogue_id != &"" else null


## Starts the conversation (the Talk action calls this). Returns false when busy or misconfigured.
func talk() -> bool:
	var def := resolve_dialogue()
	var who := npc()
	if def == null or who == null:
		push_warning("TalkTarget %s: missing dialogue or npc" % get_path())
		return false
	var map := {}
	if display_name != "":
		map[&"npc"] = display_name
	for key in speakers:
		var value: Variant = speakers[key]
		var node := get_node_or_null(NodePath(str(value))) if value is NodePath or (value is String and str(value).contains("/")) else null
		map[StringName(str(key))] = node if node != null else str(value)
	var ok := Narrative.talk(who, def, {
		"frame_camera": frame_camera,
		"face": face_player,
		"pause": pause_world,
		"speakers": map,
	})
	if ok:
		talked.emit(def.id)
	return ok
