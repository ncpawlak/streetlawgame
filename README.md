# Street Law

A 3rd-person open-world gang warfare game in the spirit of *Saints Row 1 & 2* and classic 3D *GTA*. Take your crew from the gutter to running the city: take over territories, rob houses, businesses and banks, do drive-bys, run trap houses and drug operations, buy businesses, and stock up on guns and explosives.

- 📜 [Game design document](docs/GDD.md)
- 🏗️ [Architecture](docs/ARCHITECTURE.md)

## Requirements

- [Godot 4.7](https://godotengine.org/download) (standard build; GDScript only). On Windows: `winget install GodotEngine.GodotEngine`

## Running

Open `project.godot` in Godot and press **F5**, or from a terminal:

```sh
godot --path .
```

## Controls

| Action | Key |
| --- | --- |
| Move / sprint / jump | WASD / Shift / Space |
| Look | Mouse |
| Shoot / aim | LMB / RMB |
| Weapon wheel (pauses the game) | Hold Q, move the mouse, release |
| Switch weapon | Mouse wheel / 1-9 |
| Throw grenade / molotov / C4, fire RPG | LMB with it equipped |
| Detonate placed C4 | G |
| Reload | R |
| Enter, steal or exit a vehicle | E |
| Handbrake | Space (in vehicle) |
| Drive-by (uses your equipped gun) | LMB (in vehicle) |
| Pause map | M (M / Esc closes) |
| Journal (Active / Leads / Completed) | J (J / Esc closes) |
| Release / capture mouse | Esc / click |

**Pause map (M):** the game pauses while it's open. Pan with a mouse drag or WASD/arrows, and zoom with the wheel or Q/E, from the whole North End down to a few blocks. Click a marker for its info card. Right-click sets a waypoint, or right-click the pin to clear it. A GPS line to the waypoint follows the streets on the minimap. Space recentres on you and Backspace clears the waypoint. The legend toggles each category: objectives and the current mission, hit spots, your businesses and trap houses, businesses for sale, rival fronts, plugs and corners, safehouses, gun and explosive shops, world events (hot cars) and turf colours. Roster spots without a system yet show as *coming soon*.

## Prototype gameplay

The world is a greybox of the **North End** (Zone 1, see `docs/map/north_end_wireframe.svg`): Tamarack Row, Northgrove and Mangona, all run by the Red Vipers. You start outside the boarded duplex in Tamarack Row. To take a district, kill its safehouse guards and patrols, then hold [E] Take over at the safehouse door. Owned turf pays income every 30 seconds. Roster spots from `docs/design/NORTH_END_HITS.md` that have no system yet show as labelled "coming soon" posts.

There are 9 buyable businesses, three per North End district, all in Viper turf at start, so take a district before buying there. Walk to a business door and press E to buy it, or to shop there. Owned businesses pay income, add clout to their district and sell to you at half price.

You start with fists and a pistol. There's a stash of guns (SMG, shotgun, rifle) next to your car, with a row of explosives (grenades, molotovs, C4, RPG) beside it, and rivals drop their weapons when they die. Weapons use magazines and reserve ammo.

Vehicles take damage from bullets, explosions and crashes: they smoke, then catch fire, then explode. Rivals will shoot at your car while you're driving.

## Missions, leads and safehouses

These are the building blocks for scripted missions. They live in `scripts/framework/missions/` and are driven by the `Missions` autoload. No story mission ships yet; the showcase shows them working together.

- **Missions** (`MissionDef`, `data/missions/*.tres`)
  - A mission is an ordered list of `MissionStep` resources plus:
    - fail conditions;
    - start requirements, using the existing `Condition` framework;
    - rewards (cash, respect, `Effect`s, mission unlocks and safehouse unlocks).
  - Steps can be `optional`, `bonus` or `checkpoint`, and can have a time limit. `AllOfStep` runs several steps in parallel.
  - Start a mission with `Missions.start_mission(id)` or a `MissionStartMarker`. You can also use `Missions.retry()` (from the last checkpoint) and `Missions.abandon()`.
- **Steps** (`steps/`):

  | Step | Objective |
  | --- | --- |
  | `ReachStep` | Go to a location |
  | `EnterZoneStep` | Enter a trigger zone |
  | `InteractStep` | Interact with something |
  | `TalkStep` | Talk to an NPC (dialogue hook) |
  | `WaitStep` | Wait for an event or flag |
  | `KillStep` | Kill targets |
  | `HaveItemStep` | Have an item |
  | `BuyItemStep` | Buy an item |
  | `LoseHeatStep` | Lose the heat |
  | `StealVehicleStep` | Steal a vehicle |
  | `DeliverVehicleStep` | Deliver a vehicle, with a clean bonus (no heat during the run and damage under a threshold) |
  | `ParkVehicleStep` | Park a vehicle (stopped, optionally with zero heat) |
  | `FollowStep` | Follow an NPC (follow hook) |
  | `HookStep` | Play a cutscene or start a phone call |

  Targets are found by tag (`Missions.tag(node, id)`), zone id or node path.
- **Fails** (`fails/`):
  - `PlayerDiedFail` (added automatically by `fail_on_death`)
  - `TargetDestroyedFail`
  - `TimeLimitFail`
  - `EventFail`
  - `ConditionFail`

  A failure shows MISSION FAILED. Press R to retry from the checkpoint, or Esc to give up.
- **Hooks for other systems**: cutscenes, dialogue, phone calls and companions are reached through string ids:
  - Steps call `Missions.request_hook(kind, id, ctx)`.
  - A system takes over with `Missions.register_hook(Missions.HOOK_DIALOGUE, handler)` (also `HOOK_CUTSCENE`, `HOOK_PHONE_CALL`, `HOOK_FOLLOW`). When it's done, it calls `Missions.finish_hook(kind, id, outcome)`.
  - With no handler registered, hooks auto-finish, so missions still run without those systems.
- **Leads journal**:
  - `Missions.add_lead(id, title, note, marker, marker_unlocked)` adds a lead. Its optional map marker can be locked and unlocked later.
  - Press J for the Active / Leads / Completed journal.
  - The HUD shows the current objective lines, a waypoint beacon and the heat stars. The objective also becomes the current mission marker on the map.
- **Trigger zones** (`TriggerZone`):
  - A reusable `Area3D` that fires for the player on foot, in any vehicle, in a specific vehicle or tag, or stopped, gated by `Condition`s.
  - It can apply `Effect`s once or every time, whether or not a mission is running.
- **Safehouses**:
  - `PlayerSafehouseDef` lives in `data/player_safehouses/`. `pedros_house.tres` is the Tamarack Row duplex.
  - The `PlayerSafehouse` node provides:
    - an entry door or garage;
    - a save point, which also heals;
    - reduced or cleared heat when you arrive unseen;
    - a respawn point: after death you respawn at the nearest unlocked safehouse;
    - vehicle storage (`Missions.store_vehicle` / `retrieve_vehicle`);
    - a `WardrobeSlot` Marker3D (group `wardrobe_slots`, with `safehouse_id` meta) for the wardrobe system to fill.
  - Unlock one with `Missions.unlock_safehouse(id)` or `UnlockSafehouseEffect`.
- **Heat and saving**:
  - `Missions.heat` (`HeatTracker`) is a lightweight heat level with stars. It decays after you've been unseen for 8 s, and a real wanted system can replace it through `provider` and `clear_handler`.
  - `SaveGame` persists missions, leads, items, safehouses and stored vehicles to `user://savegame.dat`.

Showcase, a sample mission: get a lead, deliver a car cleanly, park in the driveway with zero heat, and a safehouse unlocks:

```sh
godot --path . res://scenes/showcase/missions_showcase.tscn                      # play it
godot --headless --path . res://scenes/showcase/missions_showcase.tscn -- --autoplay   # prints SHOWCASE OK
```

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
