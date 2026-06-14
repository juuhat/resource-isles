class_name ResourceNodeDatabase
extends RefCounted

const ResourceNodeDefinitionScript := preload("res://scripts/resources/resource_node_definition.gd")
const FOREST_TEXTURE := preload("res://assets/resources/forest.png")
const STONE_TEXTURE := preload("res://assets/resources/stone.png")

var definitions: Dictionary = {}


func _init() -> void:
	_add_definition(ResourceNodeDefinitionScript.new(
		IslandData.ResourceNodeType.TREE,
		"Forest",
		FOREST_TEXTURE,
		ResourceManager.ResourceType.WOOD,
		1,
		10.0,
		Vector2i(1, 1),
		Vector2(1.0, 1.25),
		Vector2(0.0, -0.25)
	))
	_add_definition(ResourceNodeDefinitionScript.new(
		IslandData.ResourceNodeType.STONE,
		"Stone",
		STONE_TEXTURE,
		ResourceManager.ResourceType.STONE,
		1,
		12.0,
		Vector2i(1, 1),
		Vector2(1.0, 1.0),
		Vector2.ZERO
	))


func get_definition(resource_node_type: int) -> ResourceNodeDefinition:
	return definitions.get(resource_node_type)


func _add_definition(definition: ResourceNodeDefinition) -> void:
	definitions[definition.id] = definition
