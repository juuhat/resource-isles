class_name ChopMinigame
extends CanvasLayer

# Prototype "swing the axe" minigame. The marker sweeps across a bar and the
# player swings (click / space) to land hits. Perfect hits in the center yield
# more and build a combo; good hits count for less; misses cost a swing's worth
# of time. When all chunks are knocked off the node the total yield is emitted.

signal finished(resource_type: int, total_amount: int)
signal cancelled

const GOOD_HALF_FRACTION := 0.16
const PERFECT_HALF_FRACTION := 0.05
const BASE_MARKER_SPEED := 1.35
const SPEED_GAIN_PER_HIT := 0.12
const PERFECT_YIELD := 2
const GOOD_YIELD := 1
const COMBO_BONUS_THRESHOLD := 2

var active := false
var resource_type := -1
var resource_color := Color.WHITE

var chunks_left := 0
var total_amount := 0
var combo := 0
var marker_pos := 0.0
var marker_dir := 1.0
var marker_speed := BASE_MARKER_SPEED

var root: Control
var title_label: Label
var progress_label: Label
var feedback_label: Label
var bar: Control


func _ready() -> void:
	layer = 10
	_build_ui()
	root.visible = false


func start(definition: ResourceNodeDefinition, node_color: Color) -> void:
	resource_type = definition.extracted_resource_type
	resource_color = node_color
	chunks_left = maxi(3, definition.scavenge_amount)
	total_amount = 0
	combo = 0
	marker_pos = randf()
	marker_dir = 1.0 if randf() < 0.5 else -1.0
	marker_speed = BASE_MARKER_SPEED
	active = true

	title_label.text = "Chopping %s" % definition.display_name
	title_label.add_theme_color_override("font_color", resource_color)
	feedback_label.text = "Swing when the marker hits the green!"
	feedback_label.add_theme_color_override("font_color", Color.WHITE)
	_update_progress()
	root.visible = true


func _process(delta: float) -> void:
	if not active:
		return

	marker_pos += marker_dir * marker_speed * delta
	if marker_pos >= 1.0:
		marker_pos = 1.0 - (marker_pos - 1.0)
		marker_dir = -1.0
	elif marker_pos <= 0.0:
		marker_pos = -marker_pos
		marker_dir = 1.0

	bar.queue_redraw()


func _input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_swing()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_swing()
		get_viewport().set_input_as_handled()


func _swing() -> void:
	var quality := _quality_at_marker()
	match quality:
		2:
			combo += 1
			var gain := PERFECT_YIELD
			if combo >= COMBO_BONUS_THRESHOLD:
				gain += 1
			total_amount += gain
			chunks_left -= 1
			marker_speed += SPEED_GAIN_PER_HIT
			_flash("PERFECT! +%d (x%d combo)" % [gain, combo], Color("#7ee081"))
		1:
			combo = 0
			total_amount += GOOD_YIELD
			chunks_left -= 1
			marker_speed += SPEED_GAIN_PER_HIT * 0.5
			_flash("Good +%d" % GOOD_YIELD, Color("#d7d77a"))
		_:
			combo = 0
			_flash("Miss!", Color("#e07a7a"))

	_update_progress()

	if chunks_left <= 0:
		_finish()


func _quality_at_marker() -> int:
	var distance := absf(marker_pos - 0.5)
	if distance <= PERFECT_HALF_FRACTION:
		return 2
	if distance <= GOOD_HALF_FRACTION:
		return 1
	return 0


func _finish() -> void:
	active = false
	root.visible = false
	finished.emit(resource_type, total_amount)


func _cancel() -> void:
	active = false
	root.visible = false
	cancelled.emit()


func _update_progress() -> void:
	progress_label.text = "Chunks left: %d    Gathered: %d" % [chunks_left, total_amount]


func _flash(text: String, color: Color) -> void:
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", color)
	feedback_label.scale = Vector2(1.25, 1.25)
	feedback_label.pivot_offset = feedback_label.size * 0.5
	var tween := create_tween()
	tween.tween_property(feedback_label, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_ui() -> void:
	name = "ChopMinigame"

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(content)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	content.add_child(title_label)

	bar = Control.new()
	bar.custom_minimum_size = Vector2(460.0, 48.0)
	bar.draw.connect(_on_bar_draw)
	content.add_child(bar)

	feedback_label = Label.new()
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_size_override("font_size", 20)
	content.add_child(feedback_label)

	progress_label = Label.new()
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(progress_label)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "Click / Space to swing      Esc to leave"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	content.add_child(hint)


func _on_bar_draw() -> void:
	var size := bar.size
	var width := size.x
	var height := size.y
	if width <= 0.0:
		return

	var center := width * 0.5
	var good_half := width * GOOD_HALF_FRACTION
	var perfect_half := width * PERFECT_HALF_FRACTION

	bar.draw_rect(Rect2(0, 0, width, height), Color("#2a2a33"))
	bar.draw_rect(Rect2(center - good_half, 0, good_half * 2.0, height), Color("#3f6b41"))
	bar.draw_rect(Rect2(center - perfect_half, 0, perfect_half * 2.0, height), Color("#5ea862"))

	var marker_x := marker_pos * width
	bar.draw_rect(Rect2(marker_x - 3.0, -4.0, 6.0, height + 8.0), Color.WHITE)
	bar.draw_rect(Rect2(0, 0, width, height), Color(1, 1, 1, 0.25), false, 2.0)
