class_name QuestLogView
extends CanvasLayer

# The robot's Quest Log: a read-only list of quests. Quests complete by playing (see
# QuestManager), so this screen doesn't let you research anything — it reflects what
# you're working on. Each quest shows its title, description, objectives (with a progress
# bar each), and reward. Entries are grouped into "Active" and "Completed". The
# moment-of-completion reward is a Toast (see main.gd), not this screen.
#
# Built programmatically to match BuildingMenu. Toggled with the T key (see main.gd).

const ACTIVE_COLOR := Color(1.0, 0.92, 0.6)
const COMPLETED_COLOR := Color(0.5, 0.85, 0.5)
const MUTED_COLOR := Color(0.62, 0.62, 0.62)

var quest_manager: QuestManager
var panel: PanelContainer
var list: VBoxContainer


func setup(new_quest_manager: QuestManager) -> void:
	quest_manager = new_quest_manager
	quest_manager.quest_completed.connect(_on_quest_completed)


func _ready() -> void:
	_build_ui()


func toggle() -> void:
	if panel == null:
		return
	panel.visible = not panel.visible
	if panel.visible:
		_rebuild()


func close() -> void:
	if panel != null:
		panel.visible = false


func is_open() -> bool:
	return panel != null and panel.visible


func _build_ui() -> void:
	name = "QuestLogView"

	panel = PanelContainer.new()
	panel.visible = false
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280.0
	panel.offset_top = -240.0
	panel.offset_right = 280.0
	panel.offset_bottom = 240.0
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)

	var title := Label.new()
	title.text = "Quest Log"
	body.add_child(title)

	var hint := Label.new()
	hint.text = "Completed by playing — no need to research anything."
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = MUTED_COLOR
	body.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	body.add_child(close_button)


func _rebuild() -> void:
	if list == null:
		return

	_clear_container(list)
	_add_section("Active", QuestManager.State.ACTIVE)
	_add_section("Completed", QuestManager.State.COMPLETED)


func _add_section(title: String, state: int) -> void:
	var quests := quest_manager.get_quests_in_state(state)
	if quests.is_empty():
		return

	var header := Label.new()
	header.text = title
	list.add_child(header)

	for quest in quests:
		list.add_child(_make_quest_entry(quest, state))


func _make_quest_entry(quest: Quest, state: int) -> Control:
	var entry := VBoxContainer.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_theme_constant_override("separation", 3)
	entry.modulate = COMPLETED_COLOR if state == QuestManager.State.COMPLETED else ACTIVE_COLOR

	var title_label := Label.new()
	title_label.text = quest.title
	entry.add_child(title_label)

	var desc := Label.new()
	desc.text = quest.description
	desc.add_theme_font_size_override("font_size", 12)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(desc)

	if state == QuestManager.State.COMPLETED:
		entry.add_child(_small_label("Completed"))
	else:
		for objective in quest.objectives:
			_add_objective(entry, objective)

	for reward in quest.rewards:
		entry.add_child(_small_label("Reward: %s" % reward.summary))
	return entry


func _add_objective(entry: VBoxContainer, objective: Objective) -> void:
	var current := objective.current(quest_manager.stat_tracker)

	var bar := ProgressBar.new()
	bar.max_value = maxi(1, objective.target)
	bar.value = current
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	entry.add_child(bar)

	entry.add_child(_small_label("%s %d/%d" % [objective.description, current, objective.target]))


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	return label


func _on_quest_completed(_quest_id: int) -> void:
	if is_open():
		_rebuild()


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
