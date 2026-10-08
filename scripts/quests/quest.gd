class_name Quest
extends RefCounted

# A single quest in the Quest Log: a kind (MAIN story goal vs MILESTONE chain step), a
# title, a flavour description, one or more objectives to complete, and one or more rewards
# granted when they're all done. Optionally, highlights: the things in the world that glow while
# the quest is active, to show the player where to go. Data only — QuestManager holds completion
# state and applies rewards; QuestCatalog holds the per-quest data.

var id: int
var kind: int
var title: String
var description: String
var objectives: Array[Objective] = []
var rewards: Array[QuestReward] = []
var highlights: Array[QuestTarget] = []


func _init(
	new_id: int,
	new_kind: int,
	new_title: String,
	new_description: String,
	new_objectives: Array[Objective],
	new_rewards: Array[QuestReward],
	new_highlights: Array[QuestTarget] = []
) -> void:
	id = new_id
	kind = new_kind
	title = new_title
	description = new_description
	objectives = new_objectives
	rewards = new_rewards
	highlights = new_highlights


func is_complete(stat_tracker: StatTracker) -> bool:
	for objective in objectives:
		if not objective.is_complete(stat_tracker):
			return false
	return true
