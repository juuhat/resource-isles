class_name FloatingText
extends Label3D

# A world-anchored damage/gain popup (3D, see docs/3d-conversion.md Phase 5). Configure
# `text`, `color`, `font_size`, and `position` (a Vector3 world point) before adding to
# the tree. It rises and fades over `duration`, then frees itself. Billboarded so it
# always faces the camera.

var color := Color.WHITE
var duration := 0.9
var rise := 80.0
# World units per font pixel. Label3D defaults to 0.005, which is microscopic at this
# scene's scale (a hex tile is ~128 units wide), so the popup needs a far larger value.
var pixel_world_size := 1.5

var _elapsed := 0.0
var _start_y := 0.0


func _ready() -> void:
	_start_y = position.y
	pixel_size = pixel_world_size
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	modulate = color
	outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	outline_size = maxi(1, int(round(font_size * 0.14)))
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return

	var progress := _elapsed / duration
	position.y = _start_y + rise * _ease_out(progress)

	var alpha := 1.0 if progress < 0.35 else clampf((1.0 - progress) / 0.65, 0.0, 1.0)
	modulate = Color(color.r, color.g, color.b, alpha)
	outline_modulate = Color(0.0, 0.0, 0.0, alpha)


func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)
