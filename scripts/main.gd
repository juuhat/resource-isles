extends Node3D

const IslandGeneratorScript := preload("res://scripts/island/island_generator.gd")
const IslandRendererScript := preload("res://scripts/island/island_renderer.gd")
const BuildingMenuScript := preload("res://scripts/ui/building_menu.gd")
const BuildingInfoPanelScript := preload("res://scripts/ui/building_info_panel.gd")
const ResourceBarScript := preload("res://scripts/ui/resource_bar.gd")
const ResourceManagerScript := preload("res://scripts/resources/resource_manager.gd")
const ResourceNodeDatabaseScript := preload("res://scripts/resources/resource_node_database.gd")
const BuildingManagerScript := preload("res://scripts/buildings/building_manager.gd")
const ProductionManagerScript := preload("res://scripts/buildings/production_manager.gd")
const PowerManagerScript := preload("res://scripts/buildings/power_manager.gd")
const FloatingTextScript := preload("res://scripts/ui/floating_text.gd")
const ActionBarScript := preload("res://scripts/ui/action_bar.gd")
const PlayerUnitScript := preload("res://scripts/player/player_unit.gd")
const DogScript := preload("res://scripts/units/dog.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const WorldDataScript := preload("res://scripts/world/world_data.gd")
const WorldMapScript := preload("res://scripts/ui/world_map.gd")
const ScreenFadeScript := preload("res://scripts/ui/screen_fade.gd")
const StatTrackerScript := preload("res://scripts/quests/stat_tracker.gd")
const QuestManagerScript := preload("res://scripts/quests/quest_manager.gd")
const QuestLogViewScript := preload("res://scripts/ui/quest_log_view.gd")
const QuestTrackerViewScript := preload("res://scripts/ui/quest_tracker_view.gd")
const ToastScript := preload("res://scripts/ui/toast.gd")

const NO_BUILDING := -1
const HARVEST_INTERVAL := 3.0
const HARVEST_YIELD := 1

# Upper bound on how often the throttled crash-backstop autosave writes (see _process).
const AUTOSAVE_INTERVAL_SECONDS := 60.0

# Icons for the robot's command-bar actions.
const PICKAXE_ICON := preload("res://assets/icons/pickaxe.png")
const POWER_ICON := preload("res://assets/icons/power.png")

const PLACEMENT_SOUND := preload("res://assets/audio/sfx/building_placement.wav")

# Actions the selected robot can take on its current tile, dispatched from the ActionBar.
enum UnitAction {
	HARVEST,
	OPERATE,
}
# Pixels the cursor may travel between left press and release before it counts
# as a drag (pan) rather than a click.
const DRAG_THRESHOLD := 6.0

var generator := IslandGeneratorScript.new()
var renderer: IslandRenderer
var camera_rig: CameraRig
# The world seed. Default 1 => every player gets the identical archipelago. Each island's own
# seed is derived from this and its hex coord (see _island_seed), so a slot's layout is stable
# across runs. Randomize this per-run later for varied worlds. See docs/island-generation.md.
var seed_value := 1
var is_panning := false
var is_left_panning := false
var left_button_down := false
var left_press_position := Vector2.ZERO
var selected_building_type := NO_BUILDING
# Move mode: the player picked "Move" on a placed building. The original stays put until a
# valid new spot is clicked, so an aborted move never loses the building. selected_building_type
# carries the building's type meanwhile, driving the placement preview (free, no cost).
var is_moving_building := false
var moving_from_cell := Vector2i(-1, -1)
var world: WorldData
var current_island: IslandData
var building_manager: BuildingManager
var production_manager: ProductionManager
var power_manager: PowerManager
var resource_manager: ResourceManager
var resource_node_database: ResourceNodeDatabase
var resource_bar: ResourceBar
var building_menu: BuildingMenu
var building_info_panel: BuildingInfoPanel
var action_bar: ActionBar
var world_map: WorldMap
var screen_fade: ScreenFade
var player_unit: PlayerUnit
var dog: Dog
var stat_tracker: StatTracker
var quest_manager: QuestManager
var quest_log_view: QuestLogView
var quest_tracker_view: QuestTrackerView
var toast: Toast
var _placement_player: AudioStreamPlayer
var pending_action_cell := Vector2i(-1, -1)
var harvestable_cell := Vector2i(-1, -1)

# Throttled crash backstop: resource changes (harvesting, production, fuel) mark the game
# dirty, and _process flushes a save at most once per AUTOSAVE_INTERVAL_SECONDS. The discrete
# event saves (quest/building/island/quit) clear this, so the timer only ever covers progress
# made between those events — bounding worst-case crash loss to one interval.
var _autosave_dirty := false
var _autosave_accum := 0.0

var is_harvesting := false
var harvest_cell := Vector2i(-1, -1)
var harvest_resource_type := -1
var _harvest_accum := 0.0

# The robot is the tier-0 power source: while is_operating, it hand-powers the
# power-consuming building anchored at operate_cell (power_manager treats that cell as
# powered for free). operable_cell is the parked tile where the Operate action is offered.
var is_operating := false
var operate_cell := Vector2i(-1, -1)
var operable_cell := Vector2i(-1, -1)


func _ready() -> void:
	building_manager = BuildingManagerScript.new()
	resource_manager = ResourceManagerScript.new()
	resource_manager.resource_changed.connect(_on_resource_changed)
	resource_node_database = ResourceNodeDatabaseScript.new()
	building_manager.setup(resource_node_database)
	production_manager = ProductionManagerScript.new()
	production_manager.setup(building_manager, resource_manager)
	production_manager.produced.connect(_on_building_produced)
	production_manager.input_consumed.connect(_on_input_consumed)
	power_manager = PowerManagerScript.new()
	power_manager.setup(building_manager, resource_manager)
	power_manager.fuel_consumed.connect(_on_fuel_consumed)
	# Quests are the robot's own knowledge: one global log driven by cumulative lifetime
	# stats, not reset on island switch (unlike per-island buildings/resources).
	stat_tracker = StatTrackerScript.new()
	quest_manager = QuestManagerScript.new()
	quest_manager.setup(stat_tracker)

	renderer = IslandRendererScript.new()
	renderer.name = "IslandRenderer"
	renderer.setup(resource_node_database, building_manager)
	add_child(renderer)

	_placement_player = AudioStreamPlayer.new()
	_placement_player.stream = PLACEMENT_SOUND
	add_child(_placement_player)

	player_unit = PlayerUnitScript.new()
	player_unit.name = "PlayerUnit"
	player_unit.setup(renderer)
	player_unit.arrived.connect(_on_unit_arrived)
	player_unit.entered_cell.connect(_on_unit_entered_cell)
	add_child(player_unit)

	# Ambient dog companion that wanders the starter island on its own (testing).
	dog = DogScript.new()
	dog.name = "Dog"
	dog.setup(renderer)
	add_child(dog)

	camera_rig = CameraRigScript.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	_setup_lighting()

	world = WorldDataScript.new()
	# A save, if present, replaces the fresh world plus the global progression (stats/quests)
	# before the UI is built so world_map/building_menu wire up against the loaded state.
	var loaded := _try_load_game()
	_add_ui()
	# Persist on quit/suspend: intercept the close request so we can save before exiting, and
	# react to the mobile pause notification in _notification (the OS can kill a backgrounded
	# app without further warning).
	get_tree().set_auto_accept_quit(false)
	if loaded:
		_switch_to_island(world.current_coord)
	else:
		_enter_island(WorldData.CENTER)


# Save on the ways the game can end: a desktop window close, or a mobile app suspend (which
# may be the last callback before the OS reclaims the process). auto_accept_quit is disabled
# in _ready, so we must quit ourselves after saving on the close request.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_save_game()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			_save_game()


# Restore a saved game into the already-constructed managers, or return false to start fresh.
# Stats and quest completion are restored directly (silently) so loading doesn't re-trigger
# quest rewards; the world replaces the empty one built in _ready. Reference time rebases the
# islands' production/fuel timers onto this session's clock (see IslandData.to_dict).
#
# NOTE: the robot is intentionally re-spawned fresh on load (see _spawn_player_unit) — its
# tile, in-progress harvest/operate, and path are not persisted yet. Persist unit state here
# once the planned general Units class lands (multiple units, per-island positions).
func _try_load_game() -> bool:
	if not SaveManager.has_save():
		return false

	var payload := SaveManager.read()
	if payload.is_empty():
		return false

	var reference_time := Time.get_ticks_msec() / 1000.0
	world = WorldData.from_dict(payload.get("world", {}), reference_time)
	seed_value = int(payload.get("seed_value", seed_value))
	stat_tracker.restore(payload.get("stats", {}))
	quest_manager.restore_completed(payload.get("completed_quests", {}))
	print("Loaded save: %d island(s)" % world.island_count())
	return true


func _save_game() -> void:
	if world == null:
		return

	var reference_time := Time.get_ticks_msec() / 1000.0
	var payload := SaveManager.build_payload(
		world,
		stat_tracker.to_dict(),
		quest_manager.completed_to_dict(),
		seed_value,
		reference_time
	)
	SaveManager.write(payload)
	# Any save (event or timer) satisfies the throttle: clear the flag and restart the window.
	_autosave_dirty = false
	_autosave_accum = 0.0


# Flush the crash-backstop save once a dirty interval has elapsed. The accumulator only runs
# while dirty, so a quiet game never writes and worst-case loss stays within one interval.
func _update_autosave(delta: float) -> void:
	if not _autosave_dirty:
		return

	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL_SECONDS:
		_save_game()


func _process(delta: float) -> void:
	_update_autosave(delta)

	if current_island == null:
		return

	var current_time_seconds := Time.get_ticks_msec() / 1000.0
	var operated_cell := operate_cell if is_operating else Vector2i(-1, -1)
	power_manager.update(current_island, current_time_seconds, operated_cell)
	production_manager.update(current_island, current_time_seconds)

	if is_harvesting:
		_update_harvest(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_BRACKETRIGHT:
		_switch_to_adjacent_island(1)

	if key_event.keycode == KEY_BRACKETLEFT:
		_switch_to_adjacent_island(-1)

	if key_event.keycode == KEY_M:
		world_map.toggle()

	if key_event.keycode == KEY_T:
		quest_log_view.toggle()

	if key_event.keycode == KEY_SPACE:
		renderer.set_show_grid(not renderer.show_grid)

	if key_event.keycode == KEY_ESCAPE:
		if quest_log_view.is_open():
			quest_log_view.close()
		elif world_map.is_open:
			world_map.close()
		else:
			building_menu.clear_selection_and_close()
			_deselect_unit()

	# Debug cheats are confined to debug builds so they can't fire in a shipped game.
	if OS.is_debug_build():
		_handle_debug_key(key_event.keycode)


# DEBUG BUILD ONLY: testing cheats dispatched from _unhandled_input. P grants resources,
# Delete wipes the save and restarts; both are gated by OS.is_debug_build() at the call site.
func _handle_debug_key(keycode: int) -> void:
	# P: grant 1000 of every resource to the current island (per-island inventory) so building
	# costs can be exercised without grinding.
	if keycode == KEY_P:
		_debug_grant_resources()

	# Delete: wipe the save and reload the scene — _ready then finds no save and starts fresh.
	# (A plain delete wouldn't stick, since quitting and most actions re-save.)
	if keycode == KEY_DELETE:
		_debug_reset_save()


# DEBUG BUILD ONLY (P key, via _handle_debug_key). Adds 1000 of every GameTypes.ResourceType
# to the current island's inventory so building costs can be exercised without grinding, and
# records the same amount as gathered so the milestone quests trip and the quest log can be
# tested instantly. Iterates the enum so new resource types are covered automatically.
func _debug_grant_resources() -> void:
	for resource_type in GameTypes.ResourceType.values():
		resource_manager.add_amount(resource_type, 1000)
		stat_tracker.record_resource_gained(resource_type, 1000)


# DEBUG BUILD ONLY (Delete key, via _handle_debug_key). Deletes the save file and reloads the
# scene; _ready then finds no save and starts a brand-new game.
func _debug_reset_save() -> void:
	SaveManager.delete_save()
	get_tree().reload_current_scene()


func _on_quest_completed(quest_id: int) -> void:
	var quest := quest_manager.get_quest(quest_id)
	if quest == null:
		return
	toast.show_message("Quest complete: %s" % quest.title)
	for reward in quest.rewards:
		_apply_reward(reward)
	# A reward may have changed what the robot can do here (e.g. harvesting unlocked).
	_refresh_action_bar()
	# Completing a quest is a milestone the player would hate to lose to a crash — checkpoint it.
	_save_game()


# Building-unlock rewards need no action here — placement reads quest_manager state
# directly. Robot upgrades and world-map reveals change game state, so they're applied
# imperatively.
func _apply_reward(reward: QuestReward) -> void:
	match reward.kind:
		GameTypes.RewardKind.ROBOT_UPGRADE:
			match reward.robot_upgrade:
				GameTypes.RobotUpgrade.HARVESTING:
					pass # Capability gate read via quest_manager.is_upgrade_active(); no imperative change.
		GameTypes.RewardKind.REVEAL_WORLD_RINGS:
			world.reveal_additional_rings(reward.ring_count)
			world_map.refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var is_over_ui := get_viewport().gui_get_hovered_control() != null

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_rig.zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_rig.zoom_out()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and not is_over_ui:
			if selected_building_type != NO_BUILDING:
				building_menu.clear_selection()
			elif player_unit != null and player_unit.selected:
				_command_unit_to_hovered()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not is_over_ui:
				left_button_down = true
				is_left_panning = false
				left_press_position = event.position
			elif not event.pressed:
				if left_button_down and not is_left_panning:
					_handle_left_click()
				left_button_down = false
				is_left_panning = false

	if event is InputEventMouseMotion:
		if left_button_down and not is_left_panning \
				and event.position.distance_to(left_press_position) > DRAG_THRESHOLD:
			is_left_panning = true

		if is_panning or is_left_panning:
			camera_rig.pan(event.relative)

		var camera := camera_rig.get_camera()
		if camera != null:
			renderer.set_hovered_from_ray(
				camera.project_ray_origin(event.position),
				camera.project_ray_normal(event.position)
			)


func _handle_left_click() -> void:
	if is_moving_building:
		_try_finish_move()
		return

	if selected_building_type != NO_BUILDING:
		_try_place_selected_building()
		return

	if _try_select_unit():
		return

	_deselect_unit()
	_try_select_building()


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-40.0), 0.0)
	# Sun-cast shadows. The world is large (128-unit cells, camera 300-1200 units out), so the
	# shadow range is pushed well past the default 100 to cover the visible island. Biases are
	# kept low — large values peter-pan the shadow inside the caster at this geometry scale.
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 4000.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.0
	add_child(sun)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0901961, 0.435294, 0.658824)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	environment.ambient_light_energy = 0.5
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)


func _command_unit_to_hovered() -> bool:
	if player_unit == null or current_island == null:
		return false

	var cell := renderer.hovered_cell
	if cell == Vector2i(-1, -1) or not HexPathfinderScript.is_walkable(current_island, cell):
		return false

	pending_action_cell = cell

	if cell == player_unit.current_cell:
		_on_unit_arrived(cell)
		return true

	var path := HexPathfinderScript.find_path(current_island, player_unit.current_cell, cell)
	if path.is_empty():
		pending_action_cell = Vector2i(-1, -1)
		return false

	_stop_harvesting()
	_stop_operating()
	harvestable_cell = Vector2i(-1, -1)
	operable_cell = Vector2i(-1, -1)
	player_unit.follow_path(path)
	_refresh_action_bar()
	return true


# Collect any ground item the robot walks onto. Fires for every cell stepped through,
# so tools are picked up by passing over them — the intro to movement.
func _on_unit_entered_cell(cell: Vector2i) -> void:
	if current_island == null or not current_island.has_item(cell):
		return

	var item_type := current_island.take_item(cell)
	stat_tracker.add(GameTypes.Stat.TOOLS_COLLECTED, 1)
	_spawn_floating_text(
		renderer.get_cell_center(cell),
		"+%s" % GameTypes.item_display_name(item_type),
		Color(1.0, 0.95, 0.7)
	)
	renderer.refresh()


func _on_unit_arrived(cell: Vector2i) -> void:
	if cell != pending_action_cell:
		return

	pending_action_cell = Vector2i(-1, -1)
	harvestable_cell = cell if current_island.get_resource_node_type(cell) != -1 else Vector2i(-1, -1)
	operable_cell = cell if _building_consumes_power(cell) else Vector2i(-1, -1)
	_refresh_action_bar()


# Rebuild the robot's command bar from its current context: the bar shows only while a
# parked, selected robot has at least one applicable action. main.gd owns what each
# action means; the bar (action_bar.gd) is just the view. To add a robot action, append
# another descriptor here and handle its id in _on_action_pressed.
func _refresh_action_bar() -> void:
	if action_bar == null:
		return

	var actions: Array = []
	if (
		player_unit != null
		and player_unit.selected
		and not player_unit.is_moving()
		and current_island != null
	):
		var harvest := _harvest_action()
		if not harvest.is_empty():
			actions.append(harvest)
		var operate := _operate_action()
		if not operate.is_empty():
			actions.append(operate)

	action_bar.set_actions(actions)
	action_bar.set_selected(player_unit != null and player_unit.selected)


# The portrait in the command bar is a second way to select the robot (besides clicking it
# on the map). Selecting refreshes the bar so its actions for the current tile appear.
func _on_portrait_select_requested() -> void:
	if player_unit == null or player_unit.current_cell == Vector2i(-1, -1):
		return

	player_unit.set_selected(true)
	_refresh_action_bar()


func _harvest_action() -> Dictionary:
	# Harvesting is locked until the robot recovers its tools (the "Hello World" quest).
	if not quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.HARVESTING):
		return {}

	if harvestable_cell == Vector2i(-1, -1) or player_unit.current_cell != harvestable_cell:
		return {}

	var resource_node_type := current_island.get_resource_node_type(harvestable_cell)
	if resource_node_type == -1:
		return {}

	var definition := resource_node_database.get_definition(resource_node_type)
	var node_name := definition.display_name if definition != null else ""
	var label := ""
	if is_harvesting:
		label = "Cancel harvesting" if node_name.is_empty() else "Cancel (%s)" % node_name
	else:
		label = "Harvest" if node_name.is_empty() else "Harvest %s" % node_name

	return {id = UnitAction.HARVEST, icon = PICKAXE_ICON, label = label, active = is_harvesting}


func _operate_action() -> Dictionary:
	if operable_cell == Vector2i(-1, -1) or player_unit.current_cell != operable_cell:
		return {}

	if not _building_consumes_power(operable_cell):
		return {}

	var definition := building_manager.get_definition(current_island.get_building_type(operable_cell))
	var building_name := definition.display_name if definition != null else ""
	var label := ""
	if is_operating:
		label = "Cancel operating" if building_name.is_empty() else "Cancel (%s)" % building_name
	else:
		label = "Operate" if building_name.is_empty() else "Operate %s" % building_name

	return {id = UnitAction.OPERATE, icon = POWER_ICON, label = label, active = is_operating}


# True when the cell holds a building that draws power, so the robot can hand-power it
# with the Operate verb (the tier-0 power source — see is_operating / power_manager.gd).
func _building_consumes_power(cell: Vector2i) -> bool:
	var building_type := current_island.get_building_type(cell)
	if building_type == -1:
		return false

	var definition := building_manager.get_definition(building_type)
	return definition != null and definition.power_consumed > 0


func _on_action_pressed(action_id: int) -> void:
	match action_id:
		UnitAction.HARVEST:
			_on_harvest_pressed()
		UnitAction.OPERATE:
			_on_operate_pressed()


func _on_harvest_pressed() -> void:
	if is_harvesting:
		_stop_harvesting()
		_refresh_action_bar()
		return

	if harvestable_cell == Vector2i(-1, -1):
		return

	var resource_node_type := current_island.get_resource_node_type(harvestable_cell)
	if resource_node_type == -1:
		return

	var definition := resource_node_database.get_definition(resource_node_type)
	if definition == null:
		return

	is_harvesting = true
	harvest_cell = harvestable_cell
	harvest_resource_type = definition.extracted_resource_type
	_harvest_accum = 0.0
	_refresh_action_bar()


func _stop_harvesting() -> void:
	if not is_harvesting:
		return

	is_harvesting = false
	harvest_cell = Vector2i(-1, -1)
	harvest_resource_type = -1
	_harvest_accum = 0.0


func _on_operate_pressed() -> void:
	if is_operating:
		_stop_operating()
		_refresh_action_bar()
		return

	if operable_cell == Vector2i(-1, -1):
		return

	if not _building_consumes_power(operable_cell):
		return

	is_operating = true
	operate_cell = current_island.get_building_anchor_cell(operable_cell)
	_refresh_action_bar()


# Hand the building back: it loses the robot's power the moment the robot stops
# operating it (or is sent elsewhere / the island is left). power_manager re-allocates
# from the island's generators on the next tick.
func _stop_operating() -> void:
	if not is_operating:
		return

	is_operating = false
	operate_cell = Vector2i(-1, -1)


func _update_harvest(delta: float) -> void:
	# Stop if the robot is no longer parked on the node it was harvesting.
	if (
		player_unit == null
		or player_unit.is_moving()
		or player_unit.current_cell != harvest_cell
		or current_island == null
		or current_island.get_resource_node_type(harvest_cell) == -1
	):
		_stop_harvesting()
		_refresh_action_bar()
		return

	_harvest_accum += delta
	while _harvest_accum >= HARVEST_INTERVAL:
		_harvest_accum -= HARVEST_INTERVAL
		resource_manager.add_amount(harvest_resource_type, HARVEST_YIELD)
		stat_tracker.record_resource_gained(harvest_resource_type, HARVEST_YIELD)
		_spawn_resource_floating_text(
			renderer.get_cell_center(harvest_cell),
			harvest_resource_type,
			"+%d" % HARVEST_YIELD
		)


func _on_building_produced(anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	stat_tracker.record_resource_gained(resource_type, amount)
	_spawn_resource_floating_text(
		renderer.get_cell_center(anchor_cell),
		resource_type,
		"+%d" % amount,
		16
	)


func _on_fuel_consumed(anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	_spawn_resource_floating_text(
		renderer.get_cell_center(anchor_cell),
		resource_type,
		"-%d" % amount,
		16
	)


func _on_input_consumed(anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	_spawn_resource_floating_text(
		renderer.get_cell_center(anchor_cell),
		resource_type,
		"-%d" % amount,
		16
	)


func _spawn_floating_text(
	world_position: Vector3,
	text: String,
	color: Color,
	font_size := 22,
	icon: Texture2D = null
) -> void:
	var floating := FloatingTextScript.new()
	floating.text = text
	floating.color = color
	floating.font_size = font_size
	floating.icon = icon
	floating.position = world_position
	add_child(floating)


# Floating popup for a resource gain/loss: shows the resource icon next to a signed amount
# (e.g. icon + "+3"), coloured per the central ResourceDatabase, instead of spelling out
# the resource name.
func _spawn_resource_floating_text(
	world_position: Vector3, resource_type: int, signed_text: String, font_size := 22
) -> void:
	var definition := ResourceDatabase.get_definition(resource_type)
	var icon: Texture2D = definition.icon if definition != null else null
	_spawn_floating_text(world_position, signed_text, _resource_color(resource_type), font_size, icon)


func _resource_color(resource_type: int) -> Color:
	var definition := ResourceDatabase.get_definition(resource_type)
	return definition.color if definition != null else Color.WHITE


func _try_select_unit() -> bool:
	if player_unit == null or player_unit.current_cell == Vector2i(-1, -1):
		return false

	if renderer.hovered_cell != player_unit.current_cell:
		return false

	player_unit.set_selected(true)
	_refresh_action_bar()
	return true


func _deselect_unit() -> void:
	if player_unit != null:
		player_unit.set_selected(false)
	_refresh_action_bar()


func _try_select_building() -> bool:
	var building_type := renderer.get_hovered_building_type()
	if building_type == -1:
		return false

	building_info_panel.show_building(building_type, renderer.hovered_cell, current_island)
	return true


func _try_place_selected_building() -> bool:
	# Defensive gate: the menu already hides locked / worldgen-only buildings, but never
	# let a stale selection place one anyway.
	var definition := building_manager.get_definition(selected_building_type)
	if definition == null or not definition.player_buildable:
		return false
	if not quest_manager.is_building_unlocked(selected_building_type):
		return false

	var cost := _get_building_cost(selected_building_type)
	if not resource_manager.can_afford(cost):
		return false

	if not renderer.try_place_hovered_building(selected_building_type):
		return false

	resource_manager.spend(cost)
	stat_tracker.record_building_built(selected_building_type)
	if _placement_player != null:
		_placement_player.play()
	# Placing a building is a deliberate, resource-spending action — checkpoint it. (If it also
	# completed a quest, record_building_built already saved via _on_quest_completed; the extra
	# write is cheap and keeps placement a save point in its own right.)
	_save_game()
	return true


func _get_building_cost(building_type: int) -> Dictionary:
	return building_manager.get_cost(building_type)


# Enter the island at a world-map slot: travel there if it exists, otherwise
# generate it first. Used both for the starter at startup and for slots clicked on
# the world map.
func _enter_island(coord: Vector2i) -> void:
	if not world.has_island(coord):
		_generate_island_at(coord)

	_switch_to_island(coord)


func _generate_island_at(coord: Vector2i) -> void:
	# The center slot (World 1) is the crash site with the starting wreck (STARTER biome). It
	# begins with no resources — the opening loop is scavenging the first wood by hand (see
	# docs/progression-and-power.md). Other slots are frontier biomes (currently STONE) and arrive
	# with just enough to establish their first dock. The biome and per-island seed are both
	# derived from the coord, so a slot's layout is intrinsic to where it is.
	var is_starter := coord == WorldData.CENTER
	var profile := IslandProfiles.get_profile(IslandProfiles.biome_for_coord(coord))
	var island := generator.generate(profile, _island_seed(coord), building_manager)
	if not is_starter:
		_stock_bootstrap_supplies(island)
		# Discovering any island beyond the starter is the "Rescue the Dog" beat — sailing
		# out to a new island is what reunites the robot with its pet (see QuestCatalog).
		stat_tracker.add(GameTypes.Stat.ISLANDS_REACHED, 1)
	world.add_island(coord, island)


# Per-slot seed: combines the world seed with the hex coord so each island is distinct yet
# stable across runs (docs/island-generation.md).
func _island_seed(coord: Vector2i) -> int:
	return hash(Vector3i(coord.x, coord.y, seed_value))


# A newly reached island arrives with exactly enough to build its first dock, which
# then lets it be the endpoint of a trade route — so a resource-barren island is
# never a soft-lock. There is no manual cargo step; all other goods come via trade
# routes once the dock exists (see docs/island-unlocks.md).
func _stock_bootstrap_supplies(island: IslandData) -> void:
	var dock_cost := building_manager.get_cost(GameTypes.BuildingType.DOCK)
	for resource_type in dock_cost.keys():
		island.inventory.add_amount(resource_type, dock_cost[resource_type])


# Cycle through already-discovered islands in discovery order (wrapping). Islands
# persist, so a revisited island keeps the buildings placed on it. No-op until a
# second island exists.
func _switch_to_adjacent_island(direction: int) -> void:
	var coords := world.ordered_coords()
	if coords.size() <= 1:
		return

	var index := coords.find(world.current_coord)
	var next_coord: Vector2i = coords[(index + direction + coords.size()) % coords.size()]
	_switch_to_island(next_coord)


func _switch_to_island(coord: Vector2i) -> void:
	# Release the wheel on the island we are leaving, while it is still current,
	# so its manual generator is not left flagged as running.
	_stop_operating()

	if not world.set_current(coord):
		return

	current_island = world.get_current()
	resource_manager.set_inventory(current_island.inventory)
	building_info_panel.hide_info()
	renderer.render(current_island)
	_spawn_player_unit()
	_spawn_dog()
	resource_bar.refresh()
	world_map.refresh()
	_apply_selected_building()
	camera_rig.center_on(renderer.get_map_center())

	# Autosave at each settled island state — the natural checkpoint, and it also writes the
	# initial save for a brand-new game (the starter island is entered through here too).
	_save_game()


# Enter an island slot chosen on the world map, with a fade transition. Travels to
# an existing island or discovers (generates) a new one at that slot.
func _on_world_map_slot_activated(coord: Vector2i) -> void:
	world_map.close()
	if coord == world.current_coord and world.has_island(coord):
		return

	screen_fade.transition(_enter_island.bind(coord))


func _spawn_player_unit() -> void:
	if player_unit == null:
		return

	_stop_harvesting()
	_stop_operating()
	pending_action_cell = Vector2i(-1, -1)
	harvestable_cell = Vector2i(-1, -1)
	operable_cell = Vector2i(-1, -1)
	player_unit.place_at(_find_unit_spawn_cell())
	_refresh_action_bar()


# The dog is a testing-only ambient wanderer confined to the starter island; it sits idle
# (hidden) on every other island for now.
func _spawn_dog() -> void:
	if dog == null:
		return

	if world.current_coord == WorldData.CENTER:
		dog.begin(current_island)
	else:
		dog.halt()


func _find_unit_spawn_cell() -> Vector2i:
	var crashed_spaceship_cell := _find_crashed_spaceship_cell()
	if crashed_spaceship_cell != Vector2i(-1, -1):
		for neighbor in HexGridScript.neighbors(crashed_spaceship_cell):
			if (
				HexPathfinderScript.is_walkable(current_island, neighbor)
				and not current_island.has_building(neighbor)
				and not current_island.has_item(neighbor)
			):
				return neighbor

	for y in range(current_island.height):
		for x in range(current_island.width):
			var cell := Vector2i(x, y)
			if (
				HexPathfinderScript.is_walkable(current_island, cell)
				and not current_island.has_building(cell)
				and not current_island.has_resource(cell)
				and not current_island.has_item(cell)
			):
				return cell

	return Vector2i.ZERO


func _find_crashed_spaceship_cell() -> Vector2i:
	for cell in current_island.buildings.keys():
		if current_island.buildings[cell].type == GameTypes.BuildingType.CRASHED_SPACESHIP:
			return cell

	return Vector2i(-1, -1)


func _select_no_building() -> void:
	# Also the cancel path for an in-progress move (right-click / picking another tool routes
	# here via the build menu); the original building was never removed, so it just stays.
	is_moving_building = false
	moving_from_cell = Vector2i(-1, -1)
	selected_building_type = NO_BUILDING
	_apply_selected_building()


func _select_building(building_type: int) -> void:
	# Choosing a building from the menu abandons any move in progress.
	is_moving_building = false
	moving_from_cell = Vector2i(-1, -1)
	selected_building_type = building_type
	_apply_selected_building()


# Panel "Move": keep the building where it is and enter a free placement preview for its type.
# The next valid left-click drops it at the new cell and removes the original (_try_finish_move).
func _on_building_move_requested(building_type: int, anchor_cell: Vector2i, island: IslandData) -> void:
	if island == null or island != current_island:
		return

	is_moving_building = true
	moving_from_cell = anchor_cell
	selected_building_type = building_type
	_apply_selected_building()


func _try_finish_move() -> void:
	# Place at the hovered cell first; only on success do we remove the original, so an
	# illegal target (occupied / wrong terrain) leaves the building untouched.
	if not renderer.try_place_hovered_building(selected_building_type):
		return

	renderer.remove_building(moving_from_cell)
	if _placement_player != null:
		_placement_player.play()

	is_moving_building = false
	moving_from_cell = Vector2i(-1, -1)
	building_menu.clear_selection()
	_save_game()


# Panel "Delete": scrap the building outright. The power/production managers recompute from the
# remaining buildings on the next _process tick, so no manual refresh is needed here.
func _on_building_delete_requested(anchor_cell: Vector2i, island: IslandData) -> void:
	if island == null or island != current_island:
		return

	if renderer.remove_building(anchor_cell):
		_save_game()


func _apply_selected_building() -> void:
	if selected_building_type == NO_BUILDING:
		renderer.set_placement_preview(false)
		return

	renderer.set_placement_preview(
		true,
		selected_building_type,
		# Moving is free — never show the moved building's preview as unaffordable.
		is_moving_building or resource_manager.can_afford(_get_building_cost(selected_building_type))
	)


func _on_resource_changed(_resource_type: int, _amount: int) -> void:
	_apply_selected_building()
	# Resources moved (harvest, production, fuel, spend) — arm the throttled backstop save.
	_autosave_dirty = true


func _add_ui() -> void:
	resource_bar = ResourceBarScript.new()
	add_child(resource_bar)
	resource_bar.setup(resource_manager, power_manager, stat_tracker)

	building_info_panel = BuildingInfoPanelScript.new()
	building_info_panel.setup(building_manager)
	building_info_panel.move_requested.connect(_on_building_move_requested)
	building_info_panel.delete_requested.connect(_on_building_delete_requested)
	add_child(building_info_panel)

	building_menu = BuildingMenuScript.new()
	building_menu.setup(building_manager, quest_manager)
	building_menu.building_selected.connect(_select_building)
	building_menu.selection_cleared.connect(_select_no_building)
	add_child(building_menu)

	action_bar = ActionBarScript.new()
	action_bar.action_pressed.connect(_on_action_pressed)
	action_bar.select_requested.connect(_on_portrait_select_requested)
	add_child(action_bar)

	world_map = WorldMapScript.new()
	world_map.setup(world)
	world_map.slot_activated.connect(_on_world_map_slot_activated)
	add_child(world_map)

	quest_log_view = QuestLogViewScript.new()
	quest_log_view.setup(quest_manager)
	add_child(quest_log_view)

	quest_tracker_view = QuestTrackerViewScript.new()
	add_child(quest_tracker_view)
	quest_tracker_view.setup(quest_manager)

	toast = ToastScript.new()
	add_child(toast)
	# Reward the moment of completion without making the player open the quest log.
	quest_manager.quest_completed.connect(_on_quest_completed)

	screen_fade = ScreenFadeScript.new()
	add_child(screen_fade)
