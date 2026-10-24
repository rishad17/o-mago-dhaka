## Automated test: the angry crowd after the rickshaw hits someone.
##
## Knocks a pedestrian over, checks that bystanders come running shouting
## "ধর শালারে!" and "তুই আজকে শেষ!", that they thump the stopped rickshaw
## and then calm down, and that pedalling away makes them give up.
##
## Run (from the project folder):
##   godot --headless --fixed-fps 60 --path . res://tests/mob_test.tscn
extends Node

const WORLD := preload("res://scenes/main_world.tscn")
const Pedestrian := preload("res://scripts/pedestrian.gd")

var world: Node3D
var player: CharacterBody3D
var peds: Node
var mob: Node
var traffic: Node
var failures: Array[String] = []
var messages: Array[String] = []
## Everything the crowd said (each line once), in order.
var said: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.use_defaults_for_testing()
	world = WORLD.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.get_node("TrafficController").nearby_target = 0
	add_child(world)
	player = world.get_node("PlayerRickshaw")
	peds = world.get_node("PedestrianManager")
	mob = world.get_node("MobManager")
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
		_listen()


## Notes what the crowd members' speech bubbles say.
func _listen() -> void:
	for m in mob.members:
		var b: Label3D = m._bubble
		if b.visible and not said.has(b.text):
			said.append(b.text)


func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir := "user://test_shots_mob"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	get_viewport().get_texture().get_image().save_png(path)
	print("  shot  ", ProjectSettings.globalize_path(path))


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


## Puts a few people on the footpaths around `p` so there are bystanders.
func _bystanders_near(p: Vector3, n: int) -> void:
	var placed := 0
	for ped in peds.pedestrians:
		if placed >= n:
			break
		if ped.state != Pedestrian.State.WALKING or ped.targeted:
			continue
		var hit: Array = peds.network.nearest_walk_point(p + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12)))
		ped.place_on_edge(hit[0], hit[1])
		placed += 1


func _run() -> void:
	print("== Dhakar Rickshaw: the angry crowd ==")
	await frames(10)
	player.controls_enabled = false
	await _hit_and_get_thumped()
	await _ride_away()
	await _bike_crash_mob()
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _hit_and_get_thumped() -> void:
	var start := Vector3(-4, 0, 100)
	_clear_traffic_near(start, 60.0)
	_bystanders_near(start, 8)
	# Someone stands in the lane ahead, about to cross.
	var victim: Node3D
	for ped in peds.pedestrians:
		if ped.state == Pedestrian.State.WALKING and not ped.targeted:
			victim = ped
			break
	victim.state = Pedestrian.State.WAIT_CROSS
	victim._timer = 99.0
	victim.global_position = start + Vector3(0, 0, -6)
	victim._update_obstacle()
	GameManager.set_damage(0.0)
	_place(start, 0.0, 5.0)
	var hits0: int = peds.hits_by_player
	for i in 90:
		await frames(1)
		if peds.hits_by_player > hits0:
			break
	check(peds.hits_by_player > hits0, "The rickshaw knocks the pedestrian over")
	check(mob.phase == mob.Phase.CHASE, "An angry crowd forms")
	check(mob.members.size() >= 2, "Several bystanders join in (%d)" % mob.members.size())
	check(not victim in mob.members, "The one who was hit isn't in the crowd (they're on the ground)")
	check(messages.has("লোকজন খেপে গেছে! পালান!"), "Message: লোকজন খেপে গেছে! পালান!")
	# Stop and wait for them.
	player.speed = 0.0
	var damage0 := GameManager.damage
	var reached := false
	for i in 600:
		await frames(1)
		for m in mob.members:
			if m.global_position.distance_to(player.global_position) < 2.2:
				reached = true
		if mob.thumps > 0:
			break
	check(reached, "They run up to the stopped rickshaw")
	check(said.has("ধর শালারে!"), "Someone shouts \"ধর শালারে!\"")
	check(said.has("তুই আজকে শেষ!"), "Someone shouts \"তুই আজকে শেষ!\"")
	check(mob.thumps > 0, "They thump the rickshaw")
	await _shot("mob_1_thumping.png")
	check(messages.has("মাইর খাচ্ছেন! পালান!"), "Message: মাইর খাচ্ছেন! পালান!")
	var in_mob: Array = mob.members.duplicate()
	for i in 600:
		await frames(1)
		if mob.phase == mob.Phase.NONE:
			break
	print("  info  said: ", said)
	check(mob.thumps == mob.MAX_THUMPS, "They stop after %d thumps" % mob.MAX_THUMPS)
	var dmg := GameManager.damage - damage0
	check(dmg > 5.0 and dmg < 20.0, "Each thump dents the rickshaw a little (+%.1f%%)" % dmg)
	check(mob.phase == mob.Phase.NONE and messages.has("লোকজন শান্ত হয়েছে।"), "Then they calm down: লোকজন শান্ত হয়েছে।")
	await frames(900)  # some cross the whole road, away from the rickshaw
	var back := 0
	for m in in_mob:
		# Back to normal life: walking, or waiting at the kerb to cross.
		if m.state in [Pedestrian.State.WALKING, Pedestrian.State.WAIT_CROSS, Pedestrian.State.CROSSING] and not m.targeted:
			back += 1
		else:
			print("  info  still %s at %s from %s to %s path_t %.1f speed %.1f blocked %.1f on_road %s" % [Pedestrian.State.keys()[m.state], m.global_position, m._from, m._to, m._path_t, m._speed_now, m._blocked_time, m.on_road])
	check(back == in_mob.size(), "Everyone goes back to normal life (%d/%d)" % [back, in_mob.size()])


func _ride_away() -> void:
	var start := Vector3(-4, 0, 60)
	_clear_traffic_near(start, 80.0)
	_bystanders_near(start, 6)
	GameManager.set_damage(0.0)
	_place(start, 0.0)
	await frames(5)
	var joined: int = mob.start_mob(start + Vector3(0, 0, -3))
	check(joined >= 2, "A new crowd forms (%d people)" % joined)
	var escapes0: int = mob.escapes
	# Pedal off down Mirpur Road at full speed.
	player.controls_enabled = true
	Input.action_press("accelerate")
	for i in 1200:
		await frames(1)
		if mob.phase == mob.Phase.NONE:
			break
	Input.action_release("accelerate")
	player.controls_enabled = false
	check(mob.escapes == escapes0 + 1, "Riding away fast, the crowd gives up")
	check(messages.has("বেঁচে গেলেন! লোকজন পিছু ছেড়েছে।"), "Message: বেঁচে গেলেন! লোকজন পিছু ছেড়েছে।")
	check(GameManager.damage < 3.0, "Got away without a beating (damage %.1f%%)" % GameManager.damage)


## Knocking a motorbike over brings the crowd too.
func _bike_crash_mob() -> void:
	var start := Vector3(-4, 0, 80)
	_clear_traffic_near(start, 60.0)
	_bystanders_near(start, 6)
	_place(start, 0.0)
	await frames(5)
	var bike: Node = null
	for v in traffic.vehicles:
		if v.vehicle_type == "motorcycle" and not v.bike_down:
			bike = v
			break
	bike.place(bike.current_edge, 5.0)
	bike.global_position = start + Vector3(0, 0, -3)
	var before: int = mob.mobs_started
	bike.on_player_impact(5.0)
	player.crashed.emit(1, 5.0, bike)
	await frames(5)
	check(bike.bike_down, "The motorbike falls over")
	check(mob.mobs_started == before + 1 and mob.phase == mob.Phase.CHASE, "Hitting a motorbike also makes the crowd angry")
	mob._end()
