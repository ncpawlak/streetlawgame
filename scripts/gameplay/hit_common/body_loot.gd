class_name BodyLoot
extends Node3D
## A dead body you can search for cash: hold E to take it straight into your wallet. Shared by every
## NPC that can die. Call [method BodyLoot.attach] from the NPC's death code; the loot lives as a
## child named "BodyLoot" on the corpse, so it goes away with it.

signal looted(amount: int, actor: Node)

const NODE_NAME := &"BodyLoot"
const ACTION := &"loot_body"
## Default cash range for a body (inclusive).
const DEFAULT_CASH := Vector2i(20, 80)

@export var cash := 50
## Hold-E time in seconds.
@export var search_time := 1.2

var interactable: Interactable
var _marker: Label3D


## Makes [param body] lootable for [param amount] cash (a random amount in [constant DEFAULT_CASH]
## when negative). Returns null when there's nothing to take or the body already has loot.
static func attach(body: Node3D, amount := -1) -> BodyLoot:
	if body == null or body.has_meta(NODE_NAME):
		return null
	if amount < 0:
		amount = randi_range(DEFAULT_CASH.x, DEFAULT_CASH.y)
	if amount <= 0:
		return null
	var loot := BodyLoot.new()
	loot.name = NODE_NAME
	loot.cash = amount
	body.set_meta(NODE_NAME, true)
	# Deferred: deaths often happen inside physics callbacks, where new areas can't be added.
	body.add_child.call_deferred(loot)
	return loot


static func of(body: Node) -> BodyLoot:
	return body.get_node_or_null(NodePath(NODE_NAME)) as BodyLoot if body != null else null


func _ready() -> void:
	# Corpses are tipped over; keep the prompt and marker upright, just above the body.
	top_level = true
	global_position = get_parent().global_position + Vector3(0.0, 0.4, 0.0) if get_parent() is Node3D else global_position
	_marker = Label3D.new()
	_marker.text = "$"
	_marker.font_size = 64
	_marker.outline_size = 12
	_marker.modulate = Color(0.45, 1.0, 0.5)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.position.y = 0.6
	add_child(_marker)

	interactable = Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt_name = "Body"
	interactable.radius = 1.6
	interactable.focus_priority = 1
	var effect := MethodEffect.create(&"loot")
	effect.pass_actor = true
	var condition := MethodCondition.create(&"can_loot")
	condition.pass_actor = true
	var action := InteractionAction.create(ACTION, "Search the body (${cash})", [effect], [condition])
	action.duration = search_time
	action.progress_text = "Searching the body..."
	interactable.add_action(action)
	interactable.context_builder = func(ctx: ActionContext) -> void: ctx.set_var("cash", cash)
	interactable.target = self
	add_child(interactable)


func can_loot(_actor: Node = null) -> bool:
	return cash > 0


## Gives the cash to the player. Returns the amount taken.
func loot(actor: Node = null) -> int:
	if cash <= 0:
		return 0
	var amount := cash
	cash = 0
	GameState.add_cash(amount)
	EventBus.notify.emit("Searched the body: +$%d" % amount)
	interactable.enabled = false
	_marker.visible = false
	looted.emit(amount, actor)
	return amount
