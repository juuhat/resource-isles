class_name Objective
extends RefCounted

# One goal within a quest: reach `target` on a cumulative play stat (GameTypes.Stat).
# Objectives are append-only progress — they track lifetime totals via the StatTracker,
# so spending resources never un-completes one. A quest is done when all its objectives
# are complete.

var description: String
var stat: int
var target: int


func _init(new_description: String, new_stat: int, new_target: int) -> void:
	description = new_description
	stat = new_stat
	target = new_target


func current(stat_tracker: StatTracker) -> int:
	# Clamped so a finished objective reads as exactly target, not an overshoot.
	return mini(stat_tracker.get_value(stat), target)


func is_complete(stat_tracker: StatTracker) -> bool:
	return stat_tracker.get_value(stat) >= target
