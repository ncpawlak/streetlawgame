class_name TimingMinigame
extends CanvasLayer
## "Bang bang bang" timing lock (safe dials, car locks). A pin sweeps from the left wall to the right.
## Press when it's inside the green sweet spot: the spot jumps ahead and you go again. Land
## [member hits_needed] in a row before the pin hits the right wall. A miss or reaching the wall
## resets the pin and the streak.
##
## Keys: E / Space / left click to hit, Esc to give up. The actor's movement is frozen meanwhile.
## Drive it without input with [method step] and [method press] (tests, AI).

signal succeeded
## Gave up ([param reason] &"cancelled") or ran out of [member max_resets] (&"too_many_resets").
signal failed(reason: StringName)
signal hit(streak: int)
## A miss or the pin reaching the wall; [param reason] is &"miss" or &"wall".
signal reset_happened(reason: StringName)

@export var hits_needed := 3
## Bar widths per second.
@export var speed := 0.5
## Sweet spot width (fraction of the bar).
@export var sweet_width := 0.1
## Resets allowed before it counts as failed (0 = unlimited).
@export var max_resets := 0
@export var title := "Crack the safe"
## Advance in _process (turn off to drive it from [method step]).
@export var auto_step := true
@export var show_ui := true

var active := false
var pin := 0.0
var streak := 0
var resets := 0
var sweet_start := 0.0
var sweet_end := 0.0
var actor: Node

var _rng := RandomNumberGenerator.new()
var _panel: Control
var _bar: ColorRect
var _spot: ColorRect
var _pin_rect: ColorRect
var _title_label: Label
var _streak_label: Label
var _flash := 0.0
var _flash_color := Color.WHITE

const BAR_WIDTH := 520.0
const BAR_HEIGHT := 34.0


func _ready() -> void:
	layer = 8
	if show_ui:
		_build_ui()
	visible = false


## Opens the minigame for [param who] (frozen until it ends). [param seed_value] >= 0 makes the
## sweet spots deterministic.
func start(who: Node = null, seed_value := -1) -> void:
	actor = who
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	active = true
	resets = 0
	_restart()
	_freeze_actor(true)
	visible = show_ui
	_update_ui()


func cancel() -> void:
	if not active:
		return
	_end()
	failed.emit(&"cancelled")


## Advances the pin by [param delta] seconds.
func step(delta: float) -> void:
	if not active:
		return
	pin += speed * delta
	if pin >= 1.0:
		pin = 1.0
		_reset(&"wall")
	_flash = maxf(0.0, _flash - delta)
	_update_ui()


## A hit attempt at the pin's current position. Returns true if it landed in the sweet spot.
func press() -> bool:
	if not active:
		return false
	if pin < sweet_start or pin > sweet_end:
		_reset(&"miss")
		return false
	streak += 1
	_flash = 0.2
	_flash_color = Color(0.4, 1.0, 0.5)
	hit.emit(streak)
	if streak >= hits_needed:
		_end()
		EventBus.notify.emit("%s - done!" % title)
		succeeded.emit()
		return true
	_place_spot()
	_update_ui()
	return true


## True when the pin is in the sweet spot right now.
func in_sweet_spot() -> bool:
	return active and pin >= sweet_start and pin <= sweet_end


func _process(delta: float) -> void:
	if active and auto_step:
		step(delta)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("shoot"):
		press()
		get_viewport().set_input_as_handled()


func _restart() -> void:
	pin = 0.0
	streak = 0
	_place_spot()


func _reset(reason: StringName) -> void:
	resets += 1
	_flash = 0.35
	_flash_color = Color(1.0, 0.3, 0.25)
	reset_happened.emit(reason)
	if max_resets > 0 and resets > max_resets:
		_end()
		EventBus.notify.emit("%s - failed" % title)
		failed.emit(&"too_many_resets")
		return
	_restart()


## Puts the next sweet spot ahead of the pin, spaced so the remaining hits fit before the wall.
func _place_spot() -> void:
	var remaining := hits_needed - streak
	var room := maxf(0.0, 0.97 - pin)
	var gap := room / (float(remaining) + 0.15)
	gap = clampf(gap + _rng.randf_range(-0.03, 0.03), sweet_width * 0.5 + 0.06, room - sweet_width * 0.5)
	var centre := pin + gap
	sweet_start = clampf(centre - sweet_width * 0.5, 0.0, 1.0)
	sweet_end = clampf(centre + sweet_width * 0.5, 0.0, 0.99)


func _end() -> void:
	active = false
	visible = false
	_freeze_actor(false)


func _freeze_actor(frozen: bool) -> void:
	if actor == null or not is_instance_valid(actor) or not (actor is CharacterBody3D):
		return
	actor.set_physics_process(not frozen)
	if frozen:
		(actor as CharacterBody3D).velocity = Vector3.ZERO


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -170.0
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_title_label)
	_bar = ColorRect.new()
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar.color = Color(0.12, 0.12, 0.14)
	box.add_child(_bar)
	_spot = ColorRect.new()
	_spot.color = Color(0.2, 0.75, 0.3)
	_bar.add_child(_spot)
	_pin_rect = ColorRect.new()
	_pin_rect.color = Color(1.0, 0.95, 0.8)
	_pin_rect.size = Vector2(6.0, BAR_HEIGHT + 10.0)
	_bar.add_child(_pin_rect)
	_streak_label = Label.new()
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_streak_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_streak_label)


func _update_ui() -> void:
	if _panel == null:
		return
	_title_label.text = title
	_spot.position = Vector2(sweet_start * BAR_WIDTH, 0.0)
	_spot.size = Vector2((sweet_end - sweet_start) * BAR_WIDTH, BAR_HEIGHT)
	_pin_rect.position = Vector2(pin * BAR_WIDTH - 3.0, -5.0)
	var dots := ""
	for i in hits_needed:
		dots += "● " if i < streak else "○ "
	_streak_label.text = "%s   E / Space when the pin is in the green - Esc to give up" % dots.strip_edges()
	_bar.color = _flash_color.darkened(0.6) if _flash > 0.0 else Color(0.12, 0.12, 0.14)
