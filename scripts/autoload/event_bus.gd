extends Node
## Global signal hub. Systems emit and listen here instead of holding references to each other.

signal cash_changed(amount: int)
signal respect_changed(amount: int)
signal player_health_changed(current: float, maximum: float)
signal player_died
signal territory_entered(territory: Territory)
signal territory_captured(territory: Territory, gang_id: StringName)
signal capture_progress_changed(territory: Territory, progress: float)
signal gang_member_killed(member: GangMember, killer: Node)
signal notify(text: String)
signal explosion(position: Vector3, radius: float)

# Framework: interaction / content (#26)
signal interaction_performed(interactable: Interactable, action_id: StringName, actor: Node)
signal flag_changed(flag: StringName, value: Variant)
