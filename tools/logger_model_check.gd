extends SceneTree

# Godot --headless --path . --script res://tools/logger_model_check.gd
# Checks imported geometry, robot docking and the renderer's powered chop wiring.

# Top of the round on the chopping block, in model units (tools/build_logger_camp.py).

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const ROUND_TOP := .452


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_check")


func _check() -> void:
	var manager := BuildingManager.new()
	var definition := manager.get_definition(GameTypes.BuildingType.LOGGER_CAMP)
	CheckWatchdog.require(definition.true_tile_model, "Docking needs fixed tile scale")
	var model := definition.model.instantiate() as Node3D
	root.add_child(model)
	var spot := model.find_child("WorkSpot", true, false) as Node3D
	var dock := model.find_child("DockPoint", true, false) as Node3D
	CheckWatchdog.require(spot != null and dock != null)
	var offset := dock.global_position - spot.global_position
	CheckWatchdog.require(offset.distance_to(Vector3(.2175, .40, -.20)) < .01,
		"Socket must meet the operating robot's right forearm")
	var bounds := _bounds(model, model.find_children("*", "MeshInstance3D", true, false))
	CheckWatchdog.require(bounds.position.y >= -.001, "Feet rest on the tile")
	CheckWatchdog.require(bounds.size.x < 1.7 and bounds.size.z < 1.5, "Leave room on a single tile")
	CheckWatchdog.require(bounds.end.z < spot.position.z - .18, "Operator body clears the machine")

	var island := IslandData.new(1, 1)
	island.buildings[Vector2i.ZERO] = {type = GameTypes.BuildingType.LOGGER_CAMP}
	var renderer := IslandRenderer.new()
	renderer.island = island
	renderer._add_powered_spinner(Vector2i.ZERO, model)
	var spinner := model.get_child(model.get_child_count() - 1) as PoweredSpinner
	CheckWatchdog.require(spinner != null and spinner._targets.size() == 4 and spinner._chops.size() == 1,
		"Renderer wires the axe stroke, cam, pulley, flywheel and socket")
	spinner.set_process(false)
	var helve := model.find_child("AxeHelvePivot", true, false) as Node3D
	var cam := model.find_child("AxeCamPivot", true, false) as Node3D
	CheckWatchdog.require(helve != null and helve.get_child_count() > 0, "Helve and head stay under the fulcrum")
	CheckWatchdog.require(cam != null)
	var head: Array[Node] = helve.find_children("*Steel*", "MeshInstance3D", true, false)
	head.append_array(helve.find_children("*Iron*", "MeshInstance3D", true, false))
	var generator := _bounds(model, model.find_child("SharedGenerator", true, false).find_children("*", "MeshInstance3D", true, false))
	var rest := helve.transform
	CheckWatchdog.require(_bounds(model, head).position.y > ROUND_TOP + .1, "An idle camp holds the axe raised")

	var initial: Array[Basis] = []
	for target in spinner._targets:
		initial.append(target.basis)
	spinner._process(.1)
	for i in initial.size():
		CheckWatchdog.require(spinner._targets[i].basis.is_equal_approx(initial[i]), "Unpowered parts stay still")
	CheckWatchdog.require(helve.transform.is_equal_approx(rest), "Unpowered axe stays raised")
	island.consumer_powered_states[Vector2i.ZERO] = true
	spinner._process(.1)
	for i in initial.size():
		CheckWatchdog.require(not spinner._targets[i].basis.is_equal_approx(initial[i]), "Powered parts turn")
	CheckWatchdog.require(not helve.transform.is_equal_approx(rest), "Powered axe starts its stroke")

	# Several full strokes: the stroke stays bounded, the blade bites the round without
	# passing through it, the head never swings into the generator, and the cam keeps time.
	var lowest := INF
	for frame in 400:
		spinner._process(.02)
		var drop := rest.basis.inverse() * helve.basis
		var angle := drop.get_euler().z
		CheckWatchdog.require(angle <= .001 and angle >= -deg_to_rad(IslandRenderer.AXE_STRIKE_DEGREES) - .001,
			"Axe moves only between raised and striking")
		CheckWatchdog.require(helve.position.is_equal_approx(rest.origin), "Fulcrum stays planted")
		var head_bounds := _bounds(model, head)
		lowest = minf(lowest, head_bounds.position.y)
		CheckWatchdog.require(not head_bounds.intersects(generator), "Axe head clears the generator")
		var phase := float(spinner._chops[0].phase)
		var cam_turn := fposmod(cam.rotation.z, PI)
		CheckWatchdog.require(absf(angle_difference(cam_turn, phase * PI)) < .01 or absf(angle_difference(cam_turn, phase * PI)) > PI - .01,
			"Cam turns half a revolution per stroke, in step")
	CheckWatchdog.require(lowest < ROUND_TOP and lowest > ROUND_TOP - .02, "Blade bites into the round (lowest %.3f)" % lowest)
	CheckWatchdog.require(dock.global_position.distance_to(spot.global_position + offset) < .001,
		"Running the mechanism must not move the docking point")

	island.consumer_powered_states[Vector2i.ZERO] = false
	spinner._process(2.0)
	var stopped := spinner._targets[0].basis
	var stopped_helve := helve.transform
	spinner._process(.1)
	CheckWatchdog.require(spinner._targets[0].basis.is_equal_approx(stopped), "Machine stops after coasting down")
	CheckWatchdog.require(helve.transform.is_equal_approx(stopped_helve), "Axe stops after coasting down")
	print("Logger bounds ", bounds, " socket offset ", offset, " blade low ", lowest)
	print("LOGGER_CAMP MODEL CHECK OK")
	renderer.free()
	model.free()
	quit()


# Exact bounds from the vertices: a rotated part's transformed AABB would overstate its reach.
func _bounds(model: Node3D, meshes: Array) -> AABB:
	var result := AABB()
	var first := true
	for node in meshes:
		var mesh := node as MeshInstance3D
		var to_model := model.global_transform.affine_inverse() * mesh.global_transform
		for vertex in mesh.mesh.get_faces():
			var point := to_model * vertex
			result = AABB(point, Vector3.ZERO) if first else result.expand(point)
			first = false
	return result
