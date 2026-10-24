## Automated Milestone 5 test: collisions, damage, repairs and sound.
##
## Run (from the project folder):
##   godot --headless --fixed-fps 60 --path . res://tests/collision_test.tscn   (behaviour)
##   godot --path . res://tests/collision_test.tscn                             (screenshots)
## Optional: -- --shots=C:/some/folder
extends Node

const WORLD := preload("res://scenes/main_world.tscn")
const PlayerRickshaw := preload("res://scripts/player_rickshaw.gd")
const CityLayout := preload("res://scripts/city_layout.gd")
const AUDIO_DIR := "res://assets/audio/"

var world: Node3D
var player: PlayerRickshaw
var cm: Node3D
var traffic: Node3D
var hud: CanvasLayer
var camera: Camera3D
var failures: Array[String] = []
var shots_dir := "user://test_shots_m5"
var headless := false
var messages: Array[String] = []


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
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = world.get_node("PlayerRickshaw")
	cm = world.get_node("CollisionManager")
	# Shop stalls on the footpath would break and slow the test rides.
	world.get_node("BreakableManager").enabled = false
	traffic = world.get_node("TrafficController")
	hud = world.get_node("HUD")
	camera = world.get_node("ChaseCamera")
	GameManager.message_posted.connect(func(t, _c): messages.append(t))
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func shot(file_name: String) -> void:
	if headless:
		return
	await RenderingServer.frame_post_draw
	var path := shots_dir.path_join(file_name)
	get_viewport().get_texture().get_image().save_png(path)
	print("  shot  ", ProjectSettings.globalize_path(path))


func _place(pos: Vector3, yaw: float, spd := 0.0) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.05, pos.z))
	player.speed = spd
	player.velocity = Vector3.ZERO
	player._crash_cooldown = 0.0
	player.reset_physics_interpolation()
	camera.snap_to_target()


func _clear_traffic_near(point: Vector3, radius: float) -> void:
	for v in traffic.vehicles:
		if v.global_position.distance_to(point) < radius:
			traffic._place_somewhere(v, radius + 60.0, false)


func _keep_traffic_away(point: Vector3, radius: float, seconds: float) -> void:
	for i in int(seconds * 60.0):
		if i % 20 == 0:
			_clear_traffic_near(point, radius)
		await get_tree().physics_frame


## Rides at `spd` m/s towards the west kerb of Mirpur Road, `angle` radians
## away from straight-on, and returns the crash events.
## A spot on the west footpath of Mirpur Road, facing a flat building wall
## 0.45 m ahead (west), with nothing solid around. Returns [origin, wall_x].
## (The kerb is no longer a wall: the rickshaw rides up onto the footpath.)
func _wall_spot() -> Array:
	var space := world.get_world_3d().direct_space_state
	for zi in range(12, 55):
		var z := float(zi)
		var xs := []
		for dz in [-0.7, 0.0, 0.7]:
			var q := PhysicsRayQueryParameters3D.create(Vector3(-9.3, 1.0, z + dz), Vector3(-15, 1.0, z + dz), 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or not str(hit.collider.name).begins_with("Block"):
				break
			xs.append(hit.position.x)
		if xs.size() < 3 or absf(xs[0] - xs[2]) > 0.05 or absf(xs[1] - xs[0]) > 0.05 or xs[1] > -11.0:
			continue
		var origin := Vector3(xs[1] + 1.44 + 0.45, 0, z)
		var glance := Vector3(xs[1] + 1.3, 0, z + 3.0)
		if player._spot_is_free(Transform3D(Basis(Vector3.UP, PI * 0.5), origin + Vector3(0, 0.05, 0))) 				and player._spot_is_free(Transform3D(Basis(Vector3.UP, 0.27), glance + Vector3(0, 0.05, 0))):
			return [origin, xs[1]]
	return [Vector3(-8.0, 0, 15), -9.5]


func _ride_into_kerb(spd: float, angle: float, _z := 15.0) -> Array:
	var spot := _wall_spot()
	var origin: Vector3 = spot[0]
	_clear_traffic_near(origin, 35.0)
	await frames(2)
	var events := []
	var cb := func(sev, imp, other): events.append([sev, imp, other])
	player.crashed.connect(cb)
	# Facing west is yaw +PI/2; `angle` turns the nose back towards north.
	var yaw := PI * 0.5 - angle
	var start := origin if angle < 0.3 else Vector3(spot[1] + 1.3, 0, origin.z + 3.0)
	_place(start, yaw, spd)
	player.controls_enabled = false
	for i in 50:
		await get_tree().physics_frame
		if not events.is_empty():
			break
	player.controls_enabled = true
	player.crashed.disconnect(cb)
	return events


func _run() -> void:
	print("== Dhakar Rickshaw: Milestone 5 collision & sound test ==")
	await frames(5)
	_check_audio()
	if headless:
		await _wall_impacts()
		await _glancing_scrape()
		await _vehicle_impact()
		await _bell_hold()
		await _stuck_hint()
		await _damage_effects()
		await _repairs()
		await _crash_robustness()
		await _wreck()
	else:
		await _screenshots()
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


# --- Sound --------------------------------------------------------------------------------

func _check_audio() -> void:
	for bus in ["SFX", "Traffic", "Ambience", "UI"]:
		check(AudioServer.get_bus_index(bus) >= 0, "Audio bus exists: " + bus)
	var files := ["rickshaw_bell.wav", "bell_short.wav", "bump.wav", "clang.wav", "crash.wav", "boing.wav",
		"scrape_loop.wav", "squeal.wav", "pedal_loop.wav", "freewheel_loop.wav", "bus_horn.wav",
		"cng_horn.wav", "car_horn.wav", "bike_horn.wav", "cng_engine_loop.wav", "bus_engine_loop.wav",
		"traffic_ambience_loop.wav", "chime.wav", "coins.wav", "ui_click.wav"]
	var missing: Array[String] = []
	var total_len := 0.0
	for f in files:
		var s = load(AUDIO_DIR + f) if ResourceLoader.exists(AUDIO_DIR + f) else null
		if s == null:
			missing.append(f)
		else:
			total_len += s.get_length()
	check(missing.is_empty(), "All %d sound effects load %s" % [files.size(), missing])
	check(total_len < 20.0, "Sounds are short clips (%.1f s in total)" % total_len)
	var a_horn: AudioStreamPlayer3D = traffic.vehicles[0]._horn
	check(a_horn.bus == "Traffic", "Traffic sounds play on the Traffic bus")
	check(traffic.get_node("Ambience").bus == "Ambience", "Street ambience plays on the Ambience bus")
	check(player._pedal.bus == "SFX" and player._bell.bus == "SFX", "Rickshaw sounds play on the SFX bus")
	# A missing optional sound must not break anything.
	check(player._load_optional("res://assets/audio/does_not_exist.wav") == null, "Missing sound files are skipped safely")


# --- Impacts -------------------------------------------------------------------------------

func _last_sound() -> String:
	var newest := ""
	for p in cm._sfx:
		if p.playing and p.stream:
			newest = p.stream.resource_path.get_file()
	return newest


func _wall_impacts() -> void:
	var expected := [[2.2, 0, "bump.wav", "ঠক!", 1.0], [4.0, 1, "bump.wav", "ধাম!", 6.0], [7.0, 2, "crash.wav", "ধড়াম!", 15.0]]
	for e in expected:
		GameManager.set_damage(0.0)
		var acc_before: int = GameManager.accidents
		var fx_before: int = cm.effects_shown
		var events := await _ride_into_kerb(e[0], 0.0)
		await frames(1)
		var sev: int = events[0][0] if not events.is_empty() else -1
		var label: String = ["light", "medium", "heavy"][e[1]]
		print("  info  %.1f m/s into the kerb: severity %d, impact %.1f, sound %s, damage %.0f%%" % [
			e[0], sev, events[0][1] if not events.is_empty() else 0.0, _last_sound(), GameManager.damage])
		check(sev == e[1], "%.1f m/s head-on is a %s crash" % [e[0], label])
		check(_last_sound() == e[2], "%s crash sound: %s" % [label, e[2]])
		check(cm.effects_shown == fx_before + 1, "%s crash shows a dust effect" % label)
		var pop_ok := false
		for pop in cm._pops:
			if pop.visible and pop.text == e[3]:
				pop_ok = true
		check(pop_ok, "%s crash pops up '%s'" % [label, e[3]])
		check(camera._trauma > 0.0, "%s crash shakes the camera" % label)
		check(is_equal_approx(GameManager.damage, e[4]), "%s crash adds %.0f%% damage" % [label, e[4]])
		check(GameManager.accidents == acc_before + (0 if e[1] == 0 else 1), "Accident counter: light bumps don't count, others do")
		if e[1] == 2:
			check(cm._flash.color.a > 0.1, "Heavy crash flashes the screen")
			check(player.get_node("Model/Dizzy").visible, "Heavy crash: the puller sees stars")
		await frames(40)
	# Still drivable after the heavy crash: back away from the kerb.
	Input.action_press("brake_reverse")
	await frames(90)
	Input.action_release("brake_reverse")
	check(player.speed < -0.5, "After a heavy crash the rickshaw can still drive (reverse)")


func _glancing_scrape() -> void:
	GameManager.set_damage(0.0)
	var events := await _ride_into_kerb(7.0, 1.3)  # almost parallel to the kerb
	var sev: int = events[0][0] if not events.is_empty() else -1
	print("  info  glancing hit at 7 m/s: severity %d" % sev)
	check(sev <= 0, "A fast glancing scrape is at most a light bump (direction matters)")
	check(player.speed > 3.0, "…and the rickshaw slides on instead of stopping (%.1f m/s)" % player.speed)


func _vehicle_impact() -> void:
	var car = null
	for v in traffic.vehicles:
		if v.vehicle_type == "car":
			car = v
			break
	var net = traffic.network
	var lane := -1
	for id in net.edges.size():
		var e: Dictionary = net.edges[id]
		if absf(e.start.x + 4.0) < 0.01 and e.dir.z < -0.9 and e.start.z > 40.0 and e.end.z < 40.0:
			lane = id
	_clear_traffic_near(Vector3(-4, 0, 60), 50.0)
	car.place(lane, 20.0)
	car._stopped_until = traffic.time + 20.0
	await frames(3)
	var c: Vector3 = car.get_center()
	_place(c + Vector3(0, 0, 6.5), 0.0, 6.0)
	var events := []
	var cb := func(sev, imp, other): events.append([sev, imp, other])
	player.crashed.connect(cb)
	player.controls_enabled = false
	for i in 60:
		await get_tree().physics_frame
		if not events.is_empty():
			break
	player.controls_enabled = true
	player.crashed.disconnect(cb)
	await frames(1)
	check(not events.is_empty() and events[0][2] == car, "Rear-ending a car registers a vehicle crash")
	check(_last_sound() in ["clang.wav", "crash.wav"], "Vehicle crashes sound metallic (%s)" % _last_sound())
	var bubble: Label3D = car.get_node_or_null("Speech")
	check(bubble != null and bubble.visible and bubble.text in car.ANGRY_LINES, "The driver shouts at you in Bangla (%s)" % (bubble.text if bubble else "-"))
	car._stopped_until = 0.0


func _bell_hold() -> void:
	var rings := [0]
	var cb := func(): rings[0] += 1
	player.horn_pressed.connect(cb)
	Input.action_press("horn")
	await frames(120)
	Input.action_release("horn")
	player.horn_pressed.disconnect(cb)
	check(rings[0] >= 3, "Holding H keeps ringing the bell (%d rings in 2 s)" % rings[0])


func _stuck_hint() -> void:
	var spot := _wall_spot()
	_clear_traffic_near(spot[0], 35.0)
	_place(spot[0] - Vector3(0.45, 0, 0), PI * 0.5)  # nose against the wall
	await frames(5)
	messages.clear()
	cm._stuck_cooldown = 0.0
	Input.action_press("accelerate")
	await _keep_traffic_away(Vector3(-4, 0, 15), 30.0, 4.0)
	Input.action_release("accelerate")
	check("আটকে গেছেন? R চাপুন" in messages, "Pushing against a wall suggests pressing R")


func _top_speed_after(seconds: float) -> float:
	# A pure speed measurement: no pedestrians stepping in front of us.
	var peds: Node = world.get_node("PedestrianManager")
	peds.process_mode = Node.PROCESS_MODE_DISABLED
	_clear_traffic_near(Vector3(-4, 0, 60), 80.0)
	_place(Vector3(-4, 0, 100), 0.0)
	await frames(2)
	Input.action_press("accelerate")
	await _keep_traffic_away(Vector3(-4, 0, 70), 45.0, seconds)
	Input.action_release("accelerate")
	peds.process_mode = Node.PROCESS_MODE_INHERIT
	return player.get_speed_kmh()


func _damage_effects() -> void:
	GameManager.set_damage(0.0)
	var fresh := await _top_speed_after(7.0)
	GameManager.set_damage(95.0)  # 100% would wreck it
	var battered := await _top_speed_after(7.0)
	print("  info  speed after 7 s: like new %.1f km/h, fully battered %.1f km/h" % [fresh, battered])
	check(battered < fresh * 0.86 and battered > fresh * 0.6, "A battered rickshaw is slower, but still drives")
	check(player.get_node("Model").damage_wobble > 0.05, "A battered rickshaw's front wheel wobbles")
	var cond: Label = hud.get_node("StatsPanel/VBox/Condition")
	check(cond.text == "রিকশার অবস্থা: ৫%", "HUD shows the rickshaw condition in Bangla (%s)" % cond.text)
	check("রিকশার অবস্থা খুব খারাপ!\nমেকানিকের কাছে যান" in messages, "Warning when the rickshaw is badly damaged")
	GameManager.set_damage(0.0)
	check(cond.text == "রিকশার অবস্থা: ১০০%", "Condition back to 100% after repair")


func _repairs() -> void:
	var bay: Array = CityLayout.repair_bay()
	check(not bay.is_empty(), "There is a mechanic (রিকশা মেরামত)")
	var pos: Vector3 = bay[0]
	var along := Vector3(bay[1].z, 0, -bay[1].x)
	_clear_traffic_near(pos, 30.0)
	_place(pos, atan2(-along.x, -along.z))
	await frames(5)
	# 1) Enough money: full repair.
	GameManager.earnings = 100
	GameManager.set_damage(40.0)
	await frames(3)
	var prompt: Label = hud.get_node("Prompt")
	check(prompt.visible and prompt.text == "মেরামত করতে E চাপুন (৳২০)", "Repair prompt with price (%s)" % prompt.text)
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	await frames(2)
	check(GameManager.damage == 0.0 and GameManager.earnings == 80, "Full repair for ৳২০ (damage %.0f, money %d)" % [GameManager.damage, GameManager.earnings])
	# 2) Some money: partial repair.
	GameManager.earnings = 10
	GameManager.set_damage(60.0)
	cm.repair()
	check(GameManager.earnings == 0 and is_equal_approx(GameManager.damage, 40.0), "Partial repair with the money you have (damage %.0f)" % GameManager.damage)
	# 3) Broke: the mechanic helps anyway, so you can never get stuck.
	GameManager.earnings = 0
	GameManager.set_damage(60.0)
	cm.repair()
	check(GameManager.earnings == 0 and is_equal_approx(GameManager.damage, 30.0), "Broke: the mechanic helps for free (damage %.0f)" % GameManager.damage)
	GameManager.set_damage(0.0)
	await frames(3)
	check(not prompt.visible, "No repair prompt when nothing needs fixing")


## Lots of random hard crashes must never leave the rickshaw broken or stuck.
func _crash_robustness() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var crashes := [0]
	for i in 15:
		var road: Array = CityLayout.VERTICAL_ROADS[rng.randi() % CityLayout.VERTICAL_ROADS.size()]
		var p := Vector3(road[0] + rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-90, 90))
		GameManager.set_damage(0.0)  # this test is about physics, not wrecking
		_place(p, rng.randf() * TAU, 7.0)
		player.controls_enabled = false
		var cb := func(_s, _i, _o): crashes[0] += 1
		player.crashed.connect(cb)
		await frames(70)
		player.crashed.disconnect(cb)
		player.controls_enabled = true
	print("  info  15 random high-speed rides: %d crash events, damage now %.0f%%" % [crashes[0], GameManager.damage])
	var up := player.global_transform.basis.y.dot(Vector3.UP)
	check(up > 0.99 and absf(player.global_position.y) < 0.2, "After many crashes the rickshaw is upright on the ground")
	await frames(2)
	Input.action_press("reset_vehicle")
	await frames(2)
	Input.action_release("reset_vehicle")
	_clear_traffic_near(player.global_position, 40.0)
	await frames(5)
	check(player._spot_is_free(player.global_transform), "Reset puts it in a free spot")
	Input.action_press("accelerate")
	await _keep_traffic_away(player.global_position, 35.0, 2.0)
	Input.action_release("accelerate")
	print("  info  speed 2 s after reset: %.1f km/h" % player.get_speed_kmh())
	check(player.get_speed_kmh() > 8.0, "…and drives normally again")


# --- Wreck at 0% condition ------------------------------------------------------------------

func _wreck() -> void:
	var pm: Node = world.get_node("PassengerManager")
	_clear_traffic_near(Vector3(-4, 0, 60), 50.0)
	_place(Vector3(-4, 0, 70), 0.0)
	await frames(3)
	GameManager.earnings = 120
	messages.clear()
	var acc: int = GameManager.accidents
	GameManager.set_damage(99.0)
	check(not cm.wrecked and not player.broken_down, "At 1% condition the rickshaw still runs")
	GameManager.add_damage(5.0)
	await frames(2)
	check(cm.wrecked and player.broken_down, "At 0% condition the rickshaw is wrecked")
	check("রিকশা নষ্ট হয়ে গেছে!" in messages, "Bangla message: রিকশা নষ্ট হয়ে গেছে!")
	check(player._smoke != null and player._smoke.emitting, "The wreck smokes")
	check(player.get_node("Model/Dizzy").visible, "The puller sees stars")
	var z0 := player.global_position.z
	Input.action_press("accelerate")
	await frames(120)
	Input.action_release("accelerate")
	check(absf(player.global_position.z - z0) < 0.2 and player.speed == 0.0, "A wrecked rickshaw cannot be ridden")
	var rings := [0]
	var cb := func(): rings[0] += 1
	player.horn_pressed.connect(cb)
	Input.action_press("horn")
	await frames(3)
	Input.action_release("horn")
	player.horn_pressed.disconnect(cb)
	check(rings[0] == 0, "…and its bell is silent")
	var screen: CanvasLayer = cm._wreck_layer
	check(not screen.visible, "Breakdown screen waits a moment")
	await get_tree().create_timer(cm.WRECK_SCREEN_DELAY + 0.3).timeout
	check(screen.visible, "Then the breakdown screen appears")
	check(cm._tow_button.text == "মেকানিকের কাছে নিয়ে যান (৳৫০)", "Tow offer with price (%s)" % cm._tow_button.text)
	check(GameManager.accidents == acc, "Wrecking is not counted twice as an accident")
	check(cm._wreck_info.text.ends_with("আজকের আয়: ৳১২০"), "Breakdown screen shows today's earnings (%s)" % cm._wreck_info.text.replace("
", " / "))
	# Tow to the mechanic.
	cm._tow_button.pressed.emit()
	await frames(5)
	var bay: Array = CityLayout.repair_bay()
	var at_bay := Vector2(player.global_position.x - bay[0].x, player.global_position.z - bay[0].z).length()
	print("  info  after tow: %.1f m from the mechanic, money %d, condition %.0f%%" % [at_bay, GameManager.earnings, 100.0 - GameManager.damage])
	check(not cm.wrecked and not player.broken_down and not screen.visible, "Towing brings the rickshaw back to life")
	check(at_bay < 15.0, "…at the mechanic on Mirpur Road")
	check(GameManager.damage == 0.0, "…fully repaired")
	check(GameManager.earnings == 70, "…for ৳৫০")
	check(not player._smoke.emitting, "No more smoke")
	Input.action_press("accelerate")
	await _keep_traffic_away(player.global_position, 30.0, 1.5)
	Input.action_release("accelerate")
	check(player.speed > 2.0, "It rides again (%.1f m/s)" % player.speed)
	# A wreck with a passenger on board: the trip is cancelled, no fare.
	GameManager.earnings = 0
	var ped: Node3D = null
	for p in world.get_node("PedestrianManager").pedestrians:
		if p.state == 0:
			ped = p
			break
	pm.passenger = ped
	pm.destination = world.get_node("DestinationManager").zones[0]
	pm.trip_state = pm.Trip.ON_BOARD
	ped.reparent(player.get_passenger_seat(), false)
	ped.sit_down()
	GameManager.set_damage(100.0)
	await frames(200)
	check(pm.trip_state == pm.Trip.NONE and ped.state == 0, "A wreck ends the passenger's trip; they get off")
	check(GameManager.earnings == 0, "…and pay nothing")
	await get_tree().create_timer(cm.WRECK_SCREEN_DELAY).timeout
	check(cm._tow_button.text == "মেকানিকের কাছে নিয়ে যান (বিনা খরচে)", "Broke: the mechanic tows for free")
	cm.tow_to_mechanic()
	await frames(3)
	check(not player.broken_down and GameManager.earnings == 0, "Free tow works")


# --- Screenshots ---------------------------------------------------------------------------

func _screenshots() -> void:
	# Medium crash into the kerb: dust and "ধাম!".
	var events := await _ride_into_kerb(4.0, 0.0)
	await frames(6)
	await shot("m5_01_medium_crash.png")
	await frames(60)
	# Heavy crash: flash, dizzy stars, "ধড়াম!".
	events = await _ride_into_kerb(7.0, 0.0)
	await frames(3)
	await shot("m5_02_heavy_crash.png")
	await frames(60)
	await shot("m5_03_dizzy.png")
	# Damaged condition shown in the HUD, at the mechanic with the repair prompt.
	GameManager.set_damage(65.0)
	GameManager.earnings = 120
	var bay: Array = CityLayout.repair_bay()
	var along := Vector3(bay[1].z, 0, -bay[1].x)
	_clear_traffic_near(bay[0], 30.0)
	_place(bay[0] - along * 9.0, atan2(-along.x, -along.z))
	await frames(10)
	await shot("m5_04_mechanic.png")
	_place(bay[0], atan2(-along.x, -along.z))
	await frames(10)
	await shot("m5_05_repair_prompt.png")
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.global_position = bay[0] + bay[1] * 6.0 + Vector3(0, 3.0, 6.0)
	cam.look_at(bay[0] - bay[1] * 7.5 + Vector3(0, 1.5, 0))
	await frames(3)
	await shot("m5_07_garage.png")
	cam.current = false
	cam.queue_free()
	camera.current = true
	# Angry driver after a crash.
	await _vehicle_impact()
	await frames(5)
	await shot("m5_06_angry_driver.png")
	# Wrecked at 0%: smoke, then the breakdown screen.
	_clear_traffic_near(Vector3(-4, 0, 60), 50.0)
	_place(Vector3(-4, 0, 70), 0.0)
	GameManager.earnings = 120
	GameManager.set_damage(100.0)
	await get_tree().create_timer(1.2).timeout
	await shot("m5_08_wrecked.png")
	await get_tree().create_timer(cm.WRECK_SCREEN_DELAY).timeout
	await shot("m5_09_breakdown_screen.png")
	cm.tow_to_mechanic()
