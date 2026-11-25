class_name StreetGrid
extends Node3D
## A few greybox city blocks on a square road grid: ground, roads, sidewalks, buildings and
## boundary walls, plus intersection-to-intersection navigation for AI cars.
## Built in code so a gameplay driver can boot without the city generator.

## Intersections per side (roads per axis).
@export var size := 5
## Distance between neighbouring intersections.
@export var pitch := 44.0
@export var road_width := 12.0
## Sidewalk depth between the road edge and building fronts.
@export var sidewalk := 4.0
@export var building_seed := 7

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = building_seed
	_build_ground()
	_build_roads()
	_build_blocks()
	_build_walls()


## World position of intersection [param node] (grid coordinates).
func node_position(node: Vector2i) -> Vector3:
	var half := (size - 1) * 0.5
	return Vector3((node.x - half) * pitch, 0.0, (node.y - half) * pitch)


func nearest_node(world: Vector3) -> Vector2i:
	var half := (size - 1) * 0.5
	return Vector2i(
		clampi(roundi(world.x / pitch + half), 0, size - 1),
		clampi(roundi(world.z / pitch + half), 0, size - 1))


## Next intersection on a shortest road route from [param from] to [param to]. The grid has no
## dead ends, so the longer axis is walked first.
func step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var delta := to - from
	if delta == Vector2i.ZERO:
		return from
	if absi(delta.x) >= absi(delta.y):
		return from + Vector2i(signi(delta.x), 0)
	return from + Vector2i(0, signi(delta.y))


## Half the width of the playable area (outer road edges).
func half_extent() -> float:
	return (size - 1) * 0.5 * pitch + road_width * 0.5


func _build_ground() -> void:
	var extent := half_extent() * 2.0 + 40.0
	_add_static_box(Vector3(extent, 1.0, extent), Vector3(0.0, -0.5, 0.0), Color(0.32, 0.34, 0.3))


func _build_roads() -> void:
	var length := half_extent() * 2.0
	var road_color := Color(0.12, 0.12, 0.13)
	var stripe_color := Color(0.85, 0.75, 0.25)
	for i in size:
		var offset := node_position(Vector2i(i, i))
		_add_mesh(Vector3(road_width, 0.02, length), Vector3(offset.x, 0.01, 0.0), road_color)
		_add_mesh(Vector3(length, 0.02, road_width), Vector3(0.0, 0.012, offset.z), road_color)
		_add_mesh(Vector3(0.15, 0.02, length), Vector3(offset.x, 0.025, 0.0), stripe_color)
		_add_mesh(Vector3(length, 0.02, 0.15), Vector3(0.0, 0.026, offset.z), stripe_color)


func _build_blocks() -> void:
	var block := pitch - road_width
	for i in size - 1:
		for j in size - 1:
			var center := (node_position(Vector2i(i, j)) + node_position(Vector2i(i + 1, j + 1))) * 0.5
			_add_mesh(Vector3(block, 0.04, block), center + Vector3(0.0, 0.02, 0.0), Color(0.5, 0.5, 0.48))
			_build_block_buildings(center, block - sidewalk * 2.0)


## One or two buildings per block; the gap between a pair is an alley you can see through.
func _build_block_buildings(center: Vector3, footprint: float) -> void:
	var parts := _rng.randi_range(1, 2)
	var along_x := _rng.randf() < 0.5
	var gap := 2.0
	var part_size := (footprint - gap * (parts - 1)) / parts
	for p in parts:
		var offset := -footprint * 0.5 + part_size * 0.5 + p * (part_size + gap)
		var height := _rng.randf_range(8.0, 22.0)
		var box_size := Vector3(part_size if along_x else footprint, height, footprint if along_x else part_size)
		var at := center + Vector3(offset if along_x else 0.0, height * 0.5, 0.0 if along_x else offset)
		var tint := _rng.randf_range(0.35, 0.6)
		_add_static_box(box_size, at, Color(tint, tint * 0.92, tint * 0.85))


func _build_walls() -> void:
	var reach := half_extent() + 1.0
	var length := reach * 2.0 + 2.0
	var color := Color(0.25, 0.22, 0.2)
	for side: float in [-1.0, 1.0]:
		_add_static_box(Vector3(1.0, 4.0, length), Vector3(side * reach, 2.0, 0.0), color)
		_add_static_box(Vector3(length, 4.0, 1.0), Vector3(0.0, 2.0, side * reach), color)


func _add_static_box(box_size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = box_size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box(box_size, color)
	body.add_child(mesh)
	add_child(body)


func _add_mesh(box_size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box(box_size, color)
	mesh.position = at
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _box(box_size: Vector3, color: Color) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = box_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	return box
