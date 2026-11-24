# North End — hit locations (Zone 1, milestone "North End vertical slice")
North End is tier 1, the start area. Districts: **Tamarack Row ★**, **Northgrove**, **Mangona**.
The rival here is the **Red Vipers** (existing `vipers` gang). At the start they hold all three districts, and you begin with a foothold in Tamarack Row.
Heists are excluded (#42).

## Design goals for Zone 1
- **Teach every core event once:** burglary, hold-up, targeted theft, raid, interrupt, intercept, jack.
- **Small payouts** (tier 1 prices; a tier-1 business is $8k–20k). A full clear of the zone should fund 2–3 businesses.
- **Hit the Vipers to weaken them:** robbing Viper turf gains clout for you and takes it from them, which opens districts for capture.
- **Every target has a walkable interior,** using shared greybox templates.

## Interior templates (reused across zones)
| Template | Used by |
|---|---|
| `shotgun_house` | Tamarack Row houses |
| `bungalow` | Northgrove houses |
| `apartment_unit` | Northgrove apartments (several units per building) |
| `small_shop` (front + back room + safe) | Bodega, liquor, gas station, pawn, electronics, pharmacy, barbershop, tattoo |
| `bank_branch` (lobby, teller line, back office, small vault door) | Northgrove bank (hold-up only; vault reserved for #42) |
| `fortified_house` | Viper trap and stash houses |
| `garage_yard` | Chop shop, junkyard, Viper front |

## Roster
**Loot** is per run. **CD** is the cooldown before the place can be hit again (in-game time).
**🏪 = a buyable business site (#36).** You can rob it until you own it.

### Tamarack Row ★ (start: Vipers on the fringe, you take it first)
| # | Hit location | Target | Events | Tier | Loot | CD | Heat | Notes |
|---|---|---|---|---|---|---|---|---|
| 1 | Tamarind Ave houses ×6 | House | Burglary | 1 | $50–150 + 1–2 goods (TV, laptop, jewelry box) | 1 day each | Low | Tutorial burglary. Best when the owners are out (night or work hours) |
| 2 | Track-side duplexes ×2 | House (2 units) | Burglary, Targeted ("the landlord's cash box") | 1–2 | $100–300 | 1 day | Low | The targeted job is a tip from the bodega clerk |
| 3 | 🏪 Tamarack Bodega | Bodega | Hold-up, Burglary | 1 | $150–400 register, +$300 safe | 6 h | Medium | Tutorial hold-up. Buyable site |
| 4 | 🏪 Row Liquors | Liquor store | Hold-up, Burglary | 1 | $200–500; goods: crates (molotov mats) | 6 h | Medium | |
| 5 | 🏪 Fresh Cutz Barbershop | Barbershop | Hold-up | 1 | $100–250 | 6 h | Low–med | Hitting it costs clout locally. Better bought, since it's the recruiting spot |
| 6 | Sunoco-style gas station "Gas-N-Go" | Gas station | Hold-up, Burglary | 1 | $200–450 | 6 h | Medium | On the edge by I-59, an easy escape route |
| 7 | **Viper corner** (Tamarind & 15th) | Park/corner | **Interrupt** (Viper hand-to-hand deal) | 2 | $300–600 + 2–4 units weed | Tip-driven, ~1/day | Medium | **First world event.** Tip from the barbershop. Clout swing vs the Vipers |
| 8 | **The Spot**: Viper trap house | Rival trap | **Raid** → take over / torch | 2 | $800–1.5k + weed stash | — (one-time takeover; can be retaken) | Medium | **Story beat: your first trap house.** Feeds Operations (#14/#27) |

### Northgrove (arts strip, hospital, bank; Vipers hold it)
| # | Hit location | Target | Events | Tier | Loot | CD | Heat | Notes |
|---|---|---|---|---|---|---|---|---|
| 9 | Bungalow row ×5 | House | Burglary, Targeted ("artist's painting") | 1–2 | $100–250 + goods (art, jewelry) | 1 day | Low | The painting job is a tip from a bar/informant and pays a client bonus |
| 10 | Grove Apartments (4 units) | Apartment | Burglary | 1 | $50–200 per unit + goods | 1 day per unit | Low | Vertical interior: hallway + units. Neighbors are witnesses |
| 11 | 🏪 Northgrove Pawn | Pawn shop | Hold-up, Burglary, Targeted ("the gold chain in the case") | 1–2 | $300–700; goods: jewelry, guns | 8 h | Medium | Rob it now or buy it later (it's also the fence) |
| 12 | 🏪 Grove Pharmacy | Pharmacy | Hold-up, Burglary (pills = product) | 1 | $200–400 + pills (precursor for #27) | 8 h | Medium | Burglary loot can go into Operations |
| 13 | 🏪 Ink Lab Tattoo | Tattoo parlor | Hold-up | 1 | $150–300 | 6 h | Low–med | |
| 14 | Wired Electronics | Electronics | Hold-up, Burglary, Targeted ("prototype phones") | 1–2 | $300–600; goods: phones, laptops | 8 h | Medium | Non-buyable shop, high goods value |
| 15 | Northgrove Savings (bank branch) | Bank branch | **Hold-up** (teller drawers only) | 2 | $1k–2.5k | 2 days | High | The biggest Zone 1 cash score. The vault is locked until #42 |
| 16 | **Viper stash house** (behind the hospital) | Rival stash | **Raid**, Targeted ("Viper ledger") | 2 | $1k–2k + weed/pills | 3 days | Medium | The ledger reveals Viper tips: corner deals and the van route |

### Mangona (chop shops, lake, I-59; Vipers' muscle)
| # | Hit location | Target | Events | Tier | Loot | CD | Heat | Notes |
|---|---|---|---|---|---|---|---|---|
| 17 | Lakeside trailers / shacks ×4 | House | Burglary | 1 | $50–150 + goods (tools, scrap) | 1 day | Low | Cheap, quiet, good for practice |
| 18 | 🏪 Mangona Guns & Ammo | Gun store | Hold-up, Burglary (guns = goods) | 1–2 | $300–600; goods: guns | 12 h | **High** | Armed clerk. Worth buying, since it gives half-off guns |
| 19 | 🏪 Mangona Hardware | Hardware | Hold-up, Burglary | 1 | $150–350; goods: tools, lab gear | 8 h | Low–med | Lab gear can go into Operations |
| 20 | 🏪 Lakeside Chop Shop | Chop shop | Hold-up | 1 | $200–400 | 8 h | Medium | Also the drop-off for jacked cars |
| 21 | Lake Mangona junkyard | Junkyard | Burglary (parts) | 1 | Goods: car parts | 1 day | Low | Feeds car upgrades later (#13) |
| 22 | **Viper Garage** (front) | Rival front | **Raid** | 2 | $800–1.5k + guns | 3 days | Medium–high | Existing `rival_front`. Clearing it is the big clout swing for capturing Mangona |
| 23 | **Viper cash van**, route along I-59 / Mangona | Armored van | **Intercept** | 2 | $1.5k–3k | Tip-driven, ~1 per 2 days | High | Tip from the Viper ledger (#16) |
| 24 | **Hot car list**: 3 cars parked around North End | High-end car | **Jack** → deliver to the chop shop | 1–2 | $400–1.2k per car | Rotates daily | Medium | The list comes from the chop shop owner |
| 25 | **Plug rip-off**: Viper weed buy at the lake boat ramp | Plug meet | **Interrupt** | 2 | $1k–2k + weed bulk | Tip-driven, ~1 per 3 days | Medium–high | Uses the existing `weed_plug_meet` |

## Totals
- **~45 robbable spots:** 17 houses/units + 13 stores/shops (6 of them buyable sites) + 1 bank + 3 gang targets + 4 world-event and vehicle jobs. Some rows cover several spots.
- **Every event type is taught**, except heist.
- **Rough payout for one full sweep:** about $15–25k, which funds 2–3 tier-1 businesses. That matches the business plan.

## Intended first-hour flow
1. Burgle a Tamarind house (tutorial) → fence the goods at Northgrove Pawn.
2. Hold up the Tamarack Bodega (tutorial hold-up, heat).
3. The barbershop tip reveals the **Viper corner deal** → crash it (first world event).
4. **Raid The Spot** → take it over → your first trap house (tutorial for Operations).
5. Capture Tamarack Row → buy your first business.
6. Expand: Northgrove (bank teller job, stash house → ledger) → Mangona (Viper Garage, cash van, plug rip-off).

## Data needed (when built)
- `HitTargetDef` per row (reusing existing LocationDefs where they fit: `house`, `corner_store`, `rival_front`, `bottoms_trap_house`, `weed_plug_meet`).
- `HitEventDef`s:
  - `burglary`, `holdup`
  - `targeted_*` ×6: landlord box, painting, gold chain, prototype phones, Viper ledger, plus one spare
  - `raid`, `interrupt_corner_deal`, `interrupt_plug_buy`, `intercept_cash_van`, `jack_hot_car`
- Tips:
  - Bodega clerk → landlord box
  - Barbershop → corner deal
  - Bar/informant → painting and phones
  - Viper ledger → van route and plug buy
  - Chop shop owner → hot car list
- Hot goods: TV, laptop, jewelry, art, phones, guns, tools, pills, car parts, crates.

## Decisions
1. Tamarack Row starts in **Red Vipers** hands; you take it during the opening.
2. The Northgrove bank allows a **teller hold-up only**. The vault is saved for #42.
3. The North End rival stays the **Red Vipers**.
4. Own-turf rule confirmed: rival turf gives you +clout and them −clout; neutral has no change; your own turf costs −clout and adds extra heat; businesses you own can't be robbed.