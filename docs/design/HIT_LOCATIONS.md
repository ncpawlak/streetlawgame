# Hit locations — plan (draft v1)
Covers #15 (robberies), #14 (trap houses) and the hit side of #37 (markers).

## Core idea: **Target × Event**
- A **target** is *where* you hit, e.g. a jewelry store.
- An **event** is *what kind of job* it is: holding up the register, burgling it after hours, stealing one specific necklace for a client, or a full heist on the vault.
- The same place supports several events, and the event decides the gameplay, tier, loot and heat.
- Some events are **world events**. They happen at a time and place, show on the map with a timer, and you choose whether to crash them, e.g. a rival gang doing a deal in the park.

## Decisions so far
- **Categories:** all 10 are in, grouped into 4 target families.
- **Depth:** tiered, and **every target has a walkable interior**. Small jobs are quick in-and-out runs inside; big jobs are multi-stage missions.
- **Loot:** cash is instant. Goods (jewelry, electronics, art, product, cars) are **hot goods** that you carry and turn in for cash.
- **Trap houses:** both. Raid rival traps to take them over, and run your own with crew dealers.
- **Own turf:** see the recommendation below.
- **Failure:** lose hot goods + a cash deduction.
- **World events:** visible only after a tip.
- **Heists:** separate design discussion in #42.

## Target families
| Family | Targets | Interior |
|---|---|---|
| **Residential** | House, apartment, mansion (Palm Isle) | House/apartment templates; mansions are large, multi-room and guarded |
| **Commercial** | Gas station, bodega, liquor store, pawn shop, electronics, **jewelry store**, bank branch, **main bank** (Downtown) | Shopfront + back room + safe; banks add a vault |
| **Gang** | Rival trap house, rival stash house, rival front | Fortified house, defenders, product and cash |
| **Mobile** | Armored truck / cash van, high-end vehicles, rival deal convoys | The vehicle itself, or a meet spot |

## Events (job types)
| Event | Tier | Gameplay | Typical loot |
|---|---|---|---|
| **Burglary** | 1–2 | Sneak in (better at night or when empty), grab what you can carry, get out. Quiet if you aren't seen | Hot goods, some cash |
| **Hold-up** | 1 | Intimidate the clerk, empty the register (and the safe if you stay longer); an alarm timer starts | Cash |
| **Targeted theft** | 2 | A tip names one item (a necklace, a painting, a ledger). Find it inside and get it out | One high-value hot good |
| **Heist** | 3 | Multi-stage mission. **Design deferred to #42** | Big cash + hot goods |
| **Raid** | 2–3 | Assault a gang target, clear the defenders, crack the stash | Cash, product, guns. Traps can then be taken over |
| **Interrupt** | 2 | Timed world event (rival deal, plug meet, drop-off). Crash it, ambush the deal and rob both sides | Cash + product |
| **Intercept** | 2 | A moving armored truck or cash van on a route. Stop it, breach it and escape | Cash |
| **Jack** | 1–2 | Steal a specific high-end car (sometimes on a list) and deliver it to a chop shop | The vehicle → cash |

### Which events each target supports
| Target | Burglary | Hold-up | Targeted | Heist | Raid | Interrupt | Intercept | Jack |
|---|---|---|---|---|---|---|---|---|
| House / apartment | ✅ | | ✅ | | | | | |
| Mansion | ✅ | | ✅ | ✅ | | | | ✅ (garage) |
| Gas station / bodega / liquor | ✅ | ✅ | | | | | | |
| Pawn / electronics | ✅ | ✅ | ✅ | | | | | |
| Jewelry store | ✅ | ✅ | ✅ | ✅ | | | | |
| Bank branch | | ✅ | | ✅ (small) | | | | |
| Main bank (Downtown) | | | | ✅ (big) | | | | |
| Rival trap / stash house | | | ✅ (ledger, plug contact) | | ✅ | | | |
| Rival front | | | | | ✅ | | | |
| Park / corner / lot | | | | | | ✅ (rival deal) | | |
| Plug meet | | | | | | ✅ (rip-off) | | |
| Armored truck / van | | | | | | | ✅ | |
| High-end cars | | | | | | | | ✅ |

## Tiers
| Tier | Shape | Unlocked by |
|---|---|---|
| **1 Quick** | Walk in, act, leave (~1–2 min). Always available, short cooldown | Nothing |
| **2 Job** | Needs a **tip** (intel) and maybe one prep step (get a tool or a car). Shows on the map once known | Intel from bars, informants, Social businesses (#36) |
| **3 Mission** | Multi-stage with crew roles and a getaway. Story-like | Respect / clout and a prep chain |

## Loot and hot goods
- **Cash** goes straight to your wallet.
- **Hot goods** take carry slots, so you can only carry a few. Each one has a value and a **heat tag**. Dying or getting busted drops them.
- **Turning goods into cash:**
  - **Fence at a pawn shop:** 40% of value, or **70% at a pawn shop you own** (#36).
  - **Drop at a safehouse stash** to bank them safely and sell later. The heat tag cools over time.
  - **Cars** go to a chop shop (better rate if you own it). **Product** goes into your Operations stock (#27).
  - **Special buyers:** targeted-theft items go to the client who sent the tip, for a bonus.

## Robbing inside your own turf (my recommendation)
| Where | Allowed? | Clout | Notes |
|---|---|---|---|
| **Rival turf** | Yes | **+clout for you, −clout for them** | Hitting rivals weakens their hold and softens the district for capture. This is the main loop |
| **Neutral / unclaimed** | Yes | none | Normal heat |
| **Your own turf** | Yes | **−clout** (locals turn on you) and extra heat | Allowed but costly, so you don't farm your own blocks |
| **Your own businesses** | **No** | — | Can't rob what you own |

This makes robbery a weapon in the turf war, not just a money tap.

## Trap houses
- **Rival trap:**
  1. Raid it: clear the defenders and crack the stash.
  2. Choose **Take over** (it becomes yours) or **Torch** (bigger clout hit to the rival, no property).
- **Your trap:** it plugs into Operations (#27) for production and sales.
  - Assign crew dealers to nearby corners and parks for income.
  - Risks: police raids (more heat → more risk) and rival raids (#8).
- **Trap houses are territory markers** (#37), so owning them adds clout and district control.

## World events
- A scheduler spawns timed events in the city: rival deals, plug meets, armored-truck runs and drop-offs.
- Each has a map icon, a countdown and a heat/defense level.
- You find them through **intel**: bar and informant tips, or crew spotting them in your turf. Events only appear on your map once you have a tip.

## Heat (ties to #6)
| Event | Heat |
|---|---|
| Burglary | Low if unseen; rises if a witness or alarm |
| Hold-up | Medium + alarm timer |
| Targeted theft | Low–medium |
| Raid / interrupt | Medium (gunfire) |
| Intercept | High |
| Heist | Very high + a police response wave during the getaway |
| Palm Isle (any) | Always max (map decision) |

## North End content (for the future vertical slice, not built yet)
| District | Hit locations |
|---|---|
| Tamarack Row ★ | 6–8 houses, 1 gas station, 1 bodega, 1 rival corner deal (interrupt), *your first trap house* (tutorial takeover) |
| Northgrove | Apartments, bungalows, pawn/electronics, 1 bank branch, 1 rival stash house |
| Mangona | 1 rival trap house, 1 rival front, chop-shop car list (jack), armored-van route along I-59 |

## Engineering sketch (when we build it)
- **`HitTargetDef`:** extends LocationDef or sits alongside it. Family, interior template, supported events, defenders, loot table, cooldown.
- **`HitEventDef`** (ContentDef): tier, stages (each a list of Conditions/Costs/Effects), heat profile, loot rules, intel requirement.
- **`HotGoods`:** inventory slots, value, heat tag, drop on death.
- **`FenceService`:** pawn-shop sell action; the rate depends on site ownership (#36).
- **`WorldEventScheduler`:** autoload that spawns timed events with map markers.
- **Reuse:** the existing `rob_location_effect`, `take_out_effect`, `PocketInterior`, Locations and Operations.
- **Build order:**
  1. Tier-1 burglary + hold-up with hot goods and a fence.
  2. Raid + trap takeover.
  3. World events (interrupt, intercept).
  4. Targeted theft + tips.
  5. Heists (#42).

## Failure and visibility (decided)
- **Failed job:** if you're busted or killed mid-job, you **lose all hot goods you're carrying**, plus a **cash deduction** (a % of your wallet, like bail or a hospital bill). You keep your crew and property.
- **World events need a tip:** timed events (rival deals, plug meets, armored-truck runs) only show on the map **after you've got a tip**. Tips come from bars, informants, Social businesses or crew in your turf. Without one, you can still stumble on an event in person.