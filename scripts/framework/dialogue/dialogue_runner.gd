class_name DialogueRunner
extends RefCounted
## UI-agnostic conversation logic: walks a DialogueDef, filters/labels choices, pays costs, rolls
## checks and applies effects. DialogueView draws it; tests drive it directly.

signal node_entered(node: DialogueNode)
signal ended(dialogue_id: StringName, outcome: StringName)

var def: DialogueDef
var ctx: ActionContext
## Last non-empty DialogueNode.outcome reached.
var outcome: StringName = &""

var _node: DialogueNode


func start(dialogue: DialogueDef, context: ActionContext) -> bool:
	def = dialogue
	ctx = context
	outcome = &""
	_node = null
	if def == null or def.find_node(def.start) == null:
		return false
	EventBus.dialogue_started.emit(def.id, ctx.target)
	_enter(def.start)
	return true


func is_active() -> bool:
	return _node != null


func current() -> DialogueNode:
	return _node


func text() -> String:
	return ctx.format(_node.text) if _node != null else ""


func speaker_name() -> String:
	if _node == null:
		return ""
	return speaker_label(_node)


## Display name for a node's speaker: [member DialogueNode.speaker_name], then ctx.vars["speakers"]
## (Node label or String), then "You" / the occupant or target.
func speaker_label(node: DialogueNode) -> String:
	if node.speaker_name != "":
		return ctx.format(node.speaker_name)
	var speakers: Dictionary = ctx.vars.get("speakers", {})
	var entry: Variant = speakers.get(node.speaker)
	if entry != null and not entry is Node:
		return str(entry)
	if node.speaker == &"player":
		return "You"
	if entry is Node:
		return ActionContext._label_of(entry)
	if node.speaker == &"npc":
		return ActionContext._label_of(ctx.occupant if ctx.occupant != null else ctx.target)
	return String(node.speaker).capitalize()


## The Node saying the current line, when known (for camera framing and barks).
func speaker_node() -> Node:
	if _node == null:
		return null
	var speakers: Dictionary = ctx.vars.get("speakers", {})
	var entry: Variant = speakers.get(_node.speaker)
	if entry is Node:
		return entry
	match _node.speaker:
		&"player":
			return ctx.actor
		&"npc":
			return ctx.occupant if ctx.occupant != null else ctx.target
	return null


func choices() -> Array[DialogueChoice]:
	var result: Array[DialogueChoice] = []
	if _node == null:
		return result
	for choice in _node.choices:
		if choice != null and choice.is_visible(ctx):
			result.append(choice)
	return result


## "" when the choice can be picked, else why not.
func choice_state(choice: DialogueChoice) -> String:
	return choice.unavailable_reason(ctx)


## Picks visible choice [param index]. Returns true when it went through and its check (if any) passed.
func choose(index: int) -> bool:
	var visible := choices()
	if index < 0 or index >= visible.size():
		return false
	var choice := visible[index]
	if choice.unavailable_reason(ctx) != "" or not Cost.pay_all(choice.costs, ctx):
		return false
	var passed := choice.check == null or choice.check.roll(ctx)
	if passed:
		Effect.apply_all(choice.effects, ctx)
		_enter(choice.next)
	else:
		Effect.apply_all(choice.fail_effects, ctx)
		_enter(choice.fail_next)
	return passed


## Moves past a node without visible choices: to its [member DialogueNode.next], or ends.
## Returns false when the current node has choices to pick instead.
func advance() -> bool:
	if _node == null or not choices().is_empty():
		return false
	_enter(_node.next)
	return true


## True when the current node offers no choices but continues to another node.
func can_continue() -> bool:
	return _node != null and choices().is_empty() and _node.next != &""


## Leaves the conversation (e.g. a node with no choices, or the player walks off).
func end() -> void:
	if def == null:
		return
	_node = null
	var finished := def
	def = null
	EventBus.dialogue_ended.emit(finished.id, outcome)
	ended.emit(finished.id, outcome)


func _enter(node_id: StringName) -> void:
	var node := def.find_node(node_id) if node_id != &"" else null
	# Gated nodes redirect to else_next; the hop limit guards against authored loops.
	var hops := 0
	while node != null and not Condition.all_met(node.conditions, ctx) and hops < 32:
		node = def.find_node(node.else_next) if node.else_next != &"" else null
		hops += 1
	if node == null or hops >= 32:
		end()
		return
	_node = node
	if node.outcome != &"":
		outcome = node.outcome
	Effect.apply_all(node.on_enter, ctx)
	if def != null and _node == node:
		node_entered.emit(node)