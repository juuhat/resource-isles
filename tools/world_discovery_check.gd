extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_check_discovery")


func _check_discovery() -> void:
	var world := WorldData.new()
	for coord in world.all_slots():
		var island := IslandData.new(3, 3)
		island.set_terrain(Vector2i(1, 1), GameTypes.Terrain.GRASS)
		world.add_island(coord, island)
	world.get_current().visited = true
	var navigation := WorldNavigation.new()
	navigation.setup(world)
	var view := WorldView.new()
	view.setup(world, null, null, navigation)
	root.add_child(view)
	view.refresh()
	view.set_overview_amount(1.0)
	var frontier: Vector2i = world.slots_within(1)[1]
	CheckWatchdog.require(view.renderer_for(frontier) == null, "Locked islands must remain hidden")
	CheckWatchdog.require(view.is_uncharted(frontier), "Locked islands lie under the chart")
	CheckWatchdog.require(view._labels[frontier].text == "?", "Locked islands need an unknown marker")
	world.reveal_additional_rings()
	view.refresh()
	var renderer := view.renderer_for(frontier)
	CheckWatchdog.require(renderer != null, "Revealed islands must be reachable")
	CheckWatchdog.require(view.is_uncharted(frontier) and view._chart_patches.has(frontier), "Reachable islands keep a chart patch until discovered")
	CheckWatchdog.require(not renderer._objects_root.visible, "Unvisited resources must stay hidden")
	CheckWatchdog.require(not renderer._grid_instance.visible, "Unvisited islands must hide plot lines")
	view.set_show_grid(true)
	CheckWatchdog.require(not renderer._grid_instance.visible, "Grid toggle must preserve silhouette mode")
	CheckWatchdog.require(view._labels[frontier].text == "Unexplored", "Unvisited islands need a travel label")
	view.set_hovered(frontier)
	CheckWatchdog.require("Click to sail" in view._labels[frontier].text, "Reachable hover must explain travel")
	world.get_island(frontier).visited = true
	world.set_current(frontier)
	view.set_current_coord(frontier)
	CheckWatchdog.require(not view.is_uncharted(frontier), "Discovery starts opening the island's patch")
	CheckWatchdog.require(renderer._objects_root.visible, "Landing must restore detail")
	CheckWatchdog.require(renderer._water_instance.visible, "Landing must restore shoreline water")
	CheckWatchdog.require(renderer._grid_instance.visible, "Landing must restore enabled plot lines")
	CheckWatchdog.require(world.get_island(frontier).island_name in view._labels[frontier].text)
	await create_timer(WorldView.CHART_REVEAL_SECONDS + 0.1).timeout
	CheckWatchdog.require(not view._chart_patches.has(frontier) and not view._opening.has(frontier), "An opened patch leaves the chart")
	view.queue_free()
	await process_frame
	print("World discovery states: PASS")
	quit()
