class_name ResourceNodeDefinition
extends RefCounted

var id: int
var display_name: String
var texture: Texture2D
var extracted_resource_type: int
var extraction_amount: int
var extraction_interval_seconds: float


func _init(
	new_id: int,
	new_display_name: String,
	new_texture: Texture2D,
	new_extracted_resource_type: int,
	new_extraction_amount: int,
	new_extraction_interval_seconds: float
) -> void:
	id = new_id
	display_name = new_display_name
	texture = new_texture
	extracted_resource_type = new_extracted_resource_type
	extraction_amount = new_extraction_amount
	extraction_interval_seconds = new_extraction_interval_seconds
