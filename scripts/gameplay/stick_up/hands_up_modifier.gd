class_name HandsUpModifier
extends SkeletonModifier3D
## Raises both arms over the head on top of the animation (the character models have no hands-up
## clip). [member target] 0 = arms down, 0.5 = hands up in front of the chest (wary), 1 = hands up (held up / cowering).

const SPEED := 5.0
const SIDES := [["UpperArm.L", "LowerArm.L", "Wrist.L", -1.0], ["UpperArm.R", "LowerArm.R", "Wrist.R", 1.0]]

var target := 0.0
var amount := 0.0
## Node whose basis.x is the character's right axis (the CharacterVisual).
var facing: Node3D


func _process_modification_with_delta(delta: float) -> void:
	amount = move_toward(amount, target, delta * SPEED)
	var skeleton := get_skeleton()
	if skeleton == null or facing == null or amount < 0.001:
		return
	var to_skeleton := skeleton.global_basis.inverse()
	var up := (to_skeleton * Vector3.UP).normalized()
	var right := (to_skeleton * facing.global_basis.x).normalized()
	var forward := (to_skeleton * -facing.global_basis.z).normalized()
	var wary := clampf(amount * 2.0, 0.0, 1.0)
	var raise := clampf(amount * 2.0 - 1.0, 0.0, 1.0)
	for side: Array in SIDES:
		var out: Vector3 = right * side[3]
		var upper_wary := (forward * 0.55 - up * 0.65 + out * 0.5).normalized()
		var lower_wary := (up * 0.75 + forward * 0.45 + out * 0.15).normalized()
		var upper_up := (up * 0.92 + out * 0.3 + forward * 0.15).normalized()
		var lower_up := (upper_up + forward * 0.25).normalized()
		_point(skeleton, skeleton.find_bone(side[0]), skeleton.find_bone(side[1]), upper_wary, upper_up, wary, raise)
		_point(skeleton, skeleton.find_bone(side[1]), skeleton.find_bone(side[2]), lower_wary, lower_up, wary, raise)


## Swings [param bone] so the direction to [param child] blends from the animation toward the wary
## direction (by [param wary]) and then toward the raised one (by [param raise]).
func _point(skeleton: Skeleton3D, bone: int, child: int, wary_dir: Vector3, raised: Vector3, wary: float, raise: float) -> void:
	if bone < 0 or child < 0:
		return
	var pose := skeleton.get_bone_global_pose(bone)
	var direction := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var goal := direction.slerp(wary_dir, wary).slerp(raised, raise)
	if direction.cross(goal).length_squared() < 0.000001:
		return
	var bent := Basis(Quaternion(direction, goal)) * pose.basis
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * bent).get_rotation_quaternion())