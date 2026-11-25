class_name HighwayRoute
extends Node3D
## A closed stadium-shaped highway loop (a stretch of I-59 that wraps around) built in code: flat
## ground, a two-lane road with edge and centre lines, and roadside buildings for cover.
## [method sample] gives a local transform (+Z = direction of travel) at a distance along the loop.

@export var straight_length := 360.0
@export var turn_radius := 70.0
@export var road_width := 26.0  # SCALE.md highway width
@export var ground_size := Vector2(1100.0, 600.0)
@export var building_seed := 59

var curve: Curve3D


func _ready() -> void:
	curve = _build_curve()
	_build_ground()
	_build_road()
	_build_buildings()


func length() -> float:
	return curve.get_baked_length()


## Local transform at [param distance] along the loop, facing along the road (+Z), shifted
## [param lateral] metres to the right of the centre line.
func sample(distance: float, lateral := 0.0) -> Transform3D:
	var total := length()
	var d := fposmod(distance, total)
	var point := curve.sample_baked(d)
	var forward := curve.sample_baked(fposmod(d + 2.0, total)) - point
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.BACK
	var right := forward.cross(Vector3.UP).normalized()
	return Transform3D(Basis.looking_at(-forward, Vector3.UP), point + right * lateral)


func global_sample(distance: float, lateral := 0.0) -> Transform3D:
	return global_transform * sample(distance, lateral)


## Distance along the loop closest to a global position.
func closest_distance(global_point: Vector3) -> float:
	return curve.get_closest_offset(to_local(global_point))


func _build_curve() -> Curve3D:
	var result := Curve3D.new()
	result.bake_interval = 0.5
	var half := straight_length * 0.5
	var step := 6.0
	var x := -half
	while x < half:
		result.add_point(Vector3(x, 0.0, turn_radius))
		x += step
	_add_arc(result, Vector3(half, 0.0, 0.0), PI * 0.5, -PI * 0.5)
	x = half
	while x > -half:
		result.add_point(Vector3(x, 0.0, -turn_radius))
		x -= step
	_add_arc(result, Vector3(-half, 0.0, 0.0), -PI * 0.5, -PI * 1.5)
	result.add_point(result.get_point_position(0))
	return result


func _add_arc(target: Curve3D, center: Vector3, from_angle: float, to_angle: float) -> void:
	var segments := 24
	for i in segments:
		var angle := lerpf(from_angle, to_angle, float(i) / segments)
		target.add_point(center + Vector3(cos(angle), 0.0, sin(angle)) * turn_radius)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ground_size.x, 1.0, ground_size.y)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	var mesh := PlaneMesh.new()
	mesh.size = ground_size
	mesh.material = _material(Color(0.36, 0.42, 0.26))
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	add_child(body)


func _build_road() -> void:
	var half_width := road_width * 0.5
	_add_ribbon(-half_width, half_width, 0.02, Color(0.17, 0.17, 0.18))
	_add_ribbon(half_width - 0.5, half_width - 0.3, 0.03, Color(0.9, 0.9, 0.9))
	_add_ribbon(-half_width + 0.3, -half_width + 0.5, 0.03, Color(0.9, 0.9, 0.9))
	_add_ribbon(-0.15, 0.15, 0.03, Color(0.95, 0.8, 0.2))
	var sign := Label3D.new()
	sign.text = "I-59"
	sign.font_size = 256
	sign.modulate = Color(0.3, 0.55, 1.0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0.0, 9.0, turn_radius + half_width + 6.0)
	add_child(sign)


func _add_ribbon(from_lateral: float, to_lateral: float, height: float, color: Color) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total := length()
	var step := 2.0
	var count := int(ceil(total / step))
	for i in count:
		var a := sample(i * step)
		var b := sample(minf((i + 1) * step, total - 0.01))
		var a_right := -a.basis.x
		var b_right := -b.basis.x
		var quad: Array[Vector3] = [
			a.origin + a_right * from_lateral, a.origin + a_right * to_lateral,
			b.origin + b_right * from_lateral, b.origin + b_right * to_lateral,
		]
		for index in [0, 2, 1, 1, 2, 3]:
			tool.set_normal(Vector3.UP)
			tool.add_vertex(quad[index] + Vector3(0.0, height, 0.0))
	var mesh := tool.commit()
	mesh.surface_set_material(0, _material(color, true))
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)


## Warehouses around the loop so there's something to break line of sight with the cops.
func _build_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = building_seed
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 400:
		tries += 1
		var at := Vector3(rng.randf_range(-ground_size.x * 0.45, ground_size.x * 0.45), 0.0, rng.randf_range(-ground_size.y * 0.45, ground_size.y * 0.45))
		var size := Vector3(rng.randf_range(10.0, 26.0), rng.randf_range(5.0, 14.0), rng.randf_range(10.0, 22.0))
		if at.distance_to(curve.get_closest_point(at)) < road_width * 0.5 + maxf(size.x, size.z) * 0.75 + 6.0:
			continue
		if at.length() < 40.0:
			continue
		_add_block(at, size, Color(0.45, 0.42, 0.4).lerp(Color(0.62, 0.5, 0.42), rng.randf()))
		placed += 1


func _add_block(at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at + Vector3(0.0, size.y * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	add_child(body)


func _material(color: Color, double_sided := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
