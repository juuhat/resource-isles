class_name GameTypes
extends RefCounted

# "No cell": an unset or not-found cell (nothing hovered, no target, no building there). Cells are
# on the world lattice, which runs negative too, so this sits far outside any world. An island
# that isn't there uses WorldData.NO_COORD instead.
const NO_CELL := Vector2i(-1_000_000, -1_000_000)

# Actions the selected robot can take where it stands, offered on its command bar (see
# Game.refresh_action_bar): work from RobotController, boats from the Game.
enum UnitAction {
	HARVEST,
	OPERATE,
	RESCUE,
	BUILD,
	PILOT_BOAT,
	DISEMBARK,
	CARGO,
	REPAIR,
}

enum Terrain {
	WATER,  # deep water (ocean) — the default for unset cells
	SAND,
	GRASS,
	STONE,
	COAST,  # shallow water within a few tiles of land (Civ-style coast)
}


# Every solid-ground terrain (everything that isn't water). Hand this to a building's
# required_terrains when it can sit on any land rather than one specific terrain.
const LAND_TERRAINS: Array[int] = [Terrain.SAND, Terrain.GRASS, Terrain.STONE]


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
	WINDMILL,  # coastal power: more open water = more wind, crowding buildings = less
	IRON_MINE, # island 2+ extractors (see docs/second-island-progression.md)
	COAL_MINE,
	FURNACE,
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

# Every quest. See Quest / QuestCatalog for each one's objectives and rewards. Play order is
# QuestCatalog's order, not this enum's: ids are saved as ints, so new quests are appended here
# even when they slot earlier in the chain.
enum QuestId {
	RESCUE_THE_DOG, # MAIN: the north-star goal, sail out and bring the dog home
	HELLO_WORLD,    # recover the scattered tools
	BREAK_GROUND,   # first wood + stone -> logging and mining
	FOUNDATIONS,    # build the logger camp + quarry -> refining and power
	REFINE,         # raise a sawmill and mill planks -> the dock
	SET_SAIL,       # build the dock -> reveal the first ring of islands
	THE_SUPPLY_LINE, # dock a second island and run a trade route to it
	STRIKE_IRON,     # hand-mine iron on a frontier island -> the iron and coal mines
	LIVE_WIRE,       # hand-power a building, stockpile wood + stone -> the sawmill
	LIGHT_THE_FORGE,
	POWER_ON,
	FOLLOW_THE_SIGNAL, # discover K9-DA's island after building the dock
	COPPER_GLINT,      # rescue K9-DA and hand-mine copper -> the boat's cargo hold
	HAUL_IT_HOME,      # ship copper ore home to the crash site -> the furnace
	FIRST_MELT,        # build a furnace and smelt copper ingots
	EYES_ON_THE_HORIZON, # repair the ship's radar -> reveal the first ring of islands
}

# Loose pickups scattered on the ground that the robot collects by walking onto them.
enum ItemType {
	AXE,
	PICKAXE,
	WRENCH,
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
	OPERATING,   # the robot can hand-power a building with Operate (gated until the first extractors stand)
	CARGO_HOLD,  # the robot can load and unload its boat's cargo hold (gated until copper is found)
	REPAIRING,   # the robot can repair the crashed ship at the wreck (gated until the first copper smelting)
}

# Parts of the crashed ship the robot repairs at the wreck, in repair order (see ShipRepairs).
# Saved as ints, so new parts are appended.
enum ShipPart {
	RADAR,
}

enum ResourceNodeType {
	TREE,     # pine trees, on grass; every tree type yields wood (see is_tree)
	STONE,
	IRON_ORE, # iron deposit, found on island 2+ (see docs/second-island-progression.md)
	COAL,     # coal seam, found on island 2+
	COPPER_ORE,
	LEAF_TREE, # broadleaf trees, on grass
	PALM_TREE, # palm trees, on sand
}


# True for every kind of tree: the stands the robot chops and a logger camp fells.
static func is_tree(resource_node_type: int) -> bool:
	return resource_node_type in [ResourceNodeType.TREE, ResourceNodeType.LEAF_TREE, ResourceNodeType.PALM_TREE]

enum ResourceType {
	WOOD,
	STONE,
	PLANKS,
	IRON_ORE, # raw ore mined from an IRON_ORE node; smelted into iron later
	COAL,      # raw coal mined from a COAL node; smelter reductant + power fuel
	IRON_INGOT,
	COPPER_ORE,
	COPPER_INGOT,
}

enum AdjacencyKind {
	TERRAIN,
	RESOURCE,
	BUILDING,
	ANY_BUILDING,  # matches any neighboring building regardless of type (the rule's `type` is ignored)
	ANY_TREE,      # matches any neighboring tree, pine, leaf or palm (the rule's `type` is ignored)
}

# Cumulative lifetime play stats (totals that only ever go up, not current stock).
# Quest objectives track progress against one of these — see Objective.
enum Stat {
	WOOD_GATHERED,
	STONE_GATHERED,
	PLANKS_GATHERED,
	IRON_ORE_GATHERED, # island 2+ (see docs/second-island-progression.md)
	COAL_GATHERED,     # island 2+
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
	TRADE_ROUTES_ESTABLISHED, # trade routes ever set up
	GOODS_SHIPPED,            # units of cargo boats have ever unloaded
	# Per-building-type build counts added after the first block (appended: stats save as ints).
	IRON_MINES_BUILT,
	COAL_MINES_BUILT,
	DOG_RESCUED, # K9-DA picked up by the robot (the MAIN quest; 0 or 1)
	BUILDINGS_OPERATED, # times the robot started hand-powering a building with Operate
	IRON_INGOTS_GATHERED,
	FURNACES_BUILT,
	COPPER_ORE_GATHERED,
	DOG_ISLAND_DISCOVERED,
	COPPER_ORE_SHIPPED_HOME, # copper ore unloaded from the boat at the start island
	COPPER_INGOTS_GATHERED,
	SHIP_PARTS_REPAIRED,     # parts of the crashed ship the robot has repaired (see ShipPart)
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
		Stat.DOG_RESCUED:
			return "K9-DA rescued"
		Stat.DOG_ISLAND_DISCOVERED:
			return "K9-DA's island discovered"
		Stat.BUILDINGS_OPERATED:
			return "Buildings operated"
		Stat.IRON_INGOTS_GATHERED:
			return "Iron ingots produced"
		Stat.FURNACES_BUILT:
			return "Furnaces built"
		Stat.COPPER_ORE_GATHERED:
			return "Copper ore gathered"
		Stat.COPPER_ORE_SHIPPED_HOME:
			return "Copper ore shipped home"
		Stat.COPPER_INGOTS_GATHERED:
			return "Copper ingots produced"
		Stat.SHIP_PARTS_REPAIRED:
			return "Ship parts repaired"
		_:
			return "Unknown"


static func item_display_name(item_type: int) -> String:
	match item_type:
		ItemType.AXE:
			return "Axe"
		ItemType.PICKAXE:
			return "Pickaxe"
		ItemType.WRENCH:
			return "Wrench"
		_:
			return "Unknown"
