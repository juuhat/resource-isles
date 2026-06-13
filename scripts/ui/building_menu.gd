class_name BuildingMenu
extends CanvasLayer

signal building_selected(building_type: int)
signal selection_cleared

const NO_BUILDING := -1

var selected_building_type := NO_BUILDING
var menu_panel: PanelContainer
var selected_building_label: Label


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


func _select_crate() -> void:
	set_selected_building(IslandData.BuildingType.CRATE)
	building_selected.emit(selected_building_type)


func _build_ui() -> void:
	name = "BuildingMenu"

	var buildings_button := Button.new()
	buildings_button.text = "Buildings"
	buildings_button.anchor_left = 0.0
	buildings_button.anchor_top = 1.0
	buildings_button.anchor_right = 0.0
	buildings_button.anchor_bottom = 1.0
	buildings_button.offset_left = 16.0
	buildings_button.offset_top = -82.0
	buildings_button.offset_right = 116.0
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
	menu_panel.offset_top = -82.0
	menu_panel.offset_right = -16.0
	menu_panel.offset_bottom = -16.0
	add_child(menu_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	menu_panel.add_child(margin)

	var menu := HBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	margin.add_child(menu)

	var title := Label.new()
	title.text = "Buildings"
	title.custom_minimum_size = Vector2(80, 0)
	menu.add_child(title)

	var crate_button := Button.new()
	crate_button.text = "Crate"
	crate_button.pressed.connect(_select_crate)
	menu.add_child(crate_button)

	var clear_button := Button.new()
	clear_button.text = "Clear selection"
	clear_button.pressed.connect(clear_selection)
	menu.add_child(clear_button)

	selected_building_label = Label.new()
	menu.add_child(selected_building_label)


func _apply_selection_label() -> void:
	if selected_building_label == null:
		return

	if selected_building_type == NO_BUILDING:
		selected_building_label.text = "Selected: none"
	else:
		selected_building_label.text = "Selected: Crate"
