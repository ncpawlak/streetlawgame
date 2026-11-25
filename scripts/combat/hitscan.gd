class_name Hitscan
extends RefCounted
## Shared instant-hit weapon logic used by the player, vehicles (drive-bys) and NPCs.

const TRACER_LIFETIME := 0.06


## Fires one shot (one ray per pellet) from [param muzzle] toward [param direction], applying
## spread and damage. Anything hit that has a take_damage(amount, source) method is damaged, and
## characters bleed (see BloodFx).
## Returns how many pellets hit something damageable.
static func fire(shooter: Node3D, muzzle: Vector3, direction: Vector3, weapon: WeaponData, exclude: Array[RID] = [], damage_scale := 1.0, extra_spread := 0.0) -> int:
	var space := shooter.get_world_3d().direct_space_state
	var hits := 0
	for pellet in maxi(1, weapon.pellets):
		var aim := _apply_spread(direction.normalized(), weapon.spread_degrees + extra_spread)
		var target := muzzle + aim * weapon.max_range
		var query := PhysicsRayQueryParameters3D.create(muzzle, target)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("take_damage"):
			collider.take_damage(weapon.damage * damage_scale, shooter)
			hits += 1
			if not weapon.is_melee() and collider is Node3D:
				BloodFx.on_hit(collider, hit["position"], aim, hit["normal"])
		if weapon.show_tracer:
			_spawn_tracer(shooter, muzzle, hit.get("position", target), weapon.tracer_color)
	return hits


## Point under the center of [param camera], used to aim third-person shots.
static func camera_aim_point(camera: Camera3D, max_range: float, exclude: Array[RID] = []) -> Vector3:
	var origin := camera.global_position
	var target := origin - camera.global_basis.z * max_range
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = exclude
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position", target)


static func _apply_spread(direction: Vector3, spread_degrees: float) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var spread := deg_to_rad(spread_degrees)
	var result := direction.rotated(Vector3.UP, randf_range(-spread, spread))
	var side := result.cross(Vector3.UP)
	if side.length_squared() > 0.0001:
		result = result.rotated(side.normalized(), randf_range(-spread, spread))
	return result


static func _spawn_tracer(context: Node, from: Vector3, to: Vector3, color: Color) -> void:
	var scene := context.get_tree().current_scene
	if scene == null:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	var tracer := MeshInstance3D.new()
	tracer.mesh = mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.top_level = true
	scene.add_child(tracer)
	context.get_tree().create_timer(TRACER_LIFETIME).timeout.connect(tracer.queue_free)
