class_name CityGenerator
extends Node3D
## Builds the North End (Zone 1) greybox at runtime from [NorthEndLayout], which
## tools/extract_north_end_layout.py generates from docs/map/north_end_wireframe_source.svg: streets and I-59,
## the tracks, the lakes, blocks split into lots, district-styled buildings, the three districts and
## parked cars. Wireframe pixels map to meters with [constant METERS_PER_PX] around [constant CENTER_PX]
## (north = -Z). Roster content is placed on the lots by main.gd ([NorthEndSpots]).

const CAR_COLORS := [
	Color(0.7, 0.1, 0.1), Color(0.1, 0.2, 0.6), Color(0.85, 0.85, 0.85),
	Color(0.1, 0.1, 0.1), Color(0.2, 0.5, 0.25), Color(0.8, 0.6, 0.1),
]
## 2.0 m/px since the North End populate pass (was 1.2): lots fit the building kit at full size.
const METERS_PER_PX := 2.0
const CENTER_PX := Vector2(541.0, 660.0)
## Playable area in wireframe px; invisible boundary walls sit 20 m outside it.
const PLAY_RECT_PX := Rect2(150.0, 150.0, 782.0, 1020.0)
## District bounds (axis-aligned, px). The I-59 diagonal border is approximated.
const DISTRICT_RECTS_PX := {
	&"mangona": Rect2(180.0, 165.0, 378.0, 555.0),
	&"northgrove": Rect2(558.0, 330.0, 374.0, 390.0),
	&"tamarack_row": Rect2(255.0, 720.0, 314.0, 430.0),
}
## Safehouse centre (px), yaw (the door faces local +Z) and the px rect kept clear of buildings.
const SAFEHOUSES_PX := {
	&"mangona": {"at": Vector2(536.0, 470.0), "yaw": -PI / 2.0, "clear": Rect2(524.0, 456.0, 24.0, 30.0)},
	&"northgrove": {"at": Vector2(767.5, 575.0), "yaw": 0.0, "clear": Rect2(756.0, 563.0, 23.0, 23.0)},
	&"tamarack_row": {"at": Vector2(533.0, 786.0), "yaw": PI, "clear": Rect2(522.0, 775.0, 22.0, 22.0)},
}
## On 23rd St, outside the Tamarack Row duplex.
const PLAYER_SPAWN_PX := Vector2(533.0, 770.0)
const LAKES_PX := NorthEndLayout.LAKES
## Lake Worth Lagoon starts east of this x (px); it lies beyond the east wall.
const LAGOON_X_PX := NorthEndLayout.LAGOON_X
const BOAT_RAMP_PX := Vector2(318.0, 488.0)
## Hand-placed buildings that aren't split into lots. lot = recorded in [member building_lots].
const LANDMARKS := [
	{"name": "Viper Garage", "rect": Rect2(522.0, 306.0, 30.0, 40.0), "height": 7.0, "style": &"viper", "lot": true, "archetype": "viper_garage"},
	{"name": "Lakeside Chop Shop", "rect": Rect2(522.0, 360.0, 30.0, 40.0), "height": 8.0, "style": &"mangona", "lot": true, "archetype": "chop_shop"},
	{"name": "Grove General Hospital", "rect": Rect2(574.0, 342.0, 90.0, 88.0), "height": 24.0, "style": &"hospital", "lot": false, "archetype": "grove_general_hospital"},
	{"name": "Lakeside trailer", "rect": Rect2(307.0, 682.0, 8.0, 12.0), "height": 3.2, "style": &"trailer", "lot": true, "archetype": "trailer_1f"},
	{"name": "Lakeside trailer", "rect": Rect2(341.0, 682.0, 8.0, 12.0), "height": 3.2, "style": &"trailer", "lot": true, "archetype": "trailer_1f"},
	{"name": "Lakeside trailer", "rect": Rect2(375.0, 682.0, 8.0, 12.0), "height": 3.2, "style": &"trailer", "lot": true, "archetype": "trailer_1f"},
	{"name": "Lakeside trailer", "rect": Rect2(409.0, 682.0, 8.0, 12.0), "height": 3.2, "style": &"trailer", "lot": true, "archetype": "trailer_1f"},
	{"name": "Lakeside trailer", "rect": Rect2(443.0, 682.0, 8.0, 12.0), "height": 3.2, "style": &"trailer", "lot": true, "archetype": "trap_trailer_lakeside"},
]
## Wireframe lots merged into one bigger lot (px) for a building that needs it: the lots it
## encloses become one lot with the given archetype. The Spot (L-01) takes two block 19 lots.
const LOT_MERGES := [
	{"rect": Rect2(534.6, 1025.2, 23.7, 19.2), "archetype": "trap_house_the_spot"},
]
## Lots the wireframe doesn't have, for roster buildings that had none in reach (px, door side).
const EXTRA_LOTS := [
	{"name": "Mangona Hardware", "rect": Rect2(462.0, 231.0, 15.0, 17.0), "outward": Vector3.FORWARD, "height": 6.0, "archetype": "hardware_store"},
	{"name": "Mangona Guns", "rect": Rect2(372.0, 230.0, 12.0, 15.0), "outward": Vector3.FORWARD, "height": 6.0, "archetype": "gun_store"},
	{"name": "Northgrove Savings", "rect": Rect2(692.0, 474.0, 18.0, 16.0), "outward": Vector3.LEFT, "height": 8.0, "archetype": "bank_branch"},
]
## Intentional open frontage: no building, on purpose ([method vacant_areas]). tests/frontage_tests.gd
## excuses street gaps in front of these and fails on any other gap longer than about one lot.
## Rects in px.
const VACANT_PX: Array[Dictionary] = [
	{"name": "Mangona rail spur strip", "reason": "FEC right-of-way between the rail and the 25th St connector", "rect": Rect2(536.0, 640.0, 34.0, 36.0)},
]
## Lake shore parks: the curved stretches of each lake drive (LAKES_PX index, normalised ellipse
## angle range in degrees, 0 = east, 90 = south) stay public green, as West Palm's lakefronts do.
## The straight stretches carry trailers / houses.
const VACANT_SHORES := [
	{"name": "Lake Mangona Park (NE shore)", "lake": 0, "from": -88.0, "to": -20.0},
	{"name": "Lake Mangona Park (NW shore)", "lake": 0, "from": -162.0, "to": -104.0},
	{"name": "Lake Mangona Park (SE shore)", "lake": 0, "from": 24.0, "to": 97.0},
	{"name": "Lake Mangona Park (SW shore)", "lake": 0, "from": 99.0, "to": 155.0},
	{"name": "Clear Lake Green (north and west shore)", "lake": 1, "from": -180.0, "to": -54.0},
	{"name": "Clear Lake Green (SE shore)", "lake": 1, "from": 42.0, "to": 70.0},
	{"name": "Clear Lake Green (SW shore)", "lake": 1, "from": 126.0, "to": 150.0},
]
## Shore park band, in lake radii from the centre.
const SHORE_BAND := Vector2(0.95, 1.45)
## New lots (px, frontage x depth) packed along street frontage the wireframe left empty
## ([method _build_infill]); trailers by Lake Mangona, sheds elsewhere in Mangona.
const INFILL_LOT_PX := {&"tamarack_row": Vector2(9.0, 15.0), &"northgrove": Vector2(8.5, 14.5), &"mangona": Vector2(12.0, 15.0)}
const TRAILER_LOT_PX := Vector2(7.0, 12.0)
## Smallest lot (px) a split or infill lot may have: 12 m frontage, 24 m deep.
const MIN_LOT_PX := Vector2(6.0, 12.0)
## A wireframe lot is split into lots no narrower than this along its street (px, 15 m).
const SPLIT_FRONTAGE_PX := 7.5
## Shallowest corner lot (px, 17 m) cut to face a side street.
const CORNER_DEPTH_PX := 8.5
## Shallowest infill lot (px): fills corner remainders between a row's last lot and the cross street.
const INFILL_MIN_DEPTH_PX := 7.5
## Block index of infill lots: INFILL_BLOCK + road index.
const INFILL_BLOCK := 900
## Rail corridor half width (px) kept clear by infill lots.
const RAIL_HALF_PX := 3.0
## Lake Mangona junkyard (#21): fenced scrap yard, no building.
const JUNKYARD_PX := Rect2(522.0, 546.0, 32.0, 40.0)
## Hot car list (#24): one parked target per district, px + yaw.
const HOT_CARS_PX := [[Vector2(360.0, 1034.0), 0.0], [Vector2(900.0, 460.0), 0.0], [Vector2(262.0, 380.0), 0.0]]
## Drawn road widths (m), wider than the wireframe strokes so driving is comfortable.
const ROAD_WIDTHS := {&"loc": 9.0, &"ave": 12.0, &"art": 16.0, &"highway": 26.0, &"ramp": 8.0}
const ROAD_HEIGHTS := {&"loc": 0.02, &"ave": 0.025, &"art": 0.03, &"highway": 0.035, &"ramp": 0.03}
## Road corridor half widths in wireframe px, as the extractor uses them (ROAD_WIDTHS / 1.2 / 2: the corridors
## stay at the scale they were authored at, so the rescale to 2.0 m/px moved no street, lot or junction).
const ROAD_HALF_WIDTHS_PX := {&"loc": 3.75, &"ave": 5.0, &"art": 6.67, &"highway": 10.83, &"ramp": 3.33}
## Sidewalk between the kerb and the front of a lot (m). Block pads reach the kerb and lots are
## stretched to the back of the sidewalk, so the wireframe block inset (6 px, authored at 1.2 m/px)
## leaves no dead strip between the road and the yards.
const SIDEWALK_M := 2.5
## A rect side fronts a street when a drivable street runs alongside it this close to the kerb (m).
const FRONTAGE_REACH_M := 40.0
const DRIVABLE := [&"loc", &"ave", &"art"]

static var _drivable_segments: Array[Dictionary] = []
static var _street_sides_cache := {}
const TAKEN_CELL_PX := 16.0
## Spatial index of the infill pass's taken rects: cell -> indices.
var _taken_grid := {}
static var _front_segs: Array[Dictionary] = []
static var _poly_bounds_cache := {}
static var _vacant_cache: Array[Dictionary] = []
## I-59 deck top (m); arterials pass underneath.
const DECK_HEIGHT := 6.5
const DECK_THICKNESS := 1.0
const PILLAR_SPACING := 24.0

@export var city_seed := 1337
@export var parked_vehicles := 18
## Puts the baked building kit on every lot ([NorthEndPopulator]) instead of greybox boxes.
@export var populate_kit := true
## Batches the kit and the greybox into merged, distance-tiered meshes ([KitBatcher]). Off = every
## kit scene as-is (the unbatched baseline for tools/benchmark_north_end.tscn).
@export var batch_kit := true

var player_spawn := Vector3.ZERO
var districts: Array[District] = []
## Every building lot: {center: Vector3, footprint: Vector2, height: float, block: Vector2i,
## block_center: Vector3, rect_px: Rect2, district: StringName, index: int}. LocationPlacer and
## main.gd put enterable buildings on them.
var building_lots: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _materials := {}
var _road_points: Array[Dictionary] = []  # {at: Vector3, dir: Vector3, width: float, district: StringName}


func _ready() -> void:
	generate()


func generate() -> void:
	_rng.seed = city_seed
	GameState.city_extent = maxf(city_size(), city_depth())
	player_spawn = px_to_world(PLAYER_SPAWN_PX) + Vector3(0.0, 1.0, 0.0)
	_build_ground()
	_build_water()
	_build_roads()
	_build_rail()
	_build_rail_crossings()
	_build_blocks()
	_build_landmarks()
	_build_extra_lots()
	_build_infill()
	_build_districts()
	if populate_kit:
		NorthEndPopulator.populate(self, batch_kit)
	_build_labels()
	_spawn_vehicles()
	if batch_kit:
		var skip: Array[Node] = []
		skip.assign(get_children().filter(func(n: Node) -> bool: return n is District or n is Vehicle))
		KitBatcher.merge_static(self, skip)


## Width (X) of the playable area in meters.
func city_size() -> float:
	return PLAY_RECT_PX.size.x * METERS_PER_PX


## Depth (Z) of the playable area in meters.
func city_depth() -> float:
	return PLAY_RECT_PX.size.y * METERS_PER_PX


static func px_to_world(px: Vector2) -> Vector3:
	return Vector3((px.x - CENTER_PX.x) * METERS_PER_PX, 0.0, (px.y - CENTER_PX.y) * METERS_PER_PX)


static func world_to_px(at: Vector3) -> Vector2:
	return Vector2(at.x / METERS_PER_PX + CENTER_PX.x, at.z / METERS_PER_PX + CENTER_PX.y)


## District id whose px rect holds [param px], or &"" (neighbouring districts).
static func district_for_px(px: Vector2) -> StringName:
	for id: StringName in DISTRICT_RECTS_PX:
		if (DISTRICT_RECTS_PX[id] as Rect2).has_point(px):
			return id
	return &""


## The building lot nearest [param px] within [param max_px] (wireframe px), skipping [param used]
## lot indices; restricted to [param district] when set. Empty when none is close enough.
func lot_near(px: Vector2, max_px: float, used: Dictionary = {}, district: StringName = &"") -> Dictionary:
	var best := {}
	var best_distance := max_px
	for lot in building_lots:
		if used.has(lot["index"]) or (district != &"" and lot["district"] != district):
			continue
		var rect: Rect2 = lot["rect_px"]
		var distance := 0.0 if rect.has_point(px) else rect.get_center().distance_to(px)
		if distance <= best_distance:
			best_distance = distance
			best = lot
	return best


func _build_ground() -> void:
	var size := maxf(city_size(), city_depth()) + 400.0
	_add_static_box(Vector3(size, 1.0, size), Vector3(0.0, -0.5, 0.0), _material("ground", Color(0.33, 0.35, 0.3)))
	var half := Vector2(city_size(), city_depth()) * 0.5 + Vector2(20.0, 20.0)
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall_size := Vector3(2.0, 30.0, size) if side.x != 0 else Vector3(size, 30.0, 2.0)
		var offset := Vector3(side.x * half.x, 15.0, side.z * half.y)
		_add_static_box(wall_size, offset, null)


func _build_water() -> void:
	var water := _material("water", Color(0.22, 0.45, 0.66))
	var shore := _material("shore", Color(0.55, 0.52, 0.42))
	for lake in LAKES_PX:
		var center := px_to_world(lake["center"])
		var radii: Vector2 = lake["radii"] * METERS_PER_PX
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.0
		mesh.height = 0.1
		mesh.radial_segments = 64
		mesh.material = water
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = center + Vector3(0.0, 0.07, 0.0)
		instance.scale = Vector3(radii.x, 1.0, radii.y)
		add_child(instance)
		# Low sea wall around the shore so cars and people don't wander into the lake.
		var ramp := px_to_world(BOAT_RAMP_PX)
		var segments := 72
		for i in segments:
			var a := center + Vector3(cos(TAU * i / segments) * radii.x, 0.0, sin(TAU * i / segments) * radii.y)
			var b := center + Vector3(cos(TAU * (i + 1) / segments) * radii.x, 0.0, sin(TAU * (i + 1) / segments) * radii.y)
			if (a + b).distance_to(ramp * 2.0) < 24.0:
				continue
			_add_segment(a, b, 0.8, 1.1, 0.55, shore, true)
	# Boat ramp pier (P1) out into Lake Mangona.
	var pier_start := px_to_world(BOAT_RAMP_PX) + Vector3(-4.0, 0.0, 0.0)
	_add_segment(pier_start, pier_start + Vector3(20.0, 0.0, 0.0), 4.0, 0.3, 0.15, _material("pier", Color(0.45, 0.33, 0.2)), true)
	# Lake Worth Lagoon, out past the east wall.
	var lagoon_w := 160.0
	var lagoon := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(lagoon_w, 0.1, city_depth() + 400.0)
	box.material = water
	lagoon.mesh = box
	lagoon.position = Vector3(px_to_world(Vector2(LAGOON_X_PX, 0.0)).x + lagoon_w * 0.5, 0.07, 0.0)
	add_child(lagoon)


## Inside a lake (in px), grown by [param margin] px.
static func _in_water(px: Vector2, margin: float = 0.0) -> bool:
	for lake in LAKES_PX:
		var radii: Vector2 = lake["radii"] + Vector2(margin, margin)
		var d: Vector2 = (px - lake["center"]) / radii
		if d.length_squared() < 1.0:
			return true
	return false


func _build_roads() -> void:
	var asphalt := _material("asphalt", Color(0.17, 0.17, 0.19))
	var line := _material("road_line", Color(0.85, 0.72, 0.2))
	for road in NorthEndLayout.ROADS:
		var kind: StringName = road["kind"]
		if kind == &"rail" or kind == &"highway" or kind == &"ramp":
			continue
		var width: float = ROAD_WIDTHS[kind]
		var y: float = ROAD_HEIGHTS[kind]
		var pts := PackedVector2Array(road["pts"])
		for i in pts.size() - 1:
			var a := px_to_world(pts[i])
			var b := px_to_world(pts[i + 1])
			_add_segment(a, b, width, 0.04, y, asphalt, false)
			if kind == &"art":
				_add_segment(a, b, 0.4, 0.04, y + 0.01, line, false)
			_record_road(a, b, width)
			if i > 0:
				# Fill the joint between bends.
				var along := (px_to_world(pts[i + 1]) - px_to_world(pts[i - 1])).normalized() * width * 0.5
				_add_segment(a - along, a + along, width, 0.04, y, asphalt, false)
	_build_highway(asphalt, line)


## I-59 is an elevated viaduct: arterials pass under it and the diamond-interchange ramps slope
## from the deck down to the arterial. Ramps list their deck end first (see the extractor).
func _build_highway(asphalt: Material, line: Material) -> void:
	var concrete := _material("concrete", Color(0.58, 0.57, 0.55))
	var ramps: Array = NorthEndLayout.ROADS.filter(func(r: Dictionary) -> bool: return r["kind"] == &"ramp")
	var arterials: Array = NorthEndLayout.ROADS.filter(func(r: Dictionary) -> bool: return r["kind"] == &"art")
	var half: float = ROAD_WIDTHS[&"highway"] * 0.5
	for road in NorthEndLayout.ROADS:
		if road["kind"] != &"highway":
			continue
		var pts := PackedVector2Array(road["pts"])
		var since_pillar := 0.0
		for i in pts.size() - 1:
			var a := px_to_world(pts[i])
			var b := px_to_world(pts[i + 1])
			var dir := (b - a).normalized()
			var across := dir.cross(Vector3.UP)
			_add_segment(a - dir * 0.5, b + dir * 0.5, half * 2.0, DECK_THICKNESS, DECK_HEIGHT - DECK_THICKNESS * 0.5, asphalt, true)
			_add_segment(a, b, 0.4, 0.04, DECK_HEIGHT + 0.01, line, false)
			var length := a.distance_to(b)
			var steps := maxi(1, ceili(length / 4.0))
			for s in steps:
				var p0 := a.lerp(b, float(s) / steps)
				var p1 := a.lerp(b, float(s + 1) / steps)
				for side: float in [-1.0, 1.0]:
					var offset := across * side * (half - 0.25)
					if not _ramp_merges_at(world_to_px((p0 + p1) * 0.5 + offset), ramps):
						_add_segment(p0 + offset, p1 + offset, 0.5, 1.0, DECK_HEIGHT + 0.5, concrete, true)
			while since_pillar < length:
				var at := a + dir * since_pillar
				if not _near_any(world_to_px(at), arterials, ROAD_HALF_WIDTHS_PX[&"art"] + 3.0):
					_add_static_box(Vector3(3.0, DECK_HEIGHT - DECK_THICKNESS, 3.0), at + Vector3(0.0, (DECK_HEIGHT - DECK_THICKNESS) * 0.5, 0.0), concrete)
				since_pillar += PILLAR_SPACING
			since_pillar -= length
	var highway_pts: Array = NorthEndLayout.ROADS.filter(func(r: Dictionary) -> bool: return r["kind"] == &"highway")[0]["pts"]
	for ramp in ramps:
		_build_ramp(PackedVector2Array(ramp["pts"]), asphalt, concrete)
		_build_ramp_sign(PackedVector2Array(ramp["pts"]), highway_pts)


## Right-hand traffic: the NB carriageway is the east half. East ramps north of the arterial are
## NB entrances and south of it NB exits; west ramps north are SB exits and south SB entrances.
func _build_ramp_sign(pts: PackedVector2Array, highway: Array) -> void:
	var end := pts[pts.size() - 1]
	var east := pts[0].x > _closest_px(pts[0], highway).x
	var north := pts[0].y < end.y
	var street := ""
	var best := INF
	for entry in NorthEndLayout.STREET_LABELS:
		if entry["art"] and absf(entry["pos"].y - end.y) < best:
			best = absf(entry["pos"].y - end.y)
			street = entry["text"]
	var post_material := _material("sign_post", Color(0.3, 0.3, 0.32))
	var text: String
	var at: Vector3
	if east != north:
		# Exit: sign where the ramp leaves the deck.
		text = "EXIT\n%s" % street
		at = px_to_world(pts[1]) + Vector3(0.0, DECK_HEIGHT, 0.0)
	else:
		# Entrance: sign beside the foot of the ramp.
		text = "I-59 %s\nENTRANCE" % ("NORTH" if east else "SOUTH")
		var foot := px_to_world(pts[pts.size() - 3])
		var dir := (px_to_world(pts[pts.size() - 2]) - foot).normalized()
		at = foot + dir.cross(Vector3.UP) * (float(ROAD_WIDTHS[&"ramp"]) * 0.5 + 1.5)
	_add_mesh_box(Vector3(0.2, 4.0, 0.2), at + Vector3(0.0, 2.0, 0.0), post_material)
	var board := _label(text, 64, 0.03)
	board.modulate = Color(0.55, 1.0, 0.6)
	board.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	board.position = at + Vector3(0.0, 4.8, 0.0)
	add_child(board)


static func _closest_px(p: Vector2, pts: Array) -> Vector2:
	var best := Vector2.INF
	for i in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		if p.distance_to(q) < p.distance_to(best):
			best = q
	return best


## Ramp surface: on the deck for the merge taper, then a straight grade down to the arterial.
func _build_ramp(pts: PackedVector2Array, asphalt: Material, concrete: Material) -> void:
	var width: float = ROAD_WIDTHS[&"ramp"]
	var heights := PackedFloat32Array()
	var total := 0.0
	for i in range(1, pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var run := 0.0
	for i in pts.size():
		if i >= 2:
			run += pts[i - 1].distance_to(pts[i])
		heights.append(lerpf(DECK_HEIGHT, ROAD_HEIGHTS[&"art"], run / total))
	for i in pts.size() - 1:
		var a := px_to_world(pts[i]) + Vector3(0.0, heights[i], 0.0)
		var b := px_to_world(pts[i + 1]) + Vector3(0.0, heights[i + 1], 0.0)
		var dir := (b - a).normalized()
		_add_slab(a - dir * 0.4, b + dir * 0.4, width, 0.6, asphalt)
		if i == 0 or minf(heights[i], heights[i + 1]) < 0.8:
			continue
		var across := Vector3(dir.x, 0.0, dir.z).normalized().cross(Vector3.UP)
		for side: float in [-1.0, 1.0]:
			var offset := across * side * (width * 0.5 - 0.2) + Vector3(0.0, 0.9, 0.0)
			_add_slab(a + offset, b + offset, 0.4, 0.9, concrete)
		if heights[i] > 2.0 and i % 2 == 1:
			_add_static_box(Vector3(1.4, heights[i] - 0.6, 1.4), px_to_world(pts[i]) + Vector3(0.0, (heights[i] - 0.6) * 0.5, 0.0), concrete)


## True where a ramp's merge taper (its first segment, on the deck) meets the deck edge at [param px].
static func _ramp_merges_at(px: Vector2, ramps: Array) -> bool:
	for ramp in ramps:
		var pts: Array = ramp["pts"]
		if px.distance_to(Geometry2D.get_closest_point_to_segment(px, pts[0], pts[1])) <= ROAD_HALF_WIDTHS_PX[&"ramp"] + 1.5:
			return true
	return false


static func _near_any(px: Vector2, roads: Array, distance: float) -> bool:
	for road in roads:
		var pts: Array = road["pts"]
		for i in pts.size() - 1:
			if px.distance_to(Geometry2D.get_closest_point_to_segment(px, pts[i], pts[i + 1])) <= distance:
				return true
	return false


## Box with collision from [param a] to [param b] (any slope); its top face runs through a and b.
func _add_slab(a: Vector3, b: Vector3, width: float, thickness: float, material: Material) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var slab_basis := Basis.looking_at(b - a, Vector3.UP)
	var body := _add_static_box(Vector3(width, thickness, length), (a + b) * 0.5 - slab_basis.y * thickness * 0.5, material)
	body.basis = slab_basis


func _record_road(a: Vector3, b: Vector3, width: float) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var dir := (b - a) / length
	var spacing := 40.0
	var count := int(length / spacing)
	for i in count:
		var at := a + dir * (spacing * (i + 0.5))
		_road_points.append({"at": at, "dir": dir, "width": width, "district": district_for_px(world_to_px(at))})


func _build_rail() -> void:
	var ballast := _material("ballast", Color(0.4, 0.35, 0.3))
	var steel := _material("rail", Color(0.6, 0.6, 0.62))
	for road in NorthEndLayout.ROADS:
		if road["kind"] != &"rail":
			continue
		var pts := PackedVector2Array(road["pts"])
		for i in pts.size() - 1:
			var a := px_to_world(pts[i])
			var b := px_to_world(pts[i + 1])
			_add_segment(a, b, 5.0, 0.06, 0.05, ballast, false)
			var side := (b - a).normalized().cross(Vector3.UP) * 0.75
			for offset in [side, -side]:
				_add_segment(a + offset, b + offset, 0.12, 0.12, 0.12, steel, false)


## Each at-grade crossing gets a pad over the rails and a crossbuck on both sides of the tracks.
func _build_rail_crossings() -> void:
	var pad := _material("crossing", Color(0.3, 0.3, 0.31))
	var post := _material("sign_post", Color(0.55, 0.55, 0.55))
	var board := _material("crossbuck", Color(0.95, 0.95, 0.92))
	for crossing in NorthEndLayout.RAIL_CROSSINGS:
		var at := px_to_world(crossing["at"])
		var dir := Vector3(crossing["dir"].x, 0.0, crossing["dir"].y).normalized()
		var across := dir.cross(Vector3.UP)
		var width: float = ROAD_WIDTHS[crossing["kind"]]
		_add_segment(at - dir * 4.0, at + dir * 4.0, width, 0.06, 0.17, pad, false)
		for side: float in [-1.0, 1.0]:
			# Right-hand kerb of traffic approaching the tracks from this side.
			var base: Vector3 = at - dir * side * 6.0 + across * side * (width * 0.5 + 1.2)
			_add_static_box(Vector3(0.15, 3.0, 0.15), base + Vector3(0.0, 1.5, 0.0), post)
			for tilt: float in [PI / 4.0, -PI / 4.0]:
				var arm := _add_mesh_box(Vector3(1.6, 0.25, 0.05), base + Vector3(0.0, 2.6, 0.0), board)
				arm.rotation = Vector3(0.0, atan2(-across.z, across.x), tilt)

func _build_blocks() -> void:
	var sidewalk := _material("sidewalk", Color(0.47, 0.47, 0.46))
	var reserved := _reserved_rects()
	var blocks: Array = NorthEndLayout.BLOCKS
	for b in blocks.size():
		var block: Dictionary = blocks[b]
		var rect: Rect2 = block["rect"]
		var center := px_to_world(rect.get_center())
		var pad := to_kerb(rect)
		var size := pad.size * METERS_PER_PX
		_add_mesh_box(Vector3(size.x, 0.1, size.y), px_to_world(pad.get_center()) + Vector3(0.0, 0.05, 0.0), sidewalk)
		if block["off"]:
			_add_filler(rect)
			continue
		var lots: Array = (block["lots"] as Array).duplicate()
		var footprint_margin := Vector2(1.5, 1.5)
		if lots.is_empty():
			for building: Rect2 in NorthEndLayout.BUILDINGS:
				if rect.encloses(building.grow(-0.5)):
					lots.append(building)
			footprint_margin = Vector2(0.8, 0.8)
		if lots.is_empty():
			lots.append(rect.grow(-3.0))
		lots = merge_streetless(lots, reserved)
		var split := split_wide(lots, reserved, _spot_points(), LOT_MERGES.map(func(m: Dictionary) -> Rect2: return m["rect"]))
		lots = split["lots"]
		for lot_rect: Rect2 in lots:
			if reserved.any(func(r: Rect2) -> bool: return r.intersects(lot_rect)) or _in_water(lot_rect.get_center()):
				continue
			var district := district_for_px(lot_rect.get_center())
			var merge := _merge_for(lot_rect)
			if not merge.is_empty():
				var merged: Rect2 = merge["rect"]
				if building_lots.any(func(l: Dictionary) -> bool: return l["rect_px"] == merged):
					_building_rng(district)  # the swallowed lot still draws, so later lots keep their looks
					continue
				_add_building(merged, merged.size * METERS_PER_PX - Vector2(3.0, 3.0), district, Vector2i(b, 0), center)
				building_lots[-1]["archetype"] = merge["archetype"]
				continue
			var margin := footprint_margin
			if district == &"tamarack_row":
				margin = Vector2(4.0, 3.0) if lot_rect.size.x > lot_rect.size.y else Vector2(3.0, 4.0)
			var footprint := lot_rect.size * METERS_PER_PX - margin
			if split["extra"].has(lot_rect):
				_add_building(lot_rect, footprint, district, Vector2i(b, 0), center, district, _hashed_height(lot_rect, district), false)
			else:
				_add_building(lot_rect, footprint, district, Vector2i(b, 0), center)


## Roster points (px) that must keep their wireframe lot whole.
static func _spot_points() -> Array:
	var out: Array = []
	for spot: Dictionary in NorthEndSpots.SPOTS:
		if not spot.get("free", false):
			out.append(spot["px"])
	return out


## A lot height drawn from the lot's own seed, so new lots leave the city rng sequence alone.
static func _hashed_height(rect: Rect2, district: StringName) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rect.position, rect.size])
	match district:
		&"tamarack_row":
			return rng.randf_range(4.0, 6.5)
		&"northgrove":
			return rng.randf_range(5.0, 14.0)
		&"mangona":
			return rng.randf_range(6.0, 12.0)
	return rng.randf_range(4.0, 9.0)


func _reserved_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [JUNKYARD_PX]
	for id: StringName in SAFEHOUSES_PX:
		rects.append(SAFEHOUSES_PX[id]["clear"])
	for landmark in LANDMARKS:
		rects.append((landmark["rect"] as Rect2).grow(2.0))
	return rects


## The sides of a px rect that front a drivable street: [{out: Vector2 (unit px axis), gap_m: float
## (rect side to kerb, m, may be negative when the road overlaps), kind: StringName}], nearest street
## per side, closest first. Only streets running alongside the side (within ~25 deg) count.
static func street_sides(rect: Rect2, reach_m := FRONTAGE_REACH_M) -> Array[Dictionary]:
	var key := [rect, reach_m]
	if _street_sides_cache.has(key):
		return _street_sides_cache[key]
	if _drivable_segments.is_empty():
		for road: Dictionary in NorthEndLayout.ROADS:
			if not DRIVABLE.has(road["kind"]):
				continue
			var pts := PackedVector2Array(road["pts"])
			for i in pts.size() - 1:
				if pts[i].distance_to(pts[i + 1]) >= 0.01:
					_drivable_segments.append({"a": pts[i], "b": pts[i + 1], "dir": (pts[i + 1] - pts[i]).normalized(),
						"bounds": Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]), "half_w": ROAD_WIDTHS[road["kind"]] * 0.5, "kind": road["kind"]})
	var search := rect.grow(reach_m / METERS_PER_PX + 20.0)
	var out: Array[Dictionary] = []
	for axis: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var along := Vector2(absf(axis.y), absf(axis.x))
		var half_len := absf(rect.size.dot(along)) * 0.5
		var mid := rect.get_center() + axis * absf(rect.size.dot(axis)) * 0.5
		var best := {}
		for seg: Dictionary in _drivable_segments:
			if absf((seg["dir"] as Vector2).dot(along)) < 0.9 or not search.intersects(seg["bounds"], true):
				continue
			var c := Geometry2D.get_closest_point_to_segment(mid, seg["a"], seg["b"])
			var v := c - mid
			var ahead := v.dot(axis)
			if ahead <= 0.0 or absf(v.dot(along)) > half_len:
				continue
			var gap := ahead * METERS_PER_PX - float(seg["half_w"])
			if gap <= reach_m and (best.is_empty() or gap < best["gap_m"]):
				best = {"out": axis, "gap_m": gap, "kind": seg["kind"]}
		if not best.is_empty():
			out.append(best)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["gap_m"] < b["gap_m"])
	_street_sides_cache[key] = out
	return out


## True when one of [param obstacles] sits between [param rect] and the street on [param side]
## (a [method street_sides] entry).
static func street_blocked(rect: Rect2, side: Dictionary, obstacles: Array) -> bool:
	var axis: Vector2 = side["out"]
	var gap_px := float(side["gap_m"]) / METERS_PER_PX
	if gap_px <= 0.2:
		return false
	var along := Vector2(absf(axis.y), absf(axis.x))
	var side_len := absf(rect.size.dot(along))
	var start := rect.get_center() + axis * absf(rect.size.dot(axis)) * 0.5
	var a := start + axis * 0.1 - along * side_len * 0.25
	var b := start + axis * gap_px + along * side_len * 0.25
	var strip := Rect2(a, Vector2.ZERO).expand(b)
	for other: Rect2 in obstacles:
		if other != rect and not other.encloses(rect) and other.grow(-0.5).intersects(strip):
			return true
	return false


## Nearest open street gap (m) of [param rect], INF when every street side is behind an obstacle.
static func open_street_gap(rect: Rect2, obstacles: Array) -> float:
	for side in street_sides(rect):
		if not street_blocked(rect, side, obstacles):
			return side["gap_m"]
	return INF


## Block lots with no open street (back lots behind another lot, rail-side lots) merged into the
## edge-adjacent neighbour that gives the nearest open street, so every building fronts a street.
static func merge_streetless(lots: Array, reserved: Array = []) -> Array:
	var out: Array = lots.duplicate()
	var changed := true
	while changed:
		changed = false
		for i in out.size():
			var rect: Rect2 = out[i]
			var others: Array = reserved.duplicate()
			for j in out.size():
				if j != i:
					others.append(out[j])
			if open_street_gap(rect, others) < INF:
				continue
			var best := -1
			var best_score := INF
			for j in out.size():
				if j == i:
					continue
				var other: Rect2 = out[j]
				var union := rect.merge(other)
				var overlap := rect.intersection(other).get_area()
				if union.get_area() - rect.get_area() - other.get_area() + overlap > 0.25 * union.get_area():
					continue
				var rest: Array = reserved.duplicate()
				for k in out.size():
					if k != i and k != j:
						rest.append(out[k])
				if rest.any(func(r: Rect2) -> bool: return r.intersects(union.grow(-0.3))):
					continue
				var score := open_street_gap(union, rest) + union.get_area() * 0.001
				if score < best_score:
					best_score = score
					best = j
			if best >= 0 and best_score < INF:
				out[i] = rect.merge(out[best])
				out.remove_at(best)
				changed = true
				break
	return out


## Wide wireframe lots cut into street-fronting lots of at least [constant MIN_LOT_PX], so the 2 m/px
## lots carry houses edge to edge instead of one house in a 30 m+ yard ([method _split_lot]). Lots
## holding a point of [param spots] or inside a [param keep] rect stay whole. Returns {lots: Array
## of Rect2, extra: {Rect2: true} for every piece but the first of a split lot}.
static func split_wide(lots: Array, reserved: Array, spots: Array, keep: Array) -> Dictionary:
	var out: Array = []
	var extra := {}
	for i in lots.size():
		var rect: Rect2 = lots[i]
		if spots.any(func(p: Vector2) -> bool: return rect.has_point(p)) or keep.any(func(k: Rect2) -> bool: return k.grow(0.05).encloses(rect)):
			out.append(rect)
			continue
		var others: Array = reserved.duplicate()
		for j in lots.size():
			if j != i:
				others.append(lots[j])
		var open: Array = []
		for side in street_sides(rect):
			if not street_blocked(rect, side, others) and not open.has(side["out"]):
				open.append(side["out"])
		var pieces := _split_lot(rect, open)
		if pieces.size() > 1 and not (pieces.all(fronts_street_px) and _pieces_open(pieces, others)):
			pieces = [rect]
		for k in pieces.size():
			out.append(pieces[k])
			if k > 0:
				extra[pieces[k]] = true
	return {"lots": out, "extra": extra}


## Every piece keeps a street side not blocked by [param others] or its sibling pieces.
static func _pieces_open(pieces: Array, others: Array) -> bool:
	for piece: Rect2 in pieces:
		var blockers: Array = others + pieces.filter(func(p: Rect2) -> bool: return p != piece)
		if not street_sides(piece).any(func(side: Dictionary) -> bool: return not street_blocked(piece, side, blockers)):
			return false
	return true


## One lot cut for its open street sides ([param open], unit px axes): a through lot (streets front
## and back) splits back to back; a corner lot gives a [constant MIN_LOT_PX] deep strip to the side
## street, so block ends get houses too; what remains splits along its street into lots no narrower
## than [constant SPLIT_FRONTAGE_PX].
static func _split_lot(rect: Rect2, open: Array) -> Array:
	for axis in open:
		if open.has(-axis) and _depth_px(rect, axis) >= MIN_LOT_PX.y * 2.0:
			var a := open.filter(func(o: Vector2) -> bool: return o != axis)
			var b := open.filter(func(o: Vector2) -> bool: return o != -axis)
			var halves := _cut(rect, axis, _depth_px(rect, axis) * 0.5)
			return _split_lot(halves[0], b) + _split_lot(halves[1], a)
	var primary := Vector2.ZERO
	var best_n := 0
	var best_front := 0.0
	for axis in open:
		var front := _front_px(rect, axis)
		var n := floori(front / SPLIT_FRONTAGE_PX)
		if _depth_px(rect, axis) < MIN_LOT_PX.y:
			continue
		if n > best_n or (n == best_n and front > best_front):
			primary = axis
			best_n = n
			best_front = front
	if primary == Vector2.ZERO:
		return [rect]
	for axis in open:
		if absf(axis.dot(primary)) > 0.5:
			continue
		var strip := minf(MIN_LOT_PX.y, best_front - MIN_LOT_PX.x)
		if strip >= CORNER_DEPTH_PX and _front_px(rect, axis) >= MIN_LOT_PX.x:
			var parts := _cut(rect, axis, strip)
			return _split_lot(parts[0], [axis]) + _split_lot(parts[1], open.filter(func(o: Vector2) -> bool: return o != axis))
		if best_n < 2 and best_front >= CORNER_DEPTH_PX and _front_px(rect, axis) >= SPLIT_FRONTAGE_PX * 2.0:
			# Too shallow to carve: the corner lot turns to face the side street.
			return _split_along(rect, axis)
	if best_n < 2:
		return [rect]
	return _split_along(rect, primary)


## [param rect] split along its [param axis] street into lots no narrower than [constant SPLIT_FRONTAGE_PX].
static func _split_along(rect: Rect2, primary: Vector2) -> Array:
	var best_front := _front_px(rect, primary)
	var best_n := maxi(1, floori(best_front / SPLIT_FRONTAGE_PX))
	var out: Array = []
	var step := best_front / best_n
	for k in best_n:
		if primary.x != 0.0:
			out.append(Rect2(rect.position + Vector2(0.0, step * k), Vector2(rect.size.x, step)))
		else:
			out.append(Rect2(rect.position + Vector2(step * k, 0.0), Vector2(step, rect.size.y)))
	return out


## [param rect] cut by a line [param depth] px in from its [param axis] side: [that slab, the rest].
static func _cut(rect: Rect2, axis: Vector2, depth: float) -> Array:
	if axis == Vector2.LEFT:
		return [Rect2(rect.position, Vector2(depth, rect.size.y)), Rect2(rect.position + Vector2(depth, 0.0), rect.size - Vector2(depth, 0.0))]
	if axis == Vector2.RIGHT:
		return [Rect2(Vector2(rect.end.x - depth, rect.position.y), Vector2(depth, rect.size.y)), Rect2(rect.position, rect.size - Vector2(depth, 0.0))]
	if axis == Vector2.UP:
		return [Rect2(rect.position, Vector2(rect.size.x, depth)), Rect2(rect.position + Vector2(0.0, depth), rect.size - Vector2(0.0, depth))]
	return [Rect2(Vector2(rect.position.x, rect.end.y - depth), Vector2(rect.size.x, depth)), Rect2(rect.position, rect.size - Vector2(0.0, depth))]


static func _front_px(rect: Rect2, axis: Vector2) -> float:
	return rect.size.y if axis.x != 0.0 else rect.size.x


static func _depth_px(rect: Rect2, axis: Vector2) -> float:
	return rect.size.x if axis.x != 0.0 else rect.size.y


## [param rect] (px) grown on each street side to [param inset_m] short of the kerb.
static func to_kerb(rect: Rect2, inset_m := 0.0, sides: Array = []) -> Rect2:
	var r := rect
	for side: Dictionary in (sides if not sides.is_empty() else street_sides(rect)):
		var grow := maxf(0.0, float(side["gap_m"]) - inset_m) / METERS_PER_PX
		var axis: Vector2 = side["out"]
		r = r.grow_individual(grow if axis.x < 0.0 else 0.0, grow if axis.y < 0.0 else 0.0, grow if axis.x > 0.0 else 0.0, grow if axis.y > 0.0 else 0.0)
	return r


func _add_building(rect_px: Rect2, footprint: Vector2, district: StringName, block: Vector2i, block_center: Vector3, style: StringName = &"", height: float = -1.0, draw_style := true) -> void:
	var key := style if style != &"" else (district if district != &"" else &"filler")
	if height < 0.0:
		height = _building_height(key)
	var center := px_to_world(rect_px.get_center())
	var material := _style_material(key) if draw_style else null
	var node: Node3D
	if populate_kit:
		node = Node3D.new()
		node.name = "Lot_%d" % building_lots.size()
		node.position = center
		add_child(node)
	else:
		node = _add_static_box(Vector3(footprint.x, height, footprint.y), center + Vector3(0.0, height * 0.5, 0.0), material if material else _material("extra_lot", Color(0.6, 0.58, 0.55)))
	_tag_building(node, rect_px, &"lot")
	building_lots.append({
		"center": center, "footprint": footprint, "height": height, "block": block, "block_center": block_center,
		"rect_px": rect_px, "district": district, "index": building_lots.size(), "census_node": node,
		"classify_footprint": rect_px.size * NorthEndCensus.CLASSIFY_METERS_PER_PX - (rect_px.size * METERS_PER_PX - footprint),
	})


func _building_height(key: StringName) -> float:
	match key:
		&"tamarack_row":
			return _rng.randf_range(4.0, 6.5)
		&"northgrove":
			return _rng.randf_range(5.0, 14.0)
		&"mangona":
			return _rng.randf_range(6.0, 12.0)
	return _rng.randf_range(4.0, 9.0)


## Draws what [method _add_building] would for a lot that is not built (merged away).
func _building_rng(district: StringName) -> void:
	var key := district if district != &"" else &"filler"
	_building_height(key)
	_style_material(key)


func _merge_for(lot_rect: Rect2) -> Dictionary:
	for merge: Dictionary in LOT_MERGES:
		if (merge["rect"] as Rect2).grow(0.05).encloses(lot_rect):
			return merge
	return {}


## Extra roster lots ([constant EXTRA_LOTS]); they draw nothing from the city rng.
func _build_extra_lots() -> void:
	for extra: Dictionary in EXTRA_LOTS:
		var rect: Rect2 = extra["rect"]
		var center := px_to_world(rect.get_center())
		var district := district_for_px(rect.get_center())
		_add_building(rect, rect.size * METERS_PER_PX - Vector2(3.0, 3.0), district, Vector2i(-2, 0), center - (extra["outward"] as Vector3), district, extra["height"], false)
		building_lots[-1]["archetype"] = extra["archetype"]


## New lots along straight street frontage the wireframe left empty, packed kerb-side edge to edge
## ([constant INFILL_LOT_PX]); they draw nothing from the city rng.
func _build_infill() -> void:
	var sidewalk := _material("sidewalk", Color(0.47, 0.47, 0.46))
	var taken: Array = _reserved_rects()
	var vacant_polys: Array = vacant_areas().map(func(v: Dictionary) -> PackedVector2Array: return v["poly"])
	var lot_rects: Array = building_lots.map(func(l: Dictionary) -> Rect2: return l["rect_px"])
	for lot: Dictionary in building_lots:
		# The front yard out to the kerb of the lot's nearest open street belongs to it too.
		var rect: Rect2 = lot["rect_px"]
		var front: Array[Dictionary] = []
		for side in street_sides(rect):
			if not street_blocked(rect, side, lot_rects):
				front.append(side)
				break
		taken.append(to_kerb(rect, 0.0, front) if not front.is_empty() else rect)
	for block: Dictionary in NorthEndLayout.BLOCKS:
		if block["off"]:
			taken.append(block["rect"])
	var corridors := _corridor_segments()
	var roads: Array = NorthEndLayout.ROADS
	var placements: Array[Dictionary] = []
	_taken_grid.clear()
	for i in taken.size():
		_grid_add(i, taken[i])
	for r in roads.size():
		var kind: StringName = roads[r]["kind"]
		if not DRIVABLE.has(kind):
			continue
		var half: float = ROAD_HALF_WIDTHS_PX[kind]
		for run in _straight_runs(PackedVector2Array(roads[r]["pts"])):
			var a: Vector2 = run["axis"]
			var perp := Vector2(a.y, a.x)
			var samples: Array = run["samples"]
			for sgn: float in [1.0, -1.0]:
				var u: float = samples[0].x
				var u_end: float = samples[-1].x
				while u < u_end:
					var placed := _try_infill(u, u_end, a, perp, sgn, samples, half, taken, corridors, vacant_polys)
					if placed.is_empty():
						u += 1.0
						continue
					placed["taken_i"] = taken.size()
					placed["r"] = r
					placed["axis"] = a
					placed["toward"] = perp * -sgn
					_grid_add(taken.size(), placed["rect"])
					taken.append(placed["rect"])
					placements.append(placed)
					u += placed["frontage"]
	for placed: Dictionary in placements:
		_widen_infill(placed, taken, corridors, vacant_polys)
	_taken_grid.clear()
	for placed: Dictionary in placements:
		var rect: Rect2 = taken[placed["taken_i"]]
		var r: int = placed["r"]
		var perp: Vector2 = -placed["toward"]
		var district := district_for_px(rect.get_center())
		var into := Vector3(perp.x, 0.0, perp.y)
		var center := px_to_world(rect.get_center())
		_add_building(rect, rect.size * METERS_PER_PX - Vector2(3.0, 3.0), district, Vector2i(INFILL_BLOCK + r, 0), center + into * 20.0, district, _hashed_height(rect, district), false)
		if placed.has("archetype"):
			building_lots[-1]["archetype"] = placed["archetype"]
		var pad := to_kerb(rect)
		var size := pad.size * METERS_PER_PX
		_add_mesh_box(Vector3(size.x, 0.1, size.y), px_to_world(pad.get_center()) + Vector3(0.0, 0.05, 0.0), sidewalk)


## Indexes taken rect [param i] in [member _taken_grid] (stale entries are harmless: the check
## reads the current rect).
func _grid_add(i: int, rect: Rect2) -> void:
	for cx in range(floori(rect.position.x / TAKEN_CELL_PX), floori(rect.end.x / TAKEN_CELL_PX) + 1):
		for cy in range(floori(rect.position.y / TAKEN_CELL_PX), floori(rect.end.y / TAKEN_CELL_PX) + 1):
			var key := Vector2i(cx, cy)
			if not _taken_grid.has(key):
				_taken_grid[key] = []
			if not (_taken_grid[key] as Array).has(i):
				(_taken_grid[key] as Array).append(i)


## Widens an infill lot along its frontage into leftover kerb too short for another lot (under
## [constant MIN_LOT_PX].x on either side), so rows run tight to the cross street.
func _widen_infill(placed: Dictionary, taken: Array, corridors: Array, vacant_polys: Array) -> void:
	var i: int = placed["taken_i"]
	var rect: Rect2 = taken[i]
	var a: Vector2 = (placed["axis"] as Vector2).abs()
	var district := district_for_px(rect.get_center())
	taken[i] = Rect2()
	for dir: float in [-1.0, 1.0]:
		var grown := rect
		var step := 0.5
		while step < MIN_LOT_PX.x:
			var trial := rect.expand(rect.get_center() + a * dir * (rect.size.dot(a) * 0.5 + step))
			if not _infill_ok(trial, district, taken, corridors, placed["toward"], vacant_polys):
				break
			grown = trial
			step += 0.5
		if step >= MIN_LOT_PX.x:
			grown = rect
		rect = grown
	taken[i] = rect
	_grid_add(i, rect)


## The infill lot at [param u] on side [param sgn] of a straight run, full size first, then down to
## [constant MIN_LOT_PX]: {rect, frontage, archetype?}, or {} when nothing fits there.
func _try_infill(u: float, u_end: float, a: Vector2, perp: Vector2, sgn: float, samples: Array, half: float, taken: Array, corridors: Array, vacant_polys: Array) -> Dictionary:
	var probe := _infill_point(u + 3.0, samples, a, perp, sgn, half + 6.0)
	var probe_d := district_for_px(probe)
	if not INFILL_LOT_PX.has(probe_d):
		return {}
	var full: Vector2 = INFILL_LOT_PX[probe_d]
	var archetype := ""
	if probe_d == &"mangona":
		for lake: Dictionary in LAKES_PX:
			var d: Vector2 = (probe - lake["center"]) / ((lake["radii"] as Vector2) + Vector2(45.0, 45.0))
			if d.length_squared() < 1.0:
				full = TRAILER_LOT_PX
				archetype = "trailer_1f"
	var sizes: Array[Vector2] = []
	for w: float in [full.x, MIN_LOT_PX.x]:
		var depth := full.y
		while depth >= minf(INFILL_MIN_DEPTH_PX, full.y) - 0.01:
			sizes.append(Vector2(w, depth))
			depth -= 1.0
	var fronts := {}
	for size: Vector2 in sizes:
		if size.x > full.x or u + size.x > u_end + 0.5:
			continue
		if not fronts.has(size.x):
			var f := -INF
			for k in range(_first_sample_at(samples, u - 0.5), samples.size()):
				var smp: Vector2 = samples[k]
				if smp.x > u + size.x + 0.5:
					break
				f = maxf(f, smp.y * sgn)
			fronts[size.x] = f
		var front: float = fronts[size.x]
		var w0 := front + half + 0.3
		var p0 := a * u + perp * (w0 * sgn)
		var p1 := a * (u + size.x) + perp * ((w0 + size.y) * sgn)
		var rect := Rect2(p0, Vector2.ZERO).expand(p1)
		if _infill_ok(rect, probe_d, taken, corridors, perp * -sgn, vacant_polys):
			var out := {"rect": rect, "frontage": size.x}
			if archetype != "" and size == full:
				out["archetype"] = archetype
			return out
	return {}


static func _infill_point(u: float, samples: Array, a: Vector2, perp: Vector2, sgn: float, off: float) -> Vector2:
	# Nearest sample along the run (the first of equally near ones), by bisection.
	var i := _first_sample_at(samples, u)
	var best: Vector2 = samples[mini(i, samples.size() - 1)]
	if i > 0:
		var j := i - 1
		while j > 0 and is_equal_approx((samples[j - 1] as Vector2).x, (samples[j] as Vector2).x):
			j -= 1
		var left: Vector2 = samples[j]
		if i >= samples.size() or absf(left.x - u) <= absf(best.x - u):
			best = left
	return a * u + perp * (best.y + off * sgn)


## Index of the first of the sorted [param samples] whose along value is at least [param u].
static func _first_sample_at(samples: Array, u: float) -> int:
	var lo := 0
	var hi := samples.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if (samples[mid] as Vector2).x < u:
			lo = mid + 1
		else:
			hi = mid
	return lo


func _infill_ok(rect: Rect2, district: StringName, taken: Array, corridors: Array, toward_road: Vector2, vacant_polys: Array = []) -> bool:
	var inner := rect.grow(-0.1)
	if _taken_grid.is_empty():
		for other: Rect2 in taken:
			if other.intersects(inner):
				return false
	else:
		for cx in range(floori(inner.position.x / TAKEN_CELL_PX), floori(inner.end.x / TAKEN_CELL_PX) + 1):
			for cy in range(floori(inner.position.y / TAKEN_CELL_PX), floori(inner.end.y / TAKEN_CELL_PX) + 1):
				for i: int in _taken_grid.get(Vector2i(cx, cy), []):
					if (taken[i] as Rect2).intersects(inner):
						return false
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for c: Vector2 in corners:
		if district_for_px(c) != district or not PLAY_RECT_PX.has_point(c):
			return false
	for c: Vector2 in corners + [rect.get_center(), (corners[0] + corners[1]) * 0.5, (corners[1] + corners[2]) * 0.5, (corners[2] + corners[3]) * 0.5, (corners[3] + corners[0]) * 0.5]:
		if _in_water(c, 1.0):
			return false
	var shape := PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)])
	for poly: PackedVector2Array in vacant_polys:
		if _poly_bounds(poly).intersects(inner) and not Geometry2D.intersect_polygons(shape, poly).is_empty():
			return false
	var search := rect.grow(12.0)
	for seg: Dictionary in corridors:
		if search.intersects(seg["bounds"], true) and _segment_rect_distance(seg["a"], seg["b"], rect) < float(seg["half"]):
			return false
	if not fronts_street_px(rect):
		return false
	var sides := street_sides(rect)
	return sides.any(func(s: Dictionary) -> bool: return (s["out"] as Vector2).is_equal_approx(toward_road) and float(s["gap_m"]) <= float(sides[0]["gap_m"]) + 3.0)


## Every intentional open space ([constant VACANT_PX], [constant VACANT_SHORES]): [{name, reason,
## poly: PackedVector2Array (px)}].
static func vacant_areas() -> Array[Dictionary]:
	if not _vacant_cache.is_empty():
		return _vacant_cache
	for vacant: Dictionary in VACANT_PX:
		var r: Rect2 = vacant["rect"]
		_vacant_cache.append({"name": vacant["name"], "reason": vacant["reason"],
			"poly": PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])})
	for shore: Dictionary in VACANT_SHORES:
		var lake: Dictionary = LAKES_PX[shore["lake"]]
		var center: Vector2 = lake["center"]
		var radii: Vector2 = lake["radii"]
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		var steps := 24
		for k in steps + 1:
			var t := deg_to_rad(lerpf(shore["from"], shore["to"], float(k) / steps))
			var unit := Vector2(cos(t), sin(t)) * radii
			inner.append(center + unit * SHORE_BAND.x)
			outer.append(center + unit * SHORE_BAND.y)
		inner.reverse()
		_vacant_cache.append({"name": shore["name"], "reason": "lakefront park along the curved shore drive", "poly": outer + inner})
	return _vacant_cache


## Every road, ramp, highway and rail segment with the px half width infill lots keep clear of.
static func _corridor_segments() -> Array:
	var out: Array = []
	for road: Dictionary in NorthEndLayout.ROADS:
		var half: float = RAIL_HALF_PX if road["kind"] == &"rail" else ROAD_HALF_WIDTHS_PX.get(road["kind"], 3.75)
		var pts := PackedVector2Array(road["pts"])
		for i in pts.size() - 1:
			out.append({"a": pts[i], "b": pts[i + 1], "half": half, "bounds": Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(half)})
	return out


## Stretches of a polyline within ~14 deg of one axis: [{axis: Vector2 (RIGHT or DOWN), samples:
## Array of Vector2(along, across) every ~1 px, sorted by along}].
static func _straight_runs(pts: PackedVector2Array) -> Array:
	var runs: Array = []
	var current := {}
	for i in pts.size() - 1:
		var d := pts[i + 1] - pts[i]
		if d.length() < 0.01:
			continue
		var dir := d.normalized()
		var axis := Vector2.ZERO
		if absf(dir.x) > 0.97:
			axis = Vector2.RIGHT
		elif absf(dir.y) > 0.97:
			axis = Vector2.DOWN
		if axis == Vector2.ZERO or (not current.is_empty() and current["axis"] != axis):
			if not current.is_empty():
				runs.append(current)
			current = {}
			if axis == Vector2.ZERO:
				continue
		if current.is_empty():
			current = {"axis": axis, "samples": []}
		var perp := Vector2(axis.y, axis.x)
		var n := maxi(1, ceili(d.length()))
		for k in n + 1:
			var p := pts[i] + d * (float(k) / n)
			current["samples"].append(Vector2(p.dot(axis), p.dot(perp)))
	if not current.is_empty():
		runs.append(current)
	for run: Dictionary in runs:
		(run["samples"] as Array).sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
	return runs


## Map rule 8 for generated lots: a street (loc/ave/art) within 23.5 px and no ramp or I-59 nearer
## than it (0.8 px margin over the 1.5 px sampling the road-network test uses).
static func fronts_street_px(rect: Rect2) -> bool:
	if _front_segs.is_empty():
		for road: Dictionary in NorthEndLayout.ROADS:
			var kind: StringName = road["kind"]
			var is_street := kind in [&"loc", &"ave", &"art"]
			if not is_street and not kind in [&"highway", &"ramp"]:
				continue
			var pts: PackedVector2Array = road["pts"]
			for i in pts.size() - 1:
				_front_segs.append({"a": pts[i], "b": pts[i + 1], "street": is_street,
					"bounds": Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1])})
	# Segments whose bounds are beyond 24.5 px can neither front the lot nor undercut its street.
	var search := rect.grow(24.5)
	var street := INF
	var freeway := INF
	for seg: Dictionary in _front_segs:
		if not search.intersects(seg["bounds"], true):
			continue
		var d := _segment_rect_distance(seg["a"], seg["b"], rect)
		if seg["street"]:
			street = minf(street, d)
		else:
			freeway = minf(freeway, d)
	return street <= 23.5 and street + 0.8 <= freeway


static func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var key := hash(poly)
	if not _poly_bounds_cache.has(key):
		var r := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			r = r.expand(v)
		_poly_bounds_cache[key] = r
	return _poly_bounds_cache[key]


static func _segment_rect_distance(a: Vector2, b: Vector2, rect: Rect2) -> float:
	if rect.has_point(a) or rect.has_point(b):
		return 0.0
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var best := INF
	for k in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[k], corners[(k + 1) % 4]) != null:
			return 0.0
		best = minf(best, corners[k].distance_to(Geometry2D.get_closest_point_to_segment(corners[k], a, b)))
	for p: Vector2 in [a, b]:
		best = minf(best, p.distance_to(p.clamp(rect.position, rect.end)))
	return best


func _style_material(key: StringName) -> StandardMaterial3D:
	var palettes := {
		&"tamarack_row": [Color(0.62, 0.52, 0.42), Color(0.55, 0.6, 0.55), Color(0.66, 0.6, 0.48), Color(0.5, 0.52, 0.6), Color(0.6, 0.45, 0.42)],
		&"northgrove": [Color(0.55, 0.32, 0.26), Color(0.42, 0.5, 0.58), Color(0.7, 0.62, 0.45), Color(0.48, 0.38, 0.52), Color(0.36, 0.52, 0.44)],
		&"mangona": [Color(0.42, 0.44, 0.46), Color(0.34, 0.38, 0.44), Color(0.5, 0.48, 0.42), Color(0.3, 0.32, 0.3), Color(0.45, 0.4, 0.36)],
		&"filler": [Color(0.66, 0.64, 0.6), Color(0.7, 0.68, 0.64), Color(0.62, 0.62, 0.6)],
		&"viper": [Color(0.55, 0.18, 0.18)],
		&"hospital": [Color(0.86, 0.84, 0.82)],
		&"trailer": [Color(0.78, 0.76, 0.7), Color(0.62, 0.68, 0.72)],
	}
	var palette: Array = palettes.get(key, palettes[&"filler"])
	var shade := _rng.randi_range(0, palette.size() - 1)
	return _material("%s_%d" % [key, shade], palette[shade])


## Hatched neighbouring districts: one low, pale box per block.
func _add_filler(rect: Rect2) -> void:
	var inner := rect.grow(-4.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var height := _rng.randf_range(4.0, 10.0)
	var center := px_to_world(inner.get_center())
	var size := inner.size * METERS_PER_PX
	var body := _add_static_box(Vector3(size.x, height, size.y), center + Vector3(0.0, height * 0.5, 0.0), _style_material(&"filler"))
	_tag_building(body, rect, &"filler")


## Marks a building box for the North End census ([NorthEndCensus]): kind is lot, filler or landmark.
func _tag_building(body: Node3D, rect_px: Rect2, kind: StringName) -> void:
	body.add_to_group(NorthEndCensus.GROUP)
	body.set_meta(&"rect_px", rect_px)
	body.set_meta(&"census_kind", kind)


func _build_landmarks() -> void:
	for landmark in LANDMARKS:
		var rect: Rect2 = landmark["rect"]
		var center := px_to_world(rect.get_center())
		var footprint := rect.size * METERS_PER_PX - Vector2(1.0, 1.0)
		var district := district_for_px(rect.get_center())
		if landmark["lot"]:
			_add_building(rect, footprint, district, Vector2i(-1, 0), center + Vector3(0.0, 0.0, -1.0), landmark["style"], landmark["height"])
			building_lots[-1]["archetype"] = landmark["archetype"]
		else:
			var height: float = landmark["height"]
			var material := _style_material(landmark["style"])
			var body: Node3D
			if populate_kit:
				body = Node3D.new()
				body.name = "Landmark_%s" % String(landmark["name"]).validate_node_name()
				body.position = center
				add_child(body)
			else:
				body = _add_static_box(Vector3(footprint.x, height, footprint.y), center + Vector3(0.0, height * 0.5, 0.0), material)
			_tag_building(body, rect, &"landmark")
			body.set_meta(&"landmark", landmark["name"])
			body.set_meta(&"archetype", landmark["archetype"])
	if not populate_kit:
		# Hospital red cross on the roof.
		var hospital := px_to_world((LANDMARKS[2]["rect"] as Rect2).get_center()) + Vector3(0.0, 24.1, 0.0)
		var red := _material("cross", Color(0.8, 0.12, 0.12))
		_add_mesh_box(Vector3(30.0, 0.2, 9.0), hospital, red)
		_add_mesh_box(Vector3(9.0, 0.2, 30.0), hospital, red)
	# Junkyard: chain-link fence (open toward Industrial Way) and scrap piles.
	var fence := _material("fence", Color(0.5, 0.5, 0.48))
	var corners := [JUNKYARD_PX.position, Vector2(JUNKYARD_PX.end.x, JUNKYARD_PX.position.y), JUNKYARD_PX.end, Vector2(JUNKYARD_PX.position.x, JUNKYARD_PX.end.y)]
	for i in 3:
		_add_segment(px_to_world(corners[i]), px_to_world(corners[i + 1]), 0.3, 2.4, 1.2, fence, true)
	var scrap := _material("scrap", Color(0.42, 0.3, 0.22))
	for i in 7:
		var at := px_to_world(JUNKYARD_PX.position + Vector2(_rng.randf_range(8.0, JUNKYARD_PX.size.x - 4.0), _rng.randf_range(5.0, JUNKYARD_PX.size.y - 5.0)))
		var size := Vector3(_rng.randf_range(2.5, 5.0), _rng.randf_range(1.2, 2.5), _rng.randf_range(2.0, 4.5))
		_add_static_box(size, at + Vector3(0.0, size.y * 0.5, 0.0), scrap)


func _build_labels() -> void:
	for entry in NorthEndLayout.STREET_LABELS:
		var at := px_to_world(entry["pos"])
		var yaw := deg_to_rad(-float(entry["rot"]))
		var text: String = entry["text"]
		var flat := _label(text, 72 if entry["art"] else 56, 0.06)
		flat.position = at + Vector3(0.0, 0.15, 0.0)
		flat.rotation = Vector3(-PI / 2.0, yaw, 0.0)
		add_child(flat)
		# A street sign post beside the name, readable from the ground.
		_add_mesh_box(Vector3(0.12, 3.2, 0.12), at + Vector3(0.0, 1.6, 0.0), _material("sign_post", Color(0.3, 0.3, 0.32)))
		var sign := _label(text, 40, 0.02)
		sign.modulate = Color(0.85, 1.0, 0.85)
		sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sign.position = at + Vector3(0.0, 3.6, 0.0)
		add_child(sign)
	for lake in LAKES_PX:
		var label := _label(lake["name"], 96, 0.12)
		label.modulate = Color(0.75, 0.88, 1.0)
		label.position = px_to_world(lake["center"]) + Vector3(0.0, 0.2, 0.0)
		label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		add_child(label)
	_build_highway_signs()


func _build_highway_signs() -> void:
	var pts: PackedVector2Array
	for road in NorthEndLayout.ROADS:
		if road["kind"] == &"highway":
			pts = PackedVector2Array(road["pts"])
	var next := 0.0
	var travelled := 0.0
	for i in pts.size() - 1:
		var length := pts[i].distance_to(pts[i + 1]) * METERS_PER_PX
		while next <= travelled + length:
			var px := pts[i].lerp(pts[i + 1], (next - travelled) / length)
			if PLAY_RECT_PX.grow(20.0).has_point(px):
				var dir := px_to_world(pts[i + 1]) - px_to_world(pts[i])
				var at := px_to_world(px) + dir.normalized().cross(Vector3.UP) * (float(ROAD_WIDTHS[&"highway"]) * 0.5 - 0.25) + Vector3(0.0, DECK_HEIGHT + 1.0, 0.0)
				_add_mesh_box(Vector3(0.2, 4.0, 0.2), at + Vector3(0.0, 2.0, 0.0), _material("sign_post", Color(0.3, 0.3, 0.32)))
				var shield := _label("I-59", 96, 0.03)
				shield.modulate = Color(0.55, 0.7, 1.0)
				shield.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
				shield.position = at + Vector3(0.0, 4.6, 0.0)
				add_child(shield)
			next += 220.0
		travelled += length
	for exit in [[Vector2(247.0, 700.0), "EXIT  Lakes Blvd"], [Vector2(283.0, 1040.0), "EXIT  Okee Blvd"]]:
		var at := px_to_world(exit[0])
		_add_mesh_box(Vector3(0.2, 5.0, 0.2), at + Vector3(0.0, 2.5, 0.0), _material("sign_post", Color(0.3, 0.3, 0.32)))
		var sign := _label(exit[1], 64, 0.03)
		sign.modulate = Color(0.6, 1.0, 0.6)
		sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sign.position = at + Vector3(0.0, 5.8, 0.0)
		add_child(sign)


func _label(text: String, font_size: int, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = maxi(4, font_size >> 3)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.double_sided = true
	return label


func _build_districts() -> void:
	for resource in TurfContent.all(Turf.DISTRICTS):
		var data := resource as DistrictData
		if data == null:
			continue
		var id := TurfContent.id_of(data)
		if not DISTRICT_RECTS_PX.has(id):
			push_warning("CityGenerator: district '%s' has no place on the North End map, skipped" % id)
			continue
		var rect: Rect2 = DISTRICT_RECTS_PX[id]
		var district := District.new()
		district.name = "District_%s" % id
		district.district_id = id
		district.extents = rect.size * METERS_PER_PX
		district.position = px_to_world(rect.get_center())
		var safehouse: Dictionary = SAFEHOUSES_PX[id]
		district.safehouse_position = px_to_world(safehouse["at"]) - district.position
		district.safehouse_yaw = safehouse["yaw"]
		district.auto_spawn_defenders = false
		for point in _patrol_points(id):
			district.patrol_points.append(to_global(point))
		add_child(district)
		districts.append(district)
		district.spawn_defenders(hash([city_seed, String(id)]) & 0x7fffffff)
		_add_district_map_label(data.display_name, rect)


## Sidewalk points in front of the district's lots. Tamarack Row's patrols keep to the far south
## (8th St) so the start at 23rd St is quiet.
func _patrol_points(id: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for lot in building_lots:
		if lot["district"] != id:
			continue
		if id == &"tamarack_row" and (lot["rect_px"] as Rect2).position.y < 1066.0:
			continue
		points.append(LocationPlacer.door_transform(lot).origin + LocationPlacer.door_transform(lot).basis.z * 1.5)
	var picked: Array[Vector3] = []
	for i in mini(16, points.size()):
		picked.append(points[_rng.randi_range(0, points.size() - 1)])
	return picked


func _add_district_map_label(text: String, rect: Rect2) -> void:
	var label := _label(text.to_upper(), 96, 0.5)
	label.layers = GameState.MAP_LAYER
	label.position = px_to_world(rect.get_center()) + Vector3(0.0, 82.0, 0.0)
	label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	add_child(label)


func _spawn_vehicles() -> void:
	# One car right next to the player, facing east along 23rd St, so the first thing they can do is drive.
	_add_vehicle(player_spawn + Vector3(4.0, 0.5, 0.0), PI / 2.0)
	for hot in HOT_CARS_PX:
		_add_vehicle(px_to_world(hot[0]) + Vector3(0.0, 0.5, 0.0), hot[1], Color(0.95, 0.35, 0.05))
	var spots := _road_points.filter(func(p: Dictionary) -> bool: return p["width"] <= 12.0 and p["district"] != &"" and (p["at"] as Vector3).distance_to(player_spawn) > 40.0)
	for i in mini(parked_vehicles, spots.size()):
		var spot: Dictionary = spots.pop_at(_rng.randi_range(0, spots.size() - 1))
		var dir: Vector3 = spot["dir"]
		var curb := dir.cross(Vector3.UP) * (float(spot["width"]) * 0.5 - 1.3)
		_add_vehicle(spot["at"] + curb + Vector3(0.0, 0.5, 0.0), atan2(dir.x, dir.z))


func _add_vehicle(position: Vector3, yaw: float, color: Color = Color(0, 0, 0, 0)) -> void:
	var vehicle := Vehicle.new()
	vehicle.body_color = color if color.a > 0.0 else CAR_COLORS[_rng.randi_range(0, CAR_COLORS.size() - 1)]
	vehicle.position = position
	vehicle.rotation.y = yaw
	add_child(vehicle)


## A box from [param a] to [param b] (XZ), [param width] across, [param height] tall, its centre at [param y].
func _add_segment(a: Vector3, b: Vector3, width: float, height: float, y: float, material: Material, collide: bool) -> void:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	if length < 0.05:
		return
	var size := Vector3(width, height, length)
	var center := (a + b) * 0.5
	center.y = y
	var yaw := atan2(b.x - a.x, b.z - a.z)
	var node: Node3D
	if collide:
		node = _add_static_box(size, center, material)
	else:
		node = _add_mesh_box(size, center, material)
	node.rotation.y = yaw


func _add_static_box(size: Vector3, position: Vector3, material: Material) -> StaticBody3D:
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
	return body


func _add_mesh_box(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	add_child(instance)
	return instance


func _material(key: String, color: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_materials[key] = material
	return _materials[key]
