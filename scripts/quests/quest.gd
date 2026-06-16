class_name Quest
extends RefCounted

# A single quest in the Quest Log: a title, a flavour description, one or more objectives
# to complete, and a reward granted when they're all done. Data only — QuestManager holds
# completion state and applies rewards; QuestCatalog holds the per-quest data.

var id: int
var title: String
var description: String
var objectives: Array[Objective] = []
var reward: QuestReward


func _init(
	new_id: int,
	new_title: String,
	new_description: String,
	new_objectives: Array[Objective],
	new_reward: QuestReward
) -> void:
	id = new_id
	title = new_title
	description = new_description
	objectives = new_objectives
	reward = new_reward


func is_complete(stat_tracker: StatTracker) -> bool:
	for objective in objectives:
		if not objective.is_complete(stat_tracker):
			return false
	return true
