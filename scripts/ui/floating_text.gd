class_name FloatingText
extends Node2D

# Configure these before adding the node to the tree.
# font_size and rise are in screen pixels; they are converted to world units
# at spawn so the popup stays a constant size regardless of camera zoom.
var text := "+1"
var color := Color.WHITE
var font_size := 22
var duration := 0.9
var rise := 44.0

var _font: Font
var _elapsed := 0.0
var _start := Vector2.ZERO
var _world_scale := 1.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_start = position
	z_index = 1000

	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.zoom.x != 0.0:
		_world_scale = 1.0 / camera.zoom.x


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return

	position.y = _start.y - rise * _world_scale * _ease_out(_elapsed / duration)
	queue_redraw()


func _draw() -> void:
	var progress := _elapsed / duration
	# Hold full opacity briefly so the number is readable, then fade out.
	var alpha := 1.0 if progress < 0.35 else clampf((1.0 - progress) / 0.65, 0.0, 1.0)
	var world_font := int(round(font_size * _world_scale))
	var outline := maxi(1, int(round(world_font * 0.14)))
	var width := 256.0 * _world_scale
	var origin := Vector2(-width * 0.5, 0.0)

	draw_string_outline(
		_font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, world_font, outline,
		Color(0.0, 0.0, 0.0, alpha)
	)
	draw_string(
		_font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, width, world_font,
		Color(color.r, color.g, color.b, alpha)
	)


func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)
