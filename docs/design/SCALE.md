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

## Burglable houses (`house_layouts.gd`, `house.gd`, `house_entry.gd`)

Plans are authored on a compact grid and stretched by `HouseLayouts.PLAN_SCALE` (1.4). Furniture keeps
its real size and stays against whichever wall it was against.

| Thing | Size |
|---|---|
| Walls / ceiling | 3.0 m tall, 0.2 m thick |
| Doors | ≥ 1.2 m clear (`MIN_DOOR_WIDTH`), 2.4 m tall; patio 2.0 m |
| Archways | 1.6–2.25 m wide, 2.5 m tall |
| Windows | sill 0.9 m, top 2.3 m, 0.9–2.0 m wide |
| Footprint | low 14 × 11.2 m, medium 19.6 × 14 m, high 28 × 19.6 m |
| Rooms | ≥ 4.2 m across (bathrooms) up to 11.2 × 8.4 m (high living room) |
| Security cameras | 2.8–2.9 m up |

Every door and arch must let the 0.8 m player capsule walk from 1 m out on one side to 1 m out on
the other (`HouseRobberyTests._test_walkthrough`).

## Roads (`city_generator.gd`)

| Class | Width |
|---|---|
| Local | 9 m |
| Avenue | 12 m |
| Arterial | 16 m |
| Highway | 26 m (deck at 6.5 m) |
| Ramp | 8 m |

Map extraction uses 1.2 m per wireframe pixel (`METERS_PER_PX`).

Rules of thumb: a doorway should clear the 1.8 m model's head by ≥ 0.4 m; a
storey is about two characters tall; a car is about 2.3 character-heights long.
