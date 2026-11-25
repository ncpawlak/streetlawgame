# World scale reference

1 Godot unit = 1 metre. Use the animated character (`CharacterVisual`, normalised to a
1.8 m human) as the yardstick when sizing anything new.

## People

| Thing | Size |
|---|---|
| Character model height | 1.8 m (women models ~1.7 m; scale is shared) |
| Head bone / eye line | ~1.5 m |
| Right hand (relaxed) | ~1.0 m; aimed gun ~1.3 m high, ~0.45 m in front |
| Player / NPC collision capsule | radius 0.4 m, height 1.8 m |
| Player camera pivot | 1.6 m |
| Walk / run animation speeds | 1.6 m/s / 5 m/s (clips time-scale to match velocity) |

## Vehicles

| Thing | Size |
|---|---|
| Car body | 1.9 × 1.0 × 4.2 m (W × H × L), centre at y 0.9 |
| Car cabin | 1.7 × 0.6 × 2.0 m, centre at y 1.7 (roof ≈ 2.0 m) |

## Buildings and doors

| Thing | Size |
|---|---|
| Exterior door greybox | 1.6 × 2.6 × 0.25 m |
| Interior door | 1.4 × 2.4 × 0.1 m |
| Storey height | ~3.0–3.5 m (trailer 3.2 m single storey) |
| Garage | 7–8 m |
| Hospital | 24 m (~7 storeys) |
| Sidewalk kerb | 0.1 m |

## Roads (`city_generator.gd`)

| Class | Width |
|---|---|
| Local | 9 m |
| Avenue | 12 m |
| Arterial | 16 m |
| Highway | 26 m (deck at 6.5 m) |
| Ramp | 8 m |

Map extraction uses 2.0 m per wireframe pixel (`METERS_PER_PX`), raised from 1.2 so every census lot fits the building kit at full size. Road corridors keep their 1.2 m/px authoring widths in px; drawn roads stay 9/12/16 m, leaving a grass swale to the block pads.

Rules of thumb: a doorway should clear the 1.8 m model's head by ≥ 0.4 m; a
storey is about two characters tall; a car is about 2.3 character-heights long.
