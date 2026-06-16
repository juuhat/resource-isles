class_name QuestManager
extends RefCounted

# Holds the quest catalog plus which quests are complete, and drives the Quest Log. Quests
# complete by DISCOVERY: this watches a StatTracker and completes any quest once all of
# its objectives are met, then applies the quest's reward (unlock a building, grant a
# robot upgrade). Nothing is spent on completion — the building a reward unlocks still
# costs resources to place, so the player is never double-charged.
#
# There are no prerequisites; ordering falls out of the objectives (a stone objective
# can't finish until a quarry exists to mine it). Completion state is GLOBAL — the robot
# carries its knowledge between islands — so this manager is created once in main.gd and
# never reset on island switch.

signal quest_completed(quest_id: int)

const QuestCatalogScript := preload("res://scripts/quests/quest_catalog.gd")

enum State {
	ACTIVE,    # in progress
	COMPLETED, # all objectives met, reward granted
}

var quests: Array[Quest] = []
var stat_tracker: StatTracker
var _by_id: Dictionary = {}
var _completed: Dictionary = {}


func _init() -> void:
	quests = QuestCatalogScript.build_all()
	for quest in quests:
		_by_id[quest.id] = quest


func setup(new_stat_tracker: StatTracker) -> void:
	stat_tracker = new_stat_tracker
	stat_tracker.stat_changed.connect(_on_stat_changed)
	# Catch any quests already satisfied at startup.
	_complete_finished_quests()


func get_quest(quest_id: int) -> Quest:
	return _by_id.get(quest_id)


func is_completed(quest_id: int) -> bool:
	return _completed.has(quest_id)


func get_state(quest_id: int) -> int:
	return State.COMPLETED if is_completed(quest_id) else State.ACTIVE


func get_quests_in_state(state: int) -> Array[Quest]:
	var result: Array[Quest] = []
	for quest in quests:
		if get_state(quest.id) == state:
			result.append(quest)
	return result


# Whether a building type may be built. A building no quest rewards (e.g. the crashed
# spaceship) is always buildable; one a quest unlocks requires that quest's completion.
# Placement gating is not enforced yet — this is the hook for it.
func is_building_unlocked(building_type: int) -> bool:
	for quest in quests:
		if quest.reward.kind == GameTypes.RewardKind.UNLOCK_BUILDING \
				and quest.reward.building_type == building_type:
			return is_completed(quest.id)
	return true


func is_upgrade_active(robot_upgrade: int) -> bool:
	for quest in quests:
		if quest.reward.kind == GameTypes.RewardKind.ROBOT_UPGRADE \
				and quest.reward.robot_upgrade == robot_upgrade:
			return is_completed(quest.id)
	return false


func _on_stat_changed(_stat: int, _value: int) -> void:
	_complete_finished_quests()


func _complete_finished_quests() -> void:
	if stat_tracker == null:
		return

	for quest in quests:
		if is_completed(quest.id):
			continue
		if quest.is_complete(stat_tracker):
			_completed[quest.id] = true
			quest_completed.emit(quest.id)
