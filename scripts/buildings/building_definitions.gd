class_name BuildingDefinitions
extends RefCounted

# Static catalog of every building's data. Kept separate from BuildingManager so
# the manager holds only generic placement/production logic and this file holds
# the per-building numbers. Add new buildings here.

const BuildingDefinitionScript := preload("res://scripts/buildings/building_definition.gd")
const CRASHED_SPACESHIP_TEXTURE := preload("res://assets/buildings/crashed_spaceship.png")
const LOGGER_CAMP_TEXTURE := preload("res://assets/buildings/logger_camp.png")
const QUARRY_TEXTURE := preload("res://assets/buildings/quarry.png")
const BURNER_GENERATOR_TEXTURE := preload("res://assets/buildings/burner_generator.png")
const SAWMILL_TEXTURE := preload("res://assets/buildings/sawmill.png")
const DOCK_TEXTURE := preload("res://assets/buildings/dock.png")


static func build_all() -> Array[BuildingDefinition]:
	var definitions: Array[BuildingDefinition] = []

	definitions.append(BuildingDefinitionScript.new(
		GameTypes.BuildingType.CRASHED_SPACESHIP,
		"Crashed Spaceship",
		GameTypes.BuildingCategory.UTILITY,
		CRASHED_SPACESHIP_TEXTURE,
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
	logger_camp.power_consumed = 2
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
	quarry.power_consumed = 2
	definitions.append(quarry)

	# The pre-fuel power bootstrap is no longer a building: the robot itself is the
	# tier-0 power source. Parking on any power-consuming building and using the Operate
	# verb hand-powers it for free while the robot stays (see main.gd / power_manager.gd).
	# The self-running burner generator is the upgrade that frees the robot from that.
	var burner_generator := BuildingDefinitionScript.new(
		GameTypes.BuildingType.BURNER_GENERATOR,
		"Burner Generator",
		GameTypes.BuildingCategory.POWER,
		BURNER_GENERATOR_TEXTURE,
		{
			GameTypes.ResourceType.WOOD: 4,
			GameTypes.ResourceType.STONE: 2,
		},
		GameTypes.Terrain.GRASS
	)
	# Burns wood to hold a steady output. Stalls (0 MW) the moment wood runs out.
	burner_generator.power_generated = 5
	burner_generator.fuel_resource_type = GameTypes.ResourceType.WOOD
	burner_generator.fuel_amount = 1
	burner_generator.fuel_interval_seconds = 3.0
	definitions.append(burner_generator)

	var sawmill := BuildingDefinitionScript.new(
		GameTypes.BuildingType.SAWMILL,
		"Sawmill",
		GameTypes.BuildingCategory.PROCESSING,
		SAWMILL_TEXTURE,
		{
			GameTypes.ResourceType.WOOD: 8,
			GameTypes.ResourceType.STONE: 4,
		},
		GameTypes.Terrain.GRASS
	)
	# Refines raw logs into planks. Placed anywhere on grass — it pulls wood from
	# stock, not the map, so it needs no forest. Burns 2 wood to cut 1 plank, and
	# its power draw competes with the burner generator that eats the same wood.
	sawmill.production_resource_type = GameTypes.ResourceType.PLANKS
	sawmill.production_base_amount = 1
	sawmill.production_interval_seconds = 3.0
	sawmill.input_resource_type = GameTypes.ResourceType.WOOD
	sawmill.input_amount = 2
	sawmill.power_consumed = 2
	definitions.append(sawmill)

	var dock := BuildingDefinitionScript.new(
		GameTypes.BuildingType.DOCK,
		"Dock",
		GameTypes.BuildingCategory.LOGISTICS,
		DOCK_TEXTURE,
		{
			GameTypes.ResourceType.WOOD: 10,
			GameTypes.ResourceType.STONE: 5,
		},
		GameTypes.Terrain.SAND
	)
	# Built on the sandy shoreline and must touch open water — the future
	# launch point for boats and inter-island travel. Placeable only for now;
	# no transport behavior yet (see docs/island-unlocks.md, step 1).
	dock.required_adjacent = [_terrain_ref(GameTypes.Terrain.WATER)]
	definitions.append(dock)

	return definitions


static func _resource_ref(resource_node_type: int) -> Dictionary:
	return {kind = GameTypes.AdjacencyKind.RESOURCE, type = resource_node_type}


static func _terrain_ref(terrain_type: int) -> Dictionary:
	return {kind = GameTypes.AdjacencyKind.TERRAIN, type = terrain_type}


static func _yield_rule(kind: int, type: int, amount: int) -> Dictionary:
	return {kind = kind, type = type, amount = amount}
