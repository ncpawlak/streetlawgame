class_name ShopPanel
extends CanvasLayer
## Minimal greybox shop UI for a business site, built in code. Lists the site's stock with live
## prices (half price at a site the player owns) and buys through Businesses.buy_item. Pauses the
## game while open.

var is_open := false
var site_id: StringName

var _actor: Node
var _message := ""
var _was_paused := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _title: Label
var _body: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(520, 420)
	center.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "Close [Esc]"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open(target_site: StringName, actor: Node = null) -> void:
	site_id = target_site
	_actor = actor
	_message = ""
	if not is_open:
		is_open = true
		visible = true
		_was_paused = get_tree().paused
		get_tree().paused = true
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rebuild()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _previous_mouse_mode


func buy(item_id: StringName) -> String:
	var reason := Businesses.buy_item(site_id, item_id, _actor)
	var item := ContentDB.find_def(ShopItemDef.TYPE, item_id) as ShopItemDef
	_message = reason if reason != "" else "Bought %s" % (item.label() if item != null else String(item_id))
	rebuild()
	return reason


func rebuild() -> void:
	if _body == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var business_site := Businesses.site(site_id)
	var owned := Businesses.is_owned(site_id)
	_title.text = (business_site.label() if business_site != null else String(site_id)) + (" (yours)" if owned else "")
	_body.add_child(_label("Cash: $%d%s" % [GameState.cash, "  -  owner price: 50% off" if owned else ""], Color(0.7, 0.9, 0.7)))
	if _message != "":
		_body.add_child(_label(_message, Color(1.0, 0.8, 0.3)))
	for item in Businesses.shop_items(site_id):
		var row := HBoxContainer.new()
		var text := _label("%s - %s" % [item.label(), item.description] if item.description != "" else item.label(), Color.WHITE)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		var price := Businesses.shop_price(site_id, item.id)
		var button := Button.new()
		button.text = "Buy $%d" % price
		button.disabled = GameState.cash < price
		var item_id := item.id
		button.pressed.connect(func() -> void: buy(item_id))
		row.add_child(button)
		_body.add_child(row)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label
