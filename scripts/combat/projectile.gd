class_name Projectile
extends Node3D
## A thrown or fired explosive in flight: grenades bounce until their fuse runs out, molotovs and
## rockets burst on impact, and C4 sticks to whatever it hits until detonated.

## Safety net so stray projectiles don't live forever.
const MAX_LIFETIME := 20.0
const BOUNCE_DAMPING := 0.4
const COLLISION_MASK := 1 | 2 | 4 | 8

var weapon: WeaponData
var shooter: Node3D
var velocity := Vector3.ZERO
var exclude: Array[RID] = []
var is_stuck := false

var _fuse_left := 0.0
var _age := 0.0
var _detonated := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _blink_light: OmniLight3D


static func launch(from_shooter: Node3D, data: WeaponData, from: Vector3, direction: Vector3, ignore: Array[RID] = []) -> Projectile:
	var projectile := Projectile.new()
	projectile.weapon = data
	projectile.shooter = from_shooter
	projectile.exclude = ignore
	var aim := direction.normalized()
	projectile.velocity = aim * data.projectile_speed
	if data.thrown:
		projectile.velocity += Vector3.UP * data.projectile_speed * 0.25
	projectile.position = from
	var scene := from_shooter.get_tree().current_scene
	(scene if scene else from_shooter.get_tree().root).add_child(projectile)
	if aim.length_squared() > 0.0:
		projectile.look_at(from + aim, Vector3.UP if absf(aim.y) < 0.99 else Vector3.FORWARD)
	return projectile


func _ready() -> void:
	add_to_group("projectiles")
	_fuse_left = weapon.fuse_time
	_build_visual()


func _physics_process(delta: float) -> void:
	_age += delta
	if weapon.fuse_time > 0.0:
		_fuse_left -= delta
		if _fuse_left <= 0.0:
			detonate()
			return
	if _age > MAX_LIFETIME and not weapon.remote_detonated:
		detonate()
		return
	if _blink_light:
		_blink_light.visible = fmod(_age, 0.8) < 0.15
	if is_stuck:
		return

	velocity.y -= _gravity * weapon.projectile_gravity * delta
	var step := velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, COLLISION_MASK)
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		return
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	match weapon.impact:
		WeaponData.Impact.EXPLODE:
			global_position = point
			detonate()
		WeaponData.Impact.STICK:
			_stick(hit["collider"] as Node3D, point, normal)
		WeaponData.Impact.BOUNCE:
			global_position = point + normal * 0.05
			velocity = velocity.bounce(normal) * BOUNCE_DAMPING
			if velocity.length() < 1.0 and normal.y > 0.7:
				velocity = Vector3.ZERO
				is_stuck = true


func detonate() -> void:
	if _detonated:
		return
	_detonated = true
	var at := global_position
	Explosion.detonate(self, at, weapon.blast_radius, weapon.damage, weapon.blast_impulse, shooter)
	if weapon.fire_duration > 0.0:
		FireZone.spawn(self, at, weapon.fire_radius, weapon.fire_duration, weapon.fire_dps, shooter)
	queue_free()


## Attaches to what it hit so C4 rides along on cars.
func _stick(target: Node3D, point: Vector3, normal: Vector3) -> void:
	is_stuck = true
	velocity = Vector3.ZERO
	global_position = point + normal * 0.05
	if target != null and not (target is StaticBody3D):
		reparent.call_deferred(target)


func _build_visual() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = weapon.tracer_color.darkened(0.5)
	material.emission_enabled = true
	material.emission = weapon.tracer_color
	material.emission_energy_multiplier = 0.8
	var mesh: Mesh
	match weapon.impact:
		WeaponData.Impact.STICK:
			var box := BoxMesh.new()
			box.size = Vector3(0.3, 0.12, 0.2)
			mesh = box
		WeaponData.Impact.BOUNCE:
			var sphere := SphereMesh.new()
			sphere.radius = 0.12
			sphere.height = 0.24
			mesh = sphere
		_:
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.08
			capsule.height = 0.5
			mesh = capsule
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	if mesh is CapsuleMesh:
		instance.rotation.x = PI / 2.0
	add_child(instance)

	var light := OmniLight3D.new()
	light.light_color = weapon.tracer_color
	light.omni_range = 2.0 if weapon.thrown else 5.0
	light.light_energy = 1.5
	add_child(light)
	if weapon.remote_detonated:
		_blink_light = light
