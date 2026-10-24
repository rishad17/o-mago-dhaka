## In-game Bangla HUD: speed, earnings, accidents, passenger status,
## interaction prompt, pop-up messages and the controls hint.
extends CanvasLayer

@export var player_path: NodePath
@export var passengers_path: NodePath
@export var pedestrians_path: NodePath
## Seconds before the controls hint fades out a little.
@export var help_dim_delay := 20.0

@onready var _speed_value: Label = %SpeedValue
@onready var _speed_bar: ProgressBar = %SpeedBar
@onready var _earnings: Label = %Earnings
@onready var _accidents: Label = %Accidents
@onready var _passenger: Label = %PassengerStatus
@onready var _message: Label = %Message
@onready var _prompt: Label = %Prompt
@onready var _help: Label = %Help
@onready var _area: Label = %AreaName
@onready var _clock: Label = %Clock
@onready var _destination: Label = %Destination
@onready var _fare: Label = %Fare
@onready var _distance: Label = %Distance
@onready var _compass: Control = %Compass
@onready var _arrow: Node2D = %Arrow
@onready var _condition: Label = %Condition
@onready var _condition_bar: ProgressBar = %ConditionBar
@onready var _trips: Label = %Trips
@onready var _money_pop: Label = %MoneyPop
@onready var _minimap: Control = %Minimap

var _player: Node
var _message_tween: Tween
var _shown_speed := -1
var _time := 0.0
var _last_earnings := 0
var _money_tween: Tween


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_message.modulate.a = 0.0
	_prompt.visible = false
	GameManager.earnings_changed.connect(_on_earnings_changed)
	GameManager.accidents_changed.connect(_on_accidents_changed)
	GameManager.message_posted.connect(show_message)
	_on_earnings_changed(GameManager.earnings)
	_on_accidents_changed(GameManager.accidents)
	set_passenger_status("যাত্রী: নেই")
	set_trip_info("", 0, 0)
	set_compass(false, 0.0)
	_last_earnings = GameManager.earnings
	_money_pop.modulate.a = 0.0
	GameManager.trips_changed.connect(_on_trips_changed)
	_on_trips_changed(GameManager.trips_completed)
	_minimap.setup(_player, get_node_or_null(passengers_path), get_node_or_null(pedestrians_path))
	Settings.changed.connect(_on_settings_changed)
	_on_settings_changed()


func _process(delta: float) -> void:
	_time += delta
	if _player and _player.has_method("get_speed_kmh"):
		var kmh := roundi(_player.get_speed_kmh())
		if kmh != _shown_speed:
			_shown_speed = kmh
			_speed_value.text = GameManager.to_bangla_number(kmh)
		_speed_bar.value = _player.get_speed_fraction()
	if _time > help_dim_delay:
		_help.modulate.a = move_toward(_help.modulate.a, 0.45, delta)


func _on_earnings_changed(total: int) -> void:
	_earnings.text = "আজকের আয়: " + GameManager.format_taka(total)
	var delta := total - _last_earnings
	_last_earnings = total
	if delta != 0 and is_node_ready():
		_show_money(delta)


## Floating "+৳৪৪" (fare) or "−৳২০" (repair) next to the earnings.
func _show_money(delta: int) -> void:
	_money_pop.text = ("+" if delta > 0 else "−") + GameManager.format_taka(absi(delta))
	_money_pop.add_theme_color_override("font_color", Color(0.5, 1, 0.4) if delta > 0 else Color(1, 0.45, 0.4))
	if _money_tween:
		_money_tween.kill()
	_money_pop.modulate.a = 1.0
	_money_pop.position.y = 70.0
	_money_tween = create_tween()
	_money_tween.set_parallel(true)
	_money_tween.tween_property(_money_pop, "position:y", 40.0, 1.6)
	_money_tween.tween_property(_money_pop, "modulate:a", 0.0, 0.6).set_delay(1.0)


func _on_trips_changed(count: int) -> void:
	_trips.text = "সম্পন্ন যাত্রা: " + GameManager.to_bangla_number(count)


func _on_settings_changed() -> void:
	_minimap.visible = Settings.show_minimap


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		Settings.show_minimap = not Settings.show_minimap
		Settings.save_settings()
		_on_settings_changed()
		get_viewport().set_input_as_handled()


func _on_accidents_changed(count: int) -> void:
	_accidents.text = "দুর্ঘটনা: " + GameManager.to_bangla_number(count)


## Shows where the player is, e.g. "এলাকা: নিউ মার্কেট".
func set_area_name(area: String) -> void:
	var text := "এলাকা: " + area if area != "" else ""
	if _area.text != text:
		_area.text = text


## Time of day, e.g. "সকাল ৮:০০" (from day_night.gd).
func set_clock(text: String) -> void:
	_clock.text = text


func set_passenger_status(text: String) -> void:
	_passenger.text = text


## Rickshaw condition (100 = like new). Colour goes green -> yellow -> red.
func set_condition(percent: float) -> void:
	var p := roundi(clampf(percent, 0.0, 100.0))
	_condition.text = "রিকশার অবস্থা: " + GameManager.to_bangla_number(p) + "%"
	var col := Color(1.0, 0.35, 0.3).lerp(Color(1.0, 0.85, 0.3), clampf(p / 50.0, 0.0, 1.0))
	if p > 50:
		col = Color(1.0, 0.85, 0.3).lerp(Color(0.6, 1.0, 0.5), (p - 50) / 50.0)
	_condition.add_theme_color_override("font_color", col)
	_condition_bar.value = p
	var fill: StyleBoxFlat = _condition_bar.get_theme_stylebox("fill").duplicate()
	fill.bg_color = col
	_condition_bar.add_theme_stylebox_override("fill", fill)


## Trip details in the stats panel. Empty destination hides them.
func set_trip_info(destination: String, fare: int, distance_m: int) -> void:
	var on := destination != ""
	_destination.visible = on
	_fare.visible = on
	_distance.visible = on
	if on:
		_destination.text = "গন্তব্য: " + destination
		_fare.text = "ভাড়া: প্রায় " + GameManager.format_taka(fare)
		_distance.text = "দূরত্ব: " + GameManager.to_bangla_number(distance_m) + " মিটার"


## Arrow at the top of the screen pointing to the destination.
## `angle` is in radians, clockwise from straight ahead.
func set_compass(on: bool, angle: float) -> void:
	_compass.visible = on
	_arrow.rotation = angle


## Shows an interaction prompt such as "যাত্রী নিতে E চাপুন". Empty hides it.
func show_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""


func hide_prompt() -> void:
	_prompt.visible = false


## Big centred pop-up message that fades out.
func show_message(text: String, color := Color.WHITE, duration := 2.2) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	if _message_tween:
		_message_tween.kill()
	_message.modulate.a = 1.0
	_message.scale = Vector2(1.15, 1.15)
	_message.pivot_offset = _message.size * 0.5
	_message_tween = create_tween()
	_message_tween.tween_property(_message, "scale", Vector2.ONE, 0.15)
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.5)


## Phones: no keyboard hint, and the mini-map moves to the top right so the
## touch buttons at the bottom don't cover it.
func use_touch_layout() -> void:
	%Help.visible = false
	var m: Control = %Minimap
	m.anchor_top = 0.0
	m.anchor_bottom = 0.0
	m.offset_top = 84.0
	m.offset_bottom = 84.0 + 178.0
