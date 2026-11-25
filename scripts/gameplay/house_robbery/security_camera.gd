class_name SecurityCamera
extends StaticBody3D
## A wall-mounted CCTV camera. [method can_see] checks its view cone, range and line of sight; the
## [House] trips the alarm when a camera sees a burglar. Ways to blind it:
## - shoot it (a gunshot, so the neighbours still hear it),
## - spray-paint the lens (quiet, needs a [constant HitTools.SPRAY_PAINT] can; reach up from below),
## - cut the house's power at the breaker box ([member powered], temporary),
## - unplug the recorder inside ([member feed_cut], for the rest of the hit; erases footage).

signal destroyed(camera: SecurityCamera)
signal state_changed(camera: SecurityCamera)

@export var view_range := 14.0
## Full cone angle in degrees.
@export var fov := 80.0
## Look direction: yaw (0 = +Z) and pitch (negative = down), degrees.
@export var yaw := 0.0
@export var pitch := -35.0
@export var health := 15.0

var broken := false
var sprayed := false
## False while the house power is cut.
var powered := true
## True once the recorder (DVR) has been unplugged.
var feed_cut := false
var interactable: Interactable
var _lens_material: StandardMaterial3D
var _cone: MeshInstance3D
var _marker: Label3D


func _ready() -> void:
	add_to_group("security_cameras")
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 0.25, 0.4)
	shape.shape = box
	add_child(shape)

	var head := Node3D.new()
	head.rotation_order = EULER_ORDER_YXZ
	head.rotation = Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0.0)
	add_child(head)
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.22, 0.2, 0.38)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.85, 0.85, 0.88)
	body_mesh.material = body_material
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	head.add_child(body)
	var lens_mesh := SphereMesh.new()
	lens_mesh.radius = 0.06
	lens_mesh.height = 0.12
	_lens_material = StandardMaterial3D.new()
	_lens_material.albedo_color = Color(0.9, 0.1, 0.1)
	_lens_material.emission_enabled = true
	_lens_material.emission = Color(1.0, 0.1, 0.1)
	_lens_material.emission_energy_multiplier = 3.0
	lens_mesh.material = _lens_material
	var lens := MeshInstance3D.new()
	lens.mesh = lens_mesh
	lens.position = Vector3(0.0, 0.0, 0.2)
	head.add_child(lens)

	# Short translucent cone so players can read where it's looking.
	var cone_length := 3.0
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = tan(deg_to_rad(fov * 0.5)) * cone_length
	cone_mesh.height = cone_length
	cone_mesh.radial_segments = 16
	cone_mesh.cap_top = false
	cone_mesh.cap_bottom = false
	var cone_material := StandardMaterial3D.new()
	cone_material.albedo_color = Color(1.0, 0.2, 0.15, 0.12)
	cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone_mesh.material = cone_material
	_cone = MeshInstance3D.new()
	_cone.mesh = cone_mesh
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cone.rotation.x = -PI / 2.0
	_cone.position = Vector3(0.0, 0.0, 0.2 + cone_length * 0.5)
	head.add_child(_cone)

	_marker = Label3D.new()
	_marker.text = "CAM"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.fixed_size = true
	_marker.pixel_size = 0.0015
	_marker.font_size = 28
	_marker.outline_size = 6
	_marker.modulate = Color(1.0, 0.35, 0.3)
	_marker.position.y = 0.4
	_marker.visible = false
	add_child(_marker)

	interactable = Interactable.new()
	interactable.prompt_name = "camera"
	interactable.radius = 1.6
	interactable.position = Vector3(0.0, -1.6, 0.0)
	var effect := MethodEffect.create(&"spray")
	effect.pass_actor = true
	var condition := MethodCondition.create(&"can_spray")
	condition.pass_actor = true
	condition.hide_when_unmet = true
	var action := InteractionAction.create(&"spray", "Spray-paint the {target}", [effect], [condition])
	action.duration = 1.0
	action.progress_text = "Spraying..."
	interactable.add_action(action)
	add_child(interactable)


func label() -> String:
	return "Security camera"


func look_direction() -> Vector3:
	return Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0.0), EULER_ORDER_YXZ) * Vector3.BACK


## True when [param target] (a body; aims at its chest) is inside the cone with a clear view.
func can_see(target: Node3D) -> bool:
	if not is_working() or target == null or not is_inside_tree() or not target.is_inside_tree():
		return false
	return can_see_point(target.global_position + Vector3(0.0, 1.0, 0.0), [target])


## Watching and recording: not shot, sprayed, powered down or cut off from the recorder.
func is_working() -> bool:
	return not broken and not sprayed and powered and not feed_cut


func can_see_point(point: Vector3, exclude: Array = []) -> bool:
	if not is_working():
		return false
	var eye := global_position
	var to_point := point - eye
	var distance := to_point.length()
	if distance > view_range or distance < 0.01:
		return false
	if rad_to_deg(look_direction().angle_to(to_point)) > fov * 0.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, point, 1)
	var rids: Array[RID] = [get_rid()]
	for node: Variant in exclude:
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
	query.exclude = rids
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func set_marker_visible(show: bool) -> void:
	if _marker != null:
		_marker.visible = show and is_working()


func can_spray(actor: Node) -> bool:
	var tools := HitTools.of(actor, false)
	return not broken and not sprayed and tools != null and tools.has(HitTools.SPRAY_PAINT)


## Paints over the lens (quiet). Uses one spray can.
func spray(actor: Node) -> void:
	if not can_spray(actor) or not HitTools.of(actor).use(HitTools.SPRAY_PAINT):
		return
	sprayed = true
	EventBus.notify.emit("Camera lens painted over")
	_refresh()


func set_powered(value: bool) -> void:
	powered = value
	_refresh()


func set_feed_cut(value: bool) -> void:
	feed_cut = value
	_refresh()


func _refresh() -> void:
	if _lens_material == null:
		return
	var working := is_working()
	_lens_material.emission_enabled = working
	if not broken:
		_lens_material.albedo_color = Color(0.9, 0.1, 0.1) if working else (Color(0.1, 0.1, 0.1) if sprayed else Color(0.35, 0.12, 0.12))
	_cone.visible = working
	if not working:
		_marker.visible = false
	state_changed.emit(self)


func take_damage(amount: float, _source: Node = null) -> void:
	if broken:
		return
	health -= amount
	if health > 0.0:
		return
	broken = true
	_lens_material.emission_enabled = false
	_lens_material.albedo_color = Color(0.15, 0.15, 0.15)
	_cone.visible = false
	_marker.visible = false
	EventBus.notify.emit("Camera knocked out")
	destroyed.emit(self)
