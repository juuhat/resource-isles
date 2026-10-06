extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_check")


func _check() -> void:
	var renderer := IslandRenderer.new()
	root.add_child(renderer)
	var dog := Dog.new()
	dog.setup(renderer)
	root.add_child(dog)
	CheckWatchdog.require(dog._anim_player != null, "K9-DA must import an AnimationPlayer")
	CheckWatchdog.require(dog._walk_anim != "" and dog._idle_anim != "", "Both embedded clips must import")
	CheckWatchdog.require(dog._lying_anim != "", "Stranded resting clip must import")
	CheckWatchdog.require(dog._anim_player.current_animation == dog._lying_anim, "Stranded dog lies down")
	var model := dog._model
	var head := model.find_child("HeadPivot", true, false) as Node3D
	var leg := model.find_child("FrontLeftLegPivot", true, false) as Node3D
	CheckWatchdog.require(head != null and leg != null, "Mechanical pivots must survive export")
	var bounds := dog._model_aabb()
	CheckWatchdog.require(is_equal_approx(bounds.position.y + dog._model.position.y, 0.0), "Paws fit the ground")
	CheckWatchdog.require(is_equal_approx(maxf(bounds.size.x, bounds.size.z), renderer.cell_size.x * dog.visual_size_tiles),
		"Model must fit the companion tile footprint")
	dog._anim_player.advance(0.3)
	dog._anim_player.seek(0.0, true)
	var body := model.find_child("BodyPivot", true, false) as Node3D
	var lying_height := body.position.y
	CheckWatchdog.require(absf(body.basis.y.dot(Vector3.UP)) < 0.1, "Stranded dog rests on its side")
	var lying_head := head.transform
	var lying_leg := leg.transform
	dog._anim_player.seek(1.0, true)
	CheckWatchdog.require(not head.transform.is_equal_approx(lying_head), "Resting dog gently moves its head")
	CheckWatchdog.require(body.position.y > lying_height, "Resting body gently breathes")
	dog.mode = Dog.Mode.FOLLOWING
	dog._stop_walk_anim()
	dog._anim_player.advance(0.3)
	dog._anim_player.seek(0.0, true)
	CheckWatchdog.require(body.position.y > lying_height + 0.12, "Rescued dog rises from its resting pose")
	CheckWatchdog.require(not leg.transform.is_equal_approx(lying_leg), "Rescue unfolds the resting legs")
	var head_rest := head.transform
	dog._anim_player.seek(0.75, true)
	CheckWatchdog.require(not head.transform.is_equal_approx(head_rest), "Idle scans the head")
	dog._speed = dog.move_speed
	dog._play_walk_anim()
	dog._anim_player.advance(0.2)
	dog._anim_player.seek(0.0, true)
	var leg_rest := leg.transform
	var model_rest := model.position
	dog._anim_player.seek(0.2, true)
	CheckWatchdog.require(not leg.transform.is_equal_approx(leg_rest), "Trot articulates the legs")
	CheckWatchdog.require(model.position.is_equal_approx(model_rest), "Clip must not translate the model root")
	var clip := dog._anim_player.get_animation(dog._walk_anim)
	var rate := dog._anim_player.speed_scale
	CheckWatchdog.require(is_equal_approx(Dog.WALK_CYCLE_DISTANCE * model.scale.z * rate / clip.length, dog.move_speed),
		"Trot cadence must match ground speed")
	dog._speed = dog.catch_up_speed
	dog._play_walk_anim()
	CheckWatchdog.require(dog._anim_player.speed_scale > rate, "Catch-up must increase trot cadence")
	dog._stop_walk_anim()
	CheckWatchdog.require(dog._anim_player.current_animation == dog._idle_anim, "Stopping returns to Idle")
	CheckWatchdog.require(is_equal_approx(dog._anim_player.speed_scale, 1.0), "Idle keeps its authored rate")
	dog.halt()
	CheckWatchdog.require(not dog.visible, "Halt hides the companion")
	print("K9-DA model: PASS")
	quit()
