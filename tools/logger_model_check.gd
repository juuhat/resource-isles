extends SceneTree

# Godot --headless --path . --script res://tools/logger_model_check.gd
# Checks imported geometry, robot docking and the renderer's powered motion wiring.

func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var manager := BuildingManager.new()
	var definition := manager.get_definition(GameTypes.BuildingType.LOGGER_CAMP)
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
	island.buildings[Vector2i.ZERO] = {type = GameTypes.BuildingType.LOGGER_CAMP}
	var renderer := IslandRenderer.new()
	renderer.island = island
	renderer._add_powered_spinner(Vector2i.ZERO, model)
	var spinner := model.get_child(model.get_child_count() - 1) as PoweredSpinner
	assert(spinner != null and spinner._targets.size() == 3 and spinner._sweeps.size() == 1,
		"Renderer wires the forest blade, arm sweep, flywheel and socket")
	spinner.set_process(false)
	var arm := model.find_child("HarvesterArmPivot", true, false) as Node3D
	assert(arm != null and arm.get_child_count() > 0, "Boom and hydraulics stay under the swivel")
	var blade := model.find_child("ForestBladePivot", true, false) as Node3D
	assert(blade != null and blade.get_parent() == arm, "Spinning blade follows the sweeping arm")
	assert(blade.global_position.y - .012 > .39, "Blade clears the harvested log stack")
	var rest := arm.transform
	var initial: Array[Basis] = []
	for target in spinner._targets:
		initial.append(target.basis)
	spinner._process(.1)
	for i in initial.size():
		assert(spinner._targets[i].basis.is_equal_approx(initial[i]), "Unpowered parts stay still")
	assert(arm.transform.is_equal_approx(rest), "Unpowered arm stays at its authored pose")
	island.consumer_powered_states[Vector2i.ZERO] = true
	spinner._process(.1)
	for i in initial.size():
		assert(not spinner._targets[i].basis.is_equal_approx(initial[i]), "Powered parts turn")
	assert(not arm.transform.is_equal_approx(rest), "Powered arm sweeps")
	# Run through several full cycles: bounded motion must not accumulate rotation or
	# drag the machine's fixed socket around with the arm.
	for frame in 600:
		spinner._process(.02)
		assert(absf(arm.rotation.y) <= deg_to_rad(24.01), "Cutter stays within its work area")
		assert(arm.position.is_equal_approx(rest.origin), "Swivel base stays planted")
		assert(blade.global_position.x + .255 < -.08,
			"Sweeping blade clears the generator")
		var blade_xz := Vector2(blade.global_position.x, blade.global_position.z)
		var operator_edge := Vector2(clampf(blade_xz.x, -.22, .22), clampf(blade_xz.y, .44, .76))
		assert(blade_xz.distance_to(operator_edge) > .275, "Sweep clears the operator's body")
	assert(dock.global_position.distance_to(spot.global_position + offset) < .001,
		"Spinning the mechanism must not move the docking point")
	island.consumer_powered_states[Vector2i.ZERO] = false
	spinner._process(2.0)
	var stopped := spinner._targets[0].basis
	var stopped_arm := arm.transform
	spinner._process(.1)
	assert(spinner._targets[0].basis.is_equal_approx(stopped), "Generator stops after coasting down")
	assert(arm.transform.is_equal_approx(stopped_arm), "Harvester stops after coasting down")
	print("Logger bounds ", bounds, " socket offset ", offset)
	print("LOGGER_CAMP MODEL CHECK OK")
	renderer.free()
	model.free()
	quit()

