class_name Interactable
extends Area3D
## Component that makes any node interactable. Add it as a child (it targets its parent by default) and
## give it actions, either inline in [member actions] or by id from ContentDB ([member action_ids]).
## The player's Interactor focuses the best Interactable in range and shows its actions.

signal action_performed(action_id: StringName, actor: Node, ctx: ActionContext)
signal action_failed(action_id: StringName, actor: Node, reason: String)
signal focus_changed(focused: bool)

## Physics layer 5 ("interaction").
const LAYER := 16
const ACTIONS_TYPE := &"actions"

## Name in the prompt, e.g. "Corner Store". Falls back to the target's label()/name.
@export var prompt_name := ""
@export var actions: Array[InteractionAction] = []
## Shared actions looked up in ContentDB (data/actions/<id>.tres).
@export var action_ids: Array[StringName] = []
## Interaction range in meters.
@export var radius := 2.0:
	set(value):
		radius = value
		if _shape != null:
			(_shape.shape as SphereShape3D).radius = value
## Breaks ties when several interactables are in range (higher wins).
@export var focus_priority := 0
@export var enabled := true
## Node the actions are about. Empty = parent.
@export var target_path: NodePath

var target: Node
## The Location this interactable belongs to (a Location node), if any.
var location: Node3D
## The occupant (NPC) this interactable represents, if any.
var occupant: Node
## Per-interactable memory of action uses ({action_id: {"last", "count"}}); saved with its owner.
var memory: Dictionary = {}
## Optional func(ctx: ActionContext) -> void that fills ctx.vars before anything is evaluated.
var context_builder: Callable

var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	if target == null:
		target = get_node_or_null(target_path) if not target_path.is_empty() else get_parent()
	_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_shape.shape = sphere
	add_child(_shape)
	add_to_group("interactables")


func label() -> String:
	if prompt_name != "":
		return prompt_name
	if target != null and target.has_method("label"):
		return target.call("label")
	return String(target.name if target != null else name)


func add_action(action: InteractionAction) -> void:
	actions.append(action)


func get_actions() -> Array[InteractionAction]:
	var result: Array[InteractionAction] = actions.duplicate()
	for action_id in action_ids:
		var action := ContentDB.get_def(ACTIONS_TYPE, action_id) as InteractionAction
		if action != null:
			result.append(action)
	result.sort_custom(func(a: InteractionAction, b: InteractionAction) -> bool: return a.priority > b.priority)
	return result


func find_action(action_id: StringName) -> InteractionAction:
	for action in get_actions():
		if action.id == action_id:
			return action
	return null


func make_context(actor: Node, action: InteractionAction = null) -> ActionContext:
	var ctx := ActionContext.new(actor, target)
	ctx.interactable = self
	ctx.location = location
	ctx.occupant = occupant
	ctx.memory = memory
	ctx.action = action
	if context_builder.is_valid():
		context_builder.call(ctx)
	return ctx


## Actions to list for [param actor] (available ones plus greyed-out ones that aren't hidden).
func visible_actions(actor: Node) -> Array[InteractionAction]:
	var result: Array[InteractionAction] = []
	if not enabled:
		return result
	for action in get_actions():
		if action.on_foot_only and actor != null and actor.has_method("is_on_foot") and not actor.call("is_on_foot"):
			continue
		if action.is_visible(make_context(actor, action)):
			result.append(action)
	return result


## Runs an action immediately, ignoring its duration. Used by the Interactor at the end of a channel,
## by AI and by tests.
func perform(action_id: StringName, actor: Node) -> bool:
	var action := find_action(action_id)
	if action == null:
		action_failed.emit(action_id, actor, "Unknown action")
		return false
	return run(action, make_context(actor, action))


## Executes [param action] with an existing context (so vars set while channelling survive).
func run(action: InteractionAction, ctx: ActionContext) -> bool:
	if not enabled:
		action_failed.emit(action.id, ctx.actor, "Unavailable")
		return false
	if not action.execute(ctx):
		action_failed.emit(action.id, ctx.actor, action.unavailable_reason(ctx))
		return false
	action_performed.emit(action.id, ctx.actor, ctx)
	EventBus.interaction_performed.emit(self, action.id, ctx.actor)
	return true
