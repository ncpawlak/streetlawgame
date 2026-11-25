class_name Ragdoll
extends Node3D
## Physics corpse for a [CharacterVisual]: capsule rigid bodies along the main bones, joined with
## cone-twist joints, which the [CharacterPoseModifier] copies back onto the skeleton every frame.
## Bodies sit on [constant LAYER] and only collide with the world and vehicles, so they never block
## the living. Bullets, cars and explosions push them (see [method push]); they freeze after
## [constant SETTLE_TIME] so piles of bodies cost nothing.

const LAYER := 32
const MASK := 1 | 8
const SETTLE_TIME := 6.0
## [name, from bone, to bone, extend past the end (m), radius, mass, bones driven, parent segment]
const SEGMENTS := [
	[&"pelvis", "Body", "Abdomen", 0.1, 0.14, 10.0, ["Body", "Hips"], &""],
	[&"torso", "Abdomen", "Neck", 0.0, 0.15, 18.0, ["Abdomen", "Torso", "Chest"], &"pelvis"],
	[&"head", "Neck", "Head", 0.2, 0.11, 5.0, ["Neck", "Head"], &"torso"],
	[&"upper_arm_l", "UpperArm.L", "LowerArm.L", 0.0, 0.05, 2.5, ["UpperArm.L"], &"torso"],
	[&"lower_arm_l", "LowerArm.L", "Wrist.L", 0.12, 0.045, 2.0, ["LowerArm.L"], &"upper_arm_l"],
	[&"upper_arm_r", "UpperArm.R", "LowerArm.R", 0.0, 0.05, 2.5, ["UpperArm.R"], &"torso"],
	[&"lower_arm_r", "LowerArm.R", "Wrist.R", 0.12, 0.045, 2.0, ["LowerArm.R"], &"upper_arm_r"],
	[&"upper_leg_l", "UpperLeg.L", "LowerLeg.L", 0.0, 0.08, 8.0, ["UpperLeg.L"], &"pelvis"],
	[&"lower_leg_l", "LowerLeg.L", "Foot.L", 0.0, 0.065, 4.0, ["LowerLeg.L", "Foot.L"], &"upper_leg_l"],
	[&"upper_leg_r", "UpperLeg.R", "LowerLeg.R", 0.0, 0.08, 8.0, ["UpperLeg.R"], &"pelvis"],
	[&"lower_leg_r", "LowerLeg.R", "Foot.R", 0.0, 0.065, 4.0, ["LowerLeg.R", "Foot.R"], &"upper_leg_r"],
]

var bodies := {}


## Builds the ragdoll from the skeleton's current pose and hands the bone mapping to [param modifier].
## [param velocity] is the character's speed at death; [param impulse] is applied at [param at].
static func spawn(visual: Node3D, skeleton: Skeleton3D, modifier: CharacterPoseModifier, velocity := Vector3.ZERO, impulse := Vector3.ZERO, at := Vector3.INF) -> Ragdoll:
	var ragdoll := Ragdoll.new()
	ragdoll.name = "Ragdoll"
	ragdoll.top_level = true
	visual.add_child(ragdoll)
	ragdoll.global_transform = Transform3D.IDENTITY
	var world := skeleton.global_transform
	var mapping := {}
	for segment: Array in SEGMENTS:
		var from_bone := skeleton.find_bone(segment[1])
		var to_bone := skeleton.find_bone(segment[2])
		if from_bone < 0 or to_bone < 0:
			continue
		var start := world * skeleton.get_bone_global_pose(from_bone).origin
		var end := world * skeleton.get_bone_global_pose(to_bone).origin
		var axis := (end - start).normalized() if start.distance_to(end) > 0.001 else Vector3.UP
		end += axis * float(segment[3])
		var radius: float = segment[4]
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = maxf(start.distance_to(end), radius * 2.0 + 0.01)
		var body := RigidBody3D.new()
		body.name = String(segment[0])
		body.collision_layer = LAYER
		body.collision_mask = MASK
		body.mass = segment[5]
		body.linear_damp = 0.1
		body.angular_damp = 3.0
		body.add_to_group("ragdoll_parts")
		var shape := CollisionShape3D.new()
		shape.shape = capsule
		body.add_child(shape)
		ragdoll.add_child(body)
		body.global_transform = Transform3D(_basis_along(axis), (start + end) * 0.5 + Vector3.UP * 0.04)
		body.linear_velocity = velocity
		ragdoll.bodies[segment[0]] = body
		for bone_name: String in segment[6]:
			var bone := skeleton.find_bone(bone_name)
			if bone >= 0:
				mapping[bone] = [body, body.global_transform.affine_inverse() * world * skeleton.get_bone_global_pose(bone)]
		var parent: RigidBody3D = ragdoll.bodies.get(segment[7])
		if parent != null:
			var joint := ConeTwistJoint3D.new()
			ragdoll.add_child(joint)
			joint.global_transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, axis)), start)
			joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(55.0))
			joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(25.0))
			joint.node_a = joint.get_path_to(parent)
			joint.node_b = joint.get_path_to(body)
	modifier.ragdoll = mapping
	if impulse != Vector3.ZERO:
		ragdoll.push(impulse, at)
	ragdoll.get_tree().create_timer(SETTLE_TIME, false).timeout.connect(ragdoll.settle)
	return ragdoll


## Velocity is changed directly: impulses on bodies spawned this frame ignore their mass.
## Pushes the whole body by [param impulse] (split by mass), with extra on the part nearest
## [param at] so it twists the way the hit came from; light limbs are capped so they don't fly off.
func push(impulse: Vector3, at := Vector3.INF) -> void:
	var nearest: RigidBody3D = null
	if at != Vector3.INF:
		var best := INF
		for body: RigidBody3D in bodies.values():
			var distance := body.global_position.distance_to(at)
			if distance < best:
				best = distance
				nearest = body
	var total := 0.0
	for body: RigidBody3D in bodies.values():
		total += body.mass
	for body: RigidBody3D in bodies.values():
		body.freeze = false
		body.linear_velocity += impulse * 0.4 / maxf(total, 0.001)
	# The rest goes in at the hit (the chest when unknown) so the body topples rather than slides.
	if nearest == null:
		nearest = bodies.get(&"torso")
	if nearest != null:
		nearest.linear_velocity += (impulse * 0.6 / nearest.mass).limit_length(5.0)
	if is_inside_tree():
		get_tree().create_timer(SETTLE_TIME, false).timeout.connect(settle)


## If [param body] is a ragdoll part, pushes its whole ragdoll and returns true.
static func push_part(body: Object, impulse: Vector3, at := Vector3.INF) -> bool:
	var part := body as Node
	if part == null or not part.is_in_group("ragdoll_parts"):
		return false
	var ragdoll := part.get_parent() as Ragdoll
	if ragdoll != null:
		ragdoll.push(impulse, at)
	return true


func settle() -> void:
	for body: RigidBody3D in bodies.values():
		if is_instance_valid(body):
			body.freeze = true


static func _basis_along(axis: Vector3) -> Basis:
	var side := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, axis, side.cross(axis).normalized()).orthonormalized()
