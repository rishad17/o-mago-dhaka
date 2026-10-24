## Wires the systems of the main world together.
extends Node3D

const CityLayout := preload("res://scripts/city_layout.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")

@onready var player: CharacterBody3D = $PlayerRickshaw
@onready var camera: Camera3D = $ChaseCamera
@onready var hud: CanvasLayer = $HUD
@onready var destinations: Node3D = $DestinationManager
@onready var sun: DirectionalLight3D = $Sun
@onready var passengers: Node = $PassengerManager

## Short tips for new players, shown once per ride.
const HINT_PASSENGER := "সবুজ \"যাত্রী\" চিহ্নের কাছে থামুন,
তারপর E চাপুন"
const HINT_ARROW := "উপরের হলুদ তীর গন্তব্য দেখাচ্ছে"

var _area_timer := 0.0


func _ready() -> void:
	player.was_reset.connect(_on_player_reset)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	# GTA-style mouse look: the cursor is hidden and locked while riding.
	GameManager.pause_changed.connect(_on_pause_changed)
	var touch: CanvasLayer = TouchControls.new()
	touch.name = "TouchControls"
	add_child(touch)
	touch.setup(camera, hud)
	_set_mouse_captured(true)
	passengers.trip_started.connect(_on_first_trip, CONNECT_ONE_SHOT)
	GameManager.post_message.call_deferred("স্বাগতম! রিকশা চালান", GameManager.MSG_GOOD)
	get_tree().create_timer(9.0, false).timeout.connect(_hint_passengers)
	_update_area()
	Settings.log_time("world ready")


func _set_mouse_captured(captured: bool) -> void:
	# Never grab the mouse during automated tests (it would take over your cursor).
	if DisplayServer.get_name() == "headless" or Settings.testing:
		return
	if Settings.touch_mode:
		return  # fingers, not a mouse: nothing to lock
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _on_pause_changed(paused: bool) -> void:
	# The breakdown screen needs the mouse too.
	_set_mouse_captured(not paused and not $CollisionManager.wrecked)


# Clicking back into the game window locks the mouse again.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not get_tree().paused \
			and not $CollisionManager.wrecked and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_set_mouse_captured(true)


func _exit_tree() -> void:
	_set_mouse_captured(false)


func _apply_settings() -> void:
	Settings.configure_sun(sun)


func _hint_passengers() -> void:
	if passengers.trip_state == 0 and GameManager.trips_completed == 0:
		GameManager.post_message(HINT_PASSENGER, GameManager.MSG_INFO)


func _on_first_trip(_destination: String, _fare: int) -> void:
	get_tree().create_timer(3.0, false).timeout.connect(
		GameManager.post_message.bind(HINT_ARROW, GameManager.MSG_INFO))


func _process(delta: float) -> void:
	_area_timer -= delta
	if _area_timer <= 0.0:
		_area_timer = 0.5
		_update_area()


func _update_area() -> void:
	var p := player.global_position
	hud.set_area_name(CityLayout.area_name_at(p.x, p.z))


# Crash effects, damage and the accident counter: see collision_manager.gd.


func _on_player_reset() -> void:
	GameManager.post_message("রিকশা আবার রাস্তায়!", GameManager.MSG_INFO)
