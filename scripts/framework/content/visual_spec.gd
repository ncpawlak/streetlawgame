class_name VisualSpec
extends Resource
## Swappable visual for any piece of content. Resolution order: [member scene_path] -> [member mesh_path]
## -> a greybox primitive built in code. Paths go through ContentDB.load_asset, so a mod or art drop that
## ships the same path replaces the visual. A missing asset falls back to the greybox and never crashes.

@export_file("*.tscn", "*.scn", "*.glb", "*.gltf") var scene_path := ""
@export_file("*.tres", "*.res", "*.mesh", "*.obj") var mesh_path := ""
## &"box", &"capsule" (x = diameter, y = height) or &"cylinder".
@export var greybox_shape: StringName = &"box"
@export var greybox_size := Vector3.ONE
@export var greybox_color := Color(0.6, 0.6, 0.6)
@export var offset := Vector3.ZERO
@export var visual_scale := Vector3.ONE

static var _materials := {}


static func make(shape: StringName, size: Vector3, color: Color, at: Vector3 = Vector3.ZERO) -> VisualSpec:
	var spec := VisualSpec.new()
	spec.greybox_shape = shape
	spec.greybox_size = size
	spec.greybox_color = color
	spec.offset = at
	return spec


## A new node for this visual. The caller adds it to the tree.
func instantiate() -> Node3D:
	var node: Node3D = null
	if scene_path != "":
		var scene := ContentDB.load_asset(scene_path) as PackedScene
		if scene != null:
			node = scene.instantiate() as Node3D
	if node == null and mesh_path != "":
		var mesh := ContentDB.load_asset(mesh_path) as Mesh
		if mesh != null:
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			node = instance
	if node == null:
		node = greybox(greybox_shape, greybox_size, greybox_color)
	node.position += offset
	node.scale = visual_scale
	return node


func uses_greybox() -> bool:
	return scene_path == "" and mesh_path == ""


static func greybox(shape: StringName, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh: PrimitiveMesh
	match shape:
		&"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = size.x * 0.5
			capsule.height = size.y
			mesh = capsule
		&"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x * 0.5
			cylinder.bottom_radius = size.x * 0.5
			cylinder.height = size.y
			mesh = cylinder
		_:
			var box := BoxMesh.new()
			box.size = size
			mesh = box
	mesh.material = material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance


## Shared material per color so greybox content doesn't create one material per instance.
static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var created := StandardMaterial3D.new()
		created.albedo_color = color
		_materials[key] = created
	return _materials[key]
