class_name ContentDef
extends Resource
## Base class for data-driven content looked up through ContentDB.
## Lives at <content root>/<type>/**/<id>.tres. [member id] must equal the file basename.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var tags: Array[StringName] = []


## Human-readable name, falling back to the id.
func label() -> String:
	return display_name if display_name != "" else String(id).capitalize()


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## Override to report authoring problems. Each entry is one issue; an empty array means valid.
func validate() -> PackedStringArray:
	return PackedStringArray()
