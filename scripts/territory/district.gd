class_name District
extends Node3D
## A capturable district: bounds, safehouse, defenders and map overlay. Ownership lives in [Turf]; the
## capture behaviour is the district's [CaptureRule]. Works the same whether generated or placed by hand:
## set [member district_id] (or inline [member data]) and [member extents], and optionally add a child
## [Safehouse] and Marker3D children in group [code]patrol_point[/code].

@export var district_id: StringName
## Inline definition (tests, hand-built maps). Empty uses the content definition for [member district_id].
@export var data: DistrictData
## Size on the XZ plane, in meters.
@export var extents := Vector2(150.0, 150.0)
## Where to build the safehouse (local) when there's no child [Safehouse].
@export var safehouse_position := Vector3.ZERO
@export var safehouse_yaw := 0.0
## Spawn guards/patrols on ready while a rival holds the district.
@export var auto_spawn_defenders := true

var state: DistrictState
var safehouse: Safehouse
## World-space points patrols are spawned at. Falls back to random points inside the bounds.
var patrol_points := PackedVector3Array()

var display_name: String:
	get:
		return data.display_name if data != null else String(district_id)
var owner_gang: StringName:
	get:
		return state.owner if state != null else GameState.NO_GANG
var area_id: StringName:
	get:
		return data.area_id if data != null else &""

var _rule: CaptureRule
var _last_progress := 0.0
var _overlay_material: StandardMaterial3D


func _ready() -> void:
	if district_id == &"" and data != null:
		district_id = TurfContent.id_of(data)
	Turf.register_district(self)
	if data == null:
		data = Turf.district_data(district_id)
	_rule = Turf.capture_rule_for(district_id)
	for child in get_children():
		if child is Safehouse:
			safehouse = child
		elif child is Marker3D and child.is_in_group(&"patrol_point"):
			patrol_points.append((child as Marker3D).global_position)
	if safehouse == null:
		safehouse = Safehouse.new()
		safehouse.name = "Safehouse"
		safehouse.position = safehouse_position
		safehouse.rotation.y = safehouse_yaw
		add_child(safehouse)
	_build_overlay()
	_rule.setup(self)
	EventBus.district_owner_changed.connect(_on_owner_changed)
	if auto_spawn_defenders:
		spawn_defenders()


func _physics_process(delta: float) -> void:
	if state == null or (Turf.current_district_id != district_id and not _rule.is_active(self)):
		return
	_rule.tick(self, delta)
	if state.capture_progress != _last_progress:
		_last_progress = state.capture_progress
		EventBus.capture_progress_changed.emit(district_id, state.capture_progress)


func contains_point(point: Vector3) -> bool:
	var local := point - global_position
	return absf(local.x) <= extents.x * 0.5 and absf(local.z) <= extents.y * 0.5


func capture_rule() -> CaptureRule:
	return _rule


## Swaps the capture rule at runtime (resets any capture in progress).
func set_capture_rule(rule: CaptureRule) -> void:
	_rule = rule
	state.capture_progress = 0.0
	state.capture.clear()
	_rule.setup(self)


## Living guards of the district's current owner (they block the safehouse).
func guards_remaining() -> int:
	return _count_defenders(&"guard")


## Every living defender of the district's current owner.
func defenders_remaining() -> int:
	return _count_defenders(&"")


## The capture rule calls this when [param gang_id] has taken the district.
func complete_capture(gang_id: StringName) -> void:
	Turf.set_district_owner(district_id, gang_id, &"capture")


## Spawns guards at the safehouse and patrols around the district for a rival owner.
func spawn_defenders(seed_value: int = -1) -> void:
	if owner_gang == GameState.PLAYER_GANG or owner_gang == GameState.NO_GANG or data == null:
		return
	var config := data.defenders if data.defenders != null else DefenderConfig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value >= 0 else hash(String(district_id))
	var guard_points := safehouse.guard_points() if safehouse != null else PackedVector3Array()
	for i in config.guard_count:
		var point := guard_points[i % guard_points.size()] if not guard_points.is_empty() else global_position
		_spawn_member(&"guard", point, config, rng)
	for i in config.patrol_count:
		var point: Vector3
		if not patrol_points.is_empty():
			point = patrol_points[rng.randi_range(0, patrol_points.size() - 1)]
		else:
			point = global_position + Vector3(rng.randf_range(-0.4, 0.4) * extents.x, 0.0, rng.randf_range(-0.4, 0.4) * extents.y)
		_spawn_member(&"patrol", point, config, rng)


func _spawn_member(role: StringName, at: Vector3, config: DefenderConfig, rng: RandomNumberGenerator) -> void:
	var member := GangMember.new()
	member.gang_id = owner_gang
	member.home_district = district_id
	member.role = role
	if not config.weapon_ids.is_empty():
		member.weapon_id = config.weapon_ids[rng.randi_range(0, config.weapon_ids.size() - 1)]
	member.position = to_local(at + Vector3(0.0, 0.2, 0.0))
	add_child(member)


func _count_defenders(role: StringName) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"gang_members"):
		var member := node as GangMember
		if member.home_district == district_id and member.gang_id == owner_gang and member.is_alive() \
				and (role == &"" or member.role == role):
			count += 1
	return count


func _on_owner_changed(id: StringName, _gang_id: StringName, _previous: StringName, _reason: StringName) -> void:
	if id == district_id:
		_last_progress = 0.0
		_update_overlay()


func _build_overlay() -> void:
	var plane := PlaneMesh.new()
	plane.size = extents * 0.98
	_overlay_material = StandardMaterial3D.new()
	_overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var overlay := MeshInstance3D.new()
	overlay.name = "MapOverlay"
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
