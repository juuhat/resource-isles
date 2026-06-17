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
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")
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
var camera_pivot: Node3D
var camera: Camera3D
var seed_value := 1
var zoom_step := 1.1
# Camera orbits a pivot at a fixed pitch; zoom changes the pivot-to-camera distance.
var camera_distance := 1800.0
var camera_pitch_degrees := 55.0
var min_distance := 500.0
var max_distance := 6000.0
var is_panning := false
var is_left_panning := false
var left_button_down := false
var left_press_position := Vector2.ZERO
var selected_building_type := NO_BUILDING
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
var stat_tracker: StatTracker
var quest_manager: QuestManager
var quest_log_view: QuestLogView
var quest_tracker_view: QuestTrackerView
var toast: Toast
var _placement_player: AudioStreamPlayer
var pending_action_cell := Vector2i(-1, -1)
var harvestable_cell := Vector2i(-1, -1)

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

	_setup_camera_and_light()

	world = WorldDataScript.new()
	_add_ui()
	_enter_island(WorldData.CENTER)


func _process(delta: float) -> void:
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

	# Temporary stand-in for a boat-tier unlock: reveal one more ring on the map.
	if key_event.keycode == KEY_EQUAL:
		world.reveal_additional_rings(1)
		world_map.refresh()

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

	# DEBUG CHEAT (P): grant 1000 of every resource to the current island for
	# testing. Resources are per-island, so this fills the active island's
	# inventory only. Remove this block before shipping.
	if key_event.keycode == KEY_P:
		_debug_grant_resources()


# DEBUG/TESTING ONLY — bound to the P key (see _unhandled_input). Adds 1000 of
# every GameTypes.ResourceType to the current island's inventory so building costs
# can be exercised without grinding, and records the same amount as gathered so the
# milestone quests trip and the quest log can be tested instantly. Iterates the
# enum so new resource types are covered automatically. Not part of normal gameplay;
# delete before release.
func _debug_grant_resources() -> void:
	for resource_type in GameTypes.ResourceType.values():
		resource_manager.add_amount(resource_type, 1000)
		stat_tracker.record_resource_gained(resource_type, 1000)


func _on_quest_completed(quest_id: int) -> void:
	var quest := quest_manager.get_quest(quest_id)
	if quest == null:
		return
	toast.show_message("Quest complete: %s" % quest.title)
	for reward in quest.rewards:
		_apply_reward(reward)
	# A reward may have changed what the robot can do here (e.g. harvesting unlocked).
	_refresh_action_bar()


# Building-unlock rewards need no action here — placement reads quest_manager state
# directly. Robot upgrades change the robot, so they're applied imperatively.
func _apply_reward(reward: QuestReward) -> void:
	if reward.kind != GameTypes.RewardKind.ROBOT_UPGRADE:
		return

	match reward.robot_upgrade:
		GameTypes.RobotUpgrade.HARVESTING:
			pass # Capability gate read via quest_manager.is_upgrade_active(); no imperative change.


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var is_over_ui := get_viewport().gui_get_hovered_control() != null

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_distance(camera_distance / zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_distance(camera_distance * zoom_step)
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
			_pan_camera(event.relative)

		if camera != null:
			renderer.set_hovered_from_ray(
				camera.project_ray_origin(event.position),
				camera.project_ray_normal(event.position)
			)


func _handle_left_click() -> void:
	if selected_building_type != NO_BUILDING:
		_try_place_selected_building()
		return

	if _try_select_unit():
		return

	_deselect_unit()
	_try_select_building()


func _setup_camera_and_light() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.far = 20000.0
	camera.current = true
	camera_pivot.add_child(camera)
	_update_camera()

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-40.0), 0.0)
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


# Position the camera at the current distance/pitch behind the pivot and look at it.
func _update_camera() -> void:
	if camera == null:
		return
	var pitch := deg_to_rad(camera_pitch_degrees)
	camera.position = Vector3(0.0, sin(pitch) * camera_distance, cos(pitch) * camera_distance)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)


func _set_distance(new_distance: float) -> void:
	camera_distance = clampf(new_distance, min_distance, max_distance)
	_update_camera()


# Drag-pan: slide the pivot across the XZ ground. Scaled by distance so the world keeps
# pace with the cursor regardless of zoom.
func _pan_camera(screen_delta: Vector2) -> void:
	var pan_scale := camera_distance * 0.0016
	camera_pivot.position += Vector3(-screen_delta.x, 0.0, -screen_delta.y) * pan_scale


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
		_spawn_floating_text(
			renderer.get_cell_center(harvest_cell),
			"+%d %s" % [HARVEST_YIELD, ResourceManager.get_display_name_for_type(harvest_resource_type)],
			_resource_color(harvest_resource_type)
		)


func _on_building_produced(anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	stat_tracker.record_resource_gained(resource_type, amount)
	_spawn_floating_text(
		renderer.get_cell_center(anchor_cell),
		"+%d %s" % [amount, ResourceManager.get_display_name_for_type(resource_type)],
		_resource_color(resource_type),
		16
	)


func _on_fuel_consumed(anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	_spawn_floating_text(
		renderer.get_cell_center(anchor_cell),
		"-%d %s" % [amount, ResourceManager.get_display_name_for_type(resource_type)],
		_resource_color(resource_type),
		16
	)


func _on_input_consumed(anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	_spawn_floating_text(
		renderer.get_cell_center(anchor_cell),
		"-%d %s" % [amount, ResourceManager.get_display_name_for_type(resource_type)],
		_resource_color(resource_type),
		16
	)


func _spawn_floating_text(world_position: Vector3, text: String, color: Color, font_size := 22) -> void:
	var floating := FloatingTextScript.new()
	floating.text = text
	floating.color = color
	floating.font_size = font_size
	floating.position = world_position
	add_child(floating)


func _resource_color(resource_type: int) -> Color:
	match resource_type:
		GameTypes.ResourceType.WOOD:
			return Color("#d79a4f")
		GameTypes.ResourceType.STONE:
			return Color("#cfcfd6")
		GameTypes.ResourceType.PLANKS:
			return Color("#e8c07a")
		_:
			return Color.WHITE


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
	# The center slot (World 1) is the crash site with the starting wreck. It begins
	# with no resources — the opening loop is scavenging the first wood by hand (see
	# docs/progression-and-power.md). Other slots arrive with just enough to establish
	# their first dock.
	var is_starter := coord == WorldData.CENTER
	var island := generator.generate_starter_island(seed_value, building_manager, is_starter)
	seed_value += 1
	if not is_starter:
		_stock_bootstrap_supplies(island)
		# Discovering any island beyond the starter is the "Rescue the Dog" beat — sailing
		# out to a new island is what reunites the robot with its pet (see QuestCatalog).
		stat_tracker.add(GameTypes.Stat.ISLANDS_REACHED, 1)
	world.add_island(coord, island)


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
	resource_bar.refresh()
	world_map.refresh()
	_apply_selected_building()
	_center_camera(current_island)


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


func _center_camera(_island: IslandData) -> void:
	camera_pivot.position = renderer.get_map_center()
	_set_distance(renderer.get_map_radius() * 2.2)


func _select_no_building() -> void:
	selected_building_type = NO_BUILDING
	_apply_selected_building()


func _select_building(building_type: int) -> void:
	selected_building_type = building_type
	_apply_selected_building()


func _apply_selected_building() -> void:
	if selected_building_type == NO_BUILDING:
		renderer.set_placement_preview(false)
		return

	renderer.set_placement_preview(
		true,
		selected_building_type,
		resource_manager.can_afford(_get_building_cost(selected_building_type))
	)


func _on_resource_changed(_resource_type: int, _amount: int) -> void:
	_apply_selected_building()


func _add_ui() -> void:
	resource_bar = ResourceBarScript.new()
	add_child(resource_bar)
	resource_bar.setup(resource_manager, power_manager)

	building_info_panel = BuildingInfoPanelScript.new()
	building_info_panel.setup(building_manager)
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
