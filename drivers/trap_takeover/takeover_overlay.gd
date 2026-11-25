class_name TakeoverOverlay
extends CanvasLayer
## Driver UI for the trap takeover: objective line, claim progress bar, debug panel and the
## "takeover complete" banner. Built in code so the driver scene stays tiny.

var objective: Label
var progress: ProgressBar
var progress_label: Label
var debug_panel: PanelContainer
var debug_label: Label
var banner: PanelContainer
var banner_label: Label


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	objective = Label.new()
	objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
	objective.position.y = 54.0
	objective.add_theme_font_size_override("font_size", 22)
	objective.add_theme_constant_override("outline_size", 6)
	objective.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(objective)

	progress = ProgressBar.new()
	progress.set_anchors_preset(Control.PRESET_CENTER_TOP)
	progress.custom_minimum_size = Vector2(420.0, 22.0)
	progress.position = Vector2(-210.0, 92.0)
	progress.max_value = 1.0
	progress.show_percentage = false
	progress.visible = false
	root.add_child(progress)
	progress_label = Label.new()
	progress_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress.add_child(progress_label)

	debug_panel = PanelContainer.new()
	debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	debug_panel.position = Vector2(-16.0, 140.0)
	root.add_child(debug_panel)
	debug_label = Label.new()
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_panel.add_child(debug_label)

	banner = PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner.visible = false
	root.add_child(banner)
	banner_label = Label.new()
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 26)
	banner.add_child(banner_label)


func set_objective(text: String) -> void:
	objective.text = text


func set_progress(value: float, show: bool, contested := false) -> void:
	progress.visible = show
	progress.value = value
	progress.modulate = Color(1.0, 0.45, 0.4) if contested else Color(0.55, 1.0, 0.55)
	progress_label.text = "CONTESTED - rivals in the house" if contested else "Claiming %d%%" % roundi(value * 100.0)


func set_debug(text: String, show: bool) -> void:
	debug_panel.visible = show
	debug_label.text = text


func show_banner(text: String) -> void:
	banner.visible = not text.is_empty()
	banner_label.text = text
