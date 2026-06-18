class_name GameTypes
extends RefCounted

enum Terrain {
	WATER,  # deep water (ocean) — the default for unset cells
	SAND,
	GRASS,
	STONE,
	COAST,  # shallow water within a few tiles of land (Civ-style coast)
}


# True for any water tile (deep ocean or shallow coast). Use this for "is this water"
# checks rather than comparing to a single terrain value.
static func is_water(terrain_type: int) -> bool:
	return terrain_type == Terrain.WATER or terrain_type == Terrain.COAST

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

# Two kinds of quest. MAIN is the persistent story objective (always shown, never locked);
# MILESTONE quests form the linear chain played one at a time. See QuestManager.
enum QuestKind {
	MAIN,
	MILESTONE,
}

# Every quest. See Quest / QuestCatalog for each one's objectives and rewards. The MILESTONE
# entries are listed in play order — the chain advances down this list one at a time.
enum QuestId {
	RESCUE_THE_DOG, # MAIN: the north-star goal, sail out and bring the dog home
	HELLO_WORLD,    # recover the scattered tools
	BREAK_GROUND,   # first wood + stone -> logging and mining
	SCALE_UP,       # bigger wood + stone haul -> refining and power
	REFINE,         # raise a sawmill and mill planks -> the dock
	SET_SAIL,       # build the dock -> reveal the first ring of islands
}

# Loose pickups scattered on the ground that the robot collects by walking onto them.
enum ItemType {
	AXE,
	PICKAXE,
	HAMMER,
}

# What completing a quest grants.
enum RewardKind {
	UNLOCK_BUILDING,    # makes a BuildingType placeable
	ROBOT_UPGRADE,      # improves the robot itself (see RobotUpgrade)
	REVEAL_WORLD_RINGS, # reveals more rings of islands on the world map (see WorldData)
}

# Robot self-improvements granted as quest rewards; effects applied in main.gd.
enum RobotUpgrade {
	HARVESTING,  # the robot can harvest resource nodes at all (gated until tools recovered)
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
	BUILDINGS_BUILT, # total of every building placed, any type
	# Per-building-type build counts (cumulative). Keep in sync with BuildingType; the
	# StatTracker bumps both BUILDINGS_BUILT and the matching one of these on each placement.
	LOGGER_CAMPS_BUILT,
	QUARRIES_BUILT,
	BURNER_GENERATORS_BUILT,
	SAWMILLS_BUILT,
	DOCKS_BUILT,
	TOOLS_COLLECTED,
	ISLANDS_REACHED, # new islands discovered/sailed to (the starter doesn't count)
}


static func terrain_display_name(terrain_type: int) -> String:
	match terrain_type:
		Terrain.WATER:
			return "Ocean"
		Terrain.COAST:
			return "Coast"
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
		Stat.LOGGER_CAMPS_BUILT:
			return "Logger's Camps built"
		Stat.QUARRIES_BUILT:
			return "Quarries built"
		Stat.BURNER_GENERATORS_BUILT:
			return "Burner Generators built"
		Stat.SAWMILLS_BUILT:
			return "Sawmills built"
		Stat.DOCKS_BUILT:
			return "Docks built"
		Stat.TOOLS_COLLECTED:
			return "Tools recovered"
		Stat.ISLANDS_REACHED:
			return "Islands reached"
		_:
			return "Unknown"


static func item_display_name(item_type: int) -> String:
	match item_type:
		ItemType.AXE:
			return "Axe"
		ItemType.PICKAXE:
			return "Pickaxe"
		ItemType.HAMMER:
			return "Hammer"
		_:
			return "Unknown"
