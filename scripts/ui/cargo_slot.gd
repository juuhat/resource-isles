extends PanelContainer

var cargo_panel: Node
var boat_slot := false
var resource := -1
var amount := 0
var icon: TextureRect
var count: Label
var empty_label: Label
var slot_style: StyleBoxFlat

func _ready() -> void:
	custom_minimum_size = Vector2(76, 76)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0c1822")
	style.border_color = Color("476572")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	slot_style = style
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	icon = TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 10
	icon.offset_top = 8
	icon.offset_right = -10
	icon.offset_bottom = -14
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	count = Label.new()
	count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	count.offset_right = -7
	count.offset_bottom = -4
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override("font_size", 17)
	count.add_theme_color_override("font_shadow_color", Color.BLACK)
	count.add_theme_constant_override("shadow_offset_x", 1)
	count.add_theme_constant_override("shadow_offset_y", 1)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(count)
	empty_label = Label.new()
	empty_label.text = "Empty"
	empty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.add_theme_color_override("font_color", Color("6e8797"))
	empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(empty_label)

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var viewport := get_viewport()
	var valid_target: bool = viewport.gui_is_dragging() and cargo_panel.can_drop_on(self, viewport.gui_get_drag_data())
	slot_style.border_color = Color("79dcc5") if valid_target else Color("476572")
	slot_style.bg_color = Color("1b3942") if valid_target else Color("0c1822")

func show_resource(type: int, quantity: int, enabled: bool) -> void:
	resource = type
	amount = quantity
	var definition := ResourceDatabase.get_definition(type) if type >= 0 else null
	icon.texture = definition.icon if definition != null else null
	icon.modulate = definition.color if type == GameTypes.ResourceType.IRON_ORE else Color.WHITE
	count.text = str(quantity) if quantity > 0 else ""
	empty_label.visible = type < 0
	modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.45)
	tooltip_text = "%s: %d%s" % [definition.display_name, quantity, " / 20" if boat_slot else ""] if definition != null else "Empty cargo slot — holds 20 units"

func drag_data() -> Variant:
	if amount <= 0 or resource < 0 or cargo_panel.island == null:
		return null
	return {cargo_panel = cargo_panel, resource = resource, loading = not boat_slot}

func _get_drag_data(_at_position: Vector2) -> Variant:
	var data: Variant = drag_data()
	if data == null:
		return null
	var preview := TextureRect.new()
	preview.texture = icon.texture
	preview.modulate = icon.modulate
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(56, 56)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	return data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return cargo_panel.can_drop_on(self, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	cargo_panel.request_drop(self, data)
