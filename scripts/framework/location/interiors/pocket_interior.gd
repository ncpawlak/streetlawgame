class_name PocketInterior
extends InteriorStrategy
## Streams a separate room on enter and frees it on exit. The room sits in a "pocket" high above the
## location's door (same XZ, so turf and minimap still read the right district) and never overlaps the city.
##
## Uses [member scene_path] when set (resolved via ContentDB.load_asset, so art can be swapped); otherwise
## builds a greybox room. Custom scenes mark points with Marker3D nodes in these groups:
## "interior_entry", "interior_exit", "occupant_spot", "hostile_spot".

const ENTRY_GROUP := &"interior_entry"
const EXIT_GROUP := &"interior_exit"
const OCCUPANT_GROUP := &"occupant_spot"
const HOSTILE_GROUP := &"hostile_spot"

@export_file("*.tscn", "*.scn", "*.glb") var scene_path := ""
## Greybox room size (inside dimensions).
@export var room_size := Vector3(12.0, 4.0, 10.0)
@export var floor_color := Color(0.35, 0.3, 0.28)
@export var wall_color := Color(0.6, 0.55, 0.48)
@export var light_color := Color(1.0, 0.9, 0.75)
## Extra greybox/scene props (positioned by their offset, relative to the room center).
@export var props: Array[VisualSpec] = []
## Actions on the exit door. Empty = a default "Leave" action.
@export var exit_actions: Array[InteractionAction] = []


func is_enterable() -> bool:
	return true


func enter(location: Location, actor: Node3D) -> bool:
	if not is_loaded(location):
		var slot := Locations.allocate_pocket()
		var door := location.door_position()
		var root := _instantiate_room()
		root.name = "Interior"
		root.set_meta(&"pocket_slot", slot)
		location.add_child(root)
		root.global_transform = Transform3D(Basis.IDENTITY, Vector3(door.x, Locations.pocket_height(slot), door.z))
		location.interior_root = root
		_add_exit(location, root)
		location.populate_interior(markers(root, OCCUPANT_GROUP), markers(root, HOSTILE_GROUP))
	var entry := markers(location.interior_root, ENTRY_GROUP)
	var spot: Vector3 = entry[0].global_position if not entry.is_empty() else location.interior_root.global_position + Vector3(0.0, 0.2, 0.0)
	actor.global_position = spot
	if actor is CharacterBody3D:
		(actor as CharacterBody3D).velocity = Vector3.ZERO
	return true


func exit(location: Location, actor: Node3D) -> void:
	super(location, actor)
	var root := location.interior_root
	if root == null:
		return
	location.interior_root = null
	Locations.release_pocket(int(root.get_meta(&"pocket_slot", -1)))
	root.queue_free()


## Marker3D nodes under [param root] in [param group], in tree order.
static func markers(root: Node, group: StringName) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if root == null:
		return found
	for child in root.get_children():
		if child is Node3D and child.is_in_group(group):
			found.append(child)
		found.append_array(markers(child, group))
	return found


func _instantiate_room() -> Node3D:
	if scene_path != "":
		var scene := ContentDB.load_asset(scene_path) as PackedScene
		if scene != null:
			var node := scene.instantiate() as Node3D
			if node != null:
				return node
	return _build_greybox()


func _build_greybox() -> Node3D:
	var root := Node3D.new()
	var half := room_size * 0.5
	var thickness := 0.3
	_add_wall(root, Vector3(room_size.x + thickness * 2.0, thickness, room_size.z + thickness * 2.0), Vector3(0.0, -thickness * 0.5, 0.0), floor_color)
	_add_wall(root, Vector3(room_size.x + thickness * 2.0, thickness, room_size.z + thickness * 2.0), Vector3(0.0, room_size.y + thickness * 0.5, 0.0), wall_color.darkened(0.3))
	_add_wall(root, Vector3(thickness, room_size.y, room_size.z), Vector3(half.x + thickness * 0.5, half.y, 0.0), wall_color)
	_add_wall(root, Vector3(thickness, room_size.y, room_size.z), Vector3(-half.x - thickness * 0.5, half.y, 0.0), wall_color)
	_add_wall(root, Vector3(room_size.x, room_size.y, thickness), Vector3(0.0, half.y, half.z + thickness * 0.5), wall_color)
	_add_wall(root, Vector3(room_size.x, room_size.y, thickness), Vector3(0.0, half.y, -half.z - thickness * 0.5), wall_color)

	var light := OmniLight3D.new()
	light.light_color = light_color
	light.omni_range = room_size.length()
	light.light_energy = 1.5
	light.position = Vector3(0.0, room_size.y - 0.4, 0.0)
	root.add_child(light)

	for prop in props:
		if prop != null:
			root.add_child(prop.instantiate())

	# The entrance is on the +Z wall, the counter/staff at the back (-Z), hostiles spread in between.
	_add_marker(root, ENTRY_GROUP, Vector3(0.0, 0.1, half.z - 1.5))
	_add_marker(root, EXIT_GROUP, Vector3(0.0, 0.0, half.z - 0.4))
	for i in 3:
		_add_marker(root, OCCUPANT_GROUP, Vector3((i - 1) * 2.0, 0.1, -half.z + 1.2))
	for i in 6:
		var column := float(i % 3) - 1.0
		var row := -0.25 if i < 3 else 0.15
		_add_marker(root, HOSTILE_GROUP, Vector3(column * half.x * 0.6, 0.2, row * room_size.z))
	return root


func _add_exit(location: Location, root: Node3D) -> void:
	var exits := markers(root, EXIT_GROUP)
	var interactable := Interactable.new()
	interactable.name = "ExitDoor"
	interactable.prompt_name = "Exit"
	interactable.radius = 1.8
	interactable.location = location
	interactable.memory = location.state.memory
	interactable.target = location
	var list: Array[InteractionAction] = exit_actions.duplicate()
	if list.is_empty():
		var leave: Array[Effect] = [ExitLocationEffect.new()]
		list.append(InteractionAction.create(&"leave", "Leave", leave))
	interactable.actions = list
	root.add_child(interactable)
	interactable.global_position = (exits[0].global_position if not exits.is_empty() else root.global_position) + Vector3(0.0, 1.0, 0.0)
	var door := VisualSpec.greybox(&"box", Vector3(1.4, 2.4, 0.1), location.def.color.darkened(0.2))
	root.add_child(door)
	door.global_position = interactable.global_position + Vector3(0.0, 0.2, 0.35)


func _add_wall(root: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.add_child(VisualSpec.greybox(&"box", size, color))
	root.add_child(body)


func _add_marker(root: Node3D, group: StringName, at: Vector3) -> void:
	var marker := Marker3D.new()
	marker.position = at
	marker.add_to_group(group, true)
	root.add_child(marker)
