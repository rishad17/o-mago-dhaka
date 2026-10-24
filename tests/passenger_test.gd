## Automated Milestone 4 test: pedestrians and the passenger job.
##
## Run (from the project folder):
##   godot --headless --fixed-fps 60 --path . res://tests/passenger_test.tscn   (behaviour)
##   godot --path . res://tests/passenger_test.tscn                             (screenshots only)
## Optional: -- --shots=C:/some/folder
extends Node

const WORLD := preload("res://scenes/main_world.tscn")
const CityLayout := preload("res://scripts/city_layout.gd")
const Pedestrian := preload("res://scripts/pedestrian.gd")
const PlayerRickshaw := preload("res://scripts/player_rickshaw.gd")
const PersonModel := preload("res://scripts/person_model.gd")

var world: Node3D
var player: PlayerRickshaw
var peds: Node3D
var pm: Node
var dest: Node3D
var hud: CanvasLayer
var failures: Array[String] = []
var shots_dir := "user://test_shots_m4"
var headless := false
var seed_value := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Default settings (and never touch the player's saved ones).
	Settings.use_defaults_for_testing()
	headless = DisplayServer.get_name() == "headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
	DirAccess.make_dir_recursive_absolute(shots_dir)
	world = WORLD.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	if seed_value >= 0:
		world.get_node("PedestrianManager").ped_seed = seed_value
		world.get_node("TrafficController").traffic_seed = seed_value
	world.get_node("PassengerManager").passenger_seed = maxi(seed_value, 0)
	add_child(world)
	player = world.get_node("PlayerRickshaw")
	peds = world.get_node("PedestrianManager")
	pm = world.get_node("PassengerManager")
	dest = world.get_node("DestinationManager")
	hud = world.get_node("HUD")
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


func press(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(1)


func _place_player(pos: Vector3, yaw: float) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.05, pos.z))
	player.velocity = Vector3.ZERO
	player.speed = 0.0
	player.reset_physics_interpolation()
	world.get_node("ChaseCamera").snap_to_target()


func prompt_text() -> String:
	var p: Label = hud.get_node("Prompt")
	return p.text if p.visible else ""


func _run() -> void:
	print("== Dhakar Rickshaw: Milestone 4 pedestrian & passenger test ==")
	await frames(5)
	_check_network()
	if headless:
		await _simulate_pedestrians(60.0)
		await _passenger_loop()
		await _cancelled_trip()
		await _hit_pedestrian()
		await _traffic_stops_for_pedestrian()
	else:
		await _screenshots()
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _solid_at(p: Vector3, radius := 0.22) -> bool:
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	q.shape = s
	q.transform = Transform3D(Basis(), p + Vector3(0, 1.0, 0))
	q.collision_mask = 1
	return not space.intersect_shape(q, 1).is_empty()


# --- Sidewalk network --------------------------------------------------------------------

func _check_network() -> void:
	var net = peds.network
	var walk := 0
	var cross := 0
	var bad_walk := 0
	var bad_cross := 0
	for e in net.edges:
		if e.cross:
			cross += 1
			var mid: Vector3 = (e.pa + e.pb) * 0.5
			if not CityLayout.is_road(mid.x, mid.z):
				bad_cross += 1
		else:
			walk += 1
			var d := 0.0
			while d <= e.length:
				var p: Vector3 = (e.pa as Vector3).lerp(e.pb, d / maxf(e.length, 0.01))
				if CityLayout.is_road(p.x, p.z) or _solid_at(p):
					bad_walk += 1
				d += 2.0
	print("  info  sidewalk network: %d walking edges, %d road crossings" % [walk, cross])
	check(walk > 100 and cross > 50, "Sidewalk network covers the city")
	check(bad_walk == 0, "Walking lines are on sidewalks and clear of buildings (%d bad samples)" % bad_walk)
	check(bad_cross == 0, "Crossings go over roads")


# --- Pedestrian life ---------------------------------------------------------------------

func _simulate_pedestrians(seconds: float) -> void:
	_place_player(Vector3(-4, 0, 42), 0.0)
	player.controls_enabled = false
	var list: Array = peds.pedestrians
	check(list.size() >= 30, "Pedestrians spawned (%d)" % list.size())
	var last := {}
	var travelled := {}
	for p in list:
		last[p] = p.global_position
		travelled[p] = 0.0
	var inside := 0
	var walking_on_road := 0
	var crossings := 0
	var was_crossing := {}
	var max_waiting := 0
	var saw_waiting := false
	for t in int(seconds * 60.0):
		await get_tree().physics_frame
		for p in list:
			var step: float = p.global_position.distance_to(last[p])
			if step < 3.0:
				travelled[p] += step
			last[p] = p.global_position
			var crossing: bool = p.state == Pedestrian.State.CROSSING
			if crossing and not was_crossing.get(p, false):
				crossings += 1
			was_crossing[p] = crossing
		if t % 60 == 0:
			var waiting: int = peds.count_in_state(Pedestrian.State.WAITING_FOR_PICKUP)
			max_waiting = maxi(max_waiting, waiting)
			saw_waiting = saw_waiting or waiting > 0
			for p in list:
				if p.state in [Pedestrian.State.WALKING, Pedestrian.State.WAITING_FOR_PICKUP] and _solid_at(p.global_position, 0.15):
					inside += 1
				if p.state == Pedestrian.State.WALKING and CityLayout.is_road(p.global_position.x, p.global_position.z):
					walking_on_road += 1
					print("  diag  walking on road: %s at %s edge %d (cross %s) t %.1f" % [p.name, p.global_position, p.current_edge(), peds.network.edges[p.current_edge()].cross, p._t])
	player.controls_enabled = true
	var moving := 0
	for p in list:
		if travelled[p] > 20.0 or p.state == Pedestrian.State.WAITING_FOR_PICKUP:
			moving += 1
	print("  info  %.0f s: %d/%d pedestrians active, %d road crossings started, traffic hits %d, max waiting passengers %d, recycled %d" % [
		seconds, moving, list.size(), crossings, peds.hits_by_traffic, max_waiting, peds.recycled_count])
	check(moving >= int(list.size() * 0.85), "Pedestrians keep walking (85%+ moved over 20 m or are waiting)")
	check(inside == 0, "Nobody walks through buildings (%d samples inside)" % inside)
	check(walking_on_road == 0, "Walking pedestrians stay on the sidewalk unless crossing")
	check(crossings >= 5, "Pedestrians cross roads (%d)" % crossings)
	check(saw_waiting, "Some pedestrians become waiting passengers")
	check(max_waiting <= pm.MAX_WAITING, "Waiting passengers are limited (max %d)" % max_waiting)
	check(peds.hits_by_traffic <= maxi(6, crossings / 15), "Traffic mostly avoids pedestrians (%d hits in %d crossings)" % [peds.hits_by_traffic, crossings])


# --- The passenger loop --------------------------------------------------------------------

## Makes a pedestrian wait for a rickshaw and parks the player next to them.
func _prepare_passenger() -> Node3D:
	var chosen: Node3D = null
	var net = peds.network
	for p in peds.pedestrians:
		if p.state != Pedestrian.State.WALKING:
			continue
		var e: Dictionary = net.edges[p.current_edge()]
		# Long, straight stretch away from junctions, on a 10 m+ road.
		var inward: Vector3 = e.inward
		var road_pt: Vector3 = p.global_position - inward * 4.0
		if e.cross or e.length < 30.0 or not CityLayout.is_road(road_pt.x, road_pt.z):
			continue
		if not CityLayout.is_road(road_pt.x - inward.x * 4.0, road_pt.z - inward.z * 4.0):
			continue
		chosen = p
		break
	if chosen == null:
		return null
	chosen.become_waiting_passenger()
	var e2: Dictionary = net.edges[chosen.current_edge()]
	var along: Vector3 = ((e2.pb as Vector3) - e2.pa).normalized()
	var spot: Vector3 = chosen.global_position - (e2.inward as Vector3) * 3.0
	_place_player(spot, atan2(-along.x, -along.z))
	await frames(5)
	return chosen


func _passenger_loop() -> void:
	# Clear other waiting passengers so the nearest one is ours.
	for p in pm.waiting_passengers():
		p.stop_waiting()
	var earnings_before: int = GameManager.earnings
	var ped := await _prepare_passenger()
	check(ped != null and ped.state == Pedestrian.State.WAITING_FOR_PICKUP, "A passenger is waiting by the road")
	if ped == null:
		return
	check(prompt_text() == "যাত্রী নিতে E চাপুন", "Prompt: যাত্রী নিতে E চাপুন (got '%s')" % prompt_text())
	# Too fast: no pickup.
	player.speed = 4.0
	await frames(1)
	check(prompt_text() == "যাত্রী নিতে থামুন", "Moving too fast asks the player to stop")
	check(not pm.begin_pickup(ped), "Pickup refused while moving")
	player.speed = 0.0
	player.velocity = Vector3.ZERO
	var spot := player.global_position
	_place_player(spot, player.rotation.y)
	await frames(3)
	await press("interact")
	check(pm.trip_state == pm.Trip.BOARDING or pm.trip_state == pm.Trip.ON_BOARD, "E starts boarding")
	check(not player.controls_enabled, "Rickshaw waits while the passenger climbs on")
	await frames(150)
	var seat: Node3D = player.get_passenger_seat()
	check(pm.trip_state == pm.Trip.ON_BOARD, "Passenger is on board")
	check(ped.get_parent() == seat, "Passenger is attached to the passenger seat")
	check(ped.state == Pedestrian.State.ON_BOARD and ped.model.pose == PersonModel.Pose.SIT, "Passenger sits")
	check(player.controls_enabled, "Player can drive again after boarding")
	var d: Node3D = pm.destination
	check(d != null and d.active and d.get_node("Marker").visible, "Destination marker is shown")
	check(d != null and d.global_position.distance_to(ped.global_position) >= 50.0, "Destination is a different, distant place (%s)" % (d.zone_name if d else "-"))
	check(pm.fare_estimate >= pm.BASE_FARE, "Estimated fare shown (%s)" % GameManager.format_taka(pm.fare_estimate))
	var dest_label: Label = hud.get_node("StatsPanel/VBox/Destination")
	check(dest_label.visible and dest_label.text == "গন্তব্য: " + d.zone_name, "HUD shows the destination in Bangla")
	check(hud.get_node("Compass").visible, "Compass arrow points the way")
	check(hud.get_node("StatsPanel/VBox/PassengerStatus").text == "যাত্রী: আছে", "HUD shows passenger on board")
	# No second passenger while occupied.
	var other: Node3D = null
	for p in peds.pedestrians:
		if p.state == Pedestrian.State.WALKING and p != ped:
			other = p
			break
	other.become_waiting_passenger()
	check(not pm.begin_pickup(other), "Cannot pick up a second passenger")
	other.stop_waiting()
	# Pressing E away from the destination does nothing.
	await press("interact")
	check(pm.trip_state == pm.Trip.ON_BOARD, "No drop-off away from the destination")
	# Drive a little (with the road ahead cleared): the passenger stays seated.
	await _clear_traffic_near(player.global_position, 40.0)
	Input.action_press("accelerate")
	var max_offset := 0.0
	for i in 90:
		await get_tree().physics_frame
		max_offset = maxf(max_offset, ped.global_position.distance_to(seat.global_position + seat.global_transform.basis * Vector3(0, -PersonModel.HIP_Y + 0.05, 0.02)))
	Input.action_release("accelerate")
	check(max_offset < 0.05, "Passenger stays in the seat while driving (%.3f m)" % max_offset)
	# Reset and pause don't break the trip.
	await press("reset_vehicle")
	await frames(5)
	check(pm.trip_state == pm.Trip.ON_BOARD and ped.get_parent() == seat, "Reset (R) keeps the passenger and the trip")
	GameManager.set_paused(true)
	await get_tree().create_timer(0.3, true).timeout
	GameManager.set_paused(false)
	await frames(3)
	check(pm.trip_state == pm.Trip.ON_BOARD, "Pause/resume keeps the trip")
	# Arrive at the destination (teleport onto the lane at the zone).
	var lane_yaw := 0.0
	var fwd_lane: Vector3 = Vector3(d.sidewalk_point.x - d.global_position.x, 0, d.sidewalk_point.z - d.global_position.z).normalized().cross(Vector3.UP)
	lane_yaw = atan2(-fwd_lane.x, -fwd_lane.z)
	_place_player(d.global_position, lane_yaw)
	await frames(5)
	check(prompt_text() == "যাত্রী নামাতে E চাপুন", "Prompt at destination: যাত্রী নামাতে E চাপুন (got '%s')" % prompt_text())
	var fare: Dictionary = pm.final_fare()
	var estimate: int = pm.fare_estimate
	await press("interact")
	check(pm.trip_state == pm.Trip.EXITING, "E starts the drop-off")
	await press("interact")  # pressing again must not pay twice
	await frames(200)
	check(pm.trip_state == pm.Trip.NONE, "Trip complete")
	check(GameManager.earnings - earnings_before == fare.total, "Fare paid once: %s" % GameManager.format_taka(GameManager.earnings - earnings_before))
	check(pm.fares_paid == 1 and pm.trips_completed == 1, "Exactly one fare and one completed trip")
	check(not d.active and not d.get_node("Marker").visible, "Destination marker removed")
	check(ped.get_parent() == peds and ped.state == Pedestrian.State.WALKING, "Passenger is back on foot")
	print("  info  passenger at %s (road %s), %.1f m from the drop-off point, state %s" % [ped.global_position,
		CityLayout.is_road(ped.global_position.x, ped.global_position.z), ped.global_position.distance_to(d.sidewalk_point), Pedestrian.State.keys()[ped.state]])
	check(not CityLayout.is_road(ped.global_position.x, ped.global_position.z) and ped.global_position.distance_to(d.sidewalk_point) < 6.0,  # (they walk on for ~3 s)
		"Passenger got off onto the sidewalk at the destination")
	check(not dest_label.visible and not hud.get_node("Compass").visible, "HUD trip info cleared")
	await press("interact")
	await frames(5)
	check(GameManager.earnings - earnings_before == fare.total, "Pressing E again pays nothing more")
	print("  info  trip fare %s (estimate %s, tip %s, penalty %s)" % [fare.total, estimate, fare.tip, fare.penalty])


func _cancelled_trip() -> void:
	for p in pm.waiting_passengers():
		p.stop_waiting()
	var earnings_before: int = GameManager.earnings
	var ped := await _prepare_passenger()
	await press("interact")
	await frames(150)
	check(pm.trip_state == pm.Trip.ON_BOARD, "Second trip: passenger on board")
	# A medium accident costs a little, a heavy one ends the trip.
	player.crashed.emit(1, 3.5, null)
	await frames(2)
	check(pm.final_fare().penalty == pm.ACCIDENT_PENALTY, "Medium accident with a passenger costs %s" % GameManager.format_taka(pm.ACCIDENT_PENALTY))
	var marker: Node3D = pm.destination
	player.crashed.emit(2, 7.0, null)
	await frames(200)
	check(pm.trip_state == pm.Trip.NONE, "Heavy crash cancels the trip")
	check(GameManager.earnings == earnings_before, "No fare for a cancelled trip")
	check(ped.state == Pedestrian.State.WALKING and not CityLayout.is_road(ped.global_position.x, ped.global_position.z),
		"Passenger got off safely onto the sidewalk")
	check(not marker.active, "Marker removed after cancellation")
	check(player.controls_enabled, "Player can drive after the cancelled trip")


# --- Accidents with pedestrians --------------------------------------------------------------

## Moves random traffic away so a scenario isn't disturbed.
func _clear_traffic_near(point: Vector3, radius: float, keep: Node = null) -> void:
	var traffic = world.get_node("TrafficController")
	for v in traffic.vehicles:
		if v != keep and v.global_position.distance_to(point) < radius:
			traffic._place_somewhere(v, radius + 60.0, false)
	await frames(2)


func _hit_pedestrian() -> void:
	await _clear_traffic_near(Vector3(-4, 0, 32), 45.0)
	_place_player(Vector3(-4, 0, 42), 0.0)
	var ped: Node3D = null
	for p in peds.pedestrians:
		if p.state == Pedestrian.State.WALKING:
			ped = p
			break
	# Someone standing in the lane 12 m ahead, not paying attention
	# (people who see the rickshaw coming usually run out of the way).
	ped.global_position = Vector3(-4, 0, 30)
	ped.state = Pedestrian.State.WAIT_CROSS
	ped._timer = 100.0
	ped._from = Vector3(-9.5, 0.15, 30)
	ped._to = Vector3(9.5, 0.15, 30)
	var acc_before: int = GameManager.accidents
	var hits_before: int = peds.hits_by_player
	Input.action_press("accelerate")
	for i in 300:
		await get_tree().physics_frame
		if ped.state == Pedestrian.State.KNOCKED:
			break
	Input.action_release("accelerate")
	print("  info  hit at %.1f km/h" % player.get_speed_kmh())
	check(ped.state == Pedestrian.State.KNOCKED, "Riding into a pedestrian knocks them down")
	check(peds.hits_by_player == hits_before + 1, "Pedestrian hit is counted once (%d)" % (peds.hits_by_player - hits_before))
	check(GameManager.accidents == acc_before + 1, "Hitting a pedestrian at speed counts as an accident (+%d)" % (GameManager.accidents - acc_before))
	check(player.speed < 7.0, "The rickshaw is slowed but not stopped dead")
	await frames(60 * 8)
	check(ped.state != Pedestrian.State.KNOCKED, "The pedestrian gets up again")
	await frames(60 * 6)
	check(not CityLayout.is_road(ped.global_position.x, ped.global_position.z) or ped.state == Pedestrian.State.CROSSING,
		"…and walks back to the sidewalk")


func _traffic_stops_for_pedestrian() -> void:
	var traffic = world.get_node("TrafficController")
	_place_player(Vector3(-100, 0, 100), 0.0)
	var net = traffic.network
	var lane := -1
	for id in net.edges.size():
		var e: Dictionary = net.edges[id]
		if absf(e.start.x + 4.0) < 0.01 and e.dir.z < -0.9 and e.start.z > 40.0 and e.end.z < 40.0:
			lane = id
	var car = null
	for v in traffic.vehicles:
		if v.vehicle_type == "car":
			car = v
			break
	for v in traffic.vehicles:
		if v != car and v.current_edge == lane:
			traffic._place_somewhere(v, 60.0, false)
	var ped: Node3D = null
	for p in peds.pedestrians:
		if p.state == Pedestrian.State.WALKING:
			ped = p
			break
	await _clear_traffic_near(Vector3(-4, 0, 40), 60.0, car)
	# Someone standing still in the northbound lane at z = 40.
	ped.global_position = Vector3(-4, 0, 40)
	ped.state = Pedestrian.State.WAIT_CROSS
	ped._timer = 100.0
	ped._from = Vector3(-9.5, 0.15, 40)
	ped._to = Vector3(9.5, 0.15, 40)
	ped.on_road = true
	var e: Dictionary = net.edges[lane]
	car.place(lane, (e.start.z - 40.0) - 30.0)
	car.speed = 8.0
	var stopped := false
	var knocked := false
	for i in 60 * 10:
		await get_tree().physics_frame
		knocked = knocked or ped.state == Pedestrian.State.KNOCKED
		# Stopped behind the pedestrian (cars drive north, towards -Z).
		var gap: float = car.get_center().z - ped.global_position.z
		if car.speed < 0.3 and gap > 0.0 and gap < 12.0:
			stopped = true
	print("  info  car stopped for pedestrian: %s, gap %.1f m" % [stopped, car.get_center().distance_to(ped.global_position)])
	ped._timer = 0.0
	check(stopped, "Traffic stops for a pedestrian crossing the road")
	check(not knocked, "…without hitting them")


# --- Screenshots -----------------------------------------------------------------------------

func _screenshots() -> void:
	player.controls_enabled = false
	# A line-up of all clothing styles.
	var cam := Camera3D.new()
	world.add_child(cam)
	var lineup: Array[Node3D] = []
	await _clear_traffic_near(Vector3(0, 0, 80), 40.0)
	for i in 8:
		var m := PersonModel.new()
		m.variant = i + (8 if i % 2 == 1 else 0)
		world.add_child(m)
		# Standing in a row on Mirpur Road, facing the camera (people face -Z).
		m.global_position = Vector3(-3.85 + i * 1.1, 0.0, 80)
		m.set_pose(PersonModel.Pose.STAND)
		lineup.append(m)
	cam.current = true
	cam.global_position = Vector3(0, 1.3, 74.5)
	cam.look_at(Vector3(0, 0.95, 80))
	cam.fov = 60.0
	await frames(3)
	await shot("m4_01_people.png")
	lineup[3].set_pose(PersonModel.Pose.WAVE)
	lineup[5].set_pose(PersonModel.Pose.WALK)
	lineup[5].speed = 1.4
	lineup[1].set_pose(PersonModel.Pose.FALLEN)
	await frames(40)
	await shot("m4_02_poses.png")
	for m in lineup:
		m.queue_free()
	cam.current = false
	cam.queue_free()
	world.get_node("ChaseCamera").current = true
	# Waiting passenger, then the trip.
	for p in pm.waiting_passengers():
		p.stop_waiting()
	var ped := await _prepare_passenger()
	await frames(30)
	await shot("m4_03_waiting_passenger.png")
	pm.begin_pickup(ped)
	await frames(20)
	await shot("m4_04_boarding.png")
	await frames(150)
	await shot("m4_05_on_board.png")
	var d: Node3D = pm.destination
	var fwd_lane: Vector3 = Vector3(d.sidewalk_point.x - d.global_position.x, 0, d.sidewalk_point.z - d.global_position.z).normalized().cross(Vector3.UP)
	_place_player(d.global_position - fwd_lane * 20.0, atan2(-fwd_lane.x, -fwd_lane.z))
	await frames(30)
	await shot("m4_06_destination_ahead.png")
	_place_player(d.global_position, atan2(-fwd_lane.x, -fwd_lane.z))
	await frames(5)
	pm.begin_dropoff()
	await frames(100)
	await shot("m4_07_trip_complete.png")
	# Street life near Farmgate.
	_place_player(Vector3(-4, 0, 20), 0.0)
	await frames(60 * 5)
	await shot("m4_08_street_life.png")
