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
godot --path . res://drivers/turf_capture/turf_capture_driver.tscn -- --waves=6 --difficulty=hard --guards=0 --strength=4 --income-interval=10 --counter-delay=20
```

`--difficulty` is `easy`, `normal` or `hard`. In game, press **F1** to change waves, difficulty, guards and Vipers strength, then restart.

Once the block is captured:

- **Rival strength** (1 to 5): Vipers strength grows while you leave their block alone. A stronger rival means a longer hold, bigger waves and harder counter-attacks. It also means the block pays more once you own it.
- **Passive income**: the block (`fifth_and_pine`) pays cash every 20 s (`--income-interval`) and emits `EventBus.turf_block_income`.
- **Counter-attacks**: stay more than 40 m away from your block for 60 s (`--counter-delay`) and the Vipers move into the zone. Get back in and kill them. If they hold the zone for 45 s without you, the block is lost: the income stops and the Vipers come back stronger. Ownership changes are emitted on `EventBus.turf_block_owner_changed`.
- **Debug keys**: **F2** pays the next income now and **F3** starts a counter-attack now.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
