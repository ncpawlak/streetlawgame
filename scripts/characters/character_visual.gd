class_name CharacterVisual
extends Node3D
## Animated humanoid body (Quaternius CC0 models, see assets/characters/quaternius/CREDITS.md) used by
## the player and NPCs in place of greybox capsules. Purely visual: owners keep their own collision and
## drive it with update_motion(), set_aiming(), set_aim_pitch(), fire(), hit() and die().
## The model is normalised so the reference man is [constant HEIGHT] m tall (see docs/design/SCALE.md),
## stands on this node's origin and faces -Z like the rest of the game.
## The clip set has no crouch, climb, reload or seated clips, so those (plus recoil, flinches, the left
## hand on the foregrip and draw/holster reaches) are posed procedurally by a [CharacterPoseModifier];
## deaths hand the skeleton to a [Ragdoll].

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
## Pelvis drop (m) and forward lean (rad) when fully crouched.
const CROUCH_DROP := 0.42
const CROUCH_LEAN := 0.35
## Seconds for the right hand to reach the holster and back when drawing or putting a weapon away.
const DRAW_TIME := 0.35
## melee() kinds -> upper-body one-shot (kick is full-body).
const MELEE_SHOTS := {&"punch_l": &"punch_l", &"punch_r": &"punch", &"kick": &"kick", &"whip": &"punch", &"butt": &"slash"}
## Reload hand paths: [progress, left-hand spot]. Spots: pouch / shoulder are on the body, well /
## fore / port / rear are on the gun (see _gun_spot).
const RELOAD_PATHS := {
	WeaponData.ReloadStyle.PISTOL: [[0.0, &"grip"], [0.3, &"pouch"], [0.5, &"pouch"], [0.8, &"well"], [1.0, &"grip"]],
	WeaponData.ReloadStyle.MAGAZINE: [[0.0, &"fore"], [0.15, &"well"], [0.3, &"well"], [0.5, &"pouch"], [0.6, &"pouch"], [0.8, &"well"], [1.0, &"fore"]],
	WeaponData.ReloadStyle.SHELLS: [[0.0, &"fore"], [0.12, &"pouch"], [0.25, &"port"], [0.4, &"pouch"], [0.55, &"port"], [0.7, &"pouch"], [0.85, &"port"], [1.0, &"fore"]],
	WeaponData.ReloadStyle.ROCKET: [[0.0, &"fore"], [0.2, &"shoulder"], [0.45, &"shoulder"], [0.75, &"rear"], [1.0, &"fore"]],
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
var ragdoll: Ragdoll

var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _aim_modifier: AimPitchModifier
var _pose: CharacterPoseModifier
var _weapon_mesh: MeshInstance3D
var _hip_mesh: MeshInstance3D
var _back_mesh: MeshInstance3D
var _bandana: MeshInstance3D
var _flash_material: StandardMaterial3D
var _hand_bone := -1
var _head_bone := -1
var _aiming := false
var _aim_weight := 0.0
var _aim_pitch := 0.0
var _local_velocity := Vector2.ZERO
var _dead := false
var _time := 0.0
## Weapon actually shown in the hand (lags [member weapon] while a draw is playing).
var _in_hand: WeaponData
var _hip_weapon: WeaponData
var _back_weapon: WeaponData
var _carried: Array[WeaponData] = []
var _holstered := false
var _draw_time := -1.0
var _draw_from: WeaponData
var _crouching := false
var _crouch_weight := 0.0
var _sprinting := false
var _sprint_weight := 0.0
var _winded := 0.0
var _shoulder := 1.0
var _shoulder_weight := 1.0
var _reload_style := 0
var _reload_progress := -1.0
var _reload_weight := 0.0
var _seated := 0.0
var _seated_weight := 0.0
var _crawl := 0.0
var _crawl_weight := 0.0
var _airborne := false
var _air_vy := 0.0
var _air_weight := 0.0
## Landing dip (0..1), set from the fall speed when touching down.
var _land := 0.0
var _reach := {&"L": [Vector3.ZERO, 0.0], &"R": [Vector3.ZERO, 0.0]}
var _kick := 0.0
var _flinch := Vector2.ZERO
var _weapon_pitch := 0.0
var _weapon_roll := 0.0
var _punch_left := false


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
	_time += delta
	var alive := not _dead
	_aim_weight = move_toward(_aim_weight, 1.0 if _aiming and alive and _in_hand != null and _reload_progress < 0.0 else 0.0, delta * 6.0)
	_crouch_weight = move_toward(_crouch_weight, 1.0 if _crouching and alive else 0.0, delta * 5.0)
	_sprint_weight = move_toward(_sprint_weight, 1.0 if _sprinting and alive else 0.0, delta * 4.0)
	_shoulder_weight = move_toward(_shoulder_weight, _shoulder, delta * 6.0)
	_seated_weight = move_toward(_seated_weight, _seated, delta * 4.0)
	_crawl_weight = move_toward(_crawl_weight, _crawl, delta * 4.0)
	_reload_weight = move_toward(_reload_weight, 1.0 if _reload_progress >= 0.0 else 0.0, delta * 8.0)
	_air_weight = move_toward(_air_weight, 1.0 if _airborne and alive else 0.0, delta * (8.0 if _airborne else 10.0))
	_land *= exp(-delta * 6.0)
	_kick *= exp(-delta * 12.0)
	_flinch *= exp(-delta * 6.0)
	if _draw_time >= 0.0:
		_draw_time += delta
		if _draw_time >= DRAW_TIME * 0.5 and _draw_from != null:
			_draw_from = null
			_in_hand = _hand_choice()
			_refresh_meshes()
		if _draw_time >= DRAW_TIME:
			_draw_time = -1.0
			_in_hand = _hand_choice()
			_refresh_meshes()

	# No stride in the air: the clips settle to their idle pose and the procedural jump pose takes over.
	var grounded := 1.0 - _air_weight
	var speed := _local_velocity.length()
	animation_tree.set(&"parameters/free/blend_position", minf(speed, RUN_SPEED) * grounded)
	animation_tree.set(&"parameters/free_speed/scale", clampf(speed / RUN_SPEED, 1.0, MAX_TIME_SCALE) if _crouch_weight < 0.5 else 0.8)
	var strafe := _local_velocity / STRAFE_SPEED * grounded
	animation_tree.set(&"parameters/aim/blend_position", strafe.limit_length(1.0))
	animation_tree.set(&"parameters/aim_speed/scale", clampf(strafe.length(), 1.0, MAX_TIME_SCALE))
	animation_tree.set(&"parameters/loco/blend_amount", _aim_weight)
	animation_tree.set(&"parameters/aim_upper/blend_amount", _aim_weight)
	var holding := _in_hand != null and alive
	animation_tree.set(&"parameters/armed/blend_amount", (1.0 - _aim_weight) * (1.0 - _sprint_weight * 0.6) if holding else 0.0)
	_aim_modifier.pitch = _aim_pitch * _aim_weight
	_update_pose()


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


func set_crouching(crouching: bool) -> void:
	_crouching = crouching


func is_crouching() -> bool:
	return _crouching


## 0..1 how far the crouch pose is blended in.
func crouch_amount() -> float:
	return _crouch_weight


func set_sprinting(sprinting: bool) -> void:
	_sprinting = sprinting


## In the air (jump or fall): legs tuck while rising and reach down while falling, free arms go up,
## and the stride stops. Touching down plays a landing dip scaled by the fall speed.
func set_airborne(airborne: bool, vertical_velocity := 0.0) -> void:
	if _airborne and not airborne and _air_weight > 0.3:
		_land = maxf(_land, clampf(-_air_vy / 9.0, 0.2, 0.8))
	_airborne = airborne
	if airborne:
		_air_vy = vertical_velocity


func is_airborne() -> bool:
	return _airborne


## 0..1 how far into the airborne pose the body is.
func air_amount() -> float:
	return _air_weight


## 0..1 landing dip still playing.
func landing_amount() -> float:
	return _land


## 0..1 out-of-breath: hunches and heaves the chest (low stamina).
func set_winded(amount: float) -> void:
	_winded = clampf(amount, 0.0, 1.0)


## Which shoulder the over-the-shoulder aim leans to: 1 right, -1 left.
func set_shoulder(side: float) -> void:
	_shoulder = signf(side) if side != 0.0 else 1.0


## Holstered: the equipped gun goes to the hip or back and the hands are free.
func set_holstered(holstered: bool) -> void:
	if holstered == _holstered:
		return
	_holstered = holstered
	_begin_draw()


func is_holstered() -> bool:
	return _holstered


## Weapons on the character's body (pistols on the hip, long guns slung on the back).
func set_carried(weapons: Array) -> void:
	_carried.clear()
	for data in weapons:
		if data is WeaponData:
			_carried.append(data)
	_refresh_meshes()


## Reload animation for [param style] (WeaponData.ReloadStyle) at [param progress] 0..1; negative
## progress ends it.
func set_reload(style: int, progress: float) -> void:
	_reload_style = style
	_reload_progress = progress


## 0..1 sitting (vehicle seats): pelvis drops and moves back, knees come forward.
func set_seated(amount: float) -> void:
	_seated = clampf(amount, 0.0, 1.0)


## 0..1 on hands and knees (crawling out of an upside-down car).
func set_crawl(amount: float) -> void:
	_crawl = clampf(amount, 0.0, 1.0)


## Reaches a hand (&"L" / &"R") to a world point (ledges, door handles); weight 0 releases it.
func set_reach(side: StringName, world_position: Vector3, weight: float) -> void:
	_reach[side] = [world_position, clampf(weight, 0.0, 1.0)]


func set_weapon(data: WeaponData) -> void:
	var changed := _weapon_id(data) != _weapon_id(weapon)
	weapon = data
	if changed:
		_begin_draw()
	else:
		_refresh_meshes()


## A firearm or throwable is equipped (uses the gun-holding poses when drawn).
func is_armed() -> bool:
	return weapon != null and not weapon.is_melee()


## Plays the shoot one-shot plus recoil (or a punch, for melee).
func fire() -> void:
	if _dead:
		return
	if weapon != null and weapon.is_melee():
		melee(&"punch_l" if _punch_left else &"punch_r")
		_punch_left = not _punch_left
		return
	_kick = minf(_kick + (weapon.recoil_degrees if weapon != null else 1.0) * 0.04, 0.5)
	animation_tree.set(&"parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Melee swing: punch_l, punch_r, kick, whip (pistol) or butt (rifle stock).
func melee(kind: StringName) -> void:
	if _dead:
		return
	var shot: StringName = MELEE_SHOTS.get(kind, &"punch")
	animation_tree.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Reach-and-use gesture (door handles, pickups).
func interact() -> void:
	if not _dead:
		animation_tree.set(&"parameters/interact/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Hit reaction plus a short red flash; [param push] (world direction the hit travelled) flinches the
## body away from it.
func hit(push: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	var shot := &"hit"
	if push != Vector3.ZERO:
		var local := global_basis.inverse() * push
		var flat := Vector2(-local.z, local.x)
		if flat.length_squared() > 0.0001:
			_flinch = flat.normalized()
			shot = &"hit2" if absf(flat.y) > absf(flat.x) else &"hit"
	animation_tree.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_set_overlay(_flash_material)
	if is_inside_tree():
		get_tree().create_timer(0.1, false).timeout.connect(_set_overlay.bind(null))


## Death: the body goes limp as a ragdoll pushed by [param impulse] (applied near [param at]) and
## carried along by [param velocity]. The Death clip stays underneath for bones the ragdoll skips.
func die(impulse: Vector3 = Vector3.ZERO, at: Vector3 = Vector3.INF, velocity: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	_dead = true
	_aiming = false
	_set_overlay(null)
	_local_velocity = Vector2.ZERO
	_weapon_mesh.visible = false
	_reload_progress = -1.0
	animation_tree.set(&"parameters/life/transition_request", "dead")
	if is_inside_tree() and skeleton.is_inside_tree():
		if impulse == Vector3.ZERO:
			# Unattributed deaths still topple: a shove at the chest, mostly backwards.
			impulse = (global_basis.z + global_basis.x * randf_range(-0.4, 0.4)).normalized() * 35.0
			at = global_position + Vector3.UP * 1.3
		ragdoll = Ragdoll.spawn(self, skeleton, _pose, velocity, impulse, at)


func revive() -> void:
	_dead = false
	if ragdoll != null:
		ragdoll.queue_free()
		ragdoll = null
	_pose.ragdoll = {}
	_flinch = Vector2.ZERO
	_kick = 0.0
	_in_hand = _hand_choice()
	_refresh_meshes()
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


## World position of the right hand (where weapons are held), after procedural posing.
func hand_position() -> Vector3:
	if _pose.has_pose:
		return _pose.hand_r.origin
	return skeleton.global_transform * skeleton.get_bone_global_pose(_hand_bone).origin


## World-space height of the head bone above this node (drops when crouched or dead).
func head_height() -> float:
	return _head_world().origin.y - global_position.y


## World position of the head bone (headshot checks).
func head_position() -> Vector3:
	return _head_world().origin


## The weapon mesh currently held in the hand (null when holstered or unarmed).
func weapon_in_hand() -> WeaponData:
	return _in_hand


func _head_world() -> Transform3D:
	if _pose.has_pose:
		return _pose.head
	return skeleton.global_transform * skeleton.get_bone_global_pose(_head_bone)


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
	_pose = CharacterPoseModifier.new()
	_pose.name = "Pose"
	_pose.facing = self
	skeleton.add_child(_pose)
	skeleton.skeleton_updated.connect(_on_skeleton_updated)

	_weapon_mesh = _box("Weapon", Vector3(0.06, 0.12, 0.3), Color(0.12, 0.12, 0.13))
	_weapon_mesh.visible = false
	_hip_mesh = _box("HipHolster", Vector3(0.05, 0.13, 0.24), Color(0.12, 0.12, 0.13))
	_hip_mesh.visible = false
	_back_mesh = _box("BackSling", Vector3(0.07, 0.14, 0.9), Color(0.12, 0.12, 0.13))
	_back_mesh.visible = false
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


static func _weapon_id(data: WeaponData) -> StringName:
	return data.id if data != null else &""


static func _shows_mesh(data: WeaponData) -> bool:
	return data != null and not data.is_melee()


## What should be in the hand right now (null when holstered, unarmed or dead).
func _hand_choice() -> WeaponData:
	return weapon if _shows_mesh(weapon) and not _holstered and not _dead else null


## Starts the reach to the holster (or straight swap when there's nothing to draw or stow).
func _begin_draw() -> void:
	var target := _hand_choice()
	if target == _in_hand:
		_refresh_meshes()
		return
	if not is_inside_tree() or _dead:
		_in_hand = target
		_draw_time = -1.0
		_refresh_meshes()
		return
	_draw_from = _in_hand if _in_hand != null else target
	_draw_time = 0.0
	_refresh_meshes()


## Picks the hip / back holster contents and sizes every weapon mesh.
func _refresh_meshes() -> void:
	if _weapon_mesh == null:
		return
	var on_body: Array[WeaponData] = []
	if _shows_mesh(weapon):
		on_body.append(weapon)
	for data in _carried:
		if _shows_mesh(data) and not data in on_body:
			on_body.append(data)
	_hip_weapon = null
	_back_weapon = null
	for data in on_body:
		if data == _in_hand:
			continue
		if data.carry == WeaponData.Carry.HIP and _hip_weapon == null:
			_hip_weapon = data
		elif data.carry == WeaponData.Carry.BACK and _back_weapon == null:
			_back_weapon = data
	_size_mesh(_weapon_mesh, _in_hand)
	_size_mesh(_hip_mesh, _hip_weapon)
	_size_mesh(_back_mesh, _back_weapon)
	if _dead:
		_weapon_mesh.visible = false


static func _size_mesh(mesh: MeshInstance3D, data: WeaponData) -> void:
	mesh.visible = data != null
	if data != null:
		(mesh.mesh as BoxMesh).size = WEAPON_SIZES.get(data.id, Vector3(0.06, 0.12, 0.3))


## Feeds the pose modifier for this frame: crouch, sit, crawl, leans, recoil and hand targets.
func _update_pose() -> void:
	var crouch := _crouch_weight * (1.0 - _seated_weight) * (1.0 - _crawl_weight)
	var offset := Vector3(0.0, -CROUCH_DROP * crouch, 0.0)
	offset = offset.lerp(Vector3(0.0, -0.45, 0.15), _seated_weight)
	offset = offset.lerp(Vector3(0.0, -0.5, 0.0), _crawl_weight)
	offset.y -= 0.25 * _land
	var spine := CROUCH_LEAN * crouch + 0.22 * _sprint_weight + 0.25 * _winded + 1.1 * _crawl_weight
	spine += 0.12 * _air_weight + 0.4 * _land
	spine += _flinch.x * 0.35
	var chest := sin(_time * 7.0) * 0.05 * _winded - _kick * 0.15
	# While aiming the chest counters the lean so the gun stays on the crosshair.
	chest -= (spine - _flinch.x * 0.35) * _aim_weight
	_pose.body_offset = offset if not _dead else Vector3.ZERO
	_pose.spine_pitch = spine if not _dead else 0.0
	_pose.chest_pitch = chest if not _dead else 0.0
	_pose.chest_roll = (0.1 * _shoulder_weight * _aim_weight + _flinch.y * 0.3) if not _dead else 0.0
	_pose.head_pitch = -spine * 0.7 * (1.0 - _crawl_weight * 0.5) if not _dead else 0.0
	_pose.arm_kick = _kick * 0.6 if _in_hand != null and not _dead else 0.0

	var axes := global_basis.orthonormalized()
	_weapon_pitch = _aim_pitch * _aim_weight + (1.0 - _aim_weight) * -0.7 + _kick
	_weapon_roll = 0.0
	var reload_tilt := 0.0
	if _reload_weight > 0.0 and _reload_style != WeaponData.ReloadStyle.NONE:
		reload_tilt = 0.45 * _reload_weight
		_weapon_pitch = lerpf(_weapon_pitch, -0.25, _reload_weight)
		_weapon_roll = reload_tilt
	var length := (_weapon_mesh.mesh as BoxMesh).size.z if _in_hand != null else 0.3
	var direction := Basis(Vector3.RIGHT, _weapon_pitch) * Vector3.FORWARD

	var left_target := Vector3.ZERO
	var left_weight := 0.0
	var grip_weight := 0.0
	var grip_offset := Vector3.ZERO
	var long_gun := _in_hand != null and _in_hand.carry == WeaponData.Carry.BACK
	if _in_hand != null and not _dead:
		if long_gun:
			grip_offset = _gun_spot(&"fore", direction, length)
			grip_weight = 1.0 - _sprint_weight * (1.0 - _aim_weight)
		elif _aim_weight > 0.0:
			grip_offset = _gun_spot(&"grip", direction, length)
			grip_weight = _aim_weight
		if _reload_weight > 0.0 and RELOAD_PATHS.has(_reload_style):
			var spot := _reload_spot(clampf(_reload_progress, 0.0, 1.0), direction, length)
			left_target = spot[0]
			left_weight = _reload_weight
			grip_offset = grip_offset.lerp(spot[1], _reload_weight) if grip_weight > 0.0 else spot[1]
			grip_weight = lerpf(grip_weight, spot[2], _reload_weight)
	var right_target := Vector3.ZERO
	var right_weight := 0.0
	if long_gun and _aim_weight > 0.0 and not _dead:
		# Long guns are shouldered: pull the gun hand in under the cheek instead of the pistol arm-out.
		var shoulder := Vector3(0.17, 1.4, 0.0) + _pose.body_offset
		right_target = global_transform * (shoulder + Basis(Vector3.RIGHT, _aim_pitch) * Vector3(-0.04, -0.14, -0.3))
		right_weight = _aim_weight * (1.0 - _reload_weight)
	if _draw_time >= 0.0 and not _dead:
		var data := _draw_from if _draw_from != null else _hand_choice()
		if data == null:
			data = _in_hand
		right_target = _holster_point(data)
		right_weight = sin(clampf(_draw_time / DRAW_TIME, 0.0, 1.0) * PI)
	for side: StringName in [&"L", &"R"]:
		var reach: Array = _reach[side]
		if reach[1] > 0.0:
			if side == &"L":
				left_target = left_target.lerp(reach[0], reach[1]) if left_weight > 0.0 else reach[0]
				left_weight = maxf(left_weight, reach[1])
				grip_weight *= 1.0 - reach[1]
			else:
				right_target = right_target.lerp(reach[0], reach[1]) if right_weight > 0.0 else reach[0]
				right_weight = maxf(right_weight, reach[1])
	if _crawl_weight > 0.0:
		left_target = left_target.lerp(global_transform * Vector3(-0.22, 0.02, -0.55), _crawl_weight) if left_weight > 0.0 else global_transform * Vector3(-0.22, 0.02, -0.55)
		right_target = right_target.lerp(global_transform * Vector3(0.22, 0.02, -0.55), _crawl_weight) if right_weight > 0.0 else global_transform * Vector3(0.22, 0.02, -0.55)
		left_weight = maxf(left_weight, _crawl_weight)
		right_weight = maxf(right_weight, _crawl_weight)
		grip_weight *= 1.0 - _crawl_weight
	if _air_weight > 0.0 and not _dead:
		# Free hands fling up and out for balance; a hand on the gun stays on it.
		var lift := _air_weight * (1.0 - _aim_weight) * (1.0 - _reload_weight)
		if grip_weight < 0.5 and left_weight < 0.5:
			left_target = left_target.lerp(global_transform * Vector3(-0.55, 1.35, -0.05), lift) if left_weight > 0.0 else global_transform * Vector3(-0.55, 1.35, -0.05)
			left_weight = maxf(left_weight, lift)
		if _in_hand == null and right_weight < 0.5:
			right_target = right_target.lerp(global_transform * Vector3(0.55, 1.35, -0.05), lift) if right_weight > 0.0 else global_transform * Vector3(0.55, 1.35, -0.05)
			right_weight = maxf(right_weight, lift)
	_pose.hand_targets[&"L"] = left_target
	_pose.hand_weights[&"L"] = left_weight if not _dead else 0.0
	_pose.hand_targets[&"R"] = right_target
	_pose.hand_weights[&"R"] = right_weight if not _dead else 0.0
	_pose.grip_offset = grip_offset
	_pose.grip_weight = grip_weight if not _dead else 0.0
	# Rising: knees tucked up. Falling: legs reach down for the landing.
	var tuck := clampf((_air_vy + 1.0) / 5.0, 0.0, 1.0)
	var air := _air_weight * (1.0 - _seated_weight) if not _dead else 0.0
	for side: StringName in [&"L", &"R"]:
		var x := -0.12 if side == &"L" else 0.12
		var seat := global_transform * Vector3(x, 0.08, -0.45)
		var lead := side == &"L"
		var air_foot := global_transform * Vector3(x, lerpf(0.22 if lead else 0.12, 0.55 if lead else 0.38, tuck), -0.2 if lead else 0.08)
		_pose.foot_targets[side] = seat.lerp(air_foot, air)
		_pose.foot_weights[side] = maxf(_seated_weight, air) if not _dead else 0.0


## A spot on the held gun relative to the right wrist, in this node's axes (forward is -Z).
func _gun_spot(spot: StringName, direction: Vector3, length: float) -> Vector3:
	var down := Basis(Vector3.RIGHT, _weapon_pitch) * Vector3.DOWN
	match spot:
		&"fore":
			return direction * length * 0.38 + down * 0.03 + Vector3(-0.02, 0.0, 0.0)
		&"well":
			return direction * length * 0.25 + down * 0.1
		&"port":
			return direction * length * 0.35 + Vector3(-0.06, 0.0, 0.0)
		&"rear":
			return -direction * length * 0.15 + down * 0.05
	# Pistol two-handed grip: the left hand cups the right.
	return Vector3(-0.05, -0.03, 0.03)


## Reload hand position at [param progress]: [world body target, gun offset, gun weight].
func _reload_spot(progress: float, direction: Vector3, length: float) -> Array:
	var path: Array = RELOAD_PATHS[_reload_style]
	var a: Array = path[0]
	var b: Array = path[path.size() - 1]
	for i in path.size() - 1:
		if progress >= path[i][0] and progress <= path[i + 1][0]:
			a = path[i]
			b = path[i + 1]
			break
	var span: float = b[0] - a[0]
	var t := smoothstep(0.0, 1.0, (progress - a[0]) / span) if span > 0.0 else 1.0
	var a_body := _is_body_spot(a[1])
	var b_body := _is_body_spot(b[1])
	var world := _body_spot(b[1] if b_body else a[1])
	var offset := _gun_spot(a[1], direction, length).lerp(_gun_spot(b[1], direction, length), t)
	if a_body and not b_body:
		offset = _gun_spot(b[1], direction, length)
	elif b_body and not a_body:
		offset = _gun_spot(a[1], direction, length)
	var on_gun := (0.0 if a_body else 1.0) * (1.0 - t) + (0.0 if b_body else 1.0) * t
	return [world, offset, on_gun]


static func _is_body_spot(spot: StringName) -> bool:
	return spot == &"pouch" or spot == &"shoulder"


func _body_spot(spot: StringName) -> Vector3:
	var drop := _pose.body_offset
	if spot == &"shoulder":
		return global_transform * (Vector3(-0.15, 1.55, 0.25) + drop)
	return global_transform * (Vector3(-0.17, 0.92, -0.05) + drop)


## Where [param data] rides on the body (hip holster or back sling), world space.
func _holster_point(data: WeaponData) -> Vector3:
	var axes := global_basis.orthonormalized()
	if data != null and data.carry == WeaponData.Carry.BACK and _pose.has_pose:
		return _pose.chest.origin - axes.z * -0.2 + axes.x * 0.15 + axes.y * 0.15
	if _pose.has_pose:
		return _pose.hips.origin + axes.x * 0.2
	return global_transform * Vector3(0.2, 0.9, 0.0)


## Places the held and holstered weapons and the bandana once the final (procedural) pose is known.
func _on_skeleton_updated() -> void:
	if not is_inside_tree() or not _pose.has_pose:
		return
	var axes := global_basis.orthonormalized()
	if _weapon_mesh.visible:
		var direction := axes * (Basis(Vector3.RIGHT, _weapon_pitch) * Vector3.FORWARD)
		var length := (_weapon_mesh.mesh as BoxMesh).size.z
		var grip := _pose.hand_r.origin + direction * length * 0.3
		var basis := Basis.looking_at(direction, axes.y)
		if _weapon_roll != 0.0:
			basis = Basis(direction, _weapon_roll) * basis
		_weapon_mesh.global_transform = Transform3D(basis, grip)
	if _hip_mesh.visible:
		var hips := _pose.hips
		var down := -axes.y
		_hip_mesh.global_transform = Transform3D(Basis.looking_at(down, -axes.z), hips.origin + axes.x * 0.2 - axes.y * 0.08)
	if _back_mesh.visible:
		var chest := _pose.chest
		var lean := chest.basis.orthonormalized()
		var back := -axes.z * -1.0
		var along := (axes.y * 0.8 + axes.x * 0.55).normalized()
		if ragdoll != null:
			back = lean * Vector3.BACK
		_back_mesh.global_transform = Transform3D(Basis.looking_at(along, back), chest.origin + back * 0.17)
	if _bandana.visible:
		var head := _pose.head
		var basis := head.basis.orthonormalized()
		_bandana.global_transform = Transform3D(basis, head.origin + basis.y * 0.12 * _shared_scale())


func _set_overlay(material: Material) -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = material


func _build_tree() -> void:
	var upper_body := _bone_paths("Abdomen")
	var gun_arm := _bone_paths("Shoulder.R")
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

	# [name, clip, one-shot, filter]. "armed" only holds the gun arm, so the other arm keeps swinging.
	var previous := &"loco"
	for layer: Array in [[&"armed", &"Idle_Gun", false, gun_arm], [&"aim_upper", &"Idle_Gun_Pointing", false, upper_body],
			[&"shoot", &"Idle_Gun_Shoot", true, upper_body], [&"punch", &"Punch_Right", true, upper_body],
			[&"punch_l", &"Punch_Left", true, upper_body], [&"slash", &"Sword_Slash", true, upper_body],
			[&"interact", &"Interact", true, upper_body], [&"kick", &"Kick_Right", true, []],
			[&"hit", &"HitRecieve", true, upper_body], [&"hit2", &"HitRecieve_2", true, upper_body]]:
		var node: AnimationNode
		if layer[2]:
			var one_shot := AnimationNodeOneShot.new()
			one_shot.fadein_time = 0.05
			one_shot.fadeout_time = 0.15
			node = one_shot
		else:
			node = AnimationNodeBlend2.new()
		var filter: Array = layer[3]
		node.filter_enabled = not filter.is_empty()
		for path in filter:
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


## Track paths of [param root_bone] and everything below it.
func _bone_paths(root_bone: String) -> Array[NodePath]:
	var paths: Array[NodePath] = []
	var pending: Array[int] = [skeleton.find_bone(root_bone)]
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
