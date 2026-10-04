extends Node3D

const IslandGeneratorScript := preload("res://scripts/island/island_generator.gd")
const WorldViewScript := preload("res://scripts/world/world_view.gd")
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
const StatTrackerScript := preload("res://scripts/quests/stat_tracker.gd")
const QuestManagerScript := preload("res://scripts/quests/quest_manager.gd")
const QuestLogViewScript := preload("res://scripts/ui/quest_log_view.gd")
const QuestTrackerViewScript := preload("res://scripts/ui/quest_tracker_view.gd")
const ToastScript := preload("res://scripts/ui/toast.gd")
const TradeManagerScript := preload("res://scripts/world/trade_manager.gd")
const GameMenuScript := preload("res://scripts/ui/game_menu.gd")

const NO_BUILDING := -1
const HARVEST_INTERVAL := 3.0
const HARVEST_YIELD := 1
# Working a building or resource node from the tile beside it, the robot leans this far (in
# tiles) toward it — close enough to read as working it, clear of its geometry.
const WORK_LEAN_TILES := 0.15
# Extra steps the robot will walk to work a target from the camera side rather than from behind
# it, where the target would hide it.
const BEHIND_PENALTY := 2

# Upper bound on how often the throttled crash-backstop autosave writes (see _process).
const AUTOSAVE_INTERVAL_SECONDS := 60.0

# Icons for the robot's command-bar actions.
const PICKAXE_ICON := preload("res://assets/icons/pickaxe.png")
const POWER_ICON := preload("res://assets/icons/power.png")
const PAW_ICON := preload("res://assets/icons/paw.png")

const PLACEMENT_SOUND := preload("res://assets/audio/sfx/building_placement.wav")
const StarfieldSkyShader := preload("res://assets/shaders/world_map/starfield_sky.gdshader")

# Actions the selected robot can take on its current tile, dispatched from the ActionBar.
enum UnitAction {
	HARVEST,
	OPERATE,
	RESCUE,
}
# Pixels the cursor may travel between left press and release before it counts
# as a drag (pan) rather than a click.
const DRAG_THRESHOLD := 6.0

var generator := IslandGeneratorScript.new()
# The renderer of the island the robot is on (current_island). Every revealed island has its own
# renderer inside world_view; this is the one hover, placement and the robot work against.
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
# Move mode: the player picked "Move" on a placed building. The building is lifted off the map
# for the duration (removed from the island data) so the placement preview's adjacency reflects
# only its NEW surroundings and it isn't drawn at the old spot. It is restored at moving_from_cell
# if the move is cancelled, re-placed on confirm, and written back at the old spot by any save
# that lands mid-move (so quitting/crashing mid-move leaves it where it started — never lost).
# selected_building_type carries the type meanwhile, driving the (free) placement preview.
var is_moving_building := false
var moving_from_cell := Vector2i(-1, -1)
var moving_building_type := NO_BUILDING
var moving_rotation := 0
var world: WorldData
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

	# The robot walks the current island; it is handed that island's renderer on every switch.
	player_unit = PlayerUnitScript.new()
	player_unit.name = "PlayerUnit"
	player_unit.arrived.connect(_on_unit_arrived)
	player_unit.entered_cell.connect(_on_unit_entered_cell)
	add_child(player_unit)

	# K9-DA, the dog the MAIN quest rescues: stranded on a ring-1 island until the robot picks
	# it up, then it follows the robot between islands (see _sync_dog).
	dog = DogScript.new()
	dog.name = "Dog"
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
	_ensure_world_generated()
	# Pick K9-DA's island and spot (or fill them in for an older save) before the map is drawn.
	_ensure_dog_placed()
	world_view.setup(world, resource_node_database, building_manager)
	world_view.refresh()
	camera_rig.set_overview(world_view.overview_pivot(), world_view.overview_distance())
	# Built after loading so it runs the loaded world's routes.
	trade_manager = TradeManagerScript.new()
	trade_manager.setup(world, building_manager)
	trade_manager.route_created.connect(_on_trade_route_created)
	trade_manager.route_removed.connect(_on_trade_route_removed)
	trade_manager.cargo_delivered.connect(_on_trade_cargo_delivered)
	_add_ui()
	# Persist on quit/suspend: intercept the close request so we can save before exiting, and
	# react to the mobile pause notification in _notification (the OS can kill a backgrounded
	# app without further warning).
	get_tree().set_auto_accept_quit(false)
	_switch_to_island(world.current_coord if loaded else WorldData.CENTER, true)


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
	for island in world.islands.values():
		building_manager.migrate_footprints(island)
	seed_value = int(payload.get("seed_value", seed_value))
	stat_tracker.restore(payload.get("stats", {}))
	quest_manager.restore_completed(payload.get("completed_quests", {}))
	print("Loaded save: %d island(s)" % world.island_count())
	return true


func _save_game() -> bool:
	if world == null:
		return false

	# A move in progress has lifted the building off the map. Write it back at its original cell
	# just for this save, so a quit/crash/autosave mid-move persists the building where it started
	# rather than losing it. The live game keeps it lifted; we remove it again right after.
	var restore_for_save := (
		is_moving_building
		and current_island != null
		and moving_from_cell != Vector2i(-1, -1)
		and not current_island.has_building(moving_from_cell)
	)
	if restore_for_save:
		building_manager.try_place(moving_from_cell, moving_building_type, current_island, moving_rotation)

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


func _on_menu_opened() -> void:
	is_panning = false
	is_left_panning = false
	left_button_down = false
	building_menu.close_menu()
	quest_log_view.close()
	building_info_panel.hide_info()


func _on_menu_save_game() -> void:
	game_menu.show_status("Game saved." if _save_game() else "Could not save the game. Please try again.")


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
		_save_game()


func _process(delta: float) -> void:
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
		var operated_cell := operate_cell if is_current and is_operating else Vector2i(-1, -1)
		power_manager.update(island, current_time_seconds, operated_cell, is_current)
		production_manager.update(island, current_time_seconds)
	trade_manager.update(current_time_seconds)

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
		if quest_log_view.is_open():
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
			_reveal_rings(reward.ring_count)


# Lift the clouds off more rings. Revealing past the disc's edge grows the disc, so its new
# islands are generated and the overview reframed.
func _reveal_rings(count: int) -> void:
	var dog_was_hidden := not world.is_revealed(world.dog_coord)
	world.reveal_additional_rings(count)
	if dog_was_hidden and world.is_revealed(world.dog_coord) and not world.dog_rescued:
		toast.show_message("K9-DA's signal detected! Press M to see which island it's coming from.")
	_ensure_world_generated()
	world_view.refresh()
	camera_rig.set_overview(world_view.overview_pivot(), world_view.overview_distance())
	_save_game()


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
					_handle_left_click(event.position)
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
			var origin := camera.project_ray_origin(event.position)
			var direction := camera.project_ray_normal(event.position)
			renderer.set_hovered_from_ray(origin, direction)
			world_view.set_hovered(world_view.slot_at_ray(origin, direction))


func _handle_left_click(screen_position: Vector2) -> void:
	if is_moving_building:
		_try_finish_move()
		return

	if selected_building_type != NO_BUILDING:
		_try_place_selected_building()
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
	environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	environment.ambient_light_energy = 0.5
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


# Send the robot to the hovered cell. Open ground is walked onto. The robot doesn't park on a
# building or resource node, so for one it walks to where it can work it instead (see
# _plan_approach) and the target stays the clicked cell.
func _command_unit_to_hovered() -> bool:
	if player_unit == null or current_island == null:
		return false

	var cell := renderer.hovered_cell
	# A building's tiles are all targets, even one standing in the water (the dock's pier).
	if cell == Vector2i(-1, -1) or not (HexPathfinderScript.is_walkable(current_island, cell) or current_island.has_building(cell)):
		return false

	var plan := _plan_approach(cell, player_unit.current_cell)
	if plan.is_empty():
		return false

	pending_action_cell = cell

	if plan.path.is_empty() and plan.spot_cell == Vector2i(-1, -1):
		# Already where it can work the target: switch to it without moving.
		if cell != harvest_cell:
			_stop_harvesting()
		if current_island.get_building_anchor_cell(cell) != operate_cell:
			_stop_operating()
		_on_unit_arrived(player_unit.current_cell)
		return true

	_stop_harvesting()
	_stop_operating()
	harvestable_cell = Vector2i(-1, -1)
	operable_cell = Vector2i(-1, -1)
	player_unit.follow_path(plan.path, plan.spot_cell, plan.spot_position)
	_refresh_action_bar()
	return true


# How the robot, standing at `start`, gets to work `target`: {path, spot_cell, spot_position} for
# PlayerUnit.follow_path, or {} when it can't get there. Empty path and no spot = already there.
#   - A building with a WorkSpot: the shortest route straight onto the building's tile (walking
#     through buildings is fine), the last step going onto the parking spot instead of the
#     tile's centre. The robot then turns to face the building (see _on_unit_arrived).
#   - Open ground: walk onto it.
#   - Anything else (a resource node, or a building whose model fills its tile): the cheapest
#     open neighbour, interacting across the edge. Neighbours behind the target (away from the
#     camera) cost BEHIND_PENALTY extra, so the robot isn't hidden by it.
#   - No open neighbour at all (fully enclosed): stand on the target itself, as a last resort.
func _plan_approach(target: Vector2i, start: Vector2i) -> Dictionary:
	var island := current_island
	var no_path: Array[Vector2i] = []

	var spot = renderer.get_work_spot(island.get_building_anchor_cell(target)) if island.has_building(target) else null
	# A building bigger than one tile is reached at the tile its spot stands on, not the one clicked.
	var spot_tile: Vector2i = renderer.world_to_cell(spot) if spot != null else target
	if spot != null and not HexPathfinderScript.is_walkable(island, spot_tile):
		spot = null
	if spot != null:
		if start == spot_tile and player_unit.is_at_spot():
			return _approach(no_path)
		var to_tile := HexPathfinderScript.find_path(island, start, spot_tile)
		if to_tile.is_empty() and start != spot_tile:
			return {}
		if not to_tile.is_empty():
			to_tile.pop_back()  # the spot leg replaces the step to the tile's centre
		return _approach(to_tile, spot_tile, Vector3(spot.x, renderer.get_cell_center(spot_tile).y, spot.z))

	if HexPathfinderScript.is_open(island, target):
		var path := HexPathfinderScript.find_path(island, start, target)
		if path.is_empty() and target != start:
			return {}
		return _approach(path)

	var search := HexPathfinderScript.search(island, start)
	var costs: Dictionary = search.cost
	var center := renderer.get_cell_center(target)

	var best := Vector2i(-1, -1)
	var best_score := INF
	for neighbor in HexGridScript.neighbors(target):
		if not HexPathfinderScript.is_open(island, neighbor) or not costs.has(neighbor):
			continue
		var neighbor_z := renderer.get_cell_center(neighbor).z
		var score: float = costs[neighbor] + (BEHIND_PENALTY if neighbor_z < center.z else 0)
		# Equal scores: the tile nearer the camera.
		score -= neighbor_z * 0.0001
		if score < best_score:
			best = neighbor
			best_score = score

	if best != Vector2i(-1, -1):
		return _approach(HexPathfinderScript.path_to(search, best))

	return _approach(HexPathfinderScript.path_to(search, target))


func _approach(path: Array[Vector2i], spot_cell := Vector2i(-1, -1), spot_position := Vector3.ZERO) -> Dictionary:
	return {path = path, spot_cell = spot_cell, spot_position = spot_position}


# True when the robot can work `target` from where it stands: on it (open ground, a work spot,
# or the enclosed-target fallback) or on a neighbouring tile.
func _is_working_position(target: Vector2i) -> bool:
	if player_unit == null or target == Vector2i(-1, -1):
		return false
	var cell := player_unit.current_cell
	# On or beside any tile of the target building, however many tiles it covers.
	var target_cells: Array[Vector2i] = [target]
	if current_island.has_building(target):
		target_cells = current_island.get_building_footprint_cells(current_island.get_building_anchor_cell(target))
	for target_cell in target_cells:
		if cell == target_cell or HexGridScript.neighbors(target_cell).has(cell):
			return true
	return false


# Placement veto (IslandRenderer.is_cell_occupied_by_unit): the robot's and K9-DA's cells,
# including the ones they're stepping into.
func _is_unit_cell(cell: Vector2i) -> bool:
	if player_unit != null and (cell == player_unit.current_cell or cell == player_unit.next_cell()):
		return true
	if dog != null and dog.visible and dog.renderer == renderer:
		return cell == dog.current_cell or cell == dog.next_cell()
	return false


# Construction changed the map: re-plan a moving robot's approach from the cell it's stepping
# into, so it never ends up parked on a building placed where it was heading (walking through
# one on the way is fine). The last leg into a work spot stays inside the building's own tile.
func _reroute_unit() -> void:
	if player_unit == null or not player_unit.is_moving() or pending_action_cell == Vector2i(-1, -1):
		return
	if player_unit.is_at_spot():
		return

	var plan := _plan_approach(pending_action_cell, player_unit.next_cell())
	if not plan.is_empty():
		player_unit.reroute(plan.path, plan.spot_cell, plan.spot_position)


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


func _on_unit_arrived(_cell: Vector2i) -> void:
	var target := pending_action_cell
	if target == Vector2i(-1, -1):
		return

	pending_action_cell = Vector2i(-1, -1)
	if _is_working_position(target):
		harvestable_cell = target if current_island.get_resource_node_type(target) != -1 else Vector2i(-1, -1)
		operable_cell = target if _building_consumes_power(target) else Vector2i(-1, -1)
		if player_unit.is_at_spot():
			player_unit.face_toward(renderer.get_cell_center(target))
		elif target != player_unit.current_cell:
			player_unit.face_toward(renderer.get_cell_center(target), WORK_LEAN_TILES)
		_start_action_at(target)
	_refresh_action_bar()


# The robot was sent to `target` and can work it from here: start the work right away (what the
# green hover promised, see _is_actionable_cell). Work already under way there is left running.
func _start_action_at(target: Vector2i) -> void:
	var can_harvest := quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.HARVESTING)
	if harvestable_cell == target and not is_harvesting and can_harvest:
		_on_harvest_pressed()
	elif operable_cell == target and not is_operating:
		_on_operate_pressed()
	elif _can_rescue_dog() and target == world.dog_cell:
		_on_rescue_pressed()


# True for a cell the selected robot would start working on if right-clicked: a resource node
# once harvesting is unlocked, a building that draws power, or the stranded K9-DA. The hover
# tints it green (IslandRenderer.is_cell_actionable). Not while placing or moving a building,
# where the right-click cancels instead.
func _is_actionable_cell(cell: Vector2i) -> bool:
	if player_unit == null or not player_unit.selected or current_island == null:
		return false
	if selected_building_type != NO_BUILDING:
		return false
	if current_island.get_resource_node_type(cell) != -1:
		return quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.HARVESTING)
	if _building_consumes_power(cell):
		return true
	return world.is_dog_stranded_on(world.current_coord) and cell == world.dog_cell


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
		var rescue := _rescue_action()
		if not rescue.is_empty():
			actions.append(rescue)

	action_bar.set_actions(actions)
	action_bar.set_selected(player_unit != null and player_unit.selected)
	# Selection and unlocks change which cells the hover tints green.
	if renderer != null:
		renderer.refresh_hover()


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

	if harvestable_cell == Vector2i(-1, -1) or not _is_working_position(harvestable_cell):
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
	if operable_cell == Vector2i(-1, -1) or not _is_working_position(operable_cell):
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


# Offered while the robot is parked on or right beside the stranded K9-DA.
func _rescue_action() -> Dictionary:
	if not _can_rescue_dog():
		return {}

	return {id = UnitAction.RESCUE, icon = PAW_ICON, label = "Rescue K9-DA", active = false}


func _can_rescue_dog() -> bool:
	if not world.is_dog_stranded_on(world.current_coord):
		return false

	var robot_cell := player_unit.current_cell
	return robot_cell == world.dog_cell or HexGridScript.neighbors(world.dog_cell).has(robot_cell)


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
		UnitAction.RESCUE:
			_on_rescue_pressed()


# Bring K9-DA aboard: it starts following the robot, and the DOG_RESCUED stat completes the MAIN
# quest (whose completion toasts and saves). dog_rescued is set first so that save records it.
func _on_rescue_pressed() -> void:
	if not _can_rescue_dog():
		return

	world.dog_rescued = true
	dog.follow(current_island, dog.current_cell, player_unit)
	dog.celebrate()
	_spawn_floating_text(dog.position, "K9-DA rescued!", Color(1.0, 0.85, 0.45), 26)
	world_view.set_current_coord(world.current_coord)
	stat_tracker.add(GameTypes.Stat.DOG_RESCUED, 1)
	_refresh_action_bar()
	_save_game()


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
	# Trees are chopped with the axe; stone, ore and coal are mined with the pickaxe.
	player_unit.set_work("chop" if harvest_resource_type == GameTypes.ResourceType.WOOD else "mine")
	_refresh_action_bar()


func _stop_harvesting() -> void:
	if not is_harvesting:
		return

	is_harvesting = false
	harvest_cell = Vector2i(-1, -1)
	harvest_resource_type = -1
	_harvest_accum = 0.0
	if player_unit != null:
		player_unit.set_work("")


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
	# Stop if the robot is no longer parked where it can work the node it was harvesting.
	if (
		player_unit == null
		or player_unit.is_moving()
		or not _is_working_position(harvest_cell)
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


# Production counts toward lifetime stats on every island; the floating "+N" only shows for the
# island on screen. Away islands don't touch the ResourceManager facade, so mark the autosave
# dirty here too.
func _on_building_produced(island: IslandData, anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	stat_tracker.record_resource_gained(resource_type, amount)
	_autosave_dirty = true
	if island == current_island:
		_spawn_resource_floating_text(renderer.get_cell_center(anchor_cell), resource_type, "+%d" % amount, 16)


func _on_fuel_consumed(island: IslandData, anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	# Away inventories do not emit through ResourceManager; fuel still needs the save backstop.
	_autosave_dirty = true
	if island == current_island:
		_spawn_resource_floating_text(renderer.get_cell_center(anchor_cell), resource_type, "-%d" % amount, 16)


func _on_input_consumed(island: IslandData, anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	if island == current_island:
		_spawn_resource_floating_text(renderer.get_cell_center(anchor_cell), resource_type, "-%d" % amount, 16)


func _on_trade_route_created(_route: TradeRoute) -> void:
	stat_tracker.add(GameTypes.Stat.TRADE_ROUTES_ESTABLISHED, 1)
	world_view.refresh()
	_save_game()


func _on_trade_route_removed(_route: TradeRoute) -> void:
	world_view.refresh()
	_save_game()


# A boat unloaded. Count it toward the shipping stat, and pop a "+N" over a dock when it's the
# island on screen.
func _on_trade_cargo_delivered(_route: TradeRoute, coord: Vector2i, resource_type: int, amount: int) -> void:
	stat_tracker.add(GameTypes.Stat.GOODS_SHIPPED, amount)
	_autosave_dirty = true
	if coord != world.current_coord:
		return
	for anchor_cell in current_island.buildings:
		if current_island.buildings[anchor_cell].type == GameTypes.BuildingType.DOCK:
			_spawn_resource_floating_text(renderer.get_cell_center(anchor_cell), resource_type, "+%d" % amount, 18)
			return


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
	_reroute_unit()

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


# Generate every slot on the disc that doesn't exist yet. The whole archipelago is one world, so
# islands exist from the start (hidden under clouds until their ring is revealed); this also
# fills in slots an older save never generated, and new ones when the disc grows.
func _ensure_world_generated() -> void:
	for coord in world.all_slots():
		if not world.has_island(coord):
			_generate_island_at(coord)


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


# Cycle through already-visited islands in generation order (wrapping). Islands
# persist, so a revisited island keeps the buildings placed on it. No-op until a
# second island has been visited.
func _switch_to_adjacent_island(direction: int) -> void:
	var coords := world.visited_coords()
	if coords.size() <= 1:
		return

	var index := coords.find(world.current_coord)
	var next_coord: Vector2i = coords[(index + direction + coords.size()) % coords.size()]
	_switch_to_island(next_coord)


# A left click on another island travels there; in the overview, picking any revealed island
# (the current one included) also zooms back down into it. Returns true if the click was used.
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

	if coord != world.current_coord:
		_switch_to_island(coord)
	elif not in_overview:
		return false

	if in_overview:
		camera_rig.exit_overview()
	return true


# Make the island at `coord` the one the robot, resource bar and build tools work on. Every
# island is always on screen in the shared world, so this hands the robot to that island's
# renderer and glides the camera across (`instant` jumps there, for startup).
func _switch_to_island(coord: Vector2i, instant := false) -> void:
	var next_renderer := world_view.renderer_for(coord)
	if next_renderer == null:
		return

	# Restore any building mid-move onto the island we are leaving (still current here), so it
	# isn't orphaned when current_island changes.
	_cancel_building_move()

	# Release the wheel on the island we are leaving, while it is still current,
	# so its manual generator is not left flagged as running.
	_stop_operating()

	if not world.set_current(coord):
		return

	if renderer != null and renderer != next_renderer:
		renderer.clear_interaction()
	renderer = next_renderer
	renderer.is_cell_occupied_by_unit = _is_unit_cell
	renderer.is_cell_actionable = _is_actionable_cell
	current_island = world.get_current()
	# Landing on an island for the first time counts as discovering it. On K9-DA's island, point
	# the player at the dog — the rescue itself is the robot's Rescue action beside it.
	if not current_island.visited:
		current_island.visited = true
		if coord != WorldData.CENTER:
			stat_tracker.add(GameTypes.Stat.ISLANDS_REACHED, 1)
		if world.is_dog_stranded_on(coord):
			toast.show_message("K9-DA is here! Walk the robot over to him and press Rescue.")
	resource_manager.set_inventory(current_island.inventory)
	building_menu.refresh_stock()
	building_info_panel.hide_info()
	player_unit.setup(renderer)
	_spawn_player_unit()
	_sync_dog()
	resource_bar.refresh()
	world_view.set_current_coord(coord)
	_apply_selected_building()
	camera_rig.center_on(renderer.get_map_center(), instant)

	# Autosave at each settled island state — the natural checkpoint, and it also writes the
	# initial save for a brand-new game (the starter island is entered through here too).
	_save_game()


func _spawn_player_unit() -> void:
	if player_unit == null:
		return

	_stop_harvesting()
	_stop_operating()
	pending_action_cell = Vector2i(-1, -1)
	harvestable_cell = Vector2i(-1, -1)
	operable_cell = Vector2i(-1, -1)
	player_unit.place_at(_find_unit_spawn_cell(current_island))
	_refresh_action_bar()


func _find_unit_spawn_cell(island: IslandData) -> Vector2i:
	var crashed_spaceship_cell := _find_crashed_spaceship_cell(island)
	if crashed_spaceship_cell != Vector2i(-1, -1):
		for neighbor in HexGridScript.neighbors(crashed_spaceship_cell):
			if HexPathfinderScript.is_open(island, neighbor) and not island.has_item(neighbor):
				return neighbor

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			if _is_open_ground(island, cell):
				return cell

	return Vector2i.ZERO


# Walkable land with nothing on it — somewhere a unit can stand without overlapping anything.
func _is_open_ground(island: IslandData, cell: Vector2i) -> bool:
	return HexPathfinderScript.is_open(island, cell) and not island.has_item(cell)


func _find_crashed_spaceship_cell(island: IslandData) -> Vector2i:
	for cell in island.buildings.keys():
		if island.buildings[cell].type == GameTypes.BuildingType.CRASHED_SPACESHIP:
			return cell

	return Vector2i(-1, -1)


# --- K9-DA ---

# Give the world its stranded dog: a ring-1 island (from the seed) and a spot on it. Runs on every
# start, so it also fills in saves from before the rescue existed — and if such a save already
# completed the old "reach any island" rescue quest, K9-DA counts as rescued rather than undoing it.
func _ensure_dog_placed() -> void:
	if world.dog_coord == WorldData.NO_COORD or not world.has_island(world.dog_coord):
		world.dog_coord = WorldData.dog_slot_for_seed(seed_value)
		world.dog_cell = Vector2i(-1, -1)
		world.dog_rescued = quest_manager.is_completed(GameTypes.QuestId.RESCUE_THE_DOG)

	if world.dog_cell == Vector2i(-1, -1):
		world.dog_cell = _choose_dog_cell(world.get_island(world.dog_coord), _island_seed(world.dog_coord))


# A cell the robot can walk to from where it lands, a few steps in so the player sees the dog on
# arrival and takes a short walk to reach it. Deterministic per island (seeded), so a world is
# stable across runs.
func _choose_dog_cell(island: IslandData, island_seed: int) -> Vector2i:
	const MIN_STEPS := 3
	const MAX_STEPS := 7
	var start := _find_unit_spawn_cell(island)
	# Breadth-first distances over walkable land from the robot's landing cell.
	var steps := {start: 0}
	var frontier: Array[Vector2i] = [start]
	var head := 0
	while head < frontier.size():
		var cell := frontier[head]
		head += 1
		for neighbor in HexGridScript.neighbors(cell):
			if not steps.has(neighbor) and HexPathfinderScript.is_walkable(island, neighbor):
				steps[neighbor] = steps[cell] + 1
				frontier.append(neighbor)

	var preferred: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []
	for cell in steps:
		if cell == start or not _is_open_ground(island, cell):
			continue
		if steps[cell] >= MIN_STEPS and steps[cell] <= MAX_STEPS:
			preferred.append(cell)
		else:
			fallback.append(cell)

	var candidates := preferred if not preferred.is_empty() else fallback
	if candidates.is_empty():
		return start

	var rng := RandomNumberGenerator.new()
	rng.seed = island_seed
	return candidates[rng.randi_range(0, candidates.size() - 1)]


# Put K9-DA where the rescue state says: beside the robot once rescued; otherwise waiting at its
# spot, but only once its island has been landed on (unexplored islands show no detail).
func _sync_dog() -> void:
	if world.dog_rescued:
		dog.setup(renderer)
		dog.follow(current_island, _find_dog_follow_cell(), player_unit)
		return

	var dog_island := world.get_island(world.dog_coord)
	var dog_renderer := world_view.renderer_for(world.dog_coord)
	if dog_island == null or dog_renderer == null or not dog_island.visited:
		dog.halt()
		return

	dog.setup(dog_renderer)
	dog.strand(dog_island, world.dog_cell)


# Where the rescued dog appears when the robot lands: an open cell beside the robot.
func _find_dog_follow_cell() -> Vector2i:
	for neighbor in HexGridScript.neighbors(player_unit.current_cell):
		if _is_open_ground(current_island, neighbor):
			return neighbor
	return player_unit.current_cell


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

	is_moving_building = true
	moving_from_cell = anchor_cell
	moving_building_type = building_type
	moving_rotation = island.get_building_rotation(anchor_cell)
	# Pick it up as it stands: the preview starts at its current turn.
	renderer.placement_rotation = moving_rotation
	# Take it off the map now so its old footprint stops drawing and stops feeding adjacency
	# (to itself in the preview, and to its neighbours) while the player picks a new spot.
	renderer.remove_building(anchor_cell)
	selected_building_type = building_type
	_apply_selected_building()


func _try_finish_move() -> void:
	# The building is already lifted off the map, so just drop it at the hovered cell. On an
	# illegal target (occupied / wrong terrain) placement fails and we stay in move mode.
	if not renderer.try_place_hovered_building(moving_building_type):
		return
	_reroute_unit()

	if _placement_player != null:
		_placement_player.play()

	# Clear move state BEFORE clear_selection so its _select_no_building doesn't try to restore
	# the building we just successfully placed.
	is_moving_building = false
	moving_from_cell = Vector2i(-1, -1)
	moving_building_type = NO_BUILDING
	building_menu.clear_selection()
	_save_game()


# Put the lifted building back at its original cell and leave move mode. A no-op when no move is
# in progress, so it's safe to call from every cancel path.
func _cancel_building_move() -> void:
	if not is_moving_building:
		return

	is_moving_building = false
	var from := moving_from_cell
	var building_type := moving_building_type
	moving_from_cell = Vector2i(-1, -1)
	moving_building_type = NO_BUILDING

	if current_island != null and from != Vector2i(-1, -1):
		renderer.place_building_at(from, building_type, moving_rotation)


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
