class_name MovementGround
extends Node3D
## Minimal test ground for working out on-foot movement, combat feel and getting in / out of cars
## before it lands in main. All the behaviour lives in the shared Player, CharacterVisual, Vehicle,
## combat and HUD scripts; this only lays out props to try it against (the tests build it too).
##
## Run: godot --path . res://drivers/movement/movement_driver.tscn
## F5 resets the cars and dummies.

## Wall you vault over, approached from the spawn side (+Z).
const VAULT_WALL := Vector3(-8.0, 0.0, -6.0)
const VAULT_HEIGHT := 1.0
## Knee-high box you step up onto.
const STEP_BOX := Vector3(-4.0, 0.0, -7.0)
const STEP_HEIGHT := 0.6
## Ledges you pull yourself up onto (3 m deep, front face toward the spawn).
const LEDGE_LOW := Vector3(0.0, 0.0, -7.5)
const LEDGE_LOW_HEIGHT := 2.0
const LEDGE_HIGH := Vector3(4.0, 0.0, -7.5)
const LEDGE_HIGH_HEIGHT := 2.6
## Slab you can only stand up from once you're out from under it.
const OVERHANG := Vector3(9.0, 0.0, -5.0)
const OVERHANG_CLEARANCE := 1.45
const CAR_UPRIGHT := Vector3(-7.0, 0.0, 9.0)
const CAR_ON_SIDE := Vector3(0.0, 0.0, 9.0)
const CAR_ON_ROOF := Vector3(7.0, 0.0, 9.0)
## Passive dummies facing away from the spawn (walk up behind one for a silent takedown).
const DUMMIES := [Vector3(13.0, 0.0, 0.0), Vector3(15.0, 0.0, 3.0), Vector3(17.0, 0.0, -2.0)]

var cars: Array[Vehicle] = []
var dummies: Array[GangMember] = []


func _ready() -> void:
	_build_environment()
	_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0), Color(0.32, 0.34, 0.3))
	_box(Vector3(4.0, VAULT_HEIGHT, 0.3), VAULT_WALL + Vector3.UP * VAULT_HEIGHT * 0.5, Color(0.55, 0.45, 0.35))
	_box(Vector3(2.0, STEP_HEIGHT, 2.0), STEP_BOX + Vector3.UP * STEP_HEIGHT * 0.5, Color(0.5, 0.5, 0.55))
	_box(Vector3(3.0, LEDGE_LOW_HEIGHT, 3.0), LEDGE_LOW + Vector3.UP * LEDGE_LOW_HEIGHT * 0.5, Color(0.45, 0.5, 0.6))
	_box(Vector3(3.0, LEDGE_HIGH_HEIGHT, 3.0), LEDGE_HIGH + Vector3.UP * LEDGE_HIGH_HEIGHT * 0.5, Color(0.4, 0.45, 0.6))
	_box(Vector3(3.0, 0.3, 4.0), OVERHANG + Vector3.UP * (OVERHANG_CLEARANCE + 0.15), Color(0.6, 0.4, 0.3))
	for x in [-1.4, 1.4]:
		_box(Vector3(0.2, OVERHANG_CLEARANCE, 0.2), OVERHANG + Vector3(x, OVERHANG_CLEARANCE * 0.5, 1.9), Color(0.6, 0.4, 0.3))
	reset()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F5:
		reset()


## Respawns the three cars (upright, on its side, on its roof) and the dummies.
func reset() -> void:
	for node: Node in cars + dummies:
		if is_instance_valid(node):
			if node is Vehicle and (node as Vehicle).driver != null:
				(node as Vehicle).exit()
			node.queue_free()
	cars.clear()
	dummies.clear()
	cars.append(_car(CAR_UPRIGHT, Basis.IDENTITY, 0.6))
	cars.append(_car(CAR_ON_SIDE, Basis(Vector3.BACK, PI * 0.5), 1.3))
	cars.append(_car(CAR_ON_ROOF, Basis(Vector3.BACK, PI), 2.3))
	for at: Vector3 in DUMMIES:
		var dummy := GangMember.new()
		dummy.gang_id = &"kings"
		dummy.weapon_id = &"pistol"
		dummy.aggro_range = 0.0
		dummy.alerted_range = 0.0
		dummy.move_speed = 0.0
		dummy.wander_radius = 0.0
		dummy.position = at
		add_child(dummy)
		dummies.append(dummy)


func _car(at: Vector3, basis: Basis, height: float) -> Vehicle:
	var car := Vehicle.new()
	car.transform = Transform3D(basis, at + Vector3.UP * height)
	add_child(car)
	return car


func _box(size: Vector3, center: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
	return body


## Light and sky when run as its own scene (the tests build the ground inside main instead).
func _build_environment() -> void:
	if get_tree().current_scene != self:
		return
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.68, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
