class_name CrewGunner
extends Node3D
## A crew member riding shotgun in the player's car. While the player drives, they pick the closest
## rival (on foot or in a chasing car) in range and sight and fire bursts out of the window.
## Add as a child of the [Vehicle]; kills are credited to the car, and so to the player.
##
## How well they shoot comes from the crew member's [constant SKILL_ID] level (1-10, see
## [CrewMemberData]): spread, reaction time, burst discipline and range all scale with it, and
## every rival they drop earns shooting xp.

const SKILL_ID := &"shooting"
## Xp the crew member earns per rival the gunner drops.
const XP_PER_KILL := 2

@export var weapon_id: StringName = &"smg"
@export var damage_scale := 0.6
## Gang whose members and chase cars count as targets.
@export var enemy_gang: StringName = &"vipers"
## Skill level used when no [member crew] is assigned.
@export_range(1, 10) var default_skill := 5

## The crew member riding shotgun; their shooting skill drives the stats below.
var crew: CrewMemberData
var weapons: WeaponInventory
var kills := 0
## Animated body leaning out of the passenger window.
var rider: CarRider

## Stats derived from the skill level (refreshed every frame, so skill changes apply live).
var gun_range := 30.0
var extra_spread := 2.0
## Seconds between spotting a new target and opening fire.
var reaction_time := 0.4
var burst_min := 4
var burst_max := 7
var pause_min := 0.4
var pause_max := 0.9

var _car: Vehicle
var _burst_left := 0
var _pause := 0.0
var _target: Node3D
var _reaction_left := 0.0
var _last_health := 0.0


func _ready() -> void:
	_car = get_parent() as Vehicle
	weapons = WeaponInventory.new()
	weapons.name = "Weapons"
	weapons.starting_weapon_ids = [weapon_id]
	weapons.starting_magazines = 0
	weapons.infinite_reserve = true
	weapons.damage_scale = damage_scale
	add_child(weapons)
	apply_skill()
	_build_body()
	if _car != null:
		_last_health = _car.health
		_car.health_changed.connect(_on_car_health_changed)
		_car.exploded.connect(rider.die)


func skill_level() -> int:
	return crew.skill_for(SKILL_ID) if crew != null else clampi(default_skill, 1, CrewMemberData.MAX_SKILL)


## Rookies spray long, wide bursts and are slow to react; veterans fire short, tight bursts fast.
func apply_skill() -> void:
	var t := (skill_level() - 1) / float(CrewMemberData.MAX_SKILL - 1)
	gun_range = lerpf(22.0, 34.0, t)
	extra_spread = lerpf(7.0, 0.5, t)
	reaction_time = lerpf(1.2, 0.15, t)
	burst_min = roundi(lerpf(8.0, 3.0, t))
	burst_max = roundi(lerpf(12.0, 5.0, t))
	pause_min = lerpf(0.25, 0.5, t)
	pause_max = lerpf(0.5, 0.9, t)
	if weapons != null:
		weapons.extra_spread = extra_spread


func _physics_process(delta: float) -> void:
	apply_skill()
	if _car == null or _car.driver == null or _car.is_wrecked():
		rider.idle()
		return
	if _pause > 0.0:
		_pause -= delta
		return
	var target := find_target()
	if target != _target:
		_target = target
		_reaction_left = reaction_time
	if target == null:
		rider.idle()
		return
	rider.aim_at(target.global_position + Vector3.UP)
	if _reaction_left > 0.0:
		_reaction_left -= delta
		return
	var muzzle := _car.global_position + Vector3.UP * 1.7 - _car.global_basis.x * 0.8
	var aim := target.global_position + Vector3.UP
	var exclude: Array[RID] = [_car.get_rid(), _car.driver.get_rid()]
	var member := target as GangMember
	if not weapons.try_fire(_car, muzzle, aim - muzzle, exclude):
		return
	rider.fire()
	if member != null and not member.is_alive():
		_on_kill()
	_burst_left -= 1
	if _burst_left <= 0:
		_burst_left = randi_range(burst_min, burst_max)
		_pause = randf_range(pause_min, pause_max)


func _on_kill() -> void:
	kills += 1
	if crew != null and crew.add_xp(SKILL_ID, XP_PER_KILL):
		EventBus.notify.emit("%s got better at shooting (%d)" % [crew.display_name, skill_level()])


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


func _on_car_health_changed(current: float, _maximum: float) -> void:
	if current < _last_health:
		rider.hit()
	_last_health = current


## The gunner rides on the passenger side (-X, where the muzzle is), in the front seat.
func _build_body() -> void:
	var seed_value := hash(crew.id) & 0xFFFF if crew != null else 7
	rider = CarRider.create(&"crew", seed_value, GameState.gang_color(GameState.PLAYER_GANG), -1.0, 0.2, weapon_id, 0.2)
	add_child(rider)
