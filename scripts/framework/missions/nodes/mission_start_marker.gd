class_name MissionStartMarker
extends Node3D
## Glowing column where a mission starts. Shows "Start <mission>" while Missions.can_start(),
## hides while unavailable (locked, done, or another mission running). Group "mission_starts"
## feeds the map.

const GROUP := &"mission_starts"

@export var mission_id: StringName
@export var color := Color(1.0, 0.75, 0.1)

var interactable: Interactable
var _visual: MeshInstance3D


func _ready() -> void:
	add_to_group(GROUP)
	_visual = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.6
	cylinder.bottom_radius = 0.6
	cylinder.height = 3.0
	_visual.mesh = cylinder
	_visual.position.y = 1.5
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, 0.35)
	_visual.material_override = material
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	interactable = Interactable.new()
	interactable.radius = 2.5
	var mission := Missions.get_mission(mission_id)
	interactable.prompt_name = mission.label() if mission != null else String(mission_id)
	interactable.add_action(InteractionAction.create(&"start_mission", "Start mission"))
	interactable.action_performed.connect(func(_action_id: StringName, _actor: Node, _ctx: ActionContext) -> void: Missions.start_mission(mission_id))
	add_child(interactable)
	Missions.mission_started.connect(func(_id: StringName) -> void: refresh())
	Missions.mission_ended.connect(func(_id: StringName, _run: MissionRun) -> void: refresh())
	Missions.mission_unlocked.connect(func(_id: StringName) -> void: refresh())
	refresh()


func is_available() -> bool:
	return Missions.can_start(mission_id)


func refresh() -> void:
	var available := is_available()
	visible = available
	interactable.enabled = available
