class_name HouseLayouts
extends RefCounted
## Hand-authored floor plans for the three house tiers. Everything is in house-local metres, with the
## house centred on its origin and the front door facing +Z (the street).
##
## walls: a -> b in XZ with openings {id, kind: door|window|arch, at: distance from a, w: width}
## furniture: {name, pos: Vector2 (centre), size: Vector3, container: bool, search: seconds}
## cameras: {pos: Vector3, yaw: degrees (0 = looking +Z, 90 = +X), pitch: degrees}
## alarmed: opening ids wired to the alarm. owners: rooms the owners hang out in.
## dog: yard spawn. breaker: {pos, yaw} on an outside wall. dvr: {pos, size} the CCTV recorder.
## safe_lock: {hits, speed} for the [TimingMinigame] on any container with "safe" in its name.

enum Tier { LOW, MEDIUM, HIGH }

const TIER_NAMES := ["Low income", "Medium income", "High income"]
## Seconds until the neighbours call the police after a break-in on an empty house.
const NEIGHBOUR_SECONDS := [60.0, 45.0, 35.0]


## The plans below are authored on a compact grid; [method get_layout] stretches them by this much so
## rooms read right around the 1.8 m character and third-person camera (see docs/design/SCALE.md).
const PLAN_SCALE := 1.4
## Clear width for every door (the player capsule is 0.8 m across).
const MIN_DOOR_WIDTH := 1.2
## How much windows and archways widen along with the plan.
const OPENING_SCALE := 1.25
## Furniture and fixtures closer than this to a wall keep their gap to it instead of drifting out.
const HUG_DISTANCE := 0.6
## Camera mounts move up with the taller walls.
const CAMERA_LIFT := 0.2


static func get_layout(tier: int) -> Dictionary:
	match tier:
		Tier.MEDIUM:
			return scaled(_medium())
		Tier.HIGH:
			return scaled(_high())
	return scaled(_low())


## Applies [constant PLAN_SCALE] to an authored plan: rooms, walls and openings stretch; furniture keeps
## its real-world size and stays against whichever wall it was against; doors widen to at least
## [constant MIN_DOOR_WIDTH].
static func scaled(plan: Dictionary, factor := PLAN_SCALE) -> Dictionary:
	var out := plan.duplicate(true)
	var bounds := Rect2(-plan["size"] * 0.5, plan["size"])
	out["size"] = plan["size"] * factor
	var rooms: Array = []
	for room: Dictionary in plan["rooms"]:
		var rect: Rect2 = room["rect"]
		rooms.append({"name": room["name"], "rect": Rect2(rect.position * factor, rect.size * factor)})
	out["rooms"] = rooms
	var walls: Array = []
	for wall: Dictionary in plan["walls"]:
		var openings: Array = []
		for opening: Dictionary in wall["openings"]:
			var width := float(opening["w"])
			match String(opening["kind"]):
				"door":
					width = maxf(width * OPENING_SCALE, MIN_DOOR_WIDTH)
				_:
					width *= OPENING_SCALE
			openings.append(_open(opening["id"], opening["kind"], float(opening["at"]) * factor, width))
		walls.append(_wall(wall["a"] * factor, wall["b"] * factor, wall["ext"], openings))
	out["walls"] = walls
	var furniture: Array = []
	for item: Dictionary in plan["furniture"]:
		var copy: Dictionary = item.duplicate()
		var half := Vector2(item["size"].x, item["size"].z) * 0.5
		copy["pos"] = _hug(item["pos"], half, _room_rect(plan, item["pos"], bounds), factor)
		furniture.append(copy)
	out["furniture"] = furniture
	var cameras: Array = []
	for camera: Dictionary in plan["cameras"]:
		var pos: Vector3 = camera["pos"]
		var flat := _hug(Vector2(pos.x, pos.z), Vector2.ZERO, bounds, factor)
		cameras.append(_cam(Vector3(flat.x, pos.y + CAMERA_LIFT, flat.y), camera["yaw"], camera["pitch"]))
	out["cameras"] = cameras
	if plan.has("dog"):
		var dog: Vector3 = plan["dog"]
		out["dog"] = Vector3(dog.x * factor, dog.y, dog.z * factor)
	for key in ["breaker", "dvr"]:
		if plan.has(key):
			var spec: Dictionary = (plan[key] as Dictionary).duplicate()
			var pos: Vector3 = spec["pos"]
			var flat := Vector2(pos.x, pos.z)
			var rect := bounds if key == "breaker" else _room_rect(plan, flat, bounds)
			flat = _hug(flat, Vector2.ZERO, rect, factor)
			spec["pos"] = Vector3(flat.x, pos.y, flat.y)
			out[key] = spec
	return out


static func _room_rect(plan: Dictionary, point: Vector2, fallback: Rect2) -> Rect2:
	for room: Dictionary in plan["rooms"]:
		var rect: Rect2 = room["rect"]
		if rect.grow(0.05).has_point(point):
			return rect
	return fallback


## Scales [param point] by [param factor], except that on each axis a point within
## [constant HUG_DISTANCE] of an edge of [param rect] keeps its gap to that (scaled) edge.
static func _hug(point: Vector2, half: Vector2, rect: Rect2, factor: float) -> Vector2:
	var out := point * factor
	for axis in 2:
		var low := rect.position[axis]
		var high := rect.end[axis]
		var to_low := point[axis] - half[axis] - low
		var to_high := high - point[axis] - half[axis]
		if to_low < HUG_DISTANCE and to_low <= to_high:
			out[axis] = low * factor + (point[axis] - low)
		elif to_high < HUG_DISTANCE:
			out[axis] = high * factor - (high - point[axis])
	return out


static func _wall(a: Vector2, b: Vector2, exterior: bool, openings: Array = []) -> Dictionary:
	return {"a": a, "b": b, "ext": exterior, "openings": openings}


static func _open(id: String, kind: String, at: float, width: float) -> Dictionary:
	return {"id": id, "kind": kind, "at": at, "w": width}


static func _furn(furniture_name: String, pos: Vector2, size: Vector3, container := false, search := 1.5) -> Dictionary:
	return {"name": furniture_name, "pos": pos, "size": size, "container": container, "search": search}


static func _cam(pos: Vector3, yaw: float, pitch := -35.0) -> Dictionary:
	return {"pos": pos, "yaw": yaw, "pitch": pitch}


## A small one-storey place: no cameras, no alarm.
static func _low() -> Dictionary:
	return {
		"name": "Shotgun house",
		"size": Vector2(10, 8),
		"wall_color": Color(0.62, 0.55, 0.45),
		"roof_color": Color(0.35, 0.28, 0.24),
		"rooms": [
			{"name": "Living room", "rect": Rect2(-5, -1, 6, 5)},
			{"name": "Kitchen", "rect": Rect2(1, -1, 4, 5)},
			{"name": "Bedroom", "rect": Rect2(-5, -4, 6, 3)},
			{"name": "Bathroom", "rect": Rect2(1, -4, 4, 3)},
		],
		"walls": [
			_wall(Vector2(-5, 4), Vector2(5, 4), true, [_open("front_door", "door", 3.0, 1.0), _open("kitchen_window", "window", 8.0, 1.2)]),
			_wall(Vector2(5, 4), Vector2(5, -4), true, [_open("side_door", "door", 3.0, 1.0)]),
			_wall(Vector2(5, -4), Vector2(-5, -4), true, [_open("bathroom_window", "window", 2.0, 0.8), _open("bedroom_window", "window", 7.0, 1.2)]),
			_wall(Vector2(-5, -4), Vector2(-5, 4), true, [_open("bedroom_side_window", "window", 1.5, 1.0), _open("living_window", "window", 5.5, 1.2)]),
			_wall(Vector2(-5, -1), Vector2(5, -1), false, [_open("bedroom_door", "door", 3.0, 0.9), _open("bathroom_door", "door", 8.0, 0.9)]),
			_wall(Vector2(1, -1), Vector2(1, 4), false, [_open("kitchen_arch", "arch", 2.5, 1.3)]),
			_wall(Vector2(1, -4), Vector2(1, -1), false),
		],
		"furniture": [
			_furn("Couch", Vector2(-3.6, 0.3), Vector3(2.2, 0.8, 0.9)),
			_furn("Coffee table", Vector2(-3.6, 1.6), Vector3(1.2, 0.45, 0.6)),
			_furn("TV stand", Vector2(-4.5, 2.8), Vector3(0.5, 0.6, 1.4)),
			_furn("Kitchen counter", Vector2(4.5, 2.6), Vector3(0.7, 0.9, 2.5)),
			_furn("Kitchen drawers", Vector2(2.2, -0.6), Vector3(1.4, 0.9, 0.6), true),
			_furn("Bed", Vector2(-2.0, -2.9), Vector3(2.0, 0.5, 1.6)),
			_furn("Dresser", Vector2(-4.5, -2.5), Vector3(0.6, 1.0, 1.2), true),
			_furn("Bathroom sink", Vector2(4.5, -3.0), Vector3(0.6, 0.85, 0.8)),
		],
		"cameras": [],
		"alarmed": [],
		"owners": ["Living room", "Bedroom"],
		"armed_owner": false,
	}


## A family home: one camera over the front door and an alarm on it.
static func _medium() -> Dictionary:
	return {
		"name": "Suburban house",
		"size": Vector2(14, 10),
		"wall_color": Color(0.82, 0.8, 0.72),
		"roof_color": Color(0.3, 0.32, 0.38),
		"rooms": [
			{"name": "Living room", "rect": Rect2(-7, 0, 8, 5)},
			{"name": "Kitchen", "rect": Rect2(1, 0, 6, 5)},
			{"name": "Kid's bedroom", "rect": Rect2(-7, -5, 5, 5)},
			{"name": "Bathroom", "rect": Rect2(-2, -5, 3, 5)},
			{"name": "Master bedroom", "rect": Rect2(1, -5, 6, 5)},
		],
		"walls": [
			_wall(Vector2(-7, 5), Vector2(7, 5), true, [_open("living_window", "window", 1.2, 1.4), _open("front_door", "door", 4.0, 1.1), _open("kitchen_window", "window", 11.0, 1.4)]),
			_wall(Vector2(7, 5), Vector2(7, -5), true, [_open("kitchen_side_window", "window", 2.5, 1.2), _open("master_side_window", "window", 7.5, 1.2)]),
			_wall(Vector2(7, -5), Vector2(-7, -5), true, [_open("master_window", "window", 3.0, 1.4), _open("bathroom_window", "window", 7.5, 0.7), _open("kids_window", "window", 11.5, 1.2)]),
			_wall(Vector2(-7, -5), Vector2(-7, 5), true, [_open("kids_side_window", "window", 2.5, 1.0), _open("side_door", "door", 7.5, 1.0)]),
			_wall(Vector2(-7, 0), Vector2(7, 0), false, [_open("kids_door", "door", 2.5, 0.9), _open("bathroom_door", "door", 6.5, 0.9), _open("master_door", "door", 11.0, 0.9)]),
			_wall(Vector2(1, 0), Vector2(1, 5), false, [_open("kitchen_arch", "arch", 2.5, 1.6)]),
			_wall(Vector2(-2, -5), Vector2(-2, 0), false),
			_wall(Vector2(1, -5), Vector2(1, 0), false),
		],
		"furniture": [
			_furn("Sofa", Vector2(-2.6, 1.5), Vector3(2.6, 0.8, 0.9)),
			_furn("Coffee table", Vector2(-2.6, 2.6), Vector3(1.4, 0.45, 0.7)),
			_furn("TV cabinet", Vector2(-6.5, 4.0), Vector3(0.6, 0.6, 1.8), true),
			_furn("Bookshelf", Vector2(-1.0, 4.6), Vector3(1.6, 1.4, 0.4)),
			_furn("Kitchen island", Vector2(4.0, 2.5), Vector3(2.0, 0.9, 1.0)),
			_furn("Kitchen counter", Vector2(6.5, 2.5), Vector3(0.6, 0.9, 3.0), true),
			_furn("Bunk bed", Vector2(-5.5, -3.8), Vector3(2.0, 1.2, 1.0)),
			_furn("Toy chest", Vector2(-3.0, -1.0), Vector3(1.0, 0.6, 0.6), true),
			_furn("Bathroom cabinet", Vector2(0.4, -4.4), Vector3(0.8, 0.9, 0.6), true),
			_furn("Double bed", Vector2(4.5, -3.2), Vector3(2.0, 0.55, 2.2)),
			_furn("Nightstand", Vector2(2.9, -4.2), Vector3(0.6, 0.6, 0.5), true),
			_furn("Desk", Vector2(6.3, -1.0), Vector3(0.8, 0.75, 1.6), true),
			_furn("Closet safe", Vector2(6.5, -4.5), Vector3(0.6, 0.7, 0.5), true, 4.0),
		],
		"cameras": [_cam(Vector3(-2.2, 2.6, 5.3), 15.0, -40.0)],
		"alarmed": ["front_door"],
		"owners": ["Living room", "Kitchen", "Master bedroom"],
		"armed_owner": false,
		"dog": Vector3(2.0, 0.1, -8.5),
		"breaker": {"pos": Vector3(-7.22, 1.3, -4.0), "yaw": 90.0},
		"dvr": {"pos": Vector3(6.3, 0.81, -0.6), "size": Vector3(0.45, 0.12, 0.32)},
		"safe_lock": {"hits": 3, "speed": 0.45},
	}


## A big detached house: cameras all over, most entries alarmed - but the master bedroom's side
## window isn't wired and no camera covers the west side.
static func _high() -> Dictionary:
	return {
		"name": "Villa",
		"size": Vector2(20, 14),
		"wall_color": Color(0.93, 0.91, 0.86),
		"roof_color": Color(0.22, 0.22, 0.24),
		"rooms": [
			{"name": "Living room", "rect": Rect2(-10, 1, 8, 6)},
			{"name": "Foyer", "rect": Rect2(-2, 1, 4, 6)},
			{"name": "Kitchen", "rect": Rect2(2, 1, 8, 6)},
			{"name": "Master bedroom", "rect": Rect2(-10, -7, 7, 8)},
			{"name": "Study", "rect": Rect2(-3, -7, 6, 8)},
			{"name": "Bathroom", "rect": Rect2(3, -2, 7, 3)},
			{"name": "Guest bedroom", "rect": Rect2(3, -7, 7, 5)},
		],
		"walls": [
			_wall(Vector2(-10, 7), Vector2(10, 7), true, [_open("living_window", "window", 3.0, 1.6), _open("living_window_2", "window", 6.0, 1.2), _open("front_door", "door", 10.0, 1.4), _open("kitchen_window", "window", 15.0, 1.6), _open("kitchen_window_2", "window", 18.0, 1.2)]),
			_wall(Vector2(10, 7), Vector2(10, -7), true, [_open("kitchen_side_window", "window", 3.0, 1.2), _open("bathroom_window", "window", 7.5, 0.8), _open("guest_window", "window", 11.5, 1.2)]),
			_wall(Vector2(10, -7), Vector2(-10, -7), true, [_open("guest_back_window", "window", 3.5, 1.2), _open("patio_door", "door", 10.0, 1.6), _open("master_window", "window", 16.5, 1.6)]),
			_wall(Vector2(-10, -7), Vector2(-10, 7), true, [_open("master_side_window", "window", 4.0, 1.2), _open("living_side_window", "window", 11.0, 1.2)]),
			_wall(Vector2(-10, 1), Vector2(10, 1), false, [_open("master_door", "door", 4.0, 1.0), _open("study_door", "door", 10.0, 1.2), _open("bathroom_door", "door", 16.0, 0.9)]),
			_wall(Vector2(-2, 1), Vector2(-2, 7), false, [_open("living_arch", "arch", 3.0, 1.8)]),
			_wall(Vector2(2, 1), Vector2(2, 7), false, [_open("kitchen_arch", "arch", 3.0, 1.8)]),
			_wall(Vector2(-3, -7), Vector2(-3, 1), false, [_open("master_study_door", "door", 4.0, 0.9)]),
			_wall(Vector2(3, -7), Vector2(3, 1), false, [_open("guest_door", "door", 2.5, 0.9)]),
			_wall(Vector2(3, -2), Vector2(10, -2), false),
		],
		"furniture": [
			_furn("Sectional sofa", Vector2(-4.0, 2.6), Vector3(3.4, 0.8, 1.0)),
			_furn("Glass table", Vector2(-4.0, 4.0), Vector3(1.6, 0.45, 0.9)),
			_furn("Media wall", Vector2(-9.6, 4.0), Vector3(0.5, 0.7, 2.6), true),
			_furn("Sideboard", Vector2(-1.0, 6.6), Vector3(1.4, 0.9, 0.5), true),
			_furn("Kitchen island", Vector2(6.0, 4.0), Vector3(3.0, 0.9, 1.2)),
			_furn("Wine rack", Vector2(9.6, 2.5), Vector3(0.6, 1.6, 1.8), true),
			_furn("King bed", Vector2(-6.5, -4.0), Vector3(2.4, 0.6, 2.4)),
			_furn("Jewellery armoire", Vector2(-9.6, -1.0), Vector3(0.6, 1.5, 1.0), true, 2.0),
			_furn("Walk-in dresser", Vector2(-4.0, -6.5), Vector3(1.6, 1.0, 0.6), true),
			_furn("Executive desk", Vector2(0.0, -3.0), Vector3(2.0, 0.78, 1.0), true),
			_furn("Wall safe", Vector2(-2.6, -6.6), Vector3(0.6, 0.8, 0.5), true, 5.0),
			_furn("Display case", Vector2(2.6, -0.5), Vector3(0.6, 1.1, 1.4)),
			_furn("Vanity", Vector2(9.6, -0.5), Vector3(0.6, 0.9, 1.2), true),
			_furn("Guest bed", Vector2(6.5, -5.0), Vector3(2.0, 0.55, 2.0)),
			_furn("Guest nightstand", Vector2(8.8, -6.5), Vector3(0.6, 0.6, 0.5), true),
		],
		"cameras": [
			_cam(Vector3(0.0, 2.7, 7.3), 0.0, -40.0),
			_cam(Vector3(-9.0, 2.7, 7.3), 30.0, -30.0),
			_cam(Vector3(10.3, 2.7, 7.3), 45.0, -30.0),
			_cam(Vector3(10.3, 2.7, -1.0), 90.0, -30.0),
			_cam(Vector3(10.3, 2.7, -7.3), 135.0, -30.0),
			_cam(Vector3(0.0, 2.7, -7.3), 180.0, -40.0),
			_cam(Vector3(-6.0, 2.7, -7.3), 170.0, -30.0),
			_cam(Vector3(0.0, 2.6, 6.7), 180.0, -30.0),
			_cam(Vector3(0.0, 2.6, -6.7), 0.0, -25.0),
		],
		"alarmed": ["front_door", "patio_door", "living_window", "living_window_2", "kitchen_window", "kitchen_window_2", "kitchen_side_window", "bathroom_window", "guest_window", "guest_back_window", "master_window", "living_side_window"],
		"owners": ["Living room", "Kitchen", "Study", "Master bedroom"],
		"armed_owner": true,
		"dog": Vector3(5.0, 0.1, -10.5),
		"breaker": {"pos": Vector3(-10.22, 1.3, -5.5), "yaw": 90.0},
		"dvr": {"pos": Vector3(2.4, 0.4, -6.5), "size": Vector3(0.5, 0.8, 0.4)},
		"safe_lock": {"hits": 4, "speed": 0.6},
	}
