class_name QuestCatalog
extends RefCounted

# Static catalog of every quest, mirroring BuildingDefinitions: QuestManager holds the
# generic completion logic, this file holds the per-quest data (kind, title, description,
# objectives, rewards). Add new quests here.
#
# Structure: one MAIN quest (the persistent "rescue the dog" goal) plus a short LINEAR chain
# of MILESTONE quests. The milestones are listed in play order and advance one at a time —
# only the current milestone is active, the rest are locked until reached (see QuestManager).
# A milestone can grant SEVERAL rewards at once (e.g. unlock the camp and the quarry
# together). Quests complete by playing; nothing is spent to complete them, and the buildings
# a reward unlocks still cost resources to place.

const ObjectiveScript := preload("res://scripts/quests/objective.gd")
const QuestScript := preload("res://scripts/quests/quest.gd")


static func build_all() -> Array[Quest]:
	var quests: Array[Quest] = []

	# The persistent main objective. Not part of the linear chain — always shown as the
	# headline goal until the robot finds K9-DA on his island in the home waters
	# (WorldData.dog_coord) and picks him up with the Rescue action. The copper milestones that
	# follow the rescue (Copper Glint) ask for it too, so the chain waits for it there.
	quests.append(QuestScript.new(
		GameTypes.QuestId.RESCUE_THE_DOG,
		GameTypes.QuestKind.MAIN,
		"Rescue K9-DA",
		"The crash threw Companion Unit K9-DA clear of the ship and onto a "
			+ "neighbouring island. Build a Dock, sail to the island where his signal is coming "
			+ "from, then walk up to him and bring him aboard.",
		[_objective("Rescue K9-DA", GameTypes.Stat.DOG_RESCUED, 1)],
		([] as Array[QuestReward])
	))

	# --- The linear milestone chain (one active at a time, in this order) ---

	quests.append(QuestScript.new(
		GameTypes.QuestId.HELLO_WORLD,
		GameTypes.QuestKind.MILESTONE,
		"Recover Your Tools",
		"The crash scattered the robot's tools across the island. Walk over and "
			+ "collect the axe, pickaxe, and wrench.",
		[_objective("Recover your tools", GameTypes.Stat.TOOLS_COLLECTED, 3)],
		[QuestReward.robot_upgrade_reward(GameTypes.RobotUpgrade.HARVESTING, "Unlocks harvesting")]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.BREAK_GROUND,
		GameTypes.QuestKind.MILESTONE,
		"Break Ground",
		"Scavenge wood and chip out some stone by hand to learn how to work the land.",
		[
			_objective("Gather wood", GameTypes.Stat.WOOD_GATHERED, 6),
			_objective("Gather stone", GameTypes.Stat.STONE_GATHERED, 6),
		],
		[
			QuestReward.unlock_building(GameTypes.BuildingType.LOGGER_CAMP, "Unlocks the Logger's Camp"),
			QuestReward.unlock_building(GameTypes.BuildingType.QUARRY, "Unlocks the Quarry")
		]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.FOUNDATIONS,
		GameTypes.QuestKind.MILESTONE,
		"Lay the Foundations",
		"Time to stop doing everything by hand. Open the build menu and place a Logger's "
			+ "Camp by the trees and a Quarry by the rocks, then let the robot build them.",
		[
			_objective("Build a Logger's Camp", GameTypes.Stat.LOGGER_CAMPS_BUILT, 1),
			_objective("Build a Quarry", GameTypes.Stat.QUARRIES_BUILT, 1),
		],
		[QuestReward.robot_upgrade_reward(GameTypes.RobotUpgrade.OPERATING, "Unlocks powering buildings by hand")]
	))

	# Manual power before automatic power (docs/quest-design.md): the robot is the island's first
	# power source, but only for the one machine it stands at. Stockpiling 20 + 20 makes the player
	# switch between the camp and the quarry. Electricity waits for rescue and smelting.
	quests.append(QuestScript.new(
		GameTypes.QuestId.LIVE_WIRE,
		GameTypes.QuestKind.MILESTONE,
		"Live Wire",
		"The camp and quarry stand idle without power, and there's no generator yet. Until "
			+ "there is, the robot is the power source: park at a machine and Operate it to run it. "
			+ "Keep them working until you've built up a stockpile.",
		[
			_objective("Power a building", GameTypes.Stat.BUILDINGS_OPERATED, 1),
			_objective("Gather wood", GameTypes.Stat.WOOD_GATHERED, 20),
			_objective("Gather stone", GameTypes.Stat.STONE_GATHERED, 20),
		],
		[
			QuestReward.unlock_building(GameTypes.BuildingType.SAWMILL, "Unlocks the Sawmill")
		]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.REFINE,
		GameTypes.QuestKind.MILESTONE,
		"Refine",
		"Raise a Sawmill and feed it your logs, milling a stack of planks sturdy enough "
			+ "to build something that floats.",
		[
			_objective("Build a Sawmill", GameTypes.Stat.SAWMILLS_BUILT, 1),
			_objective("Gather planks", GameTypes.Stat.PLANKS_GATHERED, 12),
		],
		[QuestReward.unlock_building(GameTypes.BuildingType.DOCK, "Unlocks the Dock")]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.SET_SAIL,
		GameTypes.QuestKind.MILESTONE,
		"Set Sail",
		"Build the dock at the water's edge — your way off this island. K9-DA's signal is "
			+ "coming from an island close by.",
		[
			_objective("Build a Dock", GameTypes.Stat.DOCKS_BUILT, 1),
		],
		([] as Array[QuestReward])
	))

	# K9-DA's island lies in the home waters, sailable from the start (WorldData.HOME_WATERS_RINGS).
	quests.append(QuestScript.new(
		GameTypes.QuestId.FOLLOW_THE_SIGNAL,
		GameTypes.QuestKind.MILESTONE,
		"Follow the Signal",
		"K9-DA's signal is coming from a neighbouring island. Board your boat and "
			+ "sail toward the signal marked on the map. Approach the island to clear its fog "
			+ "and discover where he is stranded.",
		[_objective("Discover K9-DA's island", GameTypes.Stat.DOG_ISLAND_DISCOVERED, 1)],
		([] as Array[QuestReward])
	))

	# The copper chain (docs/copper-and-the-radar.md): K9-DA's island is copper and stone. Copper
	# hand-mined there is shipped home, smelted at the crash site and wired into the ship's radar,
	# which charts the first ring of islands. Each step unlocks the next one's tool.
	quests.append(QuestScript.new(
		GameTypes.QuestId.COPPER_GLINT,
		GameTypes.QuestKind.MILESTONE,
		"Copper Glint",
		"Rescue K9-DA. While he sniffs around, the robot's scanner catches a glint in the "
			+ "rock: copper. That's just what the ship's burnt-out wiring needs. Chip some ore out "
			+ "of a deposit by hand.",
		[
			_objective("Rescue K9-DA", GameTypes.Stat.DOG_RESCUED, 1),
			_objective("Gather copper ore", GameTypes.Stat.COPPER_ORE_GATHERED, 6),
		],
		[QuestReward.robot_upgrade_reward(GameTypes.RobotUpgrade.CARGO_HOLD, "Unlocks the boat's cargo hold")]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.HAUL_IT_HOME,
		GameTypes.QuestKind.MILESTONE,
		"Haul It Home",
		"The ship is back at the crash site. Load the copper ore into the boat's cargo hold, "
			+ "sail home, and unload it at the shore.",
		[_objective("Ship copper ore home", GameTypes.Stat.COPPER_ORE_SHIPPED_HOME, 6)],
		[QuestReward.unlock_building(GameTypes.BuildingType.FURNACE, "Unlocks the Furnace")]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.FIRST_MELT,
		GameTypes.QuestKind.MILESTONE,
		"First Melt",
		"Build a Furnace at the crash site. A wood fire is hot enough for copper: feed it the "
			+ "ore and some wood, and Operate its bellows by hand until three ingots are cast.",
		[
			_objective("Build a Furnace", GameTypes.Stat.FURNACES_BUILT, 1),
			_objective("Smelt copper ingots", GameTypes.Stat.COPPER_INGOTS_GATHERED, 3),
		],
		[QuestReward.robot_upgrade_reward(GameTypes.RobotUpgrade.REPAIRING, "Unlocks repairing the ship")]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.EYES_ON_THE_HORIZON,
		GameTypes.QuestKind.MILESTONE,
		"Eyes on the Horizon",
		"Walk up to the wreck and Repair its radar with three copper ingots. With the radar "
			+ "working again, the robot can chart the islands beyond the home waters.",
		[_objective("Repair the radar", GameTypes.Stat.SHIP_PARTS_REPAIRED, 1)],
		[QuestReward.reveal_world_rings(1, "Reveals the first ring of islands")]
	))

	# The frontier's discovery beat (docs/second-island-progression.md): hand-mine a little iron,
	# mirroring the island-1 wood/stone intro, then unlock the buildings that automate it. Iron
	# only lies on the first ring's other islands, so this is geographically self-gating.
	quests.append(QuestScript.new(
		GameTypes.QuestId.STRIKE_IRON,
		GameTypes.QuestKind.MILESTONE,
		"Strike Iron",
		"The radar shows rocky islands further out, threaded with iron. Sail to one and chip "
			+ "some ore out of a deposit by hand. Ship-grade metal could be the key to getting "
			+ "off these islands for good.",
		[_objective("Gather iron ore", GameTypes.Stat.IRON_ORE_GATHERED, 5)],
		[
			QuestReward.unlock_building(GameTypes.BuildingType.IRON_MINE, "Unlocks the Iron Mine"),
			QuestReward.unlock_building(GameTypes.BuildingType.COAL_MINE, "Unlocks the Coal Mine")
		]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.LIGHT_THE_FORGE,
		GameTypes.QuestKind.MILESTONE,
		"Light the Forge",
		"Iron needs a hotter fire than copper: coal. Set a Furnace to its iron recipe, feed it "
			+ "iron ore and coal, and Operate its bellows by hand to smelt six ingots for your "
			+ "first Burner Generator.",
		[
			_objective("Smelt iron ingots", GameTypes.Stat.IRON_INGOTS_GATHERED, 6),
		],
		[
			QuestReward.unlock_building(GameTypes.BuildingType.BURNER_GENERATOR, "Unlocks the Burner Generator")
		]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.POWER_ON,
		GameTypes.QuestKind.MILESTONE,
		"Power On",
		"Use your first six iron ingots, stone and planks to build a Burner Generator. "
			+ "Keep wood in the island stock to fuel it, and let it drive the Furnace's bellows "
			+ "so the robot can get back to exploring.",
		[_objective("Build a Burner Generator", GameTypes.Stat.BURNER_GENERATORS_BUILT, 1)],
		[QuestReward.unlock_building(GameTypes.BuildingType.WINDMILL, "Unlocks the Windmill")]
	))

	# The trade-route tutorial (docs/second-island-progression.md). A route needs a dock at both
	# ends, so establishing one implies the second island's dock too. No mechanical reward yet;
	# the payoff is the running supply line itself.
	quests.append(QuestScript.new(
		GameTypes.QuestId.THE_SUPPLY_LINE,
		GameTypes.QuestKind.MILESTONE,
		"The Supply Line",
		"A new island can't feed itself. Build a Dock there, then open a trade route from a "
			+ "Dock's panel so a boat keeps hauling goods between your islands.",
		[
			_objective("Establish a trade route", GameTypes.Stat.TRADE_ROUTES_ESTABLISHED, 1),
			_objective("Ship goods by boat", GameTypes.Stat.GOODS_SHIPPED, 20),
		],
		([] as Array[QuestReward])
	))

	return quests


static func _objective(description: String, stat: int, target: int) -> Objective:
	return ObjectiveScript.new(description, stat, target)
