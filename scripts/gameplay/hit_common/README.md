# hit_common: shared hit aftermath

These are the reusable pieces for the end of every hit: bag the loot, beat the police call, lose the cops, then stash the bag for cash. The house robbery and stick-up drivers both use them. Everything is built in code, so you don't need any `.tscn` files.

| Class | File | Role |
| --- | --- | --- |
| `CarryBag` | `carry_bag.gd` | The player's bag: goods (slots + value) and loose cash. |
| `LootItem` | `loot_item.gd` | A world pickup. Hold E to put it in the bag. |
| `PoliceCall` | `police_call.gd` | The countdown to the police being called, or an immediate call. |
| `PoliceResponse` | `police_response.gd` | Spawns cops when called. Tracks wanted, escape and bust. |
| `Cop` | `cop.gd` | A police officer (`GangMember` AI) with line-of-sight checks. |
| `StashDropoff` | `stash_dropoff.gd` | Hold E to turn the bag into cash. It's blocked while you're wanted. |
| `HitHud` | `hit_hud.gd` | The countdown, wanted status, bag contents and objective line. |
| `HitSession` | `hit_session.gd` | Optional glue that creates and wires the above. |

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
- **Cash-in:** `StashDropoff.cash_in(actor)` pays `bag.total_value()` (goods + cash) into `GameState.cash`. You need a non-empty bag and you can't be wanted.

## API
```gdscript
# CarryBag (Node, child "CarryBag" of the actor)
CarryBag.of(actor, create := true) -> CarryBag
add_item(item_name: String, value: int, slots := 1) -> bool   # false + `rejected` when full
add_cash(amount: int)                                          # no slots
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

# PoliceCall (Node)
enum State { IDLE, COUNTDOWN, CALLED }
start_countdown(reason: StringName, seconds := -1.0, hidden := false)
call_now(reason: StringName)
report_noise(position: Vector3, reason := REASON_GUNSHOT)
reset()
is_counting() / is_called() / is_active(); state, time_left, hidden, reason
signals: countdown_started(seconds, reason), countdown_revealed, police_called(reason), reset_done
REASON_NEIGHBOURS, REASON_GUNSHOT, REASON_EXPLOSION, REASON_ALARM, REASON_CAMERA, REASON_SILENT_ALARM, REASON_WITNESS
exports: countdown_seconds := 45, hearing_radius := 40, listen_center: Node3D, listen_gunshots := true, reveal_at := 10

# PoliceResponse (Node3D)
dispatch()                  # send a wave now
update(delta)               # chase tick (runs automatically in physics)
stand_down()                # cops leave, the call resets
is_wanted(), is_seen(), escape_progress(), alive_cops(); last_seen, unseen_time
signals: cops_arrived(count), player_spotted, escaped, busted
exports: police_call, cops_per_wave := 3, wave_growth := 1, reinforcement_delay := 8, search_radius := 50, lose_time := 12, spawn_cruiser := true, spawn_points: Array[Vector3]

# StashDropoff (Node3D)
cash_in(actor) -> int, can_cash_in(actor), cash_in_reason(actor)
signal cashed_in(amount, actor); export police_response

# HitSession (Node)
setup(player, cop_spawn_points: Array[Vector3], listen_center: Node3D = null, countdown := 45.0, with_hud := true)
register_stash(stash: StashDropoff)
reset()
vars: police_call, police_response, hud, bag, state
signals: finished(cash), failed(reason)

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
