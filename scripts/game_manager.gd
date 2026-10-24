## Global game state (autoload singleton "GameManager").
##
## Holds earnings and the accident counter, converts numbers to Bangla digits,
## and handles pause / restart / quit so every scene can use them.
extends Node

signal earnings_changed(total: int)
signal accidents_changed(count: int)
## A short Bangla message for the HUD to show.
signal message_posted(text: String, color: Color)
signal pause_changed(paused: bool)
signal trips_changed(count: int)
## Rickshaw damage changed (0 = like new, 100 = badly battered).
signal damage_changed(damage: float)

const MAIN_MENU := "res://scenes/main_menu.tscn"
const WORLD := "res://scenes/main_world.tscn"
const CityBuilder := preload("res://scripts/city_builder.gd")
const BANGLA_DIGITS := ["০", "১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯"]
const MSG_INFO := Color(1.0, 1.0, 1.0)
const MSG_GOOD := Color(0.55, 1.0, 0.45)
const MSG_WARN := Color(1.0, 0.82, 0.25)
const MSG_BAD := Color(1.0, 0.35, 0.3)

var earnings := 0
var accidents := 0
var damage := 0.0
var trips_completed := 0


## 150 -> "১৫০"
func to_bangla_number(value: int) -> String:
	var text := str(value)
	var out := ""
	for ch in text:
		if ch >= "0" and ch <= "9":
			out += BANGLA_DIGITS[ch.unicode_at(0) - 48]
		else:
			out += ch
	return out


## 150 -> "৳১৫০"
func format_taka(value: int) -> String:
	return "৳" + to_bangla_number(value)


func add_earnings(amount: int) -> void:
	earnings += amount
	earnings_changed.emit(earnings)


func add_damage(amount: float) -> void:
	set_damage(damage + amount)


func set_damage(value: float) -> void:
	damage = clampf(value, 0.0, 100.0)
	damage_changed.emit(damage)


func register_accident() -> void:
	accidents += 1
	accidents_changed.emit(accidents)


func post_message(text: String, color := MSG_INFO) -> void:
	message_posted.emit(text, color)


## Called when the player's rickshaw knocks over a pedestrian.
func on_pedestrian_hit(counts_as_accident: bool) -> void:
	if counts_as_accident:
		register_accident()
		post_message("পথচারীকে ধাক্কা দিলেন!", MSG_BAD)
	else:
		post_message("সাবধানে চালান!", MSG_WARN)


## Called when the rickshaw smashes a street prop (stall, tea stall, bench).
func on_prop_broken(kind: String, hard: bool) -> void:
	add_damage(3.0 if kind != "bench" else 1.5)
	if kind == "bench":
		post_message("বেঞ্চ ভেঙে গেল!", MSG_WARN)
		return
	if hard:
		register_accident()
	post_message("দোকান ভেঙে গেল!" if kind == "stall" else "চায়ের দোকান ভেঙে গেল!", MSG_BAD)


## Called when the player's rickshaw hits something.
func on_player_crashed(severity: int, _impact_speed: float, _other: Object) -> void:
	match severity:
		1:
			register_accident()
			post_message("সাবধানে চালান!", MSG_WARN)
		2:
			register_accident()
			post_message("দুর্ঘটনা!", MSG_BAD)


func add_trip() -> void:
	trips_completed += 1
	trips_changed.emit(trips_completed)


## True while a ride is being played (not in the main menu).
func in_game() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.get_node_or_null("PauseMenu") != null


# Pause automatically when the player switches to another window.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Settings.auto_pause and in_game():
		set_paused(true)
	elif what == NOTIFICATION_PREDELETE:
		CityBuilder.free_spare()


func set_paused(value: bool) -> void:
	if get_tree().paused == value:
		return
	get_tree().paused = value
	pause_changed.emit(value)


func toggle_pause() -> void:
	set_paused(not get_tree().paused)


func reset_session() -> void:
	earnings = 0
	accidents = 0
	damage = 0.0
	trips_completed = 0
	earnings_changed.emit(earnings)
	accidents_changed.emit(accidents)
	damage_changed.emit(damage)
	trips_changed.emit(trips_completed)


## Saves this ride's results as records (best earnings and so on).
func record_session() -> bool:
	if earnings <= 0 and trips_completed == 0:
		return false
	return Settings.record_session(earnings, trips_completed)


## Starts a new ride from the main menu.
func start_game() -> void:
	set_paused(false)
	reset_session()
	_keep_city()
	get_tree().change_scene_to_file(WORLD)


func go_to_main_menu() -> void:
	record_session()
	set_paused(false)
	reset_session()
	_keep_city()
	get_tree().change_scene_to_file(MAIN_MENU)


## Starts the current level again from scratch.
func restart_level() -> void:
	record_session()
	set_paused(false)
	reset_session()
	_keep_city()
	get_tree().reload_current_scene()


## Hands the current scene's built city to the next scene (it takes long
## to build, especially in a phone's browser).
func _keep_city() -> void:
	var scene := get_tree().current_scene
	var city := scene.get_node_or_null("City") if scene else null
	if city and city.has_method("keep_for_next_scene"):
		city.keep_for_next_scene()


func quit_game() -> void:
	if in_game():
		record_session()
	get_tree().quit()
