class_name VanGuard
extends GangMember
## Armoured-transport guard. Bails out of the stopped [ArmoredVan] and fights to protect it.
## In group "hostages": crew muscle ([HitCrew]) in range calls [method hold] and the guard puts its
## hands up - no moving, no shooting - until the muscle walks off.

const WEAPONS: Array[StringName] = [&"smg", &"shotgun", &"pistol"]
## Seconds a hold lasts after the last [method hold] call (the muscle calls it every frame).
const HOLD_GRACE := 0.5
## Security-company uniform (tints the SWAT model).
const UNIFORM := Color(0.42, 0.4, 0.3)

var held_by: Node3D
var _held_left := 0.0


func _init() -> void:
	gang_id = &"armored_guard"
	max_health = 90.0
	move_speed = 3.0
	aggro_range = 40.0
	attack_range = 18.0
	alerted_range = 70.0
	alert_duration = 30.0
	wander_radius = 3.0
	damage_scale = 0.35
	drop_chance = 0.5


func _ready() -> void:
	if weapon_id == &"":
		weapon_id = WEAPONS.pick_random()
	super._ready()
	add_to_group("van_guards")
	add_to_group("hostages")


func _physics_process(delta: float) -> void:
	_held_left = maxf(0.0, _held_left - delta)
	if _dead or not is_held():
		super._physics_process(delta)
		return
	_alert_left = 0.0
	velocity = Vector3(0.0, velocity.y - (_gravity * delta if not is_on_floor() else 0.0), 0.0)
	_face(held_by.global_position - global_position)
	move_and_slide()
	visual.set_aiming(false)
	visual.update_motion(velocity, delta)


## Crew muscle has a gun on them: hands up, no fighting while held. Called every frame in range.
func hold(by: Node3D) -> void:
	if _dead:
		return
	held_by = by
	_held_left = HOLD_GRACE


func is_held() -> bool:
	return _held_left > 0.0 and held_by != null and is_instance_valid(held_by)


## Armoured-transport uniform on the SWAT model (helmet + vest) instead of the gang look.
func _make_visual() -> CharacterVisual:
	var body := CharacterVisual.create(&"cop", randi())
	body.set_tint(UNIFORM)
	body.set_weapon(current_weapon())
	return body
