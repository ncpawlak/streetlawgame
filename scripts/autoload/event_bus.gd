extends Node
## Global signal hub. Systems emit and listen here instead of holding references to each other.

signal cash_changed(amount: int)
signal respect_changed(amount: int)
signal player_health_changed(current: float, maximum: float)
signal player_died
# Turf (see Turf autoload). Everything is keyed by content ids.
signal district_entered(district_id: StringName)
## Any ownership change. [param reason]: &"capture", &"counter_attack", &"load" or &"script".
signal district_owner_changed(district_id: StringName, gang_id: StringName, previous_gang: StringName, reason: StringName)
signal district_captured(district_id: StringName, gang_id: StringName)
signal capture_progress_changed(district_id: StringName, progress: float)
signal area_captured(area_id: StringName, gang_id: StringName)
signal area_lost(area_id: StringName, gang_id: StringName)
signal safehouse_claim_started(district_id: StringName, gang_id: StringName)
signal safehouse_manage_requested(district_id: StringName)
signal gang_member_killed(member: GangMember, killer: Node)
signal notify(text: String)
signal explosion(position: Vector3, radius: float)

# Framework: interaction / content (#26)
signal interaction_performed(interactable: Interactable, action_id: StringName, actor: Node)
signal flag_changed(flag: StringName, value: Variant)

# Framework: locations (#26)
signal location_entered(location: Location, actor: Node)
signal location_exited(location: Location, actor: Node)
signal location_status_changed(location: Location, status: StringName)
signal location_robbed(location: Location, amount: int)
signal location_taken_out(location: Location, previous_owner: StringName)
signal intel_gained(intel_id: StringName, text: String)
signal crew_recruited(member: CrewMemberData)
signal heat_raised(amount: int, location: Node3D)

# Framework: dialogue (#26)
signal dialogue_requested(dialogue: DialogueDef, ctx: ActionContext)
signal dialogue_started(dialogue_id: StringName, target: Node)
signal dialogue_ended(dialogue_id: StringName, outcome: StringName)
