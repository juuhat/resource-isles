class_name QuestCatalog
extends RefCounted

# Static catalog of every quest, mirroring BuildingDefinitions: QuestManager holds the
# generic completion logic, this file holds the per-quest data (title, description,
# objectives, reward). Add new quests here.
#
# There are no explicit prerequisites — ordering falls out of the objectives themselves
# (e.g. a quest that needs stone can only be finished after you've unlocked a quarry to
# mine it). Quests complete by playing; nothing is spent to complete them, and the
# building a reward unlocks still costs resources to place.

const ObjectiveScript := preload("res://scripts/quests/objective.gd")
const QuestScript := preload("res://scripts/quests/quest.gd")


static func build_all() -> Array[Quest]:
	var quests: Array[Quest] = []

	quests.append(QuestScript.new(
		GameTypes.QuestId.FIRST_LOGS,
		"First Logs",
		"Scavenge enough wood by hand to work out a logging camp.",
		[_objective("Gather wood", GameTypes.Stat.WOOD_GATHERED, 10)],
		QuestReward.unlock_building(GameTypes.BuildingType.LOGGER_CAMP, "Unlocks the Logger's Camp")
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.QUICK_FEET,
		"Quick Feet",
		"Get your first building down and pick up the pace.",
		[_objective("Build a building", GameTypes.Stat.BUILDINGS_BUILT, 1)],
		QuestReward.robot_upgrade_reward(GameTypes.RobotUpgrade.FAST_STEPS, "The robot moves faster")
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.POWER_UP,
		"Power Up",
		"Stockpile timber for a generator so buildings run without you.",
		[_objective("Gather wood", GameTypes.Stat.WOOD_GATHERED, 20)],
		QuestReward.unlock_building(GameTypes.BuildingType.BURNER_GENERATOR, "Unlocks the Burner Generator")
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.STONE_AGE,
		"Stone Age",
		"Get a few buildings running, then dig into the rock.",
		[_objective("Build buildings", GameTypes.Stat.BUILDINGS_BUILT, 2)],
		QuestReward.unlock_building(GameTypes.BuildingType.QUARRY, "Unlocks the Quarry")
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.THE_SAWMILL,
		"The Sawmill",
		"Mine stone to build a mill that refines your lumber.",
		[_objective("Gather stone", GameTypes.Stat.STONE_GATHERED, 10)],
		QuestReward.unlock_building(GameTypes.BuildingType.SAWMILL, "Unlocks the Sawmill")
	))

	quests.append(QuestScript.new(
		GameTypes.QuestId.TIRELESS_WORKER,
		"Tireless Worker",
		"Gather plenty by hand to learn how to automate it.",
		[_objective("Gather wood", GameTypes.Stat.WOOD_GATHERED, 25)],
		QuestReward.robot_upgrade_reward(GameTypes.RobotUpgrade.AUTO_GATHER, "The robot keeps harvesting on its own")
	))

	# A multi-objective quest: needs both a wood stockpile and a settled base.
	quests.append(QuestScript.new(
		GameTypes.QuestId.SET_SAIL,
		"Set Sail",
		"Build out your island and gather the timber for a dock.",
		[
			_objective("Gather wood", GameTypes.Stat.WOOD_GATHERED, 40),
			_objective("Build buildings", GameTypes.Stat.BUILDINGS_BUILT, 3),
		],
		QuestReward.unlock_building(GameTypes.BuildingType.DOCK, "Unlocks the Dock")
	))

	return quests


static func _objective(description: String, stat: int, target: int) -> Objective:
	return ObjectiveScript.new(description, stat, target)
