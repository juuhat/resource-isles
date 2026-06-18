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
	# headline goal until the robot reaches a new island (builds the dock and sails out).
	quests.append(QuestScript.new(
		GameTypes.QuestId.RESCUE_THE_DOG,
		GameTypes.QuestKind.MAIN,
		"Rescue K9-DA",
		"The crash threw Companion Unit K9-DA clear of the ship and onto a "
			+ "neighbouring island. Gather what you need to build a boat and rescue him.",
		[_objective("Sail to a new island", GameTypes.Stat.ISLANDS_REACHED, 1)],
		# No mechanical reward — the payoff is the story beat (and the dock itself is
		# unlocked by the REFINE milestone below, not here, to avoid a circular gate).
		([] as Array[QuestReward])
	))

	# --- The linear milestone chain (one active at a time, in this order) ---

	quests.append(QuestScript.new(
		GameTypes.QuestId.HELLO_WORLD,
		GameTypes.QuestKind.MILESTONE,
		"Recover Your Tools",
		"The crash scattered the robot's tools across the island. Walk over and "
			+ "collect the axe, pickaxe, and hammer.",
		[_objective("Recover your tools", GameTypes.Stat.TOOLS_COLLECTED, 3)],
		[QuestReward.robot_upgrade_reward(GameTypes.RobotUpgrade.HARVESTING, "Unlocks harvesting")]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.BREAK_GROUND,
		GameTypes.QuestKind.MILESTONE,
		"Break Ground",
		"Scavenge wood and chip out some stone by hand to learn how to work the land.",
		[
			_objective("Gather wood", GameTypes.Stat.WOOD_GATHERED, 20),
			_objective("Gather stone", GameTypes.Stat.STONE_GATHERED, 20),
		],
		[
			QuestReward.unlock_building(GameTypes.BuildingType.LOGGER_CAMP, "Unlocks the Logger's Camp"),
			QuestReward.unlock_building(GameTypes.BuildingType.QUARRY, "Unlocks the Quarry")
		]
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.SCALE_UP,
		GameTypes.QuestKind.MILESTONE,
		"Scale Up",
		"Put the land to work: raise a Logger's Camp and a Quarry, then stockpile a real "
			+ "haul of wood and stone for refining and steady power.",
		[
			_objective("Build a Logger's Camp", GameTypes.Stat.LOGGER_CAMPS_BUILT, 1),
			_objective("Build a Quarry", GameTypes.Stat.QUARRIES_BUILT, 1),
			_objective("Gather wood", GameTypes.Stat.WOOD_GATHERED, 100),
			_objective("Gather stone", GameTypes.Stat.STONE_GATHERED, 100),
		],
		[
			QuestReward.unlock_building(GameTypes.BuildingType.SAWMILL, "Unlocks the Sawmill"),
			QuestReward.unlock_building(GameTypes.BuildingType.BURNER_GENERATOR, "Unlocks the Burner Generator")
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
		"Build the dock at the water's edge — your way off this island and out across "
			+ "the open sea.",
		[
			_objective("Build a Dock", GameTypes.Stat.DOCKS_BUILT, 1),
		],
		[QuestReward.reveal_world_rings(1, "Reveals the first ring of islands")]
	))

	return quests


static func _objective(description: String, stat: int, target: int) -> Objective:
	return ObjectiveScript.new(description, stat, target)
