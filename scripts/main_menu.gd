## Main menu (মূল মেনু): the city as a backdrop, a rickshaw pedalling in
## place, and the start / how to play / settings / exit buttons.
extends Node3D

@onready var _rickshaw: Node3D = $Rickshaw
@onready var _camera: Camera3D = $Camera
@onready var _sun: DirectionalLight3D = $Sun
@onready var _buttons: Control = $UI/Root/Buttons
@onready var _title: Control = $UI/Root/TitleBox
@onready var _start: Button = %StartButton
@onready var _help_button: Button = %HelpButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit: Button = %QuitButton
@onready var _help: Control = %HelpPanel
@onready var _back: Button = %BackButton
@onready var _settings: Control = %SettingsMenu
@onready var _records: Label = %Records
@onready var _loading: Control = %Loading

var _time := 0.0
var _click: AudioStreamPlayer


func _ready() -> void:
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_click = AudioStreamPlayer.new()
	_click.bus = "UI"
	if ResourceLoader.exists("res://assets/audio/ui_click.wav"):
		_click.stream = load("res://assets/audio/ui_click.wav")
	add_child(_click)
	for b in [_start, _help_button, _settings_button, _quit, _back]:
		b.focus_entered.connect(_play_click)
		b.pressed.connect(_play_click)
	_start.pressed.connect(start_game)
	_help_button.pressed.connect(_show_panel.bind(_help))
	_settings_button.pressed.connect(_show_settings)
	_quit.pressed.connect(get_tree().quit)
	_quit.visible = not Settings.is_web()  # a browser tab is closed, not quit
	_back.pressed.connect(_close_panels)
	_settings.closed.connect(_close_panels)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	_update_records()
	Settings.log_time("main menu ready")
	_start.grab_focus()
	# The help text wraps to the screen: wide sideways, narrow on an upright phone.
	var help_text: Label = _help.get_node("VBox/Text")
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fit_help(Settings.portrait)
	Settings.orientation_changed.connect(_fit_help)
	# `--autostart` (e.g. in a test page) skips the menu and starts riding.
	if OS.get_cmdline_args().has("--autostart") or OS.get_cmdline_user_args().has("--autostart"):
		start_game.call_deferred()


func _apply_settings() -> void:
	Settings.configure_sun(_sun)


func _update_records() -> void:
	if Settings.best_earnings <= 0 and Settings.total_trips <= 0:
		_records.text = "প্রথম যাত্রার জন্য প্রস্তুত? শুভকামনা!"
	else:
		_records.text = "সর্বোচ্চ আয়: %s   •   সবচেয়ে বেশি যাত্রা: %s   •   মোট যাত্রা: %s" % [
			GameManager.format_taka(Settings.best_earnings),
			GameManager.to_bangla_number(Settings.best_trips),
			GameManager.to_bangla_number(Settings.total_trips)]


func _process(delta: float) -> void:
	_time += delta
	# The rickshaw pedals in place; the camera slowly circles it.
	_rickshaw.update_motion(3.0, sin(_time * 0.7) * 0.15, true, delta)
	var angle := _time * 0.12 + 0.6
	var target := _rickshaw.global_position + Vector3(0, 1.0, 0)
	_camera.global_position = target + Vector3(sin(angle) * 6.5, 1.6 + sin(_time * 0.3) * 0.3, cos(angle) * 6.5)
	_camera.look_at(target)


func _play_click() -> void:
	if _click.stream:
		_click.play()


func _show_panel(panel: Control) -> void:
	_buttons.hide()
	_title.hide()
	panel.show()
	_back.grab_focus()


func _show_settings() -> void:
	_buttons.hide()
	_title.hide()
	_settings.open()


func _close_panels() -> void:
	_help.hide()
	_settings.hide()
	_buttons.show()
	_title.show()
	_start.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _help.visible:
		_close_panels()
		get_viewport().set_input_as_handled()


## Shows the loading screen for a frame, then builds the city and starts.
func start_game() -> void:
	_buttons.hide()
	_loading.show()
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.start_game()


func _fit_help(portrait: bool) -> void:
	_help.custom_minimum_size.x = 680.0 if portrait else 1100.0
