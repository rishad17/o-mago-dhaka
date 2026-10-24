## Automated Milestone 1 test. Loads the real world scene, presses the real
## input actions and checks the rickshaw behaves.
##
## Run (from the project folder):
##   godot --path . res://tests/drive_test.tscn                      (with screenshots)
##   godot --headless --path . res://tests/drive_test.tscn           (logic only)
## Optional: -- --shots=C:/some/folder   to choose where screenshots go.
## Exit code 0 = all checks passed, 1 = something failed.
## In windowed mode, don't click away from the game window while it runs:
## Godot releases all pressed actions when the window loses focus.
extends Node

const WORLD := preload("res://scenes/main_world.tscn")
const PlayerRickshaw := preload("res://scripts/player_rickshaw.gd")

var world: Node3D
var player: PlayerRickshaw
var failures: Array[String] = []
var shots_dir := "user://test_shots"
var headless := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Default settings (and never touch the player's saved ones).
	Settings.use_defaults_for_testing()
	headless = DisplayServer.get_name() == "headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(shots_dir)
	world = WORLD.instantiate()
	# This test is about the rickshaw itself: keep traffic from crowding the test spots.
	world.get_node("TrafficController").nearby_target = 0
	# This test node always runs; the world must still obey pause like in the game.
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = world.get_node("PlayerRickshaw")
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func hold(action: String, n: int) -> void:
	Input.action_press(action)
	await frames(n)
	Input.action_release(action)


func shot(file_name: String) -> void:
	if headless:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := shots_dir.path_join(file_name)
	img.save_png(path)
	print("  shot  ", ProjectSettings.globalize_path(path))


func _place(pos: Vector3, yaw: float) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	player.velocity = Vector3.ZERO
	player.speed = 0.0
	player.reset_physics_interpolation()


func heading() -> float:
	var f := -player.global_transform.basis.z
	return atan2(-f.x, -f.z)


func _run() -> void:
	print("== Dhakar Rickshaw: Milestone 1 drive test ==")
	await frames(30)

	# Bangla helpers.
	check(GameManager.to_bangla_number(150) == "১৫০", "Bangla digits: 150 -> ১৫০")
	check(GameManager.format_taka(20) == "৳২০", "Taka format: 20 -> ৳২০")

	# Scene structure.
	check(player.get_node_or_null("Model/Body") != null, "Rickshaw body mesh built")
	check(player.get_node_or_null("Model/RearWheels") != null, "Rear wheels node exists")
	check(player.get_node_or_null("Model/Fork/FrontWheel") != null, "Front wheel is under the steering fork")
	check(player.get_passenger_seat() != null, "Passenger seat marker exists")
	check(player.is_on_floor(), "Rickshaw rests on the ground (y=%.3f)" % player.global_position.y)
	await shot("01_spawn.png")

	# Acceleration and top speed.
	var start := player.global_position
	await hold("accelerate", 240)
	var kmh := player.get_speed_kmh()
	print("  info  speed after 4 s pedalling: %.1f km/h" % kmh)
	check(kmh > 15.0 and kmh <= player.max_speed_kmh + 0.1, "Accelerates to a rickshaw-like speed")
	check(player.global_position.distance_to(start) > 10.0, "Moved forward (%.1f m)" % player.global_position.distance_to(start))
	check(player.global_position.z < start.z, "Forward is towards -Z (the way the rickshaw faces)")
	var wheels: Node3D = player.get_node("Model/RearWheels")
	var wheel_before := wheels.basis
	await frames(3)
	check(not wheels.basis.is_equal_approx(wheel_before), "Rear wheels rotate while driving")
	await shot("02_driving.png")

	# Steering: start each turn rolling north towards the open intersection,
	# from the lane on the far side so the turn has room.
	for t in [["steer_left", 4.0, 1.0, "A turns left"], ["steer_right", -4.0, -1.0, "D turns right"]]:
		_place(Vector3(t[1], 0.05, 14.0), 0.0)
		player.speed = 5.0
		var h0 := heading()
		Input.action_press("accelerate")
		await hold(t[0], 50)
		Input.action_release("accelerate")
		var turned := angle_difference(h0, heading())
		var fork_angle: float = player.get_node("Model/Fork").rotation.y
		print("  info  %s: heading change %.1f deg, fork %.1f deg, speed %.1f km/h" % [t[0], rad_to_deg(turned), rad_to_deg(fork_angle), player.get_speed_kmh()])
		check(turned * t[2] > 0.3 and fork_angle * t[2] > 0.1, t[3])
		if t[0] == "steer_left":
			await shot("03_turning.png")
	player.speed = 4.0

	# Braking.
	await hold("brake_reverse", 90)
	print("  info  speed after braking: %.2f m/s" % player.speed)
	check(player.speed <= 0.05, "S brakes to a stop")
	# Reverse.
	await hold("brake_reverse", 120)
	print("  info  reverse speed: %.2f m/s signed, pos %s, contact %.2f s ago" % [player.speed, player.global_position, player._since_contact])
	check(player.speed < -0.5 and player.get_speed_kmh() <= player.max_reverse_kmh + 0.1, "Holding S reverses slowly")
	await hold("handbrake", 40)
	check(absf(player.speed) < 0.05, "Space (handbrake) stops the rickshaw")

	# Horn.
	var horn_heard := [false]
	player.horn_pressed.connect(func(): horn_heard[0] = true)
	await hold("horn", 2)
	check(horn_heard[0], "H rings the bell")
	check(player._bell.stream != null, "Bell sound loaded")

	# Crash into a building: aim west and pedal into the block.
	player.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-4, 0.05, 30))
	player.reset_physics_interpolation()
	await frames(5)
	var crashes := []
	player.crashed.connect(func(sev, imp, _o): crashes.append([sev, imp]))
	var accidents_before := GameManager.accidents
	await hold("accelerate", 300)
	print("  info  collisions: ", crashes)
	check(crashes.size() > 0, "Hitting the sidewalk/building registers a collision")
	check(player.global_position.x > -12.5, "Rickshaw rides onto the footpath and is stopped by something solid (x=%.2f)" % player.global_position.x)
	await shot("04_after_crash.png")

	# Simulate a heavy crash event to test the accident pipeline.
	player.crashed.emit(2, 6.0, null)
	await frames(2)
	check(GameManager.accidents > accidents_before, "Heavy crash increments the accident counter")

	# Reset.
	await hold("reset_vehicle", 2)
	await frames(10)
	print("  info  after reset: speed %.3f, pos %s" % [player.speed, player.global_position])
	check(absf(player.speed) < 0.01, "R reset stops the rickshaw")
	check(player.global_transform.basis.y.dot(Vector3.UP) > 0.99, "R reset leaves the rickshaw upright")
	await hold("accelerate", 60)
	check(player.speed > 0.5, "Can drive again after reset")

	# Pause.
	GameManager.set_paused(true)
	var paused_pos := player.global_position
	Input.action_press("accelerate")
	await get_tree().create_timer(0.5, true).timeout
	Input.action_release("accelerate")
	check(player.global_position.distance_to(paused_pos) < 0.001, "Pause freezes the rickshaw")
	check(world.get_node("PauseMenu").visible, "Pause menu is shown")
	await shot("05_pause_menu.png")
	GameManager.set_paused(false)
	await frames(5)
	check(not world.get_node("PauseMenu").visible, "Pause menu hides after resume")

	# Close-up showcase shots of the rickshaw model.
	if not headless:
		player.global_transform = Transform3D(Basis(), Vector3(-4, 0.05, 40))
		player.reset_physics_interpolation()
		await frames(5)
		var cam := Camera3D.new()
		world.add_child(cam)
		cam.current = true
		for v in [["06_rear_three_quarter.png", Vector3(3.5, 2.0, 46)],
				["07_side.png", Vector3(4.5, 1.4, 39.8)],
				["08_front.png", Vector3(-1.5, 1.8, 35.5)]]:
			cam.global_position = v[1]
			cam.look_at(Vector3(-4, 0.9, 40))
			await frames(3)
			await shot(v[0])
		cam.queue_free()
		await frames(2)

		# Performance probe: uncapped FPS while driving down the main road.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_place(Vector3(-4, 0.05, 60), 0.0)
		Input.action_press("accelerate")
		await get_tree().create_timer(1.0).timeout
		var frames_start := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_msec()
		await get_tree().create_timer(4.0).timeout
		var fps := (Engine.get_frames_drawn() - frames_start) * 1000.0 / (Time.get_ticks_msec() - t0)
		Input.action_release("accelerate")
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
		print("  info  perf: %.0f FPS uncapped (1280x720), %d draw calls, %d primitives, %.0f MB RAM, %.0f MB VRAM" % [fps, draws, prims, mem, vram])
		check(fps > 60.0, "Runs above 60 FPS on this machine")

	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)
