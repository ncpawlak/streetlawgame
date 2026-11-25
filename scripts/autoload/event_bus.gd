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

# Operations framework (#27). Ids are StringNames; see docs/OPERATIONS.md.
signal operations_event(event: Dictionary)
signal stash_changed(site_id: StringName, item_id: StringName, count: int)
signal site_acquired(site_id: StringName)
signal job_assigned(assignment_id: int, crew_id: StringName, site_id: StringName, job_id: StringName)
signal job_unassigned(assignment_id: int, crew_id: StringName, site_id: StringName, job_id: StringName)
signal job_status_changed(assignment_id: int, site_id: StringName, status: int, reason: String)
signal production_completed(site_id: StringName, recipe_id: StringName, outputs: Dictionary)
signal sale_completed(district_id: StringName, item_id: StringName, units: int, revenue: int)
signal unlock_granted(unlock_id: StringName)
signal plug_revealed(plug_id: StringName, location_id: StringName)
signal plug_established(plug_id: StringName)
signal plug_relationship_changed(plug_id: StringName, relationship: float)
signal operation_risk(risk_id: StringName, site_id: StringName, crew_id: StringName, text: String)

# Businesses (#36). Site ids are BusinessSiteDef ids; see docs/CONTENT.md.
## [param reason]: &"purchase", &"script"...
signal business_acquired(site_id: StringName, reason: StringName)
## [param reason]: &"raid" (#8), &"script"...
signal business_lost(site_id: StringName, reason: StringName)
signal shop_purchase(site_id: StringName, item_id: StringName, price: int)
signal clout_changed(district_id: StringName, clout: int, previous: int)

# Player appearance (clothing, hair, disguise). See scripts/framework/appearance.
signal appearance_changed(look: Appearance)
## Paid for a clothing item or a barber service. [param site_id] is &"" outside a business.
signal appearance_purchase(item_id: StringName, color: int, price: int, site_id: StringName)
## [param faction] now remembers the player's current look (they can recognise it again).
signal look_remembered(faction: StringName)
## A faction member's attitude to the player changed (&"hostile", &"suspicious", &"neutral", &"friendly").
signal faction_attitude_changed(member: Node, faction: StringName, attitude: StringName)
