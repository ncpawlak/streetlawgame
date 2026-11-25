@tool
class_name KitProp
extends Node3D
## Root of a generated West Palm Beach prop scene (tools/houses/props.py).
## Origin sits on the ground (or on the wall face, +Z out, for mount "wall"/"window").

@export var prop_id := ""
@export var category := ""
@export var display_name := ""
@export var collides := false
@export var radius := 1.0
@export var mount := "ground"
@export var label_height := 2.0
@export var show_label := false:
	set(value):
		show_label = value
		if is_inside_tree():
			_update_label()


func _ready() -> void:
	_update_label()


func _update_label() -> void:
	var label := get_node_or_null("Label") as Label3D
	if not show_label:
		if label:
			label.queue_free()
		return
	if label == null:
		label = Label3D.new()
		label.name = "Label"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.pixel_size = 0.008
		label.outline_size = 10
		add_child(label, false, Node.INTERNAL_MODE_BACK)
	label.position = Vector3(0, label_height, 0)
	label.text = "%s\n%s%s" % [display_name, category, " | solid" if collides else ""]
