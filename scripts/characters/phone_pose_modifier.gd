class_name PhonePoseModifier
extends SkeletonModifier3D
## Two-bone IK that lifts the right hand to the ear (phone call pose) on top of any animation.
## Blend it in and out with [member SkeletonModifier3D.influence].

var upper_bone_name := "UpperArm.R"
var lower_bone_name := "LowerArm.R"
var wrist_bone_name := "Wrist.R"
var head_bone_name := "Head"
var neck_bone_name := "Neck"
## Node whose basis gives the character's right (+X) and forward (-Z) axes (the CharacterVisual).
var facing: Node3D

var _upper := -1
var _lower := -1
var _wrist := -1
var _head := -1
var _neck := -1


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or facing == null:
		return
	if _upper < 0:
		_upper = skeleton.find_bone(upper_bone_name)
		_lower = skeleton.find_bone(lower_bone_name)
		_wrist = skeleton.find_bone(wrist_bone_name)
		_head = skeleton.find_bone(head_bone_name)
		_neck = skeleton.find_bone(neck_bone_name)
		if mini(mini(_upper, _lower), mini(_wrist, mini(_head, _neck))) < 0:
			_upper = -1
			return
	var to_skeleton := skeleton.global_basis.inverse()
	var right := (to_skeleton * facing.global_basis.x).normalized()
	var forward := (to_skeleton * -facing.global_basis.z).normalized()
	var up := right.cross(forward).normalized()
	var upper_pose := skeleton.get_bone_global_pose(_upper)
	var lower_pose := skeleton.get_bone_global_pose(_lower)
	var wrist_pose := skeleton.get_bone_global_pose(_wrist)
	var head := skeleton.get_bone_global_pose(_head).origin
	var unit := head.distance_to(skeleton.get_bone_global_pose(_neck).origin)
	var target := head + right * unit * 1.1 + forward * unit * 0.2 + up * unit * 0.4
	var a := upper_pose.origin
	var l1 := a.distance_to(lower_pose.origin)
	var l2 := lower_pose.origin.distance_to(wrist_pose.origin)
	var to_target := target - a
	var reach := clampf(to_target.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var direction := to_target.normalized()
	var pole := right * 0.6 - up * 1.0 - forward * 0.2
	var perpendicular := (pole - direction * pole.dot(direction)).normalized()
	var cos_a := clampf((l1 * l1 + reach * reach - l2 * l2) / (2.0 * l1 * reach), -1.0, 1.0)
	var elbow := a + (direction * cos_a + perpendicular * sqrt(1.0 - cos_a * cos_a)) * l1
	var hand := a + direction * reach

	var q_upper := Quaternion((lower_pose.origin - a).normalized(), (elbow - a).normalized())
	var new_upper := Basis(q_upper) * upper_pose.basis
	var bent_forearm := (q_upper * (wrist_pose.origin - lower_pose.origin)).normalized()
	var q_lower := Quaternion(bent_forearm, (hand - elbow).normalized())
	var new_lower := Basis(q_lower * q_upper) * lower_pose.basis

	var parent := skeleton.get_bone_parent(_upper)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(_upper, (parent_basis.orthonormalized().inverse() * new_upper.orthonormalized()).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(_lower, (new_upper.orthonormalized().inverse() * new_lower.orthonormalized()).get_rotation_quaternion())
