class_name QuestTarget
extends RefCounted

# Something in the world a quest points the player at: while the quest is active, the target glows
# (QuestHighlight). `kind` (GameTypes.QuestTargetKind) selects what `value` names: ITEM an ItemType,
# SHIP_PART a ShipPart. A quest lists its targets in Quest.highlights; most quests have none.

var kind: int
var value: int


func _init(new_kind: int, new_value: int) -> void:
	kind = new_kind
	value = new_value


# Convenience constructors keep the catalog readable.
static func item(item_type: int) -> QuestTarget:
	return QuestTarget.new(GameTypes.QuestTargetKind.ITEM, item_type)


static func ship_part(part: int) -> QuestTarget:
	return QuestTarget.new(GameTypes.QuestTargetKind.SHIP_PART, part)
