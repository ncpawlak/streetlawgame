class_name TriggerZone
extends Area3D
## Reusable box trigger. Fires [signal triggered] when the player is inside and every rule holds:
## [member mode] (on foot / in any vehicle), [member vehicle_tag] (a specific mission-tagged
## vehicle), [member require_stopped], and [member conditions]. Containment is checked geometrically
## each physics frame (no physics layers needed), so it works for steps and standalone.
## Zones post "zone_entered" / "zone_exited" mission events and apply [member effects] on trigger.

signal triggered(actor: Node)
signal released(actor: Node)

const GROUP := &"trigger_zones"

enum Mode { ANY, ON_FOOT, IN_VEHICLE }

## Id steps use to find the zone (EnterZoneStep, DeliverVehicleStep, ParkVehicleStep...).
@export var zone_id: StringName
@export var size := Vector3(8, 4, 8):
	set(value):
		size = value
		_update_shape()
@export var mode := Mode.ANY
## Only counts while the player drives a vehicle tagged with this mission tag.
@export var vehicle_tag: StringName
@export var require_stopped := false
@export var stop_speed := 1.5
@export var conditions: Array[Condition] = []
@export var effects: Array[Effect] = []
## Disable after the first trigger.
@export var one_shot := false
## Draw a translucent box (greybox / debug). Off for invisible zones.
@export var show_volume := true
@export var color := Color(1.0, 0.8, 0.1, 0.18)

var inside := false
var satisfied := false
var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _done := false


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	if show_volume:
		_mesh = MeshInstance3D.new()
		_mesh.mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = color
		_mesh.material_override = material
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)
	_update_shape()


func _physics_process(_delta: float) -> void:
	var player := GameState.player
	var now_inside := player != null and is_instance_valid(player) and contains_point(player.get_focus_position())
	if now_inside != inside:
		inside = now_inside
		Missions.post_event(&"zone_entered" if inside else &"zone_exited", {"zone_id": zone_id, "zone": self})
	var now := not _done and inside and _rules_met(player)
	if now == satisfied:
		return
	satisfied = now
	if satisfied:
		triggered.emit(player)
		Effect.apply_all(effects, ActionContext.new(player, self))
		if one_shot:
			_done = true
	else:
		released.emit(player)


## True when a world point is inside the box (rotation/scale aware).
func contains_point(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	var half := size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


## True while the player is inside and every rule holds (polled by steps).
func is_satisfied() -> bool:
	var player := GameState.player
	return not _done and player != null and is_instance_valid(player) and contains_point(player.get_focus_position()) and _rules_met(player)


func reset() -> void:
	_done = false
	satisfied = false


func _rules_met(player: Player) -> bool:
	var vehicle: Vehicle = player.current_vehicle
	match mode:
		Mode.ON_FOOT:
			if vehicle != null:
				return false
		Mode.IN_VEHICLE:
			if vehicle == null:
				return false
	if vehicle_tag != &"" and (vehicle == null or not Missions.has_tag(vehicle, vehicle_tag)):
		return false
	if require_stopped and vehicle != null and vehicle.linear_velocity.length() > stop_speed:
		return false
	return Condition.all_met(conditions, ActionContext.new(player, self))


func _update_shape() -> void:
	if _shape != null:
		(_shape.shape as BoxShape3D).size = size
	if _mesh != null:
		(_mesh.mesh as BoxMesh).size = size
