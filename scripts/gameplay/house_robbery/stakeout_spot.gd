class_name StakeoutSpot
extends Node3D
## A bench across the street. Hold E to stake out the [House]: the view switches to a zoomed camera on
## it, the occupants show up as markers (lights on / movement), and a card sums up the security -
## cameras, alarmed entries, and how long the neighbours take. Press E or move to stop.

signal started
signal ended

@export var watch_time := 2.5
@export var camera_height := 3.2
@export var fov := 38.0

var house: House
var active := false
var interactable: Interactable

var _camera: Camera3D
var _previous_camera: Camera3D
var _actor: Node
var _card: CanvasLayer
var _card_label: Label


func _ready() -> void:
	add_to_group("stakeout_spots")
	var bench := StaticBody3D.new()
	bench.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 0.45, 0.5)
	shape.shape = box
	shape.position.y = 0.225
	bench.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.45, 0.3)
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position.y = 0.225
	bench.add_child(visual)
	add_child(bench)

	var sign_label := Label3D.new()
	sign_label.text = "Stakeout"
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.font_size = 48
	sign_label.pixel_size = 0.006
	sign_label.outline_size = 8
	sign_label.modulate = Color(0.7, 1.0, 0.7)
	sign_label.position.y = 1.6
	add_child(sign_label)

	interactable = Interactable.new()
	interactable.prompt_name = "Stakeout spot"
	interactable.radius = 1.8
	interactable.position.y = 0.6
	var effect := MethodEffect.create(&"begin")
	effect.pass_actor = true
	var condition := MethodCondition.create(&"can_begin")
	condition.reason_text = "Already watching"
	condition.hide_when_unmet = true
	var action := InteractionAction.create(&"stakeout", "Stake out the house", [effect], [condition])
	action.duration = watch_time
	action.progress_text = "Watching the house..."
	interactable.add_action(action)
	add_child(interactable)

	_camera = Camera3D.new()
	_camera.name = "StakeoutCamera"
	_camera.fov = fov
	_camera.position.y = camera_height
	add_child(_camera)

	_card = CanvasLayer.new()
	_card.layer = 5
	_card.visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -436.0
	panel.offset_right = -16.0
	panel.offset_top = 272.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.05, 0.85)
	style.border_color = Color(0.4, 0.9, 0.4)
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	_card_label = Label.new()
	_card_label.add_theme_font_size_override("font_size", 17)
	_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_label.custom_minimum_size.x = 396.0
	panel.add_child(_card_label)
	_card.add_child(panel)
	add_child(_card)


func can_begin() -> bool:
	return not active and house != null


## Starts watching (the hold-E channel has already finished).
func begin(actor: Node = null) -> void:
	if active or house == null:
		return
	active = true
	_actor = actor
	if actor != null:
		actor.set_physics_process(false)
		if actor is CharacterBody3D:
			(actor as CharacterBody3D).velocity = Vector3.ZERO
	_previous_camera = get_viewport().get_camera_3d()
	var look_at_point := house.global_position + Vector3(0.0, 1.0, 0.0)
	_camera.look_at_from_position(global_position + Vector3(0.0, camera_height, 0.0), look_at_point, Vector3.UP)
	var distance := _camera.global_position.distance_to(look_at_point)
	var half_width := house.size().length() * 0.5 + 2.0
	_camera.fov = clampf(rad_to_deg(2.0 * atan(half_width / distance)), 20.0, 70.0)
	_camera.make_current()
	house.set_reveal(true)
	_card_label.text = "STAKEOUT\n\n" + house.stakeout_report() + "\n\n[E] / move to stop watching"
	_card.visible = true
	started.emit()


func end() -> void:
	if not active:
		return
	active = false
	if house != null:
		house.set_reveal(false)
	_card.visible = false
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	if _actor != null and is_instance_valid(_actor):
		_actor.set_physics_process(true)
	_actor = null
	ended.emit()


func _process(_delta: float) -> void:
	if not active:
		return
	# Keep the report live (owners can die, cameras can be shot out).
	_card_label.text = "STAKEOUT\n\n" + house.stakeout_report() + "\n\n[E] / move to stop watching"


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	for action in ["interact", "move_forward", "move_back", "move_left", "move_right", "jump"]:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			end.call_deferred()
			return
