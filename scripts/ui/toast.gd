class_name Toast
extends CanvasLayer

# Lightweight transient notifications that fade in at the top-center, hold, then fade
# out and remove themselves. For moments the player should feel without opening a
# screen — e.g. a quest completing. Messages stack vertically.

const LIFETIME_SECONDS := 3.0
const FADE_SECONDS := 0.4

var _stack: VBoxContainer


func _ready() -> void:
	name = "Toast"
	_stack = VBoxContainer.new()
	_stack.anchor_left = 0.5
	_stack.anchor_right = 0.5
	_stack.anchor_top = 0.0
	_stack.offset_left = -220.0
	_stack.offset_right = 220.0
	_stack.offset_top = 24.0
	_stack.add_theme_constant_override("separation", 6)
	# Let clicks pass through to the game underneath.
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)


func show_message(text: String) -> void:
	var panel := PanelContainer.new()
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	margin.add_child(label)

	_stack.add_child(panel)

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, FADE_SECONDS)
	tween.tween_interval(LIFETIME_SECONDS)
	tween.tween_property(panel, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(panel.queue_free)
