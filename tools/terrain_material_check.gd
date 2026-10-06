extends SceneTree

# Interaction/discovery regression for shared terrain materials, without loading a game/save.

var _failures := 0


func _initialize() -> void:
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
	print("Terrain material: PASS" if _failures == 0 else "Terrain material: FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAILED: " + message)
