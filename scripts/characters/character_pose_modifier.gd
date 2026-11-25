class_name CharacterPoseModifier
extends SkeletonModifier3D
## Procedural layer on top of the clips (the Quaternius set has no crouch, climb, reload or seated
## clips): drops the body with two-bone leg IK keeping the feet planted, bends the spine, kicks the
## gun arm for recoil, reaches the hands to world targets (foregrip, magazine, ledge, door handle),
## and drives the bones from ragdoll bodies once dead. [CharacterVisual] sets the inputs every frame.
## Results are cached in world space ([member hand_r], [member head]) because poses written by
## modifiers aren't visible through [method Skeleton3D.get_bone_global_pose] outside the modifier.

## Node whose basis gives the character's axes (the CharacterVisual; forward is -Z).
var facing: Node3D
## Pelvis offset in the facing node's space (metres): crouching drops it, sitting moves it back.
var body_offset := Vector3.ZERO
## Forward bend of the lower spine and chest (radians, positive = forward), sideways lean
## (positive = right) and head nod (positive = down).
var spine_pitch := 0.0
var chest_pitch := 0.0
var chest_roll := 0.0
var head_pitch := 0.0
## Raises the gun arm (radians) for recoil and reload tilts.
var arm_kick := 0.0
## World-space hand / foot targets, each blended in by its weight (0 leaves the clip's pose).
var hand_targets := {&"L": Vector3.ZERO, &"R": Vector3.ZERO}
var hand_weights := {&"L": 0.0, &"R": 0.0}
## Left-hand target relative to the solved right wrist, in the facing node's axes (foregrip, magazine
## well); blended over [member hand_targets] L by [member grip_weight].
var grip_offset := Vector3.ZERO
var grip_weight := 0.0
var foot_targets := {&"L": Vector3.ZERO, &"R": Vector3.ZERO}
var foot_weights := {&"L": 0.0, &"R": 0.0}
## bone index -> [RigidBody3D, Transform3D offset from body to bone]. Non-empty means ragdolled.
var ragdoll := {}

## World transforms of key bones after this frame's modification (valid once [member has_pose]).
var hand_r := Transform3D.IDENTITY
var hand_l := Transform3D.IDENTITY
var head := Transform3D.IDENTITY
var hips := Transform3D.IDENTITY
var chest := Transform3D.IDENTITY
var has_pose := false
## 0..1: turn the shoulders, head and arms back to face [member facing] whatever the clip does to
## the torso (strafe clips run sideways). The hips keep up to [constant HIP_TWIST_LIMIT] of the
## clip's turn so the legs still run the way you move.
var face_forward := 0.0
## Yaw (radians, about up) of the hip line and shoulder line off [member facing], measured from the
## animation before and after this frame's correction.
var clip_hips_yaw := 0.0
var clip_shoulders_yaw := 0.0
var hips_yaw := 0.0
var shoulders_yaw := 0.0

const HIP_TWIST_LIMIT := 0.6

var _bones := {}


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or facing == null:
		return
	if _bones.is_empty():
		for bone_name in ["Body", "Abdomen", "Chest", "Head", "Neck", "Hips", "UpperArm.L", "LowerArm.L", "Wrist.L",
				"UpperArm.R", "LowerArm.R", "Wrist.R", "UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R"]:
			_bones[bone_name] = skeleton.find_bone(bone_name)
	if not ragdoll.is_empty():
		_apply_ragdoll(skeleton)
	else:
		_apply_pose(skeleton)
	var to_world := skeleton.global_transform
	hand_r = to_world * skeleton.get_bone_global_pose(_bones["Wrist.R"])
	hand_l = to_world * skeleton.get_bone_global_pose(_bones["Wrist.L"])
	head = to_world * skeleton.get_bone_global_pose(_bones["Head"])
	hips = to_world * skeleton.get_bone_global_pose(_bones["Hips"])
	chest = to_world * skeleton.get_bone_global_pose(_bones["Chest"])
	has_pose = true


func _apply_pose(skeleton: Skeleton3D) -> void:
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var right := _axis(skeleton, facing.global_basis.x)
	var forward := _axis(skeleton, -facing.global_basis.z)
	var up := _axis(skeleton, facing.global_basis.y)
	clip_hips_yaw = _line_yaw(skeleton, "UpperLeg.L", "UpperLeg.R", right, up)
	clip_shoulders_yaw = _line_yaw(skeleton, "UpperArm.L", "UpperArm.R", right, up)
	if face_forward > 0.001:
		# Turn the whole body back until the hips are within the limit, then untwist the spine.
		var excess := clip_hips_yaw - clampf(clip_hips_yaw, -HIP_TWIST_LIMIT, HIP_TWIST_LIMIT)
		if absf(excess) > 0.0001:
			_rotate(skeleton, _bones["Body"], up, -excess * face_forward)
		# The aim pose sits on the hips, so undo the hips' remaining turn in the spine: the upper
		# body ends up exactly as when standing square, gun on the reticle.
		var twist := _line_yaw(skeleton, "UpperLeg.L", "UpperLeg.R", right, up) * face_forward
		_rotate(skeleton, _bones["Abdomen"], up, -twist * 0.5)
		_rotate(skeleton, _bones["Chest"], up, -twist * 0.5)
	hips_yaw = _line_yaw(skeleton, "UpperLeg.L", "UpperLeg.R", right, up)
	shoulders_yaw = _line_yaw(skeleton, "UpperArm.L", "UpperArm.R", right, up)
	var planted := {}
	# Feet hang off the root, not the shins, so their offset from the shin is taken before the body moves.
	var foot_in_shin := {}
	for side in [&"L", &"R"]:
		planted[side] = skeleton.get_bone_global_pose(_bones["Foot.%s" % side]).origin
		foot_in_shin[side] = skeleton.get_bone_global_pose(_bones["LowerLeg.%s" % side]).affine_inverse() * skeleton.get_bone_global_pose(_bones["Foot.%s" % side])
	if body_offset.length_squared() > 0.000001:
		var body: int = _bones["Body"]
		var global := skeleton.get_bone_global_pose(body)
		global.origin += skeleton.global_basis.inverse() * (facing.global_basis * body_offset)
		_set_global(skeleton, body, global)
	# A positive turn about the right axis tips the top backwards, so forward bends are negated.
	if absf(spine_pitch) > 0.0001:
		_rotate(skeleton, _bones["Abdomen"], right, -spine_pitch * 0.6)
	if absf(spine_pitch * 0.4 + chest_pitch) > 0.0001:
		_rotate(skeleton, _bones["Chest"], right, -(spine_pitch * 0.4 + chest_pitch))
	if absf(chest_roll) > 0.0001:
		_rotate(skeleton, _bones["Chest"], forward, chest_roll)
	if absf(head_pitch) > 0.0001:
		_rotate(skeleton, _bones["Neck"], right, -head_pitch)

	var pole_leg := forward
	for side in [&"L", &"R"]:
		var weight: float = foot_weights[side]
		var target: Vector3 = planted[side]
		if weight > 0.0:
			target = target.lerp(to_skeleton * (foot_targets[side] as Vector3), weight)
		var moved := body_offset.length_squared() > 0.000001 or weight > 0.0
		if moved:
			_two_bone(skeleton, _bones["UpperLeg.%s" % side], _bones["LowerLeg.%s" % side], _bones["Foot.%s" % side], target, pole_leg, true, foot_in_shin[side])

	if absf(arm_kick) > 0.0001:
		_rotate(skeleton, _bones["UpperArm.R"], right, arm_kick)
	var down := _axis(skeleton, -facing.global_basis.y)
	var back := -forward
	for side in [&"R", &"L"]:
		var weight: float = hand_weights[side]
		var goal := to_skeleton * (hand_targets[side] as Vector3)
		if side == &"L" and grip_weight > 0.001:
			var wrist_r := skeleton.global_transform * skeleton.get_bone_global_pose(_bones["Wrist.R"]).origin
			var grip := wrist_r + facing.global_basis.orthonormalized() * grip_offset
			goal = goal.lerp(to_skeleton * grip, clampf(grip_weight, 0.0, 1.0)) if weight > 0.001 else to_skeleton * grip
			weight = maxf(weight, grip_weight)
		if weight <= 0.001:
			continue
		var outward := -right if side == &"L" else right
		var wrist: int = _bones["Wrist.%s" % side]
		var current := skeleton.get_bone_global_pose(wrist).origin
		var target := current.lerp(goal, clampf(weight, 0.0, 1.0))
		_two_bone(skeleton, _bones["UpperArm.%s" % side], _bones["LowerArm.%s" % side], wrist, target, (down + back * 0.6 + outward * 0.5).normalized(), false)


## Two-bone IK in skeleton space: bends [param upper]/[param lower] so [param end] reaches
## [param target], with the middle joint toward [param pole]. With [param move_end] the end bone
## (feet, which hang off the root rather than the shin) is moved onto the solved position too.
func _two_bone(skeleton: Skeleton3D, upper: int, lower: int, end: int, target: Vector3, pole: Vector3, move_end: bool, end_local: Variant = null) -> void:
	var a := skeleton.get_bone_global_pose(upper)
	var b := skeleton.get_bone_global_pose(lower)
	var end_in_lower: Transform3D = end_local if end_local is Transform3D else b.affine_inverse() * skeleton.get_bone_global_pose(end)
	var c := b * end_in_lower
	var l1 := a.origin.distance_to(b.origin)
	var l2 := b.origin.distance_to(c.origin)
	if l1 <= 0.0 or l2 <= 0.0:
		return
	var to_target := target - a.origin
	var distance := clampf(to_target.length(), absf(l1 - l2) + l1 * 0.01, (l1 + l2) * 0.999)
	var direction := to_target.normalized() if to_target.length_squared() > 0.0 else (c.origin - a.origin).normalized()
	var cos_a := clampf((l1 * l1 + distance * distance - l2 * l2) / (2.0 * l1 * distance), -1.0, 1.0)
	var bend := pole - direction * direction.dot(pole)
	if bend.length_squared() < 0.000001:
		bend = (b.origin - a.origin) - direction * direction.dot(b.origin - a.origin)
	bend = bend.normalized()
	var mid := a.origin + direction * l1 * cos_a + bend * l1 * sqrt(1.0 - cos_a * cos_a)
	var tip := a.origin + direction * distance
	_aim_bone(skeleton, upper, b.origin - a.origin, mid - a.origin)
	var b_now := skeleton.get_bone_global_pose(lower)
	_aim_bone(skeleton, lower, (b_now * end_in_lower).origin - b_now.origin, tip - b_now.origin)
	if move_end:
		var global := skeleton.get_bone_global_pose(end)
		global.origin = (skeleton.get_bone_global_pose(lower) * end_in_lower).origin
		_set_global(skeleton, end, global)


## Rotates a bone (in skeleton space) so that [param from] turns onto [param to].
func _aim_bone(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 1e-12 or to.length_squared() < 1e-12:
		return
	var f := from.normalized()
	var t := to.normalized()
	if f.dot(t) > 0.99999:
		return
	var global := skeleton.get_bone_global_pose(bone)
	var axis := f.cross(t)
	var turn := Basis(axis.normalized(), f.angle_to(t)) if axis.length_squared() > 1e-12 else Basis.IDENTITY
	global.basis = turn * global.basis
	_set_global(skeleton, bone, global)


func _rotate(skeleton: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0:
		return
	var global := skeleton.get_bone_global_pose(bone)
	global.basis = Basis(axis, angle) * global.basis
	_set_global(skeleton, bone, global)


func _set_global(skeleton: Skeleton3D, bone: int, global: Transform3D) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var local := skeleton.get_bone_global_pose(parent).affine_inverse() * global if parent >= 0 else global
	skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
	skeleton.set_bone_pose_position(bone, local.origin)


func _apply_ragdoll(skeleton: Skeleton3D) -> void:
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var bones := ragdoll.keys()
	bones.sort()
	for bone: int in bones:
		var entry: Array = ragdoll[bone]
		var body := entry[0] as Node3D
		if not is_instance_valid(body):
			continue
		_set_global(skeleton, bone, to_skeleton * body.global_transform * (entry[1] as Transform3D))


## Signed yaw about [param up] from [param right] to the line from bone [param a] to bone [param b].
func _line_yaw(skeleton: Skeleton3D, a: String, b: String, right: Vector3, up: Vector3) -> float:
	var line := skeleton.get_bone_global_pose(_bones[b]).origin - skeleton.get_bone_global_pose(_bones[a]).origin
	line -= up * up.dot(line)
	if line.length_squared() < 1e-8:
		return 0.0
	return atan2(right.cross(line).dot(up), right.dot(line))


static func _axis(skeleton: Skeleton3D, world: Vector3) -> Vector3:
	return (skeleton.global_basis.inverse() * world).normalized()
