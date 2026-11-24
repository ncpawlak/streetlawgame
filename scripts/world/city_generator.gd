class_name CityGenerator
extends Node3D
## Builds the prototype city at runtime: road grid, blocks, buildings, districts, rival crews and parked cars.
## Deterministic for a given [member city_seed]. Replace with hand-built/streamed map chunks later.

const DISTRICT_NAMES := [
	"The Bottoms", "Rail Yards", "Old Harbor",
	"Eastside", "Midtown", "Downtown",
	"Northgate", "Hillcrest", "Riverside",
]
const DISTRICT_OWNERS := [
	&"player", &"vipers", &"syndicate",
	&"vipers", &"kings", &"syndicate",
	&"kings", &"kings", &"syndicate",
]
const CAR_COLORS := [
	Color(0.7, 0.1, 0.1), Color(0.1, 0.2, 0.6), Color(0.85, 0.85, 0.85),
	Color(0.1, 0.1, 0.1), Color(0.2, 0.5, 0.25), Color(0.8, 0.6, 0.1),
]

@export var city_seed := 1337
@export var blocks_per_side := 9
@export var block_size := 48.0
@export var road_width := 14.0
@export var district_blocks := 3
@export var defenders_per_district := 6
@export var parked_vehicles := 16

var player_spawn := Vector3.ZERO
var territories: Array[Territory] = []
## Every building footprint: {center: Vector3, footprint: Vector2, height: float, block: Vector2i,
## block_center: Vector3}. Used by LocationPlacer to put enterable buildings on real lots.
var building_lots: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _materials := {}
var _block := Vector2i.ZERO


func _ready() -> void:
	generate()


func generate() -> void:
	_rng.seed = city_seed
	GameState.city_extent = city_size()
	_build_ground()
	for ix in blocks_per_side:
		for iz in blocks_per_side:
			_build_block(ix, iz)
	_build_districts()
	_spawn_vehicles()


func pitch() -> float:
	return block_size + road_width


func city_size() -> float:
	return blocks_per_side * pitch() + road_width


func block_center(ix: int, iz: int) -> Vector3:
	var start := -city_size() * 0.5 + road_width + block_size * 0.5
	return Vector3(start + ix * pitch(), 0.0, start + iz * pitch())


func _build_ground() -> void:
	var size := city_size() + 200.0
	_add_static_box(Vector3(size, 1.0, size), Vector3(0.0, -0.5, 0.0), _material("asphalt", Color(0.18, 0.18, 0.2)))
	var wall_offset := city_size() * 0.5 + 20.0
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall_size := Vector3(2.0, 30.0, size) if side.x != 0 else Vector3(size, 30.0, 2.0)
		_add_static_box(wall_size, side * wall_offset + Vector3(0.0, 15.0, 0.0), null)


func _build_block(ix: int, iz: int) -> void:
	_block = Vector2i(ix, iz)
	var center := block_center(ix, iz)
	var sidewalk := _material("sidewalk", Color(0.45, 0.45, 0.45))
	_add_mesh_box(Vector3(block_size, 0.1, block_size), center + Vector3(0.0, 0.05, 0.0), sidewalk)

	# Taller buildings toward the middle of the map (downtown).
	var mid := (blocks_per_side - 1) * 0.5
	var centrality := 1.0 - Vector2(ix - mid, iz - mid).length() / (mid * 1.42)
	var max_height := lerpf(10.0, 60.0, clampf(centrality, 0.0, 1.0))

	var roll := _rng.randf()
	if roll < 0.12:
		_add_mesh_box(Vector3(block_size - 6.0, 0.12, block_size - 6.0), center + Vector3(0.0, 0.08, 0.0), _material("park", Color(0.2, 0.45, 0.2)))
	elif roll < 0.4:
		_add_building(center, Vector2(block_size - 8.0, block_size - 8.0), max_height)
	else:
		var lot := block_size * 0.5
		for lx in [-1, 1]:
			for lz in [-1, 1]:
				if _rng.randf() < 0.15:
					continue
				var lot_center := center + Vector3(lx * lot * 0.5, 0.0, lz * lot * 0.5)
				_add_building(lot_center, Vector2(lot - 5.0, lot - 5.0), max_height)


func _add_building(center: Vector3, footprint: Vector2, max_height: float) -> void:
	var height := _rng.randf_range(6.0, max_height)
	var shade := _rng.randi_range(0, 4)
	var palette := [Color(0.55, 0.5, 0.45), Color(0.4, 0.35, 0.33), Color(0.6, 0.6, 0.62), Color(0.35, 0.38, 0.45), Color(0.5, 0.3, 0.25)]
	var material := _material("building_%d" % shade, palette[shade])
	_add_static_box(Vector3(footprint.x, height, footprint.y), center + Vector3(0.0, height * 0.5, 0.0), material)
	building_lots.append({"center": center, "footprint": footprint, "height": height, "block": _block, "block_center": block_center(_block.x, _block.y)})


func _build_districts() -> void:
	var per_side := blocks_per_side / district_blocks
	var extent := district_blocks * pitch()
	for dz in per_side:
		for dx in per_side:
			var index := dz * per_side + dx
			var first := block_center(dx * district_blocks, dz * district_blocks)
			var last := block_center((dx + 1) * district_blocks - 1, (dz + 1) * district_blocks - 1)
			var territory := Territory.new()
			territory.name = "Territory_%d" % index
			territory.display_name = DISTRICT_NAMES[index % DISTRICT_NAMES.size()]
			territory.owner_gang = DISTRICT_OWNERS[index % DISTRICT_OWNERS.size()]
			territory.extents = Vector2(extent, extent)
			territory.income_per_cycle = 150 + 50 * (2 - absi(dx - 1) - absi(dz - 1))
			territory.position = (first + last) * 0.5
			add_child(territory)
			territories.append(territory)
			if territory.owner_gang == GameState.PLAYER_GANG:
				# Spawn at the road intersection just past the district's first block.
				player_spawn = first + Vector3(block_size * 0.5 + road_width * 0.5, 1.0, block_size * 0.5 + road_width * 0.5)
			else:
				_spawn_defenders(territory, dx, dz)


func _spawn_defenders(territory: Territory, dx: int, dz: int) -> void:
	for i in defenders_per_district:
		var bx := dx * district_blocks + _rng.randi_range(0, district_blocks - 1)
		var bz := dz * district_blocks + _rng.randi_range(0, district_blocks - 1)
		var member := GangMember.new()
		member.gang_id = territory.owner_gang
		member.home_territory = territory
		member.position = _sidewalk_point(bx, bz) + Vector3(0.0, 0.2, 0.0)
		add_child(member)


## A random point on the outer sidewalk ring of a block (outside any building footprint).
func _sidewalk_point(ix: int, iz: int) -> Vector3:
	var center := block_center(ix, iz)
	var edge := block_size * 0.5 - 1.2
	var along := _rng.randf_range(-edge, edge)
	match _rng.randi_range(0, 3):
		0:
			return center + Vector3(along, 0.0, edge)
		1:
			return center + Vector3(along, 0.0, -edge)
		2:
			return center + Vector3(edge, 0.0, along)
		_:
			return center + Vector3(-edge, 0.0, along)


func _spawn_vehicles() -> void:
	# One car right next to the player so the first thing they can do is drive.
	_add_vehicle(player_spawn + Vector3(4.0, 0.5, 0.0), 0.0)
	for i in parked_vehicles:
		var ix := _rng.randi_range(0, blocks_per_side - 1)
		var iz := _rng.randi_range(0, blocks_per_side - 1)
		var center := block_center(ix, iz)
		var curb := block_size * 0.5 + 2.5
		var along := _rng.randf_range(-block_size * 0.4, block_size * 0.4)
		if _rng.randf() < 0.5:
			_add_vehicle(center + Vector3(curb, 0.5, along), 0.0)
		else:
			_add_vehicle(center + Vector3(along, 0.5, curb), PI / 2.0)


func _add_vehicle(position: Vector3, yaw: float) -> void:
	var vehicle := Vehicle.new()
	vehicle.body_color = CAR_COLORS[_rng.randi_range(0, CAR_COLORS.size() - 1)]
	vehicle.position = position
	vehicle.rotation.y = yaw
	add_child(vehicle)


func _add_static_box(size: Vector3, position: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = position
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	if material != null:
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = material
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		body.add_child(instance)
	add_child(body)


func _add_mesh_box(size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	add_child(instance)


func _material(key: String, color: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_materials[key] = material
	return _materials[key]
