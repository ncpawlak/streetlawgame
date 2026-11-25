class_name FactionStyleDef
extends ContentDef
## How a faction reads the player's look (data/faction_styles/<faction id>.tres): its colours,
## its rivals, how well it remembers a face and what its own members wear. The id is the faction /
## gang id (GameState.GANGS). Used by PlayerAppearance.reaction_of and GangMember.

const TYPE := &"faction_styles"

## Colour families that are this faction's colours (Appearance.color_weights tags).
@export var color_tags: Array[StringName] = []
## Rival factions: wearing their colours here is provocation.
@export var rivals: Array[StringName] = []
## Attitude to a stranger in neutral clothes: &"hostile", &"suspicious", &"neutral" or &"friendly".
@export var default_attitude: StringName = &"hostile"
## Attitude when they recognise the player's look (see [member recognition_threshold]).
@export var recognised_attitude: StringName = &"hostile"
## Attitude when the player wears enough of this faction's colours.
@export var own_colors_attitude: StringName = &"neutral"
## Look similarity (Appearance.similarity) at or above which they recognise the player.
@export_range(0.0, 1.0) var recognition_threshold := 0.6
## Share of the outfit in their colours that counts as "wearing our colours".
@export_range(0.0, 1.0) var own_colors_threshold := 0.5
## Share of the outfit in a rival's colours that makes them hostile / suspicious.
@export_range(0.0, 1.0) var rival_hostile_threshold := 0.45
@export_range(0.0, 1.0) var rival_suspicious_threshold := 0.2
## Members remember the player's current look whenever they fight them.
@export var remembers_on_sight := true
## The faction already knows the player's starting look at the start of a new game.
@export var knows_starting_look := false
## Seconds a suspicious member stares before turning hostile (0 = never).
@export var suspicion_time := 8.0
## Range (m) within which suspicion builds.
@export var suspicion_range := 9.0
## Members' outfit (Appearance.to_dict form). Empty = tint the model in the gang colour.
@export var uniform: Dictionary = {}


static func find(faction: StringName) -> FactionStyleDef:
	return ContentDB.find_def(TYPE, faction) as FactionStyleDef


func uniform_look() -> Appearance:
	return Appearance.from_dict(uniform) if not uniform.is_empty() else null


func validate() -> PackedStringArray:
	var issues := super()
	for attitude in [default_attitude, recognised_attitude, own_colors_attitude]:
		if not PlayerAppearance.ATTITUDES.has(attitude):
			issues.append("unknown attitude '%s'" % attitude)
	return issues
