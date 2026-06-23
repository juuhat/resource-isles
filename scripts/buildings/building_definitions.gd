class_name BuildingDefinitions
extends RefCounted

# Static catalog of every building's data. Kept separate from BuildingManager so
# the manager holds only generic placement/production logic and this file holds
# the per-building numbers. Add new buildings here.

const BuildingDefinitionScript := preload("res://scripts/buildings/building_definition.gd")
const CRASHED_SPACESHIP_TEXTURE := preload("res://assets/buildings/crashed_spaceship.png")
const CRASHED_SPACESHIP_MODEL := preload("res://assets/models/buildings/crashed_spaceship.glb")
const LOGGER_CAMP_TEXTURE := preload("res://assets/buildings/logger_camp.png")
const QUARRY_TEXTURE := preload("res://assets/buildings/quarry.png")
const BURNER_GENERATOR_TEXTURE := preload("res://assets/buildings/burner_generator.png")
const SAWMILL_TEXTURE := preload("res://assets/buildings/sawmill.png")
const DOCK_TEXTURE := preload("res://assets/buildings/dock.png")
const WINDMILL_MODEL := preload("res://assets/models/buildings/windmill2.glb")


static func build_all() -> Array[BuildingDefinition]:
	var definitions: Array[BuildingDefinition] = []

	# The wreck is placed by worldgen as the starting landmark / win-condition ship, never
	# by the player — so it stays out of the build menu.
	var crashed_spaceship := BuildingDefinitionScript.new()
	crashed_spaceship.id = GameTypes.BuildingType.CRASHED_SPACESHIP
	crashed_spaceship.display_name = "Crashed Spaceship"
	crashed_spaceship.category = GameTypes.BuildingCategory.UTILITY
	crashed_spaceship.texture = CRASHED_SPACESHIP_TEXTURE
	crashed_spaceship.cost = {
		GameTypes.ResourceType.WOOD: 8,
		GameTypes.ResourceType.STONE: 4,
	}
	crashed_spaceship.required_terrains = [GameTypes.Terrain.GRASS]
	crashed_spaceship.visual_size_tiles = Vector2(1.6, 1.6)
	crashed_spaceship.player_buildable = false
	crashed_spaceship.model = CRASHED_SPACESHIP_MODEL
	crashed_spaceship.visual_rotation_y = 35.0
	definitions.append(crashed_spaceship)

	var logger_camp := BuildingDefinitionScript.new()
	logger_camp.id = GameTypes.BuildingType.LOGGER_CAMP
	logger_camp.display_name = "Logger's Camp"
	logger_camp.category = GameTypes.BuildingCategory.RESOURCES
	logger_camp.texture = LOGGER_CAMP_TEXTURE
	logger_camp.cost = {GameTypes.ResourceType.WOOD: 6}
	logger_camp.required_terrains = [GameTypes.Terrain.GRASS]
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

	var quarry := BuildingDefinitionScript.new()
	quarry.id = GameTypes.BuildingType.QUARRY
	quarry.display_name = "Quarry"
	quarry.category = GameTypes.BuildingCategory.RESOURCES
	quarry.texture = QUARRY_TEXTURE
	quarry.cost = {GameTypes.ResourceType.WOOD: 6}
	quarry.required_terrains = GameTypes.LAND_TERRAINS
	# Same rule as the logger's camp, one terrain over: built on the grass rim of a
	# rocky outcrop and reaching in. Must touch a stone deposit, earns +1 per adjacent
	# deposit, but neighboring quarries compete for the same rock face: -1 each.
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
	var burner_generator := BuildingDefinitionScript.new()
	burner_generator.id = GameTypes.BuildingType.BURNER_GENERATOR
	burner_generator.display_name = "Burner Generator"
	burner_generator.category = GameTypes.BuildingCategory.POWER
	burner_generator.texture = BURNER_GENERATOR_TEXTURE
	burner_generator.cost = {
		GameTypes.ResourceType.WOOD: 4,
		GameTypes.ResourceType.STONE: 2,
	}
	burner_generator.required_terrains = [GameTypes.Terrain.GRASS]
	# Burns wood to hold a steady output. Stalls (0 MW) the moment wood runs out.
	burner_generator.power_generated = 5
	burner_generator.fuel_resource_type = GameTypes.ResourceType.WOOD
	burner_generator.fuel_amount = 1
	burner_generator.fuel_interval_seconds = 3.0
	definitions.append(burner_generator)

	# Fuel-free coastal power: it always spins (no fuel), and its output is shaped entirely
	# by where it sits. Built on the shore and must touch the coastal water ring; open water
	# around it means more wind (+1 MW each), while crowding buildings block the airflow
	# (-1 MW each). Model only — rendered from the .glb, no flat icon.
	var windmill := BuildingDefinitionScript.new()
	windmill.id = GameTypes.BuildingType.WINDMILL
	windmill.display_name = "Windmill"
	windmill.category = GameTypes.BuildingCategory.POWER
	windmill.model = WINDMILL_MODEL
	# The blades are a separate object in the .glb; spin them around the model-local axle.
	windmill.spin_node_name = "Blades"
	windmill.cost = {
		GameTypes.ResourceType.WOOD: 6,
		GameTypes.ResourceType.STONE: 2,
	}
	windmill.visual_size_tiles = Vector2(0.75, 0.75)
	windmill.required_terrains = [GameTypes.Terrain.SAND, GameTypes.Terrain.GRASS]
	windmill.required_adjacent = [_terrain_ref(GameTypes.Terrain.COAST)]
	windmill.adjacency_yields = [
		_yield_rule(GameTypes.AdjacencyKind.TERRAIN, GameTypes.Terrain.COAST, 1),
		_yield_rule(GameTypes.AdjacencyKind.TERRAIN, GameTypes.Terrain.WATER, 1),
		_yield_rule(GameTypes.AdjacencyKind.ANY_BUILDING, 0, -1),
	]
	# Base 1 MW marks it as a generator (the power loop skips base-0 buildings) and gives a
	# shoreline windmill a floor; the coast it must touch then lifts it to at least 2 MW.
	windmill.power_generated = 1
	definitions.append(windmill)

	var sawmill := BuildingDefinitionScript.new()
	sawmill.id = GameTypes.BuildingType.SAWMILL
	sawmill.display_name = "Sawmill"
	sawmill.category = GameTypes.BuildingCategory.PROCESSING
	sawmill.texture = SAWMILL_TEXTURE
	sawmill.cost = {
		GameTypes.ResourceType.WOOD: 8,
		GameTypes.ResourceType.STONE: 4,
	}
	sawmill.required_terrains = [GameTypes.Terrain.GRASS]
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

	var dock := BuildingDefinitionScript.new()
	dock.id = GameTypes.BuildingType.DOCK
	dock.display_name = "Dock"
	dock.category = GameTypes.BuildingCategory.LOGISTICS
	dock.texture = DOCK_TEXTURE
	dock.cost = {
		GameTypes.ResourceType.WOOD: 10,
		GameTypes.ResourceType.STONE: 5,
	}
	dock.required_terrains = [GameTypes.Terrain.SAND]
	# Built on the sandy shoreline and must touch open water — the future
	# launch point for boats and inter-island travel. Placeable only for now;
	# no transport behavior yet (see docs/island-unlocks.md, step 1).
	# Coast = the shallow water that always rings land, so a shoreline dock touches it.
	dock.required_adjacent = [_terrain_ref(GameTypes.Terrain.COAST)]
	definitions.append(dock)

	return definitions


static func _resource_ref(resource_node_type: int) -> Dictionary:
	return {kind = GameTypes.AdjacencyKind.RESOURCE, type = resource_node_type}


static func _terrain_ref(terrain_type: int) -> Dictionary:
	return {kind = GameTypes.AdjacencyKind.TERRAIN, type = terrain_type}


static func _yield_rule(kind: int, type: int, amount: int) -> Dictionary:
	return {kind = kind, type = type, amount = amount}
