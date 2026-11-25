class_name AppearanceStation
extends Interactable
## Where the player changes their look: a clothing-store rack or counter (mode &"clothing"), a
## barber chair (&"barber") or a wardrobe (&"wardrobe", see Wardrobe). Opens the appearance panel
## through OpenAppearanceEffect; [member site_id] prices it at a business site.

const ACTION := &"change_look"

@export_enum("wardrobe", "clothing", "barber") var mode: String = "wardrobe"
## Business site this station belongs to (clothing store / barbershop). Empty = no site pricing.
@export var site_id: StringName
## Where the player stands / sits while it's in use (the preview camera frames them there). Empty
## = in front of this node.
@export var anchor_path: NodePath
## Extra conditions on using it (e.g. only in an owned safehouse).
@export var use_conditions: Array[Condition] = []


func _ready() -> void:
	super()
	if prompt_name == "":
		prompt_name = AppearancePanel.MODE_TITLES.get(StringName(mode), "Change look")
	if find_action(ACTION) == null:
		var open_panel := OpenAppearanceEffect.new()
		open_panel.mode = StringName(mode)
		open_panel.site_id = site_id
		var effects: Array[Effect] = [open_panel]
		add_action(InteractionAction.create(ACTION, AppearancePanel.ACTION_LABELS.get(StringName(mode), "Change look"),
			effects, use_conditions))


## Where the player is placed while using the station.
func anchor() -> Node3D:
	var node := get_node_or_null(anchor_path) as Node3D if not anchor_path.is_empty() else null
	return node if node != null else self
