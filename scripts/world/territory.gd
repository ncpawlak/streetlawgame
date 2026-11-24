class_name Territory
extends Node3D
## A capturable district. Wipe out its defenders, then hold the zone on foot to take it over.

@export var display_name := "District"
@export var owner_gang: StringName = &"none"
## Size of the district on the XZ plane, in meters.
@export var extents := Vector2(150.0, 150.0)
@export var income_per_cycle := 200
@export var capture_time := 8.0
@export var capture_respect := 100

var capture_progress := 0.0

var _overlay_material: StandardMaterial3D


func _ready() -> void:
	GameState.register_territory(self)
	_build_overlay()


func _physics_process(delta: float) -> void:
	if owner_gang == GameState.PLAYER_GANG:
		return
	var player := GameState.player
	var contesting := player != null and player.is_on_foot() \
		and contains_point(player.global_position) and defenders_remaining() == 0
	var previous := capture_progress
	if contesting:
		capture_progress = minf(1.0, capture_progress + delta / capture_time)
	else:
		capture_progress = maxf(0.0, capture_progress - delta / (capture_time * 2.0))
	if capture_progress != previous:
		EventBus.capture_progress_changed.emit(self, capture_progress)
	if capture_progress >= 1.0:
		capture(GameState.PLAYER_GANG)


func contains_point(point: Vector3) -> bool:
	var local := point - global_position
	return absf(local.x) <= extents.x * 0.5 and absf(local.z) <= extents.y * 0.5


func defenders_remaining() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("gang_members"):
		var member := node as GangMember
		if member.home_territory == self and member.is_alive():
			count += 1
	return count


func capture(gang_id: StringName) -> void:
	set_owner_gang(gang_id)
	if gang_id == GameState.PLAYER_GANG:
		GameState.add_respect(capture_respect)
	EventBus.territory_captured.emit(self, gang_id)
	EventBus.notify.emit("%s is now %s turf!" % [display_name, GameState.gang_name(gang_id)])


func set_owner_gang(gang_id: StringName) -> void:
	owner_gang = gang_id
	capture_progress = 0.0
	_update_overlay()


func _build_overlay() -> void:
	var plane := PlaneMesh.new()
	plane.size = extents * 0.98
	_overlay_material = StandardMaterial3D.new()
	_overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var overlay := MeshInstance3D.new()
	overlay.mesh = plane
	overlay.material_override = _overlay_material
	overlay.layers = GameState.MAP_LAYER
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.position.y = 80.0
	add_child(overlay)
	_update_overlay()


func _update_overlay() -> void:
	if _overlay_material == null:
		return
	var color := GameState.gang_color(owner_gang)
	color.a = 0.35
	_overlay_material.albedo_color = color
