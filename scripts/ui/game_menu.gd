class_name GameMenu
extends CanvasLayer

signal new_game_requested
signal save_game_requested
signal load_game_requested
signal opened

var overlay: ColorRect
var launcher: Button
var load_button: Button
var status_label: Label
var new_game_dialog: ConfirmationDialog


func _ready() -> void:
	name = "GameMenu"
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	launcher = _button("MENU")
	launcher.position = Vector2(16, 70)
	launcher.custom_minimum_size = Vector2(100, 40)
	launcher.pressed.connect(open)
	add_child(launcher)

	overlay = ColorRect.new()
	overlay.color = Color(0.02, 0.05, 0.07, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.hide()
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	panel.add_theme_stylebox_override("panel", _style(Color("12212b")))
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	var title := Label.new()
	title.text = "Game Menu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	body.add_child(title)

	var new_button := _button("New Game")
	new_button.pressed.connect(func(): new_game_dialog.popup_centered())
	body.add_child(new_button)
	var save_button := _button("Save Game")
	save_button.pressed.connect(func(): save_game_requested.emit())
	body.add_child(save_button)
	load_button = _button("Load Game")
	load_button.pressed.connect(func(): load_game_requested.emit())
	body.add_child(load_button)
	status_label = Label.new()
	status_label.custom_minimum_size.x = 280
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	body.add_child(status_label)
	var close_button := _button("Resume")
	close_button.pressed.connect(close)
	body.add_child(close_button)

	new_game_dialog = ConfirmationDialog.new()
	new_game_dialog.title = "New Game"
	new_game_dialog.dialog_text = "Start a new game? This replaces your current save."
	new_game_dialog.ok_button_text = "Start New Game"
	new_game_dialog.confirmed.connect(func(): new_game_requested.emit())
	add_child(new_game_dialog)


func open() -> void:
	opened.emit()
	refresh_save_state()
	status_label.text = "Manual saves and autosaves use the same slot."
	overlay.show()
	launcher.hide()
	get_tree().paused = true


func close() -> void:
	new_game_dialog.hide()
	overlay.hide()
	launcher.show()
	get_tree().paused = false


func is_open() -> bool:
	return overlay != null and overlay.visible


func refresh_save_state() -> void:
	load_button.disabled = not SaveManager.has_save()


func show_status(message: String) -> void:
	status_label.text = message
	refresh_save_state()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
		get_viewport().set_input_as_handled()


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _style(Color("1b303c")))
	button.add_theme_stylebox_override("hover", _style(Color("254b4b")))
	button.add_theme_stylebox_override("pressed", _style(Color("2c5656")))
	return button


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("4b7779")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
