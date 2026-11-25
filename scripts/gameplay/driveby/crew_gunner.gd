class_name CrewGunner
extends Node3D
## A crew member riding shotgun in the player's car. While the player drives, they pick the closest
## rival (on foot or in a chasing car) in range and sight and fire bursts out of the window.
## Add as a child of the [Vehicle]; kills are credited to the car, and so to the player.

@export var weapon_id: StringName = &"smg"
@export var gun_range := 30.0
@export var damage_scale := 0.6
@export var extra_spread := 2.0
## Gang whose members and chase cars count as targets.
@export var enemy_gang: StringName = &"vipers"

var weapons: WeaponInventory

var _car: Vehicle
var _burst_left := 0
var _pause := 0.0


func _ready() -> void:
	_car = get_parent() as Vehicle
	weapons = WeaponInventory.new()
	weapons.name = "Weapons"
	weapons.starting_weapon_ids = [weapon_id]
	weapons.starting_magazines = 0
	weapons.infinite_reserve = true
	weapons.damage_scale = damage_scale
	weapons.extra_spread = extra_spread
	add_child(weapons)
	_build_body()


func _physics_process(delta: float) -> void:
	if _car == null or _car.driver == null or _car.is_wrecked():
		return
	if _pause > 0.0:
		_pause -= delta
		return
	var target := find_target()
	if target == null:
		return
	var muzzle := _car.global_position + Vector3.UP * 1.7 - _car.global_basis.x * 0.8
	var aim := target.global_position + Vector3.UP
	var exclude: Array[RID] = [_car.get_rid(), _car.driver.get_rid()]
	if not weapons.try_fire(_car, muzzle, aim - muzzle, exclude):
		return
	_burst_left -= 1
	if _burst_left <= 0:
		_burst_left = randi_range(4, 7)
		_pause = randf_range(0.4, 0.9)


## Closest live rival or chasing rival car in range with a clear view, or null.
func find_target() -> Node3D:
	var eye := _car.global_position + Vector3.UP * 1.7
	var best: Node3D = null
	var best_distance := gun_range
	for node in get_tree().get_nodes_in_group("gang_members"):
		var member := node as GangMember
		if member.is_alive() and member.gang_id == enemy_gang:
			var distance := eye.distance_to(member.global_position)
			if distance < best_distance and DriveByMission.line_of_sight(self, eye, member.global_position + Vector3.UP):
				best = member
				best_distance = distance
	for node in get_tree().get_nodes_in_group("vehicles"):
		var chase := node as ChaseCar
		if chase != null and chase.is_chasing() and chase.gang_id == enemy_gang:
			var distance := eye.distance_to(chase.global_position)
			if distance < best_distance and DriveByMission.line_of_sight(self, eye, chase.global_position + Vector3.UP):
				best = chase
				best_distance = distance
	return best


func _build_body() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.7
	var material := StandardMaterial3D.new()
	material.albedo_color = GameState.gang_color(GameState.PLAYER_GANG)
	mesh.material = material
	var head := MeshInstance3D.new()
	head.mesh = mesh
	head.position = Vector3(-0.45, 2.05, 0.2)
	add_child(head)
