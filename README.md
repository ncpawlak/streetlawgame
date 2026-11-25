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

Self-contained scenes for trying out one gameplay type on its own. They boot straight in and aren't part of the city map.

### Turf capture

Take a Red Vipers intersection. Kill the guards, then stand in the highlighted zone on foot. The capture bar only fills while you're inside it and drains while you're out. Each step of progress brings a bigger Vipers wave, on foot and by car from more streets. The block is yours once the bar is full and the final wave is dead. If you die, the capture restarts.

```sh
godot --path . res://drivers/turf_capture/turf_capture_driver.tscn
# Debug options (all optional):
godot --path . res://drivers/turf_capture/turf_capture_driver.tscn -- --waves=6 --difficulty=hard --guards=0
```

`--difficulty` is `easy`, `normal` or `hard`. In game, press **F1** to change waves, difficulty and guards, then restart.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
