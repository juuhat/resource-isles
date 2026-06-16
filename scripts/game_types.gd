class_name GameTypes
extends RefCounted

enum Terrain {
	WATER,
	SAND,
	GRASS,
	STONE,
}

enum BuildingType {
	CRASHED_SPACESHIP,
	LOGGER_CAMP,
	QUARRY,
	BURNER_GENERATOR,
	SAWMILL,
	DOCK,
}

enum BuildingCategory {
	RESOURCES,
	POWER,
	PROCESSING,
	LOGISTICS,
	UTILITY,
}

# Every quest. See Quest / QuestCatalog for each one's objectives and reward.
enum QuestId {
	FIRST_LOGS,
	QUICK_FEET,
	POWER_UP,
	STONE_AGE,
	THE_SAWMILL,
	TIRELESS_WORKER,
	SET_SAIL,
}

# What completing a quest grants.
enum RewardKind {
	UNLOCK_BUILDING, # makes a BuildingType placeable
	ROBOT_UPGRADE,   # improves the robot itself (see RobotUpgrade)
}

# Robot self-improvements granted as quest rewards; effects applied in main.gd.
enum RobotUpgrade {
	FAST_STEPS,  # faster movement between tiles
	AUTO_GATHER, # keep harvesting a node without re-issuing the command
}

enum ResourceNodeType {
	TREE,
	STONE,
}

enum ResourceType {
	WOOD,
	STONE,
	PLANKS,
}

enum AdjacencyKind {
	TERRAIN,
	RESOURCE,
	BUILDING,
}

# Cumulative lifetime play stats (totals that only ever go up, not current stock).
# Quest objectives track progress against one of these — see Objective.
enum Stat {
	WOOD_GATHERED,
	STONE_GATHERED,
	PLANKS_GATHERED,
	BUILDINGS_BUILT,
}


static func terrain_display_name(terrain_type: int) -> String:
	match terrain_type:
		Terrain.WATER:
			return "Water"
		Terrain.SAND:
			return "Sand"
		Terrain.GRASS:
			return "Grass"
		Terrain.STONE:
			return "Stone"
		_:
			return "Unknown"


static func building_category_display_name(category: int) -> String:
	match category:
		BuildingCategory.RESOURCES:
			return "Resources"
		BuildingCategory.POWER:
			return "Power"
		BuildingCategory.PROCESSING:
			return "Processing"
		BuildingCategory.LOGISTICS:
			return "Logistics"
		BuildingCategory.UTILITY:
			return "Utility"
		_:
			return "Unknown"


static func stat_display_name(stat: int) -> String:
	match stat:
		Stat.WOOD_GATHERED:
			return "Wood gathered"
		Stat.STONE_GATHERED:
			return "Stone gathered"
		Stat.PLANKS_GATHERED:
			return "Planks gathered"
		Stat.BUILDINGS_BUILT:
			return "Buildings built"
		_:
			return "Unknown"
