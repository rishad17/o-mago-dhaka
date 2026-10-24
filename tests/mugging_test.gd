## Automated test: Mohammadpur and its muggers (ছিনতাইকারী).
##
## Run (from the project folder):
##   godot --headless --fixed-fps 60 --path . res://tests/mugging_test.tscn
##   godot --path . res://tests/mugging_test.tscn      (screenshots)
## Optional: -- --shots=C:/some/folder
extends Node

const WORLD := preload("res://scenes/main_world.tscn")
const CityLayout := preload("res://scripts/city_layout.gd")
const Pedestrian := preload("res://scripts/pedestrian.gd")
const PersonModel := preload("res://scripts/person_model.gd")
const PlayerRickshaw := preload("res://scripts/player_rickshaw.gd")

var world: Node3D
var player: PlayerRickshaw
var mm: Node3D
var peds: Node3D
var traffic: Node3D
var failures: Array[String] = []
var shots_dir := "user://test_shots_mugging"
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
	add_child(world)
	player = world.get_node("PlayerRickshaw")
	mm = world.get_node("MuggingManager")
	peds = world.get_node("PedestrianManager")
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


func shot(file_name: String, target: Vector3 = Vector3.INF, from: Vector3 = Vector3.ZERO) -> void:
	if headless:
		return
	var cam: Camera3D = null
	if target != Vector3.INF:
		cam = Camera3D.new()
		world.add_child(cam)
		cam.current = true
		cam.global_position = from
		cam.look_at(target)
	await RenderingServer.frame_post_draw
	var path := shots_dir.path_join(file_name)
	get_viewport().get_texture().get_image().save_png(path)
	print("  shot  ", ProjectSettings.globalize_path(path))
	if cam:
		cam.queue_free()
		world.get_node("ChaseCamera").current = true


func _place(pos: Vector3, yaw: float, spd := 0.0) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.05, pos.z))
	player.speed = spd
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	world.get_node("ChaseCamera").snap_to_target()


func _clear_traffic_near(point: Vector3, radius: float) -> void:
	for v in traffic.vehicles:
		if v.global_position.distance_to(point) < radius:
			traffic._place_somewhere(v, radius + 60.0, false)


func _run() -> void:
	print("== Dhakar Rickshaw: Mohammadpur muggings ==")
	await frames(5)
	mm.interval = Vector2(9999, 9999)  # only the events this test starts
	mm._timer = 9999.0
	player.controls_enabled = false
	_layout()
	await _warning()
	await _pedestrian_mugging()
	await _catch_pedestrian_mugger()
	await _player_robbed_and_caught()
	await _player_escapes()
	await _random_event()
	await _common_sight()
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _layout() -> void:
	check(CityLayout.area_name_at(-250, -90).begins_with("মোহাম্মদপুর"), "Mohammadpur exists on the map (%s)" % CityLayout.area_name_at(-250, -90))
	check(CityLayout.area_name_at(-224.5, -90) == "মোহাম্মদপুর • নূরজাহান রোড", "On its roads the HUD says মোহাম্মদপুর • road (%s)" % CityLayout.area_name_at(-224.5, -90))
	check(CityLayout.area_name_at(-200, -90) == "মোহাম্মদপুর" and not CityLayout.is_road(-200, -90), "A strip of buildings separates it from the city (%s)" % CityLayout.area_name_at(-200, -90))
	check(CityLayout.area_name_at(-200, 0) == "মোহাম্মদপুর • আসাদ এভিনিউ" and CityLayout.area_name_at(-150, 0) == "ফার্মগেট রোড", "The bridge road is আসাদ এভিনিউ in Mohammadpur, ফার্মগেট রোড in the city")
	check(not CityLayout.is_road(-200, -120) and CityLayout.is_road(-200, 0) and CityLayout.is_road(-200, -180) and CityLayout.is_road(-200, 180), "Only three bridges cross the canal")
	check(not CityLayout.in_mohammadpur(Vector3(-150, 0, -90)), "The old city side (Lalmatia) is not Mohammadpur any more")
	var names := []
	for d in CityLayout.destinations():
		names.append(d.name)
	check("মোহাম্মদপুর টাউন হল" in names and "সাত গম্বুজ মসজিদ" in names and "মোহাম্মদপুর বাসস্ট্যান্ড" in names, "Mohammadpur destinations: টাউন হল, সাত গম্বুজ মসজিদ, বাসস্ট্যান্ড")
	var signs := {}
	for n in world.get_node("City").get_children():
		if n is Label3D:
			signs[n.text] = true
	check(signs.has("ছিনতাই থেকে সাবধান!") and signs.has("টাউন হল বাজার") and signs.has("মোহাম্মদপুরে স্বাগতম"), "Warning sign, Town Hall market and welcome arch are built")


func _warning() -> void:
	messages.clear()
	_clear_traffic_near(Vector3(-224.5, 0, -90), 40.0)
	_place(Vector3(-224.5, 0, -90), 0.0)
	await frames(3)
	check("সাবধান! মোহাম্মদপুরে ছিনতাই হয়" in messages, "Warning when riding into Mohammadpur")
	messages.clear()
	_place(Vector3(-224.5, 0, -95), 0.0)
	await frames(3)
	check(messages.is_empty(), "…only once")


## A walking pedestrian on a long Mohammadpur footpath, far from the player.
func _victim() -> Node3D:
	var net = peds.network
	for id in net.edges.size():
		var e: Dictionary = net.edges[id]
		var mid: Vector3 = ((e.pa as Vector3) + e.pb) * 0.5
		if e.cross or e.length < 40.0 or absf(mid.x - (-228.5)) > 0.5 or not CityLayout.in_mohammadpur(mid):
			continue
		for p in peds.pedestrians:
			if p.state == Pedestrian.State.WALKING:
				p.place_on_edge(id, 20.0, 1)
				p.walk_speed = 0.6
				return p
	return null


func _pedestrian_mugging() -> void:
	var victim := _victim()
	check(victim != null, "Found a pedestrian in Mohammadpur")
	# On Elephant Road's far lane, ~30 m away: close enough to watch, not in the way.
	_place(Vector3(-219.5, 0, victim.global_position.z + 30.0), PI)
	check(mm.start_pedestrian_mugging(victim), "A mugger sneaks up on the pedestrian")
	var m: Node3D = mm.mugger
	check(m.model.get_node_or_null("Hips") != null and m.model.find_child("Knife", true, false) != null, "The mugger carries a knife")
	check(get_tree().get_nodes_in_group("muggers").size() == 1, "He shows on the mini-map")
	for i in 60 * 15:
		await get_tree().physics_frame
		if mm.phase == mm.Phase.THREATEN:
			break
	check(mm.phase == mm.Phase.THREATEN, "He catches up and threatens with the knife")
	check(victim.state == Pedestrian.State.VICTIM and victim.model.pose == PersonModel.Pose.WAVE, "The victim freezes with hands up")
	check(victim._bubble.text in mm.VICTIM_CRIES, "The victim cries for help (%s)" % victim._bubble.text)
	check(m.model.pose == PersonModel.Pose.WAVE and m._bubble.text in mm.MUGGER_LINES, "The mugger raises the knife: %s" % m._bubble.text)
	await shot("mug_01_threat.png", victim.global_position + Vector3(0, 1, 0), victim.global_position + Vector3(4, 2.2, 3))
	await frames(60 * 3)
	check(mm.phase == mm.Phase.FLEE and m.walk_speed > 3.0, "He grabs the bag and runs")
	check(victim._bubble.text == "ধরুন ওকে! ছিনতাইকারী!", "The victim shouts ধরুন ওকে!")
	var d0: float = m.global_position.distance_to(victim.global_position)
	await frames(60 * 2)
	check(m.global_position.distance_to(victim.global_position) > d0 + 3.0, "He runs away")
	await frames(60 * 3)
	check(victim.state == Pedestrian.State.WALKING, "The shaken victim walks on")
	mm._end_event()
	await frames(2)
	check(mm.phase == mm.Phase.NONE and get_tree().get_nodes_in_group("muggers").is_empty(), "The event cleans up")


## Rides into a fleeing mugger.
func _ram_mugger() -> void:
	var m: Node3D = mm.mugger
	var run_dir: Vector3 = (-m.global_transform.basis.z).normalized()
	# Bystanders on the footpath could get in the way (and slow the rickshaw).
	for ped in peds.pedestrians:
		if ped != mm.victim and ped.state == Pedestrian.State.WALKING and ped.global_position.distance_to(m.global_position) < 8.0:
			peds._place_randomly(ped, 40.0, 1e9, false)
	# Start right behind him at a gentle speed, so trees or poles on the
	# footpath can't get in the way of the test.
	_place(m.global_position - run_dir * 0.4, atan2(-run_dir.x, -run_dir.z), 1.6)
	var hits := []
	var cb := func(sv, im, o): hits.append(o.name if o else "-")
	player.crashed.connect(cb)
	for i in 30:
		await get_tree().physics_frame
		if mm.phase == mm.Phase.CAUGHT:
			break
	player.crashed.disconnect(cb)
	if mm.phase != mm.Phase.CAUGHT:
		print("  diag  ram failed: player %s speed %.2f, mugger %s, crashes %s" % [player.global_position, player.speed, m.global_position if is_instance_valid(m) else Vector3.ZERO, hits])


func _catch_pedestrian_mugger() -> void:
	var victim := _victim()
	_place(Vector3(-219.5, 0, victim.global_position.z + 30.0), PI)
	mm.start_pedestrian_mugging(victim)
	for i in 60 * 20:
		await get_tree().physics_frame
		if mm.phase == mm.Phase.FLEE:
			break
	await frames(20)
	var money: int = GameManager.earnings
	var acc: int = GameManager.accidents
	messages.clear()
	await _ram_mugger()
	print("  info  caught: phase %s, money %d -> %d" % [mm.Phase.keys()[mm.phase], money, GameManager.earnings])
	check(mm.phase == mm.Phase.CAUGHT, "Riding into the fleeing mugger catches him")
	check(mm.mugger.state == Pedestrian.State.KNOCKED and mm.mugger._bubble.text in mm.CAUGHT_LINES, "He falls and begs: %s" % mm.mugger._bubble.text)
	check(GameManager.earnings == money + mm.RESCUE_REWARD, "The grateful victim gives a ৳৫০ reward")
	check(messages.size() > 0 and messages[-1].begins_with("ছিনতাইকারী ধরা পড়েছে!"), "Message: ছিনতাইকারী ধরা পড়েছে!")
	check(GameManager.accidents == acc, "Catching a mugger is not an accident")
	await shot("mug_02_caught.png", mm.mugger.global_position, mm.mugger.global_position + Vector3(4, 2.5, 4))
	await frames(60 * 6)
	check(mm.phase == mm.Phase.NONE, "Afterwards he is gone")


func _player_robbed_and_caught() -> void:
	_clear_traffic_near(Vector3(-224.5, 0, -90), 40.0)
	_place(Vector3(-224.5, 0, -90), 0.0)
	GameManager.earnings = 100
	messages.clear()
	check(mm.start_player_mugging(), "A mugger comes for the stopped rickshaw")
	check(mm.mugger._bubble.text in mm.PLAYER_THREATS, "\"%s\"" % mm.mugger._bubble.text)
	for i in 60 * 12:
		await get_tree().physics_frame
		if mm.phase == mm.Phase.FLEE:
			break
	print("  info  robbed: money %d, stolen %d" % [GameManager.earnings, mm.stolen])
	check(mm.stolen == 40 and GameManager.earnings == 60, "He takes 40% of the day's earnings (৳৪০)")
	check("ছিনতাই হয়ে গেল! −৳৪০" in messages, "Message: ছিনতাই হয়ে গেল! −৳৪০")
	await shot("mug_03_robbed.png")
	await frames(30)
	await _ram_mugger()
	check(mm.phase == mm.Phase.CAUGHT, "Chasing him down catches him")
	check(GameManager.earnings == 60 + 40 + mm.CATCH_BONUS, "Money back plus a ৳২০ reward (now %d)" % GameManager.earnings)
	mm._end_event()
	await frames(2)


func _player_escapes() -> void:
	_clear_traffic_near(Vector3(-224.5, 0, -70), 60.0)
	_place(Vector3(-224.5, 0, -100), 0.0)
	GameManager.earnings = 100
	messages.clear()
	mm.start_player_mugging()
	player.controls_enabled = true
	Input.action_press("accelerate")
	for i in 60 * 10:
		await get_tree().physics_frame
		if mm.phase == mm.Phase.GAVE_UP:
			break
	Input.action_release("accelerate")
	player.controls_enabled = false
	check(mm.phase == mm.Phase.GAVE_UP, "Pedalling away in time escapes the mugger")
	check(GameManager.earnings == 100, "…keeping all the money")
	check("ছিনতাইকারী থেকে বেঁচে গেলেন!" in messages, "Message: ছিনতাইকারী থেকে বেঁচে গেলেন!")
	mm._end_event()
	await frames(2)


func _random_event() -> void:
	_place(Vector3(-224.5, 0, -90), 0.0)
	var before: int = mm.muggings
	mm._timer = 0.05
	await frames(10)
	check(mm.muggings == before + 1 and mm.phase != mm.Phase.NONE, "Muggings also happen on their own in Mohammadpur")
	mm._end_event()
	_place(Vector3(-4, 0, 42), 0.0)  # far from Mohammadpur
	mm._timer = 0.05
	await frames(10)
	check(mm.phase == mm.Phase.NONE, "…but not elsewhere in the city")


## With the game's own timing, muggings are a common sight in Mohammadpur.
func _common_sight() -> void:
	mm._end_event()
	mm.interval = Vector2(6.0, 14.0)
	mm._timer = 4.0
	# Ride slowly up and down a Mohammadpur street for a minute.
	_place(Vector3(-224.5, 0, -90), 0.0)
	var before: int = mm.muggings
	var most := 0
	for i in 60 * 60:
		await get_tree().physics_frame
		most = maxi(most, mm.events.size())
	var started: int = mm.muggings - before
	print("  info  in 60 s: %d muggings started, up to %d at once" % [started, most])
	check(started >= 4, "Muggings are common in Mohammadpur (%d in a minute)" % started)
	check(most >= 2, "Several can happen at the same time (up to %d)" % most)
	check(most <= mm.MAX_EVENTS, "…but never more than %d at once" % mm.MAX_EVENTS)
	var on_player := 0
	for e in mm.events:
		if e.targets_player:
			on_player += 1
	check(on_player <= 1, "Only one mugger at a time comes for the rickshaw-wala")
	mm._end_event()
	mm.interval = Vector2(9999, 9999)
	mm._timer = 9999.0
