class_name GangMember
extends CharacterBody3D
## Rival gang NPC. Loiters on its turf, attacks the player on sight and drops cash when killed.

@export var gang_id: StringName = &"vipers"
@export var max_health := 60.0
@export var move_speed := 3.5
@export var aggro_range := 22.0
@export var attack_range := 16.0
@export var wander_radius := 6.0
@export var corpse_lifetime := 15.0
@export var weapon: WeaponData

var health := 0.0
var home_territory: Territory

var _home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _fire_cooldown := 0.0
var _dead := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("gang_members")
	collision_layer = 4
	collision_mask = 15
	health = max_health
	_home = global_position
	_wander_target = _home
	if weapon == null:
		weapon = WeaponData.new()
		weapon.damage = 7.0
		weapon.fire_interval = 1.2
		weapon.spread_degrees = 4.0
		weapon.max_range = 40.0
		weapon.tracer_color = GameState.gang_color(gang_id).lightened(0.4)
	_fire_cooldown = randf_range(0.5, weapon.fire_interval * 2.0)
	_build_body()


func is_alive() -> bool:
	return not _dead


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_fire_cooldown -= delta
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var player := GameState.player
	var move_direction := Vector3.ZERO
	var speed := move_speed
	if player != null and player.is_on_foot() and global_position.distance_to(player.global_position) < aggro_range:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		_face(to_player)
		if to_player.length() > attack_range * 0.6:
			move_direction = to_player.normalized()
		if to_player.length() <= attack_range and _fire_cooldown <= 0.0:
			_shoot_at(player)
	else:
		move_direction = _wander_direction(delta)
		speed *= 0.4
		_face(move_direction)

	velocity.x = move_direction.x * speed
	velocity.z = move_direction.z * speed
	move_and_slide()


func take_damage(amount: float, source: Node = null) -> void:
	if _dead:
		return
	if source is GangMember and (source as GangMember).gang_id == gang_id:
		return
	health -= amount
	if health <= 0.0:
		_die(source)


func _shoot_at(target: Node3D) -> void:
	_fire_cooldown = weapon.fire_interval
	var muzzle := global_position + Vector3(0.0, 1.4, 0.0)
	var exclude: Array[RID] = [get_rid()]
	Hitscan.fire(self, muzzle, target.global_position + Vector3(0.0, 1.0, 0.0) - muzzle, weapon, exclude)


func _wander_direction(delta: float) -> Vector3:
	_wander_timer -= delta
	var offset := _wander_target - global_position
	offset.y = 0.0
	if _wander_timer <= 0.0 or offset.length() < 0.5:
		_wander_timer = randf_range(3.0, 7.0)
		_wander_target = _home + Vector3(randf_range(-wander_radius, wander_radius), 0.0, randf_range(-wander_radius, wander_radius))
		return Vector3.ZERO
	return offset.normalized()


func _face(direction: Vector3) -> void:
	if direction.length_squared() > 0.01:
		rotation.y = atan2(-direction.x, -direction.z)


func _die(killer: Node) -> void:
	_dead = true
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	rotation.x = -PI / 2.0
	position.y += 0.4
	if killer == GameState.player or (killer is Vehicle and (killer as Vehicle).driver != null):
		GameState.add_cash(randi_range(20, 80))
		GameState.add_respect(10)
	EventBus.gang_member_killed.emit(self, killer)
	get_tree().create_timer(corpse_lifetime).timeout.connect(queue_free)


func _build_body() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	var color := GameState.gang_color(gang_id)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.4
	body_mesh.height = 1.8
	body_mesh.material = _material(color.darkened(0.3))
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.position.y = 0.9
	add_child(body)

	var bandana_mesh := BoxMesh.new()
	bandana_mesh.size = Vector3(0.84, 0.15, 0.84)
	bandana_mesh.material = _material(color)
	var bandana := MeshInstance3D.new()
	bandana.mesh = bandana_mesh
	bandana.position.y = 1.55
	add_child(bandana)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
