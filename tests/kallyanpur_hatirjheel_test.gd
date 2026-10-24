## Automated test: Kallyanpur, Hatirjheel lake and the bigger map.
## Run: godot --headless --fixed-fps 60 --path . res://tests/kallyanpur_hatirjheel_test.tscn
extends Node

const WORLD := preload("res://scenes/main_world.tscn")
const CityLayout := preload("res://scripts/city_layout.gd")
const PlayerRickshaw := preload("res://scripts/player_rickshaw.gd")

var world: Node3D
var player: PlayerRickshaw
var failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.use_defaults_for_testing()
	world = WORLD.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = world.get_node("PlayerRickshaw")
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _place(pos: Vector3, yaw: float, spd := 0.0) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.05, pos.z))
	player.speed = spd
	player.velocity = Vector3.ZERO
	player._crash_cooldown = 0.0
	player.reset_physics_interpolation()


func _run() -> void:
	print("== Dhakar Rickshaw: Kallyanpur & Hatirjheel ==")
	await frames(5)
	player.controls_enabled = false
	var m := CityLayout.MAP
	print("  info  map %.0f x %.0f m, %d intersections, %d lanes" % [m.size.x, m.size.y, CityLayout.intersections().size(), CityLayout.lane_count()])
	check(m.size.x > 700.0 and m.size.y > 500.0, "The map is bigger (about 720 x 530 m)")
	# Kallyanpur.
	check(CityLayout.area_name_at(-4, -280).begins_with("কল্যাণপুর"), "Kallyanpur is north on Mirpur Road (%s)" % CityLayout.area_name_at(-4, -280))
	check(CityLayout.area_name_at(-30, -250) == "কল্যাণপুর • কল্যাণপুর মেইন রোড", "Its own roads (%s)" % CityLayout.area_name_at(-30, -250))
	var names := []
	for d in CityLayout.destinations():
		names.append(d.name)
	check("কল্যাণপুর বাসস্ট্যান্ড" in names and "কল্যাণপুর বাজার" in names, "Kallyanpur destinations: বাসস্ট্যান্ড, বাজার")
	# Hatirjheel.
	check(CityLayout.area_name_at(240, -90) == "হাতিরঝিল", "Hatirjheel lake is on the map (%s)" % CityLayout.area_name_at(240, -90))
	check(CityLayout.area_name_at(240, 0) == "হাতিরঝিল সেতু", "A causeway crosses it (%s)" % CityLayout.area_name_at(240, 0))
	check(not CityLayout.is_road(240, -90) and not CityLayout.is_road(240, 60), "…and the rest is water")
	check("হাতিরঝিল" in names, "Destination: হাতিরঝিল (water taxi jetty)")
	var labels := {}
	for n in world.get_node("City").get_children():
		if n is Label3D:
			labels[n.text] = true
	check(labels.has("হাতিরঝিল ওয়াটার ট্যাক্সি") and labels.has("কল্যাণপুর নতুন বাজার") and labels.has("দারুস সালাম রোড"), "New signs are built")
	# Badda and BRAC are east of the lake now.
	check(CityLayout.district_for(Vector2(330, -149)) == "campus", "BRAC University is in Badda, east of Hatirjheel")
	check(CityLayout.area_name_at(330, -80) == "বাড্ডা", "Badda is across the lake (%s)" % CityLayout.area_name_at(330, -80))
	# Mohammadpur: no water any more.
	check(CityLayout.district_for(Vector2(-202, -90)) != "lake" and CityLayout.district_for(Vector2(-202, -90)) != "canal", "No lake or canal next to Mohammadpur")
	# You can ride the lake promenade but not into the water.
	_place(Vector3(183.8, 0, -40), -PI * 0.5, 4.0)  # heading east, from the lakeside road into the lake
	for i in 120:
		await get_tree().physics_frame
	print("  info  rode towards the lake: stopped at x %.2f" % player.global_position.x)
	check(player.global_position.x > 187.5, "The rickshaw can ride onto the lake promenade")
	check(player.global_position.x < 192.0, "…but the railing keeps it out of the water")
	# Cross the lake on the causeway.
	var traffic: Node = world.get_node("TrafficController")
	for v in traffic.vehicles:
		if absf(v.global_position.z) < 12.0 and v.global_position.x > 170.0 and v.global_position.x < 310.0:
			traffic._place_somewhere(v, 150.0, false)
	var hits := []
	player.crashed.connect(func(s, i, o): hits.append([o.name if o else "-", player.global_position]))
	_place(Vector3(180, 0, -3.5), -PI * 0.5, 6.0)
	for i in 60 * 22:  # about 120 m at 6 m/s
		await get_tree().physics_frame
		player.speed = 6.0
	print("  info  causeway: reached x %.1f, hits %s" % [player.global_position.x, hits])
	check(player.global_position.x > 290.0, "The causeway leads across Hatirjheel to Badda")
	print("== %d failure(s) ==" % failures.size())
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)
