class_name InteractionPrompt
extends Control
## Bottom-center "[E] Rob - Corner Store" prompt plus the channel progress bar for the player's Interactor.

var interactor: Interactor

var _label: Label
var _detail: Label
var _bar: ProgressBar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -300.0
	offset_right = 300.0
	offset_top = -170.0
	offset_bottom = -76.0
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_END
	add_child(box)
	_label = _make_label(22)
	box.add_child(_label)
	_detail = _make_label(16)
	_detail.modulate = Color(1.0, 0.55, 0.45)
	box.add_child(_detail)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(320.0, 14.0)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.show_percentage = false
	_bar.visible = false
	box.add_child(_bar)


func _process(_delta: float) -> void:
	if interactor == null or not is_instance_valid(interactor):
		var player := GameState.player
		interactor = player.get("interactor") as Interactor if player != null else null
	visible = has_prompt()
	if not visible:
		return
	if interactor.is_channelling():
		var action := interactor.channel_action
		var text := action.progress_text if action.progress_text != "" else action.make_label(interactor.channel_ctx) + "..."
		_label.text = interactor.channel_ctx.format(text)
		_detail.text = ""
		_bar.visible = true
		_bar.value = interactor.channel_fraction() * 100.0
		return
	_bar.visible = false
	var focused := interactor.focused
	var listed := interactor.focused_actions()
	if listed.size() == 1:
		var ctx := focused.make_context(interactor.actor, listed[0])
		_label.text = "[E] %s" % listed[0].make_label(ctx)
		_detail.text = listed[0].unavailable_reason(ctx)
	else:
		_label.text = "[E] %s" % focused.label()
		_detail.text = "%d options" % listed.size()


## True when the prompt is showing something (the HUD hides its own hint then).
func has_prompt() -> bool:
	if interactor == null or not is_instance_valid(interactor):
		return false
	return interactor.is_channelling() or (interactor.focused != null and is_instance_valid(interactor.focused))


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
