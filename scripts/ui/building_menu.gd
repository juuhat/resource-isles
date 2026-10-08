class_name BuildingMenu
extends CanvasLayer

# The construction menu, laid out like the bottom build bars of Cities: Skylines or Anno. Three
# pieces, all built programmatically:
#   - the BUILD launcher (bottom-left, hotkey B, see main.gd), with a NEW badge while freshly
#     unlocked buildings are still unseen;
#   - a bar along the bottom edge, centred: category tabs over one row of building cards. Cards
#     show their cost against the current island's stock (short resources in red) and a 1-9
#     hotkey. Only unlocked buildings are listed, and a category gets a tab once it has one.
#     Hovering a card pops its details (cost against stock, output, placement rules) up above it;
#   - a placement bar beside the launcher while a building is picked, saying what's being placed,
#     what it still needs, and how to cancel.

signal building_selected(building_type: int)
signal selection_cleared

const NO_BUILDING := -1
const NO_CATEGORY := -1
const BUILDINGS_ICON := preload("res://assets/icons/building.png")
const POWER_ICON := preload("res://assets/icons/power.png")
const CANCEL_ICON := preload("res://assets/icons/cancel.png")
const HEADING_FONT := preload("res://assets/fonts/exo2_bold.tres")
const ACCENT := Color("79dcc5")
const MUTED := Color("9eafbb")
const TEXT := Color("e9f1f3")
const SHORT := Color("ff8a7a")
const NEW_BADGE := Color("f2c14e")
const BORDER := Color("314653")
const BUILDING_CATEGORIES := [
	GameTypes.BuildingCategory.RESOURCES, GameTypes.BuildingCategory.POWER,
	GameTypes.BuildingCategory.PROCESSING, GameTypes.BuildingCategory.LOGISTICS,
	GameTypes.BuildingCategory.UTILITY,
]
# The bar keeps one width while open so its tabs stay put when switching category. It is capped
# to leave the BUILD launcher (left) and the robot portrait (right) uncovered.
const BAR_MAX_WIDTH := 820.0
const BAR_SIDE_CLEARANCE := 160.0
const CARD_SIZE := Vector2(132.0, 150.0)
const CARD_SPACING := 8.0
const POPUP_WIDTH := 320.0
const POPUP_GAP := 8.0
const COST_ICON_SIZE := 18.0
const THUMBNAIL_SIZE := Vector2i(192, 192)
const HOTKEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

var building_manager: BuildingManager
var quest_manager: QuestManager
var resource_manager: ResourceManager
var selected_building_type := NO_BUILDING
var selected_category := NO_CATEGORY
var hovered_building_type := NO_BUILDING
var launcher: Button
var launcher_badge: Control
var menu_panel: PanelContainer
var category_row: HBoxContainer
var card_scroll: ScrollContainer
var card_row: HBoxContainer
var empty_label: Label
var detail_popup: PanelContainer
var detail_box: VBoxContainer
var placement_bar: PanelContainer
var placement_art: TextureRect
var placement_title: Label
var placement_status: Label
# building_type -> card Button, for the cards in the current category.
var cards: Dictionary = {}
# Building types in card order; index i is hotkey i + 1.
var card_order: Array[int] = []
# { label, stock_label, resource_type, amount } for every cost figure on screen (cards and the
# details popup), recoloured as stock changes.
var cost_labels: Array[Dictionary] = []
var detail_cost_labels: Array[Dictionary] = []
# Building types unlocked this session that the player hasn't hovered or picked yet.
var new_buildings: Dictionary = {}
var _unlocked_snapshot: Dictionary = {}
# building_type -> ViewportTexture rendered from the 3D model, for buildings with no flat art.
var _thumbnails: Dictionary = {}
var _panel_tween: Tween


func setup(
	new_building_manager: BuildingManager,
	new_quest_manager: QuestManager,
	new_resource_manager: ResourceManager
) -> void:
	building_manager = new_building_manager
	quest_manager = new_quest_manager
	resource_manager = new_resource_manager
	quest_manager.quest_completed.connect(_on_quest_completed)
	resource_manager.resource_changed.connect(_on_resource_changed)
	_unlocked_snapshot = _unlocked_building_types()


func _ready() -> void:
	_build_ui()
	_update_placement_bar()
	get_viewport().size_changed.connect(_fit_bar_width)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var index := HOTKEYS.find(key_event.keycode)
	if index != -1 and index < card_order.size():
		get_viewport().set_input_as_handled()
		_select_building_type(card_order[index])


func is_open() -> bool:
	return menu_panel != null and menu_panel.visible


func clear_selection() -> void:
	set_selected_building(NO_BUILDING)
	selection_cleared.emit()


func clear_selection_and_close() -> void:
	clear_selection()
	close_menu()


func set_selected_building(building_type: int) -> void:
	selected_building_type = building_type
	for id in cards:
		(cards[id] as Button).set_pressed_no_signal(id == selected_building_type)
	_update_placement_bar()


func open_menu() -> void:
	if menu_panel == null or menu_panel.visible:
		return
	_ensure_visible_category()
	# Stock and unlocks may have changed while closed (another island, a finished quest).
	_fit_bar_width()
	_rebuild()
	menu_panel.show()
	launcher.set_pressed_no_signal(true)
	_update_placement_bar()

	# Short fade-and-rise out of the bottom edge. The bar's offsets are its resting place at 0, so
	# sliding them leaves nothing to restore afterwards.
	if _panel_tween != null:
		_panel_tween.kill()
	menu_panel.modulate.a = 0.0
	_set_bar_drop(24.0)
	_panel_tween = create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_panel_tween.tween_property(menu_panel, "modulate:a", 1.0, 0.14)
	_panel_tween.tween_method(_set_bar_drop, 24.0, 0.0, 0.14)


func close_menu() -> void:
	if menu_panel == null:
		return
	if _panel_tween != null and _panel_tween.is_running():
		_panel_tween.custom_step(1.0)
	menu_panel.hide()
	detail_popup.hide()
	launcher.set_pressed_no_signal(false)
	hovered_building_type = NO_BUILDING
	_update_placement_bar()


func toggle_menu() -> void:
	if is_open():
		close_menu()
	else:
		open_menu()


func _on_quest_completed(_quest_id: int) -> void:
	var unlocked := _unlocked_building_types()
	for building_type in unlocked:
		if not _unlocked_snapshot.has(building_type):
			new_buildings[building_type] = true
	_unlocked_snapshot = unlocked
	_update_launcher_badge()
	if is_open():
		_ensure_visible_category()
		_rebuild()


func _on_resource_changed(_resource_type: int, _amount: int) -> void:
	refresh_stock()


# Inventory switches change the stock without emitting a resource mutation.
func refresh_stock() -> void:
	_refresh_cost_colors()
	_update_placement_bar()


func _select_category(category: int) -> void:
	if category == selected_category:
		return
	selected_category = category
	_rebuild()


func _select_building_type(building_type: int) -> void:
	_mark_seen(building_type)
	set_selected_building(building_type)
	building_selected.emit(selected_building_type)
	close_menu()


# --- Catalog queries ---

# The player-buildable, unlocked buildings in a category, in catalog order.
func _available_definitions(category: int) -> Array[BuildingDefinition]:
	var result: Array[BuildingDefinition] = []
	for definition in building_manager.get_definitions_for_category(category):
		if definition.player_buildable and quest_manager.is_building_unlocked(definition.id):
			result.append(definition)
	return result


# Categories with something to build right now. Locked buildings stay out of the menu entirely,
# so a category whose buildings are all still locked (or, like Utility, not player-buildable)
# gets no tab.
func _visible_categories() -> Array[int]:
	var result: Array[int] = []
	for category in BUILDING_CATEGORIES:
		if not _available_definitions(category).is_empty():
			result.append(category)
	return result


func _ensure_visible_category() -> void:
	var categories := _visible_categories()
	if not categories.has(selected_category):
		selected_category = categories[0] if not categories.is_empty() else NO_CATEGORY


func _category_has_new(category: int) -> bool:
	for definition in _available_definitions(category):
		if new_buildings.has(definition.id):
			return true
	return false


func _unlocked_building_types() -> Dictionary:
	var result := {}
	for category in BUILDING_CATEGORIES:
		for definition in _available_definitions(category):
			result[definition.id] = true
	return result


func _mark_seen(building_type: int) -> void:
	if not new_buildings.has(building_type):
		return
	new_buildings.erase(building_type)
	_update_launcher_badge()
	var card: Button = cards.get(building_type)
	if card != null:
		var badge := card.get_node_or_null("NewBadge")
		if badge != null:
			badge.hide()
	_rebuild_category_tabs()


# --- Styling helpers ---

func _style(color: Color, border: Color = BORDER, margin: float = 12.0, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_stylebox_override("normal", _style(Color("1d2c37")))
	button.add_theme_stylebox_override("hover", _style(Color("2a4350"), ACCENT))
	button.add_theme_stylebox_override("pressed", _style(Color("254b4b"), ACCENT))
	button.add_theme_stylebox_override("hover_pressed", _style(Color("2c5656"), ACCENT))
	button.add_theme_stylebox_override("disabled", _style(Color("16232c"), Color("24343f")))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), ACCENT))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", MUTED)
	return button


# A category tab: flat until hovered, lit with an accent underline while it's the open one.
func _tab(text: String) -> Button:
	var button := _button(text)
	var idle := _style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0.0, 6)
	idle.content_margin_left = 12.0
	idle.content_margin_right = 12.0
	idle.content_margin_top = 4.0
	idle.content_margin_bottom = 6.0
	var hover := idle.duplicate() as StyleBoxFlat
	hover.bg_color = Color("1d2c37")
	var active := idle.duplicate() as StyleBoxFlat
	active.bg_color = Color("1d3940")
	active.border_color = ACCENT
	active.border_width_left = 0
	active.border_width_top = 0
	active.border_width_right = 0
	active.border_width_bottom = 2
	active.corner_radius_bottom_left = 0
	active.corner_radius_bottom_right = 0
	button.add_theme_stylebox_override("normal", idle)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_font_override("font", HEADING_FONT)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_color_override("font_hover_pressed_color", ACCENT)
	button.toggle_mode = true
	return button


func _label(text: String, font_size: int = 14, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _heading(text: String, font_size: int, color: Color = TEXT) -> Label:
	var label := _label(text, font_size, color)
	label.add_theme_font_override("font", HEADING_FONT)
	return label


func _icon(texture: Texture2D, size: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(size, size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# A small rounded tag (hotkey number, NEW) pinned to a card corner.
func _badge(text: String, background: Color, foreground: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	var style := _style(background, background, 0.0, 6)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	badge.add_theme_stylebox_override("panel", style)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_heading(text, 11, foreground))
	return badge


func _resource_icon(resource_type: int) -> Texture2D:
	var definition := ResourceDatabase.get_definition(resource_type)
	if definition == null or definition.icon == null:
		return BUILDINGS_ICON
	return definition.icon


func _format_seconds(seconds: float) -> String:
	if is_equal_approx(seconds, roundf(seconds)):
		return "%ds" % roundi(seconds)
	return "%.1fs" % seconds


# --- Layout ---

func _build_ui() -> void:
	name = "BuildingMenu"

	launcher = _button("BUILD")
	launcher.icon = BUILDINGS_ICON
	launcher.expand_icon = true
	launcher.add_theme_constant_override("icon_max_width", 28)
	launcher.add_theme_font_override("font", HEADING_FONT)
	launcher.toggle_mode = true
	launcher.anchor_top = 1.0
	launcher.anchor_bottom = 1.0
	launcher.offset_left = 16
	launcher.offset_top = -68
	launcher.offset_right = 132
	launcher.offset_bottom = -16
	launcher.tooltip_text = "Construction (B)"
	launcher.pressed.connect(toggle_menu)
	add_child(launcher)
	launcher_badge = _badge("NEW", NEW_BADGE, Color("1a1a1a"))
	launcher_badge.position = Vector2(84, -9)
	launcher.add_child(launcher_badge)
	_update_launcher_badge()

	_build_placement_bar()

	# Bottom-centre, flush with the screen edge. Zero offsets on centre/bottom anchors let the bar
	# size itself: it grows out from the middle and up from the bottom to fit its content.
	menu_panel = PanelContainer.new()
	menu_panel.visible = false
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 1.0
	menu_panel.anchor_bottom = 1.0
	menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bar_style := _style(Color("12212bf2"), BORDER, 12.0, 12)
	bar_style.corner_radius_bottom_left = 0
	bar_style.corner_radius_bottom_right = 0
	bar_style.border_width_bottom = 0
	bar_style.content_margin_top = 8.0
	bar_style.content_margin_bottom = 14.0
	menu_panel.add_theme_stylebox_override("panel", bar_style)
	add_child(menu_panel)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 10)
	menu_panel.add_child(menu)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	menu.add_child(heading)
	category_row = HBoxContainer.new()
	category_row.add_theme_constant_override("separation", 2)
	category_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(category_row)
	var close := _button("")
	close.icon = CANCEL_ICON
	close.expand_icon = true
	close.custom_minimum_size = Vector2(30, 30)
	close.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6.0))
	close.add_theme_stylebox_override("hover", _style(Color("2a4350"), ACCENT, 6.0))
	close.add_theme_stylebox_override("pressed", _style(Color("254b4b"), ACCENT, 6.0))
	close.tooltip_text = "Close (B)"
	close.pressed.connect(close_menu)
	heading.add_child(close)

	card_scroll = ScrollContainer.new()
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.custom_minimum_size.y = CARD_SIZE.y
	menu.add_child(card_scroll)
	card_row = HBoxContainer.new()
	card_row.add_theme_constant_override("separation", int(CARD_SPACING))
	card_scroll.add_child(card_row)
	empty_label = _label("Nothing to build yet. Complete quests to unlock buildings.", 14, MUTED)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.custom_minimum_size.y = CARD_SIZE.y
	empty_label.visible = false
	menu.add_child(empty_label)

	_build_detail_popup()


# The hover details, floating above the bar over the hovered card. It never takes the mouse, so
# moving between cards doesn't flicker it.
func _build_detail_popup() -> void:
	detail_popup = PanelContainer.new()
	detail_popup.visible = false
	detail_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_popup.anchor_top = 1.0
	detail_popup.anchor_bottom = 1.0
	detail_popup.grow_vertical = Control.GROW_DIRECTION_BEGIN
	detail_popup.add_theme_stylebox_override("panel", _style(Color("172a35f7"), ACCENT, 14.0, 10))
	add_child(detail_popup)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 6)
	detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_popup.add_child(detail_box)


# Sits right of the launcher while a building is picked and the menu is closed.
func _build_placement_bar() -> void:
	placement_bar = PanelContainer.new()
	placement_bar.visible = false
	placement_bar.anchor_top = 1.0
	placement_bar.anchor_bottom = 1.0
	placement_bar.offset_left = 144
	placement_bar.offset_right = 144
	placement_bar.offset_top = -68
	placement_bar.offset_bottom = -16
	placement_bar.grow_horizontal = Control.GROW_DIRECTION_END
	placement_bar.add_theme_stylebox_override("panel", _style(Color("12212bf2"), ACCENT, 6.0))
	add_child(placement_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	placement_bar.add_child(row)
	placement_art = _icon(BUILDINGS_ICON, 38.0)
	row.add_child(placement_art)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	placement_title = _heading("", 15)
	text.add_child(placement_title)
	placement_status = _label("", 12, MUTED)
	text.add_child(placement_status)
	var cancel := _button("Cancel")
	cancel.add_theme_stylebox_override("normal", _style(Color("1d2c37"), BORDER, 8.0))
	cancel.add_theme_stylebox_override("hover", _style(Color("2a4350"), ACCENT, 8.0))
	cancel.add_theme_stylebox_override("pressed", _style(Color("254b4b"), ACCENT, 8.0))
	cancel.tooltip_text = "Stop placing (Esc / right-click)"
	cancel.pressed.connect(clear_selection)
	row.add_child(cancel)


func _update_placement_bar() -> void:
	if placement_bar == null:
		return
	var definition: BuildingDefinition = null
	if selected_building_type != NO_BUILDING:
		definition = building_manager.get_definition(selected_building_type)
	placement_bar.visible = definition != null and not is_open()
	if not placement_bar.visible:
		return
	placement_art.texture = _building_art(definition)
	placement_title.text = "Placing %s" % definition.display_name
	var shortfall := _shortfall_text(definition.cost)
	if shortfall.is_empty():
		placement_status.text = "Click a tile to build  ·  Esc or right-click to stop"
		placement_status.add_theme_color_override("font_color", MUTED)
	else:
		placement_status.text = shortfall
		placement_status.add_theme_color_override("font_color", SHORT)
	# Shrink back to fit when the status text gets shorter.
	placement_bar.reset_size()


func _update_launcher_badge() -> void:
	if launcher_badge != null:
		launcher_badge.visible = not new_buildings.is_empty()


# One fixed width per screen size: as wide as the clearance for the launcher and portrait allows,
# up to BAR_MAX_WIDTH. The panel's margins come on top of the scroll area's width.
func _fit_bar_width() -> void:
	if card_scroll == null:
		return
	var available := get_viewport().get_visible_rect().size.x - 2.0 * BAR_SIDE_CLEARANCE
	card_scroll.custom_minimum_size.x = clampf(available, CARD_SIZE.x * 3.0, BAR_MAX_WIDTH)
	empty_label.custom_minimum_size.x = card_scroll.custom_minimum_size.x


# Lowers the bar by `amount` pixels below its resting place (for the open animation).
func _set_bar_drop(amount: float) -> void:
	menu_panel.offset_top = amount
	menu_panel.offset_bottom = amount


func _rebuild() -> void:
	_rebuild_category_tabs()
	_rebuild_cards()
	detail_popup.hide()
	hovered_building_type = NO_BUILDING


func _rebuild_category_tabs() -> void:
	if category_row == null:
		return
	_clear_container(category_row)
	var group := ButtonGroup.new()
	for category in _visible_categories():
		var button := _tab(GameTypes.building_category_display_name(category).to_upper())
		button.button_group = group
		button.button_pressed = category == selected_category
		if _category_has_new(category):
			button.add_theme_color_override("font_color", NEW_BADGE)
			button.tooltip_text = "New buildings"
		button.pressed.connect(_select_category.bind(category))
		category_row.add_child(button)


func _rebuild_cards() -> void:
	if card_row == null:
		return
	_clear_container(card_row)
	cards.clear()
	card_order.clear()
	cost_labels.clear()
	var definitions: Array[BuildingDefinition] = []
	if selected_category != NO_CATEGORY:
		definitions = _available_definitions(selected_category)
	card_scroll.visible = not definitions.is_empty()
	empty_label.visible = definitions.is_empty()
	for definition in definitions:
		card_order.append(definition.id)
		var card := _build_card(definition, card_order.size())
		cards[definition.id] = card
		card_row.add_child(card)
	_refresh_cost_colors()


func _build_card(definition: BuildingDefinition, hotkey: int) -> Button:
	var button := _button("")
	button.custom_minimum_size = CARD_SIZE
	button.toggle_mode = true
	button.button_pressed = definition.id == selected_building_type
	button.mouse_entered.connect(_on_card_hovered.bind(definition))
	button.mouse_exited.connect(_on_card_unhovered.bind(definition.id))
	button.pressed.connect(_select_building_type.bind(definition.id))
	button.focus_entered.connect(_on_card_hovered.bind(definition))
	button.focus_exited.connect(_on_card_unhovered.bind(definition.id))

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8
	content.offset_top = 8
	content.offset_right = -8
	content.offset_bottom = -8
	content.add_theme_constant_override("separation", 3)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)

	var art := _icon(_building_art(definition), 0.0)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(art)

	var title := _heading(definition.display_name, 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(title)
	content.add_child(_cost_row(definition.cost, false, cost_labels))

	var key_badge := _badge(str(hotkey), Color("0e1a22"), MUTED)
	key_badge.position = Vector2(6, 6)
	button.add_child(key_badge)
	if new_buildings.has(definition.id):
		var new_badge := _badge("NEW", NEW_BADGE, Color("1a1a1a"))
		new_badge.name = "NewBadge"
		new_badge.position = Vector2(CARD_SIZE.x - 44, 6)
		button.add_child(new_badge)
	return button


# A centred row of [icon amount] chips. with_stock adds "/ have" after each amount. Each chip is
# registered in `into` so _refresh_cost_colors can keep it current.
func _cost_row(cost: Dictionary, with_stock: bool, into: Array[Dictionary]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cost.is_empty():
		row.add_child(_label("Free", 12, ACCENT))
		return row
	for resource_type in cost:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(_icon(_resource_icon(resource_type), COST_ICON_SIZE))
		var amount: int = cost[resource_type]
		var label := _label(str(amount), 13)
		chip.add_child(label)
		var stock_label: Label = null
		if with_stock:
			stock_label = _label("", 12, MUTED)
			chip.add_child(stock_label)
		into.append({label = label, stock_label = stock_label, resource_type = resource_type, amount = amount})
		row.add_child(chip)
	return row


func _refresh_cost_colors() -> void:
	for entry in cost_labels + detail_cost_labels:
		var label: Label = entry.label
		if not is_instance_valid(label):
			continue
		var have := resource_manager.get_amount(entry.resource_type)
		label.add_theme_color_override("font_color", TEXT if have >= int(entry.amount) else SHORT)
		if entry.stock_label != null:
			(entry.stock_label as Label).text = "/ %d" % have


# "Need 3 more Stone, 2 more Wood", or "" when the cost is covered.
func _shortfall_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for resource_type in cost:
		var missing: int = int(cost[resource_type]) - resource_manager.get_amount(resource_type)
		if missing > 0:
			parts.append("%d more %s" % [missing, ResourceManager.get_display_name_for_type(resource_type)])
	return "" if parts.is_empty() else "Need " + ", ".join(parts)


# --- Details popup ---

func _on_card_hovered(definition: BuildingDefinition) -> void:
	hovered_building_type = definition.id
	_mark_seen(definition.id)
	_show_details(definition)


func _on_card_unhovered(building_type: int) -> void:
	if hovered_building_type != building_type:
		return
	hovered_building_type = NO_BUILDING
	detail_popup.hide()


func _show_details(definition: BuildingDefinition) -> void:
	_clear_container(detail_box)
	detail_cost_labels.clear()

	detail_box.add_child(_heading(definition.display_name, 18))
	var tag := GameTypes.building_category_display_name(definition.category).to_upper()
	detail_box.add_child(_heading(tag, 11, ACCENT))

	# What it takes comes first: the cost against stock.
	var cost_row := _cost_row(definition.cost, true, detail_cost_labels)
	cost_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	detail_box.add_child(cost_row)
	var shortfall := _shortfall_text(definition.cost)
	if not shortfall.is_empty():
		detail_box.add_child(_wrapped(shortfall, 12, SHORT))
	_refresh_cost_colors()

	if not definition.description.is_empty():
		detail_box.add_child(_wrapped(definition.description, 13, MUTED))

	var stats := _stat_rows(definition)
	if not stats.is_empty():
		detail_box.add_child(_section("OUTPUT"))
		for row in stats:
			detail_box.add_child(row)

	detail_box.add_child(_section("PLACEMENT"))
	for row in _placement_rows(definition):
		detail_box.add_child(row)

	_place_detail_popup(definition.id)
	detail_popup.show()


# Above the bar, centred on the card and kept on screen. The popup grows upward from its offsets,
# so only the bar's height is needed, not the popup's own.
func _place_detail_popup(building_type: int) -> void:
	var card: Button = cards.get(building_type)
	var screen_width := get_viewport().get_visible_rect().size.x
	var center_x := screen_width * 0.5
	if card != null:
		center_x = card.get_global_rect().get_center().x
	var left := clampf(center_x - POPUP_WIDTH * 0.5, 16.0, screen_width - 16.0 - POPUP_WIDTH)
	detail_popup.offset_left = left
	detail_popup.offset_right = left + POPUP_WIDTH
	detail_popup.offset_top = -(menu_panel.size.y + POPUP_GAP)
	detail_popup.offset_bottom = detail_popup.offset_top


func _stat_rows(definition: BuildingDefinition) -> Array[Control]:
	var rows: Array[Control] = []
	var output_unit := ""
	if not definition.recipes.is_empty():
		# One row per recipe: what it makes from what.
		output_unit = ResourceManager.get_display_name_for_type(definition.production_resource_type)
		for recipe in definition.recipes:
			var parts: Array[String] = []
			for resource in recipe.inputs:
				parts.append("%d %s" % [recipe.inputs[resource], ResourceManager.get_display_name_for_type(resource)])
			rows.append(_detail_row(_resource_icon(recipe.output), "Makes %d %s from %s every %s" % [
				definition.production_base_amount, ResourceManager.get_display_name_for_type(recipe.output),
				" + ".join(parts), _format_seconds(definition.production_interval_seconds),
			]))
	elif definition.production_resource_type != -1:
		output_unit = ResourceManager.get_display_name_for_type(definition.production_resource_type)
		rows.append(_detail_row(_resource_icon(definition.production_resource_type), "Makes %d %s every %s" % [
			definition.production_base_amount, output_unit,
			_format_seconds(definition.production_interval_seconds),
		]))
	var inputs := definition.get_production_inputs()
	for resource in inputs:
		rows.append(_detail_row(_resource_icon(resource), "Uses %d %s per batch" % [
			inputs[resource],
			ResourceManager.get_display_name_for_type(resource),
		]))
	if definition.power_generated > 0:
		output_unit = "MW"
		rows.append(_detail_row(POWER_ICON, "Generates %d MW" % definition.power_generated))
		if definition.fuel_resource_type != -1:
			rows.append(_detail_row(_resource_icon(definition.fuel_resource_type), "Burns %d %s every %s" % [
				definition.fuel_amount,
				ResourceManager.get_display_name_for_type(definition.fuel_resource_type),
				_format_seconds(definition.fuel_interval_seconds),
			]))
		else:
			rows.append(_detail_row(null, "Needs no fuel"))
	if definition.power_consumed > 0:
		rows.append(_detail_row(POWER_ICON, "Draws %d MW while running" % definition.power_consumed))
	for rule in definition.adjacency_yields:
		var amount := int(rule.amount)
		rows.append(_detail_row(null, "%s%d %s per adjacent %s" % [
			"+" if amount >= 0 else "-", absi(amount), output_unit,
			building_manager.get_reference_label(rule),
		], ACCENT if amount >= 0 else SHORT))
	return rows


func _placement_rows(definition: BuildingDefinition) -> Array[Control]:
	var rows: Array[Control] = []
	var terrains: Array[String] = []
	for terrain in definition.required_terrains:
		terrains.append(GameTypes.terrain_display_name(terrain))
	if not terrains.is_empty():
		rows.append(_detail_row(null, "Build on " + " or ".join(terrains)))
	for required in definition.required_adjacent:
		rows.append(_detail_row(null, "Must touch " + building_manager.get_reference_label(required)))
	for forbidden in definition.forbidden_adjacent:
		rows.append(_detail_row(null, "Can't touch " + building_manager.get_reference_label(forbidden)))
	if definition.footprint.size() > 1:
		rows.append(_detail_row(null, "Covers %d tiles (R to rotate)" % definition.footprint.size()))
	for tile_terrains in definition.footprint_terrains:
		if (tile_terrains as Array).is_empty():
			continue
		var names: Array[String] = []
		for terrain in tile_terrains:
			names.append(GameTypes.terrain_display_name(terrain))
		rows.append(_detail_row(null, "One tile on " + " or ".join(names)))
	return rows


func _section(text: String) -> Control:
	var label := _heading(text, 11, MUTED)
	label.custom_minimum_size.y = 20
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label


func _wrapped(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = POPUP_WIDTH - 28
	return label


# One details line with an optional leading icon (a blank gutter keeps text aligned without one).
func _detail_row(icon: Texture2D, text: String, color: Color = TEXT) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gutter := _icon(icon, COST_ICON_SIZE)
	row.add_child(gutter)
	var label := _wrapped(text, 13, color)
	label.custom_minimum_size.x = POPUP_WIDTH - 28 - COST_ICON_SIZE - 6
	row.add_child(label)
	return row


# --- Art ---

# A building's menu art is its 3D model, so the menu shows what will actually be built. The flat
# texture is only a fallback for buildings that don't have a model yet.
func _building_art(definition: BuildingDefinition) -> Texture2D:
	if definition.model != null:
		return _model_thumbnail(definition)
	if definition.texture != null:
		return definition.texture
	return BUILDINGS_ICON


# Renders a building's model once into an offscreen viewport, framed on its bounds from a
# three-quarter view, and reuses that texture.
func _model_thumbnail(definition: BuildingDefinition) -> Texture2D:
	if _thumbnails.has(definition.id):
		return _thumbnails[definition.id]

	var viewport := SubViewport.new()
	viewport.size = THUMBNAIL_SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.55
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	viewport.add_child(light)

	var model := definition.model.instantiate() as Node3D
	model.rotation_degrees.y = definition.visual_rotation_y
	viewport.add_child(model)

	var bounds := _visual_bounds(model)
	var camera := Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)
	var radius := maxf(bounds.size.length() * 0.5, 0.01)
	var distance := radius / sin(deg_to_rad(camera.fov * 0.5))
	var center := bounds.get_center()
	camera.look_at_from_position(center + Vector3(0.8, 0.7, 1.0).normalized() * distance, center)
	camera.current = true

	var texture := viewport.get_texture()
	_thumbnails[definition.id] = texture
	return texture


func _visual_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is VisualInstance3D:
			var box: AABB = (node as VisualInstance3D).global_transform * (node as VisualInstance3D).get_aabb()
			bounds = box if not found else bounds.merge(box)
			found = true
	return bounds if found else AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
