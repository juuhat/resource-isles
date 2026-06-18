class_name QuestReward
extends RefCounted

# What a quest grants on completion. `kind` (GameTypes.RewardKind) selects which payload
# applies: UNLOCK_BUILDING uses `building_type`, ROBOT_UPGRADE uses `robot_upgrade`,
# REVEAL_WORLD_RINGS uses `ring_count`. `summary` is the human-readable line shown in the
# Quest Log (e.g. "Unlocks the Dock").

var kind: int
var building_type: int
var robot_upgrade: int
var ring_count: int
var summary: String


func _init(
	new_kind: int,
	new_summary: String,
	new_building_type: int = -1,
	new_robot_upgrade: int = -1,
	new_ring_count: int = 0
) -> void:
	kind = new_kind
	summary = new_summary
	building_type = new_building_type
	robot_upgrade = new_robot_upgrade
	ring_count = new_ring_count


# Convenience constructors keep the catalog readable.
static func unlock_building(building_type: int, summary: String) -> QuestReward:
	return QuestReward.new(GameTypes.RewardKind.UNLOCK_BUILDING, summary, building_type)


static func robot_upgrade_reward(robot_upgrade: int, summary: String) -> QuestReward:
	return QuestReward.new(GameTypes.RewardKind.ROBOT_UPGRADE, summary, -1, robot_upgrade)


static func reveal_world_rings(ring_count: int, summary: String) -> QuestReward:
	return QuestReward.new(GameTypes.RewardKind.REVEAL_WORLD_RINGS, summary, -1, -1, ring_count)
