class_name HouseLoot
extends RefCounted
## Per-tier loot tables and the roller that scatters loot around a [House]: loose items on random
## furniture tops and floors, plus random contents (or nothing) in each searchable container.

## name, min value, max value, slots, is cash
const TABLES := [
	# Low income
	[
		["Cash", 20, 80, 0, true],
		["Phone", 25, 40, 1, false],
		["Game console", 100, 140, 2, false],
		["Old TV", 70, 110, 2, false],
		["Jewellery box", 40, 80, 1, false],
		["Tool kit", 35, 55, 1, false],
		["Radio", 15, 30, 1, false],
		["Sneakers", 30, 60, 1, false],
	],
	# Medium income
	[
		["Cash", 60, 200, 0, true],
		["Laptop", 260, 340, 1, false],
		["Flat-screen TV", 220, 280, 2, false],
		["Watch", 160, 240, 1, false],
		["Tablet", 150, 210, 1, false],
		["Game console", 190, 250, 2, false],
		["Camera", 120, 180, 1, false],
		["Jewellery", 180, 260, 1, false],
		["Bike", 150, 220, 3, false],
	],
	# High income
	[
		["Cash", 200, 800, 0, true],
		["Gold watch", 1000, 1400, 1, false],
		["Diamond necklace", 1800, 2200, 1, false],
		["Painting", 1300, 1700, 3, false],
		["OLED TV", 800, 1000, 3, false],
		["Laptop", 600, 800, 1, false],
		["Designer bag", 500, 700, 1, false],
		["Vintage whiskey", 200, 300, 1, false],
		["Silverware", 300, 450, 2, false],
	],
]
## Loose items per tier: [min, max].
const LOOSE_COUNT := [[4, 6], [6, 8], [7, 10]]
## Chance a container holds nothing.
const EMPTY_CHANCE := [0.4, 0.3, 0.2]


static func roll_item(tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var table: Array = TABLES[clampi(tier, 0, 2)]
	var row: Array = table[rng.randi_range(0, table.size() - 1)]
	return {"name": row[0], "value": rng.randi_range(row[1], row[2]), "slots": row[3], "cash": row[4]}


## Safes always hold something good: a stack of cash or the most valuable small item.
static func roll_safe(tier: int, rng: RandomNumberGenerator) -> Dictionary:
	if rng.randf() < 0.5:
		return {"name": "Cash", "value": rng.randi_range(600, 1200) * (tier + 1), "slots": 0, "cash": true}
	return {"name": "Diamond necklace", "value": rng.randi_range(1800, 2200), "slots": 1, "cash": false}


static func roll_container(tier: int, container_name: String, rng: RandomNumberGenerator) -> Dictionary:
	if container_name.to_lower().contains("safe"):
		return roll_safe(tier, rng)
	if rng.randf() < EMPTY_CHANCE[clampi(tier, 0, 2)]:
		return {}
	var item := roll_item(tier, rng)
	# Bulky goods don't fit in a drawer: swap them for cash.
	if int(item["slots"]) > 1:
		var table: Array = TABLES[clampi(tier, 0, 2)]
		var cash_row: Array = table[0]
		item = {"name": "Cash", "value": rng.randi_range(cash_row[1], cash_row[2]), "slots": 0, "cash": true}
	return item


static func loose_count(tier: int, rng: RandomNumberGenerator) -> int:
	var range_pair: Array = LOOSE_COUNT[clampi(tier, 0, 2)]
	return rng.randi_range(range_pair[0], range_pair[1])
