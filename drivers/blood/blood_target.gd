class_name BloodTarget
extends CharacterBody3D
## Passive shooting target for the blood driver. Either a plain greybox capsule or an animated
## CharacterVisual model, standing still or walking back and forth. Takes damage like any NPC,
## so the shared Hitscan -> BloodFx path handles its blood; dies (falls over) at 0 health.

@export var max_health := 100.0
## Use an animated model (CharacterVisual) instead of a capsule mesh.
@export var animated := false
@export var archetype: StringName = &"civilian"
@export var variant := 0
## Walks between its spawn point and spawn + this offset. Zero stands still.
@export var patrol_offset := Vector3.ZERO
@export var walk_speed := 1.6

var health := 0.0
var visual: CharacterVisual
var spawn_transform: Transform3D

var _body_mesh: MeshInstance3D
var _toward_end := true
var _dead := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("blood_targets")
	collision_layer = 4
	collision_mask = 1
	spawn_transform = global_transform
	health = max_health
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	if animated:
		visual = CharacterVisual.create(archetype, variant)
		add_child(visual)
	else:
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.4
		mesh.height = 1.8
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.72, 0.68, 0.6)
		mesh.material = material
		_body_mesh = MeshInstance3D.new()
		_body_mesh.name = "Body"
		_body_mesh.mesh = mesh
		_body_mesh.position.y = 0.9
		add_child(_body_mesh)


func is_alive() -> bool:
	return not _dead


func is_walker() -> bool:
	return patrol_offset != Vector3.ZERO


## Capsule wounds ride the body mesh so they tip over with it (BloodFx uses this when present).
func wound_anchor(_point: Vector3) -> Node3D:
	return _body_mesh if _body_mesh != null else self


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var move := Vector3.ZERO
	if not _dead and is_walker():
		var goal := spawn_transform.origin + (patrol_offset if _toward_end else Vector3.ZERO)
		var offset := goal - global_position
		offset.y = 0.0
		if offset.length() < 0.3:
			_toward_end = not _toward_end
		else:
			move = offset.normalized()
			rotation.y = atan2(-move.x, -move.z)
	velocity.x = move.x * walk_speed
	velocity.z = move.z * walk_speed
	move_and_slide()
	if visual != null:
		visual.update_motion(velocity, delta)


func take_damage(amount: float, _source: Node = null) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0.0:
		_die()
	elif visual != null:
		visual.hit()


## Back to full health at the spawn point.
func respawn() -> void:
	_dead = false
	health = max_health
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	_toward_end = true
	collision_layer = 4
	if visual != null:
		visual.revive()
	else:
		_body_mesh.rotation = Vector3.ZERO
		_body_mesh.position = Vector3(0.0, 0.9, 0.0)


func _die() -> void:
	_dead = true
	collision_layer = 0
	if visual != null:
		visual.die()
	else:
		# The capsule topples backwards onto the ground.
		_body_mesh.rotation.x = PI / 2.0
		_body_mesh.position = Vector3(0.0, 0.4, 0.9)
