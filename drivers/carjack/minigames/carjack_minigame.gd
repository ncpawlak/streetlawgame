class_name CarjackMinigame
extends Control
## Common interface for the carjack prototypes. The driver opens one, listens for [signal finished]
## and [signal too_slow], and never cares which prototype is running, so they can be swapped freely.
## Input: primary = E / F / Space, options = 1-4, Esc walks away. Game logic lives in [method tick],
## [method press_primary] and [method press_option] so tests can drive it without input events.

## [param success] false means the attempt blew up (the driver raises an alarm). [param reason] is
## shown to the player.
signal finished(success: bool, reason: String)
## Fired once when the attempt takes longer than [member slow_after] (someone notices).
signal too_slow
## The player walked away (Esc). No alarm by itself.
signal cancelled

const KIND_LOCK_PICK := &"lock_pick"
const KIND_HOTWIRE := &"hotwire"
const KIND_STRUGGLE := &"struggle"
const KINDS: Array[StringName] = [KIND_LOCK_PICK, KIND_HOTWIRE, KIND_STRUGGLE]
const KIND_NAMES := {
	&"lock_pick": "Lock pick",
	&"hotwire": "Hotwire",
	&"struggle": "Pull-out struggle",
}

## 1.0 = normal; higher is harder (faster needles, shorter timers, stronger drivers).
@export var difficulty := 1.0
## Seconds before a bystander notices the attempt.
@export var slow_after := 10.0

var kind: StringName
var target: Node
var elapsed := 0.0
var done := false
var succeeded := false
var slow_reported := false

var _title: Label
var _hint: Label
var _status: Label
var _body: Control


static func create(minigame_kind: StringName) -> CarjackMinigame:
	match minigame_kind:
		KIND_HOTWIRE:
			return HotwireMinigame.new()
		KIND_STRUGGLE:
			return StruggleMinigame.new()
	return LockPickMinigame.new()


static func display_name(minigame_kind: StringName) -> String:
	return KIND_NAMES.get(minigame_kind, String(minigame_kind))


## Starts the attempt on [param car] (may be null in tests).
func begin(car: Node = null) -> void:
	target = car
	elapsed = 0.0
	done = false
	succeeded = false
	slow_reported = false
	_setup()
	if is_inside_tree():
		_refresh()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.88)
	style.border_color = Color(0.95, 0.75, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = _make_label(box, 28, Color(1.0, 0.85, 0.3))
	_title.text = display_name(kind).to_upper()
	_body = Control.new()
	_body.custom_minimum_size = Vector2(520.0, _body_height())
	box.add_child(_body)
	_status = _make_label(box, 20, Color(0.95, 0.95, 0.95))
	_hint = _make_label(box, 15, Color(0.7, 0.7, 0.75))
	_build_body(_body)
	_refresh()


func _process(delta: float) -> void:
	tick(delta)


## Advances the attempt by [param delta] seconds.
func tick(delta: float) -> void:
	if done:
		return
	elapsed += delta
	if not slow_reported and elapsed >= slow_after:
		slow_reported = true
		too_slow.emit()
	_tick(delta)
	if is_inside_tree():
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if done or not visible:
		return
	var handled := true
	if event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		press_primary()
	elif event.is_action_pressed("ui_cancel"):
		cancel()
	else:
		handled = false
		for i in 4:
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				press_option(i)
				handled = true
				break
	if handled:
		get_viewport().set_input_as_handled()


## E / F / Space.
func press_primary() -> void:
	if not done:
		_primary()
		if is_inside_tree():
			_refresh()


## 1-4 (0-based [param index]).
func press_option(index: int) -> void:
	if not done:
		_option(index)
		if is_inside_tree():
			_refresh()


func cancel() -> void:
	if done:
		return
	done = true
	cancelled.emit()


func status_text() -> String:
	return _status.text if _status != null else ""


# --- Overridden by the prototypes -------------------------------------------------------------

## Resets the attempt's state (called by [method begin]).
func _setup() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _primary() -> void:
	pass


func _option(_index: int) -> void:
	pass


## Builds the static visuals once, inside [param _parent] (520 px wide).
func _build_body(_parent: Control) -> void:
	pass


func _body_height() -> float:
	return 60.0


## Updates the visuals from the current state (only called while in the tree).
func _refresh() -> void:
	pass


# --- Helpers ----------------------------------------------------------------------------------

func _succeed(reason: String) -> void:
	if done:
		return
	done = true
	succeeded = true
	_set_status(reason, Color(0.4, 1.0, 0.5))
	finished.emit(true, reason)


func _fail(reason: String) -> void:
	if done:
		return
	done = true
	_set_status(reason, Color(1.0, 0.35, 0.3))
	finished.emit(false, reason)


func _set_status(text: String, color := Color(0.95, 0.95, 0.95)) -> void:
	if _status != null:
		_status.text = text
		_status.add_theme_color_override("font_color", color)


func _set_hint(text: String) -> void:
	if _hint != null:
		_hint.text = text


func _make_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _rect(parent: Control, color: Color, at: Vector2, rect_size: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = at
	rect.size = rect_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect
