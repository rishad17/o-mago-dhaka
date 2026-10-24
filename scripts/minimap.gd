## North-up mini-map of the whole neighbourhood (toggle with M).
##
## Shows the roads, the player's rickshaw (yellow arrow), the current
## destination (pulsing), waiting passengers (green dots) and the mechanic.
## Drawn with simple 2D calls and redrawn ten times a second.
extends Control

const CityLayout := preload("res://scripts/city_layout.gd")
const Pedestrian := preload("res://scripts/pedestrian.gd")

const BG := Color(0.12, 0.2, 0.14, 0.85)
const ROAD := Color(0.78, 0.78, 0.74)
const BORDER := Color(1, 0.78, 0.1)

var _player: Node3D
var _passengers: Node
var _pedestrians: Node
var _roads: Array[Rect2] = []
var _bay := Vector3.ZERO
var _has_bay := false
var _timer := 0.0
var _time := 0.0


func setup(player: Node3D, passengers: Node, pedestrians: Node) -> void:
	_player = player
	_passengers = passengers
	_pedestrians = pedestrians


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roads = CityLayout.road_rects()
	var bay := CityLayout.repair_bay()
	if not bay.is_empty():
		_bay = bay[0]
		_has_bay = true


func _process(delta: float) -> void:
	_time += delta
	_timer -= delta
	if _timer <= 0.0 and is_visible_in_tree():
		_timer = 0.25 if Settings.touch_mode else 0.1  # phones: fewer redraws
		queue_redraw()


## World position (x, z) -> point inside this control.
func to_map(p: Vector3) -> Vector2:
	var m := CityLayout.MAP
	return Vector2(p.x - m.position.x, p.z - m.position.y) * _scale()


## Pixels per metre (the map is wider than it is tall).
func _scale() -> float:
	var m := CityLayout.MAP
	return minf(size.x / m.size.x, size.y / m.size.y)


func _draw() -> void:
	var k := _scale()
	var area := CityLayout.MAP.size * k
	draw_rect(Rect2(Vector2.ZERO, area), BG)
	# Mohammadpur, across the canal, is tinted slightly differently.
	var mp := CityLayout.MOHAMMADPUR
	draw_rect(Rect2(to_map(Vector3(mp.position.x, 0, mp.position.y)), mp.size * k), Color(0.2, 0.16, 0.12, 0.6))
	var park := CityLayout.PARK
	draw_rect(Rect2(to_map(Vector3(park.position.x, 0, park.position.y)), park.size * k), Color(0.25, 0.5, 0.22))
	var lake := CityLayout.HATIRJHEEL
	draw_rect(Rect2(to_map(Vector3(lake.position.x, 0, lake.position.y)), lake.size * k), Color(0.25, 0.55, 0.75))
	for r in _roads:
		draw_rect(Rect2(to_map(Vector3(r.position.x, 0, r.position.y)), r.size * k), ROAD)
	# BRAC University campus in Badda.
	var campus := CityLayout.CAMPUS
	var cr := Rect2(to_map(Vector3(campus.position.x, 0, campus.position.y)), campus.size * k).grow(-2.0)
	draw_rect(cr, Color(0.33, 0.34, 0.35, 0.95))  # dark ash, like the building
	# Text size follows the square, so the label always fits.
	# "ব্র্যাক" in full: centred on the campus, allowed to stick out of the
	# small square, with an outline so it stays readable.
	var font := get_theme_default_font()
	var fs := 12
	var tw := font.get_string_size("ব্র্যাক", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := cr.get_center() + Vector2(-tw * 0.5, fs * 0.35)
	tp.x = clampf(tp.x, 1.0, area.x - tw - 1.0)
	draw_string_outline(font, tp, "ব্র্যাক", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.05, 0.05, 0.05))
	draw_string(font, tp, "ব্র্যাক", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.85))
	if _has_bay:
		var b := to_map(_bay)
		draw_rect(Rect2(b - Vector2(4, 4), Vector2(8, 8)), Color(0.9, 0.15, 0.15))
		draw_string(get_theme_default_font(), b + Vector2(6, 5), "ম", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.9))
	if _pedestrians:
		for ped in _pedestrians.pedestrians:
			if ped.state == Pedestrian.State.WAITING_FOR_PICKUP:
				draw_circle(to_map(ped.global_position), 3.5, Color(0.3, 1.0, 0.3))
	# Muggers (ছিনতাইকারী) show as red dots.
	for m in get_tree().get_nodes_in_group("muggers"):
		draw_circle(to_map(m.global_position), 4.0, Color(0.1, 0.0, 0.0))
		draw_circle(to_map(m.global_position), 3.0, Color(1.0, 0.15, 0.1))
	if _passengers and _passengers.destination:
		var d := to_map(_passengers.destination.global_position)
		var pulse := 5.0 + 2.5 * sin(_time * 6.0)
		draw_circle(d, pulse + 2.0, Color(0.1, 0.05, 0.0))
		draw_circle(d, pulse, Color(1.0, 0.85, 0.1))
	if _player:
		var p := to_map(_player.global_position)
		var f := -_player.global_transform.basis.z
		var angle := atan2(f.x, -f.z)  # clockwise from map-up (north)
		var pts := PackedVector2Array([Vector2(0, -8), Vector2(6, 6), Vector2(0, 3), Vector2(-6, 6)])
		var xf := Transform2D(angle, p)
		var shape := PackedVector2Array()
		for v in pts:
			shape.append(xf * v)
		draw_colored_polygon(shape, Color(1, 0.85, 0.1))
		draw_polyline(shape + PackedVector2Array([shape[0]]), Color(0.1, 0.05, 0.0), 1.5)
	draw_rect(Rect2(Vector2.ZERO, area), BORDER, false, 2.0)
