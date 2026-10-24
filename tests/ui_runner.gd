## Automated Milestone 6 test: main menu, settings, pause menu, HUD extras,
## restart / back to menu, records, traffic density and (windowed) FPS per
## graphics quality at 1920x1080.
##
## This node moves itself to the scene tree root so it survives scene changes.
## Run (from the project folder):
##   godot --headless --fixed-fps 60 --path . res://tests/ui_test.tscn
##   godot --path . res://tests/ui_test.tscn      (screenshots + FPS)
## Optional: -- --shots=C:/some/folder
extends Node

const MENU := "res://scenes/main_menu.tscn"
const TEST_SETTINGS := "user://test_settings.cfg"

var failures: Array[String] = []
var shots_dir := "user://test_shots_m6"
var headless := false
var messages: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.use_defaults_for_testing()
	headless = DisplayServer.get_name() == "headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(shots_dir)
	GameManager.message_posted.connect(func(t, _c): messages.append(t))
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(file_name: String) -> void:
	if headless:
		return
	await RenderingServer.frame_post_draw
	var path := shots_dir.path_join(file_name)
	get_viewport().get_texture().get_image().save_png(path)
	print("  shot  ", ProjectSettings.globalize_path(path))


func scene() -> Node:
	return get_tree().current_scene


func wait_for_scene(scene_name: String, max_frames := 600) -> bool:
	for i in max_frames:
		await get_tree().process_frame
		if scene() and scene().name == scene_name and scene().is_node_ready():
			return true
	return false


func send_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await frames(1)


func _run() -> void:
	print("== Dhakar Rickshaw: Milestone 6 UI test ==")
	# Survive scene changes: hang this runner directly under the root.
	reparent(get_tree().root)
	get_tree().change_scene_to_file(MENU)
	await _main_menu()
	await _settings_persistence()
	await _start_and_play()
	await _mouse_look()
	await _pause_menu()
	await _restart_and_menu()
	await _traffic_density()
	if not headless:
		await _performance()
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


# --- Main menu ------------------------------------------------------------------------------

func _main_menu() -> void:
	check(await wait_for_scene("MainMenu"), "Game opens on the main menu")
	await frames(10)
	var menu := scene()
	check(menu.get_node("UI/Root/TitleBox/VBox/Title").text == "ও মাগো! ঢাকা!", "Title in Bangla: ও মাগো! ঢাকা!")
	check(menu.get_node("UI/Root/TitleBox/VBox/Subtitle").text == "একটা রিকশা, হাজারটা বিপদ।", "Tagline: একটা রিকশা, হাজারটা বিপদ।")
	check(menu.get_node("City").building_count > 100, "The city is the menu backdrop")
	var start: Button = menu.get_node("%StartButton")
	check(start.has_focus(), "Start button has keyboard focus")
	for b in ["%StartButton", "%HelpButton", "%SettingsButton", "%QuitButton"]:
		check(menu.get_node(b).text != "", "Menu button in Bangla: " + menu.get_node(b).text)
	var cam: Camera3D = menu.get_node("Camera")
	var p0 := cam.global_position
	await frames(30)
	check(cam.global_position.distance_to(p0) > 0.01, "Menu camera slowly circles the rickshaw")
	await shot("m6_01_main_menu.png")
	# How to play.
	menu.get_node("%HelpButton").pressed.emit()
	await frames(3)
	var help: Control = menu.get_node("%HelpPanel")
	check(help.visible and not menu.get_node("UI/Root/Buttons").visible, "How-to-play panel opens")
	await shot("m6_02_how_to_play.png")
	await send_action("ui_cancel")
	check(not help.visible and menu.get_node("UI/Root/Buttons").visible, "Esc closes it")
	# Settings: live volume and quality changes.
	menu.get_node("%SettingsButton").pressed.emit()
	await frames(3)
	var sm: Control = menu.get_node("%SettingsMenu")
	check(sm.visible, "Settings panel opens")
	sm._sliders["Master"].value = 0.5
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	check(absf(db - linear_to_db(0.5)) < 0.1, "Master volume slider changes the volume (%.1f dB)" % db)
	sm._sliders["Traffic"].value = 0.0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Traffic")), "Volume at zero mutes the bus")
	sm._quality.select(0)
	sm._quality.item_selected.emit(0)
	check(get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "Low quality: no anti-aliasing")
	check(not menu.get_node("Sun").shadow_enabled, "Low quality: no shadows")
	await shot("m6_03_settings.png")
	sm._quality.select(1)
	sm._quality.item_selected.emit(1)
	check(menu.get_node("Sun").shadow_enabled and get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "Medium quality: shadows on, no anti-aliasing")
	sm._quality.select(2)
	sm._quality.item_selected.emit(2)
	check(get_viewport().msaa_3d == Viewport.MSAA_2X, "High quality: 2x anti-aliasing")
	sm._quality.select(1)
	sm._quality.item_selected.emit(1)
	sm._sliders["Traffic"].value = 0.9
	sm._sliders["Master"].value = 1.0
	await send_action("ui_cancel")
	check(not sm.visible and menu.get_node("UI/Root/Buttons").visible, "Esc closes settings")


func _settings_persistence() -> void:
	# Save to a test file and read it back into a fresh Settings state.
	Settings.testing = false
	Settings.path = TEST_SETTINGS
	Settings.volumes["SFX"] = 0.3
	Settings.quality = 2
	Settings.traffic_density = 0
	Settings.show_minimap = false
	Settings.mouse_sensitivity = 0.8
	Settings.invert_mouse_y = true
	Settings.save_settings()
	Settings.reset_to_defaults()
	Settings.load_settings()
	check(is_equal_approx(Settings.volumes["SFX"], 0.3) and Settings.quality == 2 and Settings.traffic_density == 0 and not Settings.show_minimap 		and is_equal_approx(Settings.mouse_sensitivity, 0.8) and Settings.invert_mouse_y,
		"Settings are saved and loaded again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	Settings.use_defaults_for_testing()


# --- Playing --------------------------------------------------------------------------------

func _start_and_play() -> void:
	messages.clear()
	scene().get_node("%StartButton").pressed.emit()
	await frames(1)
	check(scene().get_node("%Loading").visible, "Loading screen while the city is built")
	var t0 := Time.get_ticks_msec()
	check(await wait_for_scene("MainWorld"), "Start button starts a ride")
	print("  info  menu -> playing took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await frames(10)
	var world := scene()
	var hud := world.get_node("HUD")
	check(GameManager.earnings == 0 and not get_tree().paused, "A fresh ride: no money yet, not paused")
	var minimap: Control = hud.get_node("%Minimap")
	check(minimap.visible, "Mini-map is shown")
	var mp: Vector2 = minimap.to_map(world.get_node("PlayerRickshaw").global_position)
	check(Rect2(Vector2.ZERO, minimap.size).has_point(mp), "Player is drawn inside the mini-map (%s)" % mp)
	await send_action("toggle_map")
	check(not minimap.visible, "M hides the mini-map")
	await send_action("toggle_map")
	check(minimap.visible, "M shows it again")
	GameManager.add_earnings(44)
	await frames(2)
	var pop: Label = hud.get_node("%MoneyPop")
	check(pop.text == "+৳৪৪" and pop.modulate.a > 0.5, "Money changes float up next to the earnings (%s)" % pop.text)
	# The passenger hint only appears for players who haven't done a trip yet.
	await get_tree().create_timer(9.5).timeout
	check(world.HINT_PASSENGER in messages, "New players get a hint about passengers")
	GameManager.add_trip()
	check(hud.get_node("%Trips").text == "সম্পন্ন যাত্রা: ১", "Completed trips are counted in the HUD")
	await frames(2)
	await shot("m6_04_hud_minimap.png")
	# Auto-pause when the window loses focus.
	Settings.auto_pause = true
	GameManager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(2)
	check(get_tree().paused and world.get_node("PauseMenu").visible, "Switching to another window pauses the game")
	GameManager.set_paused(false)
	Settings.auto_pause = false
	await frames(2)


func _mouse(relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = relative
	Input.parse_input_event(ev)
	await frames(2)


func _wheel(button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)


## GTA-style camera: mouse orbits, wheel zooms, riding recentres.
func _mouse_look() -> void:
	var world := scene()
	var cam: Camera3D = world.get_node("ChaseCamera")
	var player: Node3D = world.get_node("PlayerRickshaw")
	player.global_transform = Transform3D(Basis(), Vector3(-4, 0.05, 40))
	player.reset_physics_interpolation()
	cam.snap_to_target()
	await frames(3)
	var behind := (cam.global_position - player.global_position) * Vector3(1, 0, 1)
	await _mouse(Vector2(300, 0))
	await frames(3)
	var after := (cam.global_position - player.global_position) * Vector3(1, 0, 1)
	var turned := absf(behind.signed_angle_to(after, Vector3.UP))
	print("  info  300 px of mouse movement turned the camera %.0f degrees" % rad_to_deg(turned))
	# (Exact angles depend on screen scaling; a clear swing is what matters.)
	check(turned > 0.4, "Moving the mouse sideways swings the camera round the rickshaw")
	await shot("m6_07_mouse_look_side.png")
	var y0 := cam.global_position.y
	await _mouse(Vector2(0, 200))
	await frames(3)
	check(cam.global_position.y > y0 + 0.5, "Moving the mouse down raises the camera to look down")
	await _mouse(Vector2(0, 5000))
	await frames(3)
	check(cam.orbit_pitch < 1.3, "Looking up/down is limited (no flipping over)")
	await _mouse(Vector2(0, -5000))
	await frames(3)
	check(cam.global_position.y > 0.3, "The camera never goes under the road (y %.2f)" % cam.global_position.y)
	var z0: float = cam.zoom
	await _wheel(MOUSE_BUTTON_WHEEL_UP)
	check(cam.zoom < z0, "Mouse wheel zooms in")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(cam.zoom > z0, "Mouse wheel zooms out")
	# Ride without touching the mouse: the camera swings back behind.
	await _mouse(Vector2(400, 0))
	Input.action_press("accelerate")
	await get_tree().create_timer(4.0).timeout
	Input.action_release("accelerate")
	print("  info  after riding 4 s without the mouse: orbit %.2f rad" % cam.orbit_yaw)
	check(absf(cam.orbit_yaw) < 0.15, "While riding, the camera recentres behind the rickshaw")
	# Invert option.
	var p0: float = cam.orbit_pitch
	Settings.invert_mouse_y = true
	await _mouse(Vector2(0, 100))
	check(cam.orbit_pitch < p0, "Invert option flips mouse up/down")
	Settings.invert_mouse_y = false
	cam.snap_to_target()


func _pause_menu() -> void:
	var world := scene()
	var pm: CanvasLayer = world.get_node("PauseMenu")
	await send_action("pause")
	check(get_tree().paused and pm.visible, "Esc pauses the game")
	var stats: Label = pm.get_node("%Stats")
	check(stats.text.begins_with("আজকের আয়: ৳৪৪"), "Pause menu shows this ride's stats (%s)" % stats.text)
	await shot("m6_05_pause.png")
	pm.get_node("%SettingsButton").pressed.emit()
	await frames(3)
	var sm: Control = pm.get_node("%SettingsMenu")
	check(sm.visible and not pm.get_node("Center/Panel").visible, "Settings open from the pause menu")
	await send_action("ui_cancel")
	check(not sm.visible and pm.get_node("Center/Panel").visible and get_tree().paused, "Esc closes settings but stays paused")
	await send_action("pause")
	check(not get_tree().paused and not pm.visible, "Esc again resumes the game")


func _restart_and_menu() -> void:
	GameManager.earnings = 60
	GameManager.trips_completed = 2
	GameManager.set_paused(true)
	scene().get_node("PauseMenu/%RestartButton").pressed.emit()
	check(await wait_for_scene("MainWorld"), "Restart reloads the ride")
	await frames(10)
	check(GameManager.earnings == 0 and GameManager.trips_completed == 0 and not get_tree().paused, "Restart starts from zero")
	check(Settings.best_earnings == 60 and Settings.best_trips == 2, "The finished ride became the record (৳৬০, 2 trips)")
	GameManager.earnings = 30
	GameManager.set_paused(true)
	scene().get_node("PauseMenu/%MenuButton").pressed.emit()
	check(await wait_for_scene("MainMenu"), "'মূল মেনু' returns to the main menu")
	await frames(5)
	var records: Label = scene().get_node("%Records")
	check(records.text.contains("৳৬০"), "Main menu shows the best earnings (%s)" % records.text)
	check(not get_tree().paused, "Main menu is not paused")


func _traffic_density() -> void:
	Settings.traffic_density = 0
	scene().get_node("%StartButton").pressed.emit()
	check(await wait_for_scene("MainWorld"), "Ride started with light traffic")
	await frames(5)
	var vehicles: int = scene().get_node("TrafficController").vehicles.size()
	var people: int = scene().get_node("PedestrianManager").pedestrians.size()
	print("  info  light traffic: %d vehicles, %d pedestrians" % [vehicles, people])
	var normal_vehicles := 0
	for k in scene().get_node("TrafficController").counts:
		normal_vehicles += int(scene().get_node("TrafficController").counts[k])
	var normal_people: int = scene().get_node("PedestrianManager").count
	check(vehicles < normal_vehicles * 0.75 and people < normal_people * 0.75,
		"Light traffic setting means fewer vehicles and people (normal: %d / %d)" % [normal_vehicles, normal_people])
	Settings.traffic_density = 1


# --- Performance at 1920x1080 ------------------------------------------------------------

func _performance() -> void:
	GameManager.go_to_main_menu()
	await wait_for_scene("MainMenu")
	scene().get_node("%StartButton").pressed.emit()
	await wait_for_scene("MainWorld")
	await frames(30)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await frames(10)
	var player: Node3D = scene().get_node("PlayerRickshaw")
	for q in [0, 1, 2]:
		Settings.quality = q
		Settings.apply()
		player.global_transform = Transform3D(Basis(), Vector3(-4, 0.05, 40))
		player.reset_physics_interpolation()
		Input.action_press("accelerate")
		await get_tree().create_timer(1.0).timeout
		var f0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_msec()
		await get_tree().create_timer(4.0).timeout
		var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)
		Input.action_release("accelerate")
		print("  info  1920x1080, quality %s: %.0f FPS" % [Settings.QUALITY_NAMES[q], fps])
		if q == 1:
			await shot("m6_06_1080p_medium.png")
		# Low and medium must hold 60 FPS at full HD; high is for stronger PCs.
		check(fps > 40.0 if q == 2 else fps > 60.0, "Playable at 1920x1080 on %s quality (%.0f FPS)" % [Settings.QUALITY_NAMES[q], fps])
	Settings.quality = 1
	Settings.apply()
