class_name StickUpNpc
extends CharacterBody3D
## A civilian in a stick-up: the clerk, a customer in the shop, a bystander on the street or the
## shopkeeper of a neighbouring business. [StickUpController] drives the state changes; this node only
## acts them out (moves, raises hands, phones the cops) and reports damage and death.

signal died(npc: StickUpNpc, killer: Node)
signal hurt(npc: StickUpNpc, source: Node)
signal state_changed(npc: StickUpNpc, state: State)
## Finished a phone call to the police.
signal called_cops(npc: StickUpNpc)

enum Role { CLERK, CUSTOMER, BYSTANDER, NEIGHBOUR }
enum State {
	CALM, ## Going about their business.
	WARY, ## Saw a gun: stops, watches the player, hands half up.
	HELD_UP, ## Clerk only: being aimed at, emptying the register into the bag.
	COWERING, ## Hands up, stays put.
	FLEEING, ## Running away from the player.
	CALLING, ## On the phone to the cops.
	HOSTILE, ## Armed clerk who went for the gun under the counter.
	DEAD,
}

const STATE_ICONS := {
	State.CALM: "", State.WARY: "?", State.HELD_UP: "$", State.COWERING: "!",
	State.FLEEING: "!!", State.CALLING: "911", State.HOSTILE: "X", State.DEAD: "",
}

@export var role := Role.CUSTOMER
@export var max_health := 40.0
@export var walk_speed := 1.4
@export var run_speed := 5.0
@export var wander_radius := 2.0
## Seconds on the phone before the call goes through.
@export var call_duration := 3.0
@export var body_color := Color(0.7, 0.6, 0.5)
@export var corpse_lifetime := 60.0
## Cash on the body when killed (searched with hold E, see [BodyLoot]).
@export var loot_cash := BodyLoot.DEFAULT_CASH
## Armed clerks fight back with this weapon when they turn HOSTILE.
@export var weapon_id: StringName = &""

var health := 0.0
var state := State.CALM
## Seconds left on an active phone call.
var call_left := 0.0
var home := Vector3.ZERO
## Node the NPC is reacting to (usually the player).
var threat: Node3D
var weapons: WeaponInventory

var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## The animated character model (see [CharacterVisual]).
var visual: CharacterVisual
var _hands_up: HandsUpModifier
var _icon: Label3D
var _phone: MeshInstance3D
var _fire_pause := 0.0
var _held_left := 0.0

## Seconds a [method hold] lasts without being renewed.
const HOLD_TIME := 0.5


func _ready() -> void:
	add_to_group("stick_up_npcs")
	if role in [Role.CLERK, Role.CUSTOMER]:
		add_to_group("hostages")
	collision_layer = 4
	collision_mask = 15
	health = max_health
	home = global_position
	_wander_target = home
	if weapon_id != &"":
		weapons = WeaponInventory.new()
		weapons.name = "Weapons"
		weapons.starting_weapon_ids = [weapon_id]
		weapons.starting_magazines = 0
		weapons.infinite_reserve = true
		weapons.damage_scale = 0.35
		weapons.extra_spread = 4.0
		add_child(weapons)
	_build_body()
	_apply_state_visuals()


func is_alive() -> bool:
	return state != State.DEAD


## Crew muscle keeps this NPC covered (hit_common's CrewMember calls this every tick on nodes in the
## "hostages" group): they put their hands up and stay put, and a call in progress is dropped.
func hold(by: Node3D) -> void:
	if state == State.DEAD:
		return
	_held_left = HOLD_TIME
	if threat == null:
		threat = by
	if state in [State.CALM, State.WARY, State.FLEEING, State.CALLING]:
		state = State.CALM if state == State.CALLING else state
		set_state(State.COWERING)


func is_held() -> bool:
	return _held_left > 0.0


func label() -> String:
	return ["Clerk", "Customer", "Bystander", "Shopkeeper"][role]


## Changes behaviour. Ignored once dead. While held by crew muscle, an NPC won't run, phone or fight.
func set_state(next: State) -> void:
	if state == State.DEAD or next == state:
		return
	if is_held() and next in [State.FLEEING, State.CALLING, State.HOSTILE]:
		return
	state = next
	if state == State.CALLING:
		call_left = call_duration
	_apply_state_visuals()
	state_changed.emit(self, state)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_held_left = maxf(0.0, _held_left - delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var move := Vector3.ZERO
	var speed := walk_speed
	match state:
		State.CALM:
			move = _wander(delta)
		State.WARY, State.HELD_UP, State.COWERING:
			_face_threat()
		State.FLEEING:
			move = _away_from_threat()
			speed = run_speed
		State.CALLING:
			call_left -= delta
			if call_left <= 0.0:
				set_state(State.COWERING)
				called_cops.emit(self)
		State.HOSTILE:
			_face_threat()
			_shoot_at_threat(delta)
	velocity.x = move.x * speed
	velocity.z = move.z * speed
	move_and_slide()
	if move.length_squared() > 0.01:
		rotation.y = atan2(-move.x, -move.z)
	visual.update_motion(velocity, delta)


func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health <= 0.0:
		_die(source)
		return
	visual.hit()
	hurt.emit(self, source)


func _die(killer: Node) -> void:
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	set_physics_process(false)
	_apply_state_visuals()
	visual.die()
	BodyLoot.attach(self, randi_range(loot_cash.x, loot_cash.y))
	state_changed.emit(self, state)
	died.emit(self, killer)
	if corpse_lifetime > 0.0:
		get_tree().create_timer(corpse_lifetime, false).timeout.connect(queue_free)


func _wander(delta: float) -> Vector3:
	if wander_radius <= 0.0:
		return Vector3.ZERO
	_wander_timer -= delta
	var offset := _wander_target - global_position
	offset.y = 0.0
	if _wander_timer <= 0.0 or offset.length() < 0.3:
		_wander_timer = randf_range(2.0, 5.0)
		_wander_target = home + Vector3(randf_range(-wander_radius, wander_radius), 0.0, randf_range(-wander_radius, wander_radius))
		return Vector3.ZERO
	return offset.normalized()


func _away_from_threat() -> Vector3:
	if threat == null or not is_instance_valid(threat):
		return Vector3.ZERO
	var away := global_position - threat.global_position
	away.y = 0.0
	return away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD


func _face_threat() -> void:
	if threat == null or not is_instance_valid(threat):
		return
	var to := threat.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		rotation.y = atan2(-to.x, -to.z)


func _shoot_at_threat(delta: float) -> void:
	if weapons == null or threat == null or not is_instance_valid(threat):
		return
	_fire_pause -= delta
	if _fire_pause > 0.0:
		return
	var muzzle := global_position + Vector3(0.0, 1.4, 0.0)
	var exclude: Array[RID] = [get_rid()]
	if weapons.try_fire(self, muzzle, threat.global_position + Vector3(0.0, 1.0, 0.0) - muzzle, exclude):
		_fire_pause = randf_range(0.8, 1.6)
		visual.fire()


func _apply_state_visuals() -> void:
	if _icon == null:
		return
	_icon.text = STATE_ICONS.get(state, "")
	_icon.modulate = Color(1.0, 0.3, 0.3) if state in [State.CALLING, State.HOSTILE] else Color(1.0, 0.9, 0.3)
	_phone.visible = state == State.CALLING
	_hands_up.target = {State.WARY: 0.5, State.HELD_UP: 1.0, State.COWERING: 1.0}.get(state, 0.0)
	var armed := state == State.HOSTILE and weapons != null and weapons.current() != null
	visual.set_weapon(weapons.current().data if armed else null)
	visual.set_aiming(armed)


func _build_body() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.875
	add_child(shape)

	# Clerks and shopkeepers wear work clothes; everyone else is a random civilian.
	visual = CharacterVisual.create(&"civilian", 1 if role in [Role.CLERK, Role.NEIGHBOUR] else randi())
	add_child(visual)
	visual.set_tint(body_color)
	_hands_up = HandsUpModifier.new()
	_hands_up.name = "HandsUp"
	_hands_up.facing = visual
	visual.skeleton.add_child(_hands_up)
	var phone_mesh := BoxMesh.new()
	phone_mesh.size = Vector3(0.08, 0.16, 0.03)
	phone_mesh.material = _material(Color(0.1, 0.1, 0.1))
	_phone = MeshInstance3D.new()
	_phone.mesh = phone_mesh
	_phone.position = Vector3(0.22, 1.6, -0.1)
	add_child(_phone)

	_icon = Label3D.new()
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.font_size = 64
	_icon.outline_size = 12
	_icon.pixel_size = 0.005
	_icon.position.y = 2.2
	add_child(_icon)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
