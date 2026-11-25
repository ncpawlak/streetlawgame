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
| Map | Tab / M |
| Release / capture mouse | Esc / click |

## Prototype gameplay

You start in **The Bottoms**. Every other district belongs to a rival gang. To take a district, kill all of its defenders, then stay inside it **on foot** until the capture bar fills. Owned turf pays income every 30 seconds.

There are 9 buyable businesses. Tamarack Row sites are in The Bottoms. Northgrove (Rail Yards) and Mangona (Old Harbor) sites are in rival turf, so take those districts first. Walk to a business door and press E to buy it, or to shop there. Owned businesses pay income, add clout to their district and sell to you at half price.

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

Kill every rival, then go to the **CLAIM** ring in the basement stash room and stand in it until the bar fills. Stepping into the ring calls in reinforcements. The bar pauses while any rival is still alive inside the house, and drains slowly if you leave the ring. When the bar fills you get +$1000 and +100 respect.

| Debug key | Action |
| --- | --- |
| F1 | Toggle debug panel |
| F2 | Cycle difficulty (Easy 8 / Normal 12 / Hard 18 rivals) and restart |
| F3 / F4 | Fewer / more rivals and restart |
| F5 | Re-roll enemy placement |
| F6 | Restart with the same placement |
| F7 | Kill all rivals |
| F8 | Cycle top-down floor views (basement / ground / upper / roof / normal camera) |
| F9 | God mode |

`-- --screenshots=DIR` saves a cutaway of each floor plus exterior shots to `DIR`, then quits. It needs a rendering (non-headless) Godot.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
