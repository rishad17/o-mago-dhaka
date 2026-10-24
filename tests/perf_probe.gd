## Performance probe: average FPS, frame-time spikes (stutter) and where the
## time goes, at a few busy spots in the full game world.
##
## Run windowed (from the project folder) and leave the window alone:
##   godot --path . res://tests/perf_probe.tscn
## Optional: -- --quality=0|1|2 --size=1920x1080
extends Node

const WORLD := preload("res://scenes/main_world.tscn")

var world: Node3D
var player: CharacterBody3D
var _missed := 0
var _only_first := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.use_defaults_for_testing()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			Settings.quality = int(arg.trim_prefix("--quality="))
		elif arg == "--touch":
			Settings.touch_mode = true
			Settings.quality = 0
			Settings.traffic_density = 0
			Settings.use_phone_timing()
		elif arg == "--phone-timing":
			Settings.use_phone_timing()
		elif arg.begins_with("--density="):
			Settings.traffic_density = int(arg.trim_prefix("--density="))
		elif arg.begins_with("--size="):
			var p := arg.trim_prefix("--size=").split("x")
			DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
	Settings.apply()
	world = WORLD.instantiate()
	add_child(world)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--atlas="):
			RenderingServer.directional_shadow_atlas_set_size(int(arg.trim_prefix("--atlas=")), true)
		elif arg.begins_with("--sdist="):
			world.get_node("Sun").directional_shadow_max_distance = float(arg.trim_prefix("--sdist="))
		elif arg == "--only-first":
			_only_first = true
	player = world.get_node("PlayerRickshaw")
	_run.call_deferred()


func _place(pos: Vector3, yaw: float) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	player.velocity = Vector3.ZERO
	player.speed = 0.0
	player.reset_physics_interpolation()
	world.get_node("ChaseCamera").snap_to_target()


## Drives forward for a while and returns [avg fps, 99th-percentile frame ms,
## worst frame ms, frames over 25 ms, process ms, physics ms, draw calls, objects].
func _measure(pos: Vector3, yaw: float) -> Array:
	_place(pos, yaw)
	Input.action_press("accelerate")
	await get_tree().create_timer(1.0).timeout
	_missed = 0
	var times: Array[float] = []
	var proc := 0.0
	var phys := 0.0
	var t_end := Time.get_ticks_msec() + 4000
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	Input.action_release("accelerate")
	var total := 0.0
	var spikes := 0
	for t in times:
		total += t
		if t > 25.0:
			spikes += 1
		if t > 18.5:
			_missed += 1
	var sorted := times.duplicate()
	sorted.sort()
	var n := times.size()
	return [n * 1000.0 / total, sorted[int(n * 0.99)], sorted[n - 1], spikes,
		proc / n, phys / n,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)]


func _report(label: String, r: Array) -> void:
	print("  %-28s missed vsync %3d  %5.0f FPS  p99 %5.1f ms  worst %5.1f ms  >25ms: %d  process %4.1f ms  physics %4.1f ms  %d draws  %d objects"
		% [label, _missed, r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]])


func _run() -> void:
	var vsync := OS.get_cmdline_user_args().has("--vsync")
	if not vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("== perf probe: quality %d, window %s ==" % [Settings.quality, DisplayServer.window_get_size()])
	await get_tree().create_timer(2.0).timeout
	var spots := [
		["Farmgate (Mirpur Rd)", Vector3(-4, 0.05, 100), 0.0],
		["Panthapath", Vector3(-100, 0.05, -2.5), -PI * 0.5],
		["east grid", Vector3(122.5, 0.05, 100), 0.0],
		["south band", Vector3(-4, 0.05, 290), 0.0],
		["Farmgate again", Vector3(-4, 0.05, 100), 0.0],
	]
	for s in spots:
		for k in Engine.get_meta_list():
			Engine.set_meta(k, 0)
		var f0 := Engine.get_physics_frames()
		_report(s[0], await _measure(s[1], s[2]))
		var nf := float(Engine.get_physics_frames() - f0)
		var parts := []
		for k in Engine.get_meta_list():
			parts.append("%s %.2f" % [k, Engine.get_meta(k) / nf / 1000.0])
		print("      ms per physics tick: ", ", ".join(parts))
	# Attribute the cost: switch systems off one by one at the first spot.
	var s0: Array = spots[0]
	if OS.get_cmdline_user_args().has("--draws"):
		_place(s0[1], s0[2])
		await get_tree().create_timer(1.0).timeout
		var info := func(): return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		print("  draws all: ", info.call())
		var city := world.get_node("City")
		var labels := 0
		for n in city.get_children():
			if n is Label3D:
				n.visible = false
				labels += 1
		await get_tree().create_timer(0.3).timeout
		print("  draws without %d city signs: %d" % [labels, info.call()])
		world.get_node("PedestrianManager").visible = false
		await get_tree().create_timer(0.3).timeout
		print("  …and without people: ", info.call())
		world.get_node("TrafficController").visible = false
		await get_tree().create_timer(0.3).timeout
		print("  …and without traffic: ", info.call())
		world.get_node("HUD").visible = false
		await get_tree().create_timer(0.3).timeout
		print("  …and without HUD: ", info.call())
		get_tree().quit()
		return
	if _only_first:
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--ablate"):
		get_tree().physics_interpolation = false
		_report("…interpolation off", await _measure(s0[1], s0[2]))
		get_tree().physics_interpolation = true
		world.get_node("PedestrianManager").visible = false
		world.get_node("TrafficController").visible = false
		_report("…all hidden, still simulated", await _measure(s0[1], s0[2]))
		world.get_node("PedestrianManager").visible = true
		world.get_node("TrafficController").visible = true
	var peds := world.get_node("PedestrianManager")
	peds.process_mode = Node.PROCESS_MODE_DISABLED
	peds.visible = false
	_report("…without pedestrians", await _measure(s0[1], s0[2]))
	var traffic := world.get_node("TrafficController")
	traffic.process_mode = Node.PROCESS_MODE_DISABLED
	traffic.visible = false
	_report("…and without traffic", await _measure(s0[1], s0[2]))
	var sun: DirectionalLight3D = world.get_node("Sun")
	sun.shadow_enabled = false
	_report("…and without shadows", await _measure(s0[1], s0[2]))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("  memory: %.0f MB" % mem)
	get_tree().quit()
