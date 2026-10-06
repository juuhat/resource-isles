extends SceneTree


func _initialize() -> void:
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
	assert(view.renderer_for(frontier) == null, "Locked islands must remain hidden")
	assert(view.is_uncharted(frontier), "Locked islands lie under the chart")
	assert(view._labels[frontier].text == "?", "Locked islands need an unknown marker")
	world.reveal_additional_rings()
	view.refresh()
	var renderer := view.renderer_for(frontier)
	assert(renderer != null, "Revealed islands must be reachable")
	assert(view.is_uncharted(frontier) and view._chart_patches.has(frontier), "Reachable islands keep a chart patch until discovered")
	assert(not renderer._objects_root.visible, "Unvisited resources must stay hidden")
	assert(not renderer._grid_instance.visible, "Unvisited islands must hide plot lines")
	view.set_show_grid(true)
	assert(not renderer._grid_instance.visible, "Grid toggle must preserve silhouette mode")
	assert(view._labels[frontier].text == "Unexplored", "Unvisited islands need a travel label")
	view.set_hovered(frontier)
	assert("Click to sail" in view._labels[frontier].text, "Reachable hover must explain travel")
	world.get_island(frontier).visited = true
	world.set_current(frontier)
	view.set_current_coord(frontier)
	assert(not view.is_uncharted(frontier), "Discovery starts opening the island's patch")
	assert(renderer._objects_root.visible, "Landing must restore detail")
	assert(renderer._water_instance.visible, "Landing must restore shoreline water")
	assert(renderer._grid_instance.visible, "Landing must restore enabled plot lines")
	assert(world.get_island(frontier).island_name in view._labels[frontier].text)
	await create_timer(WorldView.CHART_REVEAL_SECONDS + 0.1).timeout
	assert(not view._chart_patches.has(frontier) and not view._opening.has(frontier), "An opened patch leaves the chart")
	view.queue_free()
	await process_frame
	print("World discovery states: PASS")
	quit()
