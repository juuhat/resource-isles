class_name ResourceNodeDatabase
extends RefCounted

const ResourceNodeDefinitionScript := preload("res://scripts/resources/resource_node_definition.gd")
const FOREST_TEXTURE := preload("res://assets/resources/forest.png")
const STONE_TEXTURE := preload("res://assets/resources/stone.png")
# Low-poly kit tree stands (tools/build_trees.py) and deposits (tools/build_deposit.py), at true
# tile scale in their own palette materials.
const PINE_TREES_MODEL := preload("res://assets/models/resources/pine_trees.glb")
const LEAF_TREES_MODEL := preload("res://assets/models/resources/leaf_trees.glb")
const PALM_TREES_MODEL := preload("res://assets/models/resources/palm_trees.glb")
const STONE_DEPOSIT_MODEL := preload("res://assets/models/resources/stone_deposit.glb")
const IRON_DEPOSIT_MODEL := preload("res://assets/models/resources/iron_deposit.glb")
const COAL_DEPOSIT_MODEL := preload("res://assets/models/resources/coal_deposit.glb")
const COPPER_DEPOSIT_MODEL := preload("res://assets/models/resources/copper_deposit.glb")
# Deposits have no front, so each tile turns its model up to this far either way.
const DEPOSIT_YAW_VARIATION := 45.0

var definitions: Dictionary = {}


func _init() -> void:
	_add_deposit(GameTypes.ResourceNodeType.TREE, "Pine Trees", GameTypes.ResourceType.WOOD, PINE_TREES_MODEL, 0.741, FOREST_TEXTURE)
	_add_deposit(GameTypes.ResourceNodeType.LEAF_TREE, "Leaf Trees", GameTypes.ResourceType.WOOD, LEAF_TREES_MODEL, 0.749, FOREST_TEXTURE)
	_add_deposit(GameTypes.ResourceNodeType.PALM_TREE, "Palm Trees", GameTypes.ResourceType.WOOD, PALM_TREES_MODEL, 0.820, FOREST_TEXTURE)
	_add_deposit(GameTypes.ResourceNodeType.STONE, "Stone", GameTypes.ResourceType.STONE, STONE_DEPOSIT_MODEL, 0.704)
	# Island 2+ deposits. Reusing the stone texture as their flat fallback art for now
	# (see docs/second-island-progression.md).
	_add_deposit(GameTypes.ResourceNodeType.IRON_ORE, "Iron Deposit", GameTypes.ResourceType.IRON_ORE, IRON_DEPOSIT_MODEL, 0.736)
	_add_deposit(GameTypes.ResourceNodeType.COAL, "Coal Seam", GameTypes.ResourceType.COAL, COAL_DEPOSIT_MODEL, 0.752)
	_add_deposit(GameTypes.ResourceNodeType.COPPER_ORE, "Copper Deposit", GameTypes.ResourceType.COPPER_ORE, COPPER_DEPOSIT_MODEL, 0.726)


func get_definition(resource_node_type: int) -> ResourceNodeDefinition:
	return definitions.get(resource_node_type)


# A tree stand or rock deposit; width_tiles is its model's width as tools/build_trees.py or
# tools/build_deposit.py reports it.
func _add_deposit(node_type: int, display_name: String, resource_type: int, model: PackedScene, width_tiles: float, texture: Texture2D = STONE_TEXTURE) -> void:
	var deposit := ResourceNodeDefinitionScript.new(
		node_type,
		display_name,
		texture,
		resource_type,
		Vector2i(1, 1),
		Vector2(width_tiles, width_tiles),
		Vector2.ZERO
	)
	deposit.model = model
	deposit.true_tile_model = true
	deposit.visual_yaw_variation = DEPOSIT_YAW_VARIATION
	deposit.scavenge_amount = 3
	_add_definition(deposit)


func _add_definition(definition: ResourceNodeDefinition) -> void:
	definitions[definition.id] = definition
