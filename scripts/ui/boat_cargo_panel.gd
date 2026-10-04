class_name BoatCargoPanel
extends CanvasLayer

signal transfer_requested(resource: int, amount: int, loading: bool)

const Cargo := preload("res://scripts/player/boat_cargo.gd")
const Slot := preload("res://scripts/ui/cargo_slot.gd")

var panel: PanelContainer
var location_label: Label
var island_slots: Array = []
var boat_slots: Array = []
var amount_dialog: ConfirmationDialog
var amount_label: Label
var amount_picker: SpinBox
var hold: Inventory
var island: IslandData
var pending_resource := -1
var pending_loading := false
var pending_island: IslandData
var pending_hold: Dictionary
var pending_slot: Control

func _ready() -> void:
	layer = 8
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -380
	panel.offset_right = -16
	panel.offset_top = -210
	panel.offset_bottom = 140
	var style := StyleBoxFlat.new()
	style.bg_color = Color("12212b")
	style.border_color = Color("397b80")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := Label.new()
	title.text = "Cargo transfer"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	heading.add_child(close_button)
	location_label = Label.new()
	location_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(location_label)
	_add_heading(column, "Island inventory")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for resource in GameTypes.ResourceType.values():
		var slot := _make_slot(grid, false)
		slot.resource = resource
		island_slots.append(slot)
	_add_heading(column, "Boat hold · 2 slots · 20 units each")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for index in Cargo.SLOT_COUNT:
		boat_slots.append(_make_slot(row, true))
	var hint := Label.new()
	hint.text = "Drag a resource between inventories.\nChoose how many to transfer."
	hint.add_theme_color_override("font_color", Color("9eafbb"))
	column.add_child(hint)
	_build_amount_dialog()
	close()

func _add_heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("79dcc5"))
	parent.add_child(label)

func _make_slot(parent: Control, on_boat: bool) -> Control:
	var slot := Slot.new()
	slot.cargo_panel = self
	slot.boat_slot = on_boat
	parent.add_child(slot)
	return slot

func _build_amount_dialog() -> void:
	amount_dialog = ConfirmationDialog.new()
	amount_dialog.title = "Transfer stack"
	amount_dialog.confirmed.connect(_confirm_transfer)
	amount_dialog.canceled.connect(_clear_pending)
	add_child(amount_dialog)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	amount_dialog.add_child(column)
	amount_label = Label.new()
	column.add_child(amount_label)
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := Label.new()
	label.text = "Stack size"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	amount_picker = SpinBox.new()
	amount_picker.min_value = 1
	amount_picker.max_value = Cargo.SLOT_CAPACITY
	amount_picker.step = 1
	amount_picker.custom_minimum_size.x = 130
	row.add_child(amount_picker)

func is_open() -> bool:
	return panel != null and panel.visible

func close() -> void:
	if panel != null:
		panel.hide()
	if amount_dialog != null:
		amount_dialog.hide()
	hold = null
	island = null
	_clear_pending()

func show_cargo(new_hold: Inventory, new_island: IslandData) -> void:
	hold = new_hold
	island = new_island
	panel.show()
	refresh()

func update_context(new_hold: Inventory, new_island: IslandData) -> void:
	hold = new_hold
	island = new_island
	refresh()

func refresh() -> void:
	if not is_open() or hold == null:
		return
	location_label.text = island.island_name if island != null else "Moor beside a clear shoreline or dock to transfer cargo."
	for slot in island_slots:
		var quantity := island.inventory.get_amount(slot.resource) if island != null else 0
		slot.show_resource(slot.resource, quantity, island != null and quantity > 0)
	# Keep occupied slots in place while stock changes, so dragging never moves a target.
	var assigned: Array[int] = []
	for slot in boat_slots:
		if slot.resource >= 0 and hold.get_amount(slot.resource) > 0:
			assigned.append(slot.resource)
		else:
			slot.resource = -1
	for resource in GameTypes.ResourceType.values():
		if hold.get_amount(resource) > 0 and not assigned.has(resource):
			for slot in boat_slots:
				if slot.resource == -1:
					slot.resource = resource
					assigned.append(resource)
					break
	for slot in boat_slots:
		slot.show_resource(slot.resource, hold.get_amount(slot.resource), island != null)
	if amount_dialog.visible:
		var maximum := _pending_maximum()
		if maximum <= 0:
			amount_dialog.hide()
			_clear_pending()
		else:
			amount_picker.max_value = maximum

func maximum_transfer(resource: int, loading: bool) -> int:
	if island == null or hold == null:
		return 0
	return mini(island.inventory.get_amount(resource), Cargo.space_for(hold, resource)) if loading else hold.get_amount(resource)

func can_drop_on(slot: Control, data: Variant) -> bool:
	if not data is Dictionary or data.get("cargo_panel") != self or not data.has("resource") or not data.has("loading"):
		return false
	var resource := int(data.resource)
	var loading := bool(data.loading)
	if slot.boat_slot != loading or maximum_transfer(resource, loading) <= 0:
		return false
	if loading:
		return slot.resource == resource or (slot.resource == -1 and hold.get_amount(resource) == 0)
	return slot.resource == resource

func request_drop(slot: Control, data: Variant) -> void:
	if not can_drop_on(slot, data):
		return
	pending_resource = int(data.resource)
	pending_loading = bool(data.loading)
	pending_island = island
	pending_hold = hold.amounts
	pending_slot = slot
	var maximum := maximum_transfer(pending_resource, pending_loading)
	amount_picker.max_value = maximum
	amount_picker.value = maximum
	amount_label.text = "%s %s\n%s" % ["Load" if pending_loading else "Unload", ResourceManager.get_display_name_for_type(pending_resource), "Island → Boat" if pending_loading else "Boat → Island"]
	amount_dialog.get_ok_button().text = "Load" if pending_loading else "Unload"
	amount_dialog.popup_centered(Vector2i(340, 200))
	amount_picker.get_line_edit().grab_focus()
	amount_picker.get_line_edit().select_all()

func _pending_maximum() -> int:
	if pending_resource < 0 or island != pending_island or hold == null or not is_same(hold.amounts, pending_hold):
		return 0
	var data := {cargo_panel = self, resource = pending_resource, loading = pending_loading}
	return maximum_transfer(pending_resource, pending_loading) if can_drop_on(pending_slot, data) else 0

func _confirm_transfer() -> void:
	amount_picker.apply()
	var amount := int(amount_picker.value)
	if amount > 0 and amount <= _pending_maximum():
		transfer_requested.emit(pending_resource, amount, pending_loading)
	_clear_pending()
	refresh()

func _clear_pending() -> void:
	pending_resource = -1
	pending_island = null
	pending_hold = {}
	pending_slot = null
