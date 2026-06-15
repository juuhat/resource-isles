class_name ScreenFade
extends CanvasLayer

# A reusable full-screen fade. transition() fades to a calm dark, runs the supplied
# callable at the midpoint (e.g. the island swap), then fades back. Used as the
# placeholder transition between islands until a literal sailing animation exists.

const FADE_TIME := 0.18

var rect: ColorRect


func _ready() -> void:
	layer = 100

	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.04, 0.09, 0.13, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)


func transition(on_midpoint: Callable) -> void:
	# Block input while the screen is covered so a swap can't race with clicks.
	rect.mouse_filter = Control.MOUSE_FILTER_STOP

	var tween := create_tween()
	tween.tween_property(rect, "color:a", 1.0, FADE_TIME)
	tween.tween_callback(on_midpoint)
	tween.tween_property(rect, "color:a", 0.0, FADE_TIME)
	tween.tween_callback(func() -> void: rect.mouse_filter = Control.MOUSE_FILTER_IGNORE)
