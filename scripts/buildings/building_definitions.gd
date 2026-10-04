class_name BuildingDefinitions
extends RefCounted

# Static catalog of every building's data. Kept separate from BuildingManager so
# the manager holds only generic placement/production logic and this file holds
# the per-building numbers. Add new buildings here.

const BuildingDefinitionScript := preload("res://scripts/buildings/building_definition.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const CRASHED_SPACESHIP_TEXTURE := preload("res://assets/buildings/crashed_spaceship.png")
const CRASHED_SPACESHIP_MODEL := preload("res://assets/models/buildings/crashed_spaceship.glb")
const LOGGER_CAMP_TEXTURE := preload("res://assets/buildings/logger_camp.png")
const LOGGER_CAMP_MODEL := preload("res://assets/models/buildings/logger_camp.glb")
const QUARRY_TEXTURE := preload("res://assets/buildings/quarry.png")
const QUARRY_MODEL := preload("res://assets/models/buildings/quarry.glb")
const BURNER_GENERATOR_TEXTURE := preload("res://assets/buildings/burner_generator.png")
const BURNER_GENERATOR_MODEL := preload("res://assets/models/buildings/burner_generator.glb")
const SAWMILL_TEXTURE := preload("res://assets/buildings/sawmill.png")
const SAWMILL_MODEL := preload("res://assets/models/buildings/sawmill.glb")
const DOCK_TEXTURE := preload("res://assets/buildings/dock.png")
const DOCK_MODEL := preload("res://assets/models/buildings/dock.glb")
const WINDMILL_MODEL := preload("res://assets/models/buildings/windmill2.glb")
const IRON_MINE_MODEL := preload("res://assets/models/buildings/iron_mine.glb")
const COAL_MINE_MODEL := preload("res://assets/models/buildings/coal_mine.glb")


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
	logger_camp.description = "Fells the surrounding forest for a steady supply of wood. Best where trees are thick and other camps are far."
	logger_camp.category = GameTypes.BuildingCategory.RESOURCES
	logger_camp.texture = LOGGER_CAMP_TEXTURE
	logger_camp.model = LOGGER_CAMP_MODEL
	# Powered chopping axe over a block, with shared hand-PTO socket and open front operator yard.
	logger_camp.true_tile_model = true
	logger_camp.visual_size_tiles = Vector2(0.784, 0.784)
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
	quarry.description = "Cuts stone from neighbouring rock deposits. Nearby quarries compete for the same rock face."
	quarry.category = GameTypes.BuildingCategory.RESOURCES
	quarry.texture = QUARRY_TEXTURE
	quarry.model = QUARRY_MODEL
	# Stone drill with a shared PTO socket aligned to the front WorkSpot.
	quarry.true_tile_model = true
	quarry.visual_size_tiles = Vector2(0.787, 0.787)
	quarry.cost = {GameTypes.ResourceType.STONE: 6}
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

	# The frontier's extractors, modeled on the quarry: built beside an iron deposit or coal
	# seam, +1 per adjacent node, -1 per neighboring mine of the same kind working the same
	# vein. Any land will do. Model only — rendered from the .glb, no flat icon.
	var iron_mine := BuildingDefinitionScript.new()
	iron_mine.id = GameTypes.BuildingType.IRON_MINE
	iron_mine.display_name = "Iron Mine"
	iron_mine.description = "Tunnels into neighbouring iron deposits for a steady supply of ore. Nearby iron mines work the same vein."
	iron_mine.category = GameTypes.BuildingCategory.RESOURCES
	iron_mine.model = IRON_MINE_MODEL
	iron_mine.visual_size_tiles = Vector2(0.85, 0.85)
	iron_mine.cost = {
		GameTypes.ResourceType.WOOD: 6,
		GameTypes.ResourceType.STONE: 4,
	}
	iron_mine.required_terrains = GameTypes.LAND_TERRAINS
	iron_mine.required_adjacent = [_resource_ref(GameTypes.ResourceNodeType.IRON_ORE)]
	iron_mine.adjacency_yields = [
		_yield_rule(GameTypes.AdjacencyKind.RESOURCE, GameTypes.ResourceNodeType.IRON_ORE, 1),
		_yield_rule(GameTypes.AdjacencyKind.BUILDING, GameTypes.BuildingType.IRON_MINE, -1),
	]
	iron_mine.production_resource_type = GameTypes.ResourceType.IRON_ORE
	iron_mine.production_base_amount = 1
	iron_mine.production_interval_seconds = 3.0
	iron_mine.power_consumed = 2
	definitions.append(iron_mine)

	var coal_mine := BuildingDefinitionScript.new()
	coal_mine.id = GameTypes.BuildingType.COAL_MINE
	coal_mine.display_name = "Coal Mine"
	coal_mine.description = "Digs coal from neighbouring seams: smelter fuel and island power. Nearby coal mines work the same seam."
	coal_mine.category = GameTypes.BuildingCategory.RESOURCES
	coal_mine.model = COAL_MINE_MODEL
	coal_mine.visual_size_tiles = Vector2(0.85, 0.85)
	coal_mine.cost = {
		GameTypes.ResourceType.WOOD: 6,
		GameTypes.ResourceType.STONE: 4,
	}
	coal_mine.required_terrains = GameTypes.LAND_TERRAINS
	coal_mine.required_adjacent = [_resource_ref(GameTypes.ResourceNodeType.COAL)]
	coal_mine.adjacency_yields = [
		_yield_rule(GameTypes.AdjacencyKind.RESOURCE, GameTypes.ResourceNodeType.COAL, 1),
		_yield_rule(GameTypes.AdjacencyKind.BUILDING, GameTypes.BuildingType.COAL_MINE, -1),
	]
	coal_mine.production_resource_type = GameTypes.ResourceType.COAL
	coal_mine.production_base_amount = 1
	coal_mine.production_interval_seconds = 3.0
	coal_mine.power_consumed = 2
	definitions.append(coal_mine)

	# The pre-fuel power bootstrap is no longer a building: the robot itself is the
	# tier-0 power source. Parking on any power-consuming building and using the Operate
	# verb hand-powers it for free while the robot stays (see main.gd / power_manager.gd).
	# The self-running burner generator is the upgrade that frees the robot from that.
	var burner_generator := BuildingDefinitionScript.new()
	burner_generator.id = GameTypes.BuildingType.BURNER_GENERATOR
	burner_generator.display_name = "Burner Generator"
	burner_generator.description = "Burns wood to power the whole island, freeing the robot from hand-operating buildings. Stalls when the wood runs out."
	burner_generator.category = GameTypes.BuildingCategory.POWER
	burner_generator.texture = BURNER_GENERATOR_TEXTURE
	burner_generator.model = BURNER_GENERATOR_MODEL
	# Authored at true tile scale (tools/build_burner_generator.py): 1.16 units wide / 2 units per
	# tile, so the furnace sits in the back of its tile with an open yard in front.
	burner_generator.visual_size_tiles = Vector2(0.579, 0.579)
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
	windmill.description = "Fuel-free shoreline power. Open water around it means more wind; nearby buildings block the airflow."
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
	sawmill.description = "Saws logs from stock into planks. Needs no forest, just a supply of wood and power."
	sawmill.category = GameTypes.BuildingCategory.PROCESSING
	sawmill.texture = SAWMILL_TEXTURE
	sawmill.model = SAWMILL_MODEL
	# Authored at true tile scale (tools/build_sawmill.py), origin at the tile centre, so the
	# shared generator's socket lands exactly under the robot's hand at the WorkSpot.
	# visual_size_tiles (1.47 units wide / 2 units per tile) only frames the menu art.
	sawmill.true_tile_model = true
	sawmill.visual_size_tiles = Vector2(0.73, 0.73)
	sawmill.cost = {
		GameTypes.ResourceType.WOOD: 10,
		GameTypes.ResourceType.STONE: 10,
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
	dock.description = "A landing on the sandy shore, and the future launch point for boats to other islands."
	dock.category = GameTypes.BuildingCategory.LOGISTICS
	dock.texture = DOCK_TEXTURE
	dock.model = DOCK_MODEL
	# Three tiles in a line: the quay on a sandy shore tile, the pier out over the coast tile
	# beside it (the shallow water that always rings land), and the berth beyond the pier head
	# where the salvage skiff moors, on coast or open water. auto_rotate swings the pier toward
	# the water wherever the player hovers; R picks between several water sides. The future
	# launch point for boats and inter-island travel (see docs/island-unlocks.md).
	dock.footprint = [Vector2i.ZERO, HexGridScript.AXIAL_EAST, HexGridScript.AXIAL_EAST * 2]
	dock.required_terrains = [GameTypes.Terrain.SAND]
	dock.footprint_terrains = [[], [GameTypes.Terrain.COAST], [GameTypes.Terrain.COAST, GameTypes.Terrain.WATER]]
	dock.auto_rotate = true
	# Authored at true tile scale (tools/build_dock.py), origin on the pier tile, the middle of three.
	dock.true_tile_model = true
	# Size of the billboard fallback only; the true-tile model sets its own scale.
	dock.visual_size_tiles = Vector2(1.6, 1.6)
	dock.cost = {
		GameTypes.ResourceType.PLANKS: 10,
		GameTypes.ResourceType.STONE: 15,
	}
	definitions.append(dock)

	return definitions


static func _resource_ref(resource_node_type: int) -> Dictionary:
	return {kind = GameTypes.AdjacencyKind.RESOURCE, type = resource_node_type}


static func _terrain_ref(terrain_type: int) -> Dictionary:
	return {kind = GameTypes.AdjacencyKind.TERRAIN, type = terrain_type}


static func _yield_rule(kind: int, type: int, amount: int) -> Dictionary:
	return {kind = kind, type = type, amount = amount}
