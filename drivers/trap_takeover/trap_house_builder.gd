class_name TrapHouseBuilder
extends RefCounted
## Builds "The Spot", a Red Vipers trap house on a fenced lot: basement (grow room + stash room),
## ground floor (living room, count room, hall, kitchen, laundry), upper floor (two bedrooms,
## lookout room, boss's room) and a flat roof, joined by two staircases. Everything is greybox
## boxes so the driver needs no assets. Collisions are static (layer 1) and parented under a
## NavigationRegion3D so the navmesh (stairs included) bakes from them at runtime.
##
## Coordinates: the house footprint is x -9..9, z -7..7 with the front door facing +z (the street).
## Level n's floor top is at y = n * FLOOR_HEIGHT (basement -1, ground 0, upper 1, roof 2).

const FLOOR_HEIGHT := 3.0
const SLAB := 0.2
const WALL := 0.2
const WALL_HEIGHT := FLOOR_HEIGHT - SLAB
const DOOR_WIDTH := 1.4
const DOOR_HEIGHT := 2.2
const WINDOW_BOTTOM := 1.0
const WINDOW_TOP := 2.1

## House footprint on the x/z plane (Rect2.position = (x, z)).
const FOOTPRINT := Rect2(-9.0, -7.0, 18.0, 14.0)
## The fenced lot around the house.
const LOT := Rect2(-22.0, -20.0, 44.0, 35.0)
const NAV_BOUNDS := AABB(Vector3(-30.0, -4.0, -26.0), Vector3(60.0, 12.0, 60.0))
const LEVEL_NAMES := {-1: "Basement", 0: "Ground floor", 1: "Upper floor", 2: "Roof"}
## Stairwell openings cut into the slabs (x/z rects), keyed by the level whose floor has the hole.
const STAIR_HOLES := {0: Rect2(-2.0, -5.0, 1.5, 5.0), 1: Rect2(1.5, -3.0, 1.5, 5.0)}

const CLAIM_POINT := Vector3(5.8, -3.0, 0.0)
const CLAIM_RADIUS := 1.6
const PLAYER_SPAWN := Vector3(0.5, 0.1, 25.0)
const REINFORCEMENT_SPAWNS := [Vector3(-6.0, 0.1, 27.0), Vector3(8.0, 0.1, 27.0), Vector3(-14.0, 0.1, 24.0), Vector3(16.0, 0.1, 24.0), Vector3(0.0, 0.1, 30.0)]

## Rooms per level: name -> x/z rect. Used for labels and to describe where rivals are.
const ROOMS := {
	-1: {"Grow room": Rect2(-9, -7, 7, 14), "Corridor": Rect2(-2, -7, 5, 14), "Stash room": Rect2(3, -7, 6, 14)},
	0: {"Living room": Rect2(-9, 0, 7, 7), "Count room": Rect2(-9, -7, 7, 7), "Hall": Rect2(-2, -7, 5, 14), "Kitchen": Rect2(3, 0, 6, 7), "Laundry": Rect2(3, -7, 6, 7)},
	1: {"Front bedroom": Rect2(-9, 0, 7, 7), "Back bedroom": Rect2(-9, -7, 7, 7), "Landing": Rect2(-2, -7, 5, 14), "Lookout room": Rect2(3, 0, 6, 7), "Boss's room": Rect2(3, -7, 6, 7)},
}

## Enemy spawn slots. post: IndoorGangMember.Post name. look: point the rival faces while idle.
## patrol: waypoints for PATROL. boss: tougher, carries a shotgun. area: Yard/Ground/Upper/Basement.
const SLOTS := [
	# Yard (front)
	{"id": &"porch_left", "area": "Yard", "pos": Vector3(-2.5, 0, 8.3), "look": Vector3(-2.5, 0, 20), "post": &"GUARD"},
	{"id": &"porch_right", "area": "Yard", "pos": Vector3(3.0, 0, 8.3), "look": Vector3(3, 0, 20), "post": &"GUARD"},
	{"id": &"front_gate", "area": "Yard", "pos": Vector3(3.0, 0, 13.5), "look": Vector3(0.5, 0, 20), "post": &"GUARD"},
	{"id": &"lawn_car", "area": "Yard", "pos": Vector3(-10.0, 0, 9.2), "look": Vector3(-10, 0, 20), "post": &"GUARD"},
	{"id": &"driveway", "area": "Yard", "pos": Vector3(12.0, 0, 8.3), "look": Vector3(12, 0, 20), "post": &"GUARD"},
	{"id": &"front_patrol", "area": "Yard", "pos": Vector3(-17.0, 0, 13), "look": Vector3(0, 0, 20), "post": &"PATROL", "patrol": [Vector3(-17, 0, 13), Vector3(8, 0, 13)]},
	{"id": &"west_side", "area": "Yard", "pos": Vector3(-12.0, 0, 1.0), "look": Vector3(-20, 0, 1), "post": &"GUARD"},
	{"id": &"east_alley", "area": "Yard", "pos": Vector3(14.0, 0, 5.0), "look": Vector3(20, 0, 5), "post": &"PATROL", "patrol": [Vector3(14, 0, 5), Vector3(14, 0, -13)]},
	# Yard (back)
	{"id": &"back_door", "area": "Yard", "pos": Vector3(0.5, 0, -8.6), "look": Vector3(0.5, 0, -20), "post": &"GUARD"},
	{"id": &"shed", "area": "Yard", "pos": Vector3(-12.5, 0, -13.0), "look": Vector3(0, 0, -16), "post": &"GUARD"},
	{"id": &"back_patrol", "area": "Yard", "pos": Vector3(16.0, 0, -10), "look": Vector3(0, 0, -20), "post": &"PATROL", "patrol": [Vector3(16, 0, -10), Vector3(-10, 0, -10)]},
	{"id": &"grill", "area": "Yard", "pos": Vector3(6.0, 0, -12.5), "look": Vector3(6, 0, -20), "post": &"GUARD"},
	# Ground floor
	{"id": &"living_window", "area": "Ground", "pos": Vector3(-5.5, 0, 6.3), "look": Vector3(-5.5, 0, 20), "post": &"OVERWATCH"},
	{"id": &"living_ambush", "area": "Ground", "pos": Vector3(-8.0, 0, 1.2), "look": Vector3(-2, 0, 3.5), "post": &"HOLD"},
	{"id": &"count_table", "area": "Ground", "pos": Vector3(-5.5, 0, -1.8), "look": Vector3(-2, 0, -6), "post": &"HOLD"},
	{"id": &"count_corner", "area": "Ground", "pos": Vector3(-8.0, 0, -6.0), "look": Vector3(-2, 0, -6), "post": &"HOLD"},
	{"id": &"foyer", "area": "Ground", "pos": Vector3(0.5, 0, 5.2), "look": Vector3(0.5, 0, 12), "post": &"GUARD"},
	{"id": &"back_hall", "area": "Ground", "pos": Vector3(0.5, 0, -5.8), "look": Vector3(0.5, 0, -12), "post": &"GUARD"},
	{"id": &"kitchen", "area": "Ground", "pos": Vector3(4.2, 0, 1.2), "look": Vector3(3, 0, 4.5), "post": &"HOLD"},
	{"id": &"kitchen_door", "area": "Ground", "pos": Vector3(8.0, 0, 5.2), "look": Vector3(14, 0, 3.5), "post": &"GUARD"},
	{"id": &"laundry", "area": "Ground", "pos": Vector3(6.0, 0, -3.0), "look": Vector3(7, 0, 0), "post": &"HOLD"},
	# Upper floor
	{"id": &"front_window", "area": "Upper", "pos": Vector3(-5.5, 3, 6.3), "look": Vector3(-5.5, 3, 20), "post": &"OVERWATCH"},
	{"id": &"front_bed", "area": "Upper", "pos": Vector3(-3.2, 3, 1.0), "look": Vector3(-2, 3, 3.5), "post": &"HOLD"},
	{"id": &"back_window", "area": "Upper", "pos": Vector3(-5.5, 3, -6.3), "look": Vector3(-5.5, 3, -20), "post": &"OVERWATCH"},
	{"id": &"back_bed", "area": "Upper", "pos": Vector3(-4.0, 3, -1.2), "look": Vector3(-2, 3, -3.5), "post": &"HOLD"},
	{"id": &"landing_patrol", "area": "Upper", "pos": Vector3(-1.2, 3, 5.0), "look": Vector3(-1.2, 3, -5), "post": &"PATROL", "patrol": [Vector3(-1.2, 3, 5), Vector3(-1.0, 3, -5.5), Vector3(2.2, 3, -5.5)]},
	{"id": &"hall_window", "area": "Upper", "pos": Vector3(0.5, 3, 6.3), "look": Vector3(0.5, 3, 20), "post": &"OVERWATCH"},
	{"id": &"lookout", "area": "Upper", "pos": Vector3(6.0, 3, 6.3), "look": Vector3(6, 3, 20), "post": &"OVERWATCH"},
	{"id": &"lookout_couch", "area": "Upper", "pos": Vector3(4.0, 3, 1.0), "look": Vector3(3, 3, 4.5), "post": &"HOLD"},
	{"id": &"boss", "area": "Upper", "pos": Vector3(7.5, 3, -4.5), "look": Vector3(3, 3, -5), "post": &"HOLD", "boss": true},
	{"id": &"boss_guard", "area": "Upper", "pos": Vector3(4.2, 3, -1.0), "look": Vector3(3, 3, -5), "post": &"HOLD"},
	# Basement
	{"id": &"grow_door", "area": "Basement", "pos": Vector3(-8.2, -3, 3.3), "look": Vector3(-2, -3, 3), "post": &"HOLD"},
	{"id": &"grow_back", "area": "Basement", "pos": Vector3(-3.2, -3, -5.5), "look": Vector3(-2, -3, 3), "post": &"HOLD"},
	{"id": &"corridor", "area": "Basement", "pos": Vector3(1.2, -3, -2.5), "look": Vector3(-1.2, -3, 1), "post": &"GUARD"},
	{"id": &"stash_front", "area": "Basement", "pos": Vector3(7.8, -3, 3.5), "look": Vector3(3, -3, 2), "post": &"HOLD"},
	{"id": &"stash_back", "area": "Basement", "pos": Vector3(8.0, -3, -2.5), "look": Vector3(3, -3, 2), "post": &"HOLD"},
]

## Doors that swing: [level, axis, fixed, center, width, swing].
## axis &"x": wall runs along x at z = fixed; &"z": along z at x = fixed. swing: +1/-1 picks the side
## it opens to (into the house/room, except the back door, which opens out so it doesn't block
## the hall where the basement stairs come up).
const SWING_DOORS := [
	[0, &"x", 7.0, 0.5, 1.6, 1.0],    # front door
	[0, &"x", -7.0, 0.5, 1.6, 1.0],   # back door
	[0, &"z", 9.0, 3.5, DOOR_WIDTH, 1.0],    # kitchen side door
	[0, &"z", -2.0, -6.0, DOOR_WIDTH, 1.0],  # count room
	[1, &"z", 3.0, -5.0, DOOR_WIDTH, -1.0],  # boss's room
	[-1, &"z", 3.0, 2.0, DOOR_WIDTH, -1.0],  # stash room
]

var region: NavigationRegion3D
## Level index -> StaticBody3D holding that level's slab, walls, furniture and lights.
var levels := {}
var grounds: StaticBody3D
var room_labels: Array[Label3D] = []
var doors: Array[SwingDoor] = []

var _materials := {}


## Builds everything under a new NavigationRegion3D added to [param parent]. Call [method bake]
## once it is in the tree.
func build(parent: Node) -> NavigationRegion3D:
	region = NavigationRegion3D.new()
	region.name = "TrapHouse"
	region.navigation_mesh = _navmesh_settings()
	parent.add_child(region)
	_build_grounds()
	for level in [-1, 0, 1, 2]:
		var body := StaticBody3D.new()
		body.name = "Level%s" % ("B" if level < 0 else str(level))
		body.collision_mask = 0
		region.add_child(body)
		levels[level] = body
	_build_basement(levels[-1])
	_build_ground_floor(levels[0])
	_build_upper_floor(levels[1])
	_build_roof(levels[2])
	for level: int in ROOMS:
		for room: String in ROOMS[level]:
			_room_label(levels[level], room, ROOMS[level][room], level)
	return region


## Bakes the navmesh from the static geometry (synchronously), then adds the swinging doors so
## they don't get baked in as walls.
func bake() -> void:
	var map := region.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, region.navigation_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, region.navigation_mesh.cell_height)
	region.bake_navigation_mesh(false)
	for spec: Array in SWING_DOORS:
		_add_swing_door(spec)


## Knocks the house down: frees every level (floors, walls, doors, labels) and leaves a dirt pad
## with the old foundation and rubble. Returns the new "EmptyLot" body.
func demolish() -> StaticBody3D:
	for level: int in levels:
		var body: Node = levels[level]
		body.get_parent().remove_child(body)
		body.queue_free()
	levels.clear()
	doors.clear()
	room_labels.clear()
	var lot := StaticBody3D.new()
	lot.name = "EmptyLot"
	lot.collision_mask = 0
	region.add_child(lot)
	_slab(lot, FOOTPRINT, 0.0, _material(&"dirt", Color(0.36, 0.28, 0.2)), 0.5)
	var foundation := _material(&"foundation", Color(0.55, 0.55, 0.52))
	for edge: Array in [[Vector3(0.0, 0.12, 7.0), Vector3(18.2, 0.24, 0.3)], [Vector3(0.0, 0.12, -7.0), Vector3(18.2, 0.24, 0.3)],
			[Vector3(-9.0, 0.12, 0.0), Vector3(0.3, 0.24, 14.0)], [Vector3(9.0, 0.12, 0.0), Vector3(0.3, 0.24, 14.0)]]:
		_visual(lot, edge[0], edge[1], foundation)
	var rubble := [_material(&"siding", Color(0.82, 0.76, 0.58)), _material(&"plaster", Color(0.74, 0.7, 0.64)), _material(&"crate", Color(0.55, 0.42, 0.25))]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 24:
		var at := Vector3(rng.randf_range(-8.0, 8.0), 0.1, rng.randf_range(-6.0, 6.0))
		var size := Vector3(rng.randf_range(0.4, 1.6), rng.randf_range(0.1, 0.4), rng.randf_range(0.3, 1.2))
		_visual(lot, at, size, rubble[i % rubble.size()], Basis(Vector3.UP, rng.randf_range(0.0, PI)))
	return lot


static func level_y(level: int) -> float:
	return level * FLOOR_HEIGHT


static func is_inside(position: Vector3) -> bool:
	return FOOTPRINT.has_point(Vector2(position.x, position.z)) and position.y > -3.5 and position.y < 5.8


## Level index for [param position], or [code]-99[/code] when outside the house.
static func level_of(position: Vector3) -> int:
	if not is_inside(position):
		return -99
	return clampi(floori((position.y + 0.6) / FLOOR_HEIGHT), -1, 1)


## "Yard", "Basement", "Ground" or "Upper".
static func area_of(position: Vector3) -> String:
	match level_of(position):
		-1:
			return "Basement"
		0:
			return "Ground"
		1:
			return "Upper"
	return "Yard"


static func room_at(position: Vector3) -> String:
	var level := level_of(position)
	if level == -99:
		return "Yard"
	for room: String in ROOMS.get(level, {}):
		if (ROOMS[level][room] as Rect2).has_point(Vector2(position.x, position.z)):
			return room
	return LEVEL_NAMES[level]


static func slot_yaw(slot: Dictionary) -> float:
	var direction: Vector3 = slot["look"] - slot["pos"]
	return atan2(-direction.x, -direction.z)


func _navmesh_settings() -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 1
	navmesh.cell_size = 0.15
	navmesh.cell_height = 0.1
	navmesh.agent_height = 1.8
	navmesh.agent_radius = 0.45
	navmesh.agent_max_climb = 0.3
	navmesh.agent_max_slope = 40.0
	navmesh.filter_baking_aabb = NAV_BOUNDS
	return navmesh


# --- Levels -------------------------------------------------------------------------------------

func _build_grounds() -> void:
	grounds = StaticBody3D.new()
	grounds.name = "Grounds"
	grounds.collision_mask = 0
	region.add_child(grounds)
	var grass := _material(&"grass", Color(0.24, 0.36, 0.17))
	# Terrain around the footprint (the house's own slabs cover the footprint so the basement fits).
	var outer := Rect2(-45.0, -40.0, 90.0, 90.0)
	var f := FOOTPRINT
	for rect: Rect2 in [
		Rect2(outer.position.x, outer.position.y, f.position.x - outer.position.x, outer.size.y),
		Rect2(f.end.x, outer.position.y, outer.end.x - f.end.x, outer.size.y),
		Rect2(f.position.x, outer.position.y, f.size.x, f.position.y - outer.position.y),
		Rect2(f.position.x, f.end.y, f.size.x, outer.end.y - f.end.y),
	]:
		_slab(grounds, rect, 0.0, grass, 0.5)
	var street := _material(&"asphalt", Color(0.16, 0.16, 0.17))
	var concrete := _material(&"concrete", Color(0.6, 0.6, 0.58))
	_visual(grounds, Vector3(0, 0.01, 25), Vector3(90, 0.02, 12), street)
	_visual(grounds, Vector3(0, 0.02, 17.5), Vector3(90, 0.02, 3), concrete)
	_visual(grounds, Vector3(0.5, 0.02, 12.25), Vector3(1.8, 0.02, 5.5), concrete)
	_visual(grounds, Vector3(12, 0.02, 12.5), Vector3(4, 0.02, 11), concrete)
	for x in range(-40, 41, 8):
		_visual(grounds, Vector3(x, 0.03, 25), Vector3(3.0, 0.02, 0.2), _material(&"paint", Color(0.9, 0.8, 0.2)))
	_visual(grounds, Vector3(0.5, 0.03, 8.25), Vector3(9.0, 0.04, 2.5), _material(&"deck", Color(0.42, 0.3, 0.2)))
	_fence()
	_yard_props()


func _build_basement(body: StaticBody3D) -> void:
	var y := level_y(-1)
	var concrete := _material(&"basement", Color(0.42, 0.42, 0.42))
	_slab(body, FOOTPRINT, y, concrete)
	for wall: Array in [
		[&"x", 7.0, -9.1, 9.1, []], [&"x", -7.0, -9.1, 9.1, []],
		[&"z", -9.0, -7.0, 7.0, []], [&"z", 9.0, -7.0, 7.0, []],
	]:
		_wall(body, y, wall, _material(&"basement_wall", Color(0.5, 0.5, 0.48)))
	var inner := _material(&"cinder", Color(0.58, 0.56, 0.52))
	_wall(body, y, [&"z", -2.0, -7.0, 7.0, [_door(3.0)]], inner)
	_wall(body, y, [&"z", 3.0, -7.0, 7.0, [_door(2.0)]], inner)
	# Grow room: tables under purple lights.
	var table := _material(&"grow_table", Color(0.3, 0.3, 0.32))
	var plant := _material(&"plant", Color(0.2, 0.6, 0.2))
	for z: float in [5.2, 1.5, -2.2]:
		_box(body, Vector3(-5.5, y + 0.45, z), Vector3(4.0, 0.9, 1.0), table)
		for x: float in [-7.0, -5.5, -4.0]:
			_visual(body, Vector3(x, y + 1.15, z), Vector3(0.6, 0.5, 0.6), plant)
		_light(body, Vector3(-5.5, y + 2.4, z), Color(0.75, 0.35, 1.0), 1.6, 5.0)
	# Corridor junk and the stash room.
	var crate := _material(&"crate", Color(0.55, 0.42, 0.25))
	_box(body, Vector3(1.8, y + 0.5, -5.5), Vector3(1.0, 1.0, 1.0), crate)
	_box(body, Vector3(2.2, y + 0.5, 6.0), Vector3(1.0, 1.0, 1.0), crate)
	_box(body, Vector3(8.4, y + 0.7, 0.0), Vector3(1.0, 1.4, 1.0), _material(&"safe", Color(0.2, 0.22, 0.25)))
	_box(body, Vector3(6.0, y + 0.9, 6.5), Vector3(4.0, 1.8, 0.6), _material(&"shelf", Color(0.35, 0.3, 0.25)))
	_box(body, Vector3(6.0, y + 0.4, -4.5), Vector3(2.2, 0.8, 1.2), _material(&"table", Color(0.4, 0.3, 0.2)))
	for i in 6:
		_visual(body, Vector3(5.3 + (i % 3) * 0.6, y + 0.9, -4.8 + floorf(i / 3.0) * 0.6), Vector3(0.4, 0.2, 0.3), _material(&"brick", Color(0.9, 0.9, 0.85)))
	_light(body, Vector3(0.5, y + 2.4, 0.0), Color(1.0, 0.85, 0.6), 1.0, 7.0)
	_light(body, Vector3(6.0, y + 2.4, 0.0), Color(1.0, 0.85, 0.6), 1.2, 8.0)
	# Stairwell wall: closes the flight's open side so it can only be climbed from its foot.
	_wall(body, y, [&"z", -0.45, -5.0, 0.0, [], WALL_HEIGHT, 0.1], inner)
	_stairs(body, STAIR_HOLES[0], Vector3(0, y, 0.0), Vector3(0, 0.0, -5.0))


func _build_ground_floor(body: StaticBody3D) -> void:
	var y := level_y(0)
	_slab(body, FOOTPRINT, y, _material(&"floor", Color(0.45, 0.33, 0.22)), SLAB, STAIR_HOLES[0])
	var siding := _material(&"siding", Color(0.82, 0.76, 0.58))
	_wall(body, y, [&"x", 7.0, -9.1, 9.1, [_window(-5.5, 2.0), _window(6.0), _door(0.5, 1.6)]], siding)
	_wall(body, y, [&"x", -7.0, -9.1, 9.1, [_window(-5.5), _window(6.0), _door(0.5, 1.6)]], siding)
	_wall(body, y, [&"z", -9.0, -7.0, 7.0, [_window(3.5), _window(-3.5)]], siding)
	_wall(body, y, [&"z", 9.0, -7.0, 7.0, [_door(3.5), _window(-3.5)]], siding)
	var inner := _material(&"plaster", Color(0.74, 0.7, 0.64))
	_wall(body, y, [&"z", -2.0, -7.0, 7.0, [_door(3.5), _door(-6.0)]], inner)
	_wall(body, y, [&"z", 3.0, -7.0, 7.0, [_door(4.5)]], inner)
	_wall(body, y, [&"x", 0.0, -9.0, -2.0, [_door(-7.5)]], inner)
	_wall(body, y, [&"x", 0.0, 3.0, 9.0, [_door(7.0)]], inner)
	var rail := _material(&"rail", Color(0.25, 0.18, 0.12))
	_wall(body, y, [&"z", -0.5, -5.0, 0.0, [], 1.0, 0.08], rail)
	_wall(body, y, [&"x", 0.0, -2.0, -0.5, [], 1.0, 0.08], rail)
	_wall(body, y, [&"z", 1.45, -3.0, 2.0, [], WALL_HEIGHT, 0.1], inner)
	# Living room.
	_box(body, Vector3(-8.4, y + 0.4, 3.5), Vector3(0.9, 0.8, 2.8), _material(&"couch", Color(0.3, 0.25, 0.35)))
	_box(body, Vector3(-6.5, y + 0.25, 3.5), Vector3(0.8, 0.5, 1.4), _material(&"table", Color(0.4, 0.3, 0.2)))
	_box(body, Vector3(-4.5, y + 0.3, 0.6), Vector3(1.8, 0.6, 0.5), _material(&"tv", Color(0.1, 0.1, 0.1)))
	# Count room: table covered in cash.
	_box(body, Vector3(-5.5, y + 0.4, -3.5), Vector3(2.4, 0.8, 1.2), _material(&"table", Color(0.4, 0.3, 0.2)))
	for i in 8:
		_visual(body, Vector3(-6.4 + (i % 4) * 0.6, y + 0.86, -3.8 + floorf(i / 4.0) * 0.6), Vector3(0.35, 0.12, 0.18), _material(&"cash", Color(0.3, 0.65, 0.3)))
	# Kitchen and laundry.
	var counter := _material(&"counter", Color(0.7, 0.7, 0.68))
	_box(body, Vector3(6.0, y + 0.45, 6.5), Vector3(4.0, 0.9, 0.7), counter)
	_box(body, Vector3(6.0, y + 0.45, 3.0), Vector3(1.6, 0.9, 1.0), counter)
	_box(body, Vector3(8.5, y + 0.9, 0.6), Vector3(0.7, 1.8, 0.7), _material(&"fridge", Color(0.85, 0.85, 0.85)))
	_box(body, Vector3(8.4, y + 0.5, -5.5), Vector3(0.8, 1.0, 1.8), _material(&"fridge", Color(0.85, 0.85, 0.85)))
	_box(body, Vector3(3.45, y + 0.9, -3.5), Vector3(0.5, 1.8, 2.0), _material(&"shelf", Color(0.35, 0.3, 0.25)))
	for room: String in ROOMS[0]:
		var rect: Rect2 = ROOMS[0][room]
		_light(body, Vector3(rect.get_center().x, y + 2.4, rect.get_center().y), Color(1.0, 0.88, 0.7), 0.9, 7.0)
	_stairs(body, STAIR_HOLES[1], Vector3(0, y, 2.0), Vector3(0, y + FLOOR_HEIGHT, -3.0))


func _build_upper_floor(body: StaticBody3D) -> void:
	var y := level_y(1)
	_slab(body, FOOTPRINT, y, _material(&"floor", Color(0.45, 0.33, 0.22)), SLAB, STAIR_HOLES[1])
	var siding := _material(&"siding", Color(0.82, 0.76, 0.58))
	_wall(body, y, [&"x", 7.0, -9.1, 9.1, [_window(-5.5, 2.0), _window(0.5), _window(6.0)]], siding)
	_wall(body, y, [&"x", -7.0, -9.1, 9.1, [_window(-5.5), _window(0.5), _window(6.0)]], siding)
	_wall(body, y, [&"z", -9.0, -7.0, 7.0, [_window(3.5), _window(-3.5)]], siding)
	_wall(body, y, [&"z", 9.0, -7.0, 7.0, [_window(3.5), _window(-3.5)]], siding)
	var inner := _material(&"plaster", Color(0.74, 0.7, 0.64))
	_wall(body, y, [&"z", -2.0, -7.0, 7.0, [_door(3.5), _door(-3.5)]], inner)
	_wall(body, y, [&"z", 3.0, -7.0, 7.0, [_door(4.5), _door(-5.0)]], inner)
	_wall(body, y, [&"x", 0.0, -9.0, -2.0, []], inner)
	_wall(body, y, [&"x", 0.0, 3.0, 9.0, []], inner)
	var rail := _material(&"rail", Color(0.25, 0.18, 0.12))
	_wall(body, y, [&"z", 1.5, -3.0, 2.0, [], 1.0, 0.08], rail)
	_wall(body, y, [&"x", 2.0, 1.5, 3.0, [], 1.0, 0.08], rail)
	var bed := _material(&"bed", Color(0.55, 0.55, 0.7))
	_box(body, Vector3(-7.8, y + 0.3, 1.5), Vector3(2.0, 0.6, 2.4), bed)
	_box(body, Vector3(-7.8, y + 0.3, -5.5), Vector3(2.0, 0.6, 2.4), bed)
	_box(body, Vector3(8.4, y + 0.4, 3.5), Vector3(0.9, 0.8, 2.6), _material(&"couch", Color(0.3, 0.25, 0.35)))
	_box(body, Vector3(7.5, y + 0.3, -1.5), Vector3(2.4, 0.6, 2.0), _material(&"boss_bed", Color(0.6, 0.12, 0.12)))
	_box(body, Vector3(5.5, y + 0.4, -6.4), Vector3(1.8, 0.8, 0.7), _material(&"table", Color(0.4, 0.3, 0.2)))
	for room: String in ROOMS[1]:
		var rect: Rect2 = ROOMS[1][room]
		_light(body, Vector3(rect.get_center().x, y + 2.4, rect.get_center().y), Color(1.0, 0.88, 0.7), 0.9, 7.0)


func _build_roof(body: StaticBody3D) -> void:
	var y := level_y(2)
	var roof := _material(&"roof", Color(0.22, 0.22, 0.24))
	_slab(body, Rect2(FOOTPRINT.position - Vector2(0.4, 0.4), FOOTPRINT.size + Vector2(0.8, 0.8)), y, roof)
	for wall: Array in [
		[&"x", 7.3, -9.4, 9.4, [], 0.8], [&"x", -7.3, -9.4, 9.4, [], 0.8],
		[&"z", -9.3, -7.3, 7.3, [], 0.8], [&"z", 9.3, -7.3, 7.3, [], 0.8],
	]:
		_wall(body, y, wall, roof)
	_visual(body, Vector3(-4.0, y + 0.6, -3.0), Vector3(1.6, 1.2, 1.2), _material(&"ac", Color(0.7, 0.7, 0.7)))


func _fence() -> void:
	var fence := _material(&"fence", Color(0.6, 0.62, 0.65, 0.55), true)
	var lot := LOT
	var height := 1.2
	for span: Array in [[lot.position.x, -0.5], [2.5, 10.5], [13.5, lot.end.x]]:
		_fence_run(Vector3(span[0], 0, lot.end.y), Vector3(span[1], 0, lot.end.y), height, fence)
	_fence_run(Vector3(lot.position.x, 0, lot.position.y), Vector3(-1.0, 0, lot.position.y), height, fence)
	_fence_run(Vector3(1.5, 0, lot.position.y), Vector3(lot.end.x, 0, lot.position.y), height, fence)
	_fence_run(Vector3(lot.position.x, 0, lot.position.y), Vector3(lot.position.x, 0, lot.end.y), height, fence)
	_fence_run(Vector3(lot.end.x, 0, lot.position.y), Vector3(lot.end.x, 0, lot.end.y), height, fence)


func _fence_run(from: Vector3, to: Vector3, height: float, material: Material) -> void:
	var center := (from + to) * 0.5 + Vector3(0, height * 0.5, 0)
	var length := from.distance_to(to)
	var size := Vector3(length, height, 0.06) if absf(to.x - from.x) > absf(to.z - from.z) else Vector3(0.06, height, length)
	_box(grounds, center, size, material)
	var post := _material(&"fence_post", Color(0.45, 0.45, 0.48))
	var posts := maxi(1, int(length / 3.0))
	for i in posts + 1:
		_visual(grounds, from.lerp(to, float(i) / posts) + Vector3(0, height * 0.55, 0), Vector3(0.1, height * 1.1, 0.1), post)


func _yard_props() -> void:
	var glass := _material(&"car_glass", Color(0.15, 0.2, 0.25))
	_box(grounds, Vector3(-10.0, 0.6, 11.0), Vector3(4.2, 1.2, 1.9), _material(&"junker", Color(0.45, 0.12, 0.1)))
	_visual(grounds, Vector3(-10.2, 1.45, 11.0), Vector3(2.2, 0.5, 1.7), glass)
	_box(grounds, Vector3(12.0, 0.6, 12.0), Vector3(1.9, 1.2, 4.4), _material(&"sedan", Color(0.15, 0.15, 0.18)))
	_visual(grounds, Vector3(12.0, 1.45, 12.2), Vector3(1.7, 0.5, 2.2), glass)
	var crate := _material(&"crate", Color(0.55, 0.42, 0.25))
	_box(grounds, Vector3(5.0, 0.5, 11.0), Vector3(1.0, 1.0, 1.0), crate)
	_box(grounds, Vector3(-15.0, 0.5, -6.0), Vector3(1.2, 1.0, 1.2), crate)
	_box(grounds, Vector3(8.0, 0.5, -15.0), Vector3(1.0, 1.0, 1.0), crate)
	var barrel := _material(&"barrel", Color(0.2, 0.35, 0.5))
	_box(grounds, Vector3(-6.0, 0.5, -11.0), Vector3(0.7, 1.0, 0.7), barrel)
	_box(grounds, Vector3(3.0, 0.5, -15.5), Vector3(0.7, 1.0, 0.7), barrel)
	_box(grounds, Vector3(6.0, 0.45, -13.8), Vector3(1.2, 0.9, 0.7), _material(&"grill", Color(0.1, 0.1, 0.1)))
	_box(grounds, Vector3(16.0, 0.7, -5.0), Vector3(1.8, 1.4, 3.2), _material(&"dumpster", Color(0.15, 0.35, 0.2)))
	_box(grounds, Vector3(-16.0, 1.3, -15.0), Vector3(4.0, 2.6, 3.0), _material(&"shed", Color(0.5, 0.45, 0.35)))
	_light(grounds, Vector3(0.5, 2.6, 8.0), Color(1.0, 0.8, 0.5), 1.0, 6.0)


# --- Geometry helpers ---------------------------------------------------------------------------

func _door(center: float, width := DOOR_WIDTH) -> Vector4:
	return Vector4(center, width, 0.0, DOOR_HEIGHT)


func _window(center: float, width := 1.4) -> Vector4:
	return Vector4(center, width, WINDOW_BOTTOM, WINDOW_TOP)


## [param spec]: [axis, fixed, from, to, openings(Array[Vector4]), height?, thickness?].
## Openings are Vector4(center along the wall, width, bottom, top) relative to [param base_y].
func _wall(body: StaticBody3D, base_y: float, spec: Array, material: Material) -> void:
	var axis: StringName = spec[0]
	var fixed: float = spec[1]
	var from: float = spec[2]
	var to: float = spec[3]
	var openings: Array = spec[4].duplicate()
	var height: float = spec[5] if spec.size() > 5 else WALL_HEIGHT
	var thickness: float = spec[6] if spec.size() > 6 else WALL
	openings.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.x < b.x)
	var cursor := from
	for opening: Vector4 in openings:
		var start := opening.x - opening.y * 0.5
		var end := opening.x + opening.y * 0.5
		_wall_piece(body, axis, fixed, cursor, start, base_y, base_y + height, thickness, material)
		_wall_piece(body, axis, fixed, start, end, base_y, base_y + opening.z, thickness, material)
		_wall_piece(body, axis, fixed, start, end, base_y + opening.w, base_y + height, thickness, material)
		cursor = end
	_wall_piece(body, axis, fixed, cursor, to, base_y, base_y + height, thickness, material)


func _wall_piece(body: StaticBody3D, axis: StringName, fixed: float, from: float, to: float, bottom: float, top: float, thickness: float, material: Material) -> void:
	if to - from < 0.01 or top - bottom < 0.01:
		return
	var along := (from + to) * 0.5
	var center := Vector3(along, (bottom + top) * 0.5, fixed) if axis == &"x" else Vector3(fixed, (bottom + top) * 0.5, along)
	var size := Vector3(to - from, top - bottom, thickness) if axis == &"x" else Vector3(thickness, top - bottom, to - from)
	_box(body, center, size, material)


## A floor slab whose top is at [param top]; [param hole] (x/z rect) is left open for stairs.
func _slab(body: StaticBody3D, rect: Rect2, top: float, material: Material, thickness := SLAB, hole := Rect2()) -> void:
	var rects: Array[Rect2] = [rect]
	if hole.has_area():
		rects = [
			Rect2(rect.position.x, rect.position.y, hole.position.x - rect.position.x, rect.size.y),
			Rect2(hole.end.x, rect.position.y, rect.end.x - hole.end.x, rect.size.y),
			Rect2(hole.position.x, rect.position.y, hole.size.x, hole.position.y - rect.position.y),
			Rect2(hole.position.x, hole.end.y, hole.size.x, rect.end.y - hole.end.y),
		]
	for piece in rects:
		if piece.has_area():
			_box(body, Vector3(piece.get_center().x, top - thickness * 0.5, piece.get_center().y), Vector3(piece.size.x, thickness, piece.size.y), material)


## A straight flight inside [param footprint] (x/z rect) from [param bottom] to [param top]
## (only their y and z are used). Collision is a smooth ramp; the steps are visual.
func _stairs(body: StaticBody3D, footprint: Rect2, bottom: Vector3, top: Vector3) -> void:
	var x := footprint.get_center().x
	var width := footprint.size.x - WALL * 0.5
	var start := Vector3(x, bottom.y, bottom.z)
	var end := Vector3(x, top.y, top.z)
	var direction := (end - start).normalized()
	var normal := Vector3(0.0, absf(direction.z), -direction.y * signf(direction.z))
	var extended := start - direction * 0.4
	var thickness := 0.15
	var basis := Basis(normal.cross(direction), normal, direction)
	var center := (extended + end) * 0.5 - normal * thickness * 0.5
	_box(body, center, Vector3(width, thickness, extended.distance_to(end)), _material(&"stringer", Color(0.3, 0.22, 0.15)), true, basis)
	var count := roundi((end.y - start.y) / 0.2)
	var tread := (end.z - start.z) / count
	var rise := (end.y - start.y) / count
	var step := _material(&"step", Color(0.5, 0.38, 0.26))
	for i in count:
		var top_y := start.y + rise * (i + 0.5)
		_visual(body, Vector3(x, top_y - rise * 0.5, start.z + tread * (i + 0.5)), Vector3(width, rise, absf(tread)), step)


func _add_swing_door(spec: Array) -> void:
	var level: int = spec[0]
	var axis: StringName = spec[1]
	var fixed: float = spec[2]
	var center: float = spec[3]
	var width: float = spec[4]
	var door := SwingDoor.new()
	door.width = width
	door.height = DOOR_HEIGHT
	door.swing = spec[5]
	door.name = "Door_%d_%s_%d_%d" % [level, axis, roundi(fixed * 10.0), roundi(center * 10.0)]
	var y := level_y(level)
	if axis == &"x":
		door.position = Vector3(center - width * 0.5, y, fixed)
	else:
		door.position = Vector3(fixed, y, center + width * 0.5)
		door.closed_yaw = PI / 2.0
	levels[level].add_child(door)
	doors.append(door)


func _box(body: Node3D, center: Vector3, size: Vector3, material: Material, collide := true, basis := Basis.IDENTITY) -> void:
	_visual(body, center, size, material, basis)
	if not collide:
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(basis, center)
	body.add_child(collision)


func _visual(body: Node3D, center: Vector3, size: Vector3, material: Material, basis := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = Transform3D(basis, center)
	body.add_child(instance)


func _light(body: Node3D, at: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	body.add_child(light)


func _room_label(body: Node3D, room: String, rect: Rect2, level: int) -> void:
	var label := Label3D.new()
	label.text = room
	label.font_size = 64
	label.pixel_size = 0.012
	label.outline_size = 12
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.position = Vector3(rect.get_center().x, level_y(level) + 0.05, rect.get_center().y + rect.size.y * 0.3)
	label.visible = false
	body.add_child(label)
	room_labels.append(label)


func _material(key: StringName, color: Color, transparent := false) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	return material
