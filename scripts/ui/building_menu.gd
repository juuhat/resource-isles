class_name BuildingMenu
extends CanvasLayer

signal building_selected(building_type: int)
signal selection_cleared

const NO_BUILDING := -1
const BUILDINGS_ICON := preload("res://assets/icons/building.png")
const ACCENT := Color("79dcc5")
const MUTED := Color("9eafbb")
const BUILDING_CATEGORIES := [
	GameTypes.BuildingCategory.RESOURCES, GameTypes.BuildingCategory.POWER,
	GameTypes.BuildingCategory.PROCESSING, GameTypes.BuildingCategory.LOGISTICS,
	GameTypes.BuildingCategory.UTILITY,
]

var building_manager: BuildingManager
var quest_manager: QuestManager
var selected_building_type := NO_BUILDING
var selected_category := GameTypes.BuildingCategory.RESOURCES
var menu_panel: PanelContainer
var category_row: HBoxContainer
var building_row: HBoxContainer
var selected_building_label: Label
var detail_title: Label
var detail_text: Label
var cards: Dictionary = {}
var launcher: Button


func setup(new_building_manager: BuildingManager, new_quest_manager: QuestManager) -> void:
	building_manager = new_building_manager
	quest_manager = new_quest_manager
	quest_manager.quest_completed.connect(_on_quest_completed)


func _on_quest_completed(_quest_id: int) -> void:
	_rebuild_building_buttons()


func _ready() -> void:
	_build_ui()
	_apply_selection_label()


func clear_selection() -> void:
	set_selected_building(NO_BUILDING)
	selection_cleared.emit()


func clear_selection_and_close() -> void:
	clear_selection()
	close_menu()


func set_selected_building(building_type: int) -> void:
	selected_building_type = building_type
	_apply_selection_label()


func close_menu() -> void:
	if menu_panel != null:
		menu_panel.hide()
		launcher.set_pressed_no_signal(false)


func toggle_menu() -> void:
	if menu_panel != null:
		menu_panel.visible = not menu_panel.visible
		launcher.set_pressed_no_signal(menu_panel.visible)


func _select_category(category: int) -> void:
	selected_category = category
	_rebuild_category_buttons()
	_rebuild_building_buttons()


func _select_building_type(building_type: int) -> void:
	set_selected_building(building_type)
	building_selected.emit(selected_building_type)
	close_menu()


func _style(color: Color, border: Color = Color("314653")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	return style


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_stylebox_override("normal", _style(Color("1d2c37")))
	button.add_theme_stylebox_override("hover", _style(Color("2a4350"), ACCENT))
	button.add_theme_stylebox_override("pressed", _style(Color("254b4b"), ACCENT))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), ACCENT))
	button.add_theme_color_override("font_color", Color("e9f1f3"))
	return button


func _label(text: String, font_size: int = 14, color: Color = Color("e9f1f3")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_ui() -> void:
	name = "BuildingMenu"
	launcher = _button("BUILD")
	launcher.icon = BUILDINGS_ICON
	launcher.expand_icon = true
	launcher.add_theme_constant_override("icon_max_width", 28)
	launcher.toggle_mode = true
	launcher.anchor_top = 1.0
	launcher.anchor_bottom = 1.0
	launcher.offset_left = 16
	launcher.offset_top = -68
	launcher.offset_right = 132
	launcher.offset_bottom = -16
	launcher.tooltip_text = "Open construction menu"
	launcher.pressed.connect(toggle_menu)
	add_child(launcher)

	menu_panel = PanelContainer.new()
	menu_panel.visible = false
	menu_panel.anchor_top = 1.0
	menu_panel.anchor_right = 1.0
	menu_panel.anchor_bottom = 1.0
	menu_panel.offset_left = 16
	menu_panel.offset_right = -16
	menu_panel.offset_top = -394
	menu_panel.offset_bottom = -80
	menu_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	menu_panel.add_theme_stylebox_override("panel", _style(Color("12212b")))
	add_child(menu_panel)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 10)
	menu_panel.add_child(menu)
	var heading := HBoxContainer.new()
	menu.add_child(heading)
	var title := _label("CONSTRUCTION", 19, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := _button("Close")
	close.pressed.connect(close_menu)
	heading.add_child(close)

	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu.add_child(tabs_scroll)
	category_row = HBoxContainer.new()
	category_row.add_theme_constant_override("separation", 6)
	tabs_scroll.add_child(category_row)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	building_row = HBoxContainer.new()
	building_row.add_theme_constant_override("separation", 8)
	scroll.add_child(building_row)

	var details := PanelContainer.new()
	details.custom_minimum_size.x = 250
	details.add_theme_stylebox_override("panel", _style(Color("192e38")))
	body.add_child(details)
	var detail_box := VBoxContainer.new()
	details.add_child(detail_box)
	detail_box.add_child(_label("BUILDING BRIEF", 11, ACCENT))
	detail_title = _label("Choose a building", 18)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(detail_title)
	detail_text = _label("Hover or focus a card to see its output and placement requirements.", 13, MUTED)
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(detail_text)

	var footer := HBoxContainer.new()
	menu.add_child(footer)
	selected_building_label = _label("", 13, ACCENT)
	selected_building_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_building_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(selected_building_label)
	var clear := _button("Cancel placement")
	clear.pressed.connect(clear_selection)
	footer.add_child(clear)
	_rebuild_category_buttons()
	_rebuild_building_buttons()


func _apply_selection_label() -> void:
	if selected_building_label == null:
		return
	selected_building_label.text = "Choose a card to begin building"
	if selected_building_type != NO_BUILDING:
		selected_building_label.text = "Placing %s  /  Esc to cancel" % building_manager.get_display_name(selected_building_type)
		_show_details(building_manager.get_definition(selected_building_type))
	for id in cards:
		(cards[id] as Button).set_pressed_no_signal(id == selected_building_type)


func _rebuild_category_buttons() -> void:
	_clear_container(category_row)
	for category in BUILDING_CATEGORIES:
		var button := _button(GameTypes.building_category_display_name(category))
		button.toggle_mode = true
		button.button_pressed = category == selected_category
		button.pressed.connect(_select_category.bind(category))
		category_row.add_child(button)


func _rebuild_building_buttons() -> void:
	if building_row == null:
		return
	_clear_container(building_row)
	cards.clear()
	for definition in building_manager.get_definitions_for_category(selected_category):
		if not definition.player_buildable or not quest_manager.is_building_unlocked(definition.id):
			continue
		var button := _button("")
		button.custom_minimum_size = Vector2(170, 164)
		button.toggle_mode = true
		button.button_pressed = definition.id == selected_building_type
		button.pressed.connect(_select_building_type.bind(definition.id))
		button.mouse_entered.connect(_show_details.bind(definition))
		button.focus_entered.connect(_show_details.bind(definition))
		building_row.add_child(button)
		cards[definition.id] = button
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 10
		content.offset_top = 8
		content.offset_right = -10
		content.offset_bottom = -8
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(content)
		var art := TextureRect.new()
		art.texture = definition.texture if definition.texture != null else BUILDINGS_ICON
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size.y = 86
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(art)
		var title := _label(definition.display_name, 15)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(title)
		var cost := _label(building_manager.format_cost(definition.cost), 12, ACCENT)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(cost)
	if cards.is_empty():
		var empty := _label("More to discover\nComplete quests to unlock this category.", 15, MUTED)
		empty.custom_minimum_size = Vector2(180, 164)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		building_row.add_child(empty)


func _show_details(definition: BuildingDefinition) -> void:
	if definition == null:
		return
	detail_title.text = definition.display_name
	var lines: Array[String] = []
	if definition.production_resource_type != -1:
		lines.append("Base: %d %s / %.0fs" % [definition.production_base_amount, ResourceManager.get_display_name_for_type(definition.production_resource_type), definition.production_interval_seconds])
	if definition.power_generated > 0:
		lines.append("Base power: +%d MW" % definition.power_generated)
	if definition.power_consumed > 0:
		lines.append("Requires %d MW" % definition.power_consumed)
	if definition.input_resource_type != -1:
		lines.append("Input: %d %s / cycle" % [definition.input_amount, ResourceManager.get_display_name_for_type(definition.input_resource_type)])
	if definition.fuel_resource_type != -1:
		lines.append("Fuel: %d %s / %.0fs" % [definition.fuel_amount, ResourceManager.get_display_name_for_type(definition.fuel_resource_type), definition.fuel_interval_seconds])
	var terrains: Array[String] = []
	for terrain in definition.required_terrains:
		terrains.append(GameTypes.terrain_display_name(terrain))
	lines.append("Build on: " + " / ".join(terrains))
	for required in definition.required_adjacent:
		lines.append("Next to: " + building_manager._ref_label(required))
	if not definition.adjacency_yields.is_empty():
		lines.append("Nearby tiles affect output.")
	if definition.id == GameTypes.BuildingType.DOCK:
		lines.append("Shoreline structure; transport not yet available.")
	detail_text.text = "\n".join(lines)


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
