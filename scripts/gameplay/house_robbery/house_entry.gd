class_name HouseEntry
extends Node3D
## A door, window or open archway in a [House] wall. Placed at the opening's centre (floor level) with
## the wall's rotation: local X runs along the wall, local Z through it.
##
## Exterior doors start locked: pick the lock (quiet, slow) or kick it in (loud, fast). Windows are
## pried open (quiet) or smashed (loud), then climbed through. From inside, doors unlock and windows
## open freely - but an alarmed entry trips the alarm whichever way it's opened.

enum Kind { DOOR, WINDOW, ARCH }

const DOOR_HEIGHT := 2.4
const SILL := 0.9
const WINDOW_TOP := 2.3

var entry_id := ""
var kind := Kind.DOOR
var exterior := false
var alarmed := false
var width := 1.0
var locked := false
var is_open := false
var broken := false
var house: Node3D
## House-local direction pointing out of the house (exterior entries only).
var outward := Vector3.FORWARD

var interactable: Interactable
var _hinge: Node3D
var _panel: StaticBody3D
var _glass_material: StandardMaterial3D
var _marker: Label3D


static func create(id: String, entry_kind: Kind, entry_width: float, is_exterior: bool, is_alarmed: bool) -> HouseEntry:
	var entry := HouseEntry.new()
	entry.entry_id = id
	entry.name = id.to_pascal_case()
	entry.kind = entry_kind
	entry.width = entry_width
	entry.exterior = is_exterior
	entry.alarmed = is_alarmed
	entry.locked = is_exterior and entry_kind == Kind.DOOR
	entry.is_open = entry_kind == Kind.ARCH
	return entry


func _ready() -> void:
	add_to_group("house_entries")
	match kind:
		Kind.DOOR:
			_build_door()
		Kind.WINDOW:
			_build_window()
		Kind.ARCH:
			return
	_build_interactable()
	_marker = Label3D.new()
	_marker.text = "ALARM"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.fixed_size = true
	_marker.pixel_size = 0.0015
	_marker.font_size = 24
	_marker.outline_size = 6
	_marker.modulate = Color(1.0, 0.8, 0.2)
	_marker.position.y = WINDOW_TOP + 0.3
	_marker.visible = false
	add_child(_marker)


func label() -> String:
	var noun := "door" if kind == Kind.DOOR else "window"
	return entry_id.replace("_", " ").capitalize() if entry_id != "" else noun.capitalize()


func is_window() -> bool:
	return kind == Kind.WINDOW


func is_door() -> bool:
	return kind == Kind.DOOR


func set_marker_visible(show: bool) -> void:
	if _marker != null:
		_marker.visible = show and alarmed


## True when [param actor] is on the inside of the house.
func actor_inside(actor: Node) -> bool:
	return house != null and actor is Node3D and bool(house.call("contains_point", (actor as Node3D).global_position))


# --- conditions -------------------------------------------------------------------------------

func can_breach_door(actor: Node) -> bool:
	return kind == Kind.DOOR and locked and not actor_inside(actor)


func can_unlock(actor: Node) -> bool:
	return kind == Kind.DOOR and locked and actor_inside(actor)


func can_open_door() -> bool:
	return kind == Kind.DOOR and not locked and not is_open


func can_close_door() -> bool:
	return kind == Kind.DOOR and is_open and not broken


func can_pry(actor: Node) -> bool:
	return kind == Kind.WINDOW and not is_open and not actor_inside(actor)


func can_open_window(actor: Node) -> bool:
	return kind == Kind.WINDOW and not is_open and actor_inside(actor)


func can_smash() -> bool:
	return kind == Kind.WINDOW and not is_open


func can_climb() -> bool:
	return kind == Kind.WINDOW and is_open


# --- effects ----------------------------------------------------------------------------------

func pick_lock(actor: Node) -> void:
	locked = false
	_set_open(true)
	EventBus.notify.emit("Lock picked")
	_breached(actor, false)


func kick_in(actor: Node) -> void:
	locked = false
	broken = true
	_set_open(true)
	EventBus.notify.emit("*CRASH* Door kicked in")
	_breached(actor, true)


func unlock_from_inside(actor: Node) -> void:
	locked = false
	_set_open(true)
	_breached(actor, false)


func open_door(_actor: Node) -> void:
	_set_open(true)
	if exterior:
		_breached(_actor, false)


func close_door() -> void:
	_set_open(false)


func pry_open(actor: Node) -> void:
	_set_open(true)
	EventBus.notify.emit("Window pried open")
	_breached(actor, false)


func open_window(actor: Node) -> void:
	_set_open(true)
	_breached(actor, false)


func smash(actor: Node) -> void:
	broken = true
	_set_open(true)
	EventBus.notify.emit("*SMASH*")
	_breached(actor, true)


## Climbs through an open window to the other side.
func climb_through(actor: Node) -> void:
	if not (actor is Node3D) or not exterior:
		return
	var body := actor as Node3D
	var side := 1.0 if actor_inside(actor) else -1.0
	var out_world := (house.global_basis * outward).normalized() if house != null else outward
	var target := global_position + out_world * side * 0.9
	target.y = global_position.y + 0.05
	body.global_position = target
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO


func _breached(actor: Node, loud: bool) -> void:
	if house != null and exterior:
		house.call("on_entry_breached", self, actor, loud)


func _set_open(value: bool) -> void:
	is_open = value
	match kind:
		Kind.DOOR:
			_hinge.rotation.y = -PI * 0.5 if value else 0.0
			_hinge.position.z = 0.0
		Kind.WINDOW:
			_panel.visible = not value
			(_panel.get_child(0) as CollisionShape3D).disabled = value


# --- building ---------------------------------------------------------------------------------

func _build_door() -> void:
	_hinge = Node3D.new()
	_hinge.position.x = -width * 0.5
	add_child(_hinge)
	_panel = StaticBody3D.new()
	_panel.collision_layer = 1
	_panel.position = Vector3(width * 0.5, DOOR_HEIGHT * 0.5, 0.0)
	var size := Vector3(width - 0.04, DOOR_HEIGHT - 0.02, 0.07)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_panel.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.24, 0.14) if exterior else Color(0.75, 0.68, 0.58)
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	_panel.add_child(visual)
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.05
	knob_mesh.height = 0.1
	var knob_material := StandardMaterial3D.new()
	knob_material.albedo_color = Color(0.8, 0.7, 0.3)
	knob_material.metallic = 0.8
	knob_mesh.material = knob_material
	for z in [0.06, -0.06]:
		var knob := MeshInstance3D.new()
		knob.mesh = knob_mesh
		knob.position = Vector3(width * 0.5 - 0.12, 0.0, z)
		_panel.add_child(knob)
	_hinge.add_child(_panel)
	_set_open(is_open)


func _build_window() -> void:
	_panel = StaticBody3D.new()
	_panel.collision_layer = 1
	var height := WINDOW_TOP - SILL
	_panel.position.y = SILL + height * 0.5
	var size := Vector3(width, height, 0.04)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_panel.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	_glass_material = StandardMaterial3D.new()
	_glass_material.albedo_color = Color(0.55, 0.75, 0.9, 0.35)
	_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_material.metallic = 0.3
	_glass_material.roughness = 0.1
	mesh.material = _glass_material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	_panel.add_child(visual)
	add_child(_panel)


func _build_interactable() -> void:
	interactable = Interactable.new()
	interactable.radius = 1.3 if kind == Kind.DOOR else 1.2
	interactable.position.y = 1.0 if kind == Kind.DOOR else SILL + 0.3
	interactable.focus_priority = 1
	if kind == Kind.DOOR:
		_add(&"pick", "Pick the lock", &"pick_lock", &"can_breach_door", true, 3.0, "Picking the lock...")
		_add(&"kick", "Kick the door in (loud)", &"kick_in", &"can_breach_door", true, 0.6, "Kicking...")
		_add(&"unlock", "Unlock the door", &"unlock_from_inside", &"can_unlock", true)
		_add(&"open", "Open the door", &"open_door", &"can_open_door", false)
		_add(&"close", "Close the door", &"close_door", &"can_close_door", false, 0.0, "", false)
	else:
		_add(&"climb", "Climb through", &"climb_through", &"can_climb", false, 0.5, "Climbing...")
		_add(&"pry", "Pry the window open", &"pry_open", &"can_pry", true, 2.0, "Prying the window...")
		_add(&"open", "Open the window", &"open_window", &"can_open_window", true)
		_add(&"smash", "Smash the window (loud)", &"smash", &"can_smash", false, 0.3, "Smashing...")
	add_child(interactable)


func _add(id: StringName, verb: String, method: StringName, condition_method: StringName, condition_takes_actor: bool, duration := 0.0, progress := "", effect_takes_actor := true) -> void:
	var effect := MethodEffect.create(method)
	effect.pass_actor = effect_takes_actor
	var condition := MethodCondition.create(condition_method)
	condition.pass_actor = condition_takes_actor
	condition.hide_when_unmet = true
	var action := InteractionAction.create(id, verb, [effect], [condition])
	action.duration = duration
	action.progress_text = progress
	interactable.add_action(action)
