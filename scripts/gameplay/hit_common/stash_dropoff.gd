class_name StashDropoff
extends Node3D
## Where the bag gets cashed in. Hold E to stash it: everything in the actor's [CarryBag] (goods and
## cash) becomes money. Blocked while the cops are on you.

signal cashed_in(amount: int, actor: Node)

@export var police_response: PoliceResponse
@export var stash_time := 1.5
@export var prompt_name := "Stash"
## Carry-over heat: goods from a hot [member heat_area] pay [method HeatMap.payout_multiplier]
## (loose cash pays in full). Null = full price.
var heat_map: HeatMap
var heat_area: StringName = &""
## Fraction of the payout the crew takes (a [HitCrew] sets this via [method HitCrew.payout_cut]).
var crew_cut := 0.0

var interactable: Interactable


func _ready() -> void:
	add_to_group("stashes")
	_build_visual()
	interactable = Interactable.new()
	interactable.prompt_name = prompt_name
	interactable.radius = 2.5
	interactable.position.y = 1.0
	var effect := MethodEffect.create(&"cash_in")
	effect.pass_actor = true
	var condition := MethodCondition.create(&"can_cash_in")
	condition.pass_actor = true
	condition.reason_method = &"cash_in_reason"
	var action := InteractionAction.create(&"stash_bag", "Stash the bag (+${value})", [effect], [condition])
	action.duration = stash_time
	action.progress_text = "Stashing the bag..."
	interactable.add_action(action)
	interactable.context_builder = func(ctx: ActionContext) -> void:
		var bag := CarryBag.of(ctx.actor, false)
		ctx.set_var("value", payout(bag) if bag != null else 0)
	add_child(interactable)


func can_cash_in(actor: Node) -> bool:
	return cash_in_reason(actor) == ""


func cash_in_reason(actor: Node) -> String:
	var bag := CarryBag.of(actor, false)
	if bag == null or bag.is_empty():
		return "Nothing in the bag"
	if police_response != null and police_response.is_wanted():
		return "Lose the cops first"
	return ""


## Converts the bag into cash. Returns the amount paid.
func cash_in(actor: Node) -> int:
	if not can_cash_in(actor):
		return 0
	var bag := CarryBag.of(actor)
	var amount := payout(bag)
	var full := bag.empty()
	GameState.add_cash(amount)
	if amount < full:
		EventBus.notify.emit("Bag stashed: +$%d (heat/crew cut: -$%d)" % [amount, full - amount])
	else:
		EventBus.notify.emit("Bag stashed: +$%d" % amount)
	cashed_in.emit(amount, actor)
	return amount


## What [param bag] is worth here: goods x the heat payout multiplier, plus the loose cash.
func payout(bag: CarryBag) -> int:
	if bag == null:
		return 0
	var multiplier := heat_map.payout_multiplier(heat_area) if heat_map != null else 1.0
	return roundi((bag.goods_value() * multiplier + bag.cash) * (1.0 - clampf(crew_cut, 0.0, 1.0)))


func _build_visual() -> void:
	var color := Color(0.15, 0.6, 0.25)
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 0.9, 0.9)
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.3)
	box.material = material
	var crate := MeshInstance3D.new()
	crate.mesh = box
	crate.position.y = 0.45
	add_child(crate)
	var ring := CylinderMesh.new()
	ring.top_radius = 2.2
	ring.bottom_radius = 2.2
	ring.height = 0.05
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(color, 0.35)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material = ring_material
	var marker := MeshInstance3D.new()
	marker.mesh = ring
	marker.position.y = 0.03
	add_child(marker)
	var tag := Label3D.new()
	tag.text = "$ STASH"
	tag.font_size = 96
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.5, 1.0, 0.6)
	tag.position.y = 2.2
	add_child(tag)
