@tool
class_name HouseExterior
extends Node3D
## Root of an exterior-only house scene (scenes/houses/). The scene holds the whole lot:
## the "Lot" combiner (yard, driveway, walks), the "House" combiner (solid CSG shell with
## static collision; doors and windows are recesses, so it can't be entered), plus fences and
## landscaping. Lot convention: origin at the centre of the front property line, the street is
## toward +Z, the lot spans x in [-lot_size.x / 2, lot_size.x / 2] and z in [-lot_size.y, 0].
## Bed/bath counts only describe the massing; there is no interior.

@export var house_id := ""
@export var display_name := ""
@export_range(1, 2) var floors := 1
@export_range(1, 6) var bedrooms := 2
@export_range(1.0, 4.0, 0.5) var bathrooms := 1.0
## House footprint bounding box (x = width along the street, y = depth), metres.
@export var footprint := Vector2(10, 8)
## Lot size (x = frontage, y = depth), metres. North End lots are ~12 x 17-29 and ~17-19 x 23-29.
@export var lot_size := Vector2(12, 20)
## How the house sits on its lot, e.g. "small house, big yard".
@export var lot_type := ""
## Census design archetype this house fills (house_1f_small_yard, trailer_1f, trap_house_the_spot, ...).
## Empty for the generic houses; data/buildings/building_kit.json maps archetypes to scenes.
@export var archetype := ""
## Shows a floating info sign (used by the showcase street).
@export var show_label := false:
	set(value):
		show_label = value
		_update_label()

## Extra label line set at runtime (e.g. the variant seed by KitPlacement).
var label_note := "":
	set(value):
		label_note = value
		_update_label()
var _label: Label3D


func _ready() -> void:
	_update_label()


func lot_rect() -> Rect2:
	return Rect2(-lot_size.x * 0.5, -lot_size.y, lot_size.x, lot_size.y)


func info_text() -> String:
	var baths := str(int(bathrooms)) if is_equal_approx(bathrooms, floorf(bathrooms)) else str(bathrooms)
	var text := "%s  %s\n%d floor%s - %d bed / %s bath\nHouse %.1f x %.1f m - Lot %.0f x %.0f m\n%s" % [
		house_id, display_name, floors, "" if floors == 1 else "s", bedrooms, baths,
		footprint.x, footprint.y, lot_size.x, lot_size.y, lot_type]
	return text if archetype.is_empty() else text + "\n[%s]" % archetype


func _update_label() -> void:
	if not is_inside_tree():
		return
	if not show_label:
		if _label:
			_label.queue_free()
			_label = null
		return
	if not _label:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_label.font_size = 40
		_label.outline_size = 10
		_label.pixel_size = 0.008
		_label.modulate = Color(1, 0.95, 0.7)
		add_child(_label, false, Node.INTERNAL_MODE_BACK)
	_label.text = info_text() if label_note.is_empty() else info_text() + "\n" + label_note
	_label.position = Vector3(0, 3.2, 1.0)
