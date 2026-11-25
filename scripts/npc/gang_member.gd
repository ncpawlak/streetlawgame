class_name GangMember
extends CharacterBody3D
## Rival gang NPC. Loiters on its turf, attacks the player (or the player's car) on sight and drops cash when killed.

## Weapons each rival gang can roll for its members.
const GANG_ARSENAL := {
	&"vipers": [&"pistol", &"pistol", &"smg"],
	&"kings": [&"pistol", &"shotgun", &"smg"],
	&"syndicate": [&"smg", &"rifle", &"shotgun"],
}

@export var gang_id: StringName = &"vipers"
@export var max_health := 60.0
@export var move_speed := 3.5
@export var aggro_range := 22.0
@export var attack_range := 16.0
@export var wander_radius := 6.0
@export var corpse_lifetime := 15.0
## Weapon id to carry. Empty rolls one from the gang's arsenal.
@export var weapon_id: StringName = &""
## NPC damage is scaled down so firefights against groups stay fair.
@export var damage_scale := 0.3
@export var extra_spread := 3.0
## Aggro range while alerted (after being shot at).
@export var alerted_range := 60.0
@export var alert_duration := 10.0
## Chance to drop the weapon on death.
@export_range(0.0, 1.0) var drop_chance := 0.6

var health := 0.0
## District this member defends (&"" for none) and its job there: &"guard" (safehouse) or &"patrol".
var home_district: StringName
var role: StringName

var _home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var weapons: WeaponInventory
var _burst_left := 0
var _burst_pause := 0.0
var _alert_left := 0.0
## Animated body tinted in the gang's colours (see CharacterVisual).
var visual: CharacterVisual
var _dead := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("gang_members")
	collision_layer = 4
	collision_mask = 15
	health = max_health
	_home = global_position
	_wander_target = _home
	if weapon_id == &"":
		weapon_id = GANG_ARSENAL.get(gang_id, [&"pistol"]).pick_random()
	weapons = WeaponInventory.new()
	weapons.name = "Weapons"
	weapons.starting_weapon_ids = [weapon_id]
	weapons.starting_magazines = 0
	weapons.infinite_reserve = true
	weapons.damage_scale = damage_scale
	weapons.extra_spread = extra_spread
	add_child(weapons)
	_burst_pause = randf_range(0.3, 1.5)
	_build_body()


func is_alive() -> bool:
	return not _dead


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_alert_left = maxf(0.0, _alert_left - delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var player := GameState.player
	var target: Node3D = null
	if player != null:
		target = player if player.is_on_foot() else player.current_vehicle
	var move_direction := Vector3.ZERO
	var speed := move_speed
	var range_now := alerted_range if _alert_left > 0.0 else aggro_range
	if target != null and global_position.distance_to(target.global_position) < range_now:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		_face(to_target)
		if to_target.length() > attack_range * 0.6:
			move_direction = to_target.normalized()
		if to_target.length() <= _engage_range():
			_update_attack(target, delta)
	else:
		move_direction = _wander_direction(delta)
		speed *= 0.4
		_face(move_direction)

	velocity.x = move_direction.x * speed
	velocity.z = move_direction.z * speed
	move_and_slide()
	visual.set_aiming(target != null and global_position.distance_to(target.global_position) < range_now)
	visual.update_motion(velocity, delta)


func take_damage(amount: float, source: Node = null) -> void:
	if _dead:
		return
	if source is GangMember and (source as GangMember).gang_id == gang_id:
		return
	health -= amount
	if health <= 0.0:
		_die(source)
		return
	_alert_left = alert_duration
	_flash()


func current_weapon() -> WeaponData:
	return weapons.current().data if weapons.current() else null


## Fires in bursts with pauses between them so NPCs don't hold the trigger down.
func _update_attack(target: Node3D, delta: float) -> void:
	if _burst_pause > 0.0:
		_burst_pause -= delta
		return
	var muzzle := global_position + Vector3(0.0, 1.4, 0.0)
	var exclude: Array[RID] = [get_rid()]
	var aim := target.global_position + Vector3(0.0, 1.0, 0.0) - muzzle
	visual.set_aim_pitch(atan2(aim.y, Vector2(aim.x, aim.z).length()))
	if not weapons.try_fire(self, muzzle, aim, exclude):
		return
	visual.fire()
	_burst_left -= 1
	if _burst_left <= 0:
		var automatic := current_weapon().automatic
		_burst_left = randi_range(3, 6) if automatic else randi_range(1, 2)
		_burst_pause = randf_range(0.6, 1.4)


func _engage_range() -> float:
	var weapon := current_weapon()
	return minf(attack_range, weapon.max_range * 0.9) if weapon else attack_range


func _flash() -> void:
	if visual != null:
		visual.hit()


func _drop_weapon() -> void:
	var weapon := current_weapon()
	if weapon == null or not weapon.uses_ammo() or randf() > drop_chance:
		return
	var pickup := WeaponPickup.create(weapon, weapon.magazine_size * randi_range(1, 2), global_position + Vector3(0.0, 0.1, 0.0), 30.0)
	get_parent().add_child.call_deferred(pickup)


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
	_play_death()
	if killer == GameState.player or (killer is Vehicle and (killer as Vehicle).driver != null):
		GameState.add_cash(randi_range(20, 80))
		GameState.add_respect(10)
	_drop_weapon()
	EventBus.gang_member_killed.emit(self, killer)
	get_tree().create_timer(corpse_lifetime).timeout.connect(queue_free)


## Death animation; subclasses can stage it (e.g. a hit reaction first).
func _play_death() -> void:
	visual.die()


func _build_body() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	var color := GameState.gang_color(gang_id)
	visual = CharacterVisual.create(&"gang", randi())
	visual.set_tint(color.darkened(0.3))
	visual.set_bandana(color)
	visual.set_weapon(current_weapon())
	add_child(visual)
