class_name ArmoredVan
extends AnimatableBody3D
## The Viper cash van (#23): drives a [HighwayRoute] loop at a steady speed. The hull is armoured;
## each of its four [VanTire]s can be shot out individually and every flat slows it down. With all
## four flat it pulls onto the shoulder, the guards bail out and fight, and the rear doors can be
## released from the cab (stand at the front and press E). Released doors expose the cargo as
## [LootItem]s.

signal tire_popped(tire: VanTire, flats: int)
## First time (and every time) someone shoots the van or its tires.
signal attacked(source: Node)
signal stopped
signal guards_deployed(guards: Array[Node])
signal doors_released(actor: Node)

enum State { DRIVING, STOPPING, STOPPED }

const TIRE_IDS: Array[StringName] = [&"front_left", &"front_right", &"rear_left", &"rear_right"]
## Speed multiplier by number of flat tires.
const SPEED_BY_FLATS: Array[float] = [1.0, 0.8, 0.62, 0.45, 0.0]
const HULL_SIZE := Vector3(2.3, 2.25, 5.6)
const HULL_BOTTOM := 0.75
## Stand within this distance of the front bumper to release the doors.
const FRONT_REACH := 2.6
## Cargo: [name, value, slots, count]. 12 slots of goods against an 8-slot bag, so you choose.
const CARGO := [
	["Cash sack", 650, 2, 4],
	["Cash bundle", 250, 1, 3],
	["Coin bag", 120, 1, 1],
]

@export var route: HighwayRoute
## Metres per second with four good tires.
@export var base_speed := 17.0
## Lateral offset of the van's lane from the centre line (+ = right).
@export var lane := 3.5
## Where the van pulls over to when it stops.
@export var shoulder := 6.5
@export var start_distance := 0.0
@export var guard_count := 3
## Off for tests that want to place the van by hand.
@export var drive_enabled := true

var state := State.DRIVING
var distance := 0.0
var speed := 0.0
var tires: Array[VanTire] = []
var guards: Array[Node] = []
var doors_open := false
var loot: Array[LootItem] = []
var front_interactable: Interactable
var rear_interactable: Interactable

var _lateral := 0.0
var _wobble := 0.0
var _door_left: Node3D
var _door_right: Node3D
var _door_angle := 0.0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	sync_to_physics = false
	add_to_group("cash_vans")
	distance = start_distance
	_lateral = lane
	speed = base_speed
	_build_hull()
	_build_tires()
	_build_doors()
	_build_interactables()
	if route != null:
		_place()


func _physics_process(delta: float) -> void:
	if route == null:
		return
	if state != State.STOPPED:
		_drive(delta)
	if doors_open and _door_angle < 1.0:
		_door_angle = minf(1.0, _door_angle + delta * 1.5)
		_door_left.rotation.y = -_door_angle * deg_to_rad(110.0)
		_door_right.rotation.y = _door_angle * deg_to_rad(110.0)


func flats() -> int:
	var count := 0
	for tire in tires:
		if tire.is_flat():
			count += 1
	return count


func is_stopped() -> bool:
	return state == State.STOPPED


func get_tire(tire_id: StringName) -> VanTire:
	for tire in tires:
		if tire.tire_id == tire_id:
			return tire
	return null


## Cruising speed for the current number of flats (what the van is slowing toward).
func target_speed() -> float:
	return base_speed * SPEED_BY_FLATS[mini(flats(), SPEED_BY_FLATS.size() - 1)]


## Global position of the front bumper (where the cab's door release is).
func front_point() -> Vector3:
	return to_global(Vector3(0.0, 1.0, HULL_SIZE.z * 0.5 + 0.4))


func rear_point() -> Vector3:
	return to_global(Vector3(0.0, 1.0, -HULL_SIZE.z * 0.5 - 0.6))


## The van is armoured: shots only alert it.
func take_damage(_amount: float, source: Node = null) -> void:
	notify_attacked(source)


func notify_attacked(source: Node) -> void:
	if source is GangMember:
		return
	attacked.emit(source)


func can_release_doors(actor: Node) -> bool:
	return release_reason(actor) == ""


func release_reason(actor: Node) -> String:
	if doors_open:
		return "Already open"
	if state != State.STOPPED:
		return "The van's still moving"
	if actor is Node3D and (actor as Node3D).global_position.distance_to(front_point()) > FRONT_REACH:
		return "Get to the front of the van"
	return ""


## Pops the rear doors from the cab. Only works with the van stopped and [param actor] at the front.
func release_doors(actor: Node) -> bool:
	if not can_release_doors(actor):
		return false
	doors_open = true
	front_interactable.enabled = false
	rear_interactable.enabled = false
	_spawn_loot()
	EventBus.notify.emit("Rear doors released - grab what you can!")
	doors_released.emit(actor)
	return true


## Stops the van on the spot (tests / debug).
func force_stop() -> void:
	for tire in tires:
		if not tire.is_flat():
			tire.pop()
	speed = 0.0
	_lateral = shoulder
	_place()
	_on_stopped()


func _drive(delta: float) -> void:
	var goal := target_speed()
	if state == State.DRIVING and flats() >= tires.size():
		state = State.STOPPING
		EventBus.notify.emit("The van's limping onto the shoulder!")
	if state == State.STOPPING:
		speed = move_toward(speed, 0.0, 6.0 * delta)
		_lateral = move_toward(_lateral, shoulder, 2.0 * delta)
		if speed <= 0.01:
			speed = 0.0
			_on_stopped()
	else:
		speed = move_toward(speed, goal, 4.0 * delta)
	if drive_enabled:
		distance += speed * delta
	_wobble += delta * (4.0 + speed * 0.4)
	_place()


func _place() -> void:
	var transform_on_road := route.global_sample(distance, _lateral)
	var tilt := _tilt()
	global_transform = Transform3D(transform_on_road.basis * Basis.from_euler(tilt), transform_on_road.origin)


## Leans the van toward its flat tires (and shakes a little while driving on them).
func _tilt() -> Vector3:
	var roll := 0.0
	var pitch := 0.0
	for tire in tires:
		if not tire.is_flat():
			continue
		roll += 0.035 if tire.tire_id.ends_with("left") else -0.035
		pitch += 0.025 if tire.tire_id.begins_with("front") else -0.025
	if state != State.STOPPED and flats() > 0:
		roll += sin(_wobble) * 0.01 * flats()
	return Vector3(pitch, 0.0, roll)


func _on_stopped() -> void:
	if state == State.STOPPED:
		return
	state = State.STOPPED
	front_interactable.enabled = true
	rear_interactable.enabled = true
	stopped.emit()
	_deploy_guards()


func _deploy_guards() -> void:
	var parent := get_parent()
	var spots := [Vector3(-2.2, 0.0, 1.6), Vector3(2.2, 0.0, 1.6), Vector3(2.2, 0.0, -2.6), Vector3(-2.2, 0.0, -2.6)]
	for i in guard_count:
		var guard := VanGuard.new()
		guard.name = "Guard%d" % (i + 1)
		guard.weapon_id = VanGuard.WEAPONS[i % VanGuard.WEAPONS.size()]
		var spot: Vector3 = to_global(spots[i % spots.size()])
		spot.y = global_position.y + 0.2
		guard.position = (parent as Node3D).to_local(spot) if parent is Node3D else spot
		parent.add_child(guard)
		guard._alert_left = guard.alert_duration * 2.0
		guards.append(guard)
	EventBus.notify.emit("The guards are bailing out!")
	guards_deployed.emit(guards)


func _spawn_loot() -> void:
	var slot := 0
	for entry in CARGO:
		for n in int(entry[3]):
			var row := slot / 4
			var column := slot % 4
			var at := Vector3(-0.75 + column * 0.5, HULL_BOTTOM + 0.08, -HULL_SIZE.z * 0.5 + 0.35 + row * 0.6)
			var item := LootItem.create(entry[0], int(entry[1]), int(entry[2]), false, at)
			item.color = Color(0.3, 0.7, 0.35) if String(entry[0]).begins_with("Cash") else Color(0.8, 0.7, 0.3)
			item.take_time = 0.5
			item.name = "Loot%d" % slot
			add_child(item)
			item.interactable.radius = 2.4
			loot.append(item)
			item.taken.connect(func(taken: LootItem, _actor: Node) -> void: loot.erase(taken))
			slot += 1


func _build_hull() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = HULL_SIZE
	shape.shape = box
	shape.position = Vector3(0.0, HULL_BOTTOM + HULL_SIZE.y * 0.5, 0.0)
	add_child(shape)
	var body_color := Color(0.78, 0.78, 0.74)
	# Hollow cargo box (so the open doors show the cargo), cab, windshield, bumpers, stripe, light bar.
	var cargo_length := HULL_SIZE.z - 1.6
	var cargo_z := -0.8
	var wall := 0.08
	var inside := Color(0.22, 0.22, 0.22)
	_box(Vector3(HULL_SIZE.x, wall, cargo_length), Vector3(0.0, HULL_BOTTOM + wall * 0.5, cargo_z), inside)
	_box(Vector3(HULL_SIZE.x, wall, cargo_length), Vector3(0.0, HULL_BOTTOM + HULL_SIZE.y - wall * 0.5, cargo_z), body_color)
	for side in [-1.0, 1.0]:
		_box(Vector3(wall, HULL_SIZE.y, cargo_length), Vector3((HULL_SIZE.x - wall) * 0.5 * side, HULL_BOTTOM + HULL_SIZE.y * 0.5, cargo_z), body_color)
	_box(Vector3(HULL_SIZE.x, HULL_SIZE.y, wall), Vector3(0.0, HULL_BOTTOM + HULL_SIZE.y * 0.5, cargo_z + cargo_length * 0.5 - wall * 0.5), inside)
	_box(Vector3(HULL_SIZE.x, HULL_SIZE.y * 0.8, 1.6), Vector3(0.0, HULL_BOTTOM + HULL_SIZE.y * 0.4, HULL_SIZE.z * 0.5 - 0.8), body_color.darkened(0.1))
	_box(Vector3(HULL_SIZE.x - 0.2, 0.6, 0.05), Vector3(0.0, HULL_BOTTOM + 1.3, HULL_SIZE.z * 0.5 + 0.01), Color(0.15, 0.2, 0.25))
	_box(Vector3(HULL_SIZE.x + 0.1, 0.3, 0.3), Vector3(0.0, HULL_BOTTOM + 0.1, HULL_SIZE.z * 0.5 + 0.1), Color(0.2, 0.2, 0.2))
	_box(Vector3(HULL_SIZE.x + 0.1, 0.3, 0.3), Vector3(0.0, HULL_BOTTOM + 0.1, -HULL_SIZE.z * 0.5 - 0.1), Color(0.2, 0.2, 0.2))
	for side in [-1.0, 1.0]:
		_box(Vector3(0.04, 0.25, HULL_SIZE.z - 1.8), Vector3((HULL_SIZE.x * 0.5 + 0.01) * side, HULL_BOTTOM + 1.2, -0.8), Color(0.1, 0.45, 0.2))
	_box(Vector3(1.2, 0.15, 0.3), Vector3(0.0, HULL_BOTTOM + HULL_SIZE.y * 0.8 + 0.08, HULL_SIZE.z * 0.5 - 0.6), Color(1.0, 0.6, 0.1))
	var label := Label3D.new()
	label.text = "SECURE TRANSPORT"
	label.font_size = 64
	label.modulate = Color(0.1, 0.4, 0.2)
	label.position = Vector3(HULL_SIZE.x * 0.5 + 0.02, HULL_BOTTOM + 1.65, -0.8)
	label.rotation.y = PI / 2.0
	add_child(label)
	var other := label.duplicate() as Label3D
	other.position.x = -other.position.x
	other.rotation.y = -PI / 2.0
	add_child(other)


func _build_tires() -> void:
	var offsets := {
		&"front_left": Vector3(1.2, 0.5, 1.8),
		&"front_right": Vector3(-1.2, 0.5, 1.8),
		&"rear_left": Vector3(1.2, 0.5, -1.8),
		&"rear_right": Vector3(-1.2, 0.5, -1.8),
	}
	for tire_id in TIRE_IDS:
		var tire := VanTire.new()
		tire.name = "Tire_%s" % tire_id
		tire.tire_id = tire_id
		tire.van = self
		tire.position = offsets[tire_id]
		add_child(tire)
		tire.popped.connect(_on_tire_popped)
		tires.append(tire)


func _on_tire_popped(tire: VanTire) -> void:
	var count := flats()
	EventBus.notify.emit("Tire out! (%d/4)" % count)
	tire_popped.emit(tire, count)


func _build_doors() -> void:
	var rear_z := -HULL_SIZE.z * 0.5 - 0.03
	var half := HULL_SIZE.x * 0.5
	_door_left = Node3D.new()
	_door_left.position = Vector3(half, HULL_BOTTOM + HULL_SIZE.y * 0.5, rear_z)
	add_child(_door_left)
	_door_right = Node3D.new()
	_door_right.position = Vector3(-half, HULL_BOTTOM + HULL_SIZE.y * 0.5, rear_z)
	add_child(_door_right)
	for pair in [[_door_left, -1.0], [_door_right, 1.0]]:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(half - 0.02, HULL_SIZE.y - 0.1, 0.06)
		mesh.material = _material(Color(0.7, 0.7, 0.66))
		var door := MeshInstance3D.new()
		door.mesh = mesh
		door.position.x = (half * 0.5) * float(pair[1])
		(pair[0] as Node3D).add_child(door)


func _build_interactables() -> void:
	front_interactable = Interactable.new()
	front_interactable.name = "CabRelease"
	front_interactable.prompt_name = "Cash van cab"
	front_interactable.radius = 2.0
	front_interactable.focus_priority = 5
	front_interactable.position = Vector3(0.0, 1.0, HULL_SIZE.z * 0.5 + 0.4)
	front_interactable.enabled = false
	var release := InteractionAction.create(&"release_doors", "Release rear doors", [_method_effect(&"release_doors")], [_method_condition(&"can_release_doors", &"release_reason")])
	release.duration = 1.2
	release.progress_text = "Hitting the door release..."
	front_interactable.add_action(release)
	add_child(front_interactable)

	rear_interactable = Interactable.new()
	rear_interactable.name = "RearDoors"
	rear_interactable.prompt_name = "Rear doors"
	rear_interactable.radius = 2.0
	rear_interactable.position = Vector3(0.0, 1.0, -HULL_SIZE.z * 0.5 - 0.6)
	rear_interactable.enabled = false
	var locked := InteractionAction.create(&"open", "Open rear doors", [], [_method_condition(&"rear_doors_unlocked", &"rear_doors_reason")])
	rear_interactable.add_action(locked)
	add_child(rear_interactable)


func rear_doors_unlocked(_actor: Node = null) -> bool:
	return false


func rear_doors_reason(_actor: Node = null) -> String:
	return "Locked - release them from the cab (front)"


func _method_effect(method: StringName) -> Effect:
	var effect := MethodEffect.create(method)
	effect.pass_actor = true
	return effect


func _method_condition(method: StringName, reason: StringName) -> Condition:
	var condition := MethodCondition.create(method)
	condition.pass_actor = true
	condition.reason_method = reason
	return condition


func _box(size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	add_child(visual)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
