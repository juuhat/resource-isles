class_name BuildingMenu
extends CanvasLayer

signal building_selected(building_type: int)
signal selection_cleared

const NO_BUILDING := -1

const BUILDINGS_ICON := preload("res://assets/icons/building.png")

const BUILDING_CATEGORIES := [
	GameTypes.BuildingCategory.RESOURCES,
	GameTypes.BuildingCategory.POWER,
	GameTypes.BuildingCategory.PROCESSING,
	GameTypes.BuildingCategory.LOGISTICS,
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


func setup(new_building_manager: BuildingManager, new_quest_manager: QuestManager) -> void:
	building_manager = new_building_manager
	quest_manager = new_quest_manager
	# Completing a quest can unlock a building; refresh so it appears without reopening.
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
		menu_panel.visible = false


func toggle_menu() -> void:
	if menu_panel != null:
		menu_panel.visible = not menu_panel.visible


func _select_category(category: int) -> void:
	selected_category = category
	_rebuild_category_buttons()
	_rebuild_building_buttons()


func _select_building_type(building_type: int) -> void:
	set_selected_building(building_type)
	building_selected.emit(selected_building_type)


func _build_ui() -> void:
	name = "BuildingMenu"

	var buildings_button := Button.new()
	buildings_button.icon = BUILDINGS_ICON
	buildings_button.expand_icon = true
	buildings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buildings_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	buildings_button.add_theme_constant_override("icon_max_width", 64)
	buildings_button.anchor_left = 0.0
	buildings_button.anchor_top = 1.0
	buildings_button.anchor_right = 0.0
	buildings_button.anchor_bottom = 1.0
	buildings_button.offset_left = 16.0
	buildings_button.offset_top = -104.0
	buildings_button.offset_right = 104.0
	buildings_button.offset_bottom = -16.0
	buildings_button.pressed.connect(toggle_menu)
	add_child(buildings_button)

	menu_panel = PanelContainer.new()
	menu_panel.visible = false
	menu_panel.anchor_left = 0.0
	menu_panel.anchor_top = 1.0
	menu_panel.anchor_right = 1.0
	menu_panel.anchor_bottom = 1.0
	menu_panel.offset_left = 124.0
	menu_panel.offset_top = -142.0
	menu_panel.offset_right = -16.0
	menu_panel.offset_bottom = -16.0
	add_child(menu_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	menu_panel.add_child(margin)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	margin.add_child(menu)

	var title := Label.new()
	title.text = "Buildings"
	menu.add_child(title)

	category_row = HBoxContainer.new()
	category_row.add_theme_constant_override("separation", 6)
	menu.add_child(category_row)

	building_row = HBoxContainer.new()
	building_row.add_theme_constant_override("separation", 8)
	menu.add_child(building_row)

	var clear_button := Button.new()
	clear_button.text = "Clear selection"
	clear_button.pressed.connect(clear_selection)
	menu.add_child(clear_button)

	selected_building_label = Label.new()
	menu.add_child(selected_building_label)
	_rebuild_category_buttons()
	_rebuild_building_buttons()


func _apply_selection_label() -> void:
	if selected_building_label == null:
		return

	if selected_building_type == NO_BUILDING:
		selected_building_label.text = "Selected: none"
		return

	selected_building_label.text = "Selected: %s" % building_manager.get_label(selected_building_type)


func _rebuild_category_buttons() -> void:
	if category_row == null:
		return

	_clear_container(category_row)

	for category in BUILDING_CATEGORIES:
		var button := Button.new()
		button.text = GameTypes.building_category_display_name(category)
		button.disabled = category == selected_category
		button.pressed.connect(_select_category.bind(category))
		category_row.add_child(button)


func _rebuild_building_buttons() -> void:
	if building_row == null:
		return

	_clear_container(building_row)

	var definitions := building_manager.get_definitions_for_category(selected_category)
	var available: Array[BuildingDefinition] = []
	for definition in definitions:
		# Hide worldgen-only buildings and any still locked behind a quest.
		if definition.player_buildable and quest_manager.is_building_unlocked(definition.id):
			available.append(definition)

	if available.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Nothing unlocked yet"
		building_row.add_child(empty_label)
		return

	for definition in available:
		var button := Button.new()
		button.text = building_manager.get_label(definition.id)
		button.pressed.connect(_select_building_type.bind(definition.id))
		building_row.add_child(button)


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
