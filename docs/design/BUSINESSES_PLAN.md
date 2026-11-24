# #36 Businesses — plan (draft v2: repeat sites)

## Decisions so far
- **Repeat businesses:** a business is a **type** (gun store, bodega…) placed as many **sites** across the map. For example, there are 4 gun stores, so one is always within reach.
- **Who can buy a site:** only in districts your gang controls.
- **Hangar** (PCI Airport, neutral): cash only, very expensive (~$2.5M). Not tied to turf.
- **Passive income:** yes, every site pays per cycle.
- **Rivals:** they raid sites, the hangout crew defends, and you can lose a site. Raids are a follow-up and tie into #8.
- **Discount:** per site (only the sites you own).
- **Clout:** defense, economy, purchase unlocks, and **area influence levels** that upgrade your gang's vehicles, weapons and crew size there.

## Data model
- **BusinessTypeDef** (~27 types): category, merchandise list, unlock effects, base price, base income, hangout crew count, clout value.
- **BusinessSiteDef** (~80 sites): type, district, display name (e.g. "Mangona Guns & Ammo"), and an optional price/income override.
  - Price and income = type base × the district's **tier multiplier**.
  - The same gun store costs more in Downtown than in North End.
- Ownership is **per site**. Every site you own gives its district clout, a hangout crew and income.

### Discount rule (decided)
- **Per site:** 50% off applies only at the sites you own. Owning the Mangona gun store doesn't discount the Riviera one, so owning shops near your turf matters.

## Categories
| Category | What owning it gives |
|---|---|
| **Retail** | 50% off its merchandise |
| **Service** | A service (vehicle storage and upgrades, haircuts, tattoos, training) |
| **Front** | High income + money laundering |
| **Social** | Recruits, intel, respect, meeting spots |
| **Logistics** | Stash, respawn point, imports, storage |

## Business types (27) and how many sites each
| Type | Category | Sites | Merch / unlock |
|---|---|---|---|
| Corner store / bodega | Retail | 7 | Health, snacks |
| Liquor store | Retail | 4 | Molotov ingredients, buffs |
| Gun store | Retail | 4 | Pistols, SMGs, shotguns, rifles, ammo (#12) |
| Surplus / explosives shop | Retail | 1 | Grenades, molotovs, C4, RPG (#12). Rare on purpose |
| Pharmacy | Retail | 4 | Health, drug precursors (#27) |
| Hardware store | Retail | 3 | Lab equipment, tools (#27) |
| Clothing / sneaker store | Retail | 3 | Outfits, gang colors (#39) |
| Car dealership | Retail | 3 | Vehicles |
| Jeweler | Retail | 1 | Bling (respect items); robbery-proof once owned |
| Chop shop / garage | Service | 4 | Vehicle storage, respray, upgrades (#13) |
| Barbershop | Service + Social | 4 | Hairstyles; recruits (#7) |
| Tattoo parlor | Service + Social | 3 | Tattoos, respect (#39) |
| Boxing gym | Service | 2 | Melee stats, tough recruits |
| Pawn shop | Front | 4 | Fence stolen goods from robberies (#15) |
| Laundromat | Front | 2 | Laundering |
| Car wash | Front | 3 | Laundering, quick vehicle repair |
| Check-cashing | Front | 2 | Laundering, loans |
| Nightclub / strip club | Social + Front | 2 | Big income, intel |
| Bar / lounge | Social | 5 | Intel, recruiting |
| Restaurant | Social | 6 | Health, meeting spot (missions / deals) |
| Recording studio | Social | 2 | Respect / clout boost |
| Motel | Logistics | 2 | Safe spot, respawn point |
| Hotel | Logistics | 1 | Luxury safe spot / respawn (the Breakwater) |
| Warehouse | Logistics | 3 | Stash capacity, product storage (#37) |
| Airstrip | Logistics | 2 | Plug imports (gated by the plug storyline) |
| Marina | Logistics | 3 | Boats (**deferred until boats exist**) |
| Hangar | Logistics | 1 | Premium vehicle storage; jets later. Neutral, ~$2.5M |
| **Total** | | **81** | |

## Sites by district (~3 per district)
| Area (tier) | District | Sites |
|---|---|---|
| **North End (1)** | Tamarack Row ★ | Corner store, Barbershop, Liquor store |
| | Northgrove | Pawn shop, Pharmacy, Tattoo parlor |
| | Mangona | Chop shop, Gun store, Hardware store |
| **Riviera (2)** | Riviera Heights | Corner store, Gun store, Car wash, Barbershop |
| | Port Palmetto | Warehouse, Chop shop, Bar |
| | Sandpiper Key | Marina, Restaurant, Liquor store |
| **South End (2)** | Grand Vista | Corner store, Pharmacy, Laundromat |
| | Del Sol | Recording studio, Restaurant, Tattoo parlor |
| | Pelican Park | Barbershop, Clothing store, Liquor store |
| | Southshore | Bar, Pawn shop, Car wash |
| **Worthing (3)** | Motel Row | Motel, Pawn shop, Check-cashing, Gun store |
| | Worthing | Bar, Tattoo parlor, Restaurant, Corner store |
| | Lantern Bay | Hardware store, Chop shop, Airstrip |
| **Westlands (3)** | Regal Palms | Car dealership, Gun store, Corner store |
| | Wellmont | Boxing gym, Restaurant, Pharmacy |
| | Greenhaven | Check-cashing, Laundromat, Barbershop, Liquor store |
| | Grassy Flats | Warehouse (stash) |
| **The Glades (3)** | Pahoka Shore | Corner store (bait & tackle), Bar (fish camp), Motel |
| | Cane Hollow | Surplus / explosives, Pawn shop, Corner store |
| | Sugarmill | Airstrip, Chop shop, Hardware store |
| **Downtown (4)** | Clement Street | Nightclub, Bar, Recording studio |
| | Rosewood Square | Clothing store, Car dealership, Boxing gym, Pharmacy |
| | Lagoon Front | Restaurant, Marina, Nightclub |
| **Palm Isle (5)** | Gilded Row | Jeweler, Clothing store, Car dealership |
| | Ocean Estates | Hotel, Restaurant, Warehouse |
| | Southpoint | Marina, Car wash |
| **Neutral** | PCI Airport | Hangar |

A few counts may drift as we tune. The point is that common types (bodega, bar, restaurant, gun store, chop shop) appear in most areas, and rare ones (explosives, jeweler, hangar) are destinations.

## Price tiers (multiplier on the type's base price)
| Tier | Areas | Multiplier | Example: gun store (base $15k) |
|---|---|---|---|
| 1 | North End | ×1 | $15k |
| 2 | Riviera, South End | ×2.5 | $37.5k |
| 3 | Worthing, Westlands, Glades | ×5 | $75k |
| 4 | Downtown | ×15 | $225k |
| 5 | Palm Isle | ×30 | $450k |

Income scales the same way. Base prices run from about $8k (bodega) to $40k (nightclub, dealership). The Hangar is a flat ~$2.5M.

## Clout (decided)
Clout is a **per-district** score, 0–100.
- **Raised by:** sites you own, hangout crew, captures and activities.
- **Lowered by:** raids, losing sites and police heat.

What clout does in a district:
1. **Defense:** high clout makes rival raids and counter-attacks rarer and weaker.
2. **Economy:** clout multiplies site income and drug-sale prices there (#27).
3. **Unlocks:** some sites need clout X in their district before you can buy them.
4. **Gang influence levels (per area):** the area's combined clout levels up your gang's influence there, from Lv 1 to Lv 5. Each level upgrades what your gang fields in that area.

| Influence | Example unlocks in that area |
|---|---|
| Lv 1 | Street crew on foot, pistols, beaters |
| Lv 2 | More members per hangout / squad, SMGs |
| Lv 3 | Better crew cars (lowriders, sedans), shotguns, crew can drive-by |
| Lv 4 | Armored crew, rifles, SUVs, faster backup |
| Lv 5 | Elite squads, heavy weapons, top-tier rides, max crew cap |

The loop: buy sites → clout → income + safer turf + influence level-ups → stronger gang there → take and buy the next district.

Not in v1: clout reducing police heat and rolling up into global respect. Revisit later.
## First PR — engineering scope
- `BusinessTypeDef` and `BusinessSiteDef` (extend ContentDef). They replace the old `scripts/data/business_data.gd`.
- `Businesses` autoload: per-site ownership, purchase (`TurfControlCondition` + `CashCost`), income tick, discount lookup and EventBus signals.
- **Shop system:** `ShopItemDef` + shop UI on the site's Location. Price is base × discount, when the player owns that site.
- Purchase as a door action on the LocationDef / Interactable framework.
- Hangout crew spawner: N idle crew around an owned site. They are ambient for now.
- **Basic clout only:** a per-district score that sites add to, with signals, plus a CloutCondition for site unlocks.
- **Not in this PR:** influence levels, income/price multipliers, raid defense, and any map or vertical-slice work.
- **Content:** the 9 types and 9 sites in **North End** (one per type, buyable from the start area). Tests for purchase gating, discount, income and clout.

## Follow-ups
- Clout influence levels (Lv 1–5 per area), income/drug-price multipliers, raid defense.
- The remaining types and ~74 sites, as data.
- Rival raids and losing sites (#8).
- Apply influence levels to crew loadouts, vehicles and squad size (#7, #12, #13).
