extends SceneTree


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var asset := load("res://assets/models/parts/shared_generator.glb") as PackedScene
	assert(asset != null, "Generator GLB must import as a PackedScene")
	var model := asset.instantiate() as Node3D
	root.add_child(model)
	var socket := model.find_child("SocketRotor", true, false) as Node3D
	var wheel := model.find_child("FlywheelPivot", true, false) as Node3D
	var dock := model.find_child("DockPoint", true, false) as Node3D
	var output := model.find_child("OutputShaft", true, false) as Node3D
	assert(socket != null and wheel != null and dock != null and output != null,
		"Generator must preserve separate pivots and placement markers")
	assert(dock.position.is_equal_approx(Vector3(0, 0.25, 0.265)), "Dock position and front axis")
	assert(output.position.is_equal_approx(Vector3(0.43, 0.25, -0.015)), "Output shaft placement")
	var mesh_count := 0
	var bounds := AABB()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var local_bounds := model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = local_bounds if mesh_count == 0 else bounds.merge(local_bounds)
		mesh_count += 1
	assert(mesh_count == 9, "Keep nine material/parent groups")
	print("Generator bounds: ", bounds)
	assert(bounds.size.is_equal_approx(Vector3(0.71, 0.47, 0.5)), "Part stays at native tile scale")
	var dock_rest := dock.global_transform
	var socket_mesh := socket.get_child(0) as Node3D
	var wheel_mesh := wheel.get_child(0) as Node3D
	var socket_rest := socket_mesh.global_transform
	var wheel_rest := wheel_mesh.global_transform
	wheel.rotate_x(0.4)
	socket.rotate_z(0.4)
	assert(not wheel_mesh.global_transform.is_equal_approx(wheel_rest), "Flywheel rotates around axle")
	assert(not socket_mesh.global_transform.is_equal_approx(socket_rest), "Socket sleeve can rotate independently")
	assert(dock.global_transform.is_equal_approx(dock_rest), "Docking marker stays stationary")
	print("SHARED_GENERATOR_CHECK passed: 9 meshes, native bounds, independent pivots, stable dock")
	model.queue_free()
	quit()
