class_name BladeSpinner
extends Node

# Spins a target node (e.g. a windmill's "Blades" sub-mesh, a separate object in the .glb)
# around a fixed local axis at a constant rate. Added as a child of a spawned building model
# so the renderer needs no per-frame loop over every building — each animated model drives
# itself and is freed with the model when the island re-renders.

var target: Node3D
var axis := Vector3(0, 0, 1)
var degrees_per_second := 45.0


func _process(delta: float) -> void:
	if target == null or axis == Vector3.ZERO:
		return
	target.rotate_object_local(axis.normalized(), deg_to_rad(degrees_per_second) * delta)
