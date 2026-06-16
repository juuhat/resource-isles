class_name QuestTrackerView
extends CanvasLayer

# The always-on quest tracker pinned to the right edge of the screen (World-of-Warcraft
# objective-tracker style): a compact, read-only list of the ACTIVE quests and their
# objective progress, so the player can track goals at a glance without opening the full
# Quest Log (QuestLogView, the T key). This is the at-a-glance HUD; QuestLogView is the
# detailed screen (descriptions, rewards, completed history).
#
# Live-updates off the same data the log uses: stat_tracker.stat_changed bumps objective
# bars, quest_manager.quest_completed drops the finished quest from the list. Quest state
# is global (not per-island), so this never needs refreshing on island switch.
#
# Built programmatically to match QuestLogView / ResourceBar.

const TITLE_COLOR := Color(1.0, 0.92, 0.6)
const OBJECTIVE_COLOR := Color(0.86, 0.86, 0.86)
const DONE_COLOR := Color(0.5, 0.85, 0.5)
const HEADER_COLOR := Color(0.62, 0.62, 0.62)

const PANEL_WIDTH := 248.0
# Sits below the resource bar (which occupies the top strip — see ResourceBar).
const TOP_MARGIN := 70.0
const SIDE_MARGIN := 16.0

var quest_manager: QuestManager
var panel: PanelContainer
var list: VBoxContainer


func setup(new_quest_manager: QuestManager) -> void:
	quest_manager = new_quest_manager
	quest_manager.quest_completed.connect(_on_quest_completed)
	quest_manager.stat_tracker.stat_changed.connect(_on_stat_changed)
	_rebuild()


func _ready() -> void:
	_build_ui()
	_rebuild()


func _build_ui() -> void:
	name = "QuestTrackerView"

	panel = PanelContainer.new()
	# Pin to the top-right corner and let it grow down/left to fit its content.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_top = TOP_MARGIN
	panel.offset_left = -SIDE_MARGIN
	panel.offset_right = -SIDE_MARGIN
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	# A passive HUD overlay — never eat clicks meant for the map behind it.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)

	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	margin.add_child(list)


func _rebuild() -> void:
	# _ready() runs during add_child(), before setup() assigns quest_manager.
	if list == null or quest_manager == null:
		return

	_clear_container(list)

	# Two tiers: the persistent main objective(s) up top, then the single current milestone.
	var main_quests := quest_manager.get_active_main_quests()
	var milestone := quest_manager.get_current_milestone()

	# Hide the whole tracker once everything's done — nothing to track.
	panel.visible = not main_quests.is_empty() or milestone != null

	if not main_quests.is_empty():
		list.add_child(_make_header("Main Objective"))
		for quest in main_quests:
			list.add_child(_make_entry(quest))

	if milestone != null:
		list.add_child(_make_header("Current Task"))
		list.add_child(_make_entry(milestone))


func _make_header(text: String) -> Label:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 12)
	header.modulate = HEADER_COLOR
	return header


func _make_entry(quest: Quest) -> Control:
	var entry := VBoxContainer.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = quest.title
	title.modulate = TITLE_COLOR
	title.add_theme_font_size_override("font_size", 14)
	entry.add_child(title)

	for objective in quest.objectives:
		entry.add_child(_make_objective_line(objective))

	return entry


func _make_objective_line(objective: Objective) -> Label:
	var current := objective.current(quest_manager.stat_tracker)
	var done := current >= objective.target

	var label := Label.new()
	label.text = "%s  %s  %d/%d" % [
		"✔" if done else "-",
		objective.description,
		current,
		objective.target,
	]
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = DONE_COLOR if done else OBJECTIVE_COLOR
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _on_stat_changed(_stat: int, _value: int) -> void:
	_rebuild()


func _on_quest_completed(_quest_id: int) -> void:
	_rebuild()


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
