class_name Safehouse
extends Node3D
## A district's safehouse: the thing you take to take the district, and later its gang HQ.
## The visual comes from [member SafehouseData.scene_path] (see its scene contract) or a code-built greybox.
## [method can_claim]/[method claim] and [method can_manage]/[method manage] are the interaction hooks.

const DOOR_OFFSET := 1.5

var district: District
var data: SafehouseData

var _visual: Node3D
var _door: Vector3
var _guard_points := PackedVector3Array()
var _tinted: Array[GeometryInstance3D] = []
var _marker_material: StandardMaterial3D


func _ready() -> void:
	district = get_parent() as District
	var district_id := district.district_id if district != null else &""
	if data == null:
		data = Turf.safehouse_data_for(district_id)
	add_to_group(&"safehouses")
	_build_visual()
	_build_marker()
	_update_tint()
	EventBus.district_owner_changed.connect(_on_owner_changed)


## True when an interaction prompt is wired up (otherwise reaching the door starts a takeover).
func has_interaction() -> bool:
	return false


func door_position() -> Vector3:
	return to_global(_door)


func guard_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for point in _guard_points:
		points.append(to_global(point))
	return points


func owner_gang() -> StringName:
	return district.owner_gang if district != null else GameState.NO_GANG


func is_owned_by_player() -> bool:
	return owner_gang() == GameState.PLAYER_GANG


func can_claim(_actor: Node = null) -> bool:
	return district != null and district.capture_rule().can_capture(district, GameState.PLAYER_GANG)


func claim(actor: Node = null) -> bool:
	return district != null and district.capture_rule().begin(district, GameState.PLAYER_GANG, actor)


func can_manage(_actor: Node = null) -> bool:
	return is_owned_by_player()


func manage(_actor: Node = null) -> void:
	if can_manage():
		EventBus.safehouse_manage_requested.emit(district.district_id)


func has_feature(feature: StringName) -> bool:
	return data.features.has(feature)


func _build_visual() -> void:
	var scene := TurfContent.load_asset(data.scene_path) as PackedScene
	if scene != null:
		_visual = scene.instantiate() as Node3D
	if _visual == null:
		_visual = _build_greybox()
	_visual.name = "Visual"
	add_child(_visual)
	var door := _visual.get_node_or_null(^"Door") as Node3D
	_door = door.position if door != null else Vector3(0.0, 0.0, data.footprint.y * 0.5 + DOOR_OFFSET)
	var guards := _visual.get_node_or_null(^"GuardPoints")
	if guards != null:
		for marker in guards.get_children():
			if marker is Node3D:
				_guard_points.append((marker as Node3D).position)
	if _guard_points.is_empty():
		_guard_points = _default_guard_points()
	for node in _visual.find_children("*", "GeometryInstance3D", true, false):
		if node.is_in_group(&"owner_tinted"):
			_tinted.append(node as GeometryInstance3D)


func _build_greybox() -> Node3D:
	var root := Node3D.new()
	var size := Vector3(data.footprint.x, data.height, data.footprint.y)
	var body := StaticBody3D.new()
	body.position.y = size.y * 0.5
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.add_child(_box_mesh(size, Vector3.ZERO, data.greybox_color))
	root.add_child(body)
	# Door, owner-colored banner over it and a flag on the roof.
	root.add_child(_box_mesh(Vector3(2.4, 3.2, 0.2), Vector3(0.0, 1.6, size.z * 0.5 + 0.1), Color(0.15, 0.1, 0.08)))
	var banner := _box_mesh(Vector3(size.x * 0.6, 1.0, 0.25), Vector3(0.0, 4.0, size.z * 0.5 + 0.15), Color.WHITE)
	banner.add_to_group(&"owner_tinted")
	root.add_child(banner)
	var flag := _box_mesh(Vector3(2.5, 1.5, 0.1), Vector3(0.0, size.y + 3.0, 0.0), Color.WHITE)
	flag.add_to_group(&"owner_tinted")
	root.add_child(flag)
	root.add_child(_box_mesh(Vector3(0.15, 4.0, 0.15), Vector3(-1.3, size.y + 2.0, 0.0), Color(0.3, 0.3, 0.3)))
	return root


func _default_guard_points() -> PackedVector3Array:
	var half := data.footprint * 0.5
	var out := 3.5
	return PackedVector3Array([
		Vector3(-2.5, 0.0, half.y + out), Vector3(2.5, 0.0, half.y + out),
		Vector3(half.x + out, 0.0, 0.0), Vector3(-half.x - out, 0.0, 0.0),
		Vector3(-half.x, 0.0, half.y + out + 2.0), Vector3(half.x, 0.0, half.y + out + 2.0),
	])


func _build_marker() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.0, 0.5, 8.0)
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = _marker_material
	var marker := MeshInstance3D.new()
	marker.name = "MapMarker"
	marker.mesh = mesh
	marker.layers = GameState.MAP_LAYER
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.position.y = 85.0
	marker.rotation.y = PI / 4.0
	add_child(marker)


func _box_mesh(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	return instance


func _update_tint() -> void:
	var color := GameState.gang_color(owner_gang())
	for node in _tinted:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		node.material_override = material
	if _marker_material != null:
		_marker_material.albedo_color = color.lightened(0.4)


func _on_owner_changed(id: StringName, _gang_id: StringName, _previous: StringName, _reason: StringName) -> void:
	if district != null and id == district.district_id:
		_update_tint()
