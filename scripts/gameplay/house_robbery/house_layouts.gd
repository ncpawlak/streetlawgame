class_name HouseLayouts
extends RefCounted
## Hand-authored floor plans for the three house tiers. Everything is in house-local metres, with the
## house centred on its origin and the front door facing +Z (the street).
##
## walls: a -> b in XZ with openings {id, kind: door|window|arch, at: distance from a, w: width}
## furniture: {name, pos: Vector2 (centre), size: Vector3, container: bool, search: seconds}
## cameras: {pos: Vector3, yaw: degrees (0 = looking +Z, 90 = +X), pitch: degrees}
## alarmed: opening ids wired to the alarm. owners: rooms the owners hang out in.

enum Tier { LOW, MEDIUM, HIGH }

const TIER_NAMES := ["Low income", "Medium income", "High income"]
## Seconds until the neighbours call the police after a break-in on an empty house.
const NEIGHBOUR_SECONDS := [60.0, 45.0, 35.0]


static func get_layout(tier: int) -> Dictionary:
	match tier:
		Tier.MEDIUM:
			return _medium()
		Tier.HIGH:
			return _high()
	return _low()


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
			_furn("Couch", Vector2(-3.0, 0.0), Vector3(2.2, 0.8, 0.9)),
			_furn("Coffee table", Vector2(-3.0, 1.5), Vector3(1.2, 0.45, 0.6)),
			_furn("TV stand", Vector2(-4.5, 2.8), Vector3(0.5, 0.6, 1.4)),
			_furn("Kitchen counter", Vector2(4.5, 1.5), Vector3(0.7, 0.9, 2.5)),
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
			_furn("Sofa", Vector2(-4.0, 1.0), Vector3(2.6, 0.8, 0.9)),
			_furn("Coffee table", Vector2(-4.0, 2.6), Vector3(1.4, 0.45, 0.7)),
			_furn("TV cabinet", Vector2(-6.5, 3.0), Vector3(0.6, 0.6, 1.8), true),
			_furn("Bookshelf", Vector2(-1.0, 4.6), Vector3(1.6, 1.4, 0.4)),
			_furn("Kitchen island", Vector2(4.0, 2.5), Vector3(2.0, 0.9, 1.0)),
			_furn("Kitchen counter", Vector2(6.5, 2.5), Vector3(0.6, 0.9, 3.0), true),
			_furn("Bunk bed", Vector2(-5.5, -3.8), Vector3(2.0, 1.2, 1.0)),
			_furn("Toy chest", Vector2(-3.0, -1.0), Vector3(1.0, 0.6, 0.6), true),
			_furn("Bathroom cabinet", Vector2(0.4, -4.4), Vector3(0.8, 0.9, 0.6), true),
			_furn("Double bed", Vector2(4.5, -3.2), Vector3(2.0, 0.55, 2.2)),
			_furn("Nightstand", Vector2(2.9, -4.2), Vector3(0.6, 0.6, 0.5), true),
			_furn("Desk", Vector2(6.3, -1.0), Vector3(0.8, 0.75, 1.6), true),
		],
		"cameras": [_cam(Vector3(-2.2, 2.6, 5.3), 15.0, -40.0)],
		"alarmed": ["front_door"],
		"owners": ["Living room", "Kitchen", "Master bedroom"],
		"armed_owner": false,
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
			_furn("Sectional sofa", Vector2(-6.0, 2.2), Vector3(3.4, 0.8, 1.0)),
			_furn("Glass table", Vector2(-6.0, 4.0), Vector3(1.6, 0.45, 0.9)),
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
	}
