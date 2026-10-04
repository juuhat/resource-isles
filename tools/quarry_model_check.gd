extends SceneTree

# Godot --headless --path . --script res://tools/quarry_model_check.gd
# Checks imported geometry, robot docking and the renderer's powered motion wiring.

func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var manager := BuildingManager.new()
	var definition := manager.get_definition(GameTypes.BuildingType.QUARRY)
	assert(definition.true_tile_model, "Docking needs fixed tile scale")
	var model := definition.model.instantiate() as Node3D
	root.add_child(model)
	var spot := model.find_child("WorkSpot", true, false) as Node3D
	var dock := model.find_child("DockPoint", true, false) as Node3D
	assert(spot != null and dock != null)
	var offset := dock.global_position - spot.global_position
	assert(offset.distance_to(Vector3(.2175, .40, -.20)) < .01,
		"Socket must meet the operating robot's right forearm")
	var bounds := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var local_bounds := model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = local_bounds if first else bounds.merge(local_bounds)
		first = false
	assert(bounds.position.y >= -.001, "Feet rest on the tile")
	assert(bounds.size.x < 1.7 and bounds.size.z < 1.5, "Leave room on a single tile")
	assert(bounds.end.z < spot.position.z - .18, "Operator body clears the machine")

	var island := IslandData.new(1, 1)
	island.buildings[Vector2i.ZERO] = {type = GameTypes.BuildingType.QUARRY}
	var renderer := IslandRenderer.new()
	renderer.island = island
	renderer._add_powered_spinner(Vector2i.ZERO, model)
	var spinner := model.get_child(model.get_child_count() - 1) as PoweredSpinner
	assert(spinner != null and spinner._targets.size() == 4,
		"Renderer wires the drill, pulley, flywheel and socket")
	spinner.set_process(false)
	var initial: Array[Basis] = []
	for target in spinner._targets:
		initial.append(target.basis)
	spinner._process(.1)
	for i in initial.size():
		assert(spinner._targets[i].basis.is_equal_approx(initial[i]), "Unpowered parts stay still")
	island.consumer_powered_states[Vector2i.ZERO] = true
	spinner._process(.1)
	for i in initial.size():
		assert(not spinner._targets[i].basis.is_equal_approx(initial[i]), "Powered parts turn")
	assert(dock.global_position.distance_to(spot.global_position + offset) < .001,
		"Spinning the mechanism must not move the docking point")
	island.consumer_powered_states[Vector2i.ZERO] = false
	spinner._process(2.0)
	var stopped := spinner._targets[0].basis
	spinner._process(.1)
	assert(spinner._targets[0].basis.is_equal_approx(stopped), "Drill stops after coasting down")
	print("Quarry bounds ", bounds, " socket offset ", offset)
	print("QUARRY MODEL CHECK OK")
	renderer.free()
	model.free()
	quit()
