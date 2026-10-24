## Automated test: riding on footpaths, smashing stalls, knocking bikers off
## their motorbikes, and pedestrians' "ও মাগো!".
##
## Run (from the project folder):
##   godot --headless --fixed-fps 60 --path . res://tests/street_test.tscn
##   godot --path . res://tests/street_test.tscn      (screenshots)
## Optional: -- --shots=C:/some/folder
extends Node

const CityLayout := preload("res://scripts/city_layout.gd")

const WORLD := preload("res://scenes/main_world.tscn")
const PlayerRickshaw := preload("res://scripts/player_rickshaw.gd")
const Pedestrian := preload("res://scripts/pedestrian.gd")
const PersonModel := preload("res://scripts/person_model.gd")

var world: Node3D
var player: PlayerRickshaw
var city: Node3D
var bm: Node3D
var traffic: Node3D
var failures: Array[String] = []
var shots_dir := "user://test_shots_street"
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
	world = WORLD.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	# The staged scenes need the street to themselves.
	world.get_node("TrafficController").nearby_target = 0
	world.get_node("PedestrianManager").nearby_target = 0
	add_child(world)
	player = world.get_node("PlayerRickshaw")
	city = world.get_node("City")
	bm = world.get_node("BreakableManager")
	traffic = world.get_node("TrafficController")
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


## Screenshot from a separate camera looking at `target` (windowed runs only).
func side_shot(file_name: String, target: Vector3, from: Vector3) -> void:
	if headless:
		return
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.global_position = from
	cam.look_at(target)
	await shot(file_name)
	cam.queue_free()
	world.get_node("ChaseCamera").current = true


func _place(pos: Vector3, yaw: float, spd := 0.0) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.05, pos.z))
	player.speed = spd
	player.velocity = Vector3.ZERO
	player._crash_cooldown = 0.0
	player.reset_physics_interpolation()
	world.get_node("ChaseCamera").snap_to_target()


func _clear_traffic_near(point: Vector3, radius: float, keep: Node = null) -> void:
	for v in traffic.vehicles:
		if v != keep and v.global_position.distance_to(point) < radius:
			traffic._place_somewhere(v, radius + 60.0, false)


func _run() -> void:
	print("== Dhakar Rickshaw: footpaths, breakable stalls, motorbike crashes ==")
	await frames(5)
	player.controls_enabled = false
	await _footpath()
	await _solid_pole()
	await _break_stall()
	await _park_bench()
	await _tea_stall_and_repair()
	await _bike_crash()
	_omago()
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


# --- Footpaths -------------------------------------------------------------------------

func _footpath() -> void:
	# The open footpath corner at Farmgate (south-west of the junction's
	# north-west block has no poles, trees or buildings).
	_clear_traffic_near(Vector3(-6, 0, 9), 30.0)
	_place(Vector3(-4.0, 0, 9.0), PI * 0.5, 4.0)
	check(not player.on_footpath, "Starts on the road")
	var lifted := 0.0
	var crashes := [0]
	var cb := func(_s, _i, _o): crashes[0] += 1
	player.crashed.connect(cb)
	for i in 130:
		await get_tree().physics_frame
		lifted = maxf(lifted, player.get_node("Model").position.y)
	player.crashed.disconnect(cb)
	print("  info  footpath: x %.2f, model lifted %.2f m, speed %.1f m/s" % [player.global_position.x, lifted, player.speed])
	check(player.global_position.x < -8.3, "The rickshaw rides over the kerb onto the footpath")
	check(player.on_footpath, "…and knows it is on the footpath")
	check(lifted > 0.1, "Its body rises onto the 15 cm footpath")
	check(crashes[0] == 0, "Riding up the kerb is not a crash")
	check(player.speed > 1.5, "…and keeps moving (%.1f m/s)" % player.speed)
	await shot("street_01_on_footpath.png")


func _solid_pole() -> void:
	# The first electric pole on Mirpur Road's west footpath (north of Farmgate road).
	_clear_traffic_near(Vector3(-8.6, 0, 16), 30.0)
	_place(Vector3(-8.6, 0, 18.0), 0.0, 4.0)
	var hits := []
	var cb := func(s, i, o): hits.append([s, o.name if o else "-"])
	player.crashed.connect(cb)
	for i in 120:
		await get_tree().physics_frame
		if not hits.is_empty():
			break
	player.crashed.disconnect(cb)
	print("  info  ride into pole: ", hits, " stopped at z %.2f" % player.global_position.z)
	check(not hits.is_empty(), "Electric poles on the footpath are solid")
	check(player.global_position.z > 13.0, "…the rickshaw doesn't pass through it")


# --- Breakable props --------------------------------------------------------------------

func _find_prop(kind: String) -> Dictionary:
	for rec in city.props:
		if rec.kind == kind and not rec.broken:
			return rec
	return {}


## Benches in Gulshan Lake Park break just like the ones on the footpaths.
func _park_bench() -> void:
	var rec := {}
	for r in city.props:
		if r.kind == "bench" and not r.broken and CityLayout.PARK.has_point(Vector2(r.center.x, r.center.z)):
			rec = r
			break
	check(not rec.is_empty(), "The park has breakable benches")
	if rec.is_empty():
		return
	var along: Vector3 = rec.xf.basis.x
	_place(rec.center - along * 4.5, atan2(-along.x, -along.z), 4.0)
	for i in 90:
		await get_tree().physics_frame
		if rec.broken:
			break
	check(rec.broken, "Riding into a park bench smashes it")
	await frames(30)


func _break_stall() -> void:
	check(city.props.size() > 20, "Footpaths have breakable stalls and benches (%d)" % city.props.size())
	var rec := _find_prop("stall")
	check(not rec.is_empty(), "There are vegetable stalls")
	var along: Vector3 = rec.xf.basis.x  # direction along the footpath
	var start: Vector3 = rec.center - along * 4.5
	_clear_traffic_near(start, 30.0)
	_place(start, atan2(-along.x, -along.z), 4.0)
	messages.clear()
	var acc_before: int = GameManager.accidents
	var dmg_before: float = GameManager.damage
	for i in 90:
		await get_tree().physics_frame
		if rec.broken:
			break
	await frames(3)
	print("  info  stall smashed: %s, debris pieces %d, speed after %.1f m/s" % [rec.broken, bm._debris.size(), player.speed])
	check(rec.broken, "Riding into a vegetable stall smashes it")
	check(bm._debris.size() >= 8, "Vegetables and planks fly everywhere (%d pieces)" % bm._debris.size())
	check("দোকান ভেঙে গেল!" in messages, "Bangla message: দোকান ভেঙে গেল!")
	check(GameManager.accidents == acc_before + 1, "Smashing a stall at speed counts as an accident")
	check(GameManager.damage > dmg_before, "…and dents the rickshaw a little")
	check(player.speed > 1.0, "The rickshaw ploughs through instead of stopping (%.1f m/s)" % player.speed)
	var shouts := 0
	for n in bm.get_children():
		if n is Label3D and n.text in bm.SHOUTS.stall:
			shouts += 1
	check(shouts == 1, "The shopkeeper shouts in Bangla")
	var out: Vector3 = -(rec.xf.basis.z as Vector3)  # from the footpath towards the road
	await frames(6)
	await side_shot("street_02_stall_smashed.png", rec.center, rec.center - out * 6.0 + along * 3.0 + Vector3(0, 2.5, 0))
	await frames(90)
	var landed := 0
	for d in bm._debris:
		if d.node.global_position.y < 0.5:
			landed += 1
	check(landed >= 6, "Debris lands on the ground and lingers a moment (%d pieces down)" % landed)
	await frames(360)
	check(bm._debris.is_empty(), "Debris clears up after a few seconds")


func _tea_stall_and_repair() -> void:
	var tea := _find_prop("tea")
	check(not tea.is_empty() and not tea.labels.is_empty(), "The tea stall (চায়ের দোকান) is breakable too")
	_place(Vector3(-100, 0, 100), 0.0)  # far away
	bm.break_prop(tea)
	await frames(2)
	check(not tea.labels[0].visible, "Its sign disappears with it")
	var stall := {}
	for rec in city.props:
		if rec.broken and rec.kind == "stall":
			stall = rec
	bm._time += bm.REPAIR_AFTER + 1.0
	bm._repair_props()
	check(not tea.broken and tea.labels[0].visible, "Broken shops are rebuilt later, out of sight")
	check(stall.is_empty() or not stall.broken, "…the vegetable stall too")


# --- Motorbike crash ----------------------------------------------------------------------

func _bike_crash() -> void:
	var bike = null
	for v in traffic.vehicles:
		if v.vehicle_type == "motorcycle" and v._variant % 2 == 1:
			bike = v  # one with a passenger
			break
	check(bike != null, "Found a motorbike carrying a passenger")
	if bike == null:
		return
	var net = traffic.network
	var lane := -1
	for id in net.edges.size():
		var e: Dictionary = net.edges[id]
		if absf(e.start.x + 4.0) < 0.01 and e.dir.z < -0.9 and e.start.z > 40.0 and e.end.z < 40.0:
			lane = id
	_clear_traffic_near(Vector3(-4, 0, 60), 50.0, bike)
	bike.place(lane, 20.0)
	bike._stopped_until = traffic.time + 3.0
	await frames(3)
	var c: Vector3 = bike.get_center()
	_place(c + Vector3(0, 0, 5.0), 0.0, 4.0)
	for i in 60:
		await get_tree().physics_frame
		if bike.bike_down:
			break
	await frames(20)
	print("  info  bike down: %s, riders on the ground: %d, bike tilt %.2f rad" % [bike.bike_down, bike._fallen.size(), bike._model.rotation.z])
	check(bike.bike_down, "Hitting a motorbike knocks it over")
	check(bike._fallen.size() == 2, "Both the rider and the passenger fall off")
	check(absf(bike._model.rotation.z) > 1.0, "The bike lies on its side")
	var fallen_ok := true
	var said: Array[String] = []
	for p in bike._fallen:
		fallen_ok = fallen_ok and p.pose == PersonModel.Pose.FALLEN
		for n in p.get_children():
			if n is Label3D:
				said.append(n.text)
	check(fallen_ok, "They lie dazed on the road")
	print("  info  bikers shout: ", said)
	check(said.size() == 2, "Both shout in Bangla")
	var c0: Vector3 = bike.get_center()
	var far := true
	for p in bike._fallen:
		far = far and Vector2(p.global_position.x - c0.x, p.global_position.z - c0.z).length() > 1.0
	check(far, "They are thrown clear of the bike")
	await side_shot("street_03_bike_crash.png", c0, c0 + Vector3(6.0, 2.5, 3.0))
	await frames(60 * 9)  # lie dazed 4 s, get up, walk back, lift the bike (~6.5 s)
	check(not bike.bike_down and bike._fallen.is_empty(), "They get up, lift the bike and get back on")
	check(absf(bike._model.rotation.z) < 0.05, "The bike is upright again")
	await frames(120)
	check(bike.speed > 0.5, "…and ride on (%.1f m/s)" % bike.speed)


# --- "ও মাগো!" --------------------------------------------------------------------------

func _omago() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var counts := {}
	for i in 400:
		var t := Pedestrian.random_hit_shout(rng)
		counts[t] = counts.get(t, 0) + 1
	var omago: int = counts.get("ও মাগো!", 0)
	print("  info  400 hit shouts: ও মাগো! x%d, others: %s" % [omago, counts])
	check(omago > 80 and omago < 200, "Pedestrians often cry \"ও মাগো!\" when hit (%d of 400)" % omago)
	var all_old := true
	for line in Pedestrian.HIT_SHOUTS:
		all_old = all_old and counts.has(line)
	check(all_old, "…and the old complaints are all still used")
