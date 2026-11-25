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

Self-contained scenes for testing one gameplay type each. They aren't connected to the city map.

### Cash van hit

```sh
godot --path . res://drivers/cash_van/cash_van_driver.tscn
```

You start in a getaway car on a looping stretch of I-59. First an intel briefing shows the van's route (drawn on a map and marked on the road), its schedule, its guards and what it's carrying. Without intel (press **F6** to toggle it for debugging), none of that is known and you have to find the van yourself. Press Enter and the van heads out. Shoot out all 4 tires (each one is tracked separately, and the van slows with each flat). After the 4th flat the van stops and three armed guards get out. The longer the hit takes, the more police cruisers join the pursuit. Once the van is stopped, go to its **front** and hold **E** to release the rear doors. Then bag as much cargo as fits in your 8-slot carry bag, lose the police, and cash in at the stash garage in the infield. Press **F5** to restart. See [drivers/cash_van/README.md](drivers/cash_van/README.md) for details.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
