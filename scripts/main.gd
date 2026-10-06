class_name Game
extends Node3D

const WorldViewScript := preload("res://scripts/world/world_view.gd")
const BuildingMenuScript := preload("res://scripts/ui/building_menu.gd")
const BuildingInfoPanelScript := preload("res://scripts/ui/building_info_panel.gd")
const ResourceBarScript := preload("res://scripts/ui/resource_bar.gd")
const ResourceManagerScript := preload("res://scripts/resources/resource_manager.gd")
const ResourceNodeDatabaseScript := preload("res://scripts/resources/resource_node_database.gd")
const BuildingManagerScript := preload("res://scripts/buildings/building_manager.gd")
const ProductionManagerScript := preload("res://scripts/buildings/production_manager.gd")
const PowerManagerScript := preload("res://scripts/buildings/power_manager.gd")
const ActionBarScript := preload("res://scripts/ui/action_bar.gd")
const BoatCargoPanelScript := preload("res://scripts/ui/boat_cargo_panel.gd")
const BoatCargoScript := preload("res://scripts/player/boat_cargo.gd")
const PlayerUnitScript := preload("res://scripts/player/player_unit.gd")
const DogScript := preload("res://scripts/units/dog.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")
const WorldNavigationScript := preload("res://scripts/world/world_navigation.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const WorldDataScript := preload("res://scripts/world/world_data.gd")
const StatTrackerScript := preload("res://scripts/quests/stat_tracker.gd")
const QuestManagerScript := preload("res://scripts/quests/quest_manager.gd")
const QuestLogViewScript := preload("res://scripts/ui/quest_log_view.gd")
const QuestTrackerViewScript := preload("res://scripts/ui/quest_tracker_view.gd")
const ToastScript := preload("res://scripts/ui/toast.gd")
const TradeManagerScript := preload("res://scripts/world/trade_manager.gd")
const GameMenuScript := preload("res://scripts/ui/game_menu.gd")

const NO_BUILDING := -1

# Upper bound on how often the throttled crash-backstop autosave writes (see _process).
const AUTOSAVE_INTERVAL_SECONDS := 60.0

const PLACEMENT_SOUND := preload("res://assets/audio/sfx/building_placement.wav")
const StarfieldSkyShader := preload("res://assets/shaders/world_map/starfield_sky.gdshader")

# Pixels the cursor may travel between left press and release before it counts
# as a drag (pan) rather than a click.
const DRAG_THRESHOLD := 6.0

# The renderer of the island the robot is on (current_island). Every revealed island has its own
# renderer inside world_view; this is the one hover, placement and the robot work against.
var renderer: IslandRenderer
var camera_rig: CameraRig
# The world seed. Default 1 => every player gets the identical archipelago. Each island's own
# seed is derived from this and its hex coord (WorldBuilder.island_seed), so a slot's layout is stable
# across runs. Randomize this per-run later for varied worlds. See docs/island-generation.md.
var seed_value := 1
var is_panning := false
var is_left_panning := false
var left_button_down := false
var left_press_position := Vector2.ZERO
var selected_building_type := NO_BUILDING
# Move mode: the player picked "Move" on a placed building. The building is lifted off the map
# for the duration (removed from the island data) so the placement preview's adjacency reflects
# only its NEW surroundings and it isn't drawn at the old spot. It is restored at moving_from_cell
# if the move is cancelled, re-placed on confirm, and written back at the old spot by any save
# that lands mid-move (so quitting/crashing mid-move leaves it where it started — never lost).
# selected_building_type carries the type meanwhile, driving the (free) placement preview.
var is_moving_building := false
var moving_from_cell := GameTypes.NO_CELL
var moving_building_type := NO_BUILDING
var moving_rotation := 0
var moving_boat_launched := false
var world: WorldData
var world_navigation := WorldNavigationScript.new()
var current_island: IslandData
var building_manager: BuildingManager
var production_manager: ProductionManager
var power_manager: PowerManager
var trade_manager: TradeManager
var resource_manager: ResourceManager
var resource_node_database: ResourceNodeDatabase
var resource_bar: ResourceBar
var building_menu: BuildingMenu
var building_info_panel: BuildingInfoPanel
var action_bar: ActionBar
var boat_cargo_panel: BoatCargoPanel
var world_view: WorldView
var player_unit: PlayerUnit
var dog: Dog
var stat_tracker: StatTracker
var quest_manager: QuestManager
var quest_log_view: QuestLogView
var quest_tracker_view: QuestTrackerView
var toast: Toast
var game_menu: GameMenu
var _placement_player: AudioStreamPlayer
# The robot's work and walking commands, and K9-DA at its side.
var robot: RobotController
# Boarding, sailing, landing and the boat's cargo.
var boats: BoatController
# The cell under the cursor, on any island or the open sea (see _update_hover). Walking and sailing
# commands, and selecting the robot, all go by it.
var hovered_cell := GameTypes.NO_CELL

# Throttled crash backstop: resource changes (harvesting, production, fuel) mark the game
# dirty, and _process flushes a save at most once per AUTOSAVE_INTERVAL_SECONDS. The discrete
# event saves (quest/building/island/quit) clear this, so the timer only ever covers progress
# made between those events — bounding worst-case crash loss to one interval.
var _autosave_dirty := false
var _autosave_accum := 0.0


func _ready() -> void:
	building_manager = BuildingManagerScript.new()
	resource_manager = ResourceManagerScript.new()
	resource_manager.resource_changed.connect(_on_resource_changed)
	resource_node_database = ResourceNodeDatabaseScript.new()
	building_manager.setup(resource_node_database)
	production_manager = ProductionManagerScript.new()
	production_manager.setup(building_manager)
	production_manager.produced.connect(_on_building_produced)
	production_manager.input_consumed.connect(_on_input_consumed)
	power_manager = PowerManagerScript.new()
	power_manager.setup(building_manager)
	power_manager.fuel_consumed.connect(_on_fuel_consumed)
	# Quests are the robot's own knowledge: one global log driven by cumulative lifetime
	# stats, not reset on island switch (unlike per-island buildings/resources).
	stat_tracker = StatTrackerScript.new()
	quest_manager = QuestManagerScript.new()
	quest_manager.setup(stat_tracker)

	# The whole disc and every island on it; set up once the world exists (below).
	world_view = WorldViewScript.new()
	world_view.name = "WorldView"
	add_child(world_view)

	_placement_player = AudioStreamPlayer.new()
	_placement_player.stream = PLACEMENT_SOUND
	add_child(_placement_player)

	# The robot walks and sails the whole world; the world view tells it where every cell is.
	player_unit = PlayerUnitScript.new()
	player_unit.name = "PlayerUnit"
	player_unit.setup(world_view, world_navigation)
	player_unit.arrived.connect(_on_unit_arrived)
	player_unit.entered_cell.connect(_on_unit_entered_cell)
	add_child(player_unit)

	# K9-DA, the dog the MAIN quest rescues: stranded on a ring-1 island until the robot picks
	# it up, then it follows the robot between islands (RobotController.sync_dog).
	dog = DogScript.new()
	dog.name = "Dog"
	dog.setup(world_view)
	add_child(dog)

	camera_rig = CameraRigScript.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	_setup_lighting()

	world = WorldDataScript.new()
	# A save, if present, replaces the fresh world plus the global progression (stats/quests)
	# before the UI is built so building_menu wires up against the loaded state.
	var loaded := _try_load_game()
	# Every island on the disc exists from the start (unrevealed ones wait under the clouds).
	# Also fills in slots an older save never generated.
	WorldBuilder.ensure_generated(world, seed_value, building_manager)
	world_navigation.setup(world)
	# Pick K9-DA's island and spot (or fill them in for an older save) before the map is drawn.
	WorldBuilder.place_dog(world, seed_value)
	world_view.setup(world, resource_node_database, building_manager, world_navigation)
	world_view.refresh()
	camera_rig.set_overview(world_view.overview_pivot(), world_view.overview_distance())
	# Built after loading so it runs the loaded world's routes.
	trade_manager = TradeManagerScript.new()
	trade_manager.setup(world, building_manager)
	trade_manager.route_created.connect(_on_trade_route_created)
	trade_manager.route_removed.connect(_on_trade_route_removed)
	trade_manager.cargo_delivered.connect(_on_trade_cargo_delivered)
	# Set up once the world and units exist.
	robot = RobotController.new()
	robot.setup(self)
	# K9-DA stands taller than the chart, so it appears once its island's patch has opened.
	world_view.patch_opened.connect(func(_coord: Vector2i) -> void: robot.sync_dog())
	_add_ui()
	# Set up once the robot and the UI it uses (the toast, the cargo panel) exist.
	boats = BoatController.new()
	boats.setup(self)
	# Persist on quit/suspend: intercept the close request so we can save before exiting, and
	# react to the mobile pause notification in _notification (the OS can kill a backgrounded
	# app without further warning).
	get_tree().set_auto_accept_quit(false)
	switch_to_island(world.current_coord if loaded else WorldData.CENTER, true)


# Save on the ways the game can end: a desktop window close, or a mobile app suspend (which
# may be the last callback before the OS reclaims the process). auto_accept_quit is disabled
# in _ready, so we must quit ourselves after saving on the close request.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			save_game()


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
	for island in world.islands.values():
		building_manager.migrate_footprints(island)
	seed_value = int(payload.get("seed_value", seed_value))
	stat_tracker.restore(payload.get("stats", {}))
	quest_manager.restore_completed(payload.get("completed_quests", {}))
	print("Loaded save: %d island(s)" % world.island_count())
	return true


func save_game() -> bool:
	if world == null:
		return false
	boats.store_position()

	# A move in progress has lifted the building off the map. Write it back at its original cell
	# just for this save, so a quit/crash/autosave mid-move persists the building where it started
	# rather than losing it. The live game keeps it lifted; we remove it again right after.
	var restore_for_save := (
		is_moving_building
		and current_island != null
		and moving_from_cell != GameTypes.NO_CELL
		and not current_island.has_building(moving_from_cell)
	)
	if restore_for_save:
		building_manager.try_place(moving_from_cell, moving_building_type, current_island, moving_rotation)
		current_island.buildings[moving_from_cell].boat_launched = moving_boat_launched

	var reference_time := Time.get_ticks_msec() / 1000.0
	var payload := SaveManager.build_payload(
		world,
		stat_tracker.to_dict(),
		quest_manager.completed_to_dict(),
		seed_value,
		reference_time
	)
	var saved := SaveManager.write(payload)

	if restore_for_save:
		current_island.remove_building(moving_from_cell)
	# Any save (event or timer) satisfies the throttle: clear the flag and restart the window.
	if saved:
		_autosave_dirty = false
		_autosave_accum = 0.0
	return saved


# Progress was made that a crash shouldn't lose: arms the throttled backstop save (see _process).
func mark_dirty() -> void:
	_autosave_dirty = true


func play_placement_sound() -> void:
	if _placement_player != null:
		_placement_player.play()


func _on_menu_opened() -> void:
	is_panning = false
	is_left_panning = false
	left_button_down = false
	building_menu.close_menu()
	quest_log_view.close()
	building_info_panel.hide_info()
	boat_cargo_panel.close()


func _on_menu_save_game() -> void:
	game_menu.show_status("Game saved." if save_game() else "Could not save the game. Please try again.")


func _on_menu_load_game() -> void:
	if SaveManager.read().is_empty():
		game_menu.show_status("No readable save found.")
		return
	_reload_from_menu()


func _on_menu_new_game() -> void:
	SaveManager.delete_save()
	if SaveManager.has_save():
		game_menu.show_status("Could not replace the save. Please try again.")
		return
	_reload_from_menu()


func _reload_from_menu() -> void:
	# Reload runs the normal startup path, rebuilding every manager and view together.
	# Keep the old scene paused until it is replaced so it cannot autosave over the load.
	# The outgoing scene is detached during reload; retain the tree before that happens.
	var tree := get_tree()
	var error := tree.reload_current_scene()
	if error != OK:
		game_menu.show_status("Could not restart the game. Please try again.")
		return
	tree.paused = false


# Flush the crash-backstop save once a dirty interval has elapsed. The accumulator only runs
# while dirty, so a quiet game never writes and worst-case loss stays within one interval.
func _update_autosave(delta: float) -> void:
	if not _autosave_dirty:
		return

	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL_SECONDS:
		save_game()


func _process(delta: float) -> void:
	boats.refresh_cargo()
	_update_autosave(delta)
	world_view.set_overview_amount(camera_rig.overview_amount())

	if current_island == null:
		return

	# Every island runs, not just the one on screen, so a colony keeps producing (and trade routes
	# keep hauling its goods) while the robot is elsewhere. Only the current island can be
	# hand-powered by the robot, and only its power balance feeds the resource bar.
	var current_time_seconds := Time.get_ticks_msec() / 1000.0
	for coord in world.islands:
		var island: IslandData = world.islands[coord]
		var is_current := island == current_island
		var operated_cell: Vector2i = robot.operated_cell() if is_current else GameTypes.NO_CELL
		power_manager.update(island, current_time_seconds, operated_cell, is_current)
		production_manager.update(island, current_time_seconds)
	trade_manager.update(current_time_seconds)

	robot.update(delta)


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
		camera_rig.toggle_overview()

	if key_event.keycode == KEY_T:
		quest_log_view.toggle()

	if key_event.keycode == KEY_B:
		building_menu.toggle_menu()

	if key_event.keycode == KEY_R and selected_building_type != NO_BUILDING:
		# Turn the footprint being placed; Shift turns it back.
		renderer.rotate_placement(-1 if key_event.shift_pressed else 1)

	if key_event.keycode == KEY_SPACE:
		world_view.set_show_grid(not renderer.show_grid)

	if key_event.keycode == KEY_ESCAPE:
		if boat_cargo_panel.is_open():
			boat_cargo_panel.close()
		elif quest_log_view.is_open():
			quest_log_view.close()
		elif camera_rig.overview_amount() > 0.5:
			camera_rig.exit_overview()
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

	# =: reveal one more ring of islands — a stand-in for a boat-tier unlock.
	if keycode == KEY_EQUAL:
		_reveal_rings(1)


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
	refresh_action_bar()
	# Completing a quest is a milestone the player would hate to lose to a crash — checkpoint it.
	save_game()


# Building-unlock rewards need no action here — placement reads quest_manager state
# directly. Robot upgrades and world-map reveals change game state, so they're applied
# imperatively.
func _apply_reward(reward: QuestReward) -> void:
	match reward.kind:
		GameTypes.RewardKind.ROBOT_UPGRADE:
			match reward.robot_upgrade:
				GameTypes.RobotUpgrade.HARVESTING, GameTypes.RobotUpgrade.OPERATING:
					pass # Capability gate read via quest_manager.is_upgrade_active(); no imperative change.
		GameTypes.RewardKind.REVEAL_WORLD_RINGS:
			_reveal_rings(reward.ring_count)


# Lift the clouds off more rings. Revealing past the disc's edge grows the disc, so its new
# islands are generated and the overview reframed.
func _reveal_rings(count: int) -> void:
	var dog_was_hidden := not world.is_revealed(world.dog_coord)
	world.reveal_additional_rings(count)
	if dog_was_hidden and world.is_revealed(world.dog_coord) and not world.dog_rescued:
		toast.show_message("K9-DA's signal detected! Press M to see which island it's coming from.")
	WorldBuilder.ensure_generated(world, seed_value, building_manager)
	world_navigation.rebuild_regions()
	world_view.refresh()
	camera_rig.set_overview(world_view.overview_pivot(), world_view.overview_distance())
	save_game()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var is_over_ui := get_viewport().gui_get_hovered_control() != null
		# Clicks act on the cell under the cursor now, even if the camera moved since it last did.
		_update_hover(event.position)

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
					_handle_left_click(event.position)
				left_button_down = false
				is_left_panning = false

	if event is InputEventMouseMotion:
		if left_button_down and not is_left_panning \
				and event.position.distance_to(left_press_position) > DRAG_THRESHOLD:
			is_left_panning = true

		if is_panning or is_left_panning:
			camera_rig.pan(event.relative)

		_update_hover(event.position)


# Hover the cell under a screen position: an island tile at its own height, or the sea. Steering
# the boat, a marker shows where it can go (BoatController.show_hover); otherwise the current island
# lights the tile up, placement previews included.
func _update_hover(screen_position: Vector2) -> void:
	var camera := camera_rig.get_camera()
	if camera == null:
		return
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	hovered_cell = world_view.cell_from_ray(origin, direction)
	world_view.set_hovered(world_view.slot_at_ray(origin, direction))
	if player_unit.boat_id != -1 and player_unit.selected and selected_building_type == NO_BUILDING:
		boats.show_hover(hovered_cell)
		return
	world_view.hide_sailing_hover()
	renderer.set_hovered_cell(hovered_cell)


func _handle_left_click(screen_position: Vector2) -> void:
	if is_moving_building:
		_try_finish_move()
		return

	if selected_building_type != NO_BUILDING:
		_try_place_selected_building()
		return
	if player_unit.boat_id != -1 and _try_select_unit():
		return

	if _try_travel_to_clicked_island(screen_position):
		return

	if _try_select_unit():
		return

	_deselect_unit()
	_try_select_building()


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-40.0), 0.0)
	# Restrained warm sunlight and cool ambient keep the earthy material palette readable.
	sun.light_color = Color("#fff4e4")
	# Sun-cast shadows. The world is large (128-unit cells, camera 300-1200 units out in play), so
	# the shadow range is pushed well past the default 100; the camera rig grows it further as it
	# zooms out. Biases are kept low — large values peter-pan the shadow inside the caster at this
	# geometry scale.
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
	camera_rig.set_sun(sun)

	# The disc floats in open space: a procedural starfield behind everything, seen past the ice
	# rim whenever the camera pulls back far enough to look over the edge.
	var sky_material := ShaderMaterial.new()
	sky_material.shader = StarfieldSkyShader
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Lighting stays the hand-tuned flat ambient rather than coming from the (dark) sky.
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b3c2cf")
	environment.ambient_light_energy = 0.4
	# Islanders-style distance haze: depth fog fading the far ocean into a light cyan. The camera
	# rig moves the fog start/end with zoom so the island itself always stays clear, and fades it
	# out for the overview. It never touches the stars.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color(0.45, 0.8, 0.8)
	environment.fog_density = 0.85
	environment.fog_depth_curve = 1.4
	environment.fog_sky_affect = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	camera_rig.set_fog_environment(environment)


func _command_unit_to_hovered() -> bool:
	return _command_unit_to(hovered_cell)


# Send the robot to `cell`: aboard, its boat sails there (or lands there, BoatController.command_to);
# on foot, it walks to where it can work the cell (RobotController.command_to).
func _command_unit_to(cell: Vector2i) -> bool:
	if player_unit == null or current_island == null:
		return false
	if player_unit.boat_id != -1:
		return boats.command_to(cell)
	return robot.command_to(cell)


# The robot's moves go to the boat while it's aboard, to its walking and work otherwise.
func _on_unit_entered_cell(cell: Vector2i) -> void:
	if player_unit.boat_id != -1:
		boats.on_entered_cell(cell)
	else:
		robot.on_entered_cell(cell)


func _on_unit_arrived(_cell: Vector2i) -> void:
	if player_unit.boat_id != -1:
		boats.on_arrived()
	else:
		robot.on_arrived()


# The hovered cell is tinted green where the selected robot would start working if right-clicked
# (RobotController.is_actionable_cell), but not while placing or moving a building, where the
# right-click cancels instead.
func _is_actionable_cell(cell: Vector2i) -> bool:
	return selected_building_type == NO_BUILDING and robot.is_actionable_cell(cell)


# Rebuild the robot's command bar from its current context: the bar shows only while a
# parked, selected robot has at least one applicable action: the boat's (BoatController.actions)
# and, on foot, its work (RobotController.actions). The bar (action_bar.gd) is just the view;
# _on_action_pressed carries an action out.
func refresh_action_bar() -> void:
	if action_bar == null:
		return

	var actions: Array = []
	if (
		player_unit != null
		and player_unit.selected
		and not player_unit.is_moving()
		and current_island != null
	):
		actions.append_array(boats.actions())
		if player_unit.boat_id == -1:
			actions.append_array(robot.actions())

	action_bar.set_actions(actions)
	action_bar.set_selected(player_unit != null and player_unit.selected)
	# Selection and unlocks change which cells the hover tints green.
	if renderer != null:
		renderer.refresh_hover()


# The portrait selects the robot and brings the camera back to its current position.
func _on_portrait_select_requested() -> void:
	if player_unit == null or player_unit.current_cell == GameTypes.NO_CELL:
		return

	player_unit.set_selected(true)
	if camera_rig.is_heading_to_overview() or camera_rig.overview_amount() > 0.0:
		camera_rig.exit_overview()
	camera_rig.center_on(player_unit.position)
	refresh_action_bar()


func _on_action_pressed(action_id: int) -> void:
	if player_unit.is_moving():
		return
	match action_id:
		GameTypes.UnitAction.CARGO, GameTypes.UnitAction.PILOT_BOAT, GameTypes.UnitAction.DISEMBARK:
			boats.press(action_id)
		_:
			robot.press(action_id)


# Coming close enough to reveal an island discovers it; landing only activates its economy.
func discover_island(coord: Vector2i) -> bool:
	var island: IslandData = world.islands[coord]
	if island.visited:
		return false
	island.sighted = true
	island.visited = true
	world_view.set_current_coord(world.current_coord)
	robot.sync_dog()
	if coord != WorldData.CENTER:
		stat_tracker.add(GameTypes.Stat.ISLANDS_REACHED, 1)
	if world.is_dog_stranded_on(coord):
		stat_tracker.add(GameTypes.Stat.DOG_ISLAND_DISCOVERED, 1)
		toast.show_message("K9-DA's island discovered! Land and walk over to him to rescue him.")
	return true


# Production counts toward lifetime stats on every island; the floating "+N" only shows for the
# island on screen. Away islands don't touch the ResourceManager facade, so mark the autosave
# dirty here too.
func _on_building_produced(island: IslandData, anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	stat_tracker.record_resource_gained(resource_type, amount)
	mark_dirty()
	if island == current_island:
		FloatingText.spawn_resource(self, renderer.get_cell_center(anchor_cell), resource_type, "+%d" % amount, 16)


func _on_fuel_consumed(island: IslandData, anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	# Away inventories do not emit through ResourceManager; fuel still needs the save backstop.
	mark_dirty()
	if island == current_island:
		FloatingText.spawn_resource(self, renderer.get_cell_center(anchor_cell), resource_type, "-%d" % amount, 16)


func _on_input_consumed(island: IslandData, anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	if island == current_island:
		FloatingText.spawn_resource(self, renderer.get_cell_center(anchor_cell), resource_type, "-%d" % amount, 16)


func _on_trade_route_created(_route: TradeRoute) -> void:
	stat_tracker.add(GameTypes.Stat.TRADE_ROUTES_ESTABLISHED, 1)
	world_view.refresh()
	save_game()


func _on_trade_route_removed(_route: TradeRoute) -> void:
	world_view.refresh()
	save_game()


# A boat unloaded. Count it toward the shipping stat, and pop a "+N" over a dock when it's the
# island on screen.
func _on_trade_cargo_delivered(_route: TradeRoute, coord: Vector2i, resource_type: int, amount: int) -> void:
	stat_tracker.add(GameTypes.Stat.GOODS_SHIPPED, amount)
	mark_dirty()
	if coord != world.current_coord:
		return
	for anchor_cell in current_island.buildings:
		if current_island.buildings[anchor_cell].type == GameTypes.BuildingType.DOCK:
			FloatingText.spawn_resource(self, renderer.get_cell_center(anchor_cell), resource_type, "+%d" % amount, 18)
			return


func _try_select_unit() -> bool:
	if player_unit == null or player_unit.current_cell == GameTypes.NO_CELL:
		return false
	if hovered_cell not in [player_unit.current_cell, player_unit.next_cell()]:
		return false

	player_unit.set_selected(true)
	refresh_action_bar()
	return true


func _deselect_unit() -> void:
	world_view.hide_sailing_hover()
	if player_unit != null:
		player_unit.set_selected(false)
	refresh_action_bar()


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
	if selected_building_type == GameTypes.BuildingType.DOCK and building_manager.has_dock(current_island):
		toast.show_message("Only one Dock per island. Move or remove the existing Dock first.")
		return false

	var cost := _get_building_cost(selected_building_type)
	if not resource_manager.can_afford(cost):
		return false

	# Placement puts down a blueprint; the robot builds it (see RobotController._finish_construction,
	# which is also where it counts as built for quests). Its materials are paid now, and refunded if
	# cancelled.
	var anchor_cell := renderer.hovered_cell
	if not renderer.try_place_hovered_building(selected_building_type, true):
		return false
	robot.reroute()

	resource_manager.spend(cost)
	play_placement_sound()
	robot.send_to_build(anchor_cell)
	building_menu.clear_selection()
	# Placing a building is a deliberate, resource-spending action — checkpoint it.
	save_game()
	return true


func _get_building_cost(building_type: int) -> Dictionary:
	return building_manager.get_cost(building_type)


# Inspect the neighbouring visited island with the camera; the robot stays where it is.
func _switch_to_adjacent_island(direction: int) -> void:
	var coords := world.visited_coords()
	if coords.size() <= 1:
		return

	var index := coords.find(world.current_coord)
	var next_coord: Vector2i = coords[(index + direction + coords.size()) % coords.size()]
	camera_rig.center_on(world_view.renderer_for(next_coord).get_map_center())


# An island click plans a real voyage while aboard. On foot, it explains how to board.
# In the overview a sailing destination also returns to the play zoom.
func _try_travel_to_clicked_island(screen_position: Vector2) -> bool:
	var camera := camera_rig.get_camera()
	if camera == null:
		return false

	var coord := world_view.slot_at_ray(
		camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position)
	)
	var in_overview := camera_rig.overview_amount() > 0.5
	if coord == WorldData.NO_COORD:
		# Open sea: nothing to do, but in the overview don't let it fall through to the island.
		return in_overview

	if not world.is_revealed(coord):
		toast.show_message("Uncharted island — " + world_view.locked_island_hint(coord))
		return true

	if player_unit.boat_id != -1 and (coord != world.current_coord or in_overview):
		boats.sail_to_island(coord)
	elif coord != world.current_coord:
		toast.show_message("Board a boat at the shore or dock to sail here.")
	elif not in_overview:
		return false

	if in_overview:
		camera_rig.exit_overview()
	return true


# Make the island at `coord` the one the robot, resource bar and build tools work on. Every
# island is always on screen in the shared world, so this hands the robot to that island's
# renderer and glides the camera across (`instant` jumps there, for startup).
func switch_to_island(coord: Vector2i, instant := false) -> void:
	var next_renderer := world_view.renderer_for(coord)
	if next_renderer == null:
		return

	# Restore any building mid-move onto the island we are leaving (still current here), so it
	# isn't orphaned when current_island changes.
	_cancel_building_move()
	if player_unit.boat_id != -1:
		boats.store_position()
		world.piloted_boat = -1
		player_unit.leave_boat()
		renderer.refresh()

	# Release the wheel on the island we are leaving, while it is still current,
	# so its manual generator is not left flagged as running.
	robot.stop_operating()

	if not world.set_current(coord):
		return

	if renderer != null and renderer != next_renderer:
		renderer.clear_interaction()
	renderer = next_renderer
	renderer.is_cell_occupied_by_unit = robot.is_unit_cell
	renderer.is_cell_actionable = _is_actionable_cell
	current_island = world.get_current()
	# Startup and legacy saves can enter an island before a sailing approach has discovered it.
	discover_island(coord)
	resource_manager.set_inventory(current_island.inventory)
	building_menu.refresh_stock()
	building_info_panel.hide_info()
	_spawn_player_unit()
	robot.sync_dog()
	resource_bar.refresh()
	world_view.set_current_coord(coord)
	_apply_selected_building()
	camera_rig.center_on(player_unit.position if player_unit.boat_id != -1 else renderer.get_map_center(), instant)

	# Autosave at each settled island state — the natural checkpoint, and it also writes the
	# initial save for a brand-new game (the starter island is entered through here too).
	save_game()


func _spawn_player_unit() -> void:
	if player_unit == null:
		return
	player_unit.leave_boat()

	robot.stop_work()
	robot.clear_targets()
	player_unit.place_at(WorldBuilder.find_spawn_cell(current_island))
	if world.boats.has(world.piloted_boat):
		var saved_boat: Dictionary = world.boats[world.piloted_boat]
		player_unit.mount_boat(world.piloted_boat, saved_boat.cell, float(saved_boat.yaw))
	boats.landing_cell = GameTypes.NO_CELL
	refresh_action_bar()


func _select_no_building() -> void:
	# Also the cancel path for an in-progress move (right-click / picking another tool routes
	# here via the build menu): restore the lifted building to its original cell.
	_cancel_building_move()
	selected_building_type = NO_BUILDING
	_apply_selected_building()


func _select_building(building_type: int) -> void:
	# Choosing a building from the menu abandons any move in progress (restoring the building).
	_cancel_building_move()
	selected_building_type = building_type
	_apply_selected_building()


# Panel "Move": lift the building off the map and enter a free placement preview for its type.
# The next valid left-click drops it at the new cell (_try_finish_move); cancelling restores it.
func _on_building_move_requested(building_type: int, anchor_cell: Vector2i, island: IslandData) -> void:
	if island == null or island != current_island:
		return
	# Older saves may contain multiple docks. Keep them intact until the player removes extras,
	# rather than lifting a dock that the placement limit would prevent us from restoring.
	if building_type == GameTypes.BuildingType.DOCK and building_manager.has_dock(island, anchor_cell):
		toast.show_message("Only one Dock per island. Remove the extra Docks before moving this one.")
		return
	# Moving is for finished buildings; a blueprint is cancelled and placed again instead.
	if island.is_under_construction(anchor_cell):
		return

	is_moving_building = true
	moving_from_cell = anchor_cell
	moving_building_type = building_type
	moving_rotation = island.get_building_rotation(anchor_cell)
	moving_boat_launched = bool(island.buildings[anchor_cell].get("boat_launched", false))
	# Pick it up as it stands: the preview starts at its current turn.
	renderer.placement_rotation = moving_rotation
	# Take it off the map now so its old footprint stops drawing and stops feeding adjacency
	# (to itself in the preview, and to its neighbours) while the player picks a new spot.
	renderer.remove_building(anchor_cell)
	robot.land_stranded_units(anchor_cell)
	selected_building_type = building_type
	_apply_selected_building()


func _try_finish_move() -> void:
	# The building is already lifted off the map, so just drop it at the hovered cell. On an
	# illegal target (occupied / wrong terrain) placement fails and we stay in move mode.
	if not renderer.try_place_hovered_building(moving_building_type):
		return
	current_island.buildings[renderer.hovered_cell].boat_launched = moving_boat_launched
	renderer.refresh()
	robot.reroute()

	play_placement_sound()

	# Clear move state BEFORE clear_selection so its _select_no_building doesn't try to restore
	# the building we just successfully placed.
	is_moving_building = false
	moving_from_cell = GameTypes.NO_CELL
	moving_building_type = NO_BUILDING
	building_menu.clear_selection()
	save_game()


# Put the lifted building back at its original cell and leave move mode. A no-op when no move is
# in progress, so it's safe to call from every cancel path.
func _cancel_building_move() -> void:
	if not is_moving_building:
		return

	is_moving_building = false
	var from := moving_from_cell
	var building_type := moving_building_type
	moving_from_cell = GameTypes.NO_CELL
	moving_building_type = NO_BUILDING

	if current_island != null and from != GameTypes.NO_CELL:
		renderer.place_building_at(from, building_type, moving_rotation)
		current_island.buildings[from].boat_launched = moving_boat_launched
		renderer.refresh()


# Panel "Delete": scrap the building outright, or cancel a blueprint and get its materials back.
# The power/production managers recompute from the remaining buildings on the next _process tick,
# so no manual refresh is needed here.
func _on_building_delete_requested(anchor_cell: Vector2i, island: IslandData) -> void:
	if island == null or island != current_island:
		return

	var refund := {}
	if island.is_under_construction(anchor_cell):
		refund = _get_building_cost(island.get_building_type(anchor_cell))
	if not renderer.remove_building(anchor_cell):
		return

	if anchor_cell == robot.construct_cell:
		robot.stop_constructing()
	robot.land_stranded_units(anchor_cell)
	for resource_type in refund:
		resource_manager.add_amount(resource_type, refund[resource_type])
	refresh_action_bar()
	save_game()


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
	mark_dirty()


func _add_ui() -> void:
	resource_bar = ResourceBarScript.new()
	add_child(resource_bar)
	resource_bar.setup(resource_manager, power_manager, stat_tracker)

	building_info_panel = BuildingInfoPanelScript.new()
	building_info_panel.setup(building_manager, trade_manager, world)
	building_info_panel.move_requested.connect(_on_building_move_requested)
	building_info_panel.delete_requested.connect(_on_building_delete_requested)
	add_child(building_info_panel)

	building_menu = BuildingMenuScript.new()
	building_menu.setup(building_manager, quest_manager, resource_manager)
	building_menu.building_selected.connect(_select_building)
	building_menu.selection_cleared.connect(_select_no_building)
	add_child(building_menu)

	action_bar = ActionBarScript.new()
	action_bar.action_pressed.connect(_on_action_pressed)
	action_bar.select_requested.connect(_on_portrait_select_requested)
	add_child(action_bar)

	boat_cargo_panel = BoatCargoPanelScript.new()
	add_child(boat_cargo_panel)

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

	game_menu = GameMenuScript.new()
	add_child(game_menu)
	game_menu.opened.connect(_on_menu_opened)
	game_menu.new_game_requested.connect(_on_menu_new_game)
	game_menu.save_game_requested.connect(_on_menu_save_game)
	game_menu.load_game_requested.connect(_on_menu_load_game)
