class_name ChopShop
extends Node3D
## Drop-off for stolen cars. Roll a jacked [HotCar] onto the pad and stop: the shop strips it (and
## its tracker) and pays [method payout_for] in cash. It won't open the shutter while a cop can see
## you. The open side faces local -Z.

signal delivered(car: HotCar, payout: int)

@export var drop_radius := 5.0
## Stop (below this speed, m/s) on the pad to deliver.
@export var max_speed := 4.0
## Extra fraction paid for a car whose tracker was already dead (a "cold" car).
@export var clean_bonus := 0.2
## Fraction of the value still paid for a wreck-in-waiting.
@export var min_condition_pay := 0.4
@export var police_response: PoliceResponse

var deliveries := 0
var total_paid := 0

var _pad_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("chop_shops")
	var wall := Color(0.35, 0.3, 0.28)
	_box(Vector3(14.0, 6.0, 0.6), Vector3(0.0, 3.0, 7.0), wall)
	_box(Vector3(0.6, 6.0, 14.0), Vector3(-7.0, 3.0, 0.0), wall)
	_box(Vector3(0.6, 6.0, 14.0), Vector3(7.0, 3.0, 0.0), wall)
	_box(Vector3(14.6, 0.4, 14.6), Vector3(0.0, 6.2, 0.0), wall.darkened(0.3))
	var pad := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = drop_radius
	cylinder.bottom_radius = drop_radius
	cylinder.height = 0.06
	_pad_material = StandardMaterial3D.new()
	_pad_material.albedo_color = Color(1.0, 0.6, 0.1, 0.45)
	_pad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pad_material.emission_enabled = true
	_pad_material.emission = Color(1.0, 0.5, 0.1)
	cylinder.material = _pad_material
	pad.mesh = cylinder
	pad.position.y = 0.05
	add_child(pad)
	var beacon := MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.4
	beam.bottom_radius = 0.4
	beam.height = 40.0
	var beam_material := StandardMaterial3D.new()
	beam_material.albedo_color = Color(1.0, 0.6, 0.1, 0.35)
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material = beam_material
	beacon.mesh = beam
	beacon.position = Vector3(0.0, 26.0, 0.0)
	add_child(beacon)
	var sign_label := Label3D.new()
	sign_label.text = "CHOP SHOP"
	sign_label.font_size = 128
	sign_label.modulate = Color(1.0, 0.7, 0.2)
	sign_label.position = Vector3(0.0, 7.5, -7.0)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign_label)


func _physics_process(_delta: float) -> void:
	var player := GameState.player
	if player == null or not (player.current_vehicle is HotCar):
		return
	var car := player.current_vehicle as HotCar
	if not is_on_pad(car) or car.linear_velocity.length() > max_speed:
		return
	if can_deliver(car) == "":
		deliver(car)


func is_on_pad(car: Node3D) -> bool:
	var offset := car.global_position - global_position
	offset.y = 0.0
	return offset.length() <= drop_radius


## Why [param car] can't be delivered right now, or "" when it can.
func can_deliver(car: HotCar) -> String:
	if car == null or not is_instance_valid(car) or not car.stolen:
		return "That's not a hot car"
	if car.is_wrecked():
		return "That car is scrap"
	if police_response != null and police_response.is_seen():
		return "Lose the cops first - don't lead them to the shop"
	return ""


func payout_for(car: HotCar) -> int:
	var cold := car.tracker == null or not car.tracker.active
	var condition_pay := lerpf(min_condition_pay, 1.0, car.condition())
	return int(round(car.car_value * condition_pay * (1.0 + (clean_bonus if cold else 0.0))))


## Strips [param car] and pays out. Returns the cash paid (0 if refused).
func deliver(car: HotCar) -> int:
	var reason := can_deliver(car)
	if reason != "":
		EventBus.notify.emit(reason)
		return 0
	var cold := car.tracker == null or not car.tracker.active
	var payout := payout_for(car)
	if car.tracker != null:
		car.tracker.stop(&"chopped")
	if car.driver != null:
		car.exit()
	if police_response != null and police_response.is_wanted():
		police_response.stand_down()
	car.remove_from_group("vehicles")
	car.remove_from_group("hot_cars")
	car.queue_free()
	GameState.add_cash(payout)
	deliveries += 1
	total_paid += payout
	EventBus.notify.emit("Chop shop paid $%d for the %s%s" % [payout, car.car_name, " (cold car bonus)" if cold else ""])
	delivered.emit(car, payout)
	return payout


func _box(box_size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
