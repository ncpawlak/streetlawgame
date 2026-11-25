# Cash van hit driver

A self-contained, playable version of the I-59 cash van hit (#23 in `docs/design/NORTH_END_HITS.md`). It isn't connected to the city map.

```sh
godot --path . res://drivers/cash_van/cash_van_driver.tscn
```

## Flow

1. **Chase.** You start in a getaway car with an assault rifle and an SMG, about 80 m behind the van on a looping highway. The van cruises at about 61 km/h, and your car is faster.
2. **Tires.** Each of the 4 tires (FL/FR/RL/RR) has its own hitbox and 45 hp. Hits on the armoured hull do nothing except raise the alarm. Each flat slows the van to 80%, then 62%, then 45% of its speed, and the van leans toward the flat side. After 4 flats it brakes to a stop.
3. **Guards.** When the van stops, 3 armed guards get out (SMG, shotgun and pistol, 90 hp each) and fight.
4. **Police.** The first shot at the van starts the hit clock and a 20 s panic-button countdown. Gunshots near the van also count. Heat is `1 + hit_time / 20 s`. Every police wave sends `heat` pursuit cruisers from behind (up to 6 at once) and `heat - 1` foot cops at a roadblock ahead. A new wave comes every 20 s while you're wanted. Cruisers ram your car, and their officers get out when you're on foot, slow, or have wrecked the cruiser.
5. **Doors.** The rear doors are locked. Go to the van's **front** (cab) and hold **E** for 1.2 s to release them. This only works once the van has stopped.
6. **Loot.** The cargo is 4 cash sacks ($650, 2 slots each), 3 cash bundles ($250, 1 slot) and a coin bag ($120, 1 slot). That's 12 slots of cargo for an 8-slot bag, so you have to choose what to take. Hold **E** on an item to bag it.
7. **Escape.** Get more than 50 m from where the police last saw you and stay unseen for 12 s.
8. **Stash.** Hold **E** at the stash garage in the infield (map origin) to cash in. You can't cash in while you're wanted. If you die while wanted, you're busted and drop the bag.

Press **F5** to restart.

## Files

| File | Purpose |
| --- | --- |
| `cash_van_driver.gd/.tscn` | Scene root. Sets up the scene, tracks phases, runs escalation and the HUD objective. |
| `highway_route.gd` | Stadium-loop highway (Curve3D), ground and roadside blocks. |
| `armored_van.gd` | Van movement, state, door release and loot. |
| `van_tire.gd` | A single shootable tire. |
| `van_guard.gd` | Armed guard (extends `GangMember`). |
| `pursuit_cruiser.gd` | Police car that chases and rams you, then lets its officers out. |

The carry bag, police call/response, escape, stash and HUD come from the shared `scripts/gameplay/hit_common/` package.

## Tests

`tests/cash_van_tests.gd` runs as part of `res://tests/test_runner.tscn`.
