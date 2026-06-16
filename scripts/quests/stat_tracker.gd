class_name StatTracker
extends RefCounted

# Cumulative, append-only play stats: total wood ever gathered, buildings ever built,
# etc. These are LIFETIME totals, not current stock — they only ever go up, so they
# never drop back below a milestone when you spend resources. The QuestManager subscribes
# to stat_changed to auto-complete milestone quests.
#
# Like quest completion state, stats are GLOBAL (the robot's lifetime record), not
# per-island.

signal stat_changed(stat: int, value: int)

var _values: Dictionary = {}


func get_value(stat: int) -> int:
	return _values.get(stat, 0)


func add(stat: int, amount: int) -> void:
	if amount <= 0:
		return
	_values[stat] = get_value(stat) + amount
	stat_changed.emit(stat, _values[stat])


# Records a resource gain against its cumulative "<resource> gathered" stat. Only
# positive gains count (gathering/production); spending does not decrement a lifetime
# total. Resources without a gathered stat (none yet) are ignored.
func record_resource_gained(resource_type: int, amount: int) -> void:
	var stat := _resource_gathered_stat(resource_type)
	if stat != -1:
		add(stat, amount)


func _resource_gathered_stat(resource_type: int) -> int:
	match resource_type:
		GameTypes.ResourceType.WOOD:
			return GameTypes.Stat.WOOD_GATHERED
		GameTypes.ResourceType.STONE:
			return GameTypes.Stat.STONE_GATHERED
		GameTypes.ResourceType.PLANKS:
			return GameTypes.Stat.PLANKS_GATHERED
		_:
			return -1
