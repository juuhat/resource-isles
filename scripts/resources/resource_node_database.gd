class_name ResourceNodeDatabase
extends RefCounted

const ResourceNodeDefinitionScript := preload("res://scripts/resources/resource_node_definition.gd")
const TREE_TEXTURE := preload("res://assets/resources/tree.png")

var definitions: Dictionary = {}


func _init() -> void:
	_add_definition(ResourceNodeDefinitionScript.new(
		IslandData.ResourceNodeType.TREE,
		"Tree",
		TREE_TEXTURE,
		ResourceManager.ResourceType.WOOD,
		1,
		10.0
	))


func get_definition(resource_node_type: int) -> ResourceNodeDefinition:
	return definitions.get(resource_node_type)


func _add_definition(definition: ResourceNodeDefinition) -> void:
	definitions[definition.id] = definition
