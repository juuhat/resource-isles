class_name ResourceNodeDefinition
extends RefCounted

var id: int
var display_name: String
var texture: Texture2D
# Optional 3D model. When set, the renderer instances this instead of the flat texture.
var model: PackedScene = null
var footprint_size: Vector2i
var visual_size_tiles: Vector2
var visual_offset_tiles: Vector2
# Heading (degrees) applied around the Y axis when instancing a 3D model.
var visual_rotation_y: float = 0.0
var extracted_resource_type: int
# One-time yield when the player manually scavenges this node.
var scavenge_amount: int = 1


func _init(
	new_id: int,
	new_display_name: String,
	new_texture: Texture2D,
	new_extracted_resource_type: int,
	new_footprint_size: Vector2i = Vector2i.ONE,
	new_visual_size_tiles: Vector2 = Vector2.ONE,
	new_visual_offset_tiles: Vector2 = Vector2.ZERO
) -> void:
	id = new_id
	display_name = new_display_name
	texture = new_texture
	footprint_size = new_footprint_size
	visual_size_tiles = new_visual_size_tiles
	visual_offset_tiles = new_visual_offset_tiles
	extracted_resource_type = new_extracted_resource_type
