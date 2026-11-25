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

| Car | Value | Notes |
| --- | --- | --- |
| Sedan | $1,200 | parked |
| Sports coupe | $3,500 | parked, tracker |
| SUV | $2,200 | occupied |
| Muscle car | $2,800 | parked, tracker |

## Minigames (prototypes, swappable)

The final minigame hasn't been decided, so there are three prototypes. They all share one interface, `CarjackMinigame` in `minigames/carjack_minigame.gd`:

- `begin(car)`, `tick(delta)`, `press_primary()`, `press_option(i)`, `cancel()`
- signals `finished(success, reason)`, `too_slow`, `cancelled`

| Kind | Script | How it plays |
| --- | --- | --- |
| `lock_pick` | `lock_pick_minigame.gd` | A needle sweeps across a bar. Press E/Space inside the green zone to set a pin. 3 pins wins, 3 misses snaps the pick. The zone shrinks and the needle speeds up with each pin. |
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

These map to the command-line args `--minigame=auto|lock_pick|hotwire|struggle`, `--tracker=per_car|always|never` and `--difficulty=easy|normal|hard`, and to the matching exports on `CarjackDriver`.

## Files

| File | Purpose |
| --- | --- |
| `carjack_driver.gd` / `.tscn` | World builder, jack flow, alarms, tracker → police wiring, respawns, debug keys |
| `carjack_hud.gd` | Objective / police / tracker lines and the debug panel |
| `hot_car.gd` | `HotCar` (a `Vehicle`): locked / occupied / stolen state, the Jack interaction, the alarm |
| `hot_car_tracker.gd` | `HotCarTracker`: pings, expiry and jamming |
| `chop_shop.gd` | `ChopShop`: the drop-off pad and payouts |
| `jam_zone.gd` | Parking garage that blocks tracker signals |
| `pursuit_cruiser.gd` | Simple AI police car that chases tracker pings |
| `fleeing_driver.gd` | Victim who runs off after being pulled out |

The police countdown and response reuse `scripts/gameplay/hit_common/` (`PoliceCall`, `PoliceResponse`, `Cop`). There is no wanted-star system yet.

## Tests

`tests/carjack_tests.gd` runs as part of `res://tests/test_runner.tscn`. To run only the carjack tests:

```sh
godot --headless --path . res://tests/carjack_test_runner.tscn
```