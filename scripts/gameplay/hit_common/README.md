# hit_common: shared hit aftermath

These are the reusable pieces for every hit: bag the loot, beat the police call, lose the cops, then stash the bag for cash. Plus carry-over heat, masks, crew and the timing lock minigame. The house robbery and stick-up drivers both use them. Everything is built in code, so you don't need any `.tscn` files.

| Class | File | Role |
| --- | --- | --- |
| `CarryBag` | `carry_bag.gd` | The player's bag: goods (slots + value) and loose cash. |
| `LootItem` | `loot_item.gd` | A world pickup. Hold E to put it in the bag. |
| `LootContainer` | `loot_container.gd` | A searchable StaticBody3D (drawers, a safe, a register). Hold E to search it and bag what's inside. |
| `PoliceCall` | `police_call.gd` | The countdown to the police being called, or an immediate call. |
| `PoliceResponse` | `police_response.gd` | Spawns cops when called. Tracks wanted, escape and bust. |
| `Cop` | `cop.gd` | A police officer (`GangMember` AI) with line-of-sight checks. |
| `StashDropoff` | `stash_dropoff.gd` | Hold E to turn the bag into cash. It's blocked while you're wanted. |
| `HitHud` | `hit_hud.gd` | The countdown, wanted status, bag contents and objective line. |
| `HitSession` | `hit_session.gd` | Optional glue that creates and wires the above. |
| `HeatMap` | `heat_map.gd` | Carry-over heat per area (120 m grid cell or a named area) plus the player's personal heat. Decays over time. |
| `HitIdentity` | `hit_identity.gd` | The actor's mask, whether their face or car was seen, and how fast their heat cools. |
| `HitTools` | `hit_tools.gd` | Consumable gear (dog treats, spray paint). |
| `TimingMinigame` | `timing_minigame.gd` | The "bang bang bang" timing lock: safes, and the carjack lock pick. |
| `CrewSlot` / `CrewMember` / `HitCrew` | `crew_slot.gd` / `crew_member.gd` / `hit_crew.gd` | Homies on the hit: lookout, driver, muscle. |
| `BodyLoot` | `body_loot.gd` | Lootable cash on dead NPCs. Owned by the stick-up branch (`GangMember._die` attaches it). |

## Rules
- **Countdown:** `PoliceCall.start_countdown(reason, seconds := -1, hidden := false)`.
  - Neighbours noticing a break-in, gunshots, explosions and witnesses all start it.
  - If a countdown is already running, the shorter remaining time wins.
  - A hidden countdown (a silent alarm) turns visible at `reveal_at` (10 s) left.
- **Immediate call:** `PoliceCall.call_now(reason)` is for alarms and cameras.
- **Gunshots:** `WeaponInventory.try_fire` emits `EventBus.gunshot(position, shooter)` for firearms. It doesn't for fists or thrown weapons.
  - `PoliceCall` listens for it, and for `EventBus.explosion`.
  - Anything within `hearing_radius` of `listen_center` starts the countdown. A null `listen_center` hears everywhere.
- **Cops:** when the call fires, `PoliceResponse` spawns `cops_per_wave` cops, and a cruiser on the first wave, at its `Marker3D` children or `spawn_points`.
  - If every cop is down, reinforcements arrive after `reinforcement_delay`.
- **Escape:** get farther than `search_radius` from where a cop last saw you, and stay unseen for `lose_time`.
  - Then `escaped` fires, the cops leave and the call resets.
- **Bust:** if the player dies while the police are involved, the bag is dropped and `busted` fires.
- **Cash-in:** `StashDropoff.cash_in(actor)` pays `payout(bag)` into `GameState.cash`. You need a non-empty bag and you can't be wanted.
  - `payout = round((goods * heat_map.payout_multiplier(area) + cash) * (1 - crew_cut))`.
- **Carry-over heat:** `HitSession.end_hit()` (run on cash-in, bust and `reset`) adds `HIT_HEAT` (20) to the area, plus `CALLED_HEAT` (15) if the police were called. Area heat decays at 0.25/s.
  - Hot areas: `extra_cops = floor(area/25) + floor(personal/34)` per wave, countdowns down to 60% (`countdown_multiplier`), goods pay down to 40% (`payout_multiplier`). Loose cash is unaffected.
- **Masks:** being seen unmasked (camera, witness, police) adds `FACE_HEAT` (25) personal heat, once per source per hit. Masked, nothing is added.
  - The car the player is in (or last drove) when the police are called is noted as `seen_vehicle`.
  - Personal heat decays (and cops lose you) x4 when in a different car with the mask off and the face unseen, x1.75 for one of those two, x0.6 masked or in the seen car.
  - `erase_evidence(heat, source)` takes back one source's heat (the house's DVR wipes `&"camera"`).
- **Crew:** each member takes `CrewSlot.CUT` (10%). Lookout: countdowns x1.35, reveals hidden (silent-alarm) countdowns, warns on call and arrival. Driver: waits hidden in `crew.getaway`; escape x1.5 while the player is in that car. Muscle: follows the player and calls `hold(self)` every frame on anything in groups `"homeowners"` / `"hostages"` within 7 m.
- **Timing minigame:** a pin sweeps left to right. Press E / Space / click (`interact`, `jump`, `shoot`) in the green sweet spot `hits_needed` times in a row. A miss or the pin hitting the far wall resets the streak (the spot moves). Esc cancels.
- **Bodies:** every person is an animated `CharacterVisual`. Cops wear the navy SWAT model, homeowners a civilian model (a gun only if `armed`), crew the crew model in the player's gang tint and bandana. They play shoot, hit and death clips through `GangMember`. Override `GangMember._make_visual()` to give a subclass its own look. The `HitIdentity` balaclava follows the head bone.

## API
```gdscript
# CarryBag (Node, child "CarryBag" of the actor)
CarryBag.of(actor, create := true) -> CarryBag
add_item(item_name: String, value: int, slots := 1) -> bool   # false + `rejected` when full
add_cash(amount: int)                                          # no slots
remove_item(index: int) -> Dictionary                          # {} if out of range
can_fit(slots) / free_slots() / used_slots() / is_full() / is_empty()
total_value() -> int        # goods + cash
empty() -> int              # clears, returns the total (the stash uses this)
drop()                      # loses everything
signals: changed, item_added(item), rejected(item_name, reason), emptied(total)
vars: capacity := 8, items: Array[Dictionary] {name, value, slots}, cash: int

# LootItem (Node3D)
LootItem.create(item_name, value, slots, is_cash, position) -> LootItem
take(actor) -> bool         # what the hold-E action calls
signal taken(item, actor)

# LootContainer (StaticBody3D, layer 1)
@export container_name, size: Vector3, color, search_time := 1.5
set_contents({name, value, slots, cash} or {})   # {} = nothing worth taking
search(actor) -> Dictionary  # what the hold-E "search" action calls; bags the item or cash
can_search() -> bool         # false while locked
set_locked(value, hits := 3, speed := 0.5)   # lock behind a TimingMinigame
crack(actor) -> TimingMinigame # opens the minigame; success unlocks and searches
can_crack(); vars: contents, is_searched, locked, minigame
signals: searched(container, actor, found), unlocked(container, actor)

# PoliceCall (Node)
enum State { IDLE, COUNTDOWN, CALLED }
start_countdown(reason: StringName, seconds := -1.0, hidden := false)
call_now(reason: StringName)
report_noise(position: Vector3, reason := REASON_GUNSHOT)
reset()
is_counting() / is_called() / is_active(); state, time_left, hidden, reason
signals: countdown_started(seconds, reason), countdown_revealed, police_called(reason), reset_done
reveal()                    # a hidden countdown becomes visible (the lookout does this)
countdown_scale := 1.0      # multiplies the duration of new countdowns (crew x heat, set by HitSession)
REASON_NEIGHBOURS, REASON_GUNSHOT, REASON_EXPLOSION, REASON_ALARM, REASON_CAMERA, REASON_SILENT_ALARM, REASON_WITNESS, REASON_DOG
exports: countdown_seconds := 45, hearing_radius := 40, listen_center: Node3D, listen_gunshots := true, reveal_at := 10

# PoliceResponse (Node3D)
dispatch()                  # send a wave now
update(delta)               # chase tick (runs automatically in physics)
stand_down()                # cops leave, the call resets
is_wanted(), is_seen(), escape_progress(), alive_cops(); last_seen, unseen_time, wanted_time, waves
heat_map, heat_area         # each wave gets heat_map.extra_cops(heat_area) more cops
escape_rate := 1.0          # x identity.escape_multiplier() on unseen_time gain (crew driver sets it)
wave_size_hook: Callable    # optional func(wanted_time: float, wave: int) -> int, replaces cops_per_wave + wave * wave_growth
signals: cops_arrived(count), player_spotted, escaped, busted
exports: police_call, cops_per_wave := 3, wave_growth := 1, reinforcement_delay := 8, escalation_interval := 0 (seconds between extra waves while wanted; 0 = only when all cops are down), search_radius := 50, lose_time := 12, spawn_cruiser := true, spawn_points: Array[Vector3]

# StashDropoff (Node3D)
cash_in(actor) -> int, can_cash_in(actor), cash_in_reason(actor), payout(bag) -> int
vars: heat_map, heat_area, crew_cut := 0.0
signal cashed_in(amount, actor); export police_response

# HitSession (Node)
setup(player, cop_spawn_points: Array[Vector3], listen_center: Node3D = null, countdown := 45.0, with_hud := true)
register_stash(stash: StashDropoff)
reset()                     # ends the hit (its heat carries over), stands the police down
begin_hit()                 # the hit is on: identity tracking, crew to posts, modifiers applied
end_hit()                   # adds the area heat; runs on cash-in / bust / reset
set_heat_map(map: HeatMap)  # default HeatMap.shared(); tests use HeatMap.new()
set_heat_area(area)         # default heat_map.area_key(listen_center position); set heat_area before setup() to name it
vars: police_call, police_response, hud, bag, state, identity, crew: HitCrew, heat_map, heat_area, in_progress
signals: finished(cash), failed(reason), hit_started, hit_ended

# HeatMap (Node)
HeatMap.shared() -> HeatMap # game-wide, added to the root; decays every frame
area_key(position) -> StringName; area_heat(area); add_area_heat(area, amount); add_personal_heat(amount)
decay(delta); clear(); level(area) -> 0..1; describe(area) -> String
extra_cops(area) -> int; countdown_multiplier(area); payout_multiplier(area)
vars: areas, personal_heat, area_decay := 0.25, personal_decay := 0.2, cell_size := 120
const MAX_HEAT 100, HIT_HEAT 20, CALLED_HEAT 15, FACE_HEAT 25

# HitIdentity (Node, child "HitIdentity" of the actor)
HitIdentity.of(actor, create := true) -> HitIdentity
set_masked(bool), toggle_mask(); masked; signal mask_changed(masked)   # drivers bind their own key (X in the house driver)
begin_hit(), end_hit(); on_hit
witness(heat, source: StringName, amount := FACE_HEAT) -> bool        # true if their face was seen; signal identified
note_vehicle()              # remember the current / last car as seen_vehicle
erase_evidence(heat, source) -> float
is_disguised(), swapped_vehicle(), decay_multiplier(), escape_multiplier(), status_text()
vars: face_seen, seen_vehicle, last_vehicle, evidence

# HitTools (Node, child "HitTools" of the actor)
HitTools.of(actor); give(tool, n := 1); use(tool) -> bool; has(tool); count(tool); summary()
DOG_TREAT, SPRAY_PAINT; signal changed

# TimingMinigame (CanvasLayer)
start(actor := null, seed := -1); press() -> bool; step(delta); cancel(); in_sweet_spot()
exports: hits_needed := 3, speed := 0.5 (screen widths/s), sweet_width := 0.1, max_resets := 0 (0 = unlimited), title, auto_step := true, show_ui := true
vars: active, pin, streak, resets, sweet_start, sweet_end, actor   # the actor is frozen while active
signals: succeeded, failed(reason), hit(streak), reset_happened(reason)   # reason &"miss" / &"wall" / &"cancelled" / &"too_many_resets"

# CrewSlot (RefCounted)
enum Role { LOOKOUT, DRIVER, MUSCLE }; ROLE_NAMES; CUT 0.1, LOOKOUT_TIME 1.35, DRIVER_ESCAPE 1.5, HOLD_RANGE 7.0

# HitCrew (Node3D, HitSession.crew)
assign(role) -> CrewMember; dismiss(role); toggle(role) -> bool; has_role(role); clear(); members(); place()
countdown_multiplier(); escape_rate(); payout_cut(); warn(text); summary()
vars: lookout_post: Vector3, getaway: Node3D, getaway_spot: Transform3D, slots
signals: warning(text), changed
# e.g. a silent alarm: if session.crew.has_role(CrewSlot.Role.LOOKOUT): session.crew.warn("Lookout: 'Clerk hit something under the counter!'")

# CrewMember (GangMember): crew_role, crew, place(), is_in_car(). Not shootable, no collision layer.
# Anything holdable: add it to group "hostages" and implement hold(by: Node3D) (called every frame while in range).

# HitHud (CanvasLayer)
bind(bag, police_call, police_response); set_objective(text)
```

## Minimal setup
```gdscript
var session := HitSession.new()
add_child(session)
session.setup(player, [Vector3(60, 0, 0)], house_node)
var stash := StashDropoff.new()
stash.position = Vector3(-40, 0, 20)
add_child(stash)
session.register_stash(stash)
add_child(LootItem.create("Register cash", 350, 0, true, Vector3(1, 1, 0)))
# Silent alarm in a hold-up:
session.police_call.start_countdown(PoliceCall.REASON_SILENT_ALARM, 30.0, true)
```
