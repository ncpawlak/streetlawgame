class_name AppearanceRig
extends Node
## Applies an [Appearance] to a [CharacterVisual] (created by CharacterVisual.apply_appearance).
## Clothes and hairstyles swap the Body / Legs / Feet / Head part meshes in from other Quaternius
## models (they all share one 62-bone rig, so a part skinned for one model deforms on any other).
## Colours are material overrides: clothing tint materials take the variant colour, hair materials
## the dye colour and every Skin* material the look's skin tone (models ship different skins).
## Hats, accessories and facial hair are procedural greybox meshes that follow a bone.

const PARTS: Array[StringName] = [&"Body", &"Legs", &"Feet", &"Head"]
## Mesh name suffixes per part (Farmer calls its legs "Pants").
const PART_SUFFIXES := {&"Body": ["_Body"], &"Legs": ["_Legs", "_Pants"], &"Feet": ["_Feet"], &"Head": ["_Head"]}
## Which slot dresses which part.
const PART_SLOTS := {&"Body": &"top", &"Legs": &"bottom", &"Feet": &"shoes", &"Head": &"hair"}
## Hair materials of an un-swapped head (any material whose name starts with one of these).
const DEFAULT_HAIR_PREFIXES: Array[String] = ["Hair"]
const DARK := Color(0.08, 0.08, 0.09)
const GOLD := Color(0.95, 0.75, 0.25)
## Procedural attachments. Each piece: shape (box / cylinder / sphere / torus), size, offset in
## metres in the bone's frame (x = side, y = up the bone, z = towards the face), rotation in
## degrees and colour source: &"item" (variant colour), &"hair" (dye colour), &"dark" or &"gold".
const ATTACHMENTS := {
	&"cap": [
		{"shape": &"cylinder", "size": Vector3(0.1, 0.07, 0.0), "offset": Vector3(0.0, 0.19, 0.0), "color": &"item"},
		{"shape": &"box", "size": Vector3(0.16, 0.015, 0.1), "offset": Vector3(0.0, 0.162, 0.125), "rotation": Vector3(-8.0, 0.0, 0.0), "color": &"item"},
	],
	&"backwards_cap": [
		{"shape": &"cylinder", "size": Vector3(0.1, 0.07, 0.0), "offset": Vector3(0.0, 0.19, 0.0), "color": &"item"},
		{"shape": &"box", "size": Vector3(0.16, 0.015, 0.1), "offset": Vector3(0.0, 0.165, -0.12), "rotation": Vector3(8.0, 0.0, 0.0), "color": &"item"},
	],
	&"beanie": [
		{"shape": &"cylinder", "size": Vector3(0.1, 0.07, 0.0), "offset": Vector3(0.0, 0.18, 0.0), "color": &"item"},
		{"shape": &"sphere", "size": Vector3(0.1, 0.05, 0.0), "offset": Vector3(0.0, 0.215, 0.0), "color": &"item"},
	],
	&"bandana": [
		{"shape": &"box", "size": Vector3(0.19, 0.04, 0.2), "offset": Vector3(0.0, 0.165, 0.0), "color": &"item"},
	],
	&"sunglasses": [
		{"shape": &"box", "size": Vector3(0.2, 0.045, 0.03), "offset": Vector3(0.0, 0.145, 0.125), "color": &"item"},
	],
	&"chain": [
		{"shape": &"torus", "size": Vector3(0.1, 0.115, 0.0), "offset": Vector3(0.0, -0.03, 0.03), "rotation": Vector3(-25.0, 0.0, 0.0), "color": &"item", "bone": &"Neck"},
	],
	&"goatee": [
		{"shape": &"box", "size": Vector3(0.05, 0.06, 0.035), "offset": Vector3(0.0, 0.035, 0.115), "color": &"hair"},
	],
	&"moustache": [
		{"shape": &"box", "size": Vector3(0.09, 0.022, 0.025), "offset": Vector3(0.0, 0.085, 0.13), "color": &"hair"},
	],
	&"beard": [
		{"shape": &"box", "size": Vector3(0.14, 0.07, 0.07), "offset": Vector3(0.0, 0.05, 0.085), "color": &"hair"},
		{"shape": &"box", "size": Vector3(0.09, 0.022, 0.025), "offset": Vector3(0.0, 0.09, 0.13), "color": &"hair"},
	],
}

## model id -> {part -> {"mesh", "skin", "name"}} (meshes pulled out of the source .glb once).
static var _part_cache := {}

var visual: CharacterVisual
var look: Appearance

## part -> the model's own MeshInstance3D.
var _base_parts := {}
## part -> MeshInstance3D swapped in from another model.
var _swapped := {}
var _attachments: Array[Dictionary] = []


static func for_visual(target: CharacterVisual) -> AppearanceRig:
	var rig := target.get_node_or_null("AppearanceRig") as AppearanceRig
	if rig == null:
		rig = AppearanceRig.new()
		rig.name = "AppearanceRig"
		rig.visual = target
		rig._index_base_parts()
		target.add_child(rig)
		target.skeleton.skeleton_updated.connect(rig._place_attachments)
	return rig


func apply(new_look: Appearance) -> void:
	look = new_look.copy() if new_look != null else Appearance.new()
	for part in PARTS:
		_dress_part(part)
	_rebuild_attachments()
	var meshes: Array[MeshInstance3D] = []
	for part in PARTS:
		var mesh := active_part(part)
		if mesh != null:
			meshes.append(mesh)
	visual.set_part_meshes(meshes)


## The mesh currently shown for [param part] (swapped or the model's own).
func active_part(part: StringName) -> MeshInstance3D:
	var swapped := _swapped.get(part) as MeshInstance3D
	if swapped != null and is_instance_valid(swapped):
		return swapped
	return _base_parts.get(part) as MeshInstance3D


## Source model currently providing [param part] (the visual's own model if not swapped).
func part_source(part: StringName) -> StringName:
	return StringName((_swapped[part] as MeshInstance3D).get_meta(&"source_model")) if _swapped.has(part) else visual.model_id


func attachment_nodes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for entry in _attachments:
		result.append(entry["node"])
	return result


func _index_base_parts() -> void:
	for mesh: MeshInstance3D in visual.skeleton.find_children("*", "MeshInstance3D", false, false):
		var part := _part_of(mesh.name)
		if part != &"":
			_base_parts[part] = mesh


static func _part_of(mesh_name: String) -> StringName:
	for part: StringName in PART_SUFFIXES:
		for suffix: String in PART_SUFFIXES[part]:
			if mesh_name.ends_with(suffix):
				return part
	return &""


func _dress_part(part: StringName) -> void:
	var slot: StringName = PART_SLOTS[part]
	var item := look.item_def(slot)
	var source: StringName = &""
	if item is ClothingItemDef and (item as ClothingItemDef).part == part:
		source = (item as ClothingItemDef).source_model
	elif item is HairItemDef:
		source = (item as HairItemDef).source_model
	var old := _swapped.get(part) as MeshInstance3D
	if old != null and (source == &"" or source == visual.model_id or StringName(old.get_meta(&"source_model")) != source):
		old.queue_free()
		old.get_parent().remove_child(old)
		_swapped.erase(part)
	var base := _base_parts.get(part) as MeshInstance3D
	if source != &"" and source != visual.model_id and not _swapped.has(part):
		var data := _source_part(source, part)
		if not data.is_empty():
			var mesh := MeshInstance3D.new()
			mesh.name = "%s_%s" % [part, source]
			mesh.mesh = data["mesh"]
			mesh.skin = data["skin"]
			mesh.set_meta(&"source_model", source)
			visual.skeleton.add_child(mesh)
			mesh.skeleton = NodePath("..")
			_swapped[part] = mesh
	if base != null:
		base.visible = not _swapped.has(part)
	_color_part(part, item)


func _color_part(part: StringName, item: AppearanceItemDef) -> void:
	var mesh := active_part(part)
	if mesh == null:
		return
	var tint_names: Array[StringName] = []
	var tint: Variant = null
	var hair_names: Array[StringName] = []
	var hair_color: Variant = _hair_color()
	var shaved := false
	if item is ClothingItemDef and (item as ClothingItemDef).part == part:
		tint_names = (item as ClothingItemDef).tint_materials
		tint = item.color_at(look.get_color(item.slot))
	if part == &"Head":
		var hair := item as HairItemDef
		if hair != null and not hair.hair_materials.is_empty():
			hair_names = hair.hair_materials
		shaved = hair != null and hair.shaved
	for i in mesh.mesh.get_surface_count():
		var base := mesh.mesh.surface_get_material(i) as BaseMaterial3D
		if base == null:
			mesh.set_surface_override_material(i, null)
			continue
		var material_name := StringName(base.resource_name)
		var color: Variant = null
		if String(material_name).begins_with("Skin"):
			color = look.skin_tone.darkened(0.12) if material_name != &"Skin" else look.skin_tone
		elif part == &"Head" and _is_hair_material(material_name, hair_names):
			color = look.skin_tone.darkened(0.08) if shaved else hair_color
		elif tint != null and tint_names.has(material_name):
			color = tint
		if color == null:
			mesh.set_surface_override_material(i, null)
		else:
			var material := base.duplicate() as BaseMaterial3D
			material.albedo_color = color
			mesh.set_surface_override_material(i, material)


static func _is_hair_material(material_name: StringName, hair_names: Array[StringName]) -> bool:
	if not hair_names.is_empty():
		return hair_names.has(material_name)
	for prefix in DEFAULT_HAIR_PREFIXES:
		if String(material_name).begins_with(prefix):
			return true
	return false


func _hair_color() -> Variant:
	var dye := look.item_def(&"hair_color")
	return dye.color_at(look.get_color(&"hair_color")) if dye != null else null


func _rebuild_attachments() -> void:
	for entry in _attachments:
		(entry["node"] as Node).queue_free()
	_attachments.clear()
	for slot: StringName in [&"hat", &"accessory", &"facial_hair"]:
		var item := look.item_def(slot)
		var attachment_id: StringName = &""
		if item is ClothingItemDef:
			attachment_id = (item as ClothingItemDef).attachment
		elif item is HairItemDef:
			attachment_id = (item as HairItemDef).attachment
		if attachment_id == &"":
			continue
		var item_color: Variant = item.color_at(look.get_color(slot))
		for piece: Dictionary in ATTACHMENTS[attachment_id]:
			_add_piece(slot, piece, item_color)
	_place_attachments()


func _add_piece(slot: StringName, piece: Dictionary, item_color: Variant) -> void:
	var size: Vector3 = piece["size"]
	var mesh: Mesh
	match piece["shape"]:
		&"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x
			cylinder.bottom_radius = size.x
			cylinder.height = size.y
			mesh = cylinder
		&"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = size.x
			sphere.height = size.y * 2.0
			sphere.is_hemisphere = true
			mesh = sphere
		&"torus":
			var torus := TorusMesh.new()
			torus.inner_radius = size.x
			torus.outer_radius = size.y
			mesh = torus
		_:
			var box := BoxMesh.new()
			box.size = size
			mesh = box
	var material := StandardMaterial3D.new()
	var color: Variant = null
	match piece.get("color", &"item"):
		&"item":
			color = item_color
		&"hair":
			color = _hair_color()
		&"gold":
			color = GOLD
	material.albedo_color = color if color != null else DARK
	if piece.get("color") == &"gold" or (item_color != null and slot == &"accessory" and piece["shape"] == &"torus"):
		material.metallic = 0.8
		material.roughness = 0.3
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.name = "%s_%s" % [slot, piece["shape"]]
	node.mesh = mesh
	node.top_level = true
	visual.add_child(node)
	var rotation_deg: Vector3 = piece.get("rotation", Vector3.ZERO)
	_attachments.append({
		"node": node,
		"bone": visual.skeleton.find_bone(String(piece.get("bone", &"Head"))),
		"offset": piece["offset"],
		"rotation": Basis.from_euler(rotation_deg * (PI / 180.0)),
	})


## Follows the animated pose (connected to Skeleton3D.skeleton_updated).
func _place_attachments() -> void:
	if not is_inside_tree() or _attachments.is_empty():
		return
	var scale := CharacterVisual._shared_scale()
	for entry in _attachments:
		var node := entry["node"] as MeshInstance3D
		if not is_instance_valid(node):
			continue
		var bone := skeleton_pose(entry["bone"])
		var frame := bone.basis.orthonormalized()
		var offset: Vector3 = entry["offset"]
		node.global_transform = Transform3D(frame * (entry["rotation"] as Basis) * Basis.from_scale(Vector3.ONE * scale),
			bone.origin + frame * offset * scale)


func skeleton_pose(bone: int) -> Transform3D:
	return visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(bone)


static func _source_part(model_id: StringName, part: StringName) -> Dictionary:
	if not _part_cache.has(model_id):
		var parts := {}
		var scene := load(CharacterVisual.MODEL_PATH % model_id) as PackedScene
		if scene != null:
			var root := scene.instantiate()
			for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				var found := _part_of(mesh.name)
				if found != &"":
					parts[found] = {"mesh": mesh.mesh, "skin": mesh.skin, "name": mesh.name}
			root.free()
		_part_cache[model_id] = parts
	return (_part_cache[model_id] as Dictionary).get(part, {})
