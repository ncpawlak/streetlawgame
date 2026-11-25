class_name TurfBlockLedger
extends RefCounted
## Street blocks the player can take from a rival gang, and what happens after: a held block pays income on
## its own timer, and a held block left undefended draws a counter-attack. Rival-held blocks get stronger the
## longer they're left alone (which scales the hold time and wave size of the next capture attempt).
## No scene dependencies: the driver reports who's defending and does the paying and spawning.

signal owner_changed(block_id: StringName, gang_id: StringName, previous_gang: StringName, reason: StringName)
signal income_paid(block_id: StringName, amount: int)
## The driver must start the counter-attack; call [method repel] or [method lose] when it's over.
signal counter_attack_due(block_id: StringName, strength: float)

const MIN_STRENGTH := 1.0
const MAX_STRENGTH := 5.0
## Strength at which a capture plays exactly like the difficulty tuning says.
const DEFAULT_STRENGTH := 2.0

## Seconds between payouts from each held block.
var income_interval := 20.0
## Payout at [constant DEFAULT_STRENGTH]; stronger blocks were worth more to the rival and pay more.
var base_income := 150
## Undefended seconds before the rival hits back.
var counter_attack_delay := 60.0
## How fast the counter-attack timer winds back up while someone's defending, relative to real time.
var counter_recovery := 0.5
## Strength a rival-held block gains per second while nobody is contesting it.
var strength_growth := 1.0 / 90.0
## A rival that takes a block back digs in harder.
var loss_strength_bonus := 0.5

var _blocks: Dictionary = {}


class Block:
	var id: StringName
	var display_name: String
	var rival: StringName
	var owner: StringName
	var strength := DEFAULT_STRENGTH
	var contested := false
	var under_attack := false
	var income_left := 0.0
	var counter_left := 0.0


func add_block(id: StringName, display_name: String, rival_gang: StringName, strength := DEFAULT_STRENGTH) -> void:
	var block := Block.new()
	block.id = id
	block.display_name = display_name
	block.rival = rival_gang
	block.owner = rival_gang
	block.strength = clampf(strength, MIN_STRENGTH, MAX_STRENGTH)
	_blocks[id] = block


func has_block(id: StringName) -> bool:
	return _blocks.has(id)


func display_name(id: StringName) -> String:
	return _blocks[id].display_name


func owner_of(id: StringName) -> StringName:
	return _blocks[id].owner


func is_held(id: StringName) -> bool:
	return _blocks[id].owner == GameState.PLAYER_GANG


func is_under_attack(id: StringName) -> bool:
	return _blocks[id].under_attack


func strength_of(id: StringName) -> float:
	return _blocks[id].strength


func set_strength(id: StringName, strength: float) -> void:
	_blocks[id].strength = clampf(strength, MIN_STRENGTH, MAX_STRENGTH)


## While contested (a capture is underway) the rival stops growing stronger.
func set_contested(id: StringName, contested: bool) -> void:
	_blocks[id].contested = contested


func income_of(id: StringName) -> int:
	return roundi(base_income * (0.5 + 0.25 * strength_of(id)))


func income_left(id: StringName) -> float:
	return _blocks[id].income_left


func counter_attack_left(id: StringName) -> float:
	return _blocks[id].counter_left


func held_blocks() -> Array[StringName]:
	var held: Array[StringName] = []
	for id: StringName in _blocks:
		if is_held(id):
			held.append(id)
	return held


## Income from every held block per [member income_interval].
func total_income() -> int:
	var total := 0
	for id in held_blocks():
		total += income_of(id)
	return total


func capture(id: StringName) -> void:
	var block: Block = _blocks[id]
	block.under_attack = false
	block.contested = false
	block.income_left = income_interval
	block.counter_left = counter_attack_delay
	_set_owner(block, GameState.PLAYER_GANG, &"capture")


## The counter-attack took the block: the rival owns it again, stronger than before, and the income stops.
func lose(id: StringName) -> void:
	var block: Block = _blocks[id]
	block.under_attack = false
	block.strength = minf(MAX_STRENGTH, block.strength + loss_strength_bonus)
	_set_owner(block, block.rival, &"counter_attack")


## The counter-attack was beaten off: income resumes and the next one is a full delay away.
func repel(id: StringName) -> void:
	var block: Block = _blocks[id]
	block.under_attack = false
	block.counter_left = counter_attack_delay


## Hands the block back to its rival at [param strength] (debug restarts).
func reset_block(id: StringName, strength: float) -> void:
	var block: Block = _blocks[id]
	block.under_attack = false
	block.contested = false
	block.strength = clampf(strength, MIN_STRENGTH, MAX_STRENGTH)
	if block.owner != block.rival:
		_set_owner(block, block.rival, &"script")


## [param is_defended] takes a block id and says whether someone's there to defend it.
func tick(delta: float, is_defended: Callable) -> void:
	for id: StringName in _blocks:
		var block: Block = _blocks[id]
		if block.owner != GameState.PLAYER_GANG:
			if not block.contested:
				block.strength = minf(MAX_STRENGTH, block.strength + strength_growth * delta)
			continue
		if block.under_attack:
			continue
		block.income_left -= delta
		while block.income_left <= 0.0:
			block.income_left += income_interval
			income_paid.emit(id, income_of(id))
		if is_defended.call(id):
			block.counter_left = minf(counter_attack_delay, block.counter_left + delta * counter_recovery)
		else:
			block.counter_left -= delta
			if block.counter_left <= 0.0:
				_start_counter_attack(block)


## Debug: pays the block's next income right now.
func fast_forward_income(id: StringName) -> bool:
	var block: Block = _blocks[id]
	if not is_held(id) or block.under_attack:
		return false
	block.income_left = income_interval
	income_paid.emit(id, income_of(id))
	return true


## Debug: the rival hits back right now.
func fast_forward_counter_attack(id: StringName) -> bool:
	var block: Block = _blocks[id]
	if not is_held(id) or block.under_attack:
		return false
	_start_counter_attack(block)
	return true


func _start_counter_attack(block: Block) -> void:
	block.counter_left = 0.0
	block.under_attack = true
	counter_attack_due.emit(block.id, block.strength)


func _set_owner(block: Block, gang_id: StringName, reason: StringName) -> void:
	var previous := block.owner
	block.owner = gang_id
	if previous != gang_id:
		owner_changed.emit(block.id, gang_id, previous, reason)
