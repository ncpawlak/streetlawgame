class_name AimPitchModifier
extends SkeletonModifier3D
## Bends the chest up/down so the arms (and held weapon) follow the aim pitch on top of the
## animation. Rotates about the character's right axis; [member pitch] is radians, positive = up.

var pitch := 0.0
var bone_name := "Chest"
## Node whose basis.x is the character's right axis (the CharacterVisual).
var facing: Node3D

var _bone := -1


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or facing == null or absf(pitch) < 0.001:
		return
	if _bone < 0:
		_bone = skeleton.find_bone(bone_name)
		if _bone < 0:
			return
	var parent := skeleton.get_bone_parent(_bone)
	var axis := (skeleton.global_basis.inverse() * facing.global_basis.x).normalized()
	var pose := skeleton.get_bone_global_pose(_bone).basis
	var bent := Basis(axis, pitch) * pose
	var parent_pose := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(_bone, (parent_pose.inverse() * bent).get_rotation_quaternion())
