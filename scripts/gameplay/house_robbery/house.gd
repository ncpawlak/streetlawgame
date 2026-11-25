class_name House
extends Node3D
## A burglable house built from a [HouseLayouts] floor plan: rooms, walls with doors and windows
## ([HouseEntry]), furniture, searchable [LootContainer]s, loose [LootItem]s, [SecurityCamera]s scaled
## to the tier, and optionally the [Homeowner]s at home.
##
## Police rules (fed into [member police_call]):
## - Breaking in through an alarmed entry calls the police immediately (ALARM).
## - A camera seeing the burglar break in, or anywhere on the property afterwards, calls them (CAMERA).
## - Breaking into an empty house starts the neighbours' countdown (NEIGHBOURS).
## - Gunshots near the house start the countdown (PoliceCall hears EventBus.gunshot).
## - An owner who sees or hears the burglar phones the police (WITNESS) unless stopped.

signal broken_into(entry: HouseEntry, actor: Node)
signal alarm_tripped(reason: StringName)
signal rebuilt

const WALL_HEIGHT := 2.8
const WALL_THICKNESS := 0.2
## How far around the footprint counts as "on the property" for cameras.
const YARD_MARGIN := 6.0

@export_enum("Low income", "Medium income", "High income") var tier := 0
@export var owners_home := false

var police_call: PoliceCall
var layout: Dictionary = {}
var is_broken_into := false
var entries: Dictionary = {}
var cameras: Array[SecurityCamera] = []
var owners: Array[Homeowner] = []
var containers: Array[LootContainer] = []
var loot_seed := 0
## Show owner / camera / alarm markers through walls (stakeout).
var reveal := false

var _building: Node3D
var _loot_root: Node3D
var _roof: Node3D
var _lights: Node3D
var _surfaces: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _roof_forced_hidden := false


func _ready() -> void:
	add_to_group("houses")
	if layout.is_empty():
		build(tier, owners_home)


func _physics_process(_delta: float) -> void:
	var player := GameState.player as Node3D
	if _roof != null:
		_roof.visible = not _roof_forced_hidden and not (player != null and contains_point(player.global_position))
	if is_broken_into and player != null and police_call != null and not police_call.is_called() and on_property(player.global_position):
		_check_cameras(player)


# --- queries ----------------------------------------------------------------------------------

func size() -> Vector2:
	return layout.get("size", Vector2(10, 8))


func tier_name() -> String:
	return HouseLayouts.TIER_NAMES[tier]


func neighbour_seconds() -> float:
	return HouseLayouts.NEIGHBOUR_SECONDS[tier]


## Inside the footprint (global position).
func contains_point(point: Vector3) -> bool:
	var local := to_local(point)
	var half := size() * 0.5
	return absf(local.x) < half.x and absf(local.z) < half.y and local.y > -1.0 and local.y < WALL_HEIGHT + 1.0


## Inside the footprint or its yard.
func on_property(point: Vector3) -> bool:
	var local := to_local(point)
	var half := size() * 0.5 + Vector2(YARD_MARGIN, YARD_MARGIN)
	return absf(local.x) < half.x and absf(local.z) < half.y


func room_at(point: Vector3) -> String:
	var local := to_local(point)
	for room: Dictionary in layout.get("rooms", []):
		if (room["rect"] as Rect2).has_point(Vector2(local.x, local.z)):
			return room["name"]
	return ""


func front_door() -> HouseEntry:
	return entries.get("front_door") as HouseEntry


func entry(id: String) -> HouseEntry:
	return entries.get(id) as HouseEntry


func alive_owners() -> Array[Homeowner]:
	var result: Array[Homeowner] = []
	for owner_node in owners:
		if is_instance_valid(owner_node) and owner_node.is_alive():
			result.append(owner_node)
	return result


func anyone_home() -> bool:
	return not alive_owners().is_empty()


func alarmed_entries() -> Array[HouseEntry]:
	var result: Array[HouseEntry] = []
	for e: HouseEntry in entries.values():
		if e.alarmed:
			result.append(e)
	return result


func loot_items() -> Array[LootItem]:
	var result: Array[LootItem] = []
	if _loot_root != null:
		for child in _loot_root.get_children():
			if child is LootItem and not child.is_queued_for_deletion():
				result.append(child)
	return result


## Total value still in the house (loose items + unsearched containers).
func loot_value() -> int:
	var total := 0
	for item in loot_items():
		total += item.value
	for container in containers:
		if not container.is_searched:
			total += int(container.contents.get("value", 0))
	return total


## What a stakeout reveals.
func stakeout_report() -> String:
	var lines: PackedStringArray = []
	lines.append("%s - %s" % [layout.get("name", "House"), tier_name()])
	var home := alive_owners().size()
	lines.append("Lights on, %d %s moving inside" % [home, "person" if home == 1 else "people"] if home > 0 else "Lights off, no movement - looks empty")
	lines.append("Cameras: %s" % (str(cameras.size()) if not cameras.is_empty() else "none"))
	var alarmed := alarmed_entries()
	if alarmed.is_empty():
		lines.append("Alarm: none")
	else:
		var names: PackedStringArray = []
		for e in alarmed:
			names.append(e.label().to_lower())
		lines.append("Alarm on: %s" % ", ".join(names))
	lines.append("Neighbours call it in %d s after a break-in" % int(neighbour_seconds()))
	return "\n".join(lines)


func set_reveal(value: bool) -> void:
	reveal = value
	for owner_node in alive_owners():
		owner_node.set_marker_visible(value)
	for camera in cameras:
		camera.set_marker_visible(value)
	for e: HouseEntry in entries.values():
		e.set_marker_visible(value)


func set_roof_hidden(value: bool) -> void:
	_roof_forced_hidden = value
	if _roof != null:
		_roof.visible = not value


# --- police rules -----------------------------------------------------------------------------

## Called by a [HouseEntry] when it's opened from outside / opened at all if exterior.
func on_entry_breached(e: HouseEntry, actor: Node, loud: bool) -> void:
	if police_call != null:
		if e.alarmed:
			police_call.call_now(PoliceCall.REASON_ALARM)
			alarm_tripped.emit(PoliceCall.REASON_ALARM)
		elif actor is Node3D and _check_cameras(actor as Node3D):
			pass
	if loud:
		for owner_node in alive_owners():
			owner_node.hear(e.global_position)
	if is_broken_into:
		return
	is_broken_into = true
	if police_call != null and not anyone_home():
		police_call.start_countdown(PoliceCall.REASON_NEIGHBOURS, neighbour_seconds())
	broken_into.emit(e, actor)


## Trips the alarm if any working camera sees [param target]. Returns true if one did.
func _check_cameras(target: Node3D) -> bool:
	for camera in cameras:
		if camera.can_see(target):
			if police_call != null:
				police_call.call_now(PoliceCall.REASON_CAMERA)
			alarm_tripped.emit(PoliceCall.REASON_CAMERA)
			return true
	return false


# --- building ---------------------------------------------------------------------------------

## (Re)builds the whole house. [param loot_seed_value] < 0 picks a random loot seed.
func build(new_tier: int, home: bool, loot_seed_value := -1) -> void:
	tier = clampi(new_tier, 0, 2)
	owners_home = home
	is_broken_into = false
	entries.clear()
	cameras.clear()
	owners.clear()
	containers.clear()
	_surfaces.clear()
	if _building != null:
		remove_child(_building)
		_building.queue_free()
	layout = HouseLayouts.get_layout(tier)
	_building = Node3D.new()
	_building.name = "Building"
	add_child(_building)
	_build_floor()
	_build_walls()
	_build_furniture()
	_build_roof()
	_build_cameras()
	_lights = Node3D.new()
	_lights.name = "Lights"
	_building.add_child(_lights)
	if home:
		_build_owners()
		_build_lights()
	_loot_root = Node3D.new()
	_loot_root.name = "Loot"
	_building.add_child(_loot_root)
	reroll_loot(loot_seed_value)
	set_reveal(reveal)
	rebuilt.emit()


## Clears and re-scatters all loot (loose items and container contents).
func reroll_loot(loot_seed_value := -1) -> void:
	loot_seed = loot_seed_value if loot_seed_value >= 0 else randi()
	_rng.seed = loot_seed
	for child in _loot_root.get_children():
		_loot_root.remove_child(child)
		child.queue_free()
	for container in containers:
		container.set_contents(HouseLoot.roll_container(tier, container.container_name, _rng))
	var spots := _surfaces.duplicate()
	for i in spots.size():
		var j := _rng.randi_range(i, spots.size() - 1)
		var swap: Dictionary = spots[i]
		spots[i] = spots[j]
		spots[j] = swap
	var count := mini(HouseLoot.loose_count(tier, _rng), spots.size())
	for i in count:
		var spot: Dictionary = spots[i]
		var item := HouseLoot.roll_item(tier, _rng)
		var area: Vector2 = spot["area"]
		var at: Vector3 = spot["pos"] + Vector3(_rng.randf_range(-area.x, area.x), 0.0, _rng.randf_range(-area.y, area.y))
		var loot := LootItem.create(item["name"], item["value"], maxi(1, int(item["slots"])), bool(item["cash"]), at)
		loot.rotation.y = _rng.randf_range(-PI, PI)
		_loot_root.add_child(loot)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _box(parent: Node3D, box_size: Vector3, at: Vector3, color: Color, solid: bool) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = _material(color)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	if not solid:
		visual.position = at
		parent.add_child(visual)
		return visual
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	body.add_child(visual)
	parent.add_child(body)
	return body


func _build_floor() -> void:
	var house_size := size()
	var floors := Node3D.new()
	floors.name = "Floors"
	_building.add_child(floors)
	# Foundation slab the player walks on.
	_box(floors, Vector3(house_size.x + 0.4, 0.2, house_size.y + 0.4), Vector3(0.0, -0.08, 0.0), Color(0.5, 0.5, 0.48), true)
	var palette := [Color(0.55, 0.42, 0.3), Color(0.7, 0.68, 0.62), Color(0.45, 0.5, 0.55), Color(0.62, 0.52, 0.42), Color(0.78, 0.78, 0.8), Color(0.5, 0.4, 0.45), Color(0.6, 0.55, 0.45)]
	var index := 0
	for room: Dictionary in layout["rooms"]:
		var rect: Rect2 = room["rect"]
		var centre := rect.get_center()
		_box(floors, Vector3(rect.size.x - 0.05, 0.02, rect.size.y - 0.05), Vector3(centre.x, 0.03, centre.y), palette[index % palette.size()], false)
		var label := Label3D.new()
		label.text = room["name"]
		label.font_size = 64
		label.pixel_size = 0.006
		label.outline_size = 10
		label.modulate = Color(1, 1, 1, 0.85)
		label.rotation.x = -PI / 2.0
		label.position = Vector3(centre.x, 0.06, centre.y)
		floors.add_child(label)
		index += 1


func _build_walls() -> void:
	var color: Color = layout.get("wall_color", Color(0.8, 0.8, 0.75))
	var alarmed: Array = layout.get("alarmed", [])
	var walls := Node3D.new()
	walls.name = "Walls"
	_building.add_child(walls)
	for wall: Dictionary in layout["walls"]:
		var a: Vector2 = wall["a"]
		var b: Vector2 = wall["b"]
		var exterior: bool = wall["ext"]
		var along := b - a
		var length := along.length()
		var holder := Node3D.new()
		holder.position = Vector3(a.x, 0.0, a.y)
		holder.rotation.y = atan2(-along.y, along.x)
		walls.add_child(holder)
		var wall_color := color if exterior else color.lightened(0.15)
		var openings: Array = (wall["openings"] as Array).duplicate()
		openings.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["at"]) < float(y["at"]))
		var cursor := -WALL_THICKNESS * 0.5 if exterior else 0.0
		for opening: Dictionary in openings:
			var start := float(opening["at"]) - float(opening["w"]) * 0.5
			var end := float(opening["at"]) + float(opening["w"]) * 0.5
			_wall_piece(holder, cursor, start, 0.0, WALL_HEIGHT, wall_color)
			var kind := String(opening["kind"])
			var top := HouseEntry.DOOR_HEIGHT if kind != "window" else HouseEntry.WINDOW_TOP
			if kind == "arch":
				top = HouseEntry.DOOR_HEIGHT + 0.1
			_wall_piece(holder, start, end, top, WALL_HEIGHT, wall_color)
			if kind == "window":
				_wall_piece(holder, start, end, 0.0, HouseEntry.SILL, wall_color)
			cursor = end
			_add_entry(holder, opening, exterior, alarmed.has(opening["id"]))
		_wall_piece(holder, cursor, length + (WALL_THICKNESS * 0.5 if exterior else 0.0), 0.0, WALL_HEIGHT, wall_color)


func _wall_piece(holder: Node3D, from: float, to: float, bottom: float, top: float, color: Color) -> void:
	if to - from < 0.01 or top - bottom < 0.01:
		return
	_box(holder, Vector3(to - from, top - bottom, WALL_THICKNESS), Vector3((from + to) * 0.5, (bottom + top) * 0.5, 0.0), color, true)


func _add_entry(holder: Node3D, opening: Dictionary, exterior: bool, alarmed: bool) -> void:
	var kind := HouseEntry.Kind.DOOR
	match String(opening["kind"]):
		"window":
			kind = HouseEntry.Kind.WINDOW
		"arch":
			kind = HouseEntry.Kind.ARCH
	var e := HouseEntry.create(opening["id"], kind, float(opening["w"]), exterior, alarmed)
	e.house = self
	e.position = Vector3(float(opening["at"]), 0.0, 0.0)
	holder.add_child(e)
	if exterior:
		# The wall's local Z is one of the two normals; pick the one pointing away from the centre.
		var normal := holder.basis.z
		var centre_dir := Vector3(e.position.x, 0, 0)
		var local_pos := holder.position + holder.basis * centre_dir
		e.outward = (normal if normal.dot(local_pos) > 0.0 else -normal).normalized()
	entries[opening["id"]] = e


func _build_furniture() -> void:
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	_building.add_child(furniture)
	for item: Dictionary in layout["furniture"]:
		var pos: Vector2 = item["pos"]
		var furniture_size: Vector3 = item["size"]
		var at := Vector3(pos.x, 0.0, pos.y)
		if bool(item["container"]):
			var container := LootContainer.new()
			container.container_name = item["name"]
			container.size = furniture_size
			container.search_time = float(item.get("search", 1.5))
			container.color = Color(0.25, 0.25, 0.28) if String(item["name"]).to_lower().contains("safe") else Color(0.42, 0.3, 0.2)
			container.position = at
			furniture.add_child(container)
			containers.append(container)
		else:
			_box(furniture, furniture_size, at + Vector3(0.0, furniture_size.y * 0.5, 0.0), Color(0.36, 0.33, 0.38), true)
		# Loose loot can land on top of anything but tall shelving.
		if furniture_size.y <= 1.1:
			_surfaces.append({"pos": at + Vector3(0.0, furniture_size.y, 0.0), "area": Vector2(maxf(0.0, furniture_size.x * 0.5 - 0.25), maxf(0.0, furniture_size.z * 0.5 - 0.2))})
	# And on the floor in the middle of each room.
	for room: Dictionary in layout["rooms"]:
		var rect: Rect2 = room["rect"]
		var centre := rect.get_center()
		_surfaces.append({"pos": Vector3(centre.x + 0.6, 0.02, centre.y - 0.6), "area": Vector2(0.4, 0.4)})


func _build_roof() -> void:
	var house_size := size()
	_roof = Node3D.new()
	_roof.name = "Roof"
	_building.add_child(_roof)
	var roof_color: Color = layout.get("roof_color", Color(0.3, 0.25, 0.22))
	_box(_roof, Vector3(house_size.x + 0.8, 0.25, house_size.y + 0.8), Vector3(0.0, WALL_HEIGHT + 0.12, 0.0), roof_color, false)
	_box(_roof, Vector3(house_size.x * 0.7, 0.8, house_size.y * 0.6), Vector3(0.0, WALL_HEIGHT + 0.6, 0.0), roof_color.darkened(0.15), false)


func _build_cameras() -> void:
	for spec: Dictionary in layout.get("cameras", []):
		var camera := SecurityCamera.new()
		camera.position = spec["pos"]
		camera.yaw = float(spec["yaw"])
		camera.pitch = float(spec["pitch"])
		_building.add_child(camera)
		cameras.append(camera)


func _build_owners() -> void:
	var rooms: Array = layout.get("owners", [])
	var count := 1 + int(tier >= HouseLayouts.Tier.MEDIUM) + int(tier == HouseLayouts.Tier.HIGH and randf() < 0.5)
	var picks := rooms.duplicate()
	picks.shuffle()
	for i in mini(count, picks.size()):
		var room := _room(picks[i])
		var centre: Vector2 = (room["rect"] as Rect2).get_center()
		var owner_node := Homeowner.new()
		owner_node.armed = bool(layout.get("armed_owner", false)) and i == 0
		owner_node.position = Vector3(centre.x, 0.1, centre.y)
		owner_node.house = self
		owner_node.police_call = police_call
		_building.add_child(owner_node)
		owners.append(owner_node)


func _build_lights() -> void:
	for room: Dictionary in layout["rooms"]:
		var centre: Vector2 = (room["rect"] as Rect2).get_center()
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.6)
		light.light_energy = 1.2
		light.omni_range = 5.0
		light.position = Vector3(centre.x, WALL_HEIGHT - 0.3, centre.y)
		_lights.add_child(light)


func _room(room_name: String) -> Dictionary:
	for room: Dictionary in layout["rooms"]:
		if room["name"] == room_name:
			return room
	return layout["rooms"][0]


## Points the house's homeowners (and future ones) at [param call].
func set_police_call(call: PoliceCall) -> void:
	police_call = call
	for owner_node in owners:
		owner_node.police_call = call
