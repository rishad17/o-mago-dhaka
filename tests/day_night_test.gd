## Automated test: day and night cycle, the clock, the headlamp.
## Run: godot --headless --fixed-fps 60 --path . res://tests/day_night_test.tscn
##      godot --path . res://tests/day_night_test.tscn -- --shots=C:/folder   (screenshots)
extends Node

const WORLD := preload("res://scenes/main_world.tscn")
const DayNight := preload("res://scripts/day_night.gd")
const Pedestrian := preload("res://scripts/pedestrian.gd")

var world: Node3D
var dn: Node
var failures: Array[String] = []
var shots_dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.use_defaults_for_testing()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
	world = WORLD.instantiate()
	add_child(world)
	dn = world.get_node("DayNight")
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		failures.append(what)


func _run() -> void:
	print("== O Mago! Dhaka!: day and night ==")
	await get_tree().process_frame
	var clock: Label = world.get_node("HUD/Clock")
	check(is_equal_approx(dn.hour, 8.0) or dn.hour < 8.1, "A ride starts in the morning (%.2f)" % dn.hour)
	check(clock.text == "সকাল ৮:০০", "HUD clock in Bangla: %s" % clock.text)
	# Time passes while playing.
	var h0: float = dn.hour
	await get_tree().create_timer(2.0).timeout
	print("  info  2 s of play = %.1f game minutes" % ((dn.hour - h0) * 60.0))
	check(dn.hour > h0, "Time passes while you play")
	check(absf((dn.hour - h0) * DayNight.SECONDS_PER_HOUR - 2.0) < 0.3, "One game hour takes %.0f real seconds (a day ≈ %d minutes)" % [DayNight.SECONDS_PER_HOUR, int(DayNight.SECONDS_PER_HOUR * 24 / 60)])
	# Clock text.
	check(DayNight.clock_text(12.5) == "দুপুর ১২:৩০", "দুপুর ১২:৩০ (%s)" % DayNight.clock_text(12.5))
	check(DayNight.clock_text(16.25) == "বিকেল ৪:১৫", "বিকেল ৪:১৫ (%s)" % DayNight.clock_text(16.25))
	check(DayNight.clock_text(18.0) == "সন্ধ্যা ৬:০০", "সন্ধ্যা ৬:০০ (%s)" % DayNight.clock_text(18.0))
	check(DayNight.clock_text(22.75) == "রাত ১০:৪৫", "রাত ১০:৪৫ (%s)" % DayNight.clock_text(22.75))
	check(DayNight.clock_text(5.0) == "ভোর ৫:০০", "ভোর ৫:০০ (%s)" % DayNight.clock_text(5.0))
	# Looks.
	dn.running = false
	var sun: DirectionalLight3D = world.get_node("Sun")
	var lamp: SpotLight3D = world.get_node("PlayerRickshaw/Headlamp")
	var looks := {}
	for h in [8.0, 12.0, 17.5, 22.0]:
		dn.set_hour(h)
		looks[h] = [sun.light_energy, sun.global_transform.basis.z.y, lamp.visible]
	print("  info  sun energy morning %.2f noon %.2f sunset %.2f night %.2f" % [looks[8.0][0], looks[12.0][0], looks[17.5][0], looks[22.0][0]])
	check(looks[12.0][0] > looks[17.5][0] and looks[17.5][0] > looks[22.0][0], "It gets darker from noon to evening to night")
	check(looks[12.0][1] > looks[8.0][1], "The sun is higher at noon than in the morning")
	check(not looks[12.0][2] and looks[22.0][2], "The headlamp is off by day and on at night")
	dn.set_hour(23.99)
	dn.running = true
	await get_tree().create_timer(1.0).timeout
	check(dn.hour < 1.0, "Midnight wraps round to a new day (%.2f)" % dn.hour)
	# The new pedestrian line.
	check("কানের উপর একটা দিমু!" in Pedestrian.HIT_SHOUTS, "Pedestrians can say: কানের উপর একটা দিমু!")
	if shots_dir != "":
		dn.running = false
		var p = world.get_node("PlayerRickshaw")
		p.controls_enabled = false
		p.global_transform = Transform3D(Basis(), Vector3(-4, 0.05, 40))
		p.reset_physics_interpolation()
		world.get_node("ChaseCamera").snap_to_target()
		for s in [[8.0, "dn_1_morning.png"], [13.0, "dn_2_noon.png"], [17.6, "dn_3_sunset.png"], [21.5, "dn_4_night.png"]]:
			dn.set_hour(s[0])
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots_dir.path_join(s[1]))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for h in [12.0, 22.0]:
			dn.set_hour(h)
			await get_tree().create_timer(1.0).timeout
			var f0 := Engine.get_frames_drawn()
			var t0 := Time.get_ticks_msec()
			await get_tree().create_timer(3.0).timeout
			print("  info  FPS at %.0f:00: %.0f" % [h, (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)])
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)
