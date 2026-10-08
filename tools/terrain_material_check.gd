extends SceneTree

# Interaction/discovery regression for shared terrain materials, without loading a game/save.

const CheckWatchdog := preload("res://tools/check_watchdog.gd")

var _failures := 0


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_run")


func _run() -> void:
	var island := IslandData.new(5, 3)
	var grass := Vector2i(1, 1)
	var neighbour := Vector2i(2, 1)
	var sand := Vector2i(0, 1)
	var stone := Vector2i(3, 1)
	var coast := Vector2i(4, 1)
	for cell in [grass, neighbour]:
		island.set_terrain(cell, GameTypes.Terrain.GRASS)
	island.set_terrain(sand, GameTypes.Terrain.SAND)
	island.set_terrain(stone, GameTypes.Terrain.STONE)
	island.set_terrain(coast, GameTypes.Terrain.COAST)
	var saved_data := var_to_bytes(island.to_dict(0.0))
	var renderer := IslandRenderer.new()
	root.add_child(renderer)
	renderer.position = Vector3(-640.0, 0.0, -960.0)
	renderer.render(island)
	var tile: MeshInstance3D = renderer._tiles[grass]
	var other: MeshInstance3D = renderer._tiles[neighbour]
	var shared := tile.material_override
	_expect(shared == other.material_override, "Adjacent grass tiles share one material")
	_expect(shared is ShaderMaterial, "Terrain uses the shared shader")
	for cell in [grass, sand, stone, coast]:
		var center := renderer.get_cell_center(cell)
		_expect(renderer.cell_from_ray(center + Vector3.UP * 1000.0, Vector3.DOWN) == cell,
			"Picking matches surface height for cell %s" % cell)

	renderer.set_hovered_cell(grass)
	_expect(tile.get_instance_shader_parameter("hover_state") == 1, "Ordinary hover brightens only its tile")
	_expect(other.get_instance_shader_parameter("hover_state") == 0, "Hover does not leak to a shared-material neighbour")
	_expect(tile.material_override == shared, "Hover keeps the material")
	renderer.is_cell_actionable = func(cell: Vector2i) -> bool: return cell == grass
	renderer.refresh_hover()
	_expect(tile.get_instance_shader_parameter("hover_state") == 2, "Action hover updates without moving the cursor")
	renderer.set_hovered_cell(neighbour)
	_expect(tile.get_instance_shader_parameter("hover_state") == 0, "Moving hover restores the previous tile")
	_expect(other.get_instance_shader_parameter("hover_state") == 1, "New target gets ordinary hover")
	renderer.set_hovered_cell(coast)
	_expect(renderer._tiles[coast].get_instance_shader_parameter("hover_state") == 1, "Shallow coast remains hoverable")
	renderer.clear_interaction()
	_expect(renderer._tiles[coast].get_instance_shader_parameter("hover_state") == 0, "Clearing restores the seabed")

	var grid := renderer._grid_instance.material_override as StandardMaterial3D
	var idle_alpha := grid.albedo_color.a
	renderer.set_placement_preview(true)
	_expect(grid.albedo_color.a > idle_alpha, "Placement strengthens the grid")
	renderer.set_show_grid(false)
	_expect(not renderer._grid_instance.visible, "Placement respects the user's grid toggle")
	renderer.clear_interaction()
	_expect(is_equal_approx(grid.albedo_color.a, idle_alpha), "Cancelling placement restores the quiet grid")
	renderer.set_show_grid(true)
	renderer.set_hovered_cell(grass)
	renderer.set_explored(false)
	_expect(tile.material_override == shared, "Discovery does not swap materials")
	_expect(tile.get_instance_shader_parameter("explored") == false, "Unexplored ground uses a silhouette")
	_expect(tile.get_instance_shader_parameter("hover_state") == 0, "Hiding an island clears interaction")
	_expect(not renderer._tiles[coast].visible and not renderer._water_instance.visible, "Discovery hides coast and water detail")
	_expect(not renderer._grid_instance.visible and not renderer._objects_root.visible, "Discovery hides plots and objects")
	renderer.set_hovered_cell(grass)
	_expect(tile.get_instance_shader_parameter("hover_state") == 0, "Unexplored cells cannot be highlighted")
	renderer.render(island)
	tile = renderer._tiles[grass]
	_expect(tile.get_instance_shader_parameter("explored") == false, "Rebuilding preserves discovery state")
	renderer.set_explored(true)
	_expect(tile.get_instance_shader_parameter("explored") == true, "Discovery restores the surface shader")
	_expect(renderer._tiles[coast].visible and renderer._water_instance.visible, "Discovery restores shoreline rendering")
	_expect(renderer._grid_instance.visible and renderer._objects_root.visible, "Discovery restores enabled plots and objects")
	_expect(var_to_bytes(island.to_dict(0.0)) == saved_data, "Visual state never changes saved island data")
	renderer.free()
	_check_elevation()
	print("Terrain material: PASS" if _failures == 0 else "Terrain material: FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


# Cells with their own elevation (IslandData.get_elevation): a raised grass cliff beside a beach.
func _check_elevation() -> void:
	var island := IslandData.new(6, 3)
	var beach := Vector2i(1, 1)
	var cliff := Vector2i(2, 1)
	var behind := Vector2i(3, 1)
	var low := Vector2i(4, 1)
	island.set_terrain(beach, GameTypes.Terrain.SAND)
	for cell in [cliff, behind, low]:
		island.set_terrain(cell, GameTypes.Terrain.GRASS)
	_expect(island.get_elevation(beach) == 0 and island.get_elevation(low) == 1, "Ground stands at its usual level by default")
	island.set_elevation(cliff, 5)
	island.set_elevation(behind, 5)
	island.set_elevation(Vector2i(0, 0), 3)
	_expect(island.get_elevation(cliff) == 5 and not island.elevation.has(Vector2i(0, 0)), "Only land takes an elevation")
	island.set_elevation(behind, 99)
	_expect(island.get_elevation(behind) == IslandData.MAX_ELEVATION, "Elevation stops at the highest level")
	island.set_elevation(behind, 5)
	var loaded := IslandData.from_dict(bytes_to_var(var_to_bytes(island.to_dict(0.0))), 0.0)
	_expect(loaded.get_elevation(cliff) == 5 and loaded.get_elevation(low) == 1, "Elevation survives a save")
	var old_save := island.to_dict(0.0)
	old_save.erase("elevation")
	_expect(IslandData.from_dict(old_save, 0.0).get_elevation(cliff) == 1, "An older save keeps its usual heights")

	var two_tiles: Array[Vector2i] = [cliff, behind]
	var across: Array[Vector2i] = [behind, low]
	var grass: Array[int] = [GameTypes.Terrain.GRASS]
	_expect(island.can_place_building(cliff, two_tiles, grass), "A footprint fits on level ground")
	_expect(not island.can_place_building(behind, across, grass), "A footprint can't straddle a cliff")

	var renderer := IslandRenderer.new()
	root.add_child(renderer)
	renderer.render(island)
	var top := renderer.get_cell_center(cliff).y
	_expect(is_equal_approx(top, IslandRenderer.elevation_top_y(5)), "A raised cell's top stands at its level")
	_expect(is_equal_approx(renderer._tiles[cliff].scale.y, top), "Its tile rises to its top")
	_expect(top > renderer.get_cell_center(low).y and renderer.get_cell_center(low).y > renderer.get_cell_center(beach).y,
		"Higher levels stand higher")
	for cell in [beach, cliff, behind, low]:
		var center := renderer.get_cell_center(cell)
		_expect(renderer.cell_from_ray(center + Vector3.UP * 1000.0, Vector3.DOWN) == cell, "Picking from above finds raised cell %s" % cell)
	# Looking low over the cliff (from the west) at the low cell east of it, the cliff is in the way;
	# looking from the east, nothing is.
	var low_center := renderer.get_cell_center(low)
	var over_cliff := Vector3(1.0, -0.3, 0.0).normalized()
	_expect(renderer.cell_from_ray(low_center - over_cliff * 1000.0, over_cliff) == behind, "A cliff hides the ground behind it")
	var from_east := Vector3(-1.0, -0.3, 0.0).normalized()
	_expect(renderer.cell_from_ray(low_center - from_east * 1000.0, from_east) == low, "A low cell in front of a cliff is picked")

	# Walking up from the beach, the unit keeps to the beach until the cliff's edge, then climbs.
	var beach_center := renderer.get_cell_center(beach)
	var cliff_center := renderer.get_cell_center(cliff)
	var quarter := beach_center.lerp(cliff_center, 0.25)
	var past_edge := beach_center.lerp(cliff_center, 0.55)
	_expect(is_equal_approx(renderer.get_step_height(beach, cliff, quarter), beach_center.y), "A unit walks level across the beach")
	_expect(is_equal_approx(renderer.get_step_height(beach, cliff, past_edge), top), "It is up the cliff by its edge")
	_expect(is_equal_approx(renderer.get_step_height(cliff, beach, cliff_center.lerp(beach_center, 0.45)), top),
		"Walking down, it stays on top until the edge")
	renderer.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAILED: " + message)
