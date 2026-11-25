# Carjack / hot car driver

A self-contained playable scene for the carjacking loop. It is **not** wired into the city map.

```sh
godot --path . res://drivers/carjack/carjack_driver.tscn
# pick the minigame / tracker / difficulty up front:
godot --path . res://drivers/carjack/carjack_driver.tscn -- --minigame=hotwire --tracker=always --difficulty=hard
```

## Loop

1. Walk up to one of the target cars and press **E** (*Break in* / *Pull the driver out*). Target cars are locked, so they can't be entered without jacking them.
2. Beat the carjack **minigame**:
   - **Fail** it and the car alarm goes off. The neighbours call the police in 15 s, or 10 s if the owner was in the car.
   - Take **longer than 10 s** and a witness notices you. That starts a 30 s police countdown.
   - **Esc** walks away from the car.
3. Win it and you're behind the wheel. If you pulled the driver out, they run off and call the cops (20 s).
4. **Hot cars** have a GPS tracker. After 2 s it pings every 5 s, and each ping calls the police, sends cruisers and tells the cops exactly where you are. To get rid of it you can:
   - outlast it (40 s),
   - park under the **parking garage** roof (west side) for 3 s to jam it, or
   - deliver the car to the chop shop with the tracker still on.
5. Stop on the **chop shop** pad (orange beam, east side) while no cop can see you. The shop pays `value × (40–100% for condition)`. You get a **+20 % cold-car bonus** if the tracker is dead or the car never had one. Delivering also stands the police down.

Target cars respawn 8 s after they're delivered or destroyed.

## Car classes

The scene spawns one car of each class. Classes live in the shared table `scripts/vehicles/vehicle_class.gd` (`VehicleClass.TABLE`), so the main game's cars can use the same rows: set `vehicle_class_id` on any `Vehicle`. A class sets:

- the lock difficulty: a multiplier on the F4 difficulty for every minigame, capped at 2.0 so hard + luxury is still winnable
- the tracker chance, rolled when the car spawns
- the chop shop value
- health, handling and paint

| Class | Lock | Tracker | Chop value | Handling | Spawns |
| --- | --- | --- | --- | --- | --- |
| Junker | ×0.70 | never | $600 | light, soft, weak engine | occupied |
| Sedan | ×1.00 | 10 % | $1,200 | stock `Vehicle` handling (play-tuned, see below) | parked |
| Muscle car | ×1.10 | 35 % | $2,800 | heavy, big engine, loose rear | parked |
| SUV | ×1.15 | 25 % | $2,200 | 2 t, high centre of mass, leans | occupied |
| Sports coupe | ×1.30 | always | $3,500 | low, stiff, grippy, quick steering | parked |
| Luxury sedan | ×1.45 | always | $4,500 | heavy, firm, smooth | parked |

The F1 panel shows this table. To add a class, add a row to `VehicleClass.TABLE`. Any handling key you leave out keeps the stock value.

### Handling baseline and balancing notes

The stock handling (sedan, and every `Vehicle` without a class) was picked in the F7 panel to stop the "floppy" feel: **mass 1300 kg, centre of mass 0.20 m, suspension stiffness 73, compression damping 1.55, rebound damping 2.15, tyre grip 4.9**. Travel 0.30, roll influence 0.10, engine force 3000, max steer 0.55 and steer speed 2.5 are unchanged. The other classes were rebased onto this baseline, keeping their old offsets from the sedan: mass, stiffness, damping and grip are scaled by the same ratio, and centre of mass is shifted by the same −0.1 m. They haven't been balanced yet.

Planned per-type direction (not implemented yet):

- **Trucks / vans:** higher centre of mass and more suspension bounce (softer springs, lower rebound damping, more travel).
- **Off-road trucks:** like trucks, but heavier and with more tyre grip.
- The other classes should get their own feel in the same way once there are car models for them.

A heavier, stiffer car moves less when hit by an explosion. Explosions use a fixed impulse, so a rocket now shoves a stock car about 0.2 m instead of 0.6 m. If cars should get thrown further, retune the RPG's impulse instead of the cars.

Each wheel's suspension force is capped (Godot's default is 6000 N). `VehicleTuning` raises that cap in proportion to mass (6000 N per 1300 kg, so the sedan is unchanged). Without that, anything above about 2400 kg sat on its body: the rebased 2600 kg SUV rode 0.46 m low, and dragging the F7 mass slider high did the same to any car.

## Minigames (prototypes, swappable)

The final minigame hasn't been decided, so there are three prototypes. They all share one interface, `CarjackMinigame` in `minigames/carjack_minigame.gd`:

- `begin(car)`, `tick(delta)`, `press_primary()`, `press_option(i)`, `cancel()`
- signals `finished(success, reason)`, `too_slow`, `cancelled`

| Kind | Script | How it plays |
| --- | --- | --- |
| `lock_pick` | `lock_pick_minigame.gd` | "Bang bang bang", run on the shared `TimingMinigame` (`scripts/gameplay/hit_common/timing_minigame.gd`, the same mechanic as house safes). A pin sweeps toward the far wall. Press E/Space while it is in the green to set a pin, and the next green spot appears further along. Set 3 pins back to back before the pin hits the wall. Hitting the wall, or pressing outside the green, resets the streak. 3 mis-presses snap the pick (alarm). The class lock difficulty speeds up the pin and narrows the green. |
| `hotwire` | `hotwire_minigame.gd` | Four shuffled wires on keys 1-4. Connect the bracketed wire in the shown sequence (3 wires, 4 on hard) before the step timer runs out. 2 sparks (a wrong wire or a timeout) fail it. |
| `struggle` | `struggle_minigame.gd` | Mash E/Space to drag the driver out while they claw back grip in surges. Grip at 0 or 8 s elapsed fails it. |

To add a new prototype, extend `CarjackMinigame`, override `_setup` / `_tick` / `_primary` / `_option` / `_build_body` / `_refresh`, and register it in `CarjackMinigame.KINDS` and `create()`.

## Debug menu (F1)

| Key | Action |
| --- | --- |
| F1 | Show / hide the debug panel |
| F2 | Cycle the minigame: **Auto** (lock pick for parked cars, struggle for occupied ones) → Lock pick → Hotwire → Struggle |
| F3 | Cycle trackers: Per car / Always / Never |
| F4 | Cycle difficulty: Easy / Normal / Hard |
| F5 | Reload the scene |
| F6 | Teleport next to the next target car |
| F7 | Show / hide the **car tuning** panel |
| F8 | Switch the tuning panel to the next car class |

These map to the command-line args `--minigame=auto|lock_pick|hotwire|struggle`, `--tracker=per_car|always|never` and `--difficulty=easy|normal|hard`, and to the matching exports on `CarjackDriver`.

## Car tuning (F7)

The panel on the right live-adjusts the handling of one **car class** at a time: mass, centre-of-mass height, suspension stiffness, compression and rebound damping, suspension travel, roll influence (body lean), tyre grip, engine force, max steer and steer speed. Changes apply to every car of that class.

- The panel follows the car you get into. Use **F8** or the `< Class >` button to pick another class.
- Press **Esc** to free the mouse, drag the sliders, then click the world to resume driving.
- Values you've changed from the class table show in yellow.
- **Copy values** copies a one-line summary to the clipboard (it's also printed to the console), e.g. `Car tuning [sedan]: mass=1000, center_of_mass_y=0.30, ...`. The keys match `VehicleClass.TABLE`, so the numbers can be pasted into that class's `handling` row.
- **Reset defaults** restores the class table values. Nothing in the table changes until you pick values.

"Floppy" feel mostly comes from damping, roll influence and centre-of-mass height, not just mass. Low rebound damping and high roll influence make the body wallow.

## Driving camera

This applies to all vehicles, via the shared `scripts/vehicles/vehicle.gd`. The chase camera is free-look: the mouse sets the yaw and pitch, and the camera no longer swings back behind the car. You can look anywhere while driving, and drive-bys shoot where the crosshair is.

## Characters

Everyone in the driver uses the animated `CharacterVisual` (`scripts/characters/`):

- **Owners in occupied cars** are civilians in the driver's seat, on the +X side, which is where `Vehicle.exit()` and the owner leave from. There's no sitting clip yet, so a standing model on the floor pan stands in for a seated one, scaled to 0.85 so the head stays under the 2.0 m roof. Hot cars and cruisers have tinted, see-through cabin glass so you can see who's inside.
- **The fleeing owner** is the same civilian model. They flinch (the hit clip) as they're dragged out, then run.
- **Cruisers** have a navy-tinted cop (the SWAT model) at the wheel.
- **Death:** when a car is wrecked, whoever is inside plays the death animation.
- **On-foot cops** (the hit_common `Cop`) use the same cop model with the same tint.

## Files

| File | Purpose |
| --- | --- |
| `carjack_driver.gd` / `.tscn` | World builder, jack flow, alarms, tracker → police wiring, respawns, debug keys |
| `carjack_hud.gd` | Objective / police / tracker lines and the debug panel |
| `hot_car.gd` | `HotCar` (a `Vehicle`): locked / occupied / stolen state, the Jack interaction, the alarm |
| `hot_car_tracker.gd` | `HotCarTracker`: pings, expiry and jamming |
| `chop_shop.gd` | `ChopShop`: the drop-off pad and payouts |
| `vehicle_class.gd` / `vehicle_tuning.gd` (in `scripts/vehicles/`) | Shared `VehicleClass` table and `VehicleTuning` handling knobs |
| `jam_zone.gd` | Parking garage that blocks tracker signals |
| `pursuit_cruiser.gd` | Simple AI police car that chases tracker pings |
| `fleeing_driver.gd` | Victim who runs off after being pulled out |
| `car_crew.gd` | `CarCrew`: seats an animated driver in a car and tints its cabin glass |

The police countdown and response reuse `scripts/gameplay/hit_common/` (`PoliceCall`, `PoliceResponse`, `Cop`). There is no wanted-star system yet.

## Tests

`tests/carjack_tests.gd` runs as part of `res://tests/test_runner.tscn`. To run only the carjack tests:

```sh
godot --headless --path . res://tests/carjack_test_runner.tscn
```