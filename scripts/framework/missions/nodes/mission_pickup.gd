class_name MissionPickup
extends Node3D
## A lootable mission item (the note on a body, a package on a table). Interacting gives
## [member item_id] to Missions.items and frees the pickup. Tagged with [method tag_for] so
## HaveItemStep can point the waypoint at it.

@export var item_id: StringName
@export var count := 1
@export var prompt := "Pick up"
@export var color := Color(1.0, 0.9, 0.3)

var interactable: Interactable


static func tag_for(item: StringName) -> StringName:
	return StringName("pickup_%s" % item)


static func spawn(parent: Node, at: Vector3, item: StringName, prompt_text := "Pick up") -> MissionPickup:
	var pickup := MissionPickup.new()
	pickup.item_id = item
	pickup.prompt = prompt_text
	parent.add_child(pickup)
	pickup.global_position = at + Vector3.UP * 0.3
	return pickup


func _ready() -> void:
	Missions.tag(self, tag_for(item_id))
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.06, 0.4)
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	mesh.material_override = material
	add_child(mesh)
	interactable = Interactable.new()
	interactable.prompt_name = String(item_id).capitalize()
	interactable.radius = 2.0
	interactable.add_action(InteractionAction.create(&"pick_up", prompt))
	interactable.action_performed.connect(func(_action_id: StringName, _actor: Node, _ctx: ActionContext) -> void: collect())
	add_child(interactable)


func collect() -> void:
	if is_queued_for_deletion():
		return
	Missions.give_item(item_id, count)
	queue_free()
