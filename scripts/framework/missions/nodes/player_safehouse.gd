class_name PlayerSafehouse
extends Node3D
## World piece of a player safehouse ([PlayerSafehouseDef] [member safehouse_id]). Builds, relative
## to itself:
## - a door with an Interactable: "Rest" (heal + save) and "Save game";
## - an arrival TriggerZone round the door that clears heat when unseen;
## - a garage TriggerZone (in front, +Z) with a "Store vehicle" action while driving;
## - a Respawn marker (Missions moves the player's spawn point here on death);
## - a WardrobeSlot Marker3D (group "wardrobe_slots", meta safehouse_id) for the clothing system.
## Locked safehouses show a padlocked grey door and do nothing until Missions.unlock_safehouse().

signal rested
signal arrived(cleared_heat: bool)

const GROUP := &"player_safehouses"
const WARDROBE_GROUP := &"wardrobe_slots"

@export var safehouse_id: StringName
## Door, respawn, garage and wardrobe offsets (local space).
@export var door_offset := Vector3(0, 0, 0)
@export var respawn_offset := Vector3(0, 0.5, 2.5)
@export var garage_offset := Vector3(5, 0, 6)
@export var garage_size := Vector3(4, 3, 6)
@export var wardrobe_offset := Vector3(-1.5, 0, -1.5)
## Build a small greybox shack around the door.
@export var build_greybox := true

var def: PlayerSafehouseDef
var door: Interactable
var arrival_zone: TriggerZone
var garage_zone: TriggerZone
var respawn_marker: Marker3D
var wardrobe_slot: Marker3D
var _door_mesh: MeshInstance3D
var _door_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(GROUP)
	def = ContentDB.find_def(PlayerSafehouseDef.TYPE, safehouse_id) as PlayerSafehouseDef
	if build_greybox:
		_build_greybox()
	_build_door()
	respawn_marker = Marker3D.new()
	respawn_marker.name = "Respawn"
	respawn_marker.position = respawn_offset
	add_child(respawn_marker)
	if def == null or def.has_wardrobe:
		wardrobe_slot = Marker3D.new()
		wardrobe_slot.name = "WardrobeSlot"
		wardrobe_slot.position = wardrobe_offset
		wardrobe_slot.set_meta(&"safehouse_id", safehouse_id)
		wardrobe_slot.add_to_group(WARDROBE_GROUP)
		add_child(wardrobe_slot)
	arrival_zone = TriggerZone.new()
	arrival_zone.name = "Arrival"
	arrival_zone.zone_id = StringName("%s_door" % safehouse_id)
	arrival_zone.size = Vector3(6, 4, 6)
	arrival_zone.position = door_offset + Vector3(0, 1, 1.5)
	arrival_zone.show_volume = false
	arrival_zone.triggered.connect(func(_actor: Node) -> void: on_arrival())
	add_child(arrival_zone)
	# Also catches "arrived while seen, then waited out of sight".
	var poll := Timer.new()
	poll.wait_time = 0.5
	poll.autostart = true
	poll.timeout.connect(func() -> void:
		if arrival_zone.inside and Missions.heat.is_hot() and not Missions.heat.is_seen():
			on_arrival())
	add_child(poll)
	if def == null or def.vehicle_slots > 0:
		garage_zone = TriggerZone.new()
		garage_zone.name = "Garage"
		garage_zone.zone_id = StringName("%s_garage" % safehouse_id)
		garage_zone.size = garage_size
		garage_zone.position = garage_offset + Vector3(0, garage_size.y * 0.5, 0)
		garage_zone.mode = TriggerZone.Mode.IN_VEHICLE
		garage_zone.color = Color(0.3, 0.8, 1.0, 0.15)
		add_child(garage_zone)
		var garage_door := Interactable.new()
		garage_door.prompt_name = "Garage"
		garage_door.radius = maxf(garage_size.x, garage_size.z) * 0.6
		var store := InteractionAction.create(&"store_vehicle", "Store vehicle")
		store.on_foot_only = false
		garage_door.add_action(store)
		garage_door.action_performed.connect(func(_id: StringName, _actor: Node, _ctx: ActionContext) -> void: store_current_vehicle())
		garage_zone.add_child(garage_door)
	Missions.safehouse_unlocked.connect(func(_id: StringName) -> void: refresh())
	refresh()


func label() -> String:
	return def.label() if def != null else String(safehouse_id).capitalize()


func is_unlocked() -> bool:
	return Missions.is_safehouse_unlocked(safehouse_id)


func respawn_position() -> Vector3:
	return respawn_marker.global_position if respawn_marker != null else global_position


func door_position() -> Vector3:
	return to_global(door_offset)


func garage_transform() -> Transform3D:
	return Transform3D(global_basis, to_global(garage_offset + Vector3.UP * 0.6))


func refresh() -> void:
	var unlocked := is_unlocked()
	if door != null:
		door.enabled = unlocked
	if garage_zone != null:
		garage_zone.visible = unlocked
		garage_zone.set_physics_process(unlocked)
	arrival_zone.set_physics_process(unlocked)
	if _door_material != null:
		_door_material.albedo_color = Color(0.25, 0.55, 0.3) if unlocked else Color(0.35, 0.35, 0.35)


## Heals the player and saves the game.
func rest() -> void:
	if not is_unlocked():
		return
	var player := GameState.player
	if player != null and (def == null or def.heal):
		player.heal(player.max_health)
	SaveGame.save_game()
	EventBus.notify.emit("Rested at %s. Game saved." % label())
	rested.emit()


## Arrival at the door: clears heat if nobody is watching, else knocks some off.
func on_arrival() -> bool:
	if not is_unlocked() or not Missions.heat.is_hot():
		return false
	var cleared := false
	if (def == null or def.clear_heat_when_unseen) and not Missions.heat.is_seen():
		Missions.heat.clear()
		cleared = true
		EventBus.notify.emit("You lay low at %s. The heat is off." % label())
	elif def != null and def.heat_reduce > 0.0:
		Missions.heat.reduce(def.heat_reduce)
	arrived.emit(cleared)
	return cleared


func store_current_vehicle() -> bool:
	var player := GameState.player
	if not is_unlocked() or player == null or player.current_vehicle == null:
		return false
	var slots := def.vehicle_slots if def != null else 2
	if Missions.stored_count(safehouse_id) >= slots:
		EventBus.notify.emit("The garage is full.")
		return false
	if garage_zone != null and not garage_zone.contains_point(player.current_vehicle.global_position):
		return false
	Missions.store_vehicle(safehouse_id, player.current_vehicle)
	EventBus.notify.emit("Vehicle stored at %s." % label())
	return true


func _build_door() -> void:
	_door_mesh = MeshInstance3D.new()
	_door_mesh.name = "Door"
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 2.2, 0.15)
	_door_mesh.mesh = box
	_door_mesh.position = door_offset + Vector3(0, 1.1, 0)
	_door_material = StandardMaterial3D.new()
	_door_mesh.material_override = _door_material
	add_child(_door_mesh)
	door = Interactable.new()
	door.prompt_name = label()
	door.radius = 2.2
	door.position = door_offset + Vector3(0, 1, 0.6)
	door.add_action(InteractionAction.create(&"rest", "Rest (heal + save)"))
	door.add_action(InteractionAction.create(&"save", "Save game"))
	door.action_performed.connect(_on_door_action)
	add_child(door)


func _on_door_action(action_id: StringName, _actor: Node, _ctx: ActionContext) -> void:
	match action_id:
		&"rest":
			rest()
		&"save":
			if SaveGame.save_game():
				EventBus.notify.emit("Game saved.")


func _build_greybox() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.82, 0.74, 0.6)
	for part: Array in [
		[Vector3(6, 3, 0.3), Vector3(0, 1.5, -0.2)],
		[Vector3(0.3, 3, 5), Vector3(-3, 1.5, -2.6)],
		[Vector3(0.3, 3, 5), Vector3(3, 1.5, -2.6)],
		[Vector3(6, 0.3, 5.3), Vector3(0, 3.1, -2.6)],
	]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mesh.mesh = box
		mesh.position = door_offset + (part[1] as Vector3)
		mesh.material_override = material
		add_child(mesh)
