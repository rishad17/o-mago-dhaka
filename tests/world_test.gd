## Automated Milestone 2 test: the Dhaka neighbourhood.
##
## Checks the map data, that every destination is reachable by road, that
## nothing blocks the lanes, that destination zones work, and drives the real
## rickshaw round a loop of streets with a simple autopilot.
##
## Run (from the project folder):
##   godot --path . res://tests/world_test.tscn             (with screenshots + FPS)
##   godot --headless --path . res://tests/world_test.tscn  (logic only)
## Optional: -- --shots=C:/some/folder
## In windowed mode, don't click away from the game window while it runs.
extends Node

const WORLD := preload("res://scenes/main_world.tscn")
const CityLayout := preload("res://scripts/city_layout.gd")
const PlayerRickshaw := preload("res://scripts/player_rickshaw.gd")
## Half-size of the rickshaw's collision box, used for clearance checks.
const RICKSHAW_HALF := Vector3(0.65, 0.95, 1.2)

var world: Node3D
var player: PlayerRickshaw
var city: Node3D
var dest_manager: Node3D
var failures: Array[String] = []
var shots_dir := "user://test_shots_m2"
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
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	# This test checks the map itself and its autopilot ignores traffic, so the
	# traffic is removed here (tests/traffic_test.tscn covers traffic).
	var traffic := world.get_node_or_null("TrafficController")
	if traffic:
		world.remove_child(traffic)
		traffic.free()
	add_child(world)
	player = world.get_node("PlayerRickshaw")
	city = world.get_node("City")
	dest_manager = world.get_node("DestinationManager")
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


func _place(pos: Vector3, yaw: float) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	player.velocity = Vector3.ZERO
	player.speed = 0.0
	player.reset_physics_interpolation()
	world.get_node("ChaseCamera").snap_to_target()


func _run() -> void:
	print("== Dhakar Rickshaw: Milestone 2 world test ==")
	await frames(20)
	_check_layout()
	_check_connectivity()
	_check_clearance()
	_check_city_content()
	await _check_zones()
	await _autopilot_loop()
	if not headless:
		await _screenshots()
		await _perf_probe()
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


# --- Map data ---------------------------------------------------------------------

func _check_layout() -> void:
	var dests := CityLayout.destinations()
	var names := {}
	for d in dests:
		names[d.name] = true
	check(dests.size() >= 8, "At least 8 passenger destinations (%d)" % dests.size())
	check(names.size() == dests.size(), "Destination names are unique")
	for required in ["নিউ মার্কেট", "ফার্মগেট", "মিরপুর রোড", "চায়ের দোকান", "ব্র্যাক বিশ্ববিদ্যালয়", "বাসস্ট্যান্ড", "আবাসিক এলাকা", "কারওয়ান বাজার"]:
		check(names.has(required), "Destination exists: " + required)
	for d in dests:
		var p: Vector3 = d.position
		check(CityLayout.is_road(p.x, p.z), "Destination '%s' is on a road" % d.name)
	var closest := 1e9
	for i in dests.size():
		for j in range(i + 1, dests.size()):
			closest = minf(closest, dests[i].position.distance_to(dests[j].position))
	check(closest > 11.0, "Drop-off zones don't overlap (closest pair %.1f m apart)" % closest)
	var blocks := CityLayout.block_rects()
	check(blocks.size() > 40, "City has %d blocks" % blocks.size())
	check(CityLayout.area_name_at(0, 0) == "ফার্মগেট", "Area name at the centre is ফার্মগেট")
	check(CityLayout.area_name_at(-4, 90) == "মিরপুর রোড", "Area name on the main road is মিরপুর রোড")


## Flood fill over road cells (shrunk by the rickshaw's half width) to prove
## the whole road network is one connected piece and every destination is in it.
func _check_connectivity() -> void:
	var step := 2.0  # 2 m cells keep this quick on the big map
	var m := CityLayout.MAP
	var nx := int(m.size.x / step)
	var n := int(m.size.y / step)  # cells per column
	var clearance := 0.9
	var drivable := PackedByteArray()
	drivable.resize(nx * n)
	var total := 0
	for i in nx:
		for j in n:
			var x := m.position.x + (i + 0.5) * step
			var z := m.position.y + (j + 0.5) * step
			var ok := CityLayout.is_road(x, z)
			for o in [Vector2(clearance, 0), Vector2(-clearance, 0), Vector2(0, clearance), Vector2(0, -clearance)]:
				ok = ok and CityLayout.is_road(x + o.x, z + o.y)
			drivable[i * n + j] = 1 if ok else 0
			total += 1 if ok else 0
	var start := player.global_position
	var si := int((start.x - m.position.x) / step)
	var sj := int((start.z - m.position.y) / step)
	check(drivable[si * n + sj] == 1, "Spawn point is on a drivable road")
	var seen := PackedByteArray()
	seen.resize(nx * n)
	var queue: Array[Vector2i] = [Vector2i(si, sj)]
	seen[si * n + sj] = 1
	var reached := 0
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		reached += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if q.x < 0 or q.y < 0 or q.x >= nx or q.y >= n:
				continue
			var k := q.x * n + q.y
			if drivable[k] == 1 and seen[k] == 0:
				seen[k] = 1
				queue.append(q)
	check(reached == total, "All %d drivable road cells are connected (reached %d)" % [total, reached])
	for d in CityLayout.destinations():
		var p: Vector3 = d.position
		var k := int((p.x - m.position.x) / step) * n + int((p.z - m.position.y) / step)
		check(seen[k] == 1, "Destination '%s' is reachable from spawn" % d.name)


## Places the rickshaw's collision box along every road (both directions)
## and at every destination; nothing solid may overlap it.
func _check_clearance() -> void:
	var space := world.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = RICKSHAW_HALF * 2.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	var blocked: Array[String] = []
	var tested := 0
	var points: Array = []
	for r in CityLayout.VERTICAL_ROADS:
		var z := CityLayout.v_from(r) + 3.0
		while z < CityLayout.v_to(r) - 3.0:
			for lane in [-0.25, 0.25]:
				points.append([Vector3(r[0] + lane * r[1], RICKSHAW_HALF.y + 0.05, z), 0.0])
			z += 3.0
	for r in CityLayout.HORIZONTAL_ROADS:
		var x := CityLayout.h_from(r) + 3.0
		while x < CityLayout.h_to(r) - 3.0:
			for lane in [-0.25, 0.25]:
				points.append([Vector3(x, RICKSHAW_HALF.y + 0.05, r[0] + lane * r[1]), PI * 0.5])
			x += 3.0
	for d in CityLayout.destinations():
		points.append([d.position + Vector3(0, RICKSHAW_HALF.y + 0.05, 0), 0.0])
		points.append([d.position + Vector3(0, RICKSHAW_HALF.y + 0.05, 0), PI * 0.5])
	for pt in points:
		q.transform = Transform3D(Basis(Vector3.UP, pt[1]), pt[0])
		tested += 1
		var hits := space.intersect_shape(q, 1)
		if not hits.is_empty() and blocked.size() < 10:
			blocked.append(str(pt[0]))
	check(blocked.is_empty(), "No obstacles in the lanes (%d placements tested) %s" % [tested, ", ".join(blocked)])


func _check_city_content() -> void:
	print("  info  buildings: %d, Bangla labels: %d" % [city.building_count, city.label_count])
	check(city.building_count > 150, "City has many buildings (%d)" % city.building_count)
	var texts := {}
	for n in city.get_children():
		if n is Label3D:
			texts[n.text] = true
	for t in ["নিউ মার্কেট", "ফার্মগেট", "ব্র্যাক বিশ্ববিদ্যালয়", "বাসস্ট্যান্ড", "কারওয়ান বাজার", "ঢাকা টি স্টল",
			"আবাসিক এলাকা", "স্থানীয় বাজার", "মিরপুর রোড", "পান্থপথ", "রাস্তা পারাপার", "ধীরে চলুন",
			"বিসমিল্লাহ ফার্মেসি", "চা ও নাস্তা"]:
		check(texts.has(t), "Bangla sign present: " + t)


# --- Destination zones ------------------------------------------------------------

func _check_zones() -> void:
	var zones: Array = dest_manager.zones
	check(zones.size() == CityLayout.destinations().size(), "One zone per destination (%d)" % zones.size())
	var all_hidden := true
	for z in zones:
		all_hidden = all_hidden and not z.get_node("Marker").visible
	check(all_hidden, "Zone markers are hidden until a trip needs them")
	var nm = dest_manager.get_zone("নিউ মার্কেট")
	check(nm != null, "Zone lookup by Bangla name works")
	var picked = dest_manager.pick_destination(nm.global_position, 60.0, nm)
	check(picked != null and picked != nm and picked.global_position.distance_to(nm.global_position) >= 60.0,
		"pick_destination gives a different, distant zone (%s)" % (picked.zone_name if picked else "none"))
	dest_manager.set_active_zone(nm)
	check(nm.get_node("Marker").visible and not picked.get_node("Marker").visible, "Only the active zone's marker is visible")
	# Drive into the zone: the Area3D must notice the rickshaw.
	_place(nm.global_position + Vector3(0, 0.05, 8.0), 0.0)
	await frames(5)
	check(not nm.player_inside, "Rickshaw outside the zone is not detected")
	player.speed = 3.0
	Input.action_press("accelerate", 0.3)
	await frames(150)
	Input.action_release("accelerate")
	check(nm.player_inside, "Rickshaw driving into the zone is detected")
	check(dest_manager.zone_at(player.global_position) == nm, "zone_at() finds the zone at the rickshaw")
	await frames(30)
	world._update_area()
	var area_label: Label = world.get_node("HUD/AreaName")
	print("  info  HUD area: ", area_label.text)
	check(area_label.text.begins_with("এলাকা: "), "HUD shows the area name")
	dest_manager.set_active_zone(null)


# --- Driving round the streets ----------------------------------------------------

## Drives a loop with four left turns through intersections of different
## widths, including under the Farmgate footbridge.
func _autopilot_loop() -> void:
	# Waypoints sit where the left-hand lanes cross (Bangladesh drives on the
	# left), so each turn is a proper corner rather than a diagonal shortcut.
	var route := [
		Vector2(-4, 10), Vector2(-4, -57.5), Vector2(-48, -57.5), Vector2(-57.5, -57.5),
		Vector2(-57.5, -12), Vector2(-57.5, -3.5), Vector2(-14, -3.5), Vector2(-4, -3.5),
		Vector2(-4, -30),
	]
	_place(Vector3(-4, 0.05, 42), 0.0)
	await frames(5)
	var crashes := []
	var cb := func(sev, imp, _o): crashes.append([sev, snappedf(imp, 0.1)])
	player.crashed.connect(cb)
	var idx := 0
	var ticks := 0
	var max_ticks := 60 * 90
	while idx < route.size() and ticks < max_ticks:
		var target: Vector2 = route[idx]
		var pos := Vector2(player.global_position.x, player.global_position.z)
		var dist := pos.distance_to(target)
		if dist < 3.0:
			idx += 1
			continue
		# Slow to walking pace before a sharp corner, like a real rickshaw puller.
		var target_speed := 7.0
		if idx + 1 < route.size() and dist < 10.0:
			var leg_in: Vector2 = target - pos
			var leg_out: Vector2 = route[idx + 1] - target
			if absf(leg_in.angle_to(leg_out)) > 0.7:
				target_speed = 2.0
		var to := (target - pos).normalized()
		var fwd3 := -player.global_transform.basis.z
		var fwd := Vector2(fwd3.x, fwd3.z).normalized()
		var err := fwd.angle_to(to)  # positive = target to the right (clockwise on screen)
		var steer := clampf(-err * 2.5, -1.0, 1.0)
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		if steer > 0.05:
			Input.action_press("steer_left", steer)
		elif steer < -0.05:
			Input.action_press("steer_right", -steer)
		if absf(err) > 0.5:
			target_speed = minf(target_speed, 2.5)
		Input.action_release("accelerate")
		Input.action_release("brake_reverse")
		if player.speed > target_speed + 0.4:
			Input.action_press("brake_reverse", 0.7)
		elif player.speed < target_speed:
			Input.action_press("accelerate")
		await get_tree().physics_frame
		ticks += 1
	for a in ["accelerate", "brake_reverse", "steer_left", "steer_right"]:
		Input.action_release(a)
	player.crashed.disconnect(cb)
	print("  info  autopilot: %d/%d waypoints in %.1f s, collisions %s" % [idx, route.size(), ticks / 60.0, crashes])
	check(idx == route.size(), "Autopilot drove the whole loop through 4 intersections")
	var heavy := crashes.filter(func(c): return c[0] >= 1)
	check(heavy.is_empty(), "No medium/heavy crashes on the loop")


# --- Visual checks ----------------------------------------------------------------

func _screenshots() -> void:
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.far = 600.0
	# Map overview from above (orthographic).
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CityLayout.MAP.size.y + 10.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = CityLayout.MAP.size.x + 10.0
	cam.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(CityLayout.MAP.get_center().x, 200, 0))
	world.get_node("WorldEnvironment").environment.fog_enabled = false
	await frames(5)
	await shot("m2_01_map_overview.png")
	world.get_node("WorldEnvironment").environment.fog_enabled = true
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 70.0
	dest_manager.show_all_markers = true
	dest_manager.set_active_zone(null)
	var views := [
		["m2_02_new_market.png", Vector3(10, 7, -20), Vector3(-14, 4, -32)],
		["m2_03_farmgate_footbridge.png", Vector3(-4, 3, 16), Vector3(0, 3, -17)],
		["m2_04_university_gate.png", Vector3(113, 5, -66), Vector3(98, 8, -84)],
		["m2_05_mosque.png", Vector3(8, 5, -80), Vector3(-14, 6, -98)],
		["m2_06_karwan_bazar.png", Vector3(-30, 5, -6), Vector3(-30, 2, 12)],
		["m2_07_residential.png", Vector3(82, 4, 50), Vector3(82, 3, 66)],
		["m2_08_market_street.png", Vector3(-56.5, 3, 40), Vector3(-56.5, 2, 10)],
		["m2_09_tea_stall_bus_stand.png", Vector3(3, 3, 22), Vector3(-7, 1.5, 30)],
	]
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2])
		await frames(4)
		await shot(v[0])
	cam.queue_free()
	dest_manager.show_all_markers = false
	dest_manager.set_active_zone(null)
	# Normal gameplay view near Farmgate with the area name in the HUD.
	_place(Vector3(-4, 0.05, 20), 0.0)
	await frames(10)
	world._update_area()
	await shot("m2_10_gameplay_farmgate.png")


func _perf_probe() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var spots := [[Vector3(-4, 0.05, 100), 0.0], [Vector3(-100, 0.05, -2.5), -PI * 0.5], [Vector3(122.5, 0.05, 100), 0.0]]
	var worst := 1e9
	for s in spots:
		_place(s[0], s[1])
		Input.action_press("accelerate")
		await get_tree().create_timer(0.7).timeout
		var f0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_msec()
		await get_tree().create_timer(2.5).timeout
		var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)
		Input.action_release("accelerate")
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		print("  info  perf at %s: %.0f FPS, %d draw calls, %d primitives" % [s[0], fps, draws, prims])
		worst = minf(worst, fps)
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	print("  info  memory: %.0f MB RAM, %.0f MB VRAM" % [mem, vram])
	check(worst > 60.0, "Worst-case FPS above 60 (%.0f)" % worst)
