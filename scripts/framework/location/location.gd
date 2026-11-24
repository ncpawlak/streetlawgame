class_name Location
extends Node3D
## A placed building/place in the world (runtime instance of a LocationDef). Origin = the door on the
## street, local +Z points out to the street. State lives in [member state] (owned by Locations), so the
## node and its streamed interior can be freed and rebuilt without losing anything.

const OPEN := &"open"
const ROBBED := &"robbed"
const CLOSED := &"closed"
const TAKEN_OUT := &"taken_out"
const OWNED := &"owned"
const TALK_ACTION := &"talk"
const MARKER_HEIGHT := 81.0

var def: LocationDef
var state: LocationState
var instance_id: StringName
var district_id: StringName:
	get:
		return state.district_id if state != null else &""
var door: Interactable
## Root of the streamed interior while loaded (see InteriorStrategy).
var interior_root: Node3D
## Friendly occupants currently spawned (door-only ones are bodiless).
var occupants: Array[Occupant] = []

var _hostiles: Array[GangMember] = []
var _action_occupants := {}
var _marker: MeshInstance3D


static func create(location_def: LocationDef, at: Transform3D, id: StringName) -> Location:
	var location := Location.new()
	location.def = location_def
	location.instance_id = id
	location.name = "Location_%s" % id
	location.transform = at
	return location


## Talk action for an occupant with a dialogue (shared data/actions/talk.tres).
static func talk_action_for(occupant_def: OccupantDef) -> InteractionAction:
	if occupant_def.dialogue_id == &"":
		return null
	return ContentDB.find_def(InteractionAction.TYPE, TALK_ACTION) as InteractionAction


func _ready() -> void:
	add_to_group("locations")
	if state == null:
		state = Locations.ensure_state(self)
	_build_exterior()
	_build_marker()
	if not def.is_enterable():
		for occupant_def in def.all_occupants():
			if not occupant_def.hostile:
				var occupant := Occupant.create(occupant_def, self, false)
				add_child(occupant)
				occupants.append(occupant)
	_build_door()
	EventBus.gang_member_killed.connect(_on_gang_member_killed)


func label() -> String:
	return def.label()


func kind() -> StringName:
	return def.kind


func status() -> StringName:
	return state.status


func owner_gang() -> StringName:
	return state.owner_gang


func door_position() -> Vector3:
	return global_position


## Where an actor stands when leaving: on the street in front of the door.
func outside_point() -> Vector3:
	return global_position + global_basis.z * 1.8 + Vector3(0.0, 0.2, 0.0)


func is_inside(actor: Node) -> bool:
	return Locations.current == self and actor == GameState.player


func is_enterable() -> bool:
	return def.is_enterable()


func enter(actor: Node3D) -> bool:
	if not def.is_enterable():
		return false
	if Locations.current != null and Locations.current != self:
		Locations.current.exit(actor)
	if not def.interior.enter(self, actor):
		return false
	Locations.current = self
	EventBus.location_entered.emit(self, actor)
	return true


func exit(actor: Node3D) -> void:
	if def.interior == null or interior_root == null:
		return
	_despawn_hostiles()
	occupants = occupants.filter(func(occupant: Occupant) -> bool: return occupant.interactable == null)
	def.interior.exit(self, actor)
	if Locations.current == self:
		Locations.current = null
	EventBus.location_exited.emit(self, actor)


func hostiles_remaining() -> int:
	if interior_root != null:
		return _hostiles.filter(func(member: GangMember) -> bool: return is_instance_valid(member) and member.is_alive()).size()
	return int(state.flags.get("hostiles_left", _hostile_total()))


## Marks the location taken out, applies cleared_effects and notifies everyone. Only happens once.
func take_out(actor: Node = null) -> bool:
	if state.status == TAKEN_OUT:
		return false
	state.flags["hostiles_left"] = 0
	Locations.set_status(self, TAKEN_OUT)
	var ctx := door.make_context(actor if actor != null else GameState.player)
	Effect.apply_all(def.cleared_effects, ctx)
	EventBus.location_taken_out.emit(self, state.owner_gang)
	return true


## Map-layer marker (hidden by default); e.g. #27 reveals plug meets.
func set_marker_visible(shown: bool) -> void:
	if _marker != null:
		_marker.visible = shown


func is_marker_visible() -> bool:
	return _marker != null and _marker.visible


## Called by an InteriorStrategy once its room exists: spawns friendly occupants at [param friendly_spots]
## and the remaining hostiles at [param hostile_spots].
func populate_interior(friendly_spots: Array[Node3D], hostile_spots: Array[Node3D]) -> void:
	var friendly_index := 0
	var hostile_index := 0
	var hostiles_left := int(state.flags.get("hostiles_left", _hostile_total()))
	for occupant_def in def.all_occupants():
		if occupant_def.hostile:
			for i in occupant_def.count:
				if hostiles_left <= 0:
					break
				hostiles_left -= 1
				_spawn_hostile(occupant_def, _spot(hostile_spots, hostile_index))
				hostile_index += 1
		else:
			var occupant := Occupant.create(occupant_def, self, true)
			interior_root.add_child(occupant)
			occupant.global_position = _spot(friendly_spots, friendly_index)
			occupants.append(occupant)
			friendly_index += 1
	state.flags["hostiles_left"] = _hostiles.size()


func _spot(spots: Array[Node3D], index: int) -> Vector3:
	if spots.is_empty():
		return interior_root.global_position + Vector3(0.0, 0.2, 0.0)
	var spot := spots[index % spots.size()].global_position
	# Reusing spots: nudge so bodies don't overlap.
	return spot + Vector3(0.7 * floorf(float(index) / float(spots.size())), 0.0, 0.0)


func _spawn_hostile(occupant_def: OccupantDef, at: Vector3) -> void:
	var member := GangMember.new()
	member.gang_id = occupant_def.resolve_gang(state.owner_gang)
	member.max_health = occupant_def.health
	member.weapon_id = occupant_def.weapon_id
	member.wander_radius = 1.5
	member.drop_chance = 0.0
	interior_root.add_child(member)
	member.global_position = at
	_hostiles.append(member)


func _despawn_hostiles() -> void:
	state.flags["hostiles_left"] = hostiles_remaining()
	_hostiles.clear()


func _hostile_total() -> int:
	var total := 0
	for occupant_def in def.all_occupants():
		if occupant_def.hostile:
			total += occupant_def.count
	return total


func _on_gang_member_killed(member: GangMember, killer: Node) -> void:
	if not _hostiles.has(member):
		return
	_hostiles.erase(member)
	state.flags["hostiles_left"] = hostiles_remaining()
	if hostiles_remaining() == 0 and _hostile_total() > 0:
		EventBus.notify.emit("%s is cleared out" % label())
		take_out(killer if killer == GameState.player else GameState.player)


func _build_exterior() -> void:
	var visual := def.exterior.instantiate() if def.exterior != null else VisualSpec.greybox(&"box", Vector3(1.6, 2.6, 0.25), def.color)
	if def.exterior == null:
		visual.position = Vector3(0.0, 1.3, 0.0)
		var sign_board := VisualSpec.greybox(&"box", Vector3(2.6, 0.6, 0.15), def.color.lightened(0.3))
		sign_board.position = Vector3(0.0, 3.1, 0.1)
		add_child(sign_board)
	add_child(visual)


func _build_marker() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 4.0
	mesh.bottom_radius = 4.0
	mesh.height = 0.5
	mesh.material = VisualSpec.material(def.color)
	_marker = MeshInstance3D.new()
	_marker.name = "MapMarker"
	_marker.mesh = mesh
	_marker.layers = GameState.MAP_LAYER
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)
	_marker.global_position = Vector3(global_position.x, MARKER_HEIGHT, global_position.z)


func _build_door() -> void:
	door = Interactable.new()
	door.name = "Door"
	door.prompt_name = def.label()
	door.radius = 2.2
	door.target = self
	door.location = self
	door.memory = state.memory
	door.position = Vector3(0.0, 1.0, 0.9)
	var list := def.all_door_actions()
	for occupant in occupants:
		for action in occupant.get_actions():
			var per_occupant := action.duplicate() as InteractionAction
			per_occupant.id = StringName("%s_%s" % [action.id, occupant.role()])
			list.append(per_occupant)
			_action_occupants[per_occupant] = occupant
	door.actions = list
	door.context_builder = _fill_context
	add_child(door)


func _fill_context(ctx: ActionContext) -> void:
	if ctx.action != null and _action_occupants.has(ctx.action):
		ctx.occupant = _action_occupants[ctx.action]
	ctx.vars["register"] = int(state.cash)
	ctx.vars["status"] = String(state.status)
