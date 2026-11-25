class_name ActorPlaceStep
extends CutsceneStep
## Instantly positions an actor (teleport to a marker, show/hide, fake pose). Claims the actor so its
## AI / player control is paused for the rest of the scene.

@export var actor: StringName = &"player"
## Node3D whose position and yaw the actor takes; empty = stay put.
@export var marker: StringName
@export var visible := true
## Fake poses for the bundled models (no lie/sit clips): offset and rotate the CharacterVisual,
## e.g. rotation (-90, 0, 0) + offset (0, 0.6, 0) lies the actor on a bed. Undone at the end.
@export var pose_visual := false
@export var visual_offset := Vector3.ZERO
@export var visual_rotation_degrees := Vector3.ZERO


func begin(director: CutsceneDirector, _state: Dictionary) -> void:
	var node := director.resolve_3d(actor)
	if node == null:
		push_warning("ActorPlaceStep: no actor '%s'" % actor)
		return
	director.claim(node)
	var spot := director.resolve_3d(marker)
	if spot != null:
		node.global_position = spot.global_position
		node.global_rotation.y = spot.global_rotation.y
	node.visible = visible
	if pose_visual:
		director.pose_visual(node, visual_offset, visual_rotation_degrees)


func skip(director: CutsceneDirector, state: Dictionary) -> void:
	begin(director, state)


func validate() -> PackedStringArray:
	return PackedStringArray() if actor != &"" else PackedStringArray(["needs an actor"])
