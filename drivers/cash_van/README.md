# Cash van hit driver

A self-contained, playable version of the I-59 cash van hit (#23 in `docs/design/NORTH_END_HITS.md`). It isn't connected to the city map.

```sh
godot --path . res://drivers/cash_van/cash_van_driver.tscn
```

## Flow

0. **Intel briefing.** Before the hit, an intel card and a map of I-59 show what the crew knows (the HIT_LOOP scout step). With intel you get:
   - **Route:** the loop, the van's lane and speed, and its on-ramp. The route is drawn on the map and marked on the road with orange chevrons and an on-ramp beacon.
   - **Schedule:** when the van leaves, plus the lap time.
   - **Guards:** how many and what they carry (SMG, shotgun, pistol), and whether there's a panic button.
   - **Cargo:** what's in the van and how much it's worth (about $3,470 in 12 slots).

   Press **Enter** to start, and the departure countdown begins. Without intel, everything shows "UNKNOWN", nothing is marked, and the van joins the loop at a random point after a random 8–25 s wait. You have to find it. **[I]** reopens the card. **[F6]** is a debug toggle that switches intel on/off and restarts. You can also launch with `-- --no-intel`.
1. **Chase.** You start in a getaway car with an assault rifle and an SMG. The van cruises at about 61 km/h, and your car is faster.
2. **Tires.** Each of the 4 tires (FL/FR/RL/RR) has its own hitbox and 45 hp. Hits on the armoured hull do nothing except raise the alarm. Each flat slows the van to 80%, then 62%, then 45% of its speed, and the van leans toward the flat side. After 4 flats it brakes to a stop.
3. **Guards.** When the van stops, 3 armed guards get out (SMG, shotgun and pistol, 90 hp each) and fight.
4. **Police.** The first shot at the van starts the hit clock, and the guards press a **silent** 20 s panic button. You only find out with 10 s left, unless you brought a lookout. Gunshots near the van also count. Heat is `1 + hit_time / 20 s`. Every police wave sends `heat` pursuit cruisers from behind (up to 6 at once) and `heat - 1` foot cops at a roadblock ahead. A new wave comes every 20 s while you're wanted. Cruisers ram your car, and their officers get out when you're on foot, slow, or have wrecked the cruiser.
5. **Doors.** The rear doors are locked. Go to the van's **front** (cab) and hold **E** for 1.2 s to release them. This only works once the van has stopped.
6. **Loot.** The cargo is 4 cash sacks ($650, 2 slots each), 3 cash bundles ($250, 1 slot) and a coin bag ($120, 1 slot). That's 12 slots of cargo for an 8-slot bag, so you have to choose what to take. Hold **E** on an item to bag it.
7. **Escape.** Get more than 50 m from where the police last saw you and stay unseen for 12 s.
8. **Stash.** Hold **E** at the stash garage in the infield (map origin) to cash in. You can't cash in while you're wanted. If you die while wanted, you're busted and drop the bag.

Press **F5** to restart.

## Heat, mask and crew (shared `hit_common`)
- **Carry-over heat.** Every cash van hit counts towards the `I-59` [HeatMap] area. When a hit ends (cash-in, bust or F5), the area gains +20 heat, or +35 if the police were called. Heat decays over time.
  - Extra police: each wave gets `HeatMap.extra_cops("I-59")` extra foot cops **and** extra cruisers.
  - Faster calls: the panic countdown runs shorter, down to 60%.
  - Smaller payout: the fence pays less for goods, down to 40%.
- **Mask [X].** If you're unmasked on the first shot, the van's dash cam gets your face (+25 personal heat). Either way, the chase car is noted as the seen car. A blue **swap car** is parked by the stash. Mask off in the swap car, and heat drops ×4 and the cops lose you ×4 faster. Staying in the chase car or keeping the mask on only gives ×0.6.
- **Crew** (F9 lookout, F10 driver, F11 muscle; each takes a 10% cut):
  - **Lookout:** waits on the shoulder by the on-ramp. Reveals the silent panic-button call the moment it's pressed and buys ×1.35 time.
  - **Driver:** rides in the chase car. Escape ×1.5 while you're in it.
  - **Muscle:** follows you on foot. Guards within 7 m put their hands up and stop shooting (`VanGuard` is in group `hostages` with `hold(by)`).
- The briefing card and the status label show the crew, the I-59 heat, the extra cops and the mask/swap state. F12 adds 25 heat; Shift+F12 clears it.

## Files

| File | Purpose |
| --- | --- |
| `cash_van_driver.gd/.tscn` | Scene root. Sets up the scene, tracks phases, runs escalation and the HUD objective. |
| `highway_route.gd` | Stadium-loop highway (Curve3D), ground and roadside blocks. |
| `armored_van.gd` | Van movement, state, door release and loot. |
| `cash_van_intel.gd` | Intel data: route, schedule, guards and cargo, known or unknown. |
| `intel_briefing.gd` | The pre-hit briefing card and route map. |
| `van_tire.gd` | A single shootable tire. |
| `van_guard.gd` | Armed guard (extends `GangMember`). |
| `pursuit_cruiser.gd` | Police car that chases and rams you, then lets its officers out. |

The carry bag, police call/response, escape, stash and HUD come from the shared `scripts/gameplay/hit_common/` package.

## Tests

`tests/cash_van_tests.gd` runs as part of `res://tests/test_runner.tscn`.
