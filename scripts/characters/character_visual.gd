class_name CharacterVisual
extends Node3D
## Animated humanoid body (Quaternius CC0 models, see assets/characters/quaternius/CREDITS.md) used by
## the player and NPCs in place of greybox capsules. Purely visual: owners keep their own collision and
## drive it with update_motion(), set_aiming(), set_aim_pitch(), fire(), hit() and die().
## The model is normalised so the reference man is [constant HEIGHT] m tall (see docs/design/SCALE.md),
## stands on this node's origin and faces -Z like the rest of the game.

const MODEL_PATH := "res://assets/characters/quaternius/%s.glb"
## Only this model imports its clips; every model shares its 62-bone rig, so the library is reused.
const ANIMATION_SOURCE := &"hoodie"
const HEIGHT := 1.8
const SKELETON_PATH := ^"RootNode/CharacterArmature/Skeleton3D"
## Models per archetype; an instance picks one with its variant seed.
const ARCHETYPES := {
	&"player": [&"hoodie"],
	&"gang": [&"punk", &"punk_red", &"casual", &"hoodie"],
	&"crew": [&"casual", &"hoodie", &"punk"],
	&"cop": [&"swat"],
	&"civilian": [&"suit", &"worker", &"woman_formal", &"woman_casual", &"beach", &"farmer"],
}
## Clothing materials recoloured by set_tint(); models not listed keep their own colours.
const TINT_MATERIALS := {
	&"hoodie": [&"Purple"],
	&"punk": [&"Pink"],
	&"punk_red": [&"White"],
	&"casual": [&"LightBrown"],
	&"swat": [&"Swat"],
}
const LOOPING_CLIPS: Array[StringName] = [&"Idle", &"Idle_Neutral", &"Idle_Gun", &"Idle_Gun_Pointing", &"Idle_Sword",
	&"Walk", &"Run", &"Run_Back", &"Run_Left", &"Run_Right", &"Run_Shoot"]
## Ground speeds (m/s) the Walk / Run / strafe clips look right at; faster movement speeds them up.
const WALK_SPEED := 1.6
const RUN_SPEED := 5.0
const STRAFE_SPEED := 4.0
const MAX_TIME_SCALE := 1.6
## Greybox weapon sizes (m, length along the barrel).
const WEAPON_SIZES := {
	&"pistol": Vector3(0.05, 0.13, 0.24),
	&"smg": Vector3(0.06, 0.16, 0.42),
	&"shotgun": Vector3(0.07, 0.12, 0.95),
	&"rifle": Vector3(0.07, 0.14, 0.9),
	&"rpg": Vector3(0.14, 0.14, 1.1),
	&"grenade": Vector3(0.09, 0.11, 0.09),
	&"molotov": Vector3(0.08, 0.08, 0.26),
	&"c4": Vector3(0.12, 0.06, 0.18),
}

static var _library: AnimationLibrary
static var _model_scale := 0.0

@export var archetype: StringName = &"civilian"
## Picks the model within the archetype; -1 picks randomly.
@export var variant := -1

var model_id: StringName
var skeleton: Skeleton3D
var animation_tree: AnimationTree
var weapon: WeaponData

var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _aim_modifier: AimPitchModifier
var _weapon_mesh: MeshInstance3D
var _bandana: MeshInstance3D
var _flash_material: StandardMaterial3D
var _hand_bone := -1
var _head_bone := -1
var _aiming := false
var _aim_weight := 0.0
var _aim_pitch := 0.0
var _local_velocity := Vector2.ZERO
var _dead := false


## Builds a visual in code (scenes can instead add the node with [member archetype] set).
static func create(kind: StringName, seed_value: int = -1) -> CharacterVisual:
	var visual := CharacterVisual.new()
	visual.name = "Visual"
	visual.archetype = kind
	visual.variant = seed_value
	visual._build()
	return visual


func _ready() -> void:
	if _model == null:
		_build()


func _exit_tree() -> void:
	_set_overlay(null)


func _process(delta: float) -> void:
	if animation_tree == null:
		return
	_aim_weight = move_toward(_aim_weight, 1.0 if _aiming and not _dead else 0.0, delta * 6.0)
	var speed := _local_velocity.length()
	animation_tree.set(&"parameters/free/blend_position", minf(speed, RUN_SPEED))
	animation_tree.set(&"parameters/free_speed/scale", clampf(speed / RUN_SPEED, 1.0, MAX_TIME_SCALE))
	var strafe := _local_velocity / STRAFE_SPEED
	animation_tree.set(&"parameters/aim/blend_position", strafe.limit_length(1.0))
	animation_tree.set(&"parameters/aim_speed/scale", clampf(strafe.length(), 1.0, MAX_TIME_SCALE))
	animation_tree.set(&"parameters/loco/blend_amount", _aim_weight)
	animation_tree.set(&"parameters/aim_upper/blend_amount", _aim_weight)
	animation_tree.set(&"parameters/armed/blend_amount", (1.0 - _aim_weight) if is_armed() else 0.0)
	_aim_modifier.pitch = _aim_pitch * _aim_weight


## Feeds world-space velocity; the clip blend and playback speed follow it.
func update_motion(world_velocity: Vector3, delta: float = 1.0 / 60.0) -> void:
	var local := global_basis.inverse() * world_velocity
	var target := Vector2(local.x, -local.z) if not _dead else Vector2.ZERO
	_local_velocity = _local_velocity.lerp(target, clampf(delta * 12.0, 0.0, 1.0))


func set_aiming(aiming: bool) -> void:
	_aiming = aiming


func is_aiming() -> bool:
	return _aiming


## Aim pitch in radians (positive looks up); applied to the chest while aiming.
func set_aim_pitch(radians: float) -> void:
	_aim_pitch = clampf(radians, -1.0, 1.0)


func set_weapon(data: WeaponData) -> void:
	weapon = data
	var size: Vector3 = WEAPON_SIZES.get(data.id, Vector3(0.06, 0.12, 0.3)) if data != null and not data.is_melee() else Vector3.ZERO
	_weapon_mesh.visible = size != Vector3.ZERO and not _dead
	if _weapon_mesh.visible:
		(_weapon_mesh.mesh as BoxMesh).size = size


## A firearm or throwable is in hand (uses the gun-holding poses).
func is_armed() -> bool:
	return weapon != null and not weapon.is_melee()


## Plays the shoot (or punch, for melee) one-shot over the upper body.
func fire() -> void:
	if _dead:
		return
	var shot := &"punch" if weapon != null and weapon.is_melee() else &"shoot"
	animation_tree.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Hit reaction plus a short red flash.
func hit() -> void:
	if _dead:
		return
	animation_tree.set(&"parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_set_overlay(_flash_material)
	if is_inside_tree():
		get_tree().create_timer(0.1, false).timeout.connect(_set_overlay.bind(null))


func die() -> void:
	_dead = true
	_aiming = false
	_set_overlay(null)
	_local_velocity = Vector2.ZERO
	_weapon_mesh.visible = false
	animation_tree.set(&"parameters/life/transition_request", "dead")


func revive() -> void:
	_dead = false
	set_weapon(weapon)
	animation_tree.set(&"parameters/life/transition_request", "alive")


func is_dead() -> bool:
	return _dead


## Recolours the model's clothing (see TINT_MATERIALS).
func set_tint(color: Color) -> void:
	var names: Array = TINT_MATERIALS.get(model_id, [])
	for mesh in _meshes:
		for i in mesh.mesh.get_surface_count():
			var base := mesh.mesh.surface_get_material(i)
			if base != null and StringName(base.resource_name) in names:
				var tinted := base.duplicate() as BaseMaterial3D
				tinted.albedo_color = color
				mesh.set_surface_override_material(i, tinted)


## Coloured band around the head (gang colours); null colour removes it.
func set_bandana(color: Variant) -> void:
	_bandana.visible = color != null
	if color != null:
		((_bandana.mesh as BoxMesh).material as StandardMaterial3D).albedo_color = color


## World position of the right hand (where weapons are held).
func hand_position() -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_hand_bone).origin


## World-space height of the head bone above this node.
func head_height() -> float:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(_head_bone).origin).y - global_position.y


func _build() -> void:
	var models: Array = ARCHETYPES.get(archetype, ARCHETYPES[&"civilian"])
	var index := variant if variant >= 0 else randi()
	model_id = models[index % models.size()]
	_model = (load(MODEL_PATH % model_id) as PackedScene).instantiate() as Node3D
	_model.name = "Model"
	for stray in _model.find_children("*", "AnimationPlayer", true, false):
		stray.free()
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * _shared_scale()
	add_child(_model)
	skeleton = _model.get_node(SKELETON_PATH) as Skeleton3D
	for mesh in skeleton.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mesh)
	_hand_bone = skeleton.find_bone("Wrist.R")
	_head_bone = skeleton.find_bone("Head")

	_aim_modifier = AimPitchModifier.new()
	_aim_modifier.name = "AimPitch"
	_aim_modifier.facing = self
	skeleton.add_child(_aim_modifier)
	skeleton.skeleton_updated.connect(_on_skeleton_updated)

	_weapon_mesh = _box("Weapon", Vector3(0.06, 0.12, 0.3), Color(0.12, 0.12, 0.13))
	_weapon_mesh.visible = false
	_bandana = _box("Bandana", Vector3(0.33, 0.08, 0.34), Color.WHITE)
	_bandana.visible = false
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1.0, 0.25, 0.2, 0.55)
	_build_tree()


func _box(node_name: String, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.top_level = true
	add_child(instance)
	return instance


## Places the held weapon and bandana once the animated (and aim-bent) pose is final.
func _on_skeleton_updated() -> void:
	if not is_inside_tree():
		return
	if _weapon_mesh.visible:
		var forward := -global_basis.z.normalized()
		var pitch := _aim_pitch * _aim_weight + (1.0 - _aim_weight) * -0.7
		var direction := Basis(global_basis.x.normalized(), pitch) * forward
		var length := (_weapon_mesh.mesh as BoxMesh).size.z
		var grip := hand_position() + direction * length * 0.3
		_weapon_mesh.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP), grip)
	if _bandana.visible:
		var head := skeleton.global_transform * skeleton.get_bone_global_pose(_head_bone)
		var basis := head.basis.orthonormalized()
		_bandana.global_transform = Transform3D(basis, head.origin + basis.y * 0.12 * _shared_scale())


func _set_overlay(material: Material) -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = material


func _build_tree() -> void:
	var upper_body := _upper_body_paths()
	var root := AnimationNodeBlendTree.new()

	var free_loco := AnimationNodeBlendSpace1D.new()
	free_loco.min_space = 0.0
	free_loco.max_space = RUN_SPEED
	free_loco.add_blend_point(_clip(&"Idle"), 0.0, -1, &"Idle")
	free_loco.add_blend_point(_clip(&"Walk"), WALK_SPEED, -1, &"Walk")
	free_loco.add_blend_point(_clip(&"Run"), RUN_SPEED, -1, &"Run")
	root.add_node(&"free", free_loco)
	root.add_node(&"free_speed", AnimationNodeTimeScale.new())
	root.connect_node(&"free_speed", 0, &"free")

	var aim := AnimationNodeBlendSpace2D.new()
	aim.add_blend_point(_clip(&"Idle_Gun_Pointing"), Vector2.ZERO, -1, &"Idle_Gun_Pointing")
	aim.add_blend_point(_clip(&"Run_Shoot"), Vector2(0.0, 1.0), -1, &"Run_Shoot")
	aim.add_blend_point(_clip(&"Run_Back"), Vector2(0.0, -1.0), -1, &"Run_Back")
	aim.add_blend_point(_clip(&"Run_Left"), Vector2(-1.0, 0.0), -1, &"Run_Left")
	aim.add_blend_point(_clip(&"Run_Right"), Vector2(1.0, 0.0), -1, &"Run_Right")
	root.add_node(&"aim", aim)
	root.add_node(&"aim_speed", AnimationNodeTimeScale.new())
	root.connect_node(&"aim_speed", 0, &"aim")

	root.add_node(&"loco", AnimationNodeBlend2.new())
	root.connect_node(&"loco", 0, &"free_speed")
	root.connect_node(&"loco", 1, &"aim_speed")

	var previous := &"loco"
	for layer: Array in [[&"armed", &"Idle_Gun", false], [&"aim_upper", &"Idle_Gun_Pointing", false],
			[&"shoot", &"Idle_Gun_Shoot", true], [&"punch", &"Punch_Right", true], [&"hit", &"HitRecieve", true]]:
		var node: AnimationNode
		if layer[2]:
			var one_shot := AnimationNodeOneShot.new()
			one_shot.fadein_time = 0.05
			one_shot.fadeout_time = 0.15
			node = one_shot
		else:
			node = AnimationNodeBlend2.new()
		node.filter_enabled = true
		for path in upper_body:
			node.set_filter_path(path, true)
		var clip_node := StringName("%s_clip" % layer[0])
		root.add_node(layer[0], node)
		root.add_node(clip_node, _clip(layer[1]))
		root.connect_node(layer[0], 0, previous)
		root.connect_node(layer[0], 1, clip_node)
		previous = layer[0]

	var life := AnimationNodeTransition.new()
	life.xfade_time = 0.2
	life.add_input("alive")
	life.add_input("dead")
	root.add_node(&"life", life)
	root.add_node(&"death_clip", _clip(&"Death"))
	root.connect_node(&"life", 0, previous)
	root.connect_node(&"life", 1, &"death_clip")
	root.connect_node(&"output", 0, &"life")

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.add_animation_library(&"", _shared_library())
	animation_tree.tree_root = root
	_model.add_child(animation_tree)
	animation_tree.active = true
	animation_tree.set(&"parameters/life/transition_request", "alive")


func _clip(clip_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


## Track paths of the Abdomen bone and everything above it (spine, head, arms).
func _upper_body_paths() -> Array[NodePath]:
	var paths: Array[NodePath] = []
	var pending: Array[int] = [skeleton.find_bone("Abdomen")]
	while not pending.is_empty():
		var bone: int = pending.pop_back()
		if bone < 0:
			continue
		paths.append(NodePath("%s:%s" % [SKELETON_PATH, skeleton.get_bone_name(bone)]))
		pending.append_array(skeleton.get_bone_children(bone))
	return paths


## Scale that makes the animation-source model [constant HEIGHT] tall; shared so relative heights stay.
static func _shared_scale() -> float:
	if _model_scale <= 0.0:
		var source := (load(MODEL_PATH % ANIMATION_SOURCE) as PackedScene).instantiate() as Node3D
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
			var box := _transform_to(mesh, source) * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		source.free()
		_model_scale = HEIGHT / bounds.size.y
	return _model_scale


static func _transform_to(node: Node3D, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != root and current is Node3D:
		result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


## Clips from the animation-source model, renamed without the "CharacterArmature|" prefix.
static func _shared_library() -> AnimationLibrary:
	if _library == null:
		_library = AnimationLibrary.new()
		var source := (load(MODEL_PATH % ANIMATION_SOURCE) as PackedScene).instantiate()
		var player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for clip_name in player.get_animation_list():
			var clip := player.get_animation(clip_name).duplicate(true) as Animation
			var short := StringName(String(clip_name).get_slice("|", 1) if "|" in clip_name else clip_name)
			clip.loop_mode = Animation.LOOP_LINEAR if short in LOOPING_CLIPS else Animation.LOOP_NONE
			_library.add_animation(short, clip)
		source.free()
	return _library
