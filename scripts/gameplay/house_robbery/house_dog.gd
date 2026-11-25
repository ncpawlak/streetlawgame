class_name HouseDog
extends CharacterBody3D
## A guard dog in the yard of a medium / high income [House]. Spots a burglar on foot nearby, growls,
## then barks - and a barking dog starts the neighbours' countdown early ([constant
## PoliceCall.REASON_DOG]) and wakes the owners. Feed it a [constant HitTools.DOG_TREAT] to make a
## friend for life, or shoot it (a gunshot, so the neighbours' countdown starts anyway).

signal barked(dog: HouseDog)
signal fed(dog: HouseDog)
signal died(dog: HouseDog)

enum Mood { IDLE, GROWLING, BARKING, FED, DEAD }

@export var notice_range := 7.0
## Growl this long before barking (time to get a treat out).
@export var growl_time := 1.2
@export var wander_radius := 3.5
@export var move_speed := 2.2
@export var health := 20.0

var mood := Mood.IDLE
var house: Node3D
var police_call: PoliceCall
var interactable: Interactable

var _growl_left := 0.0
var _home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _bark_label: Label3D
var _bark_flash := 0.0
var _body: Node3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("dogs")
	collision_layer = 4
	collision_mask = 1
	_home = position
	_wander_target = _home
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.6, 0.95)
	shape.shape = box
	shape.position.y = 0.3
	add_child(shape)
	_body = Node3D.new()
	add_child(_body)
	var fur := Color(0.45, 0.32, 0.2)
	_part(Vector3(0.36, 0.36, 0.8), Vector3(0.0, 0.45, 0.0), fur)
	_part(Vector3(0.3, 0.3, 0.34), Vector3(0.0, 0.66, 0.5), fur.darkened(0.15))
	_part(Vector3(0.14, 0.12, 0.18), Vector3(0.0, 0.6, 0.72), Color(0.15, 0.1, 0.08))
	for x in [-0.12, 0.12]:
		for z in [-0.28, 0.28]:
			_part(Vector3(0.1, 0.3, 0.1), Vector3(x, 0.15, z), fur.darkened(0.25))
	_part(Vector3(0.06, 0.06, 0.32), Vector3(0.0, 0.6, -0.5), fur)
	_bark_label = Label3D.new()
	_bark_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bark_label.no_depth_test = true
	_bark_label.fixed_size = true
	_bark_label.pixel_size = 0.0018
	_bark_label.font_size = 32
	_bark_label.outline_size = 8
	_bark_label.position.y = 1.3
	_bark_label.visible = false
	add_child(_bark_label)
	interactable = Interactable.new()
	interactable.prompt_name = "dog"
	interactable.radius = 2.2
	interactable.position.y = 0.5
	var effect := MethodEffect.create(&"feed")
	effect.pass_actor = true
	var condition := MethodCondition.create(&"can_feed")
	condition.pass_actor = true
	condition.hide_when_unmet = true
	interactable.add_action(InteractionAction.create(&"feed", "Feed the {target} a treat", [effect], [condition]))
	add_child(interactable)


func label() -> String:
	return "Guard dog"


func is_alive() -> bool:
	return mood != Mood.DEAD


func is_barking() -> bool:
	return mood == Mood.BARKING


func is_friendly() -> bool:
	return mood == Mood.FED


func _physics_process(delta: float) -> void:
	if mood == Mood.DEAD:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	var move := Vector3.ZERO
	var player := GameState.player as Node3D
	match mood:
		Mood.IDLE:
			move = _wander(delta)
			if _notices(player):
				_growl_left = growl_time
				mood = Mood.GROWLING
				_say("grrr...", Color(1.0, 0.75, 0.3))
		Mood.GROWLING:
			_face(player.global_position - global_position if player != null else Vector3.ZERO)
			if not _notices(player):
				mood = Mood.IDLE
				_bark_label.visible = false
			else:
				_growl_left -= delta
				if _growl_left <= 0.0:
					bark()
		Mood.BARKING:
			if player != null:
				_face(player.global_position - global_position)
			_bark_flash -= delta
			if _bark_flash <= 0.0:
				_bark_flash = 0.6
				_bark_label.visible = not _bark_label.visible
		Mood.FED:
			if player != null and player.global_position.distance_to(global_position) > 2.5 and player.global_position.distance_to(_home) < 12.0:
				move = (player.global_position - global_position).normalized()
				move.y = 0.0
	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed
	if move != Vector3.ZERO:
		_face(move)
	move_and_slide()


## Starts barking: the neighbours look out (countdown) and the owners wake up.
func bark() -> void:
	if mood == Mood.DEAD or mood == Mood.FED or mood == Mood.BARKING:
		return
	mood = Mood.BARKING
	_say("WOOF! WOOF!", Color(1.0, 0.3, 0.25))
	if police_call != null:
		var seconds: float = house.call("neighbour_seconds") if house != null and house.has_method("neighbour_seconds") else -1.0
		police_call.start_countdown(PoliceCall.REASON_DOG, seconds)
	if house != null and house.has_method("alive_owners"):
		for owner_node: Homeowner in house.call("alive_owners"):
			owner_node.hear(global_position)
	barked.emit(self)


func can_feed(actor: Node) -> bool:
	var tools := HitTools.of(actor, false)
	return (mood == Mood.IDLE or mood == Mood.GROWLING or mood == Mood.BARKING) and tools != null and tools.has(HitTools.DOG_TREAT)


## Gives it a treat: it's your friend now and won't bark (an already started countdown keeps going).
func feed(actor: Node) -> void:
	if not can_feed(actor) or not HitTools.of(actor).use(HitTools.DOG_TREAT):
		return
	mood = Mood.FED
	_say("*happy chewing*", Color(0.5, 1.0, 0.5))
	EventBus.notify.emit("The dog loves you now")
	fed.emit(self)


func take_damage(amount: float, _source: Node = null) -> void:
	if mood == Mood.DEAD:
		return
	health -= amount
	if health <= 0.0:
		mood = Mood.DEAD
		_bark_label.visible = false
		_body.rotation.z = PI / 2.0
		_body.position.y = 0.2
		collision_layer = 0
		interactable.queue_free()
		EventBus.notify.emit("The dog is down")
		died.emit(self)
		return
	if mood != Mood.FED:
		bark()


func _notices(player: Node3D) -> bool:
	if player == null or not (player as Player).is_on_foot():
		return false
	if player.global_position.distance_to(global_position) > notice_range:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.6, 0), player.global_position + Vector3(0, 1.0, 0), 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _wander(delta: float) -> Vector3:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(2.0, 5.0)
		_wander_target = _home + Vector3(randf_range(-wander_radius, wander_radius), 0.0, randf_range(-wander_radius, wander_radius))
	var to := _wander_target - position
	to.y = 0.0
	return to.normalized() * 0.5 if to.length() > 0.4 else Vector3.ZERO


func _face(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length() > 0.01:
		rotation.y = atan2(direction.x, direction.z)


func _say(text: String, color: Color) -> void:
	_bark_label.text = text
	_bark_label.modulate = color
	_bark_label.visible = true


func _part(part_size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = part_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	_body.add_child(visual)
