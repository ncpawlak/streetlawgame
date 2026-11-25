class_name Homeowner
extends GangMember
## Someone who lives in the [House]. Potters about one room. If they see or hear a burglar they get on
## the phone - five seconds later the police are on their way (a WITNESS countdown). Pointing a gun at
## them makes them cower and drop the call; an armed owner fights back instead. Killing them quietly
## (fists, melee) makes no noise; a gunshot starts the neighbours' countdown.

signal spotted_intruder(owner: Homeowner)
signal finished_call(owner: Homeowner)

enum Mood { CALM, PHONING, COWERING, FIGHTING, CALLED }

## Seconds on the phone before the police are told.
@export var call_time := 5.0
## Police arrival countdown once the call is made.
@export var police_eta := 25.0
@export var sight_range := 10.0
@export var hearing_range := 30.0
@export var armed := false

var mood := Mood.CALM
var call_left := 0.0
var police_call: PoliceCall
var house: Node3D

var _calm_down := 0.0
var _marker: Label3D
var _phone: MeshInstance3D


func _init() -> void:
	gang_id = &"civilians"
	weapon_id = &"pistol"
	max_health = 40.0
	move_speed = 2.5
	aggro_range = 0.0
	attack_range = 14.0
	wander_radius = 1.2
	drop_chance = 0.5
	damage_scale = 0.25


func _ready() -> void:
	super._ready()
	add_to_group("homeowners")
	remove_from_group("gang_members")
	_body_material.albedo_color = Color(0.55, 0.42, 0.62) if not armed else Color(0.3, 0.3, 0.3)
	EventBus.gunshot.connect(_on_gunshot)
	_marker = Label3D.new()
	_marker.text = "OWNER"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.fixed_size = true
	_marker.pixel_size = 0.0016
	_marker.font_size = 30
	_marker.outline_size = 8
	_marker.modulate = Color(0.4, 0.9, 1.0)
	_marker.position.y = 2.3
	_marker.visible = false
	add_child(_marker)
	var phone_mesh := BoxMesh.new()
	phone_mesh.size = Vector3(0.08, 0.16, 0.02)
	phone_mesh.material = _material(Color(0.1, 0.1, 0.12))
	_phone = MeshInstance3D.new()
	_phone.mesh = phone_mesh
	_phone.position = Vector3(0.35, 1.55, -0.1)
	_phone.visible = false
	add_child(_phone)


func label() -> String:
	return "Homeowner"


func set_marker_visible(show: bool) -> void:
	if _marker != null:
		_marker.visible = show and is_alive()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var player := GameState.player as Player
	var move_direction := Vector3.ZERO
	match mood:
		Mood.CALM:
			move_direction = _wander_direction(delta)
			_face(move_direction)
			if player != null and _sees(player):
				alert(player.global_position)
		Mood.PHONING:
			_face_away_from(player)
			if _threatened(player):
				_set_mood(Mood.COWERING)
			else:
				call_left -= delta
				if call_left <= 0.0:
					_finish_call()
		Mood.COWERING:
			if _threatened(player):
				_calm_down = 2.0
			else:
				_calm_down -= delta
				if _calm_down <= 0.0:
					_set_mood(Mood.PHONING)
		Mood.FIGHTING:
			if player != null:
				var target: Node3D = player if player.is_on_foot() else player.current_vehicle
				var to_target := target.global_position - global_position
				to_target.y = 0.0
				_face(to_target)
				if to_target.length() <= _engage_range() and _line_of_sight(target):
					_update_attack(target, delta)
		Mood.CALLED:
			_face_away_from(player)
	velocity.x = move_direction.x * move_speed * 0.4
	velocity.z = move_direction.z * move_speed * 0.4
	move_and_slide()


## Something gave the burglar away (seen, heard a kick or a shot, got hit).
func alert(_from: Vector3 = Vector3.ZERO) -> void:
	if _dead or mood != Mood.CALM:
		return
	spotted_intruder.emit(self)
	if armed:
		_set_mood(Mood.FIGHTING)
		EventBus.notify.emit("The owner is armed!")
		return
	call_left = call_time
	_set_mood(Mood.PHONING)
	EventBus.notify.emit("The owner is calling the police! Stop them (%d s)" % ceili(call_time))


func is_phoning() -> bool:
	return mood == Mood.PHONING


func take_damage(amount: float, source: Node = null) -> void:
	super.take_damage(amount, source)
	if not _dead and mood == Mood.CALM:
		alert()


func _finish_call() -> void:
	_set_mood(Mood.CALLED)
	if police_call != null:
		police_call.start_countdown(PoliceCall.REASON_WITNESS, police_eta)
	finished_call.emit(self)


func _set_mood(value: Mood) -> void:
	mood = value
	_phone.visible = value == Mood.PHONING
	var squash := Vector3(1.0, 0.65, 1.0) if value == Mood.COWERING else Vector3.ONE
	for child in get_children():
		if child is MeshInstance3D and child != _phone:
			(child as MeshInstance3D).scale = squash


func _on_gunshot(at: Vector3, shooter: Node) -> void:
	if shooter == self or _dead or not is_inside_tree():
		return
	if global_position.distance_to(at) <= hearing_range:
		alert(at)


## Hears a loud noise (a door being kicked in, glass breaking).
func hear(at: Vector3) -> void:
	if is_inside_tree() and global_position.distance_to(at) <= hearing_range * 0.6:
		alert(at)


func _sees(player: Player) -> bool:
	if not player.is_on_foot():
		return false
	if global_position.distance_to(player.global_position) > sight_range:
		return false
	return _line_of_sight(player)


func _line_of_sight(target: Node3D) -> bool:
	var eye := global_position + Vector3(0.0, 1.6, 0.0)
	var query := PhysicsRayQueryParameters3D.create(eye, target.global_position + Vector3(0.0, 1.2, 0.0), 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## A gun pointed their way from close by.
func _threatened(player: Player) -> bool:
	if player == null or not player.is_on_foot():
		return false
	var slot := player.weapons.current()
	if slot == null or not slot.data.uses_ammo():
		return false
	var to_me := global_position - player.global_position
	to_me.y = 0.0
	if to_me.length() > 8.0:
		return false
	var facing := -player.global_basis.z
	facing.y = 0.0
	return facing.normalized().dot(to_me.normalized()) > 0.8 and _line_of_sight(player)


func _face_away_from(player: Node3D) -> void:
	if player != null:
		_face(global_position - player.global_position)
