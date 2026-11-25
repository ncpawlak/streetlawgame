class_name CrewMember
extends GangMember
## A greybox homie on the player's crew, filling one [CrewSlot] for a [HitCrew]. Doesn't fight the
## player, isn't shootable and doesn't block doorways (no collision layer). The role AI is
## deliberately simple: walk to the post, sit in the car, or tail the player and hold people.

var crew_role: CrewSlot.Role = CrewSlot.Role.LOOKOUT
var crew: HitCrew

var _tag: Label3D
var _in_car := false


func _init() -> void:
	gang_id = GameState.PLAYER_GANG
	weapon_id = &"pistol"
	max_health = 100.0
	move_speed = 5.5
	aggro_range = 0.0
	drop_chance = 0.0


func _ready() -> void:
	super._ready()
	remove_from_group("gang_members")
	add_to_group("crew")
	collision_layer = 0
	collision_mask = 1
	# Crew model in the player's colours instead of the gang look GangMember builds.
	remove_child(visual)
	visual.free()
	visual = CharacterVisual.create(&"crew", randi())
	visual.set_tint(GameState.gang_color(gang_id).darkened(0.3))
	visual.set_bandana(GameState.gang_color(gang_id))
	visual.set_weapon(current_weapon())
	add_child(visual)
	_tag = Label3D.new()
	_tag.text = CrewSlot.ROLE_NAMES.get(crew_role, "Crew").to_upper()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.fixed_size = true
	_tag.pixel_size = 0.0015
	_tag.font_size = 28
	_tag.outline_size = 8
	_tag.modulate = GameState.gang_color(gang_id).lightened(0.4)
	_tag.position.y = 2.3
	add_child(_tag)


func take_damage(_amount: float, _source: Node = null) -> void:
	pass


func is_in_car() -> bool:
	return _in_car


## Puts the member at their post now (on [method HitCrew.place]).
func place() -> void:
	match crew_role:
		CrewSlot.Role.LOOKOUT:
			_set_in_car(false)
			global_position = crew.lookout_post
		CrewSlot.Role.DRIVER:
			_set_in_car(_car() != null)
			if not _in_car:
				global_position = crew.getaway_spot.origin
		CrewSlot.Role.MUSCLE:
			_set_in_car(false)
			var player := GameState.player
			if player != null:
				global_position = player.global_position + player.global_basis.z * 1.5
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _dead or crew == null:
		return
	var move := Vector3.ZERO
	match crew_role:
		CrewSlot.Role.LOOKOUT:
			move = _walk_to(crew.lookout_post, 0.8)
			if move == Vector3.ZERO:
				_face(Vector3.FORWARD.rotated(Vector3.UP, sin(Time.get_ticks_msec() * 0.0006) * 1.4))
		CrewSlot.Role.DRIVER:
			var car := _car()
			if car != null:
				_set_in_car(true)
				global_position = car.global_position + Vector3(0.0, 0.2, 0.0)
				return
			_set_in_car(false)
			move = _walk_to(crew.getaway_spot.origin, 1.0)
		CrewSlot.Role.MUSCLE:
			var player := GameState.player
			if player == null:
				return
			if not player.is_on_foot():
				_set_in_car(true)
				global_position = player.global_position
				return
			if _in_car:
				_set_in_car(false)
				global_position = player.global_position + player.global_basis.z * 1.5
			move = _walk_to(player.global_position, 2.2)
			_hold_nearby()
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed
	if move != Vector3.ZERO:
		_face(move)
	move_and_slide()
	visual.set_aiming(false)
	visual.update_motion(velocity, delta)


## Holds every owner / hostage in range. Returns how many.
func _hold_nearby() -> int:
	var held := 0
	for group in [&"homeowners", &"hostages"]:
		for node in get_tree().get_nodes_in_group(group):
			var target := node as Node3D
			if target == null or not target.has_method("hold"):
				continue
			if target.has_method("is_alive") and not target.call("is_alive"):
				continue
			if target.global_position.distance_to(global_position) <= CrewSlot.HOLD_RANGE:
				target.call("hold", self)
				held += 1
	return held


func _walk_to(target: Vector3, stop: float) -> Vector3:
	var to := target - global_position
	to.y = 0.0
	if to.length() <= stop:
		return Vector3.ZERO
	if to.length() > 40.0:
		global_position = target
		return Vector3.ZERO
	return to.normalized()


func _car() -> Node3D:
	var car := crew.getaway if crew != null else null
	return car if car != null and is_instance_valid(car) and car.is_inside_tree() else null


func _set_in_car(value: bool) -> void:
	if _in_car == value:
		return
	_in_car = value
	visual.visible = not value
	if _tag != null:
		_tag.text = CrewSlot.ROLE_NAMES.get(crew_role, "Crew").to_upper() + (" (in car, engine running)" if value and crew_role == CrewSlot.Role.DRIVER else "")
