class_name ResourceNodeDatabase
extends RefCounted

const ResourceNodeDefinitionScript := preload("res://scripts/resources/resource_node_definition.gd")
const FOREST_TEXTURE := preload("res://assets/resources/forest.png")
const STONE_TEXTURE := preload("res://assets/resources/stone.png")
const PINE_FOREST_MODEL := preload("res://assets/models/pine_forest.glb")

var definitions: Dictionary = {}


func _init() -> void:
	var forest := ResourceNodeDefinitionScript.new(
		GameTypes.ResourceNodeType.TREE,
		"Forest",
		FOREST_TEXTURE,
		GameTypes.ResourceType.WOOD,
		Vector2i(1, 1),
		Vector2(1.0, 1.25),
		Vector2(0.0, -0.25)
	)
	forest.model = PINE_FOREST_MODEL
	forest.scavenge_amount = 3
	_add_definition(forest)

	var stone := ResourceNodeDefinitionScript.new(
		GameTypes.ResourceNodeType.STONE,
		"Stone",
		STONE_TEXTURE,
		GameTypes.ResourceType.STONE,
		Vector2i(1, 1),
		Vector2(1.0, 1.0),
		Vector2.ZERO
	)
	stone.scavenge_amount = 3
	_add_definition(stone)


func get_definition(resource_node_type: int) -> ResourceNodeDefinition:
	return definitions.get(resource_node_type)


func _add_definition(definition: ResourceNodeDefinition) -> void:
	definitions[definition.id] = definition
