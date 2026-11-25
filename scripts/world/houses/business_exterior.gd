@tool
class_name BusinessExterior
extends Node3D
## Root of a stand-in business scene (scenes/businesses/). Same lot convention as HouseExterior:
## origin at the centre of the front property line, street toward +Z, lot spans
## x in [-lot_size.x / 2, lot_size.x / 2] and z in [-lot_size.y, 0].
##
## "Lot" is the paving/parking combiner and "Building" the CSG shell with static collision.
## Closed stand-ins are solid. Shops ([member enterable]) have a real doorway into an empty
## interior shell, an "Entrance" Marker3D just outside the door and a "ShopCounter"
## Interactable inside (no actions yet; the shop system attaches them by [member shop_type]).

@export var business_id := ""
@export var display_name := ""
## Census design archetype this building fills (storefront_1f, mixed_use_2f, industrial_shed, ...).
@export var archetype := ""
## Matches data/business_types/<shop_type>.tres when there is one (or e.g. "clothing_store").
@export var shop_type := ""
## True for shops the player walks into to buy things.
@export var enterable := false
@export_range(1, 8) var floors := 1
@export var footprint := Vector2(12, 12)
@export var lot_size := Vector2(16, 24)
@export var lot_type := ""
@export var show_label := false:
	set(value):
		show_label = value
		_update_label()

## Seeded West Palm Beach dressing (palms, brush, beds, yard clutter, window units, wear); 0 = none.
## See [KitDressing]. The tier comes from the generator's dress_tier metadata unless overridden.
@export var dress_seed := 0:
	set(value):
		dress_seed = value
		_redress()
@export_enum("auto", "low", "medium", "high", "commercial", "civic") var dress_tier := "auto":
	set(value):
		dress_tier = value
		_redress()
## Set by KitPlacement when the building is mirrored so the dressing follows it.
var dress_mirrored := false

## Extra label line set at runtime (e.g. the variant seed by KitPlacement).
var label_note := "":
	set(value):
		label_note = value
		_update_label()
var _label: Label3D


func _ready() -> void:
	_update_label()
	_redress()


func _redress() -> void:
	if is_inside_tree():
		KitDressing.apply(self, dress_seed, dress_tier, dress_mirrored)


func lot_rect() -> Rect2:
	return Rect2(-lot_size.x * 0.5, -lot_size.y, lot_size.x, lot_size.y)


func label() -> String:
	return display_name


func entrance() -> Marker3D:
	return get_node_or_null("Entrance") as Marker3D


func counter() -> Interactable:
	return get_node_or_null("ShopCounter") as Interactable


func info_text() -> String:
	var kind := "SHOP (enter) - %s" % shop_type if enterable else "Closed stand-in"
	return "%s  %s\n%s - %s\n%d floor%s - Building %.0f x %.0f m - Lot %.0f x %.0f m\n%s" % [
		business_id, display_name, kind, archetype, floors, "" if floors == 1 else "s",
		footprint.x, footprint.y, lot_size.x, lot_size.y, lot_type]


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
		_label.modulate = Color(0.75, 0.95, 1.0) if enterable else Color(1, 0.8, 0.7)
		add_child(_label, false, Node.INTERNAL_MODE_BACK)
	_label.text = info_text() if label_note.is_empty() else info_text() + "\n" + label_note
	_label.position = Vector3(0, 3.2, 1.0)
