class_name QuestManager
extends RefCounted

# Holds the quest catalog plus which quests are complete, and drives the Quest Log. Quests
# complete by DISCOVERY: this watches a StatTracker and completes the current quest once
# all of its objectives are met, then applies its reward (unlock a building, grant a robot
# upgrade). Nothing is spent on completion — the building a reward unlocks still costs
# resources to place, so the player is never double-charged.
#
# The chain is LINEAR: catalog order is the order of play, and exactly ONE quest is active
# at a time (the first not-yet-completed quest). Every quest after it is LOCKED until its
# turn comes, so the player always has a single clear "do this next". Only the active quest
# can complete; finishing it advances the chain to the next.
#
# Completion state is GLOBAL — the robot carries its knowledge between islands — so this
# manager is created once in main.gd and never reset on island switch.

signal quest_completed(quest_id: int)

const QuestCatalogScript := preload("res://scripts/quests/quest_catalog.gd")

enum State {
	LOCKED,    # an earlier quest in the chain isn't done yet
	ACTIVE,    # the single quest currently in progress
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


# The single active MILESTONE: the first milestone in catalog order not yet completed. Null
# once the whole chain is finished. MAIN quests are not part of this linear chain.
func get_current_milestone() -> Quest:
	for quest in quests:
		if quest.kind == GameTypes.QuestKind.MILESTONE and not is_completed(quest.id):
			return quest
	return null


# The MAIN story quests still in progress (always active until completed — never locked).
func get_active_main_quests() -> Array[Quest]:
	var result: Array[Quest] = []
	for quest in quests:
		if quest.kind == GameTypes.QuestKind.MAIN and not is_completed(quest.id):
			result.append(quest)
	return result


func get_state(quest_id: int) -> int:
	if is_completed(quest_id):
		return State.COMPLETED
	# MAIN quests are always active; a MILESTONE is active only when it's the current one
	# in the linear chain, otherwise it's still locked behind earlier milestones.
	var quest: Quest = _by_id.get(quest_id)
	if quest != null and quest.kind == GameTypes.QuestKind.MAIN:
		return State.ACTIVE
	var current := get_current_milestone()
	return State.ACTIVE if current != null and current.id == quest_id else State.LOCKED


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
		for reward in quest.rewards:
			if reward.kind == GameTypes.RewardKind.UNLOCK_BUILDING \
					and reward.building_type == building_type:
				return is_completed(quest.id)
	return true


func is_upgrade_active(robot_upgrade: int) -> bool:
	for quest in quests:
		for reward in quest.rewards:
			if reward.kind == GameTypes.RewardKind.ROBOT_UPGRADE \
					and reward.robot_upgrade == robot_upgrade:
				return is_completed(quest.id)
	return false


# --- Save/load ---
# Completion is persisted EXPLICITLY rather than re-derived from saved stats: re-deriving
# would re-emit quest_completed for every already-finished quest, re-applying one-shot rewards
# (revealing world rings again, popping toasts). restore_completed sets the set directly and
# silently; the imperative reward effects (e.g. revealed_rings) are captured in WorldData.

func completed_to_dict() -> Dictionary:
	return _completed.duplicate()


func restore_completed(completed: Dictionary) -> void:
	_completed = {}
	for quest_id in completed:
		_completed[int(quest_id)] = true


func _on_stat_changed(_stat: int, _value: int) -> void:
	_complete_finished_quests()


func _complete_finished_quests() -> void:
	if stat_tracker == null:
		return

	# MAIN quests complete independently of the chain — check each on its own.
	for quest in get_active_main_quests():
		if quest.is_complete(stat_tracker):
			_completed[quest.id] = true
			quest_completed.emit(quest.id)

	# MILESTONE chain: only the current milestone can complete, then the next becomes
	# current. Loop so several thresholds satisfied at once (e.g. the debug grant, or an
	# already over-gathered stat) cascade through in order rather than stalling.
	while true:
		var current := get_current_milestone()
		if current == null or not current.is_complete(stat_tracker):
			break
		_completed[current.id] = true
		quest_completed.emit(current.id)
