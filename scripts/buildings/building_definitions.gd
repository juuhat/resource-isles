class_name BuildingDefinitions
extends RefCounted

# Static catalog of every building's data. Kept separate from BuildingManager so
# the manager holds only generic placement/production logic and this file holds
# the per-building numbers. Add new buildings here.

const BuildingDefinitionScript := preload("res://scripts/buildings/building_definition.gd")
const HUB_TEXTURE := preload("res://assets/buildings/hub.png")
const LOGGER_CAMP_TEXTURE := preload("res://assets/buildings/logger_camp.png")
const QUARRY_TEXTURE := preload("res://assets/buildings/quarry.png")
const BURNER_GENERATOR_TEXTURE := preload("res://assets/buildings/burner_generator.png")


static func build_all() -> Array[BuildingDefinition]:
	var definitions: Array[BuildingDefinition] = []

	definitions.append(BuildingDefinitionScript.new(
		GameTypes.BuildingType.HUB,
		"Hub",
		GameTypes.BuildingCategory.UTILITY,
		HUB_TEXTURE,
		{
			GameTypes.ResourceType.WOOD: 8,
			GameTypes.ResourceType.STONE: 4,
		},
		GameTypes.Terrain.GRASS
	))

	var logger_camp := BuildingDefinitionScript.new(
		GameTypes.BuildingType.LOGGER_CAMP,
		"Logger's Camp",
		GameTypes.BuildingCategory.RESOURCES,
		LOGGER_CAMP_TEXTURE,
		{
			GameTypes.ResourceType.WOOD: 6,
		},
		GameTypes.Terrain.GRASS
	)
	# Must touch a forest, earns +1 per adjacent forest, but crowding other
	# camps strips the surrounding woodland faster than it regrows: -1 each.
	logger_camp.required_adjacent = [_resource_ref(GameTypes.ResourceNodeType.TREE)]
	logger_camp.adjacency_yields = [
		_yield_rule(GameTypes.AdjacencyKind.RESOURCE, GameTypes.ResourceNodeType.TREE, 1),
		_yield_rule(GameTypes.AdjacencyKind.BUILDING, GameTypes.BuildingType.LOGGER_CAMP, -1),
	]
	logger_camp.production_resource_type = GameTypes.ResourceType.WOOD
	logger_camp.production_base_amount = 1
	logger_camp.production_interval_seconds = 3.0
	definitions.append(logger_camp)

	var quarry := BuildingDefinitionScript.new(
		GameTypes.BuildingType.QUARRY,
		"Quarry",
		GameTypes.BuildingCategory.RESOURCES,
		QUARRY_TEXTURE,
		{
			GameTypes.ResourceType.WOOD: 6,
		},
		GameTypes.Terrain.STONE
	)
	# Must touch stone, earns +1 per adjacent deposit, but neighboring
	# quarries compete for the same workable rock face: -1 each.
	quarry.required_adjacent = [_resource_ref(GameTypes.ResourceNodeType.STONE)]
	quarry.adjacency_yields = [
		_yield_rule(GameTypes.AdjacencyKind.RESOURCE, GameTypes.ResourceNodeType.STONE, 1),
		_yield_rule(GameTypes.AdjacencyKind.BUILDING, GameTypes.BuildingType.QUARRY, -1),
	]
	quarry.production_resource_type = GameTypes.ResourceType.STONE
	quarry.production_base_amount = 1
	quarry.production_interval_seconds = 3.0
	definitions.append(quarry)

	definitions.append(BuildingDefinitionScript.new(
		GameTypes.BuildingType.BURNER_GENERATOR,
		"Burner Generator",
		GameTypes.BuildingCategory.POWER,
		BURNER_GENERATOR_TEXTURE,
		{
			GameTypes.ResourceType.WOOD: 4,
			GameTypes.ResourceType.STONE: 2,
		},
		GameTypes.Terrain.GRASS
	))

	return definitions


static func _resource_ref(resource_node_type: int) -> Dictionary:
	return {kind = GameTypes.AdjacencyKind.RESOURCE, type = resource_node_type}


static func _yield_rule(kind: int, type: int, amount: int) -> Dictionary:
	return {kind = kind, type = type, amount = amount}
