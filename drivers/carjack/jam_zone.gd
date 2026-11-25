class_name JamZone
extends Node3D
## A covered parking garage: concrete roof on pillars. Its roof blocks tracker signals, so a
## [HotCarTracker] dies after the car sits inside for a few seconds.

@export var size := Vector3(30.0, 5.0, 24.0)


func _ready() -> void:
	add_to_group("tracker_jammers")
	var concrete := Color(0.45, 0.45, 0.47)
	_box(Vector3(size.x, 0.6, size.z), Vector3(0.0, size.y, 0.0), concrete)
	for x: float in [-0.5, 0.5]:
		for z: float in [-0.5, 0.0, 0.5]:
			_box(Vector3(0.8, size.y, 0.8), Vector3(x * (size.x - 1.0), size.y * 0.5, z * (size.z - 1.0)), concrete.darkened(0.2))
	var sign_label := Label3D.new()
	sign_label.text = "PARKING  -  NO SIGNAL"
	sign_label.font_size = 96
	sign_label.position = Vector3(0.0, size.y + 1.2, -size.z * 0.5)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.modulate = Color(0.6, 0.85, 1.0)
	add_child(sign_label)


func contains_point(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5 and local.y >= -1.0 and local.y <= size.y


func _box(box_size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
