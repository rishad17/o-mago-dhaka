## Automated Milestone 3 test: Dhaka traffic.
##
## Run (from the project folder):
##   godot --headless --fixed-fps 60 --path . res://tests/traffic_test.tscn   (fast, logic only)
##   godot --path . res://tests/traffic_test.tscn                             (screenshots + FPS only)
## Optional: -- --shots=C:/some/folder --seed=N --sim=<seconds of traffic to simulate>
## In windowed mode, don't click away from the game window while it runs.
extends Node

const WORLD := preload("res://scenes/main_world.tscn")
const CityLayout := preload("res://scripts/city_layout.gd")
const PlayerRickshaw := preload("res://scripts/player_rickshaw.gd")

var world: Node3D
var player: PlayerRickshaw
var traffic: Node3D
var failures: Array[String] = []
var shots_dir := "user://test_shots_m3"
var headless := false
var sim_seconds := 120.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Default settings (and never touch the player's saved ones).
	Settings.use_defaults_for_testing()
	headless = DisplayServer.get_name() == "headless"
	var traffic_seed := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--sim="):
			sim_seconds = float(arg.trim_prefix("--sim="))
		elif arg.begins_with("--seed="):
			traffic_seed = int(arg.trim_prefix("--seed="))
	DirAccess.make_dir_recursive_absolute(shots_dir)
	world = WORLD.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	if traffic_seed >= 0:
		world.get_node("TrafficController").traffic_seed = traffic_seed
	add_child(world)
	player = world.get_node("PlayerRickshaw")
	traffic = world.get_node("TrafficController")
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


func _place_player(pos: Vector3, yaw: float) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	player.velocity = Vector3.ZERO
	player.speed = 0.0
	player.reset_physics_interpolation()
	world.get_node("ChaseCamera").snap_to_target()


func _run() -> void:
	print("== Dhakar Rickshaw: Milestone 3 traffic test ==")
	await frames(5)
	_check_network()
	_check_fleet()
	if headless:
		# Behaviour checks run headless: deterministic and immune to window
		# focus changes (Godot releases held keys when its window loses focus).
		await _simulate(sim_seconds)
		await _check_stops_for_player()
		await _check_crash_into_bus()
	else:
		player.controls_enabled = false
		await _screenshots()
		await _perf_probe()
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _on_road_with_margin(p: Vector3, t: Vector3, margin: float) -> bool:
	var side := t.cross(Vector3.UP) * margin
	return CityLayout.is_road(p.x, p.z) and CityLayout.is_road(p.x + side.x, p.z + side.z) \
		and CityLayout.is_road(p.x - side.x, p.z - side.z)


func _check_network() -> void:
	var net = traffic.network
	var expected_lanes := CityLayout.lane_count()
	check(net.edges.size() == expected_lanes, "Lane network has %d lanes (%d)" % [expected_lanes, net.edges.size()])
	var bad_lanes := 0
	var bad_turns := 0
	var turns := 0
	for id in net.edges.size():
		var e: Dictionary = net.edges[id]
		var piece = e.piece
		var d := 0.0
		while d <= piece.length:
			if not _on_road_with_margin(piece.position_at(d), e.dir, 1.0):
				bad_lanes += 1
			d += 1.0
		var outs := 0
		for out in net.node_out[e.to]:
			if net.edges[out].to == e.from:
				continue
			outs += 1
			turns += 1
			var tp = net.turn_piece(id, out)
			var s := 0.0
			while s <= tp.length:
				if not _on_road_with_margin(tp.position_at(s), tp.tangent_at(s), 1.0):
					bad_turns += 1
				s += 0.5
		if outs == 0:
			bad_lanes += 1000
	check(bad_lanes == 0, "Every lane stays on the road with 1 m clearance and has a way onward")
	check(bad_turns == 0, "All %d turn paths through intersections stay on the road (%d bad samples)" % [turns, bad_turns])
	# Left-hand traffic: on the north-south Mirpur Road, northbound lane is west of centre.
	var north_ok := false
	for e in net.edges:
		if absf(e.start.x - (-4.0)) < 0.01 and e.dir.z < -0.9:
			north_ok = true
	check(north_ok, "Traffic keeps left (northbound Mirpur Road lane at x = -4)")


func _check_fleet() -> void:
	var c: Dictionary = traffic.count_by_type()
	print("  info  fleet: ", c)
	for type in [["bus", 3], ["cng", 4], ["car", 2], ["microbus", 1], ["motorcycle", 3], ["rickshaw", 4]]:
		check(c.get(type[0], 0) >= type[1], "At least %d %s in traffic" % [type[1], type[0]])
	var labels := {}
	for v in traffic.vehicles:
		for n in v.find_children("*", "Label3D", true, false):
			labels[n.text] = true
	check(labels.has("সিএনজি") or labels.has("ঢাকা মেট্রো-থ ১১-৪২৭৫"), "CNGs carry Bangla lettering")
	var bus_route := false
	for t in labels:
		if "পরিবহন" in t or " - " in t:
			bus_route = true
	check(bus_route, "Buses carry Bangla route/company boards")


## Lets the traffic run with the player parked in a lane on Mirpur Road.
func _simulate(seconds: float) -> void:
	_place_player(Vector3(-4, 0.05, 42), 0.0)
	player.controls_enabled = false  # parked: ignore any real keyboard input
	var crashes := []
	var cb := func(sev, imp, other):
		crashes.append([sev, snappedf(imp, 0.1), str(other.name) if other else "?"])
		if other and "lat" in other:
			print("  diag  hit by %s: speed %.1f lat %.2f->%.2f turn=%s ignore_ai=%s gap_v %.1f blocker=%s stuck %.1f player_local %s" % [
				other.name, other.speed, other.lat, other._lat_target, other._pieces[0].is_turn(),
				traffic.time < other._ignore_ai_until, other._gap_speed,
				str(other._blocker.node.name) if not other._blocker.is_empty() else "-", other.stuck_time,
				other.global_transform.affine_inverse() * player.global_position])
	player.crashed.connect(cb)
	var vehicles: Array = traffic.vehicles
	print("  info  camera frustum test at player: ", world.get_node("ChaseCamera").is_position_in_frustum(player.global_position + Vector3(0, 1, -5)))
	var travelled := {}
	var last_pos := {}
	var max_stuck := {}
	for v in vehicles:
		travelled[v] = 0.0
		last_pos[v] = v.global_position
		max_stuck[v] = 0.0
	var off_road := 0
	var overlaps := 0
	var samples := 0
	var ticks := int(seconds * 60.0)
	var horns_before: int = traffic.horn_count
	for t in ticks:
		await get_tree().physics_frame
		for v in vehicles:
			var p: Vector3 = v.global_position
			var step := p.distance_to(last_pos[v])
			if step < 5.0:  # ignore recycling jumps
				travelled[v] += step
			last_pos[v] = p
			if v.stuck_time > max_stuck[v]:
				max_stuck[v] = v.stuck_time
				if v.stuck_time > 30.0 and int(v.stuck_time * 60.0) % 300 == 0:
					print("  diag  %s stuck %.0f s at %s, blocker %s, ignore_ai %s, lat %.2f->%.2f, overtake_until %.1f, dist to player %.1f" % [
						v.name, v.stuck_time, v.get_center(), str(v._blocker.node.name) if not v._blocker.is_empty() else "-",
						traffic.time < v._ignore_ai_until, v.lat, v._lat_target, v._overtake_until - traffic.time, v.dist_to_player])
		if t % 30 == 0:
			for i in vehicles.size():
				var a = vehicles[i]
				var ca: Vector3 = a.get_center()
				samples += 1
				if not CityLayout.is_road(ca.x, ca.z):
					off_road += 1
					if off_road <= 5:
						print("  diag  off road: %s at %s, lat %.2f, dist to player %.0f, speed %.1f, turn %s" % [a.name, ca, a.lat, a.dist_to_player, a.speed, a._pieces[0].is_turn()])
				for j in range(i + 1, vehicles.size()):
					var b = vehicles[j]
					if ca.distance_to(b.get_center()) < (a.half.x + b.half.x) * 0.5:
						overlaps += 1
	player.crashed.disconnect(cb)
	player.controls_enabled = true
	var moving := 0
	var slowest := 1e9
	var worst_stuck := 0.0
	for v in vehicles:
		if travelled[v] > 100.0 * seconds / 120.0:
			moving += 1
		slowest = minf(slowest, travelled[v])
		worst_stuck = maxf(worst_stuck, max_stuck[v])
	print("  info  %.0f s simulated: %d/%d vehicles drove >100 m (least %.0f m), worst stuck %.1f s, recycled %d, horns %d" % [
		seconds, moving, vehicles.size(), slowest, worst_stuck, traffic.recycled_count, traffic.horn_count - horns_before])
	print("  info  off-road samples %d / %d, heavy overlaps %d, hits on parked player %s" % [off_road, samples, overlaps, crashes])
	check(moving >= int(vehicles.size() * 0.9), "Traffic keeps flowing (90%%+ of vehicles drove over %.0f m)" % (100.0 * seconds / 120.0))
	check(worst_stuck < 35.0, "No vehicle stays stuck for good (worst %.1f s)" % worst_stuck)
	check(off_road == 0, "Vehicles never leave the road")
	check(overlaps <= samples / 100, "Vehicles rarely overlap each other (%d)" % overlaps)
	check(traffic.horn_count - horns_before > 0, "Vehicles honk")
	var hard_hits := crashes.filter(func(c): return c[0] >= 1)
	check(hard_hits.is_empty(), "Traffic does not ram the parked player (hard hits: %s)" % [hard_hits])


## A car coming up behind the parked player must stop, then go round.
func _check_stops_for_player() -> void:
	_place_player(Vector3(-4, 0.05, 40), 0.0)
	player.controls_enabled = false
	var net = traffic.network
	var car = null
	for v in traffic.vehicles:
		if v.vehicle_type == "car":
			car = v
			break
	# Find Mirpur Road's northbound lane segment that contains z = 40.
	var lane := -1
	for id in net.edges.size():
		var e: Dictionary = net.edges[id]
		if absf(e.start.x + 4.0) < 0.01 and e.dir.z < -0.9 and e.start.z > 40.0 and e.end.z < 40.0:
			lane = id
	check(lane >= 0, "Found Mirpur Road northbound lane")
	# Clear the lane of other traffic first.
	for v in traffic.vehicles:
		if v != car and v.current_edge == lane:
			traffic._place_somewhere(v, 60.0, false)
	var e: Dictionary = net.edges[lane]
	car.place(lane, (e.start.z - 40.0) - 25.0)  # 25 m behind the player
	car.speed = 8.0
	car._ignore_ai_until = 0.0
	var min_gap := 1e9
	var stopped := false
	var passed := false
	var crashed := [false]
	var cb := func(sev, imp, other):
		if other == car:
			crashed[0] = true
			print("  info  car touched player: severity %d, impact %.1f, car lat %.2f->%.2f speed %.1f, player in car frame %s" % [
				sev, imp, car.lat, car._lat_target, car.speed, car.global_transform.affine_inverse() * player.global_position])
	player.crashed.connect(cb)
	for t in 60 * 30:
		await get_tree().physics_frame
		var gap: float = (car.get_center() - player.global_position).length()
		min_gap = minf(min_gap, gap)
		if car.speed < 0.3 and gap < 8.0:
			stopped = true
		if car.global_position.z < player.global_position.z - 4.0:
			passed = true
			break
	player.crashed.disconnect(cb)
	player.controls_enabled = true
	if not passed:
		print("  diag  car not past: speed %.1f lat %.2f->%.2f blocker %s gap_v %.1f blocked %.1f s, overtake_until %.1f, player_local %s" % [
			car.speed, car.lat, car._lat_target, str(car._blocker.node.name) if not car._blocker.is_empty() else "-",
			car._gap_speed, car.blocked_time, car._overtake_until - traffic.time, car.global_transform.affine_inverse() * player.global_position])
	print("  info  car vs parked player: stopped=%s, closest %.1f m, passed=%s" % [stopped, min_gap, passed])
	check(stopped or passed, "A car behind the parked player slows/stops for it")
	check(not crashed[0], "The car does not crash into the player")
	check(passed, "The car eventually goes round the player")


## Riding into a stationary bus is a real accident, and the bus reacts.
func _check_crash_into_bus() -> void:
	var bus = null
	for v in traffic.vehicles:
		if v.vehicle_type == "bus":
			bus = v
			break
	var net = traffic.network
	# Put the bus on Farmgate Road's eastbound lane and hold it there.
	var lane := -1
	for id in net.edges.size():
		var e: Dictionary = net.edges[id]
		if absf(e.start.z + 3.5) < 0.01 and e.dir.x > 0.9 and e.start.x > 5.0 and e.start.x < 10.0:
			lane = id
	for v in traffic.vehicles:
		if v != bus and v.current_edge == lane:
			traffic._place_somewhere(v, 60.0, false)
	bus.place(lane, 25.0)
	bus._stopped_until = traffic.time + 30.0
	await frames(5)
	var c: Vector3 = bus.get_center()
	# Pedal into the back of the stopped bus along its lane at full speed.
	var dir: Vector3 = net.edges[lane].dir
	_place_player(c - dir * 18.0 + Vector3(0, 0.05, 0), atan2(-dir.x, -dir.z))
	var crashes := []
	var cb := func(sev, imp, other): crashes.append([sev, imp, other])
	player.crashed.connect(cb)
	var honks := [0]
	var hb := func(_v): honks[0] += 1
	bus.honked.connect(hb)
	var acc_before: int = GameManager.accidents
	Input.action_press("accelerate")
	for t in 240:
		await get_tree().physics_frame
		if not crashes.is_empty():
			break
	Input.action_release("accelerate")
	await frames(10)
	player.crashed.disconnect(cb)
	bus.honked.disconnect(hb)
	var first = crashes[0] if not crashes.is_empty() else null
	print("  info  crash into bus: ", [first[0], snappedf(first[1], 0.1)] if first else "none")
	check(first != null and first[2] == bus, "Riding into a bus registers a collision with the bus")
	check(first != null and first[0] >= 1, "Hitting a bus at speed is at least a medium accident")
	check(GameManager.accidents > acc_before, "Accident counter goes up")
	check(honks[0] > 0, "The bus honks back after being hit")
	bus._stopped_until = 0.0


# --- Visual and performance checks -------------------------------------------------

func _screenshots() -> void:
	var cam := Camera3D.new()
	world.add_child(cam)
	var showcase := [["bus", "m3_01_bus.png"], ["cng", "m3_02_cng.png"], ["car", "m3_03_car.png"],
		["microbus", "m3_04_microbus.png"], ["motorcycle", "m3_05_motorcycle.png"], ["rickshaw", "m3_06_rickshaw.png"]]
	for s in showcase:
		var v = null
		for cand in traffic.vehicles:
			if cand.vehicle_type == s[0]:
				v = cand
				break
		var c: Vector3 = v.get_center()
		var size: float = maxf(v.half.z, 1.2)
		cam.current = true
		cam.global_position = v.global_transform * Vector3(size * 1.6, size * 0.7 + 1.0, size * 1.4)
		cam.look_at(c + Vector3(0, v.half.y * 0.7, 0))
		await frames(1)
		await shot(s[1])
	cam.current = false
	cam.queue_free()
	world.get_node("ChaseCamera").current = true
	# Gameplay view: the player waiting at Farmgate amid traffic.
	_place_player(Vector3(-4, 0.05, 14), 0.0)
	await frames(60 * 6)
	await shot("m3_07_farmgate_traffic.png")
	_place_player(Vector3(-56.5, 0.05, 30), 0.0)
	await frames(60 * 4)
	await shot("m3_08_lane_traffic.png")


func _perf_probe() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var worst := 1e9
	for s in [[Vector3(-4, 0.05, 20), 0.0], [Vector3(-100, 0.05, -2.5), -PI * 0.5]]:
		_place_player(s[0], s[1])
		await get_tree().create_timer(1.0).timeout
		var f0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_msec()
		await get_tree().create_timer(3.0).timeout
		var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		print("  info  perf at %s: %.0f FPS, %d draw calls" % [s[0], fps, draws])
		worst = minf(worst, fps)
	print("  info  memory: %.0f MB RAM" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	check(worst > 60.0, "Worst-case FPS with traffic above 60 (%.0f)" % worst)
