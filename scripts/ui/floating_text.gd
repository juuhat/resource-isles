class_name FloatingText
extends Label3D

# A world-anchored damage/gain popup (3D, see docs/3d-models.md). Configure
# `text`, `color`, `font_size`, `icon` (optional), and `position` (a Vector3 world
# point) before adding to the tree. It rises and fades over `duration`, then frees
# itself. Billboarded so it always faces the camera.
#
# When `icon` is set it's drawn as a small billboarded sprite immediately to the left
# of the text (icon + "+3"), with the icon+text pair kept centred on `position`.

var color := Color.WHITE
# Optional resource icon shown to the left of the text (from ResourceDatabase).
var icon: Texture2D = null
var duration := 0.9
var rise := 80.0
# World units per font pixel. Label3D defaults to 0.005, which is microscopic at this
# scene's scale (a hex tile is ~128 units wide), so the popup needs a far larger value.
var pixel_world_size := 1.5

var _elapsed := 0.0
var _start_y := 0.0
var _icon_sprite: Sprite3D = null


func _ready() -> void:
	_start_y = position.y
	pixel_size = pixel_world_size
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	modulate = color
	outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	outline_size = maxi(1, int(round(font_size * 0.14)))
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if icon != null:
		_add_icon()


# Build the icon sprite and shift the text right so the icon+text pair stays centred on
# `position`. Layout is computed in label pixels (then converted to world units via
# pixel_size) so it tracks the font size.
func _add_icon() -> void:
	var label_font: Font = font if font != null else ThemeDB.fallback_font
	var text_width_px := label_font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size
	).x
	# Icon roughly a touch taller than the cap height, with a small gap before the text.
	var icon_px := float(font_size) * 1.1
	var gap_px := float(font_size) * 0.25

	# Nudge the centred text right by half the icon+gap so the whole pair re-centres.
	offset.x = (icon_px + gap_px) * 0.5

	_icon_sprite = Sprite3D.new()
	_icon_sprite.texture = icon
	_icon_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon_sprite.no_depth_test = true
	_icon_sprite.modulate = color
	# Scale the texture so its on-screen height matches icon_px at our pixel size.
	var texture_height := maxf(1.0, float(icon.get_height()))
	_icon_sprite.pixel_size = icon_px * pixel_world_size / texture_height
	# Place the icon to the left of the (now offset) text, vertically centred.
	_icon_sprite.position = Vector3(
		-(gap_px + text_width_px) * 0.5 * pixel_world_size, 0.0, 0.0
	)
	add_child(_icon_sprite)


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
	if _icon_sprite != null:
		_icon_sprite.modulate = Color(1.0, 1.0, 1.0, alpha)


func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)
