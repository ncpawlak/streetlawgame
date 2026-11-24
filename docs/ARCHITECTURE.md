# Architecture

Godot 4.7, GDScript, Forward+ renderer.

## Folder layout

```
project.godot          Engine config (autoloads, layers)
scenes/                .tscn scenes (main, player, ui...)
scripts/
  autoload/            Global singletons (see below)
  combat/              Shared combat logic (Hitscan, Projectile, Explosion, FireZone, WeaponInventory, WeaponSlot, WeaponPickup)
data/weapons/          WeaponData .tres files, one per weapon id
  data/                Resource classes for data-driven content (weapons, businesses, crew)
  npc/                 AI characters (GangMember)
  player/              Player controller
  ui/                  HUD and menus
  vehicles/            Vehicle controller
  world/               Main scene, city generation, territories
assets/                Models, textures, audio (binary files; consider Git LFS once large)
tests/                 Headless smoke tests
docs/                  Design & architecture docs
```

## Autoloads

| Name | Role |
| --- | --- |
| `InputSetup` | Registers input actions in code so bindings are readable and diffable. |
| `EventBus` | Global signals (`cash_changed`, `territory_captured`, `notify`...). Systems talk through it instead of referencing each other. |
| `GameState` | Run state: cash, respect, gangs, territories, businesses, crew, income timer. Future save/load serializes this. |

## Key classes

| Class | Extends | Responsibility |
| --- | --- | --- |
| `Player` | `CharacterBody3D` | On-foot movement, orbit camera, shooting, entering vehicles, health and respawn. |
| `Vehicle` | `VehicleBody3D` | Driving, chase camera, drive-by shooting, running over NPCs, health/crash damage, smoke/fire/explode states. Built in code. |
| `GangMember` | `CharacterBody3D` | Rival NPC: wander, aggro, shoot, die and drop rewards. |
| `Territory` | `Node3D` | District bounds, owner gang, capture logic, map overlay. |
| `CityGenerator` | `Node3D` | Deterministic greybox city: roads, buildings, districts, defenders, parked cars. |
| `Hitscan` | `RefCounted` | Shared instant-hit firing (pellets, damage scale), aiming from the camera, tracers. |
| `Projectile` | `Node3D` | Thrown/launched explosives: ray-stepped flight, bounce/stick/explode on impact, fuses and remote detonation. |
| `Explosion` | `Node3D` | `detonate()`: radius damage with falloff and line of sight, physics impulse, visual, `EventBus.explosion`. |
| `FireZone` | `Area3D` | Burning area left by molotovs; damages bodies inside over time. |
| `WeaponInventory` | `Node` | Carried weapons, selection, fire rate, ammo and reload. Shared by `Player` and `GangMember`. |
| `WeaponSlot` | `RefCounted` | One carried weapon: `WeaponData` + magazine/reserve ammo. |
| `WeaponPickup` | `Area3D` | World pickup that grants a weapon or ammo. |
| `WeaponWheel` | `Control` | Radial selector; pauses the tree while open (`PROCESS_MODE_ALWAYS`). |
| `WeaponData`, `BusinessData`, `CrewMemberData` | `Resource` | Data-driven content definitions. |

## Conventions

- **Damage:** anything with `take_damage(amount: float, source: Node)` can be shot.
- **Decoupling:** emit on `EventBus` for cross-system events, and read shared state from `GameState`.
- **Physics layers:** 1 `world`, 2 `player`, 3 `npc`, 4 `vehicle`.
- **Render layers:** layer 2 `map_only` holds overlays and markers that only the minimap camera renders. Gameplay cameras mask it out.
- **Groups:** `player`, `vehicles`, `gang_members`, `projectiles`, `fires`.
- **Content as data:** new guns, businesses and so on should be `.tres` resources, not new code paths.
- Tabs for indentation, static typing everywhere (`:=`, typed params and returns).

## Testing

```sh
godot --headless --path . res://tests/test_runner.tscn
```

Exits non-zero on failure. Add a check to `tests/run_tests.gd` for every new gameplay rule.
