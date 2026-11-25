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
const METERS_PER_PX := 1.2
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
	{"name": "Viper Garage", "rect": Rect2(522.0, 306.0, 30.0, 40.0), "height": 7.0, "style": &"viper", "lot": true},
	{"name": "Lakeside Chop Shop", "rect": Rect2(522.0, 360.0, 30.0, 40.0), "height": 8.0, "style": &"mangona", "lot": true},
	{"name": "Grove General Hospital", "rect": Rect2(574.0, 342.0, 90.0, 88.0), "height": 24.0, "style": &"hospital", "lot": false},
	{"name": "Lakeside trailer", "rect": Rect2(305.0, 688.0, 12.0, 6.0), "height": 3.2, "style": &"trailer", "lot": true},
	{"name": "Lakeside trailer", "rect": Rect2(339.0, 688.0, 12.0, 6.0), "height": 3.2, "style": &"trailer", "lot": true},
	{"name": "Lakeside trailer", "rect": Rect2(373.0, 688.0, 12.0, 6.0), "height": 3.2, "style": &"trailer", "lot": true},
	{"name": "Lakeside trailer", "rect": Rect2(407.0, 688.0, 12.0, 6.0), "height": 3.2, "style": &"trailer", "lot": true},
	{"name": "Lakeside trailer", "rect": Rect2(441.0, 688.0, 12.0, 6.0), "height": 3.2, "style": &"trailer", "lot": true},
]
## Lake Mangona junkyard (#21): fenced scrap yard, no building.
const JUNKYARD_PX := Rect2(522.0, 546.0, 32.0, 40.0)
## Hot car list (#24): one parked target per district, px + yaw.
const HOT_CARS_PX := [[Vector2(360.0, 1034.0), 0.0], [Vector2(900.0, 460.0), 0.0], [Vector2(262.0, 380.0), 0.0]]
## Drawn road widths (m), wider than the wireframe strokes so driving is comfortable.
const ROAD_WIDTHS := {&"loc": 9.0, &"ave": 12.0, &"art": 16.0, &"highway": 26.0, &"ramp": 8.0}
const ROAD_HEIGHTS := {&"loc": 0.02, &"ave": 0.025, &"art": 0.03, &"highway": 0.035, &"ramp": 0.03}
## Half widths in wireframe px (ROAD_WIDTHS / METERS_PER_PX / 2), as the extractor uses them.
const ROAD_HALF_WIDTHS_PX := {&"loc": 3.75, &"ave": 5.0, &"art": 6.67, &"highway": 10.83, &"ramp": 3.33}
## I-59 deck top (m); arterials pass underneath.
const DECK_HEIGHT := 6.5
const DECK_THICKNESS := 1.0
const PILLAR_SPACING := 24.0

@export var city_seed := 1337
@export var parked_vehicles := 18

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
	_build_labels()
	_build_districts()
	_spawn_vehicles()


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
		var size := rect.size * METERS_PER_PX
		_add_mesh_box(Vector3(size.x, 0.1, size.y), center + Vector3(0.0, 0.05, 0.0), sidewalk)
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
		for lot_rect: Rect2 in lots:
			if reserved.any(func(r: Rect2) -> bool: return r.intersects(lot_rect)) or _in_water(lot_rect.get_center()):
				continue
			var district := district_for_px(lot_rect.get_center())
			var margin := footprint_margin
			if district == &"tamarack_row":
				margin = Vector2(4.0, 3.0) if lot_rect.size.x > lot_rect.size.y else Vector2(3.0, 4.0)
			var footprint := lot_rect.size * METERS_PER_PX - margin
			_add_building(lot_rect, footprint, district, Vector2i(b, 0), center)


func _reserved_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [JUNKYARD_PX]
	for id: StringName in SAFEHOUSES_PX:
		rects.append(SAFEHOUSES_PX[id]["clear"])
	for landmark in LANDMARKS:
		rects.append((landmark["rect"] as Rect2).grow(2.0))
	return rects


func _add_building(rect_px: Rect2, footprint: Vector2, district: StringName, block: Vector2i, block_center: Vector3, style: StringName = &"", height: float = -1.0) -> void:
	var key := style if style != &"" else (district if district != &"" else &"filler")
	if height < 0.0:
		match key:
			&"tamarack_row":
				height = _rng.randf_range(4.0, 6.5)
			&"northgrove":
				height = _rng.randf_range(5.0, 14.0)
			&"mangona":
				height = _rng.randf_range(6.0, 12.0)
			_:
				height = _rng.randf_range(4.0, 9.0)
	var center := px_to_world(rect_px.get_center())
	var body := _add_static_box(Vector3(footprint.x, height, footprint.y), center + Vector3(0.0, height * 0.5, 0.0), _style_material(key))
	_tag_building(body, rect_px, &"lot")
	building_lots.append({
		"center": center, "footprint": footprint, "height": height, "block": block, "block_center": block_center,
		"rect_px": rect_px, "district": district, "index": building_lots.size(),
	})


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
func _tag_building(body: StaticBody3D, rect_px: Rect2, kind: StringName) -> void:
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
		else:
			var height: float = landmark["height"]
			var body := _add_static_box(Vector3(footprint.x, height, footprint.y), center + Vector3(0.0, height * 0.5, 0.0), _style_material(landmark["style"]))
			_tag_building(body, rect, &"landmark")
			body.set_meta(&"landmark", landmark["name"])
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
