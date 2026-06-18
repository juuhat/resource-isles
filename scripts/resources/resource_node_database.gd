class_name ResourceNodeDatabase
extends RefCounted

const ResourceNodeDefinitionScript := preload("res://scripts/resources/resource_node_definition.gd")
const FOREST_TEXTURE := preload("res://assets/resources/forest.png")
const STONE_TEXTURE := preload("res://assets/resources/stone.png")
const PINE_FOREST_MODEL := preload("res://assets/models/pine_forest.glb")
const STONE_DEPOSIT_MODEL := preload("res://assets/models/stone_deposit.glb")

var definitions: Dictionary = {}


func _init() -> void:
	var forest := ResourceNodeDefinitionScript.new(
		GameTypes.ResourceNodeType.TREE,
		"Forest",
		FOREST_TEXTURE,
		GameTypes.ResourceType.WOOD,
		Vector2i(1, 1),
		Vector2(0.9, 0.9),
		Vector2.ZERO
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
		Vector2(0.9, 0.9),
		Vector2.ZERO
	)
	stone.model = STONE_DEPOSIT_MODEL
	stone.scavenge_amount = 3
	_add_definition(stone)

	# Island 2+ deposits. Reusing the stone texture/model as placeholder art for now
	# (see docs/second-island-progression.md); give each its own model when authored.
	var iron_ore := ResourceNodeDefinitionScript.new(
		GameTypes.ResourceNodeType.IRON_ORE,
		"Iron Deposit",
		STONE_TEXTURE,
		GameTypes.ResourceType.IRON_ORE,
		Vector2i(1, 1),
		Vector2(0.9, 0.9),
		Vector2.ZERO
	)
	iron_ore.model = STONE_DEPOSIT_MODEL
	iron_ore.scavenge_amount = 3
	_add_definition(iron_ore)

	var coal := ResourceNodeDefinitionScript.new(
		GameTypes.ResourceNodeType.COAL,
		"Coal Seam",
		STONE_TEXTURE,
		GameTypes.ResourceType.COAL,
		Vector2i(1, 1),
		Vector2(0.9, 0.9),
		Vector2.ZERO
	)
	coal.model = STONE_DEPOSIT_MODEL
	coal.scavenge_amount = 3
	_add_definition(coal)


func get_definition(resource_node_type: int) -> ResourceNodeDefinition:
	return definitions.get(resource_node_type)


func _add_definition(definition: ResourceNodeDefinition) -> void:
	definitions[definition.id] = definition
