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
| Release / capture mouse | Esc / click |

**Pause map (M):** the game pauses while it's open. Pan with a mouse drag or WASD/arrows, and zoom with the wheel or Q/E, from the whole North End down to a few blocks. Click a marker for its info card. Right-click sets a waypoint, or right-click the pin to clear it. A GPS line to the waypoint follows the streets on the minimap. Space recentres on you and Backspace clears the waypoint. The legend toggles each category: objectives and the current mission, hit spots, your businesses and trap houses, businesses for sale, rival fronts, plugs and corners, safehouses, gun and explosive shops, world events (hot cars) and turf colours. Roster spots without a system yet show as *coming soon*.

## Prototype gameplay

The world is a greybox of the **North End** (Zone 1, see `docs/map/north_end_wireframe.svg`): Tamarack Row, Northgrove and Mangona, all run by the Red Vipers. You start outside the boarded duplex in Tamarack Row. To take a district, kill its safehouse guards and patrols, then hold [E] Take over at the safehouse door. Owned turf pays income every 30 seconds. Roster spots from `docs/design/NORTH_END_HITS.md` that have no system yet show as labelled "coming soon" posts.

There are 9 buyable businesses, three per North End district, all in Viper turf at start, so take a district before buying there. Walk to a business door and press E to buy it, or to shop there. Owned businesses pay income, add clout to their district and sell to you at half price.

You start with fists and a pistol. There's a stash of guns (SMG, shotgun, rifle) next to your car, with a row of explosives (grenades, molotovs, C4, RPG) beside it, and rivals drop their weapons when they die. Weapons use magazines and reserve ammo.

Vehicles take damage from bullets, explosions and crashes: they smoke, then catch fire, then explode. Rivals will shoot at your car while you're driving.

## Gameplay drivers

Drivers are self-contained scenes that boot straight into one gameplay type. They aren't wired into the city map.

### Trap house takeover

```sh
godot --path . res://drivers/trap_takeover/trap_takeover_driver.tscn
# optional: godot --path . res://drivers/trap_takeover/trap_takeover_driver.tscn -- --difficulty=hard --enemies=14 --seed=7 --claim-time=10
```

You spawn on the street in front of **The Spot**, a Red Vipers trap house on a fenced lot. The house has four levels:

- **Basement:** grow room, corridor and stash room.
- **Ground floor:** living room, count room, hall, kitchen and laundry.
- **Upper floor:** two bedrooms, the landing, the lookout room and the boss's room.
- **Roof.**

Swing doors open as people walk through them. Rivals are placed on posts that suit them: yard guards, window overwatch, room holders and hall patrols. They alert each other, react to gunfire, and chase you between floors on the stairs.

**Loud or quiet entry.**

- **Loud:** the front door is locked. Press **E** at it to kick it in. The whole house is alerted at once. A loud entry is worth +50 respect.
- **Quiet:** come in through the back door, the kitchen side door, or the back laundry window (**E** to climb in or out). Unaware Vipers don't see as far, so you can sneak up behind one and press **E** to take him out silently.
- **Alarm:** a Viper who spots you, or hears gunfire, raises the alarm after 3 s unless you drop him first. The alarm alerts everyone. If you clear the house without ever raising it, you get a +$500 ghost bonus.

Kill every rival, then go to the **CLAIM** ring in the basement stash room and stand in it until the bar fills. Stepping into the ring calls in reinforcements. The bar pauses while any rival is still alive inside the house, and drains slowly if you leave the ring. When the bar fills you get +$1000 and +100 respect, plus any bonuses.

**Keep it or destroy it.** After the claim, press **K** or **X**, or press **E** in the claim ring for a menu.

- **Keep (K):** The Spot becomes your trap. It's registered as an owned Operations site and starts as a Lv 2 House with the Vipers' grow room making weed. Press **T** to open the manage panel, where you can:
  - upgrade the level (House $3k, Compound $10k), which adds room slots, worker slots and stash space;
  - build rooms from the costs in `docs/design/TRAP_HOUSES_OPERATIONS.md`;
  - pick the product;
  - put crew on Guard, Cook or Dealer.
  The build-out is saved in the `trap_the_spot` GameState flag.
- **Destroy (X):** strip the trap for a one-time $2500. The house is knocked down to an empty lot, and the Vipers lose their spot. A sign out front lets you reserve the lot for a new trap house, stash house or front business. That's a stub until construction exists. The lot state is saved in the `lot_the_spot` flag.

| Key | Action |
| --- | --- |
| E | Kick in the front door / climb the laundry window / silent takedown / keep-destroy menu |
| K / X | Keep / destroy the trap after the claim |
| T | Manage a kept trap |
| F1 | Toggle debug panel |
| F2 | Cycle difficulty (Easy 8 / Normal 12 / Hard 18 rivals) and restart |
| F3 / F4 | Fewer / more rivals and restart |
| F5 | Re-roll enemy placement |
| F6 | Restart with the same placement (also rebuilds a destroyed house) |
| F7 | Kill all rivals |
| F8 | Cycle top-down floor views (basement / ground / upper / roof / normal camera) |
| F9 | God mode |

`-- --screenshots=DIR` saves a cutaway of each floor, exterior shots, the manage panel for a kept trap and the destroyed lot to `DIR`, then quits. It needs a rendering (non-headless) Godot.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
