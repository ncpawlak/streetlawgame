class_name HotwireMinigame
extends CarjackMinigame
## Prototype (b): hotwire under the dash. Four coloured wires sit in random slots 1-4; connect them in
## the order shown before the step timer runs out. A wrong wire (or a timeout) throws a spark; too
## many sparks short the ignition and trip the alarm.

const WIRE_COLORS := {
	&"red": Color(0.9, 0.2, 0.15),
	&"blue": Color(0.2, 0.45, 0.95),
	&"yellow": Color(0.95, 0.85, 0.2),
	&"green": Color(0.25, 0.8, 0.3),
}

## Wires in the sequence at difficulty 1.0 (one more on hard).
@export var sequence_length := 3
@export var max_sparks := 2
## Seconds per wire at difficulty 1.0.
@export var step_time := 4.0

## Colour in each slot (index = key 1-4).
var slots: Array[StringName] = []
## Colours to connect, in order.
var sequence: Array[StringName] = []
var step := 0
var sparks := 0
var step_left := 0.0

var _rng := RandomNumberGenerator.new()
var _wire_rects: Array[ColorRect] = []
var _wire_labels: Array[Label] = []
var _sequence_label: Label
var _timer_rect: ColorRect


func _init() -> void:
	kind = KIND_HOTWIRE


func _setup() -> void:
	_rng.randomize()
	slots.clear()
	for color: StringName in WIRE_COLORS:
		slots.append(color)
	for i in range(slots.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap := slots[i]
		slots[i] = slots[j]
		slots[j] = swap
	sequence.clear()
	var length := sequence_length + (1 if difficulty > 1.2 else 0)
	for i in length:
		var pick := slots[_rng.randi_range(0, slots.size() - 1)]
		while not sequence.is_empty() and pick == sequence[-1]:
			pick = slots[_rng.randi_range(0, slots.size() - 1)]
		sequence.append(pick)
	step = 0
	sparks = 0
	step_left = _step_duration()


## Slot index (0-3) holding the wire the current step needs.
func correct_slot() -> int:
	return slots.find(sequence[step]) if step < sequence.size() else -1


func _step_duration() -> float:
	return step_time / maxf(difficulty, 0.1)


func _tick(delta: float) -> void:
	step_left -= delta
	if step_left <= 0.0:
		_spark("Too slow - the wires sparked")


func _option(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	if slots[index] == sequence[step]:
		step += 1
		step_left = _step_duration()
		if step >= sequence.size():
			_succeed("Vroom. The engine turns over.")
	else:
		_spark("Wrong wire - spark!")


func _spark(_reason: String) -> void:
	sparks += 1
	step_left = _step_duration()
	if sparks >= max_sparks:
		_fail("Shorted the ignition - ALARM TRIPPED!")


func _body_height() -> float:
	return 150.0


func _build_body(parent: Control) -> void:
	_sequence_label = Label.new()
	_sequence_label.add_theme_font_size_override("font_size", 20)
	_sequence_label.position = Vector2(10.0, 0.0)
	_sequence_label.size = Vector2(500.0, 30.0)
	_sequence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(_sequence_label)
	for i in 4:
		var x := 30.0 + i * 120.0
		_wire_rects.append(_rect(parent, Color.WHITE, Vector2(x + 30.0, 40.0), Vector2(18.0, 70.0)))
		var label := Label.new()
		label.text = "[%d]" % (i + 1)
		label.add_theme_font_size_override("font_size", 18)
		label.position = Vector2(x + 20.0, 112.0)
		parent.add_child(label)
		_wire_labels.append(label)
	_rect(parent, Color(0.18, 0.18, 0.2), Vector2(10.0, 140.0), Vector2(500.0, 8.0))
	_timer_rect = _rect(parent, Color(0.95, 0.75, 0.2), Vector2(10.0, 140.0), Vector2(500.0, 8.0))


func _refresh() -> void:
	if _sequence_label == null or slots.is_empty():
		return
	var parts := PackedStringArray()
	for i in sequence.size():
		var wire := String(sequence[i]).to_upper()
		parts.append("[%s]" % wire if i == step else (wire.to_lower() if i < step else wire))
	_sequence_label.text = "Connect:  " + "  ->  ".join(parts)
	for i in _wire_rects.size():
		_wire_rects[i].color = WIRE_COLORS[slots[i]]
	_timer_rect.size.x = 500.0 * clampf(step_left / _step_duration(), 0.0, 1.0)
	if not done and sparks == 0:
		_set_status("Wire %d/%d" % [mini(step + 1, sequence.size()), sequence.size()])
	elif not done:
		_set_status("Wire %d/%d   -   Sparks %d/%d" % [mini(step + 1, sequence.size()), sequence.size(), sparks, max_sparks], Color(1.0, 0.6, 0.2))
	_set_hint("[1]-[4] connect the wire in brackets   [Esc] walk away")
