class_name HouseDevice
extends StaticBody3D
## A greybox box the burglar can use: the breaker box outside ([constant BREAKER]: cut the power,
## cameras and lights go dark for a while) or the CCTV recorder inside ([constant DVR]: unplug it,
## the cameras stop recording for the rest of the hit and the footage of you is gone). The [House]
## does the work in [method House.use_device].

const BREAKER := &"breaker"
const DVR := &"dvr"

var kind: StringName = BREAKER
var house: Node3D
var box_size := Vector3(0.5, 0.7, 0.2)
var interactable: Interactable

var _light_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.52, 0.48) if kind == BREAKER else Color(0.12, 0.12, 0.14)
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	add_child(visual)
	var light_mesh := BoxMesh.new()
	light_mesh.size = Vector3(0.06, 0.06, 0.06)
	_light_material = StandardMaterial3D.new()
	_light_material.emission_enabled = true
	light_mesh.material = _light_material
	var light := MeshInstance3D.new()
	light.mesh = light_mesh
	light.position = Vector3(box_size.x * 0.3, box_size.y * 0.3, box_size.z * 0.5)
	add_child(light)
	var tag := Label3D.new()
	tag.text = "BREAKER" if kind == BREAKER else "CCTV REC"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 24
	tag.outline_size = 6
	tag.position.y = box_size.y * 0.5 + 0.25
	add_child(tag)
	interactable = Interactable.new()
	interactable.prompt_name = label().to_lower()
	interactable.radius = 1.8
	var effect := MethodEffect.create(&"use")
	effect.pass_actor = true
	var condition := MethodCondition.create(&"can_use")
	condition.reason_method = &"unavailable_reason"
	var action := InteractionAction.create(&"use", "Cut the power" if kind == BREAKER else "Unplug the recorder", [effect], [condition])
	action.duration = 1.5 if kind == BREAKER else 2.0
	action.progress_text = "Flipping breakers..." if kind == BREAKER else "Pulling the drive..."
	interactable.add_action(action)
	add_child(interactable)
	refresh()


func label() -> String:
	return "Breaker box" if kind == BREAKER else "CCTV recorder"


func can_use() -> bool:
	return house != null and bool(house.call("device_available", kind))


func unavailable_reason() -> String:
	return "Power's already off" if kind == BREAKER else "Already unplugged"


func use(actor: Node) -> void:
	if can_use():
		house.call("use_device", kind, actor)


## Green while live, red once used.
func refresh() -> void:
	if _light_material == null:
		return
	var live := can_use()
	_light_material.albedo_color = Color(0.2, 1.0, 0.3) if live else Color(1.0, 0.2, 0.2)
	_light_material.emission = _light_material.albedo_color
